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
        return h > 0 ? h + " sa " + m + " dk" : m + " dk"
    }
    function tempColor(t) { return t >= 85 ? "#ff453a" : (t >= 70 ? "#ff9f0a" : "#30d158") }
    readonly property string batState: bat.state === "Charging" ? "Şarj oluyor"
                                      : bat.state === "Full" ? "Dolu"
                                      : bat.state === "Discharging" ? "Pilde" : "Beklemede"

    component StatCard: Rectangle {
        id: card
        property string title
        property string value
        property string sub
        property color accent: "#0a84ff"
        property var series: []
        property real seriesMax: 0
        property real bar: -1          // 0..1: alt çizgi (grafik yoksa)

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        radius: 14
        color: "#1c1c1e"
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
                title: "İşlemci"
                value: page.ready ? page.st.cpu + "%" : "…"
                sub: page.ready ? page.st.temp + "°C" : ""
                accent: "#0a84ff"
                series: page.ready ? page.st.cpuHist : []
                seriesMax: 100
            }
            StatCard {
                title: "Bellek"
                value: page.ready ? page.st.mem + "%" : "…"
                sub: page.ready ? page.st.memUsed + " / " + page.st.memTotal + " GB" : ""
                accent: page.ready && page.st.mem > 85 ? "#ff453a" : "#5e5ce6"
                bar: page.ready ? page.st.mem / 100 : 0
            }
            StatCard {
                title: "Ağ"
                value: page.ready ? page.speed(page.st.down) : "…"
                sub: page.ready ? "↑ " + page.speed(page.st.up) : ""
                accent: "#30d158"
                series: page.ready ? page.st.downHist : []
            }
            StatCard {
                title: "Sıcaklık"
                value: page.ready ? page.st.temp + "°C" : "…"
                sub: page.ready ? (page.st.fan > 0 ? page.st.fan + " dev/dk" : "Fan yok") : ""
                accent: page.ready ? page.tempColor(page.st.temp) : "#30d158"
                bar: page.ready ? page.st.temp / 100 : 0
            }
        }

        // Pil: tek satır
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 14
            color: "#1c1c1e"

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
                        text: page.bat.present ? "%" + page.bat.level + " · " + page.batState : "Pil yok"
                        color: "white"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        text: page.bat.present && page.bat.time > 0
                              ? page.duration(page.bat.time) + (page.bat.charging ? " içinde dolar" : " kaldı")
                              : (page.ready ? "Açık kalma " + page.duration(page.st.uptime || 0) : "")
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.pixelSize: 11
                    }
                }
                Repeater {
                    model: page.bat.present ? [
                        { k: "Güç", v: page.bat.rate > 0 ? page.bat.rate + " W" : "—" },
                        { k: "Sağlık", v: page.bat.health > 0 ? "%" + page.bat.health : "—" },
                        { k: "Limit", v: page.bat.limit > 0 ? "%" + page.bat.limit : "Yok" },
                        { k: "Döngü", v: String(page.bat.cycles) }
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
