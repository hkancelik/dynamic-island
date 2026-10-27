import QtQuick
import QtQuick.Layouts

// Uygulamalar: üstte tek sıra uygulama, altta hap biçiminde hızlı eylemler.
Item {
    id: page

    property var sh
    property string armed: ""   // onay bekleyen güç eylemi

    onVisibleChanged: if (!visible) armed = ""

    Timer { id: disarm; interval: 3000; onTriggered: page.armed = "" }

    function power(cmd) {
        if (armed === cmd) {
            sh.send(cmd)
            armed = ""
            return
        }
        armed = cmd
        disarm.restart()
    }

    component Pill: Rectangle {
        id: pill
        property string icon
        property string label
        property color tint: "white"
        property bool hot: false
        signal clicked
        Layout.preferredHeight: 30
        Layout.fillWidth: true
        radius: 15
        color: pMa.pressed ? "#48484a" : (pMa.containsMouse || hot ? "#3a3a3c" : "#2c2c2e")
        Behavior on color { ColorAnimation { duration: 120 } }
        Row {
            anchors.centerIn: parent
            spacing: 6
            Ico {
                anchors.verticalCenter: parent.verticalCenter
                source: pill.icon
                size: 14
                tint: pill.tint
            }
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                color: pill.hot ? pill.tint : "white"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }
        MouseArea {
            id: pMa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: pill.clicked()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item { Layout.fillHeight: true }

        Row {
            Layout.fillWidth: true
            Layout.preferredHeight: 74
            Repeater {
                model: sh.appList.slice(0, 8)
                Item {
                    required property var modelData
                    width: page.width / Math.max(6, Math.min(8, sh.appList.length))
                    height: 74

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 0
                        width: 52; height: 52; radius: 14
                        color: appMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        AppIcon {
                            anchors.centerIn: parent
                            size: 40
                            source: modelData.icon
                            scale: appMa.pressed ? 0.9 : 1
                            Behavior on scale { NumberAnimation { duration: 100 } }
                        }
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        y: 56
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 6
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.name
                        color: Qt.rgba(1, 1, 1, 0.75)
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: appMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            sh.send("launch", modelData.id)
                            sh.panelOpen = false
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Pill {
                icon: "camera-photo-symbolic"
                label: "Görüntü"
                onClicked: { sh.send("screenshot"); sh.panelOpen = false }
            }
            Pill {
                readonly property string st: sh.rec.state
                icon: sh.ic("isle-record-symbolic")
                label: st === "recording" ? "Durdur" : (st === "idle" ? "Kayıt" : (st === "starting" ? "Başlıyor" : "Kaydediyor"))
                tint: "#ff453a"
                hot: st === "recording"
                onClicked: { sh.send("rec_toggle"); sh.panelOpen = false }
            }
            Pill {
                icon: sh.ic("isle-lock-symbolic")
                label: "Kilitle"
                onClicked: { sh.send("lock"); sh.panelOpen = false }
            }
            Pill {
                icon: sh.ic("isle-moon")
                label: "Uyku"
                onClicked: { sh.send("suspend"); sh.panelOpen = false }
            }
            Pill {
                icon: sh.ic("isle-reset")
                label: page.armed === "reboot" ? "Emin?" : "Yeniden"
                tint: page.armed === "reboot" ? "#ffd60a" : "white"
                hot: page.armed === "reboot"
                onClicked: page.power("reboot")
            }
            Pill {
                icon: "system-shutdown-symbolic"
                label: page.armed === "poweroff" ? "Emin?" : "Kapat"
                tint: "#ff453a"
                hot: page.armed === "poweroff"
                onClicked: page.power("poweroff")
            }
        }

        Item { Layout.fillHeight: true }
    }
}
