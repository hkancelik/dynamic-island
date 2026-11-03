import QtQuick
import QtQuick.Layouts

// Komut paleti (Alt+Space / `island palette`): ada büyüyüp bir arama kutusuna dönüşür.
//   Arka uç (/search, iki aşama): uygulamalar, birimler, web kısayolları, konumlar, kabuk, süreçler,
//   oturum, sistem ayarları, son belgeler, yer imleri, saat, renk, karakter, dosyalar ("fast") ve
//   KRunner eklentileri: pencereler, tarayıcı sekmeleri ve geçmişi ("slow", biraz sonra gelir).
//   Arayüzde: hesap makinesi, "5m çay" zamanlayıcı, ada komutları, sekmeler, pano, web araması.
//   ↑/↓ seç, Enter çalıştır (riskli işlemler ikinci Enter'la), Esc kapat.
Item {
    id: pal

    property var sh
    property bool open: false
    property string query: ""
    property int sel: 0
    property var remote: []
    property string remoteFor: "\u0000"
    property var remoteSlow: []
    property string slowFor: "\u0000"
    property int armed: -1           // onay bekleyen satır (kapat, yeniden başlat, süreç sonlandır)
    readonly property int maxRows: 8
    readonly property int rows: Math.min(maxRows, results.length)
    // Ada yüksekliği için: arama satırı + sonuçlar
    readonly property int wantH: 64 + (rows > 0 ? rows * 46 + 12 : 0)

    onOpenChanged: {
        if (open) {
            input.text = ""
            query = ""
            sel = 0
            armed = -1
            fetch()
            focusTimer.start()
        }
    }
    Timer { id: focusTimer; interval: 30; onTriggered: input.forceActiveFocus() }
    // `island palette "metin"`: aramayı doldurarak aç
    function prefill(q) { input.text = q; input.cursorPosition = q.length }

    // -- eşleşme (palette.py'deki score ile aynı fikir, daha kısa)
    function fold(s) {
        return String(s).replace(/[ıİ]/g, "i").replace(/[şŞ]/g, "s").replace(/[ğĞ]/g, "g")
            .replace(/[üÜ]/g, "u").replace(/[öÖ]/g, "o").replace(/[çÇ]/g, "c").toLowerCase()
    }
    function score(q, text) {
        q = fold(q).trim(); var t = fold(text)
        if (!q || !t) return 0
        if (t === q) return 100
        if (t.indexOf(q) === 0) return 90
        var words = t.split(/[\s\-_/]+/)
        for (var i = 0; i < words.length; i++) if (words[i].indexOf(q) === 0) return 75
        var k = t.indexOf(q)
        return k >= 0 ? 60 - Math.min(10, k) : 0
    }

    // -- hesap makinesi (Pano aramasındakiyle aynı kurallar)
    function calc(q) {
        q = q.trim().replace(/,/g, ".").replace(/×/g, "*").replace(/÷/g, "/")
        if (q.length < 3 || !/^[0-9+\-*\/().%\s^]+$/.test(q) || !/[0-9]\s*[-+*\/%^]\s*[0-9(]|[0-9]%/.test(q)) return null
        try {
            var e = q.replace(/\^/g, "**").replace(/(\d+(?:\.\d+)?)%/g, "($1/100)")
            var v = Function('"use strict"; return (' + e + ')')()
            if (typeof v !== "number" || !isFinite(v)) return null
            var out = Math.abs(v) >= 1e15 || (v !== 0 && Math.abs(v) < 1e-6) ? v.toExponential(6) : String(Math.round(v * 1e10) / 1e10)
            return sh.lang === "tr" ? out.replace(".", ",") : out
        } catch (err) { return null }
    }

    // "5m çay", "25 dk", "90s", "1:30 yumurta" -> { duration, label }
    function timerOf(q) {
        var m = /^\s*(\d+:\d{1,2}|\d+\s*(?:s|sn|sec|m|dk|min|h|sa|saat))\s*(.*)$/i.exec(q)
        if (!m) return null
        var d = m[1].replace(/\s+/g, "").toLowerCase().replace(/(sn|sec)$/, "s").replace(/(dk|min)$/, "m").replace(/(sa|saat)$/, "h")
        return { duration: d, label: m[2].trim() }
    }

    readonly property var commands: [
        { t: sh.t("Odak sayacı"), k: "focus pomodoro odak", icon: sh.ic("isle-timer"), cmd: "focus_toggle", suggest: true },
        { t: sh.t("Rahatsız Etme"), k: "dnd do not disturb sessiz rahatsiz", icon: sh.ic("isle-moon"), cmd: "toggle_dnd", suggest: true },
        { t: sh.t("Ekran kaydı"), k: "record screen kayit", icon: sh.ic("isle-record-symbolic"), cmd: "rec_toggle" },
        { t: sh.t("Ekran görüntüsü"), k: "screenshot goruntu", icon: "camera-photo-symbolic", cmd: "screenshot" },
        { t: sh.t("Adayı gizle / göster"), k: "hide show gizle goster", icon: "view-hidden", cmd: "toggle_hide" },
        { t: sh.t("Oynat / Duraklat"), k: "play pause oynat duraklat muzik", icon: sh.ic("isle-play-symbolic"), cmd: "play_pause" },
        { t: sh.t("Sonraki parça"), k: "next skip sonraki", icon: sh.ic("isle-forward-symbolic"), cmd: "next" },
        { t: sh.t("Müzik"), k: "music muzik", icon: sh.ic("isle-music"), tab: 0 },
        { t: sh.t("Bildirimler"), k: "notifications bildirim", icon: sh.ic("isle-bell"), tab: 1 },
        { t: sh.t("Takvim"), k: "calendar takvim etkinlik", icon: sh.ic("isle-calendar"), tab: 3, suggest: true },
        { t: sh.t("Kontrol"), k: "controls wifi bluetooth parlaklik ses", icon: sh.ic("isle-sun-symbolic"), tab: 4 },
        { t: sh.t("Sistem"), k: "system cpu ram sistem", icon: sh.ic("isle-gauge"), tab: 6 },
        { t: sh.t("Pano"), k: "clipboard pano", icon: sh.ic("isle-clipboard"), tab: 7, sub: 0 },
        { t: sh.t("Notlar"), k: "notes not", icon: sh.ic("isle-text"), tab: 7, sub: 3 },
        { t: sh.t("Ayarlar"), k: "settings ayarlar tercihler", icon: sh.ic("isle-settings"), tab: 8, suggest: true }
    ]

    readonly property var results: {
        var q = query.trim()
        var out = []
        if (q) {
            var c = calc(q)
            if (c !== null) out.push({ kind: "calc", title: c, subtitle: q + " =", icon: sh.ic("isle-plus-symbolic"), mono: true, s: 1000 })
            var tm = timerOf(q)
            if (tm) out.push({ kind: "timer", title: sh.t("Zamanlayıcı kur: %1").arg(tm.duration) + (tm.label ? " · " + tm.label : ""),
                               subtitle: sh.t("Bitince adada ses ve bildirim"), icon: sh.ic("isle-timer"), mono: true,
                               duration: tm.duration, label: tm.label, s: 999 })
        }
        var scored = []
        for (var i = 0; i < commands.length; i++) {
            var cm = commands[i]
            var s = q ? Math.max(score(q, cm.t), score(q, cm.k) * 0.9) : 0
            if (s >= 55) scored.push({ kind: "cmd", title: cm.t, subtitle: cm.tab !== undefined ? sh.t("Sekmeyi aç") : sh.t("Komut"),
                                       icon: cm.icon, mono: true, cmd: cm.cmd, tab: cm.tab, sub: cm.sub, s: s + 2 })
        }
        // Arka uç sonuçları olduğu gibi (çalıştırırken aynen geri gönderilir; arka uç doğrular)
        var lists = [remoteFor === query ? remote : [], slowFor === query ? remoteSlow : []]
        for (var li = 0; li < lists.length; li++) {
            for (var j = 0; j < lists[li].length; j++) {
                var r = lists[li][j]
                var it = {}
                for (var key in r) it[key] = r[key]
                it.remote = true
                it.subtitle = r.subtitle || (r.kind === "app" ? sh.t("Uygulama") : "")
                it.mono = String(r.icon || "").indexOf("isle-") === 0
                if (it.mono) it.icon = sh.ic(r.icon)
                it.s = r.score
                scored.push(it)
            }
        }
        if (q) {
            var n = 0
            for (var k = 0; k < sh.clip.length && n < 3; k++) {
                var txt = String(sh.clip[k].text || "")
                if (fold(txt).indexOf(fold(q)) >= 0) {
                    n++
                    scored.push({ kind: "clip", index: k, title: txt.replace(/\s+/g, " ").slice(0, 90),
                                  subtitle: sh.t("Pano · kopyalamak için Enter"), icon: sh.ic("isle-clipboard"), mono: true, s: 35 })
                }
            }
        }
        if (!q) {   // boşken öneriler: sık açılan uygulamalar (arka uçtan) + birkaç komut
            var n2 = 0
            for (var p = 0; p < commands.length; p++) {
                var pc = commands[p]
                if (!pc.suggest) continue
                scored.push({ kind: "cmd", title: pc.t, subtitle: pc.tab !== undefined ? sh.t("Sekmeyi aç") : sh.t("Komut"),
                              icon: pc.icon, mono: true, cmd: pc.cmd, tab: pc.tab, sub: pc.sub, s: 10 - n2++ })
            }
        }
        scored.sort(function (a, b) { return b.s - a.s })
        out = out.concat(scored)
        if (q) out.push({ kind: "web", title: sh.t("Web'de ara: %1").arg(q), subtitle: "DuckDuckGo", icon: sh.ic("isle-globe"), mono: true, s: 0 })
        return out.slice(0, maxRows)
    }
    onResultsChanged: { if (sel >= results.length) sel = Math.max(0, results.length - 1); armed = -1 }

    function kindLabel(k, it) {
        if (k === "runner" && it) {     // KRunner eklentisi: kaynağın adı
            var p = String(it.path || "")
            return p === "/WindowsRunner" ? sh.t("Pencere") : p === "/TabsRunner" ? sh.t("Sekme")
                 : p === "/HistoryRunner" ? sh.t("Geçmiş") : "KRunner"
        }
        return k === "app" ? sh.t("Uygulama") : k === "file" || k === "path" ? sh.t("Dosya") : k === "calc" ? sh.t("Hesap")
             : k === "timer" ? sh.t("Zamanlayıcı") : k === "clip" ? sh.t("Pano") : k === "web" || k === "url" ? "Web"
             : k === "copy" ? sh.t("Kopyala") : k === "shell" ? sh.t("Kabuk") : k === "kill" ? sh.t("Süreç")
             : k === "session" ? sh.t("Oturum") : k === "kcm" ? sh.t("Ayar") : sh.t("Komut")
    }

    // İki istek: "fast" hemen gelir, "slow" (pencereler, sekmeler, geçmiş) biraz sonra eklenir
    function fetch() {
        if (!sh.token) return
        ask("fast")
        if (query.trim().length >= 2) ask("slow")
        else { remoteSlow = []; slowFor = query }
    }
    function ask(part) {
        var x = new XMLHttpRequest()
        x.open("GET", sh.endpoint + "/search?part=" + part + "&q=" + encodeURIComponent(query))
        x.setRequestHeader("X-Island", sh.token)
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE || x.status !== 200) return
            try {
                var r = JSON.parse(x.responseText)
                if (r.q !== pal.query) return
                if (part === "slow") { pal.remoteSlow = r.r; pal.slowFor = r.q }
                else { pal.remote = r.r; pal.remoteFor = r.q }
            } catch (e) {}
        }
        x.send()
    }
    Timer { id: debounce; interval: 60; onTriggered: pal.fetch() }

    function run(it, row) {
        if (!it) return
        // riskli işlemler: ilk Enter kurar, ikinci Enter çalıştırır
        if (it.confirm && armed !== row) { armed = row; return }
        if (it.remote) {
            var payload = {}
            for (var k in it) if (k !== "title" && k !== "subtitle" && k !== "s" && k !== "mono" && k !== "remote") payload[k] = it[k]
            sh.send("palette_run", payload)
            if (it.kind === "copy") sh.toast(sh.t("Panoya kopyalandı"), "dialog-ok-apply")
        }
        else if (it.kind === "calc") { sh.send("copy_text", it.title); sh.toast(sh.t("Sonuç kopyalandı"), "dialog-ok-apply") }
        else if (it.kind === "timer") sh.send("timer_start", { duration: it.duration, title: it.label })
        else if (it.kind === "clip") sh.send("clip_copy", it.index)
        else if (it.kind === "web") sh.send("web_search", query)
        else if (it.cmd) sh.send(it.cmd)
        sh.paletteOpen = false
        if (it.kind === "cmd" && it.tab !== undefined) {
            sh.tab = it.tab
            if (it.sub !== undefined) { if (it.tab === 7) sh.toolsSub = it.sub; else sh.settingsSub = it.sub }
            sh.panelOpen = true
        }
    }

    // -- arama satırı
    Item {
        id: bar
        width: parent.width
        height: 58
        Ico {
            id: glass
            x: 22
            anchors.verticalCenter: parent.verticalCenter
            source: sh.ic("isle-search")
            size: 18
            tint: Qt.rgba(1, 1, 1, 0.55)
        }
        TextInput {
            id: input
            anchors.left: glass.right
            anchors.leftMargin: 12
            anchors.right: escHint.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
            font.family: "Inter"
            font.pixelSize: 19
            font.weight: Font.Medium
            selectionColor: Qt.rgba(1, 1, 1, 0.25)
            selectByMouse: true
            clip: true
            onTextChanged: { pal.query = text; pal.sel = 0; debounce.restart() }
            Keys.onDownPressed: pal.sel = Math.min(pal.results.length - 1, pal.sel + 1)
            Keys.onUpPressed: pal.sel = Math.max(0, pal.sel - 1)
            Keys.onReturnPressed: pal.run(pal.results[pal.sel], pal.sel)
            Keys.onEnterPressed: pal.run(pal.results[pal.sel], pal.sel)
            Keys.onEscapePressed: sh.paletteOpen = false
            Keys.onTabPressed: pal.sel = (pal.sel + 1) % Math.max(1, pal.results.length)
            Text {
                visible: !input.text
                anchors.verticalCenter: parent.verticalCenter
                text: sh.t("Ara, hesapla ya da bir komut yaz…")
                color: Qt.rgba(1, 1, 1, 0.35)
                font: input.font
            }
        }
        Rectangle {
            id: escHint
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            width: escText.implicitWidth + 12; height: 20; radius: 6
            color: Qt.rgba(1, 1, 1, 0.08)
            Text {
                id: escText
                anchors.centerIn: parent
                text: "esc"
                color: Qt.rgba(1, 1, 1, 0.45)
                font.family: "Inter"
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }
        Rectangle {   // ayraç
            visible: pal.rows > 0
            anchors.bottom: parent.bottom
            x: 16; width: parent.width - 32; height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }
    }

    // -- sonuçlar
    Column {
        anchors.top: bar.bottom
        anchors.topMargin: 6
        x: 8
        width: parent.width - 16
        Repeater {
            model: pal.results
            Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool on: pal.sel === index
                readonly property bool arming: pal.armed === index
                width: parent.width
                height: 46
                radius: 12
                color: arming ? Qt.rgba(1, 0.27, 0.23, 0.22) : on ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                Behavior on color { ColorAnimation { duration: 90 } }

                Rectangle {
                    id: badge
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30; radius: 8
                    color: row.modelData.swatch ? row.modelData.swatch
                         : row.modelData.mono || row.modelData.glyph ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                    border.width: row.modelData.swatch ? 1 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.25)
                    Text {      // karakter sonucu: karakterin kendisi
                        visible: !!row.modelData.glyph
                        anchors.centerIn: parent
                        text: row.modelData.glyph || ""
                        color: "white"
                        font.pixelSize: 17
                    }
                    Ico {
                        visible: row.modelData.mono === true && !row.modelData.glyph
                        anchors.centerIn: parent
                        source: row.modelData.icon || ""
                        size: 15
                        tint: "white"
                    }
                    AppIcon {
                        visible: row.modelData.mono !== true && !row.modelData.swatch && !row.modelData.glyph
                        anchors.centerIn: parent
                        size: 28
                        source: row.modelData.icon || ""
                    }
                }
                Column {
                    anchors.left: badge.right
                    anchors.leftMargin: 12
                    anchors.right: kind.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        renderType: Text.CurveRendering
                        width: parent.width
                        text: row.modelData.title
                        color: "white"
                        font.family: "Inter"
                        font.pixelSize: row.modelData.kind === "calc" ? 17 : 14
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        elide: Text.ElideRight
                    }
                    Text {
                        renderType: Text.CurveRendering
                        visible: text !== ""
                        width: parent.width
                        text: row.modelData.subtitle || ""
                        color: Qt.rgba(1, 1, 1, 0.45)
                        font.family: "Inter"
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                    }
                }
                Text {
                    id: kind
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.arming ? sh.t("Onayla ↵") : row.on ? "↵" : pal.kindLabel(row.modelData.kind, row.modelData)
                    color: row.arming ? "#ff6961" : Qt.rgba(1, 1, 1, row.on ? 0.7 : 0.3)
                    font.family: "Inter"
                    font.pixelSize: row.on ? 14 : 11
                    font.weight: Font.Medium
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: pal.sel = row.index
                    onClicked: pal.run(row.modelData, row.index)
                }
            }
        }
    }
}
