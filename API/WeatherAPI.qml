import QtQuick

QtObject {
    id: weatherAPI

    signal weatherReceived(var current, var daily, var hourly, var location, var population)
    signal cityNotFound(string city)
    signal networkError(string message)

    /*
     * Retry until a fetch succeeds.
     *
     * The UI comes up well before NetworkManager has an address, so the very
     * first request on a cold boot normally fails. Without this the caller's
     * one-shot fetch() is the only attempt ever made and the page stays on its
     * placeholder for the rest of the session, even once WiFi is up.
     *
     * Backoff rather than a fixed tick: if the car is simply out of coverage,
     * a retry every few seconds for hours is pointless radio traffic.
     */
    readonly property int baseRetryMs: 5000
    readonly property int maxRetryMs:  120000

    property string pendingCity: ""
    property int    retryDelay:  baseRetryMs

    // interval is set in scheduleRetry() rather than bound to retryDelay:
    // changing a running Timer's interval restarts it, so a binding would
    // stretch the wait that is already in flight every time it backs off.
    property Timer retryTimer: Timer {
        repeat: false
        onTriggered: weatherAPI.openMeteoWeatherAPI(weatherAPI.pendingCity)
    }

    function fetch(city) {
        console.log("Getting weather info for: " + city)
        pendingCity = city
        retryDelay  = baseRetryMs
        retryTimer.stop()
        openMeteoWeatherAPI(city)
    }

    // Bring the next attempt forward — for when something external says the
    // network just came up and waiting out the backoff would be silly.
    function retryNow() {
        if (pendingCity === "")
            return
        retryDelay = baseRetryMs
        retryTimer.stop()
        openMeteoWeatherAPI(pendingCity)
    }

    function scheduleRetry(reason) {
        if (pendingCity === "")
            return
        console.log("Weather fetch failed (" + reason + "), retrying in "
                    + (retryDelay / 1000) + "s")
        retryTimer.stop()
        retryTimer.interval = retryDelay
        retryTimer.start()
        retryDelay = Math.min(retryDelay * 2, maxRetryMs)
    }

    function openMeteoWeatherAPI(city){
        // Get latitude and longitude for the city from geocoding-api
        fetchData("https://geocoding-api.open-meteo.com/v1/search?name=" + city + "&count=1&language=en&format=json", function(response) {
            if (response) {
                console.log("geocoding API response received")

                // Convert JSON text to JavaScript object. Guarded: a captive
                // portal answers 200 with a login page, which is not JSON.
                var data
                try {
                    data = JSON.parse(response)
                } catch (e) {
                    weatherAPI.networkError("Geocoding reply was not JSON")
                    weatherAPI.scheduleRetry("geocoding reply was not JSON")
                    return
                }

                if(data.results && data.results.length > 0) {
                    var location = data.results[0]
                    console.log("City found: " + location.name + ", " + location.country)
                    console.log("Latitude: " + location.latitude + ", Longitude: " + location.longitude)
                    console.log("Population: " + location.population)

                    // Now we can use the latitude and longitude to get weather info from the weather API
                    fetchData("https://api.open-meteo.com/v1/forecast?latitude=" + location.latitude + "&longitude=" + location.longitude + "&timezone=auto" + "&daily=uv_index_max,temperature_2m_max,temperature_2m_min&hourly=temperature_2m&current=temperature_2m,wind_speed_10m,wind_direction_10m,surface_pressure,rain,relative_humidity_2m,weather_code,cloud_cover,pressure_msl,apparent_temperature,is_day", function(response) {
                        if (response) {
                            console.log("Weather API response received")
                            var weatherData
                            try {
                                weatherData = JSON.parse(response)
                            } catch (e) {
                                weatherAPI.networkError("Weather reply was not JSON")
                                weatherAPI.scheduleRetry("weather reply was not JSON")
                                return
                            }
                            console.log("Current temperature: " + weatherData.current.temperature_2m + "°C")

                            // Got through — stop retrying and reset the backoff
                            // so a later drop starts from the short delay again.
                            weatherAPI.retryTimer.stop()
                            weatherAPI.retryDelay = weatherAPI.baseRetryMs

                            // Notify main.qml with the received weather data
                            weatherReceived(weatherData.current, weatherData.daily, weatherData.hourly, location, location.population)
                        }
                        else {
                            console.log("Error: Cannot fetch weather data from API")
                            networkError("Cannot fetch weather data from API")
                            weatherAPI.scheduleRetry("weather request failed")
                        }
                    })
                }
                else {
                    // The network worked, the city name is simply wrong —
                    // retrying it forever would never produce a different
                    // answer, so this one does not schedule a retry.
                    console.log("No results found for city: " + city)
                    cityNotFound(city)
                }

            }
            else {
                console.log("No response received from API")
                networkError("Cannot reach the geocoding API")
                weatherAPI.scheduleRetry("geocoding request failed")
            }
        })
    }

    function fetchData(url, callback) {
        var xhr = new XMLHttpRequest()

        xhr.onreadystatechange = function(){

            if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
                console.log("HEADERS_RECEIVED - status:", xhr.status)
            }

            if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("DONE - Request finished")
                console.log("Status:", xhr.status)
                console.log("StatusText:", xhr.statusText)
                console.log("Response:", xhr.responseText)

                if (xhr.status === 200) {
                    callback(xhr.responseText)
                }
                else {
                    console.log("Error: Cannot fetch data from API")
                    callback(null)
                }
            }
        }

        // Initialize GET request
        xhr.open("GET", url)
        console.log("Sending GET request to:", url)
        xhr.send()
    }
}