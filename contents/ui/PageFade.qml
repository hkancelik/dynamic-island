import QtQuick

// Sekme sayfası: seçilince geldiği yönden hafifçe kayarak belirir, ayrılırken karşı yöne kayıp solar.
// Gelen sayfa, çıkan sayfanın solmasına fırsat vermek için kısa bir gecikmeyle başlar.
Item {
    id: w

    property int index
    property int current
    default property alias content: holder.data

    readonly property bool active: current === index
    readonly property real slide: 18

    opacity: active ? 1 : 0
    visible: opacity > 0
    property real shift: active ? 0 : (current > index ? -slide : slide)

    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: w.active ? 70 : 0 }
            NumberAnimation { duration: w.active ? 260 : 110; easing.type: Easing.OutCubic }
        }
    }
    Behavior on shift {
        SequentialAnimation {
            PauseAnimation { duration: w.active ? 70 : 0 }
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }
    }
    transform: Translate { x: w.shift }

    Item {
        id: holder
        anchors.fill: parent
    }
}
