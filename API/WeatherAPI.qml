import QtQuick

QtObject {
    id: weatherAPI

    signal weatherReceived(var current, var daily, var hourly, var location, var population)
    signal cityNotFound(string city)
    signal networkError(string message)

    function fetch(city) {
        console.log("Getting weather info for: " + city)
        openMeteoWeatherAPI(city)
        
    }
    
    function openMeteoWeatherAPI(city){
        // Get latitude and longitude for the city from geocoding-api
        fetchData("https://geocoding-api.open-meteo.com/v1/search?name=" + city + "&count=1&language=en&format=json", function(response) {
            if (response) {
                console.log("geocoding API response received")

                // Convert JSON text to JavaScript object
                var data = JSON.parse(response)
                if(data.results && data.results.length > 0) {
                    var location = data.results[0]
                    console.log("City found: " + location.name + ", " + location.country)
                    console.log("Latitude: " + location.latitude + ", Longitude: " + location.longitude)
                    console.log("Population: " + location.population)

                    // Now we can use the latitude and longitude to get weather info from the weather API
                    fetchData("https://api.open-meteo.com/v1/forecast?latitude=" + location.latitude + "&longitude=" + location.longitude + "&timezone=auto" + "&daily=uv_index_max,temperature_2m_max,temperature_2m_min&hourly=temperature_2m&current=temperature_2m,wind_speed_10m,wind_direction_10m,surface_pressure,rain,relative_humidity_2m,weather_code,cloud_cover,pressure_msl,apparent_temperature,is_day", function(response) {
                        if (response) {
                            console.log("Weather API response received")
                            var weatherData = JSON.parse(response)
                            console.log("Current temperature: " + weatherData.current.temperature_2m + "°C")
                            // Notify main.qml with the received weather data
                            weatherReceived(weatherData.current, weatherData.daily, weatherData.hourly, location, location.population)
                        }
                        else {
                            console.log("Error: Cannot fetch weather data from API")
                            networkError("Cannot fetch weather data from API")
                        }
                    })
                }
                else {
                    console.log("No results found for city: " + city)
                    cityNotFound(city)
                }
                
            } 
            else {
                console.log("No response received from API")
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