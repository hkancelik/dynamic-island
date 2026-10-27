import QtQuick
import QtQuick.Layouts

// Müzik (Isle düzeni): solda kapak, sağda başlık, ilerleme ve kontroller.
// Sağ üstteki çıkış düğmesi ses seviyesi + çıkış listesine geçer.
Item {
    id: page

    property var sh
    property bool outputs: false

    readonly property var media: sh.media
    onVisibleChanged: if (!visible) outputs = false

    // Çalan yok
    Column {
        visible: !sh.hasMedia && !page.outputs
        anchors.centerIn: parent
        spacing: 10
        Ico {
            anchors.horizontalCenter: parent.horizontalCenter
            source: sh.ic("isle-music")
            size: 28
            tint: "white"
            opacity: 0.35
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Çalan bir şey yok"
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }

    // Oynatıcı
    Item {
        visible: sh.hasMedia && !page.outputs
        anchors.fill: parent

        ArtImage {
            id: art
            width: 124; height: 124; radius: 16
            anchors.verticalCenter: parent.verticalCenter
            source: page.media.artUrl || ""
            MouseArea { anchors.fill: parent; onClicked: sh.send("raise") }
        }

        Column {
            anchors.left: art.right
            anchors.leftMargin: 20
            anchors.right: parent.right
            anchors.verticalCenter: art.verticalCenter
            spacing: 4

            Item {
                width: parent.width
                height: 44
                Column {
                    anchors.left: parent.left
                    anchors.right: modes.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: parent.width
                        text: page.media.title || "Bilinmeyen parça"
                        color: "white"
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.2
                        elide: Text.ElideRight
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: parent.width
                        text: page.media.artist || page.media.player || ""
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }
                Row {
                    id: modes
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 2
                    CtlButton {
                        width: 28; height: 28; iconSize: 16
                        icon: sh.ic("isle-output")
                        tint: Qt.rgba(1, 1, 1, 0.75)
                        onClicked: page.outputs = true
                    }
                }
            }

            RowLayout {
                width: parent.width
                height: 22
                spacing: 10
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    Layout.preferredWidth: 34
                    text: sh.fmt(sh.pos)
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                }
                IslandSlider {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 16
                    barHeight: 4
                    knob: containsKnob
                    readonly property bool containsKnob: page.media.canSeek === true
                    trackColor: Qt.rgba(1, 1, 1, 0.2)
                    fillColor: "white"
                    interactive: page.media.canSeek === true
                    value: page.media.length > 0 ? sh.pos / page.media.length : 0
                    onCommitted: v => sh.send("seek", v * page.media.length)
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    Layout.preferredWidth: 38
                    horizontalAlignment: Text.AlignRight
                    text: page.media.length > 0 ? "-" + sh.fmt(page.media.length - sh.pos) : ""
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20
                CtlButton {
                    width: 36; height: 36; iconSize: 20
                    icon: sh.ic("isle-backward-symbolic")
                    enabledBtn: page.media.canPrev !== false
                    onClicked: sh.send("prev")
                }
                CtlButton {
                    width: 40; height: 40; iconSize: 24
                    icon: sh.playing ? sh.ic("isle-pause-symbolic") : sh.ic("isle-play-symbolic")
                    onClicked: sh.send("play_pause")
                }
                CtlButton {
                    width: 36; height: 36; iconSize: 20
                    icon: sh.ic("isle-forward-symbolic")
                    enabledBtn: page.media.canNext !== false
                    onClicked: sh.send("next")
                }
            }
        }
    }

    // Ses seviyesi + çıkışlar
    Item {
        visible: page.outputs
        anchors.fill: parent

        RowLayout {
            id: volRow
            width: parent.width
            height: 28
            spacing: 10
            CtlButton {
                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                iconSize: 16
                icon: sh.ic("isle-chevron-left-symbolic")
                tint: Qt.rgba(1, 1, 1, 0.75)
                onClicked: page.outputs = false
            }
            CtlButton {
                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                iconSize: 16
                icon: sh.volume.muted ? sh.ic("isle-speaker-off-symbolic") : sh.ic("isle-speaker-3-symbolic")
                tint: sh.volume.muted ? "#ff453a" : "white"
                onClicked: sh.send("vol_mute")
            }
            IslandSlider {
                Layout.fillWidth: true
                Layout.preferredHeight: 16
                barHeight: 4
                knob: true
                trackColor: Qt.rgba(1, 1, 1, 0.2)
                fillColor: sh.volume.muted ? "#636366" : "white"
                value: sh.volume.level / 100
                onMoved: v => sh.send("vol_set", v * 100)
            }
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                Layout.preferredWidth: 46
                horizontalAlignment: Text.AlignRight
                text: sh.volume.level + "%"
                color: Qt.rgba(1, 1, 1, 0.85)
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
        }

        ListView {
            anchors.top: volRow.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: sh.audio.sinks
            delegate: Rectangle {
                required property var modelData
                readonly property bool current: modelData.name === sh.audio["default"]
                width: ListView.view.width
                height: 40
                radius: 12
                color: current || outMa.containsMouse ? "#1c1c1e" : "transparent"
                Ico {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    source: sh.sinkIcon(modelData.kind)
                    size: 18
                    tint: "white"
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    x: 42
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 42 - 36
                    text: modelData.desc
                    color: "white"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Ico {
                    visible: parent.current
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    source: sh.ic("isle-check-symbolic")
                    size: 14
                    tint: "white"
                }
                MouseArea {
                    id: outMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: sh.send("audio_set", modelData.name)
                }
            }
        }
    }
}
