import QtQuick
import QtQuick.Controls
import QtLocation
import QtPositioning

Item {
    id: root
    anchors.fill: parent


    MapView {

        id: view
        anchors.fill: parent

        // -------- Plugin configuration --------
        map.plugin: Plugin {
            name: "osm"

            PluginParameter { name: "osm.useragent"; value: "ITI GP" }

            // PluginParameter {
            //            name: "osm.mapping.custom.host"
            //     value: "https://tile.openstreetmap.org/"
            // }

            PluginParameter {
                name: "osm.mapping.copyright"
                value: "© OpenStreetMap contributors"
            }

            PluginParameter {
                name: "osm.mapping.providersrepository.disabled"
                value: true
            }

            // Optional: public OSRM demo (uncomment if you need routing)
            // PluginParameter { name: "osm.routing.host"; value: "https://router.project-osrm.org/" }

            // Optional: Nominatim (uncomment if you need geocoding)
            // PluginParameter { name: "osm.geocoding.host"; value: "https://nominatim.openstreetmap.org" }
        }

        // -------- Activate the Custom Map type --------
        // Component.onCompleted: {
        //     for (let i = 0; i < view.map.supportedMapTypes.length; ++i) {
        //         let mt = view.map.supportedMapTypes[i];
        //         if (mt.name === "Custom Map") {
        //             view.map.activeMapType = mt;
        //             console.log("Using custom map type:", mt.name);
        //             return;
        //         }
        //     }
        //     console.warn("Custom Map type not found");
        // }

        // -------- Map settings --------
        map.center: QtPositioning.coordinate(49.011086, 8.423322) // London
        map.zoomLevel: 20
        // map.tilt: 30
        // map.bearing: 45

        // -------- Marker (static) --------
        // MapView wraps the Map, so reparent the item to view.map
        MapQuickItem {
            parent: view.map
            coordinate: view.map.center
            anchorPoint: Qt.point(marker.width / 2, marker.height)

            sourceItem: Rectangle {
                id: marker
                width: 20
                height: 20
                color: "red"
                radius: 10
                border.color: "white"
                border.width: 2

                Rectangle {
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    color: "black"
                    opacity: 0.3
                    radius: 3
                    y: 12
                }
            }


        }

        MapQuickItem {
            id: vehicleMarker
            parent: view.map

            coordinate: QtPositioning.coordinate(carInfo.currLatitude, carInfo.currLongitude)


            anchorPoint: Qt.point(-22, 0)

            sourceItem: Image {
                id: arrowImage
                width: 30
                height: 30
                source: "qrc:/img/maparrow.png"
                // fillMode: Image.PreserveAspectFit

                // Explicitly rotate around the item center
                transformOrigin: Item.Center

                // Calibration parameters:
                //   imuOffsetDeg : add this if your IMU forward axis is not X (e.g. 90 if forward is Y)
                //   headingSign  : -1 for standard math/CCW yaw, +1 if your IMU already gives clockwise heading
                rotation: quaternionToHeading(
                              carInfo.currImuX,
                              carInfo.currImuY,
                              carInfo.currImuZ,
                              carInfo.currImuW,
                              90,      // <-- change this offset if arrow points 90° off
                              -1      // <-- change to +1 if arrow turns the wrong way
                          )

                // Behavior on rotation {
                //     RotationAnimation {
                //         duration: 150
                //         direction: RotationAnimation.Shortest
                //     }
                // }
            }
        }




        // -------- Custom TapHandler (double-tap zoom, right-click menu) --------
        TapHandler {
            id: tapHandler
            property var lastCoordinate
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            onPressedChanged: {
                if (pressed) {
                    lastCoordinate = view.map.toCoordinate(tapHandler.point.position)
                }
            }


            onDoubleTapped: (eventPoint, button) => {
                // Zoom towards the cursor
                var preZoomPoint = view.map.toCoordinate(eventPoint.position);

                if (button === Qt.LeftButton) {
                    view.map.zoomLevel = Math.floor(view.map.zoomLevel + 1);
                } else if (button === Qt.RightButton) {
                    view.map.zoomLevel = Math.floor(view.map.zoomLevel - 1);
                }

                var postZoomPoint = view.map.toCoordinate(eventPoint.position);
                var dx = postZoomPoint.latitude - preZoomPoint.latitude;
                var dy = postZoomPoint.longitude - preZoomPoint.longitude;

                view.map.center = QtPositioning.coordinate(
                    view.map.center.latitude - dx,
                    view.map.center.longitude - dy
                );
            }
        }
    }

    // -------- Zoom controls overlay --------
    Column {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 20
        spacing: 10
        z: 10

        Button {
            text: "+"
            onClicked: view.map.zoomLevel = Math.min(view.map.zoomLevel + 1, view.map.maximumZoomLevel)
        }

        Button {
            text: "-"
            onClicked: view.map.zoomLevel = Math.max(view.map.zoomLevel - 1, view.map.minimumZoomLevel)
        }
    }

    // -------- Coordinate display overlay --------
    Label {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 20
        text: "Lat: " + view.map.center.latitude.toFixed(4) + "  Lon: " + view.map.center.longitude.toFixed(4)
        color: "white"
        background: Rectangle { color: "black"; opacity: 0.6; radius: 4 }
        padding: 8
        z: 10
    }

    Label {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 20
        color: "lime"
        font.pixelSize: 14
        text: "X:" + carInfo.currImuX.toFixed(2) +
              " Y:" + carInfo.currImuY.toFixed(2) +
              " Z:" + carInfo.currImuZ.toFixed(2) +
              " W:" + carInfo.currImuW.toFixed(2) +
              "\nHeading: " + quaternionToHeading(carInfo.currImuX, carInfo.currImuY, carInfo.currImuZ, carInfo.currImuW, 0, -1).toFixed(1) + "°"
        z: 100
    }

    property bool followVehicle: true
    Connections {
        target: carInfo
        function onCurrLatitudeChanged()  { if (followVehicle) view.map.center = vehicleMarker.coordinate }
        function onCurrLongitudeChanged() { if (followVehicle) view.map.center = vehicleMarker.coordinate }
    }


    // Helper function to convert quaternion to heading in degrees (0-360)

    function quaternionToHeading(x, y, z, w, offsetDeg, sign) {
        // Standard Z-up yaw extraction (radians, CCW from X-axis in math convention)
        var t3 = 2.0 * (w * z + x * y);
        var t4 = 1.0 - 2.0 * (y * y + z * z);
        var yaw = Math.atan2(t3, t4);

        var degrees = yaw * 180.0 / Math.PI;

        // sign:  -1 converts CCW math yaw -> QML clockwise rotation
        // offsetDeg: shift if your IMU defines forward on Y or Z instead of X
        var heading = (sign * degrees) + offsetDeg;

        // Normalize to 0..360
        while (heading < 0)   heading += 360;
        while (heading >= 360) heading -= 360;
        return heading;
    }
}
