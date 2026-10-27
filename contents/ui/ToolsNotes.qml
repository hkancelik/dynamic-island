import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Anımsatıcılar: turuncu başlık ve sayı, halkalı satırlar; işaretlenen
// üstü çizilir ve kısa süre sonra gider. Altta yeni anımsatıcı alanı.
Item {
    id: page

    property var sh
    readonly property color orange: "#ff9f0a"
    readonly property int open: {
        var n = 0
        for (var i = 0; i < sh.notes.length; i++) if (!sh.notes[i].done) n++
        return n
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 18
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                text: "Anımsatıcılar"
                color: page.orange
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                visible: page.open > 0
                text: page.open
                color: page.orange
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: sh.notes
            spacing: 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 200 } }
            displaced: Transition { NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic } }

            delegate: Item {
                id: row
                required property var modelData
                width: list.width
                height: Math.max(30, label.implicitHeight + 12)

                // Halka: işaretlenince turuncu, içinde nokta
                Rectangle {
                    x: 0
                    y: 6
                    width: 18; height: 18; radius: 9
                    color: "transparent"
                    border.width: 1.5
                    border.color: row.modelData.done ? page.orange : Qt.rgba(1, 1, 1, 0.35)
                    Rectangle {
                        anchors.centerIn: parent
                        width: 10; height: 10; radius: 5
                        color: page.orange
                        scale: row.modelData.done ? 1 : 0
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sh.send("note_toggle", row.modelData.id)
                    }
                }
                Text {
                    id: label
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    x: 30
                    y: 6
                    width: parent.width - 30 - 28
                    text: row.modelData.text
                    color: row.modelData.done ? Qt.rgba(1, 1, 1, 0.45) : "white"
                    font.pixelSize: 13
                    font.strikeout: row.modelData.done
                    wrapMode: Text.Wrap
                    lineHeight: 1.1
                }
                // İnce ayırıcı: yazının altından kenara
                Rectangle {
                    x: 30
                    anchors.bottom: parent.bottom
                    width: parent.width - 30
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.07)
                }
                // Üzerine gelince sil
                HoverHandler { id: hov }
                CtlButton {
                    visible: hov.hovered
                    anchors.right: parent.right
                    y: 4
                    width: 22; height: 22; iconSize: 10
                    icon: sh.ic("isle-close-symbolic")
                    tint: Qt.rgba(1, 1, 1, 0.7)
                    onClicked: sh.send("note_del", row.modelData.id)
                }
            }
        }

        // Yeni anımsatıcı
        TextField {
            id: input
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            placeholderText: "Yeni anımsatıcı"
            placeholderTextColor: Qt.rgba(1, 1, 1, 0.4)
            color: "white"
            font.family: "Inter"
            font.pixelSize: 13
            leftPadding: 30
            rightPadding: 8
            selectByMouse: true
            maximumLength: 500
            background: Item {
                Ico {
                    x: 3
                    anchors.verticalCenter: parent.verticalCenter
                    source: sh.ic("isle-plus-symbolic")
                    size: 12
                    tint: Qt.rgba(1, 1, 1, 0.5)
                }
            }
            onAccepted: {
                if (text.trim().length > 0) {
                    sh.send("note_add", text)
                    text = ""
                }
            }
        }
    }

    Text {
        renderType: Text.CurveRendering
        font.family: "Inter"
        visible: sh.notes.length === 0
        anchors.centerIn: parent
        text: "Anımsatıcı yok"
        color: Qt.rgba(1, 1, 1, 0.55)
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }
}
