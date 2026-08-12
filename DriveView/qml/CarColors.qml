pragma Singleton
import QtQuick
import QtCore

Item {
    property color ego: "#0066cc"

    Settings {
        id: carColorsSettings
        category: "DriveView"

        property real carHue: 0.583
        property real carSat: 1.0
        property real carVal: 1.0
    }

    readonly property real carHue: carColorsSettings.carHue
    readonly property real carSat: carColorsSettings.carSat
    readonly property real carVal: carColorsSettings.carVal

    Component.onCompleted: ego = hsvToRgb(carHue, carSat, carVal)

    function setColor(hue, sat, val) {
        carColorsSettings.carHue = hue
        carColorsSettings.carSat = sat
        carColorsSettings.carVal = val
        ego = hsvToRgb(hue, sat, val)
    }

    function hsvToRgb(h, s, v) {
        var r, g, b, i=Math.floor(h*6), f=h*6-i
        var p=v*(1-s), q=v*(1-f*s), t=v*(1-(1-f)*s)
        switch (i%6) {
        case 0: r=v; g=t; b=p; break;  case 1: r=q; g=v; b=p; break
                                       case 2: r=p; g=v; b=t; break;  case 3: r=p; g=q; b=v; break
                                                                      case 4: r=t; g=p; b=v; break;  case 5: r=v; g=p; b=q; break
        }
        return Qt.rgba(r, g, b, 1.0)
    }
}