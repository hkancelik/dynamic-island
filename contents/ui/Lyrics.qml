import QtQuick
import QtQuick.Layouts

// Senkron şarkı sözleri (Isle düzeni): solda küçük oynatıcı, sağda sözler.
// Söylenen satır büyük ve parlak, gelenler mesafeyle solar, söylenenler soluk;
// sözsüz aralar nefes alan üç nokta. Satıra tıkla: şarkı oraya atlar.
Item {
    id: lp

    property var sh

    readonly property var lyr: sh.lyr
    readonly property var lines: lyr.lines || []
    readonly property bool synced: lyr.status === "synced"
    readonly property int ahead: 250      // satır biraz erken yansın (Isle gibi)

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

    // Söz görünümündeyken konum sık güncellensin (satır geçişleri akıcı olsun)
    Timer {
        interval: 100
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
                        text: sh.media.title || "Bilinmeyen parça"
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
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                barHeight: 3
                knob: sh.media.canSeek === true
                trackColor: Qt.rgba(1, 1, 1, 0.2)
                fillColor: "white"
                interactive: sh.media.canSeek === true
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

            Item { Layout.fillHeight: true }
        }

        // Sağ: sözler
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: list
                anchors.fill: parent
                visible: lp.lines.length > 0 && (lp.synced || lyr.status === "plain")
                model: lp.lines
                spacing: 6
                interactive: !lp.synced
                boundsBehavior: Flickable.StopAtBounds
                // Söylenen satır yukarıdan %36'da durur
                highlightRangeMode: lp.synced ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
                preferredHighlightBegin: height * 0.36
                preferredHighlightEnd: height * 0.36 + 30
                highlightMoveDuration: 520
                highlightMoveVelocity: -1
                currentIndex: lp.synced ? Math.max(0, lp.cur) : 0
                header: Item { height: lp.synced ? 0 : 4 }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property int d: index - lp.cur
                    readonly property bool now: lp.synced && d === 0
                    readonly property bool pause: lp.synced && modelData[1] === ""
                    width: list.width
                    height: pause ? 22 : words.height

                    opacity: !lp.synced ? 0.8
                           : now ? 1
                           : d < 0 ? 0.3
                           : d === 1 ? 0.59 : d === 2 ? 0.45 : 0.35
                    Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

                    Text {
                        id: words
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
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                width: 7; height: 7; radius: 3.5
                                color: "white"
                                SequentialAnimation on scale {
                                    running: row.now && sh.playing && lp.visible
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

            // Kenarlarda solma
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                height: 20
                gradient: Gradient {
                    GradientStop { position: 0; color: "black" }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 26
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: "black" }
                }
            }

            // Söz yokken durum
            Column {
                visible: !list.visible
                anchors.centerIn: parent
                spacing: 8
                readonly property var st: ({
                    "loading": ["", "Sözler aranıyor", ""],
                    "not_found": ["isle-lyrics", "Bu şarkının sözü yok", "Sözler LRCLIB'den gelir"],
                    "instrumental": ["isle-music", "Enstrümantal", "Eşlik edecek söz yok"],
                    "error": ["isle-lyrics", "Sözlere ulaşılamıyor", "Bağlantını kontrol et · birazdan yeniden denenecek"]
                })[lyr.status] || ["", "Sözler aranıyor", ""]
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
                                running: lp.visible
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
            }
        }
    }
}
