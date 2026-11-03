import QtQuick

// Müzik çubukları: beyaz, duraklayınca soluk. Saniyede 10 adım: sürekli
// animasyon pencereyi saniyede 60 kez çizdirir (~%13 işlemci), adımlı hali çok daha hafif.
Row {
    id: bars
    property bool playing: false
    property bool live: true
    property real t: 0
    spacing: 2
    opacity: bars.playing ? 1 : 0.43
    Timer {
        interval: 100
        repeat: true
        running: bars.playing && bars.live
        onTriggered: bars.t += 0.1
    }
    Repeater {
        model: 4
        Rectangle {
            required property int index
            readonly property var speed: [7.1, 9.3, 6.2, 8.4]
            width: 3
            anchors.verticalCenter: parent.verticalCenter
            radius: 1.5
            height: bars.playing && bars.live
                    ? Math.round(4 + 8 * Math.abs(Math.sin(bars.t * speed[index] + index * 1.3)))
                    : 4
            color: "white"
        }
    }
}
