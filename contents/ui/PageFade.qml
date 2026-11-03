import QtQuick
import QtQuick.Effects

// Sekme sayfası geçişi ("sıvı cam"): yeni sayfa sekmenin geldiği yönden yay (spring) ile kayar,
// hafif bir bulanıklıktan netleşir ve çok az büyüyerek yerine oturur; çıkan sayfa karşı yöne
// bulanıklaşarak solar. Yön, sekmelerin ekrandaki sırasına göre (sh.tabOrder); Ayarlar en sonda.
// Bulanıklık katmanı yalnızca geçiş sürerken açıktır, durgunken hiç maliyeti yok.
Item {
    id: w

    property int index
    property int current
    property var order: []
    default property alias content: holder.data

    readonly property bool active: current === index
    readonly property real slide: 26

    function pos(i) { var p = order.indexOf(i); return p >= 0 ? p : 100 + i }

    // 0 = yerinde ve net, 1 = tamamen dışarıda
    property real away: active ? 0 : 1
    property real dir: 1          // +1: sağdan gelir / sağa gider
    onCurrentChanged: dir = pos(current) > pos(index) ? -1 : 1

    Behavior on away {
        NumberAnimation {
            duration: w.active ? 380 : 180
            easing.type: w.active ? Easing.OutQuint : Easing.InCubic
        }
    }

    opacity: 1 - away
    visible: away < 0.999
    scale: 1 - 0.018 * away
    transform: Translate { x: (w.active ? -w.dir : w.dir) * w.slide * w.away }

    layer.enabled: away > 0.004
    layer.effect: MultiEffect {
        blurEnabled: true
        blur: Math.min(1, w.away * 1.3)
        blurMax: 24
    }

    Item {
        id: holder
        anchors.fill: parent
    }
}
