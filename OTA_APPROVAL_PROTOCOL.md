# OTA Approval Protocol

How something on this vehicle asks a human for permission to install firmware,
and how it gets an answer back.

The head unit is the **consumer**: it shows the prompt and writes the verdict.
Anything that wants permission is a **producer**. There are four targets today —
the head unit itself, the instrument cluster, the body-control ESP32, and the
STM32 behind it — and they reach this UI through two producers:

| Producer | Runs as | Speaks for |
|---|---|---|
| `update_coordinator` (ROS 2, Jetson) | root | cluster, esp32, stm32 |
| `ivi_ota_agent.sh` | root | ivi |

Producers never talk to each other and never talk to the UI directly. They drop
a file, they read a file back. That is the entire interface.

---

## Why files

The producers are a POSIX shell script and a Python ROS node running as root.
The consumer is a Qt application running as the unprivileged `weston` user.
Files are the only transport all three speak with no new runtime dependency, and
directory ownership becomes the permission model for free.

---

## Layout

```
/run/ota-approval/
  offers/<id>.json    0755 root:root     producers write, UI reads
  verdicts/<id>       0730 root:weston   UI writes, cannot list
  ui-alive            0664 weston:weston UI touches, producers stat
```

`verdicts/` at **0730** is the point of the layout. `weston` has write and
execute on it but not read: the UI can create a file there, and cannot list the
directory or read anything in it. It can answer a question. It cannot ask one,
and it cannot see anyone else's answer.

Provision with tmpfiles.d — `/run` is a tmpfs and does not survive a reboot:

```
d /run/ota-approval          0755 root   root   -
d /run/ota-approval/offers   0755 root   root   -
d /run/ota-approval/verdicts 0730 root   weston -
f /run/ota-approval/ui-alive 0664 weston weston -
```

For development off-board, point the UI somewhere writable:

```bash
IVI_OTA_APPROVAL_DIR=/tmp/ota-approval ./appIVI
```

---

## The offer

One JSON object per pending request, at `offers/<id>.json`.

```json
{
  "id":            "esp32-1754994000",
  "target":        "esp32",
  "version":       "1.4.2",
  "slot":          "B",
  "size_bytes":    55574528,
  "requested_at":  1754994000,
  "expires_at":    1754994060,
  "auto_accept_ms": 5000,
  "stops_vehicle": true
}
```

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Must equal the filename stem. `[A-Za-z0-9._-]`, ≤128 chars, no leading dot. |
| `target` | yes | `ivi` \| `cluster` \| `esp32` \| `stm32`. Anything else is accepted and logged raw. |
| `version` | no | Version being offered. |
| `slot` | no | A/B slot being written. |
| `size_bytes` | no | Download size. |
| `requested_at` | yes | Unix seconds. Determines queue order — oldest first. |
| `expires_at` | no | Unix seconds. |
| `auto_accept_ms` | no | Ask for a **shorter** decision window. Clamped — see Auto-accept. |
| `stops_vehicle` | no | `true` when approving will trigger the emergency stop. |

**The prompt shows none of this.** It is a title and two buttons, by design — a
driver glancing at it needs to decide, not to audit. Everything except `id`,
`target` and `requested_at` is parsed, logged, and exposed to QML, but not
currently rendered; send it anyway, because it is what makes the journal useful
when an update goes wrong, and it costs a future UI revision nothing to surface.

**Write atomically.** Create `offers/<id>.json.tmp` and `rename(2)` it onto
`offers/<id>.json`. A plain `cat > offers/x.json` is not atomic: inotify fires on
the first write and the UI reads a truncated file. It recovers on the next
one-second poll, so this is cosmetic rather than dangerous — which is exactly why
it goes unnoticed until someone is debugging something else.

**Withdraw by unlinking.** When a producer stops waiting it must `rm` its own
offer file; that is what takes the prompt down.

**Expect an answer within ~5 seconds**, or whatever shorter window you asked for
with `auto_accept_ms`. The prompt approves itself if nobody touches it (see
Auto-accept below), so in practice a verdict appears quickly and `expires_at`
rarely decides anything. A producer must still handle the offer going
unanswered — the prompt only counts down while it is actually on screen, so an
offer arriving during the boot splash waits for it to finish.

---

## The verdict

`verdicts/<id>` containing exactly one word and a newline:

```
approve
```
or
```
deny
```

Written to a temporary name and renamed into place, so a producer polling for it
either does not see it or sees it complete. It will never read a zero-length file
and conclude the answer was empty.

Producers should delete the verdict once consumed, along with their offer.

---

## Auto-accept

**The prompt approves itself after 5 seconds if nobody touches it — the same
5 s for every target.** Deny is the deliberate act; letting it ride is consent. The card's top stripe drains away
over the window so the decision is visibly counting down rather than silent, and
the usual confirmation beat ("Update approved") still plays afterwards.

Set `IVI_OTA_AUTOACCEPT_MS=0` to require an explicit answer, or any other value
in milliseconds to change the window.

Worth naming plainly: at five seconds this is a notification with a veto, not a
gate. A driver who is not already looking at the screen will not stop it. That
is consistent with the rest of the handshake — a stale `ui-alive` also means
approve — so the vehicle's answer to "nobody is paying attention" is uniformly
"go ahead" rather than "block forever".

### Shortening the window per offer

A producer that is itself on a deadline can set `auto_accept_ms` to ask for a
shorter prompt. The rule is deliberately one-way:

```
effective = ours == 0 ? 0 : min(ours, offer)
```

An offer can shorten the window. It cannot lengthen it, and it cannot re-enable
auto-accept on a head unit configured with `IVI_OTA_AUTOACCEPT_MS=0`. A producer
is trusted to know its own deadline; it is not trusted to decide how long a
human on this screen gets.

No producer shortens it today: every target is deliberately held to the same
5 s. It stays in the protocol because the next ECU may be tighter still.

## Liveness, and what it means

The UI rewrites `ui-alive` once a second.

A producer that finds the mtime stale — **10 seconds** is the suggested
threshold — concludes nobody can answer and falls back to its previous automatic
behaviour rather than blocking updates forever on a head unit that has crashed.

State the consequence plainly: **human approval here is advisory, not
enforceable.** Anyone who can stop the head unit application gets auto-approve
back. That is a deliberate availability-over-strictness trade for this vehicle.
Producers should expose it as a knob — `ON_NO_UI=approve|deny` — so it can be
inverted for a demonstration where the gate needs to visibly hold.

---

## Timing, and why the ESP32 is the hard case

The three targets give a human wildly different amounts of time to answer:

| Target | Requester waits | Source |
|---|---|---|
| ivi | unbounded | the agent is a shell script; it waits as long as we tell it |
| cluster | **60 s** | `OTA_APPROVE_TIMEOUT_S`, `Cluster/qnx-host/can/mcp2515_can_udp.c` |
| esp32 / stm32 | **5 s, once** | `k_msgq_get(..., K_MSEC(5000))`, `ECU/ESP32/src/logs/can.c` |

Five seconds is the whole design constraint. The ESP32 asks at the moment it is
about to act — right before it reboots into new firmware, or right before it
drops the STM32 into its bootloader — it asks exactly once, and if no verdict
lands it abandons the update. There is no retry to fall back on.

That fits, but only if every stage is sized against it.

**The prompt itself is 5 s for every target.** A driver should not get a
decision window whose length depends on which ECU happens to be asking. What
varies per target is only how long the coordinator waits before giving up:

| Target | Prompt (`auto_accept_ms`) | Coordinator gives up | Requester's wall | Slack |
|---|---|---|---|---|
| cluster | 5000 ms | 30 s | 60 s | 30 s |
| esp32 / stm32 | 5000 ms | **4400 ms** | 5000 ms | 600 ms |

Note what the ESP32 row says: the coordinator gives up **before** the prompt
finishes. That is not an oversight, it is arithmetic. The prompt is 5000 ms and
the ESP32's wall is 5000 ms, so there is no value that is both above the prompt
and below the wall — the give-up point has to land inside the prompt. 4400 ms
keeps ~600 ms for the SecOC build and the frame itself.

The practical consequence, stated plainly:

- **Cluster** — the prompt decides. Accept, Deny and self-accept at 5 s all
  reach the ECU with 25+ seconds to spare.
- **ESP32 / STM32** — Accept and Deny decide, but only within the first 4.4 s.
  An untouched offer is resolved at 4400 ms by `on_no_verdict` (approve, by
  default) rather than by the popup reaching the end of its own countdown, so
  the last ~600 ms of the draining stripe does not decide anything on this path.
  The outcome for an ignored offer is the same either way — approve — which is
  why this is acceptable rather than a bug.

Measured end to end against the real head unit binary: a self-accepting prompt
resolves in **~5.03 s**, which the cluster honours in full; the ESP32 path
resolves at its 4.4 s deadline instead, as does the worst case on any target —
head unit alive but never answering.

Three things make that hold, and all three are load-bearing:

- **The offer is written the instant the REQUEST verifies**, before anything
  else, and atomically. A half-written offer is skipped and retried on the UI's
  one-second poll, which alone would eat a quarter of the ESP32's budget.
- **`verdicts/` is polled at 100 ms**, not the 1 s used in the shell sketch
  below. That sketch is fine for the head unit's own update, where nothing is
  waiting on a timeout, and far too coarse here.
- **A dead head unit is detected before asking, not by timing out.** If
  `ui-alive` is stale the coordinator approves immediately — measured at ~1 ms,
  identical to the pre-gate behaviour. Burning 4.4 s discovering that nobody is
  home would cost the update on a board that was never going to prompt anyone.

Deny needs no firmware change on either side: both requesters already treat a
`0` verdict as a refusal, and the coordinator's deny is a fully SecOC-signed
frame, not silence. That distinction matters — an *unsigned* or replayed frame
is ignored by both, so a deny that failed authentication would not read as a
deny, it would read as a 5 s stall.

---

## Producer configuration

`update_coordinator` (ROS 2 parameters, `config/update_coordinator.yaml`):

| Parameter | Default | Meaning |
|---|---|---|
| `require_approval` | `true` | `false` restores unconditional auto-approve, for a bench with no head unit |
| `approval_dir` | `/run/ota-approval` | Spool root |
| `ui_alive_max_age_s` | `10.0` | Older than this and the head unit counts as down |
| `on_no_verdict` | `approve` | What a prompt that is never answered resolves to |

`ivi_ota_agent.sh` (environment, `/etc/ivi-ota/agent.conf`):

| Variable | Default | Meaning |
|---|---|---|
| `REQUIRE_APPROVAL` | `1` | |
| `APPROVAL_DIR` | `/run/ota-approval` | |
| `APPROVAL_TIMEOUT_S` | `120` | |
| `ON_NO_UI` | `approve` | Same trade as `on_no_verdict` |
| `UI_ALIVE_MAX_AGE_S` | `10` | |

---

## Producer sketches

Shell:

```sh
ota_ask() {   # ota_ask <id> <target> <version> <stops_vehicle>
    d=/run/ota-approval
    [ "$(( $(date +%s) - $(stat -c %Y "$d/ui-alive" 2>/dev/null || echo 0) ))" -lt 10 ] || {
        echo "no UI — falling back to automatic"; return 0; }

    printf '{"id":"%s","target":"%s","version":"%s","requested_at":%s,"stops_vehicle":%s}\n' \
        "$1" "$2" "$3" "$(date +%s)" "$4" > "$d/offers/$1.json.tmp"
    mv "$d/offers/$1.json.tmp" "$d/offers/$1.json"

    i=0
    while [ $i -lt 300 ]; do
        if [ -f "$d/verdicts/$1" ]; then
            v=$(cat "$d/verdicts/$1")
            rm -f "$d/verdicts/$1" "$d/offers/$1.json"
            [ "$v" = "approve" ] && return 0 || return 1
        fi
        sleep 1; i=$((i+1))
    done
    rm -f "$d/offers/$1.json"      # withdraw: we stopped waiting
    return 1
}
```

Python:

```python
import json, os, time, pathlib

D = pathlib.Path("/run/ota-approval")

def ui_alive(max_age=10):
    try:
        return time.time() - (D / "ui-alive").stat().st_mtime < max_age
    except OSError:
        return False

def ask(offer, timeout=300):
    """True = approved. Falls back to True when no UI can answer."""
    if not ui_alive():
        return True

    oid = offer["id"]
    tmp = D / "offers" / f"{oid}.json.tmp"
    tmp.write_text(json.dumps(offer))
    tmp.rename(D / "offers" / f"{oid}.json")

    verdict = D / "verdicts" / oid
    deadline = time.time() + timeout
    try:
        while time.time() < deadline:
            try:
                answer = verdict.read_text().strip()
            except OSError:
                time.sleep(0.5)
                continue
            verdict.unlink(missing_ok=True)
            return answer == "approve"
        return False
    finally:
        (D / "offers" / f"{oid}.json").unlink(missing_ok=True)
```

---

## Behaviour worth knowing

- **Queue.** Multiple offers are answered oldest-first by `requested_at`. The
  prompt re-arms for the next one as soon as the current is answered, so a
  producer holding a second offer does not need to re-send it.
- **Answered offers stay answered.** The UI remembers ids it has answered, so an
  offer file a producer has not collected yet cannot re-open the prompt.
- **Malformed offers are skipped, not fatal.** Bad JSON, or an `id` inside that
  disagrees with the filename, is ignored with a log line.
- **The prompt cannot be dismissed.** No close button, no tap-outside. A stray
  touch on the scrim must not become a verdict on the CAN bus. The only ways out
  are Accept, Deny, and letting the countdown run.
- **A failed write keeps the prompt up.** If the verdict cannot be written the
  card says so and stays, because the tap genuinely did nothing.
- **Splash gating.** The prompt is withheld until the splash finishes, so an
  offer waiting from before boot cannot be answered blind.

  Note what this means on the ESP32 path specifically. `ui-alive` is touched
  from the moment the app starts, *before* the splash clears — so a request
  arriving during boot looks answerable, gets an offer written, and then goes
  unanswered because the card is still behind the splash. It resolves at the
  coordinator's 4.4 s deadline via `on_no_verdict`, which by default approves. So
  an ESP32 update triggered while the head unit is booting installs without ever
  prompting anyone. That is the fail-open policy working as specified rather
  than a bug, but it is the one window where the gate is silently absent.
