import QtQuick
import QtQuick.Layouts

// Pano geçmişi: bir öğeye tıklayınca panoya geri konur ve panel kapanır.
Item {
    id: page

    property var sh

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 20
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                text: sh.clip.length > 0 ? sh.clip.length + " öğe" : "Pano geçmişi"
                color: "#8e8e93"
                font.pixelSize: 11
                font.weight: Font.Medium
            }
            Item { Layout.fillWidth: true }
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                visible: sh.clip.length > 0
                text: "Temizle"
                color: clrMa.containsMouse ? "white" : sh.accent
                font.pixelSize: 11
                font.weight: Font.Medium
                MouseArea {
                    id: clrMa
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    onClicked: sh.send("clip_clear")
                }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: sh.clip
            spacing: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                required property var modelData
                width: list.width
                height: Math.max(44, label.implicitHeight + 20)
                radius: 14
                color: itemMa.pressed ? "#2c2c2e" : (itemMa.containsMouse ? "#242426" : "#1c1c1e")
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {

                    renderType: Text.CurveRendering

                    font.family: "Inter"
                    id: label
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 12 - 36
                    text: modelData.text.replace(/\s+/g, " ")
                    color: "white"
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                MouseArea {
                    id: itemMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        sh.send("clip_copy", modelData.id)
                        sh.toast("Panoya kopyalandı", "edit-copy")
                        sh.panelOpen = false
                    }
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: 11
                    color: xMa.containsMouse ? "#3a3a3c" : "transparent"
                    Ico { anchors.centerIn: parent; source: "window-close"; size: 11; tint: "#8e8e93" }
                    MouseArea {
                        id: xMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: sh.send("clip_del", modelData.id)
                    }
                }
            }
        }
    }

    Column {
        visible: sh.clip.length === 0
        anchors.centerIn: parent
        spacing: 8
        width: parent.width - 48
        Ico {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "edit-paste"
            size: 30
            tint: "#6c6c70"
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: sh.clipOn ? "Pano geçmişi boş.\nBir şey kopyaladığında burada görünür."
                            : "Pano geçmişi bu oturumda kullanılamıyor."
            color: "#8e8e93"
            font.pixelSize: 12
        }
    }
}
