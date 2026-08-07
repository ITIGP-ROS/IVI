pragma Singleton

import QtQuick
import QtCore

/*
 * One shared weather cache for the whole app.
 *
 * The launcher card and the weather page used to own a WeatherAPI each, and
 * the page is pushed from a Component — so it was rebuilt from scratch on
 * every entry and fired a fresh geocode + forecast pair each time. Those two
 * round trips run in sequence, which is roughly two seconds of empty page,
 * every single time, for numbers the upstream service only recomputes every
 * quarter of an hour.
 *
 * Stale-while-revalidate instead. Whatever is cached is readable synchronously
 * so a page can paint on its first frame; a request only leaves the car when
 * the cached reading has aged past ttlMs, and when it lands everything holding
 * that city updates in place. The cache is keyed by city so the page's search
 * box and the launcher's preferred city cannot evict one another, and the most
 * recent entry is written to disk so a cold boot starts populated too.
 */
QtObject {
    id: store

    // Open-Meteo recomputes its "current" block roughly every 15 minutes.
    // Asking more often than this re-downloads numbers that have not changed.
    readonly property int ttlMs: 10 * 60 * 1000

    // Cities held in memory. Uncapped this grows for the life of the process
    // every time someone searches somewhere new.
    readonly property int maxEntries: 8

    // The page shows 24 hours; the API sends a week of them. Only the part
    // that actually gets read is kept, which is what keeps the saved copy small.
    readonly property int hourlyKeep: 24

    /* normalised city -> { current, daily, hourly, location, fetchedAt } */
    property var entries: ({})

    // City of the request currently in flight, "" when idle. Doubles as the
    // guard that stops the page and the launcher asking for the same thing at
    // the same moment on entry.
    property string inFlight: ""

    signal updated(string city)
    signal notFound(string city)
    signal failed(string city, string reason)

    function normalise(city) {
        return (city || "").trim().toLowerCase()
    }

    /* Cached reading for a city, or null. Safe to call before any fetch. */
    function entryFor(city) {
        var e = entries[normalise(city)]
        return e === undefined ? null : e
    }

    function isFresh(city) {
        var e = entryFor(city)
        return e !== null && (Date.now() - e.fetchedAt) < ttlMs
    }

    /*
     * Ask for a city and return immediately; listen to updated() for the rest.
     *
     * A stale entry is deliberately left in place while the refresh runs —
     * that is the whole point, it lets a caller show last known numbers rather
     * than a spinner. Pass force to skip the TTL, which is what the page's
     * refresh button wants.
     */
    function request(city, force) {
        var k = normalise(city)
        if (k === "")
            return
        if (force !== true && isFresh(k))
            return
        if (inFlight === k)
            return
        inFlight = k
        api.fetch(city)
    }

    // Bring a backed-off retry forward — for when something external says the
    // network just came up.
    function retryNow() {
        api.retryNow()
    }

    // ------------------------------------------------------------- internals

    property WeatherAPI api: WeatherAPI {
        onWeatherReceived: function(current, daily, hourly, location) {
            store._remember(store.inFlight, current, daily, hourly, location)
        }
        onCityNotFound: function(city) {
            store.inFlight = ""
            store.notFound(city)
        }
        onNetworkError: function(message) {
            var c = store.inFlight
            store.inFlight = ""
            store.failed(c, message)
        }
    }

    function _remember(key, current, daily, hourly, location) {
        // A reply can outlive the request that asked for it if the city was
        // changed mid-flight; fall back to what the server actually resolved.
        if (key === "")
            key = normalise(location.name)

        var trimmed = {
            "time":           (hourly.time || []).slice(0, hourlyKeep),
            "temperature_2m": (hourly.temperature_2m || []).slice(0, hourlyKeep)
        }

        // The map is rebuilt rather than edited in place: QML does not notice
        // a var property whose contents change, so anything bound to entries
        // would never re-evaluate.
        var next = {}
        for (var k in entries)
            next[k] = entries[k]
        next[key] = {
            "current":   current,
            "daily":     daily,
            "hourly":    trimmed,
            "location":  location,
            "fetchedAt": Date.now()
        }
        entries = _evict(next, key)

        inFlight = ""
        _persist(key)
        updated(key)
    }

    /* Oldest first, never dropping the entry that was just written. */
    function _evict(map, keep) {
        var keys = Object.keys(map)
        while (keys.length > maxEntries) {
            var oldest = null
            for (var i = 0; i < keys.length; i++) {
                var k = keys[i]
                if (k === keep)
                    continue
                if (oldest === null || map[k].fetchedAt < map[oldest].fetchedAt)
                    oldest = k
            }
            if (oldest === null)
                break
            delete map[oldest]
            keys = Object.keys(map)
        }
        return map
    }

    // ------------------------------------------------------------------ disk

    /*
     * Only the newest city is saved. Writing the whole map would grow the
     * settings file for no benefit — on a cold boot the only city anyone is
     * waiting on is the one the launcher is about to ask for anyway.
     */
    property Settings saved: Settings {
        category: "weatherCache"
        property string payload: ""
    }

    function _persist(key) {
        var e = entries[key]
        if (e === undefined)
            return
        try {
            saved.payload = JSON.stringify({ "city": key, "entry": e })
        } catch (err) {
            // Never fatal: an unsaved cache costs one fetch on next boot.
            console.log("Weather cache: could not serialise (" + err + ")")
        }
    }

    Component.onCompleted: {
        if (saved.payload === "")
            return
        try {
            var blob = JSON.parse(saved.payload)
            if (blob && blob.city && blob.entry) {
                var next = {}
                next[blob.city] = blob.entry
                entries = next
            }
        } catch (err) {
            // A partial write or a format change from an older build. Drop it
            // rather than letting every later read trip over the same parse.
            console.log("Weather cache: saved copy unreadable, discarding")
            saved.payload = ""
        }
        // Deliberately no updated() here — the restored reading is by
        // definition stale, and callers read the cache directly at startup.
    }
}
