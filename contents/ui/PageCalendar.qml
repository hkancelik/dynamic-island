import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Takvim: solda ay, sağda seçili günün etkinlikleri.
Item {
    id: page

    property var sh
    property int monthOffset: 0
    property double selMs: 0       // seçili günün başlangıcı (0: bugün)

    readonly property var loc: sh.locale
    readonly property double todayMs: { var d = new Date(sh.nowMs); d.setHours(0, 0, 0, 0); return d.getTime() }
    readonly property double dayMs: selMs > 0 ? selMs : todayMs
    readonly property var shown: { var d = new Date(sh.nowMs); return new Date(d.getFullYear(), d.getMonth() + monthOffset, 1) }

    onVisibleChanged: if (!visible) { monthOffset = 0; selMs = 0 }

    // Ayın ızgarası: pazartesiden başlayan 6 hafta
    readonly property var cells: {
        var first = shown
        var lead = (first.getDay() + 6) % 7
        var out = []
        for (var i = 0; i < 42; i++) {
            var d = new Date(first.getFullYear(), first.getMonth(), 1 - lead + i)
            out.push({ ms: d.getTime(), num: d.getDate(), inMonth: d.getMonth() === first.getMonth() })
        }
        return out
    }
    readonly property int weeks: Math.ceil(((shown.getDay() + 6) % 7 + new Date(shown.getFullYear(), shown.getMonth() + 1, 0).getDate()) / 7)

    function eventsOn(ms) {
        var end = new Date(ms); end.setDate(end.getDate() + 1)
        var e2 = end.getTime()
        return sh.cal.events.filter(function (e) {
            return (e.start < e2 && e.end > ms) || (e.end === e.start && e.start >= ms && e.start < e2)
        })
    }
    readonly property var dayEvents: eventsOn(dayMs)

    RowLayout {
        anchors.fill: parent
        spacing: 22

        // Ay
        Column {
            Layout.preferredWidth: 196
            Layout.fillHeight: true
            spacing: 2

            Item {
                width: parent.width
                height: 20
                Row {
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        text: page.loc.standaloneMonthName(page.shown.getMonth(), Locale.LongFormat).toLocaleUpperCase(sh.lang === "tr" ? "tr-TR" : "en-US")
                        color: "#ff453a"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        text: page.shown.getFullYear()
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    CtlButton {
                        width: 20; height: 20; iconSize: 12
                        icon: sh.ic("isle-chevron-left-symbolic")
                        tint: Qt.rgba(1, 1, 1, 0.75)
                        onClicked: page.monthOffset--
                    }
                    CtlButton {
                        width: 20; height: 20; iconSize: 12
                        icon: sh.ic("isle-chevron-right-symbolic")
                        tint: Qt.rgba(1, 1, 1, 0.75)
                        onClicked: page.monthOffset++
                    }
                }
            }

            Row {
                Repeater {
                    model: [sh.t("Pt"), sh.t("Sa"), sh.t("Ça"), sh.t("Pe"), sh.t("Cu"), sh.t("Ct"), sh.t("Pz")]
                    Text {
                        required property var modelData
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: 28
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Qt.rgba(1, 1, 1, 0.45)
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }

            Grid {
                columns: 7
                Repeater {
                    model: page.cells.slice(0, page.weeks * 7)
                    Item {
                        required property var modelData
                        readonly property bool today: modelData.ms === page.todayMs
                        readonly property bool sel: modelData.ms === page.dayMs
                        readonly property bool weekend: (new Date(modelData.ms).getDay() % 6) === 0
                        width: 28
                        height: page.weeks > 5 ? 17 : 19
                        Rectangle {
                            anchors.centerIn: parent
                            width: 20; height: 20; radius: 10
                            color: parent.today ? "#ff453a" : (parent.sel ? Qt.rgba(1, 1, 1, 0.16) : (dMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"))
                        }
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            anchors.centerIn: parent
                            text: modelData.num
                            color: "white"
                            opacity: !modelData.inMonth ? 0.3 : (parent.weekend && !parent.today ? 0.55 : 1)
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                        Rectangle {
                            visible: modelData.inMonth && !parent.today && page.eventsOn(modelData.ms).length > 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: -1
                            width: 3; height: 3; radius: 1.5
                            color: Qt.rgba(1, 1, 1, 0.6)
                        }
                        MouseArea {
                            id: dMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: page.selMs = modelData.ms
                        }
                    }
                }
            }
        }

        // Gün
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 5

            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                Layout.fillWidth: true
                text: (page.dayMs === page.todayMs ? sh.t("Bugün, ") : "") + page.loc.toString(new Date(page.dayMs), page.dayMs === page.todayMs ? "d MMMM" : "d MMMM dddd")
                color: "white"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.letterSpacing: -0.1
                elide: Text.ElideRight
            }

            // Hızlı ekleme: "Akşam yemeği 20:00" → seçili güne
            TextField {
                id: addField
                visible: sh.cal.writable === true
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                placeholderText: sh.t("Etkinlik ekle · ör. Akşam yemeği 20:00")
                placeholderTextColor: Qt.rgba(1, 1, 1, 0.4)
                color: "white"
                font.family: "Inter"
                font.pixelSize: 13
                leftPadding: 30
                rightPadding: 10
                selectByMouse: true
                maximumLength: 200
                background: Rectangle {
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.11)
                    border.width: addField.activeFocus ? 1 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.16)
                    Ico {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        source: sh.ic("isle-plus-symbolic")
                        size: 12
                        tint: Qt.rgba(1, 1, 1, 0.5)
                    }
                }
                onAccepted: {
                    if (text.trim().length > 0) {
                        sh.send("cal_add", { text: text.trim(), day: page.dayMs })
                        text = ""
                    }
                }
            }

            // Kaydırılabilir kenarlarda satırlar erir (siyah şerit değil)
            FadeEdges {
                id: evFade
                view: evList
                fadeTop: evList.atYBeginning ? 0 : 14
                fadeBottom: evList.atYEnd ? 0 : 18
            }
            ListView {
                id: evList
                visible: sh.cal.configured
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 3
                boundsBehavior: Flickable.StopAtBounds
                model: page.dayEvents
                delegate: Rectangle {
                    id: evRow
                    required property var modelData
                    readonly property bool whole: modelData.allDay || (modelData.start <= page.dayMs && modelData.end >= page.dayMs + 86400000)
                    readonly property bool past: modelData.end <= sh.nowMs && modelData.end !== modelData.start
                    readonly property color accent: sh.calColor(modelData.cal)
                    width: evList.width
                    height: 26
                    radius: 8
                    color: Qt.rgba(accent.r, accent.g, accent.b, 0.2)
                    opacity: (past ? 0.5 : 1) * evFade.factor(evRow)

                    Rectangle {
                        x: 5; y: 4
                        width: 3; height: parent.height - 8; radius: 2
                        color: parent.accent
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        x: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 16 - timeT.width - (joinB.visible ? joinB.width + 8 : 0) - 18
                        text: modelData.title
                        color: "white"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        id: joinB
                        visible: modelData.url !== "" && modelData.url !== undefined && !parent.past
                        anchors.right: timeT.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42; height: 20; radius: 10
                        color: joinMa.pressed ? "#0060c0" : "#0a84ff"
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            anchors.centerIn: parent
                            text: sh.t("Katıl")
                            color: "white"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: joinMa
                            anchors.fill: parent
                            onClicked: { sh.send("open_url", modelData.url); sh.panelOpen = false }
                        }
                    }
                    Text {
                        id: timeT
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.whole ? sh.t("Tüm gün") : sh.clockOf(modelData.start)
                        color: Qt.rgba(1, 1, 1, 0.65)
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }
            }


            Item { visible: !sh.cal.configured; Layout.fillHeight: true }
        }
    }

    // Boş gün (ajanda alanının ortasında)
    Text {
        renderType: Text.CurveRendering
        font.family: "Inter"
        visible: sh.cal.configured && page.dayEvents.length === 0
        x: 196 + 22 + (parent.width - 196 - 22 - width) / 2
        y: (parent.height - height) / 2 + (sh.cal.writable ? 26 : 10)
        text: sh.t("Etkinlik yok")
        color: Qt.rgba(1, 1, 1, 0.55)
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    // Takvim bağlı değil
    Column {
        visible: !sh.cal.configured
        x: 196 + 22
        width: parent.width - x
        y: 34
        spacing: 6
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            width: parent.width
            text: sh.t("Takvim bağlı değil")
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            width: parent.width
            wrapMode: Text.Wrap
            text: sh.t("Apple iCloud hesabını \"caldav\" alanına ya da bir iCal adresini \"calendars\" alanına ekle.")
            color: Qt.rgba(1, 1, 1, 0.45)
            font.pixelSize: 12
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            text: sh.t("Ayar dosyasını aç")
            color: cfgMa.containsMouse ? "white" : "#0a84ff"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            MouseArea {
                id: cfgMa
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                onClicked: sh.send("open_config")
            }
        }
    }

    Text {
        renderType: Text.CurveRendering
        font.family: "Inter"
        visible: sh.cal.errors.length > 0
        anchors.bottom: parent.bottom
        x: 196 + 22
        width: parent.width - x
        text: sh.cal.errors[0] || ""
        color: "#ff453a"
        font.pixelSize: 10
        elide: Text.ElideRight
    }
}
