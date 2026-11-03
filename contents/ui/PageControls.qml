import QtQuick
import QtQuick.Layouts

// Kontrol: solda ses + her ekranın parlaklığı + Gece Işığı, sağda 2x2 hızlı ayar karoları.
Item {
    id: page

    property var sh

    readonly property bool warm: sh.night.running && !sh.night.inhibited
    readonly property var profileNames: ({ "power-saver": sh.t("Tasarruf"), "balanced": sh.t("Dengeli"), "performance": sh.t("Performans") })

    component SliderRow: RowLayout {
        id: row
        property string icon
        property color iconTint: "white"
        property string label
        property real value: 0
        property color fill: "white"
        signal moved(real v)
        signal iconClicked
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        spacing: 8
        CtlButton {
            Layout.preferredWidth: 28; Layout.preferredHeight: 28
            iconSize: 16
            icon: row.icon
            tint: row.iconTint
            onClicked: row.iconClicked()
        }
        IslandSlider {
            Layout.fillWidth: true
            Layout.preferredHeight: 16
            barHeight: 4
            knob: true
            trackColor: Qt.rgba(1, 1, 1, 0.2)
            fillColor: row.fill
            value: row.value
            onMoved: v => row.moved(v)
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            Layout.preferredWidth: 38
            horizontalAlignment: Text.AlignRight
            text: row.label
            color: Qt.rgba(1, 1, 1, 0.85)
            font.pixelSize: 12
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 20

        // Sol: kaydırıcılar
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4

            Item { Layout.fillHeight: true }

            SliderRow {
                icon: sh.volume.muted ? sh.ic("isle-speaker-off-symbolic") : sh.ic("isle-speaker-3-symbolic")
                iconTint: sh.volume.muted ? "#ff453a" : "white"
                value: sh.volume.level / 100
                fill: sh.volume.muted ? "#636366" : "white"
                label: sh.volume.level + "%"
                onMoved: v => sh.send("vol_set", v * 100)
                onIconClicked: sh.send("vol_mute")
            }

            // Ekran sayısı model olur: değer değişince satırlar yeniden yaratılmaz (sürükleme kopmaz)
            Repeater {
                model: sh.displays.length
                delegate: SliderRow {
                    required property int index
                    readonly property var d: index < sh.displays.length ? sh.displays[index] : null
                    icon: sh.displays.length < 2 ? sh.ic("isle-sun-symbolic")
                          : (d && d.internal ? "computer-laptop-symbolic" : sh.ic("isle-display-symbolic"))
                    iconTint: page.warm ? "#ffd60a" : "white"
                    value: d ? d.percent / 100 : 0
                    label: d ? d.percent + "%" : ""
                    onMoved: v => { if (d) sh.send("brightness_set", { id: d.id, pct: Math.max(1, v * 100) }) }
                }
            }

            // Ses çıkışı + Gece Işığı
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                Layout.topMargin: 4
                spacing: 8

                Rectangle {
                    visible: sh.audio.sinks.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: 14
                    color: outMa.containsMouse || sh.deviceMenu ? "#3a3a3c" : Qt.rgba(1, 1, 1, 0.17)
                    Row {
                        anchors.centerIn: parent
                        width: parent.width - 24
                        spacing: 6
                        Ico {
                            anchors.verticalCenter: parent.verticalCenter
                            source: sh.sinkIcon(sh.currentSinkKind())
                            size: 14
                            tint: "white"
                        }
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 20
                            text: {
                                for (var i = 0; i < sh.audio.sinks.length; i++)
                                    if (sh.audio.sinks[i].name === sh.audio["default"]) return sh.audio.sinks[i].desc
                                return sh.t("Çıkış")
                            }
                            color: "white"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: outMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: sh.deviceMenu = !sh.deviceMenu
                    }
                }

                // Gece Işığı: sol tık duraklat/sürdür, sağ tık ayarlar
                Rectangle {
                    id: nightBtn
                    visible: sh.night.available
                    readonly property bool planned: sh.night.enabled && !sh.night.inhibited && !sh.night.running
                    Layout.preferredWidth: 104
                    Layout.preferredHeight: 28
                    radius: 14
                    color: page.warm ? Qt.rgba(1, 0.84, 0.04, 0.18) : (nightMa.containsMouse ? "#3a3a3c" : Qt.rgba(1, 1, 1, 0.17))
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Ico {
                            anchors.verticalCenter: parent.verticalCenter
                            source: sh.ic("isle-moon")
                            size: 13
                            tint: page.warm || nightBtn.planned ? "#ffd60a" : "white"
                        }
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            anchors.verticalCenter: parent.verticalCenter
                            text: sh.t("Gece Işığı")
                            color: page.warm || nightBtn.planned ? "#ffd60a" : "white"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                    MouseArea {
                        id: nightMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: m => m.button === Qt.RightButton ? sh.send("open_settings", "nightlight")
                                                                    : sh.send("night_toggle")
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        // Sağ: hızlı ayar karoları (sol tık aç/kapat, sağ tık ayarlar)
        GridLayout {
            Layout.preferredWidth: 236
            Layout.maximumWidth: 236
            Layout.fillHeight: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8

            ToggleTile {
                Layout.fillWidth: true; Layout.fillHeight: true
                active: sh.ctl.wifiOn
                accent: "#0a84ff"
                icon: sh.ctl.wifiOn && sh.wifi.connected ? sh.ic("isle-wifi-symbolic") : sh.ic("isle-wifi-off-symbolic")
                title: !sh.ctl.wifiOn ? "Wi-Fi" : (sh.wifi.connected ? (sh.wifi.ssid || sh.t("Bağlı")) : sh.t("Bağlı değil"))
                subtitle: !sh.ctl.wifiOn ? sh.t("Kapalı")
                        : !sh.wifi.connected ? sh.t("Ağ yok")
                        : sh.wifi.type === "ethernet" ? sh.t("Kablolu") : sh.t("Sinyal %1%").arg(sh.wifi.signal)
                onClicked: sh.send("wifi_toggle")
                onRightClicked: sh.send("open_settings", "network")
            }
            ToggleTile {
                Layout.fillWidth: true; Layout.fillHeight: true
                enabled: sh.ctl.bt.present
                opacity: sh.ctl.bt.present ? 1 : 0.4
                active: sh.ctl.bt.on
                accent: "#0a84ff"
                icon: sh.ctl.bt.on ? sh.ic("isle-bluetooth-symbolic") : sh.ic("isle-bluetooth-off-symbolic")
                title: "Bluetooth"
                subtitle: sh.ctl.bt.on ? (sh.ctl.bt.device || sh.t("Açık")) : sh.t("Kapalı")
                onClicked: sh.send("bt_toggle")
                onRightClicked: sh.send("open_settings", "bluetooth")
            }
            ToggleTile {
                Layout.fillWidth: true; Layout.fillHeight: true
                active: sh.ui.dnd
                accent: "#5e5ce6"
                icon: sh.ic("isle-moon")
                title: sh.t("Rahatsız Etme")
                subtitle: sh.ui.dnd ? sh.t("Açık") : sh.t("Kapalı")
                onClicked: sh.send("toggle_dnd")
                onRightClicked: sh.send("open_settings", "notifications")
            }
            ToggleTile {
                Layout.fillWidth: true; Layout.fillHeight: true
                active: sh.power.profile !== "" && sh.power.profile !== "balanced"
                accent: sh.power.profile === "performance" ? "#ff9f0a" : "#30d158"
                icon: sh.battery.charging ? sh.ic("isle-bolt") : sh.ic("isle-battery-symbolic")
                title: sh.battery.present ? sh.pct(sh.battery.level) : sh.t("Güç")
                subtitle: sh.power.profile ? (page.profileNames[sh.power.profile] || sh.power.profile)
                        : (sh.battery.charging ? sh.t("Şarj oluyor") : sh.t("Pilde"))
                onClicked: sh.send("profile_cycle")
                onRightClicked: sh.send("open_settings", "power")
            }
        }
    }
}
