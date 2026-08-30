import QtQuick
import QtQuick.Controls

Item {
    id: root

    signal goBack()

    // Replay the opening camera zoom in. Main.qml calls this on the card tap;
    // the scene cannot trigger it itself because it is built and warmed long
    // before the page is actually opened.
    function playIntro() { scene.playIntro() }

    // 3D surroundings visualization (ROS2)
    Scene3D {
        id: scene
        anchors.fill: parent

        // Fills the page edge to edge, including behind the floating window
        // bar (which has its own inset) — a scene anchored below it left a
        // grey band across the top instead. Only the HUD panels are held
        // clear, via topInset.
        topInset: titleBar.height + titleBar.anchors.topMargin
    }

    WindowBar {
        id: titleBar
        z: 2
        window: mainWindow
        // No title and a see-through middle: this page is the road, and a
        // labelled opaque strip across the top of it hides the part of the
        // scene the driver most wants to see. The home button and the status
        // icons stay — they keep their tinted backing from the gradient ends.
        titleName: ""
        transparentCenter: true
        showBackButton: true
        onBackRequested: {
            scene.resetCurrentView()
            scene.closeSettings()
            root.goBack()
        }
        // Same gradient and accent as the rest of the app. The bar was still
        // amber-on-charcoal here, which put the one warm colour on the page in
        // the corner of a scene that is otherwise entirely cool.
        color0: Theme.gradientTop
        color1: Theme.gradientMid
        color2: Theme.gradientBot
        accent: Theme.accentBlue
        surface: Theme.surface

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
