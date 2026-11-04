import QtQuick
import QtQuick.Layouts

// Maç: takip edilen takımın canlı skoru, kadrosu, sıradaki maçları ve son sonuçları.
// Veri arka uçtan (football.py, ESPN); takım Ayarlar → Maç bölümünden seçilir.
Item {
    id: page

    property var sh
    readonly property var f: sh.football
    readonly property bool ok: f.ok === true
    readonly property var team: ok && f.team ? f.team : ({})
    readonly property var fmatch: ok ? (f.focus || (f.next && f.next.length ? f.next[0] : (f.last && f.last.length ? f.last[0] : null))) : null
    readonly property var lineup: ok ? f.lineup : null
    readonly property var tables: ok && f.tables ? f.tables : []
    property int tableIx: 0
    readonly property var upcoming: ok && f.next ? f.next : []
    readonly property var past: ok && f.last ? f.last : []
    readonly property color accent: team.color ? team.color : "#d11317"
    readonly property color winColor: "#30d158"
    readonly property color lossColor: "#ff453a"
    readonly property color drawColor: "#8e8e93"

    property int section: 0
    readonly property var names: [sh.t("Maç"), sh.t("Kadro"), sh.t("Fikstür"), sh.t("Puan")]
    property string lineupSide: ""             // "" = bizim takım

    function resColor(r) { return r === "W" ? winColor : r === "L" ? lossColor : drawColor }
    function resText(r) { return r === "W" ? "G" : r === "L" ? "M" : "B" }          // Galibiyet, Mağlubiyet, Beraberlik
    function dateText(ms) { return sh.locale.toString(new Date(ms), "ddd d MMM  HH:mm") }
    function timeText(ms) { return sh.locale.toString(new Date(ms), "HH:mm") }
    function countdown(ms) {
        var left = Math.round((ms - sh.nowMs) / 60000)
        if (left <= 0) return sh.t("Başlıyor")
        if (left < 60) return sh.t("%1 dk sonra").arg(left)
        if (left < 24 * 60) return sh.t("%1 sa %2 dk sonra").arg(Math.floor(left / 60)).arg(left % 60)
        return dateText(ms)
    }
    function oppOf(m) { return m.us === "home" ? m.away : m.home }
    function scoreText(m) { return (m.home.score === null ? "–" : m.home.score) + " – " + (m.away.score === null ? "–" : m.away.score) }

    onLineupChanged: if (lineup && section === 0) section = 1
    // adanın boyu bölüme göre ayarlanır (main.qml panelH)
    onSectionChanged: sh.footballSection = section
    Component.onCompleted: sh.footballSection = section
    Connections {
        target: page.sh
        function onFootballSectionChanged() { if (page.section !== page.sh.footballSection) page.section = page.sh.footballSection }
    }

    // yok / kapalı / yükleniyor
    Column {
        visible: !page.ok
        anchors.centerIn: parent
        spacing: 8
        Ico {
            anchors.horizontalCenter: parent.horizontalCenter
            size: 40
            source: sh.ic("isle-football")
            tint: Qt.rgba(1, 1, 1, 0.4)
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.f.off ? sh.t("Maç takibi kapalı") : page.f.error ? sh.t("Maç verisi alınamadı") : sh.t("Yükleniyor…")
            color: Qt.rgba(1, 1, 1, 0.6)
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Text {
            visible: !!page.f.off
            renderType: Text.CurveRendering
            font.family: "Inter"
            anchors.horizontalCenter: parent.horizontalCenter
            text: sh.t("Ayarlar → Genel → Maç takibi")
            color: Qt.rgba(1, 1, 1, 0.4)
            font.pixelSize: 11
        }
    }

    ColumnLayout {
        visible: page.ok
        anchors.fill: parent
        spacing: 8

        // Bölüm seçici
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.11)
            LiquidPill {
                width: parent.width
                height: parent.height
                baseH: 22
                restAlpha: 0.17
                goalW: (parent.width - 6) / page.names.length
                goalX: 3 + page.section * goalW
                glassLayer: page.sh.glassLayer
                glassFrost: page.sh.glassFrost || 0.3
            }
            Row {
                anchors.fill: parent
                anchors.margins: 3
                Repeater {
                    model: page.names
                    Item {
                        required property string modelData
                        required property int index
                        width: parent.width / page.names.length
                        height: parent.height
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            anchors.centerIn: parent
                            text: modelData
                            color: page.section === index ? "white" : Qt.rgba(1, 1, 1, 0.55)
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        MouseArea { anchors.fill: parent; onClicked: page.section = index }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ---------------- Maç
            Item {
                visible: page.section === 0
                anchors.fill: parent
                readonly property var m: page.fmatch

                Text {
                    visible: !parent.m
                    anchors.centerIn: parent
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    text: sh.t("Yaklaşan maç yok")
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 13
                }
                RowLayout {
                    visible: !!parent.m
                    anchors.fill: parent
                    spacing: 10
                    // iki takım ve skor
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Repeater {
                            model: parent.parent.parent.m ? [parent.parent.parent.m.home, parent.parent.parent.m.away] : []
                            Column {
                                required property var modelData
                                required property int index
                                width: 120
                                x: index === 0 ? 0 : parent.width - width
                                y: 4
                                spacing: 4
                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 52; height: 52
                                    source: modelData.logo
                                    sourceSize: Qt.size(104, 104)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                }
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    renderType: Text.CurveRendering
                                    font.family: "Inter"
                                    text: modelData.name
                                    color: "white"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 6
                            spacing: 2
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                text: {
                                    var m = page.fmatch
                                    if (!m) return ""
                                    return m.state === "pre" ? page.timeText(m.date) : page.scoreText(m)
                                }
                                color: "white"
                                font.pixelSize: 30
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                text: {
                                    var m = page.fmatch
                                    if (!m) return ""
                                    if (m.state === "in") return m.clock || m.detail
                                    if (m.state === "post") return sh.t("Maç sona erdi")
                                    return page.countdown(m.date)
                                }
                                color: page.fmatch && page.fmatch.state === "in" ? page.winColor : Qt.rgba(1, 1, 1, 0.7)
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                text: page.fmatch ? page.fmatch.leagueName : ""
                                color: Qt.rgba(1, 1, 1, 0.5)
                                font.pixelSize: 11
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                text: page.fmatch && page.fmatch.state === "pre" ? page.dateText(page.fmatch.date) : ""
                                color: Qt.rgba(1, 1, 1, 0.5)
                                font.pixelSize: 11
                            }
                        }
                        // goller
                        Text {
                            visible: page.fmatch && page.fmatch.state !== "pre" && page.f.goals && page.f.goals.length > 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: parent.width - 260
                            horizontalAlignment: Text.AlignHCenter
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            text: (page.f.goals || []).map(function (g) { return g.text + " " + g.min }).join("  ·  ")
                            color: Qt.rgba(1, 1, 1, 0.55)
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: page.fmatch && page.fmatch.state === "pre" && page.fmatch.venue !== ""
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            text: page.fmatch ? page.fmatch.venue : ""
                            color: Qt.rgba(1, 1, 1, 0.4)
                            font.pixelSize: 10
                        }
                    }
                }
            }

            // ---------------- Kadro
            Item {
                visible: page.section === 1
                anchors.fill: parent
                readonly property var sides: page.lineup ? Object.keys(page.lineup) : []
                readonly property string side: {
                    if (!page.lineup) return ""
                    if (page.lineupSide && page.lineup[page.lineupSide]) return page.lineupSide
                    for (var k in page.lineup) if (page.lineup[k].ours) return k
                    return sides[0]
                }
                readonly property var ln: page.lineup && side ? page.lineup[side] : null

                Column {
                    visible: !parent.ln
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        text: sh.t("Kadro henüz açıklanmadı")
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        text: sh.t("Genellikle maçtan yaklaşık 1 saat önce burada görünür")
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.pixelSize: 11
                    }
                }

                RowLayout {
                    visible: !!parent.ln
                    anchors.fill: parent
                    spacing: 8
                    // saha
                    Rectangle {
                        id: pitch
                        Layout.fillWidth: true
                        Layout.minimumWidth: 200
                        Layout.fillHeight: true
                        radius: 12
                        color: Qt.rgba(0.12, 0.45, 0.25, 0.30)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.14)
                        clip: true
                        readonly property var rows: page.lineup && parent.parent.ln ? parent.parent.ln.rows : []

                        Rectangle {          // orta çizgi ve daire
                            x: parent.width / 2; width: 1; height: parent.height
                            color: Qt.rgba(1, 1, 1, 0.10)
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 34; height: 34; radius: 17
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                        }
                        Repeater {
                            model: pitch.rows
                            Item {
                                required property var modelData
                                required property int index
                                readonly property real colW: pitch.width / Math.max(1, pitch.rows.length)
                                x: index * colW
                                width: colW
                                height: pitch.height
                                Repeater {
                                    model: modelData
                                    Item {
                                        required property var modelData
                                        required property int index
                                        readonly property int count: parent.modelData.length
                                        width: parent.width
                                        height: 30
                                        y: Math.max(2, Math.min(pitch.height - height - 2, (pitch.height / count) * (index + 0.5) - 16))
                                        Rectangle {
                                            id: dot
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            y: 0
                                            width: 18; height: 18; radius: 9
                                            color: page.sh.glassLayer ? Qt.rgba(1, 1, 1, 0.9) : "white"
                                            Text {
                                                anchors.centerIn: parent
                                                renderType: Text.CurveRendering
                                                font.family: "Inter"
                                                text: modelData.n
                                                color: "#111"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                font.features: { "tnum": 1 }
                                            }
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: dot.bottom
                                            anchors.topMargin: 1
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            renderType: Text.CurveRendering
                                            font.family: "Inter"
                                            text: modelData.name
                                            color: "white"
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // takım seçici ve yedekler
                    ColumnLayout {
                        Layout.preferredWidth: 130
                        Layout.minimumWidth: 130
                        Layout.maximumWidth: 130
                        Layout.fillHeight: true
                        spacing: 4
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            text: parent.parent.parent.ln ? parent.parent.parent.ln.team : ""
                            color: "white"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            text: parent.parent.parent.ln ? parent.parent.parent.ln.formation : ""
                            color: page.accent
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            text: sh.t("Yedekler")
                            color: Qt.rgba(1, 1, 1, 0.45)
                            font.pixelSize: 10
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            wrapMode: Text.WordWrap
                            text: parent.parent.parent.ln ? parent.parent.parent.ln.subs.map(function (p) { return p.n + " " + p.name }).join("\n") : ""
                            color: Qt.rgba(1, 1, 1, 0.7)
                            font.pixelSize: 9
                            lineHeight: 1.05
                            elide: Text.ElideRight
                            maximumLineCount: 9
                        }
                        // rakip kadrosuna geç
                        Rectangle {
                            visible: parent.parent.parent.sides.length > 1
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            radius: 11
                            color: Qt.rgba(1, 1, 1, 0.12)
                            Text {
                                anchors.centerIn: parent
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                text: sh.t("Rakip kadro")
                                color: "white"
                                font.pixelSize: 11
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var cur = parent.parent.parent.parent.side
                                    page.lineupSide = cur === "home" ? "away" : "home"
                                }
                            }
                        }
                    }
                }
            }

            // ---------------- Fikstür
            RowLayout {
                visible: page.section === 2
                anchors.fill: parent
                spacing: 12
                Repeater {
                    model: [{ title: sh.t("Sıradaki maçlar"), rows: page.upcoming.slice(0, 4) },
                            { title: sh.t("Son sonuçlar"), rows: page.past.slice(0, 4) }]
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        spacing: 4
                        Text {
                            Layout.leftMargin: 4
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            text: modelData.title
                            color: Qt.rgba(1, 1, 1, 0.55)
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        Repeater {
                            model: modelData.rows
                            GlassCard {
                                required property var modelData
                                sh: page.sh
                                fill: 0.07
                                radius: 12
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8
                                    Image {
                                        Layout.preferredWidth: 24; Layout.preferredHeight: 24
                                        source: page.oppOf(modelData).logo
                                        sourceSize: Qt.size(48, 48)
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 5
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                renderType: Text.CurveRendering
                                                font.family: "Inter"
                                                text: page.oppOf(modelData).name
                                                color: "white"
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                            // ev sahibi / deplasman
                                            Rectangle {
                                                Layout.preferredWidth: venueText.implicitWidth + 8
                                                Layout.preferredHeight: 13
                                                radius: 6.5
                                                color: modelData.us === "home" ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                                                border.width: modelData.us === "home" ? 0 : 1
                                                border.color: Qt.rgba(1, 1, 1, 0.22)
                                                Text {
                                                    id: venueText
                                                    anchors.centerIn: parent
                                                    renderType: Text.CurveRendering
                                                    font.family: "Inter"
                                                    text: modelData.us === "home" ? sh.t("Ev") : sh.t("Dep")
                                                    color: Qt.rgba(1, 1, 1, 0.7)
                                                    font.pixelSize: 8
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            renderType: Text.CurveRendering
                                            font.family: "Inter"
                                            text: modelData.leagueName + (modelData.state === "pre" ? "  ·  " + page.dateText(modelData.date) : "")
                                            color: Qt.rgba(1, 1, 1, 0.5)
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }
                                    }
                                    Text {
                                        visible: modelData.state === "post"
                                        renderType: Text.CurveRendering
                                        font.family: "Inter"
                                        text: page.scoreText(modelData)
                                        color: "white"
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        font.features: { "tnum": 1 }
                                    }
                                    Rectangle {
                                        visible: modelData.state === "post"
                                        Layout.preferredWidth: 18; Layout.preferredHeight: 18
                                        radius: 9
                                        color: page.resColor(modelData.result)
                                        Text {
                                            anchors.centerIn: parent
                                            renderType: Text.CurveRendering
                                            font.family: "Inter"
                                            text: page.resText(modelData.result)
                                            color: "#111"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                        }
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // ---------------- Puan
            ColumnLayout {
                id: tableView
                visible: page.section === 3
                anchors.fill: parent
                spacing: 4
                readonly property var tbl: page.tables.length > page.tableIx ? page.tables[page.tableIx] : null
                // fare üstündeki satır; yoksa takımın kendi satırı
                property var hoverRow: null
                readonly property var shownRow: hoverRow ? hoverRow : (tbl ? tbl.rows[tbl.idx] : null)

                function focusTeam(animate) {
                    if (!tbl) return
                    var target = Math.max(0, Math.min(tlist.contentHeight - tlist.height, (tbl.idx - 2) * 27))
                    if (animate) scrollAnim.to = target, scrollAnim.restart()
                    else tlist.contentY = target
                }
                onTblChanged: Qt.callLater(function () { focusTeam(false) })
                onVisibleChanged: if (visible) Qt.callLater(function () { focusTeam(false) })

                Text {
                    visible: !parent.tbl
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 30
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    text: sh.t("Puan durumu yok")
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 13
                }
                // yarışma seçici (lig, Şampiyonlar Ligi…)
                Row {
                    visible: page.tables.length > 1
                    spacing: 6
                    Repeater {
                        model: page.tables
                        Rectangle {
                            required property var modelData
                            required property int index
                            width: tlabel.implicitWidth + 18
                            height: 20
                            radius: 10
                            color: page.tableIx === index ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.08)
                            Text {
                                id: tlabel
                                anchors.centerIn: parent
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                text: modelData.name
                                color: page.tableIx === index ? "white" : Qt.rgba(1, 1, 1, 0.6)
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                            MouseArea { anchors.fill: parent; onClicked: page.tableIx = index }
                        }
                    }
                }

                // tablo: fare tekerleğiyle kayar
                FadeEdges { id: tfade; view: tlist; fadeTop: 22; fadeBottom: 22 }
                ListView {
                    id: tlist
                    visible: !!tableView.tbl
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 3
                    boundsBehavior: Flickable.StopAtBounds
                    model: tableView.tbl ? tableView.tbl.rows : []
                    NumberAnimation { id: scrollAnim; target: tlist; property: "contentY"; duration: 380; easing.type: Easing.OutCubic }

                    HoverHandler { onHoveredChanged: if (!hovered) tableView.hoverRow = null }

                    delegate: GlassCard {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool mine: modelData.id === page.team.id
                        sh: page.sh
                        width: tlist.width
                        fill: mine ? 0.18 : rowHover.hovered ? 0.12 : 0.06
                        radius: 9
                        height: 24
                        opacity: tfade.factor(row)
                        HoverHandler { id: rowHover; onHoveredChanged: if (hovered) tableView.hoverRow = row.modelData }
                        Rectangle {          // bölge çizgisi: Şampiyonlar Ligi, düşme…; takım satırı vurgu renginde
                            anchors.left: parent.left
                            anchors.leftMargin: 3
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3; height: 14; radius: 1.5
                            color: row.modelData.zone ? row.modelData.zone : row.mine ? page.accent : "transparent"
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 8
                            Text {
                                Layout.preferredWidth: 16
                                horizontalAlignment: Text.AlignRight
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                text: row.modelData.rank
                                color: Qt.rgba(1, 1, 1, 0.55)
                                font.pixelSize: 11
                                font.features: { "tnum": 1 }
                            }
                            Image {
                                Layout.preferredWidth: 16; Layout.preferredHeight: 16
                                source: row.modelData.logo
                                sourceSize: Qt.size(32, 32)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            Text {
                                Layout.fillWidth: true
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                text: row.modelData.name
                                color: "white"
                                font.pixelSize: 12
                                font.weight: row.mine ? Font.Bold : Font.Normal
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.preferredWidth: 22
                                horizontalAlignment: Text.AlignRight
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                text: row.modelData.p
                                color: Qt.rgba(1, 1, 1, 0.6)
                                font.pixelSize: 11
                                font.features: { "tnum": 1 }
                            }
                            Text {
                                Layout.preferredWidth: 28
                                horizontalAlignment: Text.AlignRight
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                text: (row.modelData.gd > 0 ? "+" : "") + row.modelData.gd
                                color: row.modelData.gd > 0 ? page.winColor : row.modelData.gd < 0 ? page.lossColor : Qt.rgba(1, 1, 1, 0.6)
                                font.pixelSize: 11
                                font.features: { "tnum": 1 }
                            }
                            Text {
                                Layout.preferredWidth: 24
                                horizontalAlignment: Text.AlignRight
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                text: row.modelData.pts
                                color: "white"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }
                // üstünde durulan satırın özeti
                RowLayout {
                    visible: !!tableView.shownRow
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.rightMargin: 10
                    spacing: 8
                    Rectangle {
                        Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4
                        visible: !!tableView.shownRow && tableView.shownRow.zone !== ""
                        color: tableView.shownRow ? tableView.shownRow.zone : "transparent"
                    }
                    Text {
                        Layout.fillWidth: true
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        elide: Text.ElideRight
                        text: {
                            var r = tableView.shownRow
                            if (!r) return ""
                            return r.name + "  ·  " + sh.t("%1 G  %2 B  %3 M").arg(r.w).arg(r.d).arg(r.l)
                                + (r.zoneName ? "  ·  " + r.zoneName : "")
                        }
                        color: Qt.rgba(1, 1, 1, 0.65)
                        font.pixelSize: 10
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        text: sh.t("O") + "   " + sh.t("AV") + "   " + sh.t("P")
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.pixelSize: 9
                    }
                }
            }
        }
    }
}
