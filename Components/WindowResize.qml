import QtQuick
import QtQuick.Window

Item {
    id: windowResize
    anchors.fill: parent

    required property var window

    // Top edge
    MouseArea {
        width: parent.width; height: 5
        anchors.top: parent.top
        cursorShape: Qt.SizeVerCursor
        onPressed: windowResize.window.startSystemResize(Qt.TopEdge)
    }
    // Bottom edge
    MouseArea {
        width: parent.width; height: 5
        anchors.bottom: parent.bottom
        cursorShape: Qt.SizeVerCursor
        onPressed: windowResize.window.startSystemResize(Qt.BottomEdge)
    }
    // Left edge
    MouseArea {
        width: 5; height: parent.height
        anchors.left: parent.left
        cursorShape: Qt.SizeHorCursor
        onPressed: windowResize.window.startSystemResize(Qt.LeftEdge)
    }
    // Right edge
    MouseArea {
        width: 5; height: parent.height
        anchors.right: parent.right
        cursorShape: Qt.SizeHorCursor
        onPressed: windowResize.window.startSystemResize(Qt.RightEdge)
    }
    // Top-left corner
    MouseArea {
        width: 10; height: 10
        anchors { top: parent.top; left: parent.left }
        cursorShape: Qt.SizeFDiagCursor
        onPressed: windowResize.window.startSystemResize(Qt.TopEdge | Qt.LeftEdge)
    }
    // Top-right corner
    MouseArea {
        width: 10; height: 10
        anchors { top: parent.top; right: parent.right }
        cursorShape: Qt.SizeBDiagCursor
        onPressed: windowResize.window.startSystemResize(Qt.TopEdge | Qt.RightEdge)
    }
    // Bottom-left corner
    MouseArea {
        width: 10; height: 10
        anchors { bottom: parent.bottom; left: parent.left }
        cursorShape: Qt.SizeBDiagCursor
        onPressed: windowResize.window.startSystemResize(Qt.BottomEdge | Qt.LeftEdge)
    }
    // Bottom-right corner
    MouseArea {
        width: 10; height: 10
        anchors { bottom: parent.bottom; right: parent.right }
        cursorShape: Qt.SizeFDiagCursor
        onPressed: windowResize.window.startSystemResize(Qt.BottomEdge | Qt.RightEdge)
    }
}