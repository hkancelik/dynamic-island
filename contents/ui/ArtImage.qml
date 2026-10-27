import QtQuick
import QtQuick.Effects

// Yuvarlatılmış albüm kapağı; görsel yoksa nota ikonlu yer tutucu gösterir.
Item {
    id: art

    property url source
    property real radius: 10

    Rectangle {
        anchors.fill: parent
        radius: art.radius
        color: "#2c2c2e"

        Ico {
            anchors.centerIn: parent
            source: "audio-x-generic"
            size: Math.round(art.width * 0.5)
            tint: "#8e8e93"
        }
    }

    Image {
        id: img
        anchors.fill: parent
        source: art.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: 192
        sourceSize.height: 192
        visible: false
    }

    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            radius: art.radius
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: img
        maskEnabled: true
        maskSource: mask
        opacity: img.status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
}
