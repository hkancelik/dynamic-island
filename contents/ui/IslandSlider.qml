import QtQuick

// Sürüklenebilir ilerleme/ses çubuğu. value: 0..1
// Sürüklerken yerel değeri gösterir, bırakınca arka uçtan güncelleme gelene
// kadar kısa süre tutar (geri sıçrama olmasın diye).
Item {
    id: s

    property real value: 0
    property color fillColor: "white"
    property color trackColor: "#2c2c2e"
    property int barHeight: 8
    property bool interactive: true
    property bool knob: false
    property bool smooth: true     // değer değişince dolgu kaysın mı      // Isle tarzı: ince çizgi + beyaz yuvarlak tutamak

    signal moved(real v)      // sürüklerken (sınırlandırılmış)
    signal committed(real v)  // bırakınca

    property real _drag: 0
    property bool _hold: false
    property bool _pending: false
    readonly property bool dragging: area.pressed
    readonly property real shown: (dragging || _hold) ? _drag : value

    implicitHeight: 24

    Rectangle {
        id: track
        width: parent.width
        height: s.dragging ? s.barHeight + 4 : s.barHeight
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        color: s.trackColor
        Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Rectangle {
            width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, s.shown)))
            height: parent.height
            radius: height / 2
            color: s.fillColor
            Behavior on color { ColorAnimation { duration: 500 } }
            // Görünmezken ya da sürekli ilerleyen değerlerde (şarkı konumu) animasyon yok:
            // her animasyon pencereyi saniyede 60 kez yeniden çizdirir
            Behavior on width {
                enabled: !s.dragging && s.smooth && s.visible
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
        }
    }

    Rectangle {
        visible: s.knob
        width: s.dragging ? 14 : 12; height: width; radius: width / 2
        color: "white"
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(s.width - width, s.width * Math.max(0, Math.min(1, s.shown)) - width / 2))
        Behavior on width { NumberAnimation { duration: 120 } }
    }

    Timer {
        id: throttle
        interval: 60
        onTriggered: if (s._pending) { s._pending = false; s.moved(s._drag); throttle.start() }
    }
    Timer {
        id: holdTimer
        interval: 500
        onTriggered: s._hold = false
    }

    function _set(x) {
        _drag = Math.max(0, Math.min(1, x / width))
        _pending = true
        if (!throttle.running) {
            _pending = false
            moved(_drag)
            throttle.start()
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: s.interactive
        preventStealing: true
        onPressed: m => { s._hold = false; holdTimer.stop(); s._set(m.x) }
        onPositionChanged: m => { if (pressed) s._set(m.x) }
        onReleased: m => {
            s._drag = Math.max(0, Math.min(1, m.x / width))
            s._hold = true
            holdTimer.restart()
            s.committed(s._drag)
        }
    }
}
