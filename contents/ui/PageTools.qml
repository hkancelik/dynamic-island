import QtQuick
import QtQuick.Layouts

// Araçlar: Pano geçmişi | Notlar | Dosya rafı
Item {
    id: page

    property var sh
    property int sub: 0

    readonly property var names: ["Pano", "Anımsatıcı", "Raf"]
    readonly property var counts: [sh.clip.length, sh.notes.length, sh.shelf.length]

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Bölüm seçici
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 28
            radius: 14
            color: "#1c1c1e"

            Rectangle {
                width: (parent.width - 6) / 3
                height: 22
                y: 3
                x: 3 + page.sub * width
                radius: 11
                color: "#3a3a3c"
                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
            Row {
                anchors.fill: parent
                anchors.margins: 3
                Repeater {
                    model: page.names
                    Item {
                        required property string modelData
                        required property int index
                        width: (parent.width) / 3
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
                        MouseArea { anchors.fill: parent; onClicked: page.sub = index }
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
        }
    }
}
