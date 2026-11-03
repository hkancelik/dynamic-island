import QtQuick
import QtQuick.Layouts

// Hava: solda şimdiki durum, sağda önümüzdeki saatler, altta 5 günlük tahmin.
// Veri arka uçtan (weather.py, Open-Meteo); konum ayar dosyasındaki "weather" bölümünden.
Item {
    id: page

    property var sh
    readonly property var w: sh.weather
    readonly property bool ok: w.ok === true
    readonly property var hours: ok && w.hours ? w.hours.slice(0, 9) : []
    readonly property var days: ok && w.days ? w.days.slice(0, 5) : []
    readonly property color rainColor: "#64d2ff"

    function pad(n) { return String(n).padStart(2, "0") }
    // dow: 0 = Pazartesi; Qt'nin dayName'i 0 = Pazar bekler
    function dayName(d, i) { return i === 0 ? sh.t("Bugün") : sh.locale.dayName((d.dow + 1) % 7, Locale.ShortFormat) }
    readonly property string rainText: !ok || w.rain_in === undefined || w.rain_in < 0 ? ""
        : w.rain_in === 0 ? sh.t("Şimdi yağış var") : sh.t("Yağmur %1 sa sonra").arg(w.rain_in)
    // Hissedilen sıcaklık yalnızca gerçekten farklıysa (≥ 2°) gösterilir
    readonly property string infoText: !ok ? "" :
        (Math.abs((w.feels || 0) - (w.temp || 0)) >= 2 ? sh.t("Hissedilen") + " " + w.feels + "°  ·  " : "")
        + sh.t("Nem") + " " + sh.pct(w.humidity || 0) + "  ·  " + sh.t("Rüzgâr") + " " + sh.t("%1 km/sa").arg(w.wind)

    // yok / kapalı / yükleniyor
    Column {
        visible: !page.ok
        anchors.centerIn: parent
        spacing: 8
        WeatherIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 40; height: 40
            name: "weather-clouds"
            opacity: 0.4
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.w.off ? sh.t("Hava durumu kapalı") : page.w.error ? sh.t("Hava durumu alınamadı") : sh.t("Yükleniyor…")
            color: Qt.rgba(1, 1, 1, 0.6)
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Text {
            visible: !!page.w.off
            renderType: Text.CurveRendering
            font.family: "Inter"
            anchors.horizontalCenter: parent.horizontalCenter
            text: sh.t("Ayarlar → Genel → Hava durumu")
            color: Qt.rgba(1, 1, 1, 0.4)
            font.pixelSize: 11
        }
    }

    Item {
        id: content
        visible: page.ok
        anchors.fill: parent

        // ---- şimdiki durum
        Item {
            id: now
            width: 172; height: 84
            WeatherIcon {
                id: nowIcon
                x: 0; y: 1
                width: 50; height: 50
                name: page.w.icon || ""
            }
            Text {
                anchors.left: nowIcon.right
                anchors.leftMargin: 8
                y: -3
                renderType: Text.CurveRendering
                font.family: "Inter"
                text: page.ok ? page.w.temp + "°" : ""
                color: "white"
                font.pixelSize: 48
                font.weight: Font.DemiBold
                font.letterSpacing: -1.5
                font.features: { "tnum": 1 }
            }
            Text {
                y: 54
                width: parent.width
                renderType: Text.CurveRendering
                font.family: "Inter"
                text: page.ok ? sh.t(page.w.text) : ""
                color: Qt.rgba(1, 1, 1, 0.92)
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                y: 71
                width: parent.width
                renderType: Text.CurveRendering
                font.family: "Inter"
                text: page.ok ? (page.w.place ? page.w.place + "  ·  " : "") + "↑" + page.w.hi + "° ↓" + page.w.lo + "°" : ""
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 11
                font.features: { "tnum": 1 }
                elide: Text.ElideRight
            }
        }

        // ---- üst bilgi satırı: hissedilen, nem, rüzgâr; sağda yağmur uyarısı
        Text {
            id: info
            x: now.width + 22
            width: content.width - x - (rain.visible ? rain.implicitWidth + 12 : 0)
            renderType: Text.CurveRendering
            font.family: "Inter"
            text: page.infoText
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 11
            font.features: { "tnum": 1 }
            elide: Text.ElideRight
        }
        Text {
            id: rain
            visible: page.rainText !== ""
            anchors.right: parent.right
            renderType: Text.CurveRendering
            font.family: "Inter"
            text: page.rainText
            color: page.rainColor
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        // ---- saatlik
        Row {
            x: now.width + 14
            y: 20
            width: content.width - x
            height: 64
            Repeater {
                model: page.hours
                Item {
                    required property var modelData
                    required property int index
                    width: parent.width / 9
                    height: 64
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 3
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            text: index === 0 ? sh.t("Şimdi") : page.pad(modelData.h)
                            color: Qt.rgba(1, 1, 1, index === 0 ? 0.9 : 0.55)
                            font.pixelSize: 11
                            font.weight: index === 0 ? Font.DemiBold : Font.Normal
                            font.features: { "tnum": 1 }
                        }
                        WeatherIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 22; height: 22
                            name: modelData.icon
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            text: modelData.temp + "°"
                            color: "white"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: modelData.pop >= 30
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            text: sh.pct(modelData.pop)
                            color: page.rainColor
                            font.pixelSize: 10
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }
        }

        // ---- 5 günlük tahmin
        GlassCard {
            sh: page.sh
            y: 94
            width: parent.width
            height: parent.height - 94
            radius: 16
            fill: 0.07
            Row {
                anchors.fill: parent
                Repeater {
                    model: page.days
                    Item {
                        required property var modelData
                        required property int index
                        width: parent.width / 5
                        height: parent.height
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                text: page.dayName(modelData, index)
                                color: Qt.rgba(1, 1, 1, index === 0 ? 0.9 : 0.6)
                                font.pixelSize: 11
                                font.weight: index === 0 ? Font.DemiBold : Font.Normal
                            }
                            WeatherIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 24; height: 24
                                name: modelData.icon
                            }
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 6
                                Text {
                                    renderType: Text.CurveRendering
                                    font.family: "Inter"
                                    text: modelData.hi + "°"
                                    color: "white"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    font.features: { "tnum": 1 }
                                }
                                Text {
                                    renderType: Text.CurveRendering
                                    font.family: "Inter"
                                    text: modelData.lo + "°"
                                    color: Qt.rgba(1, 1, 1, 0.45)
                                    font.pixelSize: 13
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
