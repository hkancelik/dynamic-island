import QtQuick

// Müzik çubukları: beyaz, duraklayınca soluk. Saniyede 10 adım: sürekli
// animasyon pencereyi saniyede 60 kez çizdirir (~%13 işlemci), adımlı hali çok daha hafif.
Row {
    id: bars
    property bool playing: false
    property bool live: true
    // Gerçek spektrum (24 bant, 0..100); boşsa taklit animasyon
    property var levels: []
    readonly property bool real: levels && levels.length >= 20
    // dört çubuk: bas, alt orta, orta, tiz
    readonly property var groups: [[1, 5], [6, 11], [12, 17], [18, 23]]
    function level(i) {
        var g = groups[i], m = 0
        for (var k = g[0]; k <= g[1]; k++) m = Math.max(m, levels[k] || 0)
        return m / 100
    }
    property real t: 0
    spacing: 2
    opacity: bars.playing ? 1 : 0.43
    Timer {
        interval: 100
        repeat: true
        running: bars.playing && bars.live && !bars.real
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
            height: !bars.playing || !bars.live ? 4
                  : bars.real ? Math.round(4 + 10 * bars.level(index))
                  : Math.round(4 + 8 * Math.abs(Math.sin(bars.t * speed[index] + index * 1.3)))
            Behavior on height { enabled: bars.real; NumberAnimation { duration: 60 } }
            color: "white"
        }
    }
}
