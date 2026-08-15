import QtQuick
import QtQuick.Controls

/*
 * List scrollbar in the app's accent.
 *
 * Explicitly on or off rather than `AsNeeded`: AsNeeded reads an empty list as
 * size 0 — which is "less than one screenful", so it counts as needed — and
 * draws a full-height bar down an empty panel. Always-on while the list can
 * actually scroll also suits a touch panel, where there is no pointer to
 * reveal it by hovering.
 *
 * Set `view` to the ListView/Flickable it scrolls; without it the bar falls
 * back to always-off rather than guessing.
 */
ScrollBar {
    id: bar

    property var   view: null
    property color accent: "#4a9eff"
    property real  thickness: 9

    width: thickness
    anchors.right: parent ? parent.right : undefined
    minimumSize: 0.1
    policy: (bar.view && bar.view.contentHeight > bar.view.height)
            ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff

    contentItem: Rectangle {
        implicitWidth: bar.thickness
        radius: width / 2
        color: bar.pressed ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.9)
             : bar.hovered ? bar.accent
                           : Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.5)
        opacity: bar.hovered || bar.pressed ? 1.0 : 0.6
        Behavior on color   { ColorAnimation  { duration: 150 } }
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    background: Rectangle {
        implicitWidth: bar.thickness
        color: Qt.rgba(1, 1, 1, 0.05)
        radius: width / 2
        opacity: 0.3
    }
}
