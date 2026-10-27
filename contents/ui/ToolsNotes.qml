import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Hızlı notlar / yapılacaklar.
Item {
    id: page

    property var sh
    readonly property int doneCount: {
        var n = 0
        for (var i = 0; i < sh.notes.length; i++) if (sh.notes[i].done) n++
        return n
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        TextField {
            id: input
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            placeholderText: "Yeni not ekle ve Enter'a bas…"
            placeholderTextColor: "#8e8e93"
            color: "white"
            font.pixelSize: 13
            leftPadding: 14
            rightPadding: 14
            selectByMouse: true
            maximumLength: 500
            background: Rectangle {
                radius: 19
                color: "#1c1c1e"
                border.width: input.activeFocus ? 1.5 : 0
                border.color: sh.accent
            }
            onAccepted: {
                if (text.trim().length > 0) {
                    sh.send("note_add", text)
                    text = ""
                }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: sh.notes
            spacing: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                required property var modelData
                width: list.width
                height: Math.max(42, label.implicitHeight + 20)
                radius: 14
                color: "#1c1c1e"

                // Tamamlandı işareti
                Rectangle {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: 11
                    color: modelData.done ? sh.accent : "transparent"
                    border.width: modelData.done ? 0 : 1.5
                    border.color: "#8e8e93"
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Ico {
                        anchors.centerIn: parent
                        visible: modelData.done
                        source: "task-complete"
                        size: 14
                        tint: "#000000"
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: sh.send("note_toggle", modelData.id)
                    }
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    id: label
                    x: 44
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 44 - 36
                    text: modelData.text
                    color: modelData.done ? "#8e8e93" : "white"
                    font.pixelSize: 13
                    font.strikeout: modelData.done
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
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
                        onClicked: sh.send("note_del", modelData.id)
                    }
                }
            }
        }

        Text {

            renderType: Text.CurveRendering

            font.family: "Inter"
            visible: page.doneCount > 0
            Layout.alignment: Qt.AlignHCenter
            text: "Biten " + page.doneCount + " notu temizle"
            color: doneMa.containsMouse ? "white" : sh.accent
            font.pixelSize: 11
            font.weight: Font.Medium
            MouseArea {
                id: doneMa
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                onClicked: sh.send("note_clear_done")
            }
        }
    }

    Column {
        visible: sh.notes.length === 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: 110
        spacing: 8
        Ico {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "document-edit"
            size: 30
            tint: "#6c6c70"
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            text: "Henüz not yok"
            color: "#8e8e93"
            font.pixelSize: 12
        }
    }
}
