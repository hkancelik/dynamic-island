import QtQuick

// Görünüm geçişi: ada büyürken içerik hafif gecikmeyle belirir, kapanırken hızla solar.
Item {
    id: v
    property bool on: false
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    opacity: on ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: v.on ? 90 : 0 }
            NumberAnimation { duration: v.on ? 240 : 80; easing.type: Easing.OutQuart }
        }
    }
    transformOrigin: Item.Top
    scale: on ? 1 : 0.94
    Behavior on scale { NumberAnimation { duration: 340; easing.type: Easing.OutQuart } }
}
