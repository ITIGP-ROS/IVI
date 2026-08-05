import QtQuick
import QtQuick.Controls

Item {
    id: root

    signal goBack()

    // 3D surroundings visualization (ROS2)
    Scene3D {
        id: scene
        anchors.fill: parent
        anchors.topMargin: 42
    }

    WindowBar {
        id: titleBar
        z: 2
        window: mainWindow
        titleName: "Drive View"
        showBackButton: true
        onBackRequested: root.goBack()
        color0: '#0e0e14'
        color1: '#1a1a2e'
        color2: '#2e2e4a'

        brightnessValue: mainWindow.appBrightness
        volumeValue: systemVolume.volume
        volumeMax: systemVolume.maxVolume
        volumeMuted: systemVolume.muted

        onBrightnessChanged: (value) => mainWindow.appBrightness = value
        onVolumeChanged: (value) => systemVolume.volume = value
        onVolumeMuteToggled: systemVolume.toggleMute()

        onWifiRequested:      mainWindow.openSettingsSection("wifi")
        onBluetoothRequested: mainWindow.openSettingsSection("bluetooth")
    }
}
