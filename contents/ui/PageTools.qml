import QtQuick
import QtQuick.Layouts

// Araçlar: Pano geçmişi | Anımsatıcı | Dosya rafı | Notlar
Item {
    id: page

    property var sh

    readonly property var names: [sh.t("Pano"), sh.t("Anımsatıcı"), sh.t("Raf"), sh.t("Notlar")]
    readonly property var counts: [sh.clip.length, sh.notes.length, sh.shelf.length, sh.docs.length]
    readonly property int sub: sh.toolsSub

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Bölüm seçici
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 28
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.11)
            GlassBack {}

            LiquidPill {
                width: parent.width
                height: parent.height
                baseH: 22
                restAlpha: 0.17
                goalW: (parent.width - 6) / page.names.length
                goalX: 3 + page.sub * goalW
                glassLayer: page.sh.glassLayer
                glassFrost: page.sh.glassFrost || 0.3
            }
            Row {
                anchors.fill: parent
                anchors.margins: 3
                Repeater {
                    model: page.names
                    Item {
                        required property string modelData
                        required property int index
                        width: parent.width / page.names.length
                        height: 22
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            anchors.centerIn: parent
                            text: modelData + (page.counts[index] > 0 ? "  " + page.counts[index] : "")
                            color: page.sub === index ? "white" : "#8e8e93"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        MouseArea { anchors.fill: parent; onClicked: sh.toolsSub = index }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ToolsClip {
                anchors.fill: parent
                sh: page.sh
                opacity: page.sub === 0 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            ToolsNotes {
                anchors.fill: parent
                sh: page.sh
                opacity: page.sub === 1 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            ToolsShelf {
                anchors.fill: parent
                sh: page.sh
                opacity: page.sub === 2 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            ToolsDocs {
                anchors.fill: parent
                sh: page.sh
                opacity: page.sub === 3 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
        }
    }
}
