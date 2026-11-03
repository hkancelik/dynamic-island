import QtQuick

// Yuvarlak ikon düğmesi (medya kontrolleri vb.)
Rectangle {
    id: b

    property string icon
    property int iconSize: 18
    property bool filled: false
    property color tint: filled ? "#000000" : "#ffffff"
    property color fillColor: "#ffffff"
    property bool enabledBtn: true
    signal clicked

    width: 36
    height: 36
    radius: width / 2
    color: filled ? fillColor : (ma.pressed ? Qt.rgba(1, 1, 1, 0.2) : ma.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent")
    opacity: enabledBtn ? 1 : 0.35
    scale: ma.pressed ? 0.92 : 1

    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 120 } }

    GlassBack {   // hover/basınca cam; yarı saydam dolgulu (filled) düğmelerde hep cam
        shown: b.filled ? b.fillColor.a < 0.5 : (ma.containsMouse || ma.pressed)
        hot: ma.containsMouse
        down: ma.pressed
    }

    Ico {
        anchors.centerIn: parent
        source: b.icon
        size: b.iconSize
        tint: b.tint
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: b.enabledBtn
        onClicked: b.clicked()
    }
}
