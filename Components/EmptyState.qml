import QtQuick

/*
 * "There is nothing here" — a drawn glyph, a headline and one line of help.
 *
 * Every such case across the media pages used to be a bare sentence floating in
 * the middle of an empty panel, which reads as a fault rather than as a state,
 * and never said what to do about it. The hint line is the point of the
 * component; the glyph is what makes it look deliberate.
 */
Column {
    id: empty

    property string kind: "search"          // MediaGlyph kind
    property color  tint: "#8899bb"
    property alias  title: titleText.text
    property alias  hint: hintText.text

    property real glyphSize: 72
    property real titleSize: 19
    property real hintSize: 11

    spacing: glyphSize * 0.17

    MediaGlyph {
        anchors.horizontalCenter: parent.horizontalCenter
        width: empty.glyphSize
        height: width
        kind: empty.kind
        tint: empty.tint
        accent: empty.tint
        // Lighter than the default: at this size the icon is decoration behind
        // the message, not the message.
        weight: 0.85
    }

    Text {
        id: titleText
        anchors.horizontalCenter: parent.horizontalCenter
        color: "#ffffff"
        font { pixelSize: empty.titleSize; family: "Arial"; bold: true }
    }

    Text {
        id: hintText
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
        visible: text !== ""
        color: "#8899bb"
        font { pixelSize: empty.hintSize; family: "Arial" }
    }
}
