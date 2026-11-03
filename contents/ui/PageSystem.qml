import QtQuick
import QtQuick.Layouts

// Sistem durumu: CPU, bellek, ağ, sıcaklık ve pil ayrıntıları.
// İstatistikler yalnızca bu sayfa açıkken toplanır (ana ekran `stats_on` yollar).
Item {
    id: page

    property var sh

    readonly property var st: sh.stats
    readonly property bool ready: st.cpu !== undefined
    readonly property var bat: sh.battery

    function speed(bps) {
        if (bps < 1024) return bps + " B/s"
        if (bps < 1048576) return (bps / 1024).toFixed(0) + " KB/s"
        return (bps / 1048576).toFixed(1) + " MB/s"
    }
    function duration(sec) {
        if (sec < 0) return "—"
        var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60)
        return h > 0 ? sh.t("%1 sa %2 dk").arg(h).arg(m) : sh.t("%1 dk").arg(m)
    }
    function tempColor(t) { return t >= 85 ? "#ff453a" : (t >= 70 ? "#ff9f0a" : "#30d158") }
    readonly property string batState: bat.state === "Charging" ? sh.t("Şarj oluyor")
                                      : bat.state === "Full" ? sh.t("Dolu")
                                      : bat.state === "Discharging" ? sh.t("Pilde") : sh.t("Beklemede")

    component StatCard: Rectangle {
        id: card
        property string title
        property string value
        property string sub
        property color accent: "#0a84ff"
        property var series: []
        property real seriesMax: 0
        property real bar: -1          // 0..1: alt çizgi (grafik yoksa)
        property string icon           // sağ üst köşe (tema ikonu)

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        radius: 14
        color: Qt.rgba(1, 1, 1, 0.11)
        clip: true

        Spark {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 30
            opacity: 0.5
            values: card.series
            lineColor: card.accent
            maxValue: card.seriesMax
            visible: card.series.length > 1
        }
        Ico {
            visible: card.icon !== ""
            x: parent.width - 28; y: 8
            size: 18
            source: card.icon
            tint: Qt.rgba(1, 1, 1, 0.8)
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            x: 12; y: 9
            text: card.title
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            x: 12; y: 24
            width: parent.width - 20
            text: card.value
            color: "white"
            font.pixelSize: 20
            font.weight: Font.DemiBold
            font.letterSpacing: -0.4
            font.features: { "tnum": 1 }
            elide: Text.ElideRight
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            x: 12; y: 51
            width: parent.width - 20
            text: card.sub
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 11
            elide: Text.ElideRight
        }
        Rectangle {
            visible: card.bar >= 0
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 12
            anchors.bottomMargin: 10
            height: 4; radius: 2
            color: Qt.rgba(1, 1, 1, 0.15)
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, card.bar))
                height: parent.height; radius: 2
                color: card.accent
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 84
            Layout.maximumHeight: 84
            spacing: 8

            StatCard {
                visible: page.sh.weather.ok === true
                Layout.preferredWidth: 1.3
                title: page.sh.weather.place || sh.t("Hava")
                value: page.sh.weather.ok ? page.sh.weather.temp + "°" : ""
                sub: page.sh.weather.ok ? page.sh.weather.text : ""
                icon: page.sh.weather.ok ? page.sh.weather.icon : ""
                accent: "#ff9f0a"
                bar: -1
                // değerin sağında, tek satır: en yüksek / en düşük
                Text {
                    visible: page.sh.weather.ok === true
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    anchors.right: parent.right; anchors.rightMargin: 12
                    y: 30
                    text: page.sh.weather.ok ? "↑" + page.sh.weather.hi + "° ↓" + page.sh.weather.lo + "°" : ""
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: 11
                    font.features: { "tnum": 1 }
                }
            }
            StatCard {
                title: sh.t("İşlemci")
                value: page.ready ? page.st.cpu + "%" : "…"
                sub: page.ready ? page.st.temp + "°C" : ""
                accent: "#0a84ff"
                series: page.ready ? page.st.cpuHist : []
                seriesMax: 100
            }
            StatCard {
                title: sh.t("Bellek")
                value: page.ready ? page.st.mem + "%" : "…"
                sub: page.ready ? page.st.memUsed + " / " + page.st.memTotal + " GB" : ""
                accent: page.ready && page.st.mem > 85 ? "#ff453a" : "#5e5ce6"
                bar: page.ready ? page.st.mem / 100 : 0
            }
            StatCard {
                title: sh.t("Ağ")
                value: page.ready ? page.speed(page.st.down) : "…"
                sub: page.ready ? "↑ " + page.speed(page.st.up) : ""
                accent: "#30d158"
                series: page.ready ? page.st.downHist : []
            }
            StatCard {
                title: sh.t("Sıcaklık")
                value: page.ready ? page.st.temp + "°C" : "…"
                sub: page.ready ? (page.st.fan > 0 ? sh.t("%1 dev/dk").arg(page.st.fan) : sh.t("Fan yok")) : ""
                accent: page.ready ? page.tempColor(page.st.temp) : "#30d158"
                bar: page.ready ? page.st.temp / 100 : 0
            }
        }

        // Pil: tek satır
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.11)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 14

                Ico {
                    source: page.bat.charging ? sh.ic("isle-bolt") : sh.ic(page.bat.level <= 20 ? "isle-battery-low-symbolic" : "isle-battery-symbolic")
                    size: 18
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    tint: sh.batColor()
                    visible: page.bat.present
                }
                Column {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        text: page.bat.present ? sh.pct(page.bat.level) + " · " + page.batState : sh.t("Pil yok")
                        color: "white"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        text: page.bat.present && page.bat.time > 0
                              ? sh.t(page.bat.charging ? "%1 içinde dolar" : "%1 kaldı").arg(page.duration(page.bat.time))
                              : (page.ready ? sh.t("Açık kalma %1").arg(page.duration(page.st.uptime || 0)) : "")
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.pixelSize: 11
                    }
                }
                Repeater {
                    model: page.bat.present ? [
                        { k: sh.t("Güç"), v: page.bat.rate > 0 ? page.bat.rate + " W" : "—" },
                        { k: sh.t("Sağlık"), v: page.bat.health > 0 ? sh.pct(page.bat.health) : "—" },
                        { k: sh.t("Limit"), v: page.bat.limit > 0 ? sh.pct(page.bat.limit) : sh.t("Yok") },
                        { k: sh.t("Döngü"), v: String(page.bat.cycles) }
                    ] : []
                    Column {
                        required property var modelData
                        spacing: 1
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            text: modelData.v
                            color: "white"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            text: modelData.k
                            color: Qt.rgba(1, 1, 1, 0.5)
                            font.pixelSize: 10
                        }
                    }
                }
                // Telefon (KDE Connect): pil yüzdesi; dokununca telefon çalar
                Rectangle {
                    id: phoneChip
                    readonly property var dev: sh.phone.present && sh.phone.devices.length > 0 ? sh.phone.devices[0] : null
                    visible: dev !== null && sh.settings.phone
                    Layout.preferredWidth: phoneRow.implicitWidth + 20
                    Layout.preferredHeight: 30
                    radius: 15
                    color: phoneMa.containsMouse ? "#3a3a3c" : Qt.rgba(1, 1, 1, 0.17)
                    opacity: dev && dev.reachable ? 1 : 0.45
                    Row {
                        id: phoneRow
                        anchors.centerIn: parent
                        spacing: 6
                        Ico {
                            anchors.verticalCenter: parent.verticalCenter
                            source: sh.ic("isle-phone-symbolic")
                            size: 14
                            tint: phoneChip.dev && phoneChip.dev.charging ? "#30d158" : "white"
                        }
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            anchors.verticalCenter: parent.verticalCenter
                            text: !phoneChip.dev ? "" : !phoneChip.dev.reachable ? sh.t("Bağlı değil")
                                  : phoneChip.dev.battery >= 0 ? sh.pct(phoneChip.dev.battery) : phoneChip.dev.name
                            color: "white"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }
                    MouseArea {
                        id: phoneMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: phoneChip.dev && phoneChip.dev.reachable
                        onClicked: { sh.send("phone_ring", phoneChip.dev.id); sh.toast("Telefon çalıyor", "phone") }
                    }
                }
                CtlButton {
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26
                    iconSize: 14
                    icon: sh.ic("isle-settings")
                    tint: Qt.rgba(1, 1, 1, 0.6)
                    onClicked: sh.send("open_settings", "power")
                }
            }
        }
    }
}
