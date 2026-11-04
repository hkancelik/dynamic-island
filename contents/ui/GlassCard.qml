import QtQuick

// Panel kartı. Sıvı camda ince cam (yalnızca kenar ışığı ve hafif ton: cam üstüne cam olmaz),
// diğer malzemelerde yarı saydam beyaz dolgu. `sh` ana pencere (glassLayer, glassTick, glassFrost).
Rectangle {
    id: card

    property var sh
    property real fill: 0.11                      // düz dolgu opaklığı
    property bool hot: false                      // üzerine gelinince / basılınca camın içi hafifçe aydınlanır
    readonly property bool glassy: sh && sh.glassLayer ? true : false

    radius: 14
    color: glassy ? "transparent" : Qt.rgba(1, 1, 1, fill)

    GlassSurface {
        anchors.fill: parent
        z: -1
        visible: card.glassy
        glassLayer: card.glassy ? card.sh.glassLayer : null
        tick: card.glassy ? card.sh.glassTick : 0
        thin: true
        radius: card.radius
        frostAmount: card.glassy ? card.sh.glassFrost : 0
        tintAmount: 0.10
        bezelPx: 10
        glow: card.hot ? 0.35 : 0
        Behavior on glow { NumberAnimation { duration: 160 } }
    }
}
