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

**Expect an answer within ~4 seconds.** The prompt approves itself if nobody
touches it (see Auto-accept below), so in practice a verdict appears quickly and
`expires_at` rarely decides anything. A producer must still handle the offer
going unanswered — the prompt only counts down while it is actually on screen,
so an offer arriving during the boot splash waits for it to finish.

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

**The prompt approves itself after 4 seconds if nobody touches it.** Deny is the
deliberate act; letting it ride is consent. The card's top stripe drains away
over the window so the decision is visibly counting down rather than silent, and
the usual confirmation beat ("Update approved") still plays afterwards.

Set `IVI_OTA_AUTOACCEPT_MS=0` to require an explicit answer, or any other value
in milliseconds to change the window.

Worth naming plainly: at four seconds this is a notification with a veto, not a
gate. A driver who is not already looking at the screen will not stop it. That
is consistent with the rest of the handshake — a stale `ui-alive` also means
approve — so the vehicle's answer to "nobody is paying attention" is uniformly
"go ahead" rather than "block forever".

### What this buys the ESP32 path

A 4 s decision window fits inside the ESP32's 5 s wait, which the two-attempt
dance described under Timing exists to work around. If the coordinator writes
the offer the instant a `0x310` REQUEST verifies and **polls `verdicts/` at
~100 ms**, an answer lands by ~4.1 s, leaving most of a second to build the
SecOC frame and put it on the bus. That is tight but real, and it would collapse
the ESP32 flow back to a single attempt with no firmware change.

Do not use the 1-second poll from the shell sketch below for that path — it is
fine for the head unit's own update, where nothing is waiting on a timeout, and
too coarse here.

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

| Target | Window | Source |
|---|---|---|
| ivi | unbounded | the agent is a shell script; it waits as long as we tell it |
| cluster | **60 s** | `OTA_APPROVE_TIMEOUT_S`, `Cluster/qnx-host/can/mcp2515_can_udp.c` |
| esp32 / stm32 | **5 s** | `k_msgq_get(..., K_MSEC(5000))`, `ECU/ESP32/src/logs/can.c` |

Sixty seconds is enough for a person. Five is not — and it is not close, because
approving also has to bring the vehicle to a halt before anything installs.

So for the ESP32 path the in-line CAN request/response **cannot** carry the
human decision. The coordinator must answer that frame within 5 s on its own
(deny, failing closed, which the ESP32 already handles), raise the offer here,
and arm an approval for the *next* attempt once a human has said yes and the
vehicle has stopped. That second attempt is either a re-trigger from the
dashboard, or a retry loop added to `ota_approval_gate()` in the ESP32 firmware.

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
