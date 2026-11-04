import QtQuick
import QtQuick.Layouts

// Bildirimler: başlık + Temizle, altta tek satırlık bildirim listesi.
Item {
    id: page

    property var sh

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: -8
        anchors.rightMargin: -8
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 6
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                text: sh.t("Bildirimler")
                color: Qt.rgba(1, 1, 1, 0.6)
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
            CtlButton {
                Layout.preferredWidth: 26; Layout.preferredHeight: 26
                iconSize: 14
                icon: sh.ic("isle-bell")
                tint: sh.ui.dnd ? "#5e5ce6" : "white"
                onClicked: sh.send("toggle_dnd")
            }
            Rectangle {
                visible: sh.notifModel.count > 0
                Layout.preferredWidth: clearText.implicitWidth + 24
                Layout.preferredHeight: 26
                radius: 13
                color: clearMa.pressed ? "#48484a" : clearMa.containsMouse ? "#3a3a3c" : Qt.rgba(1, 1, 1, 0.17)
                GlassBack { hot: clearMa.containsMouse; down: clearMa.pressed }
                Text {
                    id: clearText
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    anchors.centerIn: parent
                    text: sh.t("Temizle")
                    color: "white"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: clearMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: sh.send("notif_clear")
                }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: sh.notifModel
            spacing: 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
            }
            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: 150 }
            }
            displaced: Transition {
                NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic }
            }

            delegate: Rectangle {
                width: list.width
                height: 34
                radius: 10
                color: rowMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                AppIcon {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    size: 22
                    source: model.icon
                }
                Row {
                    x: 40
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40 - tail.width - 16
                    spacing: 8
                    clip: true
                    Text {
                        id: t1
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: Math.min(implicitWidth, parent.width * 0.6)
                        text: model.title || model.app
                        color: "white"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: parent.width - t1.width - 8
                        text: (model.body || "").replace(/\s+/g, " ")
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }
                Item {
                    id: tail
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    width: 44
                    height: parent.height
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        visible: !rowMa.containsMouse
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: sh.ago(model.ts)
                        color: Qt.rgba(1, 1, 1, 0.45)
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (model.desktop !== "") {
                            sh.send("notif_open", model.id)
                            sh.panelOpen = false
                        } else {
                            sh.send("notif_dismiss", model.id)
                        }
                    }
                }

                // Üzerine gelince kaldır (×)
                Rectangle {
                    visible: rowMa.containsMouse || xMa.containsMouse
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20; radius: 10
                    color: "#3a3a3c"
                    Ico {
                        anchors.centerIn: parent
                        source: sh.ic("isle-close-symbolic")
                        size: 10
                        tint: Qt.rgba(1, 1, 1, 0.8)
                    }
                    MouseArea {
                        id: xMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: sh.send("notif_dismiss", model.id)
                    }
                }
            }
        }
    }

    // Boş durum
    Column {
        visible: sh.notifModel.count === 0
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 12
        spacing: 10
        Ico {
            anchors.horizontalCenter: parent.horizontalCenter
            source: sh.ic("isle-bell")
            size: 26
            tint: "white"
            opacity: 0.35
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            anchors.horizontalCenter: parent.horizontalCenter
            text: sh.ui.dnd ? sh.t("Rahatsız Etme açık") : sh.t("Bildirim yok")
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }
}
