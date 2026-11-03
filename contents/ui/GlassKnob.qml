import QtQuick

// Tutamak: anahtar düğmesi ve kaydırıcı ucu. Sıvı camda küçük bir mercek (altındaki çubuğu büker,
// basınca büyür ve içeriden parlar); diğer malzemelerde düz beyaz daire.
Item {
    id: k

    property var sh
    property bool pressed: false
    readonly property bool glassy: sh && sh.glassLayer ? true : false

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "white"
        visible: !k.glassy
    }
    GlassSurface {
        anchors.fill: parent
        visible: k.glassy
        glassLayer: k.glassy ? k.sh.glassLayer : null
        tick: k.glassy ? k.sh.glassTick + k.x + k.width : 0
        radius: width / 2
        frostAmount: 0.05
        tintColor: "white"
        tintAmount: 0.22
        glow: k.pressed ? 0.8 : 0
        bezelPx: width * 0.4
        thicknessPx: width * 0.5
        lensAmount: k.pressed ? 1.3 : 1
        Behavior on glow { NumberAnimation { duration: 140 } }
    }
}
