import QtQuick

QtObject {
    id: radioAPI

    required property var stationsModel
    required property var radioPlayer
    required property var mainWindow // Point to the global window

    signal loadingStarted()
    signal loadingFinished()

    function fetchData(url, callback) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) callback(xhr.responseText)
                else callback(null)
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function buildURL() {
        var url = "https://de1.api.radio-browser.info/json/stations/search?hidebroken=true&limit=100&order=votes&reverse=true"
        if (mainWindow.radioSearchQuery) url += "&name=" + encodeURIComponent(mainWindow.radioSearchQuery)
        return url
    }

    function fetchStations() {
        loadingStarted()
        stationsModel.clear()
        fetchData(buildURL(), function(response) {
            loadingFinished()
            if (!response) return
            var data = JSON.parse(response)
            for (var i = 0; i < data.length; i++) {
                stationsModel.append({
                    stationuuid: data[i].stationuuid,
                    name:        data[i].name,
                    url:         data[i].url_resolved || data[i].url,
                    favicon:     data[i].favicon || "",
                    codec:       data[i].codec,
                    tags:        data[i].tags,
                    country:     data[i].country,
                    votes:       data[i].votes
                })
            }
        })
    }

    function playStation(station) {
        mainWindow.currentRadioStation = station
        mainWindow.currentMediaTitle = station.name
        mainWindow.currentMediaSubtitle = (station.country || "") + " • " + (station.codec || "")
        mainWindow.currentMediaFavicon = station.favicon || ""
        mainWindow.currentMediaType = 1

        radioPlayer.stop()
        radioPlayer.source = station.url
        fetchData("https://de1.api.radio-browser.info/json/url/" + station.stationuuid, function() {})
        radioPlayer.play()
    }

    function togglePlayPause() {
        radioPlayer.playbackState === 1 // PlayingState
            ? radioPlayer.pause()
            : radioPlayer.play()
    }

    function playNext() {
        if (!mainWindow.currentRadioStation || stationsModel.count === 0) return
        var currentIndex = -1
        for (var i = 0; i < stationsModel.count; i++) {
            if (stationsModel.get(i).stationuuid === mainWindow.currentRadioStation.stationuuid) {
                currentIndex = i; break;
            }
        }
        var nextIndex = currentIndex + 1
        if (nextIndex >= stationsModel.count) nextIndex = 0
        playStation(stationsModel.get(nextIndex))
    }

    function playPrevious() {
        if (!mainWindow.currentRadioStation || stationsModel.count === 0) return
        var currentIndex = -1
        for (var i = 0; i < stationsModel.count; i++) {
            if (stationsModel.get(i).stationuuid === mainWindow.currentRadioStation.stationuuid) {
                currentIndex = i; break;
            }
        }
        var prevIndex = currentIndex - 1
        if (prevIndex < 0) prevIndex = stationsModel.count - 1
        playStation(stationsModel.get(prevIndex))
    }
}