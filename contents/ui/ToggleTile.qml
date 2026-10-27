import QtQuick

// Açık/kapalı durumlu hızlı ayar karosu. Sol tık: eylem, sağ tık: ayrıntı/ayarlar.
Rectangle {
    id: t

    property string icon
    property string title
    property string subtitle
    property bool active: false
    property color accent: "#6ea8fe"
    signal clicked
    signal rightClicked

    implicitHeight: 62
    radius: 14
    color: ma.containsMouse ? "#2c2c2e" : "#1c1c1e"
    scale: ma.pressed ? 0.95 : 1

    Behavior on color { ColorAnimation { duration: 160 } }
    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

    // Açık hal yalnızca ikon dairesinde: vurgu dolgusu + beyaz ikon
    Rectangle {
        id: dot
        x: 10; y: 9
        width: 26; height: 26; radius: 13
        color: t.active ? t.accent : "#2c2c2e"
        Behavior on color { ColorAnimation { duration: 160 } }
        Ico {
            anchors.centerIn: parent
            source: t.icon
            size: 14
            tint: t.active ? "white" : "#aeaeb2"
        }
    }
    Text {
        renderType: Text.CurveRendering
        font.family: "Inter"
        x: 11; y: parent.height - 32
        width: parent.width - 18
        text: t.title
        color: "white"
        font.pixelSize: 12
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }
    Text {
        renderType: Text.CurveRendering
        font.family: "Inter"
        x: 11; y: parent.height - 18
        width: parent.width - 18
        text: t.subtitle
        color: Qt.rgba(1, 1, 1, 0.55)
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => m.button === Qt.RightButton ? t.rightClicked() : t.clicked()
    }
}
