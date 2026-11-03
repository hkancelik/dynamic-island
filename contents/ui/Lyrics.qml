import QtQuick
import QtQuick.Layouts

// Senkron şarkı sözleri: solda küçük oynatıcı, sağda sözler.
// Söylenen satır büyük ve parlak, gelenler mesafeyle solar, söylenenler soluk;
// sözsüz aralar nefes alan üç nokta. Satıra tıkla: şarkı oraya atlar.
Item {
    id: lp

    property var sh

    readonly property var lyr: sh.lyr
    readonly property var lines: lyr.lines || []
    readonly property bool synced: lyr.status === "synced"
    readonly property int ahead: 250      // satır biraz erken yansın

    // Şu anki satır: başlangıcı geçmiş en son satır (ikili arama)
    readonly property int cur: {
        if (!synced || lines.length === 0) return -1
        var t = sh.pos + ahead, lo = 0, hi = lines.length - 1, ans = -1
        while (lo <= hi) {
            var mid = (lo + hi) >> 1
            if (lines[mid][0] <= t) { ans = mid; lo = mid + 1 } else hi = mid - 1
        }
        return ans
    }

    // Söz görünümündeyken konum sık güncellensin (satır geçişi en çok 1/4 sn gecikir)
    Timer {
        interval: 250
        repeat: true
        running: lp.visible && sh.playing
        onTriggered: sh.updatePos()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 26

        // Sol: küçük oynatıcı
        ColumnLayout {
            Layout.preferredWidth: 232
            Layout.maximumWidth: 232
            Layout.fillHeight: true
            spacing: 8

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ArtImage {
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    radius: 12
                    source: sh.media.artUrl || ""
                    MouseArea { anchors.fill: parent; onClicked: sh.send("raise") }
                }
                Column {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: parent.width
                        text: sh.media.title || sh.t("Bilinmeyen parça")
                        color: "white"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: parent.width
                        text: sh.media.artist || sh.media.player || ""
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
            }

            IslandSlider {
                sh: lp.sh
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                barHeight: 3
                knob: sh.media.canSeek === true
                trackColor: Qt.rgba(1, 1, 1, 0.2)
                fillColor: "white"
                interactive: sh.media.canSeek === true
                smooth: false
                value: sh.media.length > 0 ? sh.pos / sh.media.length : 0
                onCommitted: v => sh.send("seek", v * sh.media.length)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                CtlButton {
                    width: 28; height: 28; iconSize: 15
                    icon: sh.ic("isle-lyrics-fill")
                    tint: "white"
                    onClicked: sh.lyricsOn = false
                }
                Item { Layout.fillWidth: true }
                CtlButton {
                    width: 34; height: 34; iconSize: 18
                    icon: sh.ic("isle-backward-symbolic")
                    enabledBtn: sh.media.canPrev !== false
                    onClicked: sh.send("prev")
                }
                CtlButton {
                    width: 36; height: 36; iconSize: 20
                    icon: sh.playing ? sh.ic("isle-pause-symbolic") : sh.ic("isle-play-symbolic")
                    onClicked: sh.send("play_pause")
                }
                CtlButton {
                    width: 34; height: 34; iconSize: 18
                    icon: sh.ic("isle-forward-symbolic")
                    enabledBtn: sh.media.canNext !== false
                    onClicked: sh.send("next")
                }
                Item { Layout.fillWidth: true }
                Item { width: 28; height: 28 }
            }

            // Hangi kayıttan geldiği: yanlış şarkı eşleşirse fark edilsin ("Sanatçı – Şarkı")
            Text {
                Layout.fillWidth: true
                visible: (lyr.status === "synced" || lyr.status === "plain") && !!lyr.match
                renderType: Text.CurveRendering
                font.family: "Inter"
                text: "LRCLIB · " + (lyr.match || "")
                color: Qt.rgba(1, 1, 1, 0.3)
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            Item { Layout.fillHeight: true }
        }

        // Sağ: sözler
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // Kenarlarda satırlar erir (siyah şerit değil; albüm ışığının üstünde de temiz görünür)
            FadeEdges {
                id: fade
                view: list
                fadeTop: lp.synced ? 30 : 14
                fadeBottom: lp.synced ? 38 : 18
            }
            ListView {
                id: list
                objectName: "lyricsList"
                anchors.fill: parent
                visible: lp.lines.length > 0 && (lp.synced || lyr.status === "plain")
                model: lp.lines
                spacing: 6
                interactive: !lp.synced
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 4000
                // Söylenen satır yukarıdan %36'da durur. ListView'in vurgu aralığı iki satıra
                // sarılan sözlerde hiç durulmayıp sürekli kaydırıyordu (saniyede 60 çizim):
                // bunun yerine satır değişince bir kez kayan animasyon.
                header: Item { height: lp.synced ? list.height * 0.36 : 4 }
                footer: Item { height: lp.synced ? list.height * 0.64 : 0 }
                NumberAnimation on contentY {
                    id: follow
                    running: false
                    duration: 520
                    easing.type: Easing.OutCubic
                }
                function followCur(animate) {
                    if (!lp.synced || lp.cur < 0) return
                    var it = itemAtIndex(lp.cur)
                    if (!it) { positionViewAtIndex(lp.cur, ListView.Beginning); it = itemAtIndex(lp.cur) }
                    if (!it) return
                    var target = it.y - height * 0.36
                    follow.stop()
                    if (animate && visible) { follow.from = contentY; follow.to = target; follow.start() }
                    else contentY = target
                }
                Connections {
                    target: lp
                    function onCurChanged() { list.followCur(true) }
                    function onVisibleChanged() { if (lp.visible) Qt.callLater(list.followCur, false) }
                }
                onCountChanged: Qt.callLater(followCur, false)

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property int d: index - lp.cur
                    readonly property bool now: lp.synced && d === 0
                    readonly property bool pause: lp.synced && modelData[1] === ""
                    readonly property real edge: fade.factor(row)       // görünüm kenarında 0
                    width: list.width
                    height: pause ? 22 : words.height

                    opacity: !lp.synced ? 0.8
                           : now ? 1
                           : d < 0 ? 0.3
                           : d === 1 ? 0.59 : d === 2 ? 0.45 : 0.35
                    Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

                    Text {
                        id: words
                        opacity: row.edge
                        visible: !row.pause
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: parent.width
                        text: row.modelData[1]
                        color: "white"
                        wrapMode: Text.WordWrap
                        font.pixelSize: lp.synced ? 19 : 15
                        font.weight: Font.Bold
                        font.letterSpacing: -0.3
                        transformOrigin: Item.Left
                        scale: !lp.synced || row.now ? 1 : 0.93
                        Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                    }

                    // Sözsüz ara: nefes alan üç nokta
                    Row {
                        visible: row.pause
                        opacity: row.edge
                        x: 3                       // büyüyen (1,35×) sol nokta liste kenarında kırpılmasın
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                objectName: "pauseDot" + index
                                width: 7; height: 7; radius: 3.5
                                color: "white"
                                SequentialAnimation on scale {
                                    running: row.pause && row.now && sh.playing && lp.visible
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 180 }
                                    NumberAnimation { to: 1.35; duration: 600; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: lp.synced && sh.media.canSeek === true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: sh.send("seek", row.modelData[0])
                    }
                }
            }

            // Söz yokken durum
            Column {
                visible: !list.visible
                anchors.centerIn: parent
                spacing: 8
                readonly property var st: ({
                    "loading": ["", sh.t("Sözler aranıyor"), ""],
                    "not_found": ["isle-lyrics", sh.t("Bu şarkının sözü yok"), sh.t("Sözler LRCLIB'den gelir")],
                    "instrumental": ["isle-music", sh.t("Enstrümantal"), sh.t("Eşlik edecek söz yok")],
                    "error": ["isle-lyrics", sh.t("Sözlere ulaşılamıyor"), sh.t("Bağlantını kontrol et · birazdan yeniden denenecek")]
                })[lyr.status] || ["", sh.t("Sözler aranıyor"), ""]
                Row {
                    visible: parent.st[0] === ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            width: 7; height: 7; radius: 3.5
                            color: "white"
                            opacity: 0.5
                            SequentialAnimation on opacity {
                                // yalnızca "aranıyor" yazısı görünürken (gizliyken de çizim yaptırıyordu)
                                running: lp.visible && !list.visible && lyr.status === "loading"
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 180 }
                                NumberAnimation { to: 1; duration: 600 }
                                NumberAnimation { to: 0.4; duration: 600 }
                            }
                        }
                    }
                }
                Ico {
                    visible: parent.st[0] !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: parent.st[0] ? sh.ic(parent.st[0]) : ""
                    size: 26
                    tint: "white"
                    opacity: 0.35
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.st[1]
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    visible: parent.st[2] !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.st[2]
                    color: Qt.rgba(1, 1, 1, 0.4)
                    font.pixelSize: 11
                }
                // Bulunamadı / hata: elle ara ("sanatçı şarkı"); sonuç bu şarkı için saklanır
                Rectangle {
                    visible: lyr.status === "not_found" || lyr.status === "error"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 236; height: 28; radius: 14
                    color: Qt.rgba(1, 1, 1, manualInput.activeFocus ? 0.20 : 0.11)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    TextInput {
                        id: manualInput
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        color: "white"
                        font.family: "Inter"
                        font.pixelSize: 12
                        selectByMouse: true
                        clip: true
                        onAccepted: { if (text.trim() !== "") { sh.send("lyrics_search", text.trim()); text = "" } }
                        Text {
                            visible: !manualInput.text && !manualInput.activeFocus
                            anchors.verticalCenter: parent.verticalCenter
                            text: sh.t("Elle ara: sanatçı şarkı")
                            color: Qt.rgba(1, 1, 1, 0.4)
                            font: manualInput.font
                        }
                    }
                }
            }
        }
    }
}
