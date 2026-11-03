import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Window
import org.kde.layershell as LayerShell
import "lang_en.js" as En

Window {
    id: root

    color: "transparent"
    title: "dynamic-island"
    // launch.sh ana ekranın adını argüman olarak verir; yoksa Qt'nin birincil ekranı.
    // Qt pencerenin ekranını geometrisinden seçtiği için konum da o ekrana taşınır (yoksa eDP'ye düşer).
    readonly property var targetScreen: {
        const want = Qt.application.arguments[Qt.application.arguments.length - 2]
        for (const s of Qt.application.screens)
            if (s.name === want) return s
        return Qt.application.screens[0]
    }
    flags: Qt.FramelessWindowHint

    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    // Konum (Ayarlar → Görünüm): ortada ya da sol/sağ kenara yakın. Panel açıkken pencere tüm ekranı
    // kapladığı için kenar boşluğu o zaman çentiğin kendisine verilir (bkz. notch.x).
    readonly property string position: layout.position || "center"
    readonly property int edgeGap: 28
    LayerShell.Window.anchors: position === "left" ? LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft
                             : position === "right" ? LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
                             : LayerShell.Window.AnchorTop
    LayerShell.Window.margins.left: position === "left" && !capture ? edgeGap : 0
    LayerShell.Window.margins.right: position === "right" && !capture ? edgeGap : 0
    LayerShell.Window.wantsToBeOnActiveScreen: false
    LayerShell.Window.scope: "dynamic-island"
    LayerShell.Window.exclusionZone: -1
    // Klavye yalnızca panel açıkken (not yazmak için) ve tıklayınca odak alır
    // Komut paleti açıkken klavye hemen adaya gelsin (yazmaya başlamak için tıklamak gerekmesin)
    LayerShell.Window.keyboardInteractivity: paletteOpen || quickOpen ? LayerShell.Window.KeyboardInteractivityExclusive
                                           : panelOpen ? LayerShell.Window.KeyboardInteractivityOnDemand
                                           : LayerShell.Window.KeyboardInteractivityNone

    // Pencere, ekran ve layer-shell ayarları uygulandıktan sonra gösterilmeli (sıra önemli)
    property bool placed: false
    visible: placed && !fullscreen

    Item {
        focus: true
        Keys.onEscapePressed: { root.panelOpen = false; root.paletteOpen = false; root.quickOpen = false }
        // Dosya rafında bir öğenin üstündeyken Boşluk: Hızlı Bakış
        Keys.onSpacePressed: { if (root.quickOpen) root.closeQuickLook(); else if (root.panelOpen && root.shelfHover) root.openQuickLook(root.shelfHover) }
    }

    readonly property string endpoint: "http://127.0.0.1:47615"

    // Dil: Ayarlar'dan (config.json "language": auto|en|tr); otomatikte sistem dili Türkçe ise Türkçe
    // Yeni dil: lang_xx.js ekle ve buraya yaz. Türkçe kaynak dildir, sözlüğü yoktur.
    readonly property var dicts: ({ en: En.dict })
    readonly property string sysLang: Qt.locale().name.split("_")[0]
    readonly property string lang: settings.language === "tr" || dicts[settings.language] ? settings.language
                                 : sysLang === "tr" || dicts[sysLang] ? sysLang : "en"
    readonly property var locale: Qt.locale(lang === "tr" ? "tr_TR" : Qt.locale().name.indexOf("en") === 0 ? Qt.locale().name : "en_US")
    // Arayüz metni: kaynak Türkçe; seçili dilde çevirisi yoksa Türkçe kalır. %1, %2… için .arg()
    function t(s) {
        if (lang === "tr") return s.replace(/\.short$/, "")
        var d = dicts[lang]
        var e = d ? d[s] : undefined
        return e !== undefined ? e : s.replace(/\.short$/, "")
    }
    // Yüzde: Türkçede %62, İngilizcede 62%
    function pct(n) { return lang === "tr" ? "%" + n : n + "%" }
    readonly property var calColors: ["#6ea8fe", "#30d158", "#ffd60a", "#bf5af2", "#ff375f"]

    // Vurgu rengi: çalan parçanın albüm kapağından; kapak yoksa sabit, yumuşak bir mavi.
    // Anlamsal renkler (kırmızı = uyarı/kayıt, sarı = sıcak/Gece Işığı, yeşil = şarj) ayrıdır.
    readonly property bool accentFixed: /^#[0-9a-fA-F]{6}$/.test(layout.accent || "")
    readonly property color accentDefault: accentFixed ? layout.accent : "#6ea8fe"
    property color accent: accentFixed ? accentDefault : accentExtractor.result
    Behavior on accent { ColorAnimation { duration: 700; easing.type: Easing.OutCubic } }
    AccentExtractor {
        id: accentExtractor
        fallback: root.accentDefault
        source: root.hasMedia ? (root.media.artUrl || "") : ""
    }

    // ------------------------------------------------------------------
    // Durum
    // ------------------------------------------------------------------
    property var sys: ({
        volume: { level: 50, muted: false },
        media: { active: false },
        battery: { present: false, level: 100, charging: false },
        wifi: { connected: false, ssid: "", signal: 0, type: "none" }
    })
    property var cal: ({ configured: false, events: [], errors: [] })
    property var appList: []
    property var ctl: ({ wifiOn: true, bt: { present: false, on: false, device: "" }, profile: "", profiles: [] })
    property var ui: ({ hidden: false, dnd: false })
    property var displays: []
    property var power: ({ profile: "", profiles: [] })
    property var night: ({ available: false, enabled: false, running: false, inhibited: false, mine: false, temp: 0 })
    property bool fullscreen: false
    property var stats: ({})
    property var audio: ({ "default": "", sinks: [] })
    property var clip: []
    property bool clipOn: false
    property var notes: []
    property var shelf: []
    property var docs: []               // serbest metin notları (Araçlar → Notlar)
    property var docNew: ({ seq: 0, id: 0 })
    property var weather: ({ ok: false })
    property var phone: ({ present: false, devices: [] })
    property var rec: ({ state: "idle", since: 0, error: "", last: "" })
    // Odak sayacı (arka uçta tutulur): phase idle|work|break, running, end (ms), left (ms)
    property var pomo: ({ phase: "idle", running: false, end: 0, left: 1500000, work: 25, brk: 5, round: 0, seq: 0 })
    property real focusNow: Date.now()
    // Şarkı sözleri: görünüm açık mı, arka uçtan gelen sözler
    property bool lyricsOn: false
    // Gizlilik: kamera / mikrofon / ekran paylaşımını kullanan uygulamalar
    property var priv: ({ camera: [], mic: [], screen: [] })
    // Ayarlar sayfasının gösterdiği değerler (arka uç config.json'dan yayınlar)
    property var settings: ({ suppress_plasma_popups: true, hide_in_fullscreen: true, clipboard_history: true,
                              lyrics: true, meeting_alerts: true, privacy_dots: true, weather_enabled: true, phone: true,
                              spectrum: true, otp_capture: true, sounds: false, screenshot_preview: true, split_island: true,
                              claudeHooks: false,
                              accounts: [], calendars: 0, shortcuts: {}, language: "auto",
                              layout: { tabs: [], hidden: [], open: "last", position: "center", accent: "auto" } })
    readonly property var layout: settings.layout || ({})
    // Malzeme: minimal (varsayılan, sade derinlik) | ambient (canlı renkler) | black (düz siyah)
    readonly property string material: layout.material === "ambient" || layout.material === "black" || layout.material === "glass" ? layout.material : "minimal"
    readonly property bool ambient: material !== "black"
    readonly property bool vivid: material === "ambient"
    // Sıvı cam: ada gövdesi tek cam levha, kontroller mercekli cam (docs/liquid-glass.md)
    readonly property bool glassy: material === "glass"
    // Cam levha yalnızca açık panelde; kapalı ada ve küçük görünümler donanım çentiğiyle uyumlu siyah kalır
    readonly property bool glassBody: glassy && mode === "panel"
    readonly property string glassStyle: layout.glass === "frosted" || layout.glass === "clear" ? layout.glass : "balanced"
    readonly property real glassFrost: glassStyle === "frosted" ? 0.75 : glassStyle === "clear" ? 0.12 : 0.38
    readonly property Item glassLayer: glassy ? glassBackdrop : null
    // Cam yüzeylerin arka plandaki konumunu yeniden hesaplatan sayaç (yalnızca cam panelde, kare başına)
    property real glassTick: 0
    FrameAnimation {
        running: root.glassy && root.mode === "panel"
        onTriggered: root.glassTick += 1
    }
    // Müzik ışıklarının rengi: canlı modda vurgu rengi, sade modda beyaz
    readonly property color glowColor: vivid ? accent : "white"
    // Bas düzeyi (0..1): alt ışık ve kenar ışığı müziğe göre nefes alır
    readonly property real bass: {
        var l = spectrum
        if (!l || l.length < 6) return 0
        return Math.min(1, (l[1] + l[2] + l[3] + l[4]) / 400)
    }

    // Sekmeler: sayfa numarası sabit (0 Müzik … 7 Araçlar, 8 Ayarlar), görünen sıra ve gizlilik ayardan.
    readonly property var tabKeys: ["music", "notifications", "focus", "calendar", "controls", "apps", "system", "tools", "weather"]
    // Ayarlar → Sekmeler → Varsayılan: Hava, Sistem'in yanında
    readonly property var defaultTabIds: [0, 1, 2, 3, 4, 5, 6, 8, 7]
    // Sürükleyip bırakınca arka uçtan yanıt gelene kadar yeni sıra hemen görünsün
    property var pendingTabs: null
    onSettingsChanged: pendingTabs = null
    // Görünen sekmelerin sayfa numaraları, sırayla
    readonly property var tabOrder: {
        if (pendingTabs) return pendingTabs
        var keys = (layout.tabs && layout.tabs.length) ? layout.tabs : tabKeys
        var hidden = layout.hidden || []
        var out = []
        for (var i = 0; i < keys.length; i++) {
            var id = tabKeys.indexOf(keys[i])
            if (id >= 0 && hidden.indexOf(keys[i]) < 0) out.push(id)
        }
        return out.length ? out : [0]
    }
    // Yeni sıra/gizli listesi (sayfa numaralarıyla) -> arka uç
    function saveTabs(order, hiddenIds) {
        var tabs = [], hidden = []
        for (var i = 0; i < order.length; i++) tabs.push(tabKeys[order[i]])
        for (var j = 0; j < hiddenIds.length; j++) { tabs.push(tabKeys[hiddenIds[j]]); hidden.push(tabKeys[hiddenIds[j]]) }
        pendingTabs = order.slice()
        send("set_layout", { tabs: tabs, hidden: hidden })
    }
    // Tüm sekmeler (gizliler dahil) ayardaki sırayla
    readonly property var allTabIds: {
        var keys = (layout.tabs && layout.tabs.length) ? layout.tabs : tabKeys
        var out = []
        for (var i = 0; i < keys.length; i++) { var id = tabKeys.indexOf(keys[i]); if (id >= 0 && out.indexOf(id) < 0) out.push(id) }
        for (var j = 0; j < tabKeys.length; j++) if (out.indexOf(j) < 0) out.push(j)
        return out
    }
    // Ayarlar → Sekmeler: tam sıra (gizliler yerinde kalır) ve gizli olanlar
    function saveTabOrder(fullIds, hiddenIds) {
        var tabs = [], hidden = [], visible = []
        for (var i = 0; i < fullIds.length; i++) {
            tabs.push(tabKeys[fullIds[i]])
            if (hiddenIds.indexOf(fullIds[i]) >= 0) hidden.push(tabKeys[fullIds[i]])
            else visible.push(fullIds[i])
        }
        if (!visible.length) return
        pendingTabs = visible
        send("set_layout", { tabs: tabs, hidden: hidden })
    }
    function hiddenTabIds() {
        var out = []
        for (var i = 0; i < tabKeys.length; i++) if (tabOrder.indexOf(i) < 0) out.push(i)
        return out
    }
    // Panel açılırken gösterilecek sekme: ayara göre ilk sekme ya da son açılan (gizlendiyse ilk)
    function openingTab() {
        if (layout.open === "first") return tabOrder[0]
        return tab === 9 || tabOrder.indexOf(tab) >= 0 ? tab : tabOrder[0]
    }
    // Claude Code: bekleyen izin istekleri (en eskisi önce) ve son "bitti" haberi
    property var agents: ({ asks: [], done: { seq: 0 } })
    readonly property var ask: agents.asks.length > 0 ? agents.asks[0] : null
    // Canlı Etkinlikler (island komutu / POST /activity): süren işler ve son biten
    property var live: ({ items: [], done: { seq: 0 } })
    readonly property var act: live.items.length > 0 ? live.items[live.items.length - 1] : null
    // Son sistem uyarısı (Caps Lock, Bluetooth, internet)
    property var alertD: ({ kind: "", seq: 0 })
    readonly property var privDots: {
        var d = []
        if (!settings.privacy_dots) return d
        if (priv.camera.length) d.push("#34c759")
        if (priv.mic.length) d.push("#ff9f0a")
        if (priv.screen.length && rec.state === "idle") d.push("#0a84ff")
        return d
    }
    property var lyr: ({ track: "", status: "none", lines: [] })
    // Ekran görüntüsü önizlemesi: son görüntü ve önizlemede gösterilen
    property var shot: ({ seq: 0 })
    property var shotInfo: ({})
    // Gerçek ses spektrumu: yalnızca çubuklar görünürken ve müzik çalarken sorulur
    property var spectrum: []
    readonly property bool spectrumWant: playing && settings.spectrum !== false && fullscreen === false && (
        (mode === "idle" && rightBars) || mode === "media" || (mode === "panel" && tab === 0 && !lyricsOn))
    onSpectrumWantChanged: if (!spectrumWant) spectrum = []
    property bool spectrumBusy: false
    function fetchSpectrum() {
        if (spectrumBusy || !token) return
        spectrumBusy = true
        var x = new XMLHttpRequest()
        x.open("GET", endpoint + "/spectrum")
        x.setRequestHeader("X-Island", token)
        x.timeout = 1000
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return
            spectrumBusy = false
            if (x.status !== 200 || !spectrumWant) return
            try { spectrum = JSON.parse(x.responseText).b || [] } catch (e) { spectrum = [] }
        }
        x.send()
    }
    Timer {
        // kapalı adada 4 küçük çubuk için 20 kare/sn yeter; açık görünümlerde 30
        interval: root.mode === "idle" ? 50 : 33
        repeat: true
        running: root.spectrumWant
        onTriggered: root.fetchSpectrum()
    }
    readonly property bool lyricsWant: panelOpen && tab === 0 && lyricsOn && hasMedia && settings.lyrics
    onLyricsWantChanged: send("lyrics_want", lyricsWant)
    readonly property bool focusOn: pomo.phase !== "idle"
    readonly property real focusLeft: pomo.running ? Math.max(0, pomo.end - focusNow) : pomo.left
    readonly property real focusFrac: {
        var len = (pomo.phase === "break" ? pomo.brk : pomo.work) * 60000
        return len > 0 ? Math.max(0, Math.min(1, focusLeft / len)) : 0
    }
    readonly property color focusColor: pomo.phase === "break" ? "#30d158" : "#ff9f0a"
    property real secTick: Date.now()
    property bool deviceMenu: false
    property bool dropHover: false
    property bool draggingOut: false
    property string toastText: ""
    property string toastIcon: "dialog-ok-apply"
    readonly property int ear: 14       // çentiğin yanlardaki içbükey "kulak" yarıçapı
    property bool peek: false           // gizli modda fare üstündeyken görünür
    property var notifs: ({ seq: 0, items: [] })
    property bool loaded: false
    property int stateVersion: 0

    readonly property var media: sys.media
    readonly property var battery: sys.battery
    readonly property var wifi: sys.wifi
    readonly property var volume: sys.volume
    readonly property bool hasMedia: media.active === true
    readonly property bool playing: hasMedia && media.status === "Playing"

    property real pos: 0
    property real nowMs: Date.now()
    property string clock: "00:00"
    property string dateText: ""

    ListModel { id: notifModel }
    readonly property alias notifModel: notifModel
    property int seenId: 0
    property int unread: 0
    property var nextEvent: null
    property int calAddSeq: -1          // son görülen takvim ekleme sonucu (ilk yüklemede bildirim yok)
    property var alerted: ({})

    // ------------------------------------------------------------------
    // Mod
    // ------------------------------------------------------------------
    property bool panelOpen: false
    property bool paletteOpen: false    // komut paleti (Meta+Alt+Space, island palette)
    // Hızlı Bakış: dosya önizlemesi (palet Ctrl+Y, raf Boşluk, island quicklook)
    property bool quickOpen: false
    property string quickPath: ""
    property var quickInfo: ({})
    property string shelfHover: ""      // dosya rafında fare üstündeki öğenin yolu
    onPaletteOpenChanged: { if (paletteOpen) panelOpen = false; sound(paletteOpen ? "palette" : "close") }
    property int toolsSub: 0            // Araçlar sekmesindeki bölüm: 0 Pano, 1 Anımsatıcı, 2 Raf, 3 Notlar
    property int settingsSub: 0         // Ayarlar bölümü: 0 Genel, 1 Özellikler, 2 Sekmeler, 3 Görünüm
    property int tab: 0                 // 0 Müzik, 1 Bildirim, 2 Odak, 3 Takvim, 4 Kontrol, 5 Uygulama, 6 Sistem, 7 Araçlar, 8 Hava, 9 Ayarlar
    property bool hovered: false
    property string flashKind: ""       // volume | charge | track | notif | event
    property string chargeKind: "charging"
    property var banner: ({})

    readonly property bool isHidden: ui.hidden && !peek && !panelOpen && !paletteOpen && !quickOpen && !dropHover && flashKind === ""

    readonly property string mode: {
        if (quickOpen) return "quicklook"
        if (paletteOpen) return "palette"
        if (panelOpen) return "panel"
        if (dropHover) return "drop"
        if (ask !== null) return "ask"
        if (flashKind === "shot") return "shot"
        if (flashKind === "notif" || flashKind === "event") return "banner"
        if (flashKind === "toast") return "toast"
        if (flashKind === "alert") return "alert"
        if (flashKind === "volume") return "volume"
        if (flashKind === "charge") return "charge"
        if (flashKind === "track") return "media"
        if ((flashKind === "live" || hovered) && live.items.length > 0) return "live"
        if (hovered && hasMedia) return "media"
        return "idle"
    }

    // Kapalı ada: [sol yuva] saat [sağ yuva]. Saat ortada kalsın diye iki yuva eşit genişlikte.
    readonly property string leftSlot: rec.state !== "idle" ? "rec" : act !== null ? "act"
                                     : hasMedia && satKind !== "media" ? "art"
                                     : focusOn ? "ring" : unread > 0 ? "dot" : ""
    readonly property string rightText: rec.state === "recording" ? fmt(secTick - rec.since)
                                      : rec.state !== "idle" ? "" : act !== null ? actValue(act)
                                      : focusOn ? mmss(focusLeft) : ""
    readonly property bool rightBars: hasMedia && rec.state === "idle" && satKind !== "media"
    readonly property int privW: privDots.length ? privDots.length * 11 - 4 : 0
    readonly property int slotW: {
        var parts = [rightBars ? 18 : 0, rightText !== "" ? 44 : 0, privW].filter(function (w) { return w > 0 })
        var w = 0
        for (var i = 0; i < parts.length; i++) w += parts[i] + (i ? 6 : 0)
        return Math.max(24, w)
    }
    readonly property int idleW: 32 + 2 * slotW + 20 + 46

    // ---- Bölünmüş ada: ana adada sığmayan ikinci şey, ince bir boyunla ayrılan küçük daire olur
    readonly property int satW: 34
    readonly property int satH: 32
    readonly property int satGap: 10
    readonly property string satKind: {
        if (settings.split_island === false) return ""
        if (hasMedia && (rec.state !== "idle" || act !== null || focusOn)) return "media"
        if (act !== null && live.items.length > 1) return "act2"
        if (act !== null && focusOn) return "focus"
        return ""
    }
    property string satLast: "media"       // daire kapanırken içeriği bir an daha göstermek için
    onSatKindChanged: if (satKind !== "") satLast = satKind
    // Geniş görünümlerde (panel, bildirim…) daire ana adaya geri katılır; kısa uyarılarda yanında kalır
    readonly property bool satWant: satKind !== "" && !isHidden
        && (mode === "idle" || mode === "volume" || mode === "charge" || mode === "alert" || mode === "toast")
    property real satP: satWant ? 1 : 0
    Behavior on satP { SpringAnimation { spring: 3.0; damping: 0.3; epsilon: 0.001 } }
    readonly property bool satOnLeft: position === "right"
    readonly property int satRoom: (satWant || Math.abs(satP) > 0.002) ? satW + satGap + ear : 0
    readonly property int satSides: position === "center" ? 2 : 1       // pencerede kaç yanda yer ayrılsın

    // ---- Uçan kapak: tek bir kapak nesnesi; kapalı ada, ayrılan daire, müzik görünümü ve panel
    // arasında yaylanarak akar (her yerde ayrı bir kapak çizmek yerine).
    readonly property string artHome: {
        if (!hasMedia) return "none"
        if (mode === "media") return "media"
        if (mode === "panel") return tab === 0 && !lyricsOn && !pageMusic.outputs ? "panel" : "none"
        if (satKind === "media" && satWant) return "sat"
        if (mode === "idle" && leftSlot === "art") return "idle"
        return "none"
    }
    property var artFrom: ({ x: 0, y: 0, w: 22, h: 22, r: 6 })
    property real artT: 1
    property string artLast: "none"
    property bool flyBusy: false
    function artAnchor(home) {
        return home === "idle" ? idleArt : home === "sat" ? satArt : home === "media" ? mArt
             : home === "panel" ? pageMusic.artAnchor : null
    }
    function artRect(home) {
        var a = artAnchor(home)
        if (!a || !a.width) return null
        var p = a.mapToItem(notch, 0, 0), q = a.mapToItem(notch, a.width, a.height)
        return { x: p.x, y: p.y, w: q.x - p.x, h: q.y - p.y, r: home === "media" ? 10 : home === "panel" ? 16 : 6 }
    }
    // Her karede: başlangıç ile hedef arasında artT oranında karışım (hedef hareket ederken de izlenir)
    function syncArt() {
        var to = artRect(artHome !== "none" ? artHome : artLast)
        if (!to) return
        var f = artFrom, t = artT
        flyArt.x = f.x + (to.x - f.x) * t
        flyArt.y = f.y + (to.y - f.y) * t
        flyArt.width = Math.max(1, f.w + (to.w - f.w) * t)
        flyArt.height = Math.max(1, f.h + (to.h - f.h) * t)
        flyArt.radius = Math.max(0, f.r + (to.r - f.r) * t)
    }
    function flyKick() { flyBusy = true; flySettle.restart() }
    onArtHomeChanged: {
        if (artHome === "none") { flyKick(); return }
        var to = artRect(artHome)
        if (!to) return
        artAnim.stop()
        if (flyArt.opacity < 0.1) {            // yeni beliriyor: uçmadan yerine
            artFrom = to
            artT = 1
        } else {                               // şu anki konumdan yeni yere uç
            artFrom = { x: flyArt.x, y: flyArt.y, w: flyArt.width, h: flyArt.height, r: flyArt.radius }
            artT = 0
            artAnim.start()
        }
        artLast = artHome
        flyKick()
    }
    onLyricsOnChanged: flyKick()
    onSatPChanged: flyKick()
    SpringAnimation { id: artAnim; target: root; property: "artT"; to: 1; spring: 3.4; damping: 0.34; epsilon: 0.0008 }
    FrameAnimation { running: root.flyBusy; onTriggered: root.syncArt() }
    Timer {
        id: flySettle
        interval: 1100
        onTriggered: { if (artAnim.running) restart(); else { root.syncArt(); root.flyBusy = false } }
    }
    // açılışta müzik zaten çalıyorsa kapak ilk karede yerinde olsun
    Timer {
        interval: 900; running: true
        onTriggered: { var to = root.artRect(root.artHome); if (to) { root.artFrom = to; root.artT = 1; root.artLast = root.artHome; root.syncArt() } }
    }

    // Açık panel: geniş ve alçak. Başlık 40 + sayfa 162 + alt boşluk 14.
    readonly property real panelScale: 1
    readonly property int panelW: lyricsWant ? 760 : 600
    // Ayarlar çok satır içerir: o sekmede panel daha yüksek
    readonly property int panelH: tab === 9 ? 372 : 224

    readonly property int islandW: {
        switch (mode) {
        case "panel": return panelW
        case "palette": return 640
        case "quicklook": return 520
        case "drop": return 300
        case "toast": return Math.min(420, Math.max(260, toastMeasure.implicitWidth + 32 + 10 + 40))
        case "banner": return 440
        case "shot": return 404
        case "media": return 400
        case "live": return 440
        case "volume": return 330
        case "charge": return 300
        case "alert": return 330
        case "ask": return 480
        default: return idleW
        }
    }
    readonly property int islandH: {
        switch (mode) {
        // Tüm sekmelerde aynı yükseklik. Müzik çalarken Ana sayfa medya kartı + her ek ekran için
        // bir parlaklık satırı kadar uzar; çalmıyorken en uzun sayfanın (Sistem) sığdığı boy.
        case "panel": return panelH
        case "palette": return paletteView.wantH
        case "quicklook": return quickView.wantH
        case "drop": return 56
        case "toast": return 52
        case "banner": return 64
        case "shot": return 92
        case "media": return 84
        case "live": return 16 + Math.min(3, live.items.length) * 52
        case "volume": return 44
        case "charge": return 56
        case "alert": return 56
        case "ask": return 132
        default: return 32
        }
    }

    // Pencere: büyürken anında (yay animasyonunun taşması için boşlukla), animasyon bitince
    // çentiğe sıkıca daralır; böylece altındaki uygulamaların tıklamasını engellemez.
    // Panel açıkken tüm ekranı kaplar (boş alana tıklayınca panel kapansın diye).
    readonly property bool capture: (panelOpen || paletteOpen || quickOpen) && !draggingOut
    readonly property int wantW: capture ? Screen.width : islandW + 2 * ear + 60 + satSides * satRoom
    readonly property int wantH: capture ? Screen.height : (isHidden ? 6 : islandH + 30)
    readonly property int restW: capture ? Screen.width : islandW + 2 * ear + satSides * satRoom
    readonly property int restH: capture ? Screen.height : (isHidden ? 6 : islandH + 2)
    width: 256
    height: 92
    // Pencere boyutu değişirken Qt yüzeyin yeni boyutunu hemen bildirir ama yeni tampon bir kare sonra
    // gelir: o sürede eski tampon (kapalı adanın saati, panelin kenarı) tüm ekrana gerilip çakar.
    // Büyük boyut değişimlerinde (panel aç/kapa) içerik önce gizlenir, kare sunulunca boyut değişir,
    // yeni tampon da sunulunca içerik geri gelir. Küçük değişimler (bildirim, hover) doğrudan uygulanır.
    property bool sizeHide: false
    property int sizeStage: 0           // 0 boşta, 1 gizleniyor, 2 boyut uygulandı
    property int sizeFrames: 0
    property int pendW: 0
    property int pendH: 0
    // contentItem'in opaklığı: hem çentik gövdesi hem ada içeriği (ayrı kardeşler) birlikte gizlenir
    Binding { target: root.contentItem; property: "opacity"; value: root.sizeHide ? 0 : 1 }
    function setSize(w, h) {
        if (w === width && h === height) return
        if (Math.abs(w - width) < 400 && Math.abs(h - height) < 200) {
            width = w; height = h
            return
        }
        pendW = w; pendH = h
        if (sizeStage === 0) { sizeHide = true; sizeStage = 1; sizeFrames = 0 }
        sizeGuard.restart()
    }
    function sizeDone() { kick.start(); sizeHide = false; sizeStage = 0; sizeGuard.stop() }
    onFrameSwapped: {
        if (sizeStage === 0) return
        if (++sizeFrames < 2) return
        sizeFrames = 0
        if (sizeStage === 1) { width = pendW; height = pendH; sizeStage = 2 }
        else sizeDone()
    }
    // Geçiş sürerken her karede yeniden çizim iste: gizli içerikle hiçbir şey kirlenmediği için kare gelmeyebilir
    FrameAnimation { running: root.sizeStage !== 0; onTriggered: root.update() }
    // yeniden gösterdikten sonra da bir süre kare iste (kare çağrısı geç kalırsa animasyonlar donmasın)
    Timer { id: kick; interval: 16; repeat: true; property int n: 0; onTriggered: { root.update(); if (++n > 40) { stop(); n = 0 } } }
    // Kare gelmezse takılı kalmasın
    Timer { id: sizeGuard; interval: 250; onTriggered: { root.width = root.pendW; root.height = root.pendH; root.sizeDone() } }
    onWantWChanged: { if (wantW > width) setSize(wantW, Math.max(height, wantH)); shrinkTimer.restart() }
    onWantHChanged: { if (wantH > height) setSize(Math.max(width, wantW), wantH); shrinkTimer.restart() }
    Timer {
        id: shrinkTimer
        interval: 450
        onTriggered: root.setSize(root.restW, root.restH)
    }

    // ------------------------------------------------------------------
    // Yardımcılar
    // ------------------------------------------------------------------
    function fmt(ms) {
        var s = Math.max(0, Math.floor(ms / 1000))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    function mmss(ms) {
        var t = Math.ceil(ms / 1000)
        return String(Math.floor(t / 60)).padStart(2, "0") + ":" + String(t % 60).padStart(2, "0")
    }

    function clockOf(ms) {
        var d = new Date(ms)
        return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0")
    }

    function ago(ts) {
        var s = Math.max(0, (nowMs - ts) / 1000)
        if (s < 60) return t("şimdi")
        if (s < 3600) return t("%1 dk.short").arg(Math.floor(s / 60))
        if (s < 86400) return t("%1 sa.short").arg(Math.floor(s / 3600))
        return t("%1 g.short").arg(Math.floor(s / 86400))
    }

    function untilText(ev) {
        var m = Math.ceil((ev.start - nowMs) / 60000)
        if (m <= 0) return t("Şimdi · %1").arg(clockOf(ev.start))
        if (m < 60) return t("%1 dk sonra · %2").arg(m).arg(clockOf(ev.start))
        return t("%1 · %2 sa %3 dk").arg(clockOf(ev.start)).arg(Math.floor(m / 60)).arg(m % 60)
    }

    // Etkinliğin "cal" alanı: takvimin kendi rengi ("#rrggbb", CalDAV) ya da palet sırası
    function calColor(i) { return typeof i === "string" ? i : calColors[(i || 0) % calColors.length] }

    function volIcon() {
        if (volume.muted || volume.level === 0) return "audio-volume-muted"
        if (volume.level < 34) return "audio-volume-low"
        if (volume.level < 67) return "audio-volume-medium"
        return "audio-volume-high"
    }

    function wifiIcon() {
        if (!wifi.connected) return "network-offline"
        if (wifi.type === "ethernet") return "network-wired"
        if (wifi.signal > 75) return "network-wireless-signal-excellent"
        if (wifi.signal > 50) return "network-wireless-signal-good"
        if (wifi.signal > 25) return "network-wireless-signal-ok"
        return "network-wireless-signal-weak"
    }

    function batIcon() {
        var l = Math.max(0, Math.min(100, Math.round(battery.level / 10) * 10))
        var n = l === 100 ? "100" : String(l).padStart(3, "0")
        return "battery-" + n + (battery.charging ? "-charging" : "")
    }

    function batColor() {
        if (battery.charging) return "#30d158"
        return battery.level <= 20 ? "#ff453a" : "#ffffff"
    }

    function updatePos() {
        if (!hasMedia) { pos = 0; return }
        var p = media.position + (playing ? Date.now() - media.stamp : 0)
        pos = Math.max(0, media.length > 0 ? Math.min(media.length, p) : p)
    }

    function toast(text, icon) {
        toastText = text
        toastIcon = icon || "dialog-ok-apply"
        flash("toast", 2200)
    }

    function sinkIcon(kind) {
        if (kind === "headphones") return "audio-headphones"
        if (kind === "bluetooth") return "audio-headset"
        if (kind === "display") return "video-display"
        return "audio-speakers"
    }

    function currentSinkKind() {
        for (var i = 0; i < audio.sinks.length; i++)
            if (audio.sinks[i].name === audio["default"]) return audio.sinks[i].kind
        return "speaker"
    }

    // Tek renk ikonlar (contents/icons)
    function ic(n) { return Qt.resolvedUrl("../icons/" + n + ".svg") }

    // -- Canlı Etkinlikler
    readonly property var actIcons: ({
        build: "run-build", download: "download", upload: "upload", timer: "isle-timer",
        test: "isle-tasks", deploy: "isle-send-symbolic", sync: "isle-update-symbolic",
        terminal: "isle-terminal-symbolic", music: "isle-music", mail: "mail-message",
        check: "isle-check-symbolic", warning: "isle-warning-symbolic", info: "isle-info-symbolic"
    })
    function actIcon(name) {
        var n = actIcons[name || "info"] || name
        return n.indexOf("isle-") === 0 ? ic(n) : n
    }
    function actColor(a) { return a && a.color ? a.color : accent }
    // 0..1 ilerleme; geri sayımda kalan oran; belirsizse -1
    function actFrac(a) {
        if (!a) return -1
        if (a.end > 0) return Math.max(0, Math.min(1, (a.end - secTick) / Math.max(1, a.end - a.start)))
        return a.progress
    }
    function actValue(a) {
        if (a.value) return a.value
        if (a.end > 0) return mmss(Math.max(0, a.end - secTick))
        if (a.progress >= 0) return Math.round(a.progress * 100) + "%"
        return fmt(secTick - a.start)
    }

    function baseName(p) { return String(p).split("/").pop() }
    function fmtDate(ms) {
        var d = new Date(ms)
        return Qt.formatDate(d, "dd.MM.yyyy") + " " + Qt.formatTime(d, "HH:mm")
    }

    // -- Hızlı Bakış
    function openQuickLook(path) {
        if (!path) return
        quickPath = path
        quickInfo = ({ name: baseName(path) })
        quickOpen = true
        sound("open")
        fetchPreview(path)
        quickFocus.restart()
    }
    function closeQuickLook() {
        if (!quickOpen) return
        quickOpen = false
        sound("close")
        if (paletteOpen) paletteRefocus.restart()
    }
    function fetchPreview(path) {
        if (!token) token = readToken()
        var x = new XMLHttpRequest()
        x.open("GET", endpoint + "/preview?path=" + encodeURIComponent(path))
        x.setRequestHeader("X-Island", token)
        x.timeout = 15000
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE || quickPath !== path) return
            try { quickInfo = x.status === 200 ? JSON.parse(x.responseText) : ({ error: "missing", name: baseName(path) }) }
            catch (e) { quickInfo = ({ error: "missing", name: baseName(path) }) }
        }
        x.send()
    }
    Timer { id: quickFocus; interval: 40; onTriggered: quickView.focusMe() }
    Timer { id: paletteRefocus; interval: 80; onTriggered: paletteView.refocus() }

    function flash(kind, ms) {
        flashKind = kind
        transientTimer.interval = ms
        transientTimer.restart()
        flashAnim.stop()
        flashAnim.from = Math.max(0, islandW - 72)
        flashAnim.duration = ms
        flashAnim.start()
    }

    // -- bildirimler
    function maxNotifId() {
        var m = 0
        for (var i = 0; i < notifs.items.length; i++) m = Math.max(m, notifs.items[i].id)
        return m
    }

    function recount() {
        var n = 0
        for (var i = 0; i < notifs.items.length; i++)
            if (notifs.items[i].id > seenId) n++
        unread = n
    }

    function markSeen() {
        seenId = Math.max(seenId, maxNotifId())
        recount()
    }

    // ListModel'i yerinde güncelle: kaldırma/ekleme animasyonları bozulmasın
    function syncNotifs(items) {
        var ids = {}
        for (var i = 0; i < items.length; i++) ids[items[i].id] = true
        for (var r = notifModel.count - 1; r >= 0; r--)
            if (!ids[notifModel.get(r).id]) notifModel.remove(r)
        for (var k = 0; k < items.length; k++) {
            var it = items[k]
            if (k < notifModel.count && notifModel.get(k).id === it.id) {
                notifModel.set(k, it)
            } else {
                var from = -1
                for (var j = k + 1; j < notifModel.count; j++)
                    if (notifModel.get(j).id === it.id) { from = j; break }
                if (from >= 0) { notifModel.remove(from) }
                notifModel.insert(k, it)
            }
        }
    }

    // -- takvim
    function updateNext() {
        var now = Date.now()
        var best = null
        var ev = cal.events
        for (var i = 0; i < ev.length; i++) {
            if (ev[i].allDay || ev[i].end <= now) continue
            if (best === null || ev[i].start < best.start) best = ev[i]
        }
        nextEvent = best
    }

    // Toplantı bağlantısı mı? (Katıl düğmesi yalnızca bunlarda)
    function meetingService(url) {
        var u = String(url || "")
        if (u.indexOf("meet.google.com") >= 0) return "Google Meet"
        if (/zoom\.(us|com)\//.test(u)) return "Zoom"
        if (u.indexOf("teams.microsoft.com") >= 0 || u.indexOf("teams.live.com") >= 0) return "Microsoft Teams"
        if (u.indexOf("webex.com") >= 0) return "Webex"
        if (u.indexOf("whereby.com") >= 0) return "Whereby"
        if (u.indexOf("meet.jit.si") >= 0) return "Jitsi"
        return ""
    }

    function checkEvents() {
        if (!loaded) return
        var now = Date.now()
        var ev = cal.events
        for (var i = 0; i < ev.length; i++) {
            var e = ev[i]
            if (e.allDay) continue
            var mins = (e.start - now) / 60000
            if (mins <= -0.5 || mins > 5) continue
            var key = e.id + (mins <= 1.2 ? "b" : "a")
            if (alerted[key]) continue
            alerted[e.id + "a"] = true
            if (mins <= 1.2) alerted[e.id + "b"] = true
            if (!panelOpen && !ui.dnd && settings.meeting_alerts) {
                banner = { kind: "event", title: e.title, start: e.start, end: e.end, cal: e.cal,
                           location: e.location, url: meetingService(e.url) ? e.url : "" }
                flash("event", 9000)
            }
            return
        }
    }

    // Arayüz sesi (Ayarlar → Genel → Arayüz sesleri açıksa; çalmayı arka uç yapar)
    function sound(name) { if (settings.sounds) send("sound", name) }

    // Doğrulama kodu: tek dokunuşla panoya (geçmişe eklenmez), kısa onay
    function copyCode(code) {
        sound("copy")
        send("copy_text", code)
        toast(t("Kod kopyalandı"), "dialog-ok-apply")
    }
    function prettyCode(c) {
        return c.length === 6 && /^\d+$/.test(c) ? c.slice(0, 3) + " " + c.slice(3) : c
    }

    function openFromBanner() {
        var k = banner.kind
        flashKind = ""
        if (k === "record") { send("open_recording"); return }
        if (k === "agent" || k === "activity") return
        // Bildirim: uygulamayı aç (varsa ilgili sohbet/e-posta); ada kapalı kalır
        if (k === "notif" && banner.code) { copyCode(banner.code); return }
        if (k === "notif" && banner.id) { send("notif_open", banner.id); return }
        tab = k === "event" ? 3 : 1
        panelOpen = true
    }

    // Arka uç yalnızca değişen anahtarları gönderir (delta)
    function apply(s) {
        var o = sys
        var first = !loaded
        var merged = {}
        for (var k in o) merged[k] = o[k]
        for (var k2 in s) merged[k2] = s[k2]
        sys = merged
        updatePos()

        if (s.controls !== undefined) ctl = s.controls
        if (s.ui !== undefined) ui = s.ui
        if (s.displays !== undefined) displays = s.displays
        if (s.power !== undefined) power = s.power
        if (s.night !== undefined) night = s.night
        if (s.fullscreen !== undefined) fullscreen = s.fullscreen
        if (s.apps !== undefined) appList = s.apps
        if (s.stats !== undefined) stats = s.stats
        if (s.audio !== undefined) audio = s.audio
        if (s.clip !== undefined) clip = s.clip
        if (s.clipOn !== undefined) clipOn = s.clipOn
        if (s.notes !== undefined) notes = s.notes
        if (s.shelf !== undefined) shelf = s.shelf
        if (s.docs !== undefined) docs = s.docs
        if (s.docNew !== undefined) docNew = s.docNew
        if (s.rec !== undefined) rec = s.rec
        if (s.weather !== undefined) weather = s.weather
        if (s.phone !== undefined) phone = s.phone
        if (s.focus !== undefined) { pomo = s.focus; focusNow = Date.now() }
        if (s.lyrics !== undefined) lyr = s.lyrics
        if (s.privacy !== undefined) priv = s.privacy
        if (s.alert !== undefined) alertD = s.alert
        if (s.agents !== undefined) agents = s.agents
        if (s.activities !== undefined) {
            // Yeni bir etkinlik başlayınca ada kısa süre açılıp onu gösterir
            var known = {}, fresh = false
            for (var ai = 0; ai < live.items.length; ai++) known[live.items[ai].id] = true
            for (var aj = 0; aj < s.activities.items.length; aj++)
                if (!known[s.activities.items[aj].id]) fresh = true
            live = s.activities
            secTick = Date.now()
            if (fresh && !first && !panelOpen && flashKind !== "notif" && flashKind !== "event")
                flash("live", 3500)
        }
        if (s.settings !== undefined) settings = s.settings
        if (s.calendar !== undefined) { cal = s.calendar; updateNext() }
        if (s.calAdd !== undefined && s.calAdd.seq !== calAddSeq) {
            if (calAddSeq >= 0) toast(s.calAdd.ok ? root.t("Eklendi · ") + s.calAdd.msg : root.t("Eklenemedi: ") + s.calAdd.msg,
                                      s.calAdd.ok ? "dialog-ok-apply" : "dialog-warning")
            calAddSeq = s.calAdd.seq
        }

        if (s.notifs !== undefined) {
            var prevSeq = notifs.seq
            notifs = s.notifs
            syncNotifs(notifs.items)
            if (first) {
                seenId = maxNotifId()
            } else if (notifs.seq !== prevSeq && notifs.items.length > 0) {
                if (panelOpen && tab === 1) {
                    markSeen()
                } else if (!ui.dnd) {
                    var n = notifs.items[0]
                    banner = { kind: "notif", id: n.id, icon: n.icon, app: n.app, title: n.title, body: n.body, ts: n.ts,
                               code: settings.otp_capture ? (n.code || "") : "" }
                    flash("notif", banner.code ? 12000 : 5500)
                }
            }
            recount()
        }

        if (first) { loaded = true; return }

        // Kısayol (Meta+Alt+I) ile panel aç/kapat
        if (s.panelReq !== undefined && s.panelReq !== o.panelReq) panelOpen = !panelOpen
        if (s.quickReq !== undefined && s.quickReq.seq !== o.quickReq.seq) {
            if (s.quickReq.path) openQuickLook(s.quickReq.path)
            else closeQuickLook()
        }
        if (s.paletteReq !== undefined && s.paletteReq.seq !== o.paletteReq.seq) {
            if (s.paletteReq.q) { paletteOpen = true; paletteView.prefill(s.paletteReq.q) }
            else paletteOpen = !paletteOpen
        }
        if (s.tabReq !== undefined && s.tabReq.seq !== o.tabReq.seq) {
            tab = Math.max(0, Math.min(9, s.tabReq.tab))
            if (s.tabReq.lyrics !== undefined) lyricsOn = s.tabReq.lyrics
            if (s.tabReq.sub !== undefined) {
                if (tab === 9) settingsSub = Math.max(0, Math.min(3, s.tabReq.sub))
                else toolsSub = Math.max(0, Math.min(3, s.tabReq.sub))
            }
            panelOpen = true
        }

        // Claude Code işini bitirdi
        if (s.agents !== undefined && o.agents !== undefined && s.agents.done.seq !== o.agents.done.seq) {
            var dn = s.agents.done
            banner = { kind: "agent", icon: ic("isle-claude"), app: "Claude Code",
                       title: (dn.project ? dn.project + " · " : "") + root.t("Claude Code bitirdi"),
                       body: dn.message || "", ts: Date.now() }
            if (!panelOpen) flash("notif", 7000)
        }

        // Yeni ekran görüntüsü: küçük önizleme (sürükle, aç, kopyala)
        if (s.shot !== undefined) {
            var prevShot = o.shot ? o.shot.seq : 0
            shot = s.shot
            if (s.shot.seq > 0 && s.shot.seq !== prevShot && settings.screenshot_preview && !fullscreen) {
                shotInfo = s.shot
                sound("shot")
                flash("shot", 9000)
            }
        }

        // Canlı Etkinlik bitti / betikten bildirim
        if (s.activities !== undefined && o.activities !== undefined && s.activities.done.seq !== o.activities.done.seq) {
            var ad = s.activities.done
            if (!(ui.dnd && ad.state === "info")) {
                banner = { kind: "activity", state: ad.state, icon: ad.icon || "", color: ad.color || "",
                           title: ad.title || "", body: ad.icon === "timer" && ad.state === "done"
                               ? root.t("Süre doldu · ") + ad.took : (ad.subtitle || ""), ts: Date.now() }
                if (!panelOpen) flash("notif", ad.state === "failed" || ad.icon === "timer" ? 9000 : 6000)
                // zamanlayıcı alarmını arka uç kendisi çalar (ayardan bağımsız)
                if (ad.icon !== "timer" && !ui.dnd)
                    sound(ad.state === "failed" ? "fail" : ad.state === "info" ? "notify" : "done")
            }
        }

        // Sistem uyarısı (bildirim/etkinlik gösterilirken araya girmez)
        if (s.alert !== undefined && (o.alert === undefined || s.alert.seq !== o.alert.seq)
            && flashKind !== "notif" && flashKind !== "event")
            flash("alert", s.alert.kind === "call" ? 9000
                  : s.alert.kind === "net" && !s.alert.connected ? 4000 : 2200)

        // Odak sayacı: aşama değişti
        if (s.focus !== undefined && o.focus !== undefined && s.focus.seq !== o.focus.seq)
            toast(s.focus.phase === "break" ? t("Mola zamanı · %1 dk").arg(s.focus.brk) : t("Odak zamanı · %1 dk").arg(s.focus.work),
                  "chronometer")

        // Ekran kaydı: durum bildirimleri
        if (s.rec !== undefined) {
            var or = o.rec, nr = s.rec
            if (nr.state === "starting" && or.state !== "starting") toast("Kayıt başlıyor…", "media-record")
            else if (nr.state === "recording" && or.state !== "recording") toast("Ekran kaydı başladı", "media-record")
            else if (nr.state === "saving" && or.state === "recording") toast("Kayıt kaydediliyor…", "media-record")
            if (nr.last && nr.last !== or.last) {
                banner = { kind: "record", icon: "video-x-generic", app: root.t("Ekran kaydı"),
                           title: root.t("Kayıt kaydedildi"), body: baseName(nr.last) + root.t(" · klasörü açmak için dokun"), ts: Date.now() }
                flash("notif", 7000)
            } else if (nr.error && nr.error !== or.error) {
                toast(nr.error, "dialog-warning")
            }
        }

        var busy = flashKind === "notif" || flashKind === "event"
        if (s.volume !== undefined && !busy &&
            (s.volume.level !== o.volume.level || s.volume.muted !== o.volume.muted))
            flash("volume", 1800)

        if (s.media !== undefined && !busy && s.media.active && s.media.title &&
            (!o.media.active || s.media.title !== o.media.title) && s.media.status === "Playing")
            flash("track", 3500)

        if (s.battery !== undefined && s.battery.present) {
            if (s.battery.charging && !o.battery.charging) {
                chargeKind = "charging"
                flash("charge", 3000)
            } else if (!s.battery.charging && s.battery.level <= 20 && o.battery.level > 20) {
                chargeKind = "low"
                flash("charge", 4500)
            }
        }
    }

    onPanelOpenChanged: {
        sound(panelOpen ? "open" : "close")
        if (panelOpen && tab === 1) markSeen()
        if (!panelOpen) { panelAutoClose.stop(); deviceMenu = false }
    }
    onTabChanged: { deviceMenu = false; if (panelOpen && tab === 1) markSeen(); flyKick() }
    onUiChanged: if (ui.hidden) { panelOpen = false; hovered = false }

    // ------------------------------------------------------------------
    // Arka uçla iletişim
    // ------------------------------------------------------------------
    // API belirteci: launch.sh dosya yolunu son argüman olarak verir (QML_XHR_ALLOW_FILE_READ=1 ile okunur)
    function readToken() {
        try {
            var f = new XMLHttpRequest()
            f.open("GET", "file://" + Qt.application.arguments[Qt.application.arguments.length - 1], false)
            f.send()
            return (f.responseText || "").trim()
        } catch (e) { return "" }
    }
    property string token: ""

    function poll() {
        if (!token) token = readToken()
        var x = new XMLHttpRequest()
        x.open("GET", endpoint + "/state?v=" + stateVersion)
        x.setRequestHeader("X-Island", token)
        x.timeout = 40000
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return
            if (x.status === 200) {
                try {
                    var r = JSON.parse(x.responseText)
                    if (r.v !== stateVersion) {
                        stateVersion = r.v
                        apply(r.s)
                    }
                } catch (e) { console.warn("durum hatası:", e) }
                poll()
            } else {
                if (x.status === 403) token = ""   // arka uç yeniden başlamış: belirteci yeniden oku
                retryTimer.start()
            }
        }
        x.send()
    }

    function send(cmd, arg) {
        var x = new XMLHttpRequest()
        x.open("POST", endpoint + "/cmd")
        x.setRequestHeader("X-Island", token)
        x.setRequestHeader("Content-Type", "application/json")
        x.send(JSON.stringify({ cmd: cmd, arg: arg === undefined ? null : arg }))
    }

    // Ekran takılıp çıkarılınca (ve ayarlar oturunca) çık; launch.sh ana ekranı yeniden bulup başlatır
    Connections {
        target: Qt.application
        function onScreensChanged() { screenSettle.restart() }
    }
    Timer { id: screenSettle; interval: 1500; onTriggered: Qt.exit(3) }

    Component.onCompleted: { screen = targetScreen; x = targetScreen.virtualX; y = targetScreen.virtualY; placed = true; poll(); shrinkTimer.start() }
    Timer { id: retryTimer; interval: 1000; onTriggered: root.poll() }
    Timer { id: transientTimer; onTriggered: root.flashKind = "" }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var d = new Date()
            var c = root.clockOf(d.getTime())
            if (c !== root.clock) root.clock = c
            if (root.rec.state === "recording" || root.live.items.length > 0) root.secTick = d.getTime()
            if (root.pomo.running) root.focusNow = d.getTime()
            var dt = root.locale.toString(d, "dddd, d MMMM")
            if (dt !== root.dateText) root.dateText = dt
        }
    }
    // Göreli zamanlar ve etkinlik uyarıları
    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { root.nowMs = Date.now(); root.updateNext(); root.checkEvents() }
    }
    Timer {
        // Konum yalnızca göründüğü yerde güncellenir (kısa medya görünümü, Müzik sekmesi)
        interval: 500
        repeat: true
        running: root.playing && (root.mode === "media" || (root.mode === "panel" && root.tab === 0))
        triggeredOnStart: true
        onTriggered: root.updatePos()
    }

    // Sistem sekmesi açıkken istatistik toplamayı canlı tut (backend 15 sn sonra durdurur)
    Timer {
        interval: 8000
        repeat: true
        running: root.panelOpen && root.tab === 6
        triggeredOnStart: true
        onTriggered: root.send("stats_on")
    }

    Timer { id: hoverOff; interval: 280; onTriggered: root.hovered = false }
    Timer { id: peekOff; interval: 1100; onTriggered: root.peek = false }
    Timer { id: panelAutoClose; interval: 6000; onTriggered: root.panelOpen = false }

    // ------------------------------------------------------------------
    // ADA
    // ------------------------------------------------------------------
    // Panel açıkken pencere tüm ekranı kaplar; boş alana tık paneli kapatır
    MouseArea {
        anchors.fill: parent
        enabled: root.panelOpen || root.paletteOpen || root.quickOpen
        onClicked: { if (root.quickOpen) root.closeQuickLook(); else { root.panelOpen = false; root.paletteOpen = false } }
    }

    // Çentik: ekranın üst kenarına yapışık siyah gövde + iki yanda içbükey "kulaklar".
    // Böylece ada ayrı bir kutu gibi değil, ekranın bir uzantısı gibi görünür.
    Item {
        id: notch

        width: island.width + 2 * root.ear
        height: island.height
        anchors.top: parent.top
        anchors.topMargin: root.isHidden ? -(height - 3) : 0
        // Ortada; sol/sağda pencere kenara yaslıdır (panel açıkken tüm ekran: boşluk burada verilir)
        x: root.position === "left" ? (root.capture ? root.edgeGap : 0)
         : root.position === "right" ? root.width - width - (root.capture ? root.edgeGap : 0)
         : (root.width - width) / 2
        Behavior on anchors.topMargin { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                id: outline
                readonly property real e: root.ear
                readonly property real w: island.width
                readonly property real h: island.height
                readonly property real r: Math.max(1, Math.min(root.mode === "panel" ? 36 : 28, h / 2, w / 2))

                // sıvı camda gövdeyi cam levha çizer; siyah kulaklar kalmasın
                // siyah gövde, cam levha tam opak olunca kalkar; kapanırken hemen geri gelir (arkadan masaüstü sızmasın)
                fillColor: root.glassBody && glassSlab.opacity >= 1 ? "transparent" : "#000000"
                strokeWidth: -1

                startX: 0; startY: 0
                PathLine { x: 2 * outline.e + outline.w; y: 0 }
                PathArc { x: outline.e + outline.w; y: outline.e; radiusX: outline.e; radiusY: outline.e; direction: PathArc.Counterclockwise }
                PathLine { x: outline.e + outline.w; y: outline.h - outline.r }
                PathArc { x: outline.e + outline.w - outline.r; y: outline.h; radiusX: outline.r; radiusY: outline.r; direction: PathArc.Clockwise }
                PathLine { x: outline.e + outline.r; y: outline.h }
                PathArc { x: outline.e; y: outline.h - outline.r; radiusX: outline.r; radiusY: outline.r; direction: PathArc.Clockwise }
                PathLine { x: outline.e; y: outline.e }
                PathArc { x: 0; y: 0; radiusX: outline.e; radiusY: outline.e; direction: PathArc.Counterclockwise }
            }
            // Kenar ışığı (ambiyans): gövdeyi düz siyah bir kesik olmaktan çıkarır; renksiz, çok ince.
            // Üst kenar ekrana yapışık olduğu için yalnızca yanlar ve alt çizilir.
            ShapePath {
                id: rim
                readonly property real e: root.ear
                readonly property real w: island.width
                readonly property real h: island.height - 0.5
                readonly property real r: Math.max(1, outline.r - 0.5)
                readonly property bool lit: root.vivid && root.playing && root.mode !== "idle"
                readonly property color tint: lit ? root.accent : "white"
                fillColor: "transparent"
                strokeWidth: root.ambient ? 1 : 0
                strokeColor: Qt.rgba(tint.r, tint.g, tint.b, !root.ambient ? 0 : lit ? 0.30 : root.mode === "idle" ? 0.10 : 0.13)
                startX: rim.e + 0.5; startY: rim.e
                PathLine { x: rim.e + 0.5; y: rim.h - rim.r }
                PathArc { x: rim.e + 0.5 + rim.r; y: rim.h; radiusX: rim.r; radiusY: rim.r; direction: PathArc.Counterclockwise }
                PathLine { x: rim.e + rim.w - 0.5 - rim.r; y: rim.h }
                PathArc { x: rim.e + rim.w - 0.5; y: rim.h - rim.r; radiusX: rim.r; radiusY: rim.r; direction: PathArc.Counterclockwise }
                PathLine { x: rim.e + rim.w - 0.5; y: rim.e }
            }
        }

    // Gizli modda da süren Canlı Etkinlik görünsün: kenarda kalan ince şeritte ilerleme çizgisi
    Rectangle {
        visible: root.isHidden && root.act !== null
        anchors.bottom: parent.bottom
        x: root.ear + 6
        width: Math.max(0, island.width - 12)
        height: 2
        radius: 1
        color: Qt.rgba(1, 1, 1, 0.12)
        Rectangle {
            readonly property real f: root.actFrac(root.act)
            height: parent.height
            radius: 1
            color: root.actColor(root.act)
            width: f < 0 ? parent.width * 0.3 : parent.width * f
            x: f < 0 ? hairSweep.pos * (parent.width - width) : 0
            Behavior on width { NumberAnimation { duration: 300 } }
        }
        Item {
            id: hairSweep
            property real pos: 0
            SequentialAnimation on pos {
                running: root.isHidden && root.act !== null && root.actFrac(root.act) < 0
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1; to: 0; duration: 900; easing.type: Easing.InOutSine }
            }
        }
    }

    Rectangle {
        id: island

        x: root.ear
        width: root.islandW
        height: root.islandH
        color: "transparent"
        clip: true

        Behavior on width { SpringAnimation { spring: 3.4; damping: 0.3; epsilon: 0.3 } }
        Behavior on height { SpringAnimation { spring: 3.4; damping: root.mode === "panel" ? 0.36 : 0.3; epsilon: 0.3 } }

        // Sıvı camın "içerik katmanı": cam yüzeyler bu katmanın dokusunu kırar
        GlassBackdrop {
            id: glassBackdrop
            anchors.fill: parent
            // kaynak yalnızca canlıyken gizlenir; cam levha görünürken canlı kalmalı, yoksa kare köşeli içerik sızar
            live: root.glassy && glassSlab.visible
            blurAmount: 0.6 + root.glassFrost * 0.4
            Rectangle {
                anchors.fill: parent
                color: "#0c0c10"
                visible: glassSlab.visible
            }
            Rectangle {
                anchors.fill: parent
                visible: glassSlab.visible
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.26) }
                    GradientStop { position: 0.55; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.06) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.05) }
                }
            }
        Ambient {
            anchors.fill: parent
            visible: root.ambient
            art: root.hasMedia ? (root.media.artUrl || "") : ""
            accent: root.accent
            radius: outline.r
            vivid: root.vivid
            glow: !root.ambient ? 0
                // panelde albüm ışığı yalnızca Müzik sekmesinde; öbür sekmeler (Bildirim, Takvim…) düz kalır
                : root.mode === "panel" ? (root.hasMedia && root.tab === 0 ? (root.vivid ? 1 : 0.9) : 0)
                : root.mode === "media" ? (root.vivid ? 0.9 : 0.8)
                : 0
            // kapalı adada hafif, açık görünümlerde daha belirgin
            bass: root.ambient && root.playing ? root.bass * (root.mode === "idle" ? 0.85 : 0.6) : 0
        }
        }

        // Ada gövdesi: tek cam levha. Üstünde kart/kontrol camı olduğundan ince sürüm (cam üstüne cam yok)
        GlassSurface {
            id: glassSlab
            anchors.fill: parent
            visible: opacity > 0
            opacity: root.glassBody ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
            glassLayer: glassBackdrop
            tick: island.width + island.height
            thin: true
            radiusTL: 0; radiusTR: 0; radiusBL: outline.r; radiusBR: outline.r
            frostAmount: root.glassFrost
            tintAmount: 0.05
            bezelPx: 14
        }

        // Geçici görünümlerde (bildirim, toast, uyarı) kalan süreyi gösteren ince çizgi: ortaya doğru eriyip biter
        Rectangle {
            id: flashBar
            visible: width > 0 && (root.mode === "banner" || root.mode === "toast" || root.mode === "alert" || root.mode === "shot")
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            width: 0
            height: 2
            radius: 1
            color: Qt.rgba(1, 1, 1, 0.3)
        }
        NumberAnimation { id: flashAnim; target: flashBar; property: "width"; to: 0; easing.type: Easing.Linear }

        Keys.onEscapePressed: root.panelOpen = false

        // Dosyayı ada üzerine sürükleyince "rafa bırak" kutusu açılır
        DropArea {
            anchors.fill: parent
            keys: ["text/uri-list"]
            enabled: !root.panelOpen
            onEntered: root.dropHover = true
            onExited: root.dropHover = false
            onDropped: d => {
                root.dropHover = false
                var urls = []
                for (var i = 0; i < d.urls.length; i++) urls.push(d.urls[i].toString())
                root.send("shelf_add", urls)
                root.toast("Rafa eklendi", "folder-download")
            }
        }

        HoverHandler {
            onHoveredChanged: {
                var hold = root.flashKind === "notif" || root.flashKind === "event" || root.flashKind === "shot"
                if (hovered) {
                    hoverOff.stop()
                    peekOff.stop()
                    panelAutoClose.stop()
                    root.peek = true
                    root.hovered = true
                    if (hold) { transientTimer.stop(); flashAnim.pause() }
                } else {
                    hoverOff.restart()
                    peekOff.restart()
                    if (root.panelOpen) panelAutoClose.restart()
                    if (hold) {
                        transientTimer.interval = 1500; transientTimer.restart()
                        flashAnim.stop()
                        flashAnim.from = flashBar.width
                        flashAnim.duration = 1500
                        flashAnim.start()
                    }
                }
            }
        }

        // Boş alana tık: paneli aç/kapat (banner'da ilgili sekmeyi aç). Sağ tık: sessize al / banner'ı kapat (panelde yok).
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => {
                if (m.button === Qt.LeftButton) {
                    if (root.mode === "banner") root.openFromBanner()
                    else {
                        if (!root.panelOpen) root.tab = root.openingTab()
                        root.panelOpen = !root.panelOpen
                    }
                } else if (root.mode === "banner") {
                    root.flashKind = ""
                } else if (root.mode !== "panel") {
                    root.send("vol_mute")   // panelde sağ tık sayfalara aittir (bağlam menüleri)
                }
            }
        }

        // Tekerlek: ses ayarı (panelde listeler kaydırılır)
        WheelHandler {
            property real acc: 0
            enabled: root.mode !== "panel"
            onWheel: e => {
                acc += e.angleDelta.y / 120 * 3
                if (Math.abs(acc) >= 1) {
                    var d = Math.round(acc)
                    acc -= d
                    root.send("vol_delta", d)
                }
            }
        }

        // ==============================================================
        // KAPALI ADA: [sol yuva] saat [sağ yuva]
        // ==============================================================
        View {
            id: idleView
            on: root.mode === "idle"
            width: root.idleW
            height: 32

            // Sol yuva
            Item {
                x: 16
                width: root.slotW
                height: parent.height
                Rectangle {   // ekran kaydı
                    visible: root.leftSlot === "rec"
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10; height: 10; radius: 5
                    color: "#ff453a"
                    SequentialAnimation on opacity {
                        running: root.leftSlot === "rec" && idleView.on
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 650 }
                        NumberAnimation { to: 1; duration: 650 }
                    }
                }
                ActRing {     // Canlı Etkinlik
                    visible: root.leftSlot === "act"
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    frac: root.actFrac(root.act)
                    color: root.actColor(root.act)
                    live: idleView.on
                }
                Item {        // çalan şarkının kapağının yeri (kapağı flyArt çizer)
                    id: idleArt
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22
                }
                Shape {       // odak halkası
                    visible: root.leftSlot === "ring"
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Qt.rgba(1, 1, 1, 0.18)
                        strokeWidth: 2.5
                        fillColor: "transparent"
                        PathAngleArc { centerX: 9; centerY: 9; radiusX: 7.5; radiusY: 7.5; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        strokeColor: root.focusColor
                        strokeWidth: 2.5
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"
                        PathAngleArc { centerX: 9; centerY: 9; radiusX: 7.5; radiusY: 7.5; startAngle: -90; sweepAngle: 360 * root.focusFrac }
                    }
                }
                Rectangle {   // görülmemiş bildirim
                    visible: root.leftSlot === "dot"
                    anchors.verticalCenter: parent.verticalCenter
                    x: 4
                    width: 6; height: 6; radius: 3
                    color: "white"
                }
            }

            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                anchors.centerIn: parent
                text: root.clock
                color: "white"
                font.pixelSize: 15
                font.weight: Font.DemiBold
                font.letterSpacing: -0.1
                font.features: { "tnum": 1 }
            }

            // Sağ yuva (sağa yaslı)
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                layoutDirection: Qt.RightToLeft
                Bars {
                    visible: root.rightBars
                    playing: root.playing
                    levels: root.spectrum
                    live: idleView.on
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    visible: root.rightText !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.rightText
                    color: root.rec.state !== "idle" ? "#ff6961" : root.act !== null ? root.actColor(root.act) : root.focusColor
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.2
                    font.features: { "tnum": 1 }
                }
                Row {         // gizlilik noktaları
                    visible: root.privDots.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Repeater {
                        model: root.privDots
                        Rectangle {
                            required property var modelData
                            width: 7; height: 7; radius: 3.5
                            color: modelData
                        }
                    }
                }
                Ico {         // Rahatsız Etme (başka bir şey yokken)
                    visible: !root.rightBars && root.rightText === "" && root.privDots.length === 0 && root.ui.dnd
                    anchors.verticalCenter: parent.verticalCenter
                    source: root.ic("isle-moon")
                    size: 13
                    tint: "#5e5ce6"
                }
            }
        }

        // ==============================================================
        // BİLDİRİM / YAKLAŞAN ETKİNLİK
        // ==============================================================
        View {
            id: bannerView
            on: root.mode === "banner"
            readonly property bool isEvent: root.banner.kind === "event"
            readonly property bool isAct: root.banner.kind === "activity"
            readonly property bool badged: isEvent || isAct
            width: 440; height: 64

            PeekRow {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                icon: bannerView.isEvent ? root.ic("isle-calendar")
                    : !bannerView.isAct ? ""
                    : root.banner.state === "done" && root.banner.icon !== "timer" ? root.ic("isle-check-symbolic")
                    : root.banner.state === "failed" ? root.ic("isle-warning-symbolic")
                    : root.banner.state === "cancelled" ? root.ic("isle-close-symbolic")
                    : root.actIcon(root.banner.icon)
                badgeColor: bannerView.isEvent ? root.calColor(root.banner.cal)
                    : !bannerView.isAct ? Qt.rgba(1, 1, 1, 0.11)
                    : root.banner.state === "failed" ? "#ff453a"
                    : root.banner.state === "cancelled" ? "#3a3a3c"
                    : root.banner.state === "done" ? (root.banner.icon === "timer" ? "#ff9f0a" : "#30d158")
                    : (root.banner.color || Qt.rgba(1, 1, 1, 0.17))
                title: !!root.banner.code ? root.t("Doğrulama kodu") + " · " + (root.banner.app || "")
                    : bannerView.isEvent
                    ? (root.banner.title || "") + (function () {
                          var m = Math.round((root.banner.start - root.nowMs) / 60000)
                          return m >= 1 ? root.t(" · %1 dk sonra").arg(m) : root.t(" · şimdi")
                      })()
                    : (root.banner.title || root.banner.app || "")
                subtitle: bannerView.isEvent
                    ? root.clockOf(root.banner.start) + (root.banner.end > root.banner.start ? " – " + root.clockOf(root.banner.end) : "")
                      + (root.meetingService(root.banner.url) ? " · " + root.meetingService(root.banner.url)
                         : root.banner.location ? " · " + root.banner.location : "")
                    : (root.banner.body ? String(root.banner.body).replace(/\s+/g, " ") : (root.banner.app || ""))

                Rectangle {   // doğrulama kodu: büyük, dokununca kopyalanır
                    visible: !!root.banner.code
                    width: codeText.implicitWidth + 24; height: 34; radius: 17
                    color: codeMa.pressed ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.16)
                    Text {
                        id: codeText
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.centerIn: parent
                        text: root.prettyCode(root.banner.code || "")
                        color: "white"
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1
                        font.features: { "tnum": 1 }
                    }
                    MouseArea {
                        id: codeMa
                        anchors.fill: parent
                        onClicked: root.copyCode(root.banner.code)
                    }
                }
                Rectangle {
                    visible: bannerView.isEvent && !!root.banner.url
                    width: 58; height: 30; radius: 15
                    color: joinMa.pressed ? "#0060c0" : "#0a84ff"
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.centerIn: parent
                        text: root.t("Katıl")
                        color: "white"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: joinMa
                        anchors.fill: parent
                        onClicked: { root.send("open_url", root.banner.url); root.flashKind = "" }
                    }
                }
            }
            // Bildirimlerde rozetin içinde uygulama simgesi
            AppIcon {
                visible: !bannerView.badged
                x: 18 + 5; y: (parent.height - 22) / 2
                size: 22
                source: root.banner.icon || "notifications"
            }
        }

        // ==============================================================
        // HIZLI BAKIŞ (dosya önizlemesi)
        // ==============================================================
        View {
            id: quickHost
            on: root.mode === "quicklook"
            width: 520; height: quickView.wantH
            QuickLook {
                id: quickView
                anchors.fill: parent
                sh: root
            }
        }

        // ==============================================================
        // KOMUT PALETİ
        // ==============================================================
        View {
            id: paletteHost
            on: root.mode === "palette"
            width: 640; height: paletteView.wantH
            CommandPalette {
                id: paletteView
                anchors.fill: parent
                sh: root
                open: root.paletteOpen
            }
        }

        // ==============================================================
        // CANLI ETKİNLİKLER (fare üstünde): en yeni 3 etkinlik
        // ==============================================================
        View {
            id: liveView
            on: root.mode === "live"
            width: 440; height: 16 + Math.min(3, root.live.items.length) * 52

            Column {
                x: 16; y: 8
                width: parent.width - 32
                Repeater {
                    model: root.live.items.slice(-3).reverse()
                    Item {
                        id: actRow
                        required property var modelData
                        readonly property var a: modelData
                        width: parent.width
                        height: 52
                        HoverHandler { id: rowHover }

                        ActRing {
                            id: aRing
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34; height: 34
                            thickness: 3
                            frac: root.actFrac(actRow.a)
                            color: root.actColor(actRow.a)
                            icon: root.actIcon(actRow.a.icon)
                            live: liveView.on
                        }
                        Column {
                            anchors.left: aRing.right
                            anchors.leftMargin: 12
                            anchors.right: aVal.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                width: parent.width
                                text: actRow.a.title
                                color: "white"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                visible: text !== ""
                                width: parent.width
                                text: actRow.a.subtitle
                                color: Qt.rgba(1, 1, 1, 0.5)
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            id: aVal
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            anchors.right: aStop.visible ? aStop.left : parent.right
                            anchors.rightMargin: aStop.visible ? 8 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.actValue(actRow.a)
                            color: root.actColor(actRow.a)
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.4
                            font.features: { "tnum": 1 }
                        }
                        CtlButton {   // iptal (yalnızca fare satırın üstündeyken)
                            id: aStop
                            visible: rowHover.hovered
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26; height: 26; iconSize: 12
                            icon: root.ic("isle-close-symbolic")
                            filled: true
                            fillColor: Qt.rgba(1, 1, 1, 0.1)
                            onClicked: root.send("activity_end", actRow.a.id)
                        }
                    }
                }
            }
        }

        // ==============================================================
        // EKRAN GÖRÜNTÜSÜ ÖNİZLEMESİ: küçük resim sürüklenebilir; Aç, Kopyala
        // ==============================================================
        View {
            id: shotView
            on: root.mode === "shot"
            width: 404; height: 92

            Item {
                id: shotThumb
                x: 16; y: 14
                width: 104; height: 64
                scale: shotMa.pressed ? 0.95 : 1
                Behavior on scale { NumberAnimation { duration: 100 } }

                Drag.active: shotMa.drag.active
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.mimeData: ({ "text/uri-list": (root.shotInfo.url || "") + "\r\n" })
                Drag.onActiveChanged: root.draggingOut = Drag.active
                Item { id: shotProxy; width: 1; height: 1 }

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.08)
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: root.mode === "shot" ? (root.shotInfo.url || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize: Qt.size(312, 192)
                    }
                }
                Rectangle {   // ince çerçeve
                    anchors.fill: parent
                    radius: 10
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.16)
                }
                MouseArea {
                    id: shotMa
                    anchors.fill: parent
                    drag.target: shotProxy
                    cursorShape: Qt.OpenHandCursor
                    onClicked: { root.send("shot_open"); root.flashKind = "" }
                }
            }
            Column {
                anchors.left: shotThumb.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: shotThumb.verticalCenter
                spacing: 2
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    width: parent.width
                    text: root.t("Ekran görüntüsü alındı")
                    color: "white"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    width: parent.width
                    text: (root.shotInfo.w > 0 ? root.shotInfo.w + " × " + root.shotInfo.h + " · " : "") + (root.shotInfo.name || "")
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                }
                Row {
                    spacing: 8
                    topPadding: 6
                    Repeater {
                        model: [{ k: "open", l: root.t("Aç") }, { k: "copy", l: root.t("Kopyala") }]
                        Rectangle {
                            required property var modelData
                            readonly property bool primary: modelData.k === "open"
                            width: shotBtnText.implicitWidth + 24; height: 26; radius: 13
                            color: primary ? (shotBtnMa.pressed ? "#d1d1d6" : "white")
                                           : (shotBtnMa.pressed ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, shotBtnMa.containsMouse ? 0.22 : 0.15))
                            Text {
                                id: shotBtnText
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                anchors.centerIn: parent
                                text: modelData.l
                                color: parent.primary ? "black" : "white"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: shotBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (modelData.k === "open") root.send("shot_open")
                                    else { root.send("shot_copy"); root.sound("copy"); root.toast(root.t("Görüntü kopyalandı"), "dialog-ok-apply") }
                                    if (modelData.k === "open") root.flashKind = ""
                                }
                            }
                        }
                    }
                }
            }
        }

        // ==============================================================
        // MEDYA (fare üstünde / parça değişince)
        // ==============================================================
        View {
            id: mediaView
            on: root.mode === "media"
            width: 400; height: 84

            Spectrum {     // alt kenarda yumuşak ışık: gerçek ses
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.leftMargin: 26; anchors.rightMargin: 26
                height: 26
                opacity: root.vivid ? 0.32 : 0.22
                color: root.glowColor
                gap: 2
                levels: root.spectrum
            }
            Item {
                id: mArt
                x: 18; y: 12
                width: 44; height: 44
            }
            Column {
                anchors.left: mArt.right
                anchors.leftMargin: 12
                anchors.right: mCtl.left
                anchors.rightMargin: 8
                anchors.verticalCenter: mArt.verticalCenter
                spacing: 1
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    width: parent.width
                    text: root.media.title || root.t("Bilinmeyen parça")
                    color: "white"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    width: parent.width
                    text: root.media.artist || root.media.player || ""
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
            Row {
                id: mCtl
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: mArt.verticalCenter
                spacing: 0
                CtlButton {
                    width: 32; height: 32; iconSize: 16
                    icon: root.ic("isle-backward-symbolic")
                    enabledBtn: root.media.canPrev !== false
                    onClicked: root.send("prev")
                }
                CtlButton {
                    width: 34; height: 34; iconSize: 19
                    icon: root.playing ? root.ic("isle-pause-symbolic") : root.ic("isle-play-symbolic")
                    onClicked: root.send("play_pause")
                }
                CtlButton {
                    width: 32; height: 32; iconSize: 16
                    icon: root.ic("isle-forward-symbolic")
                    enabledBtn: root.media.canNext !== false
                    onClicked: root.send("next")
                }
            }
            IslandSlider {
                sh: root
                x: 18; y: 64
                width: parent.width - 36
                height: 10
                barHeight: 3
                trackColor: Qt.rgba(1, 1, 1, 0.2)
                interactive: root.media.canSeek === true
                smooth: false
                fillColor: "white"
                value: root.media.length > 0 ? root.pos / root.media.length : 0
                onCommitted: v => root.send("seek", v * root.media.length)
            }
        }

        // ==============================================================
        // SES
        // ==============================================================
        View {
            id: volumeView
            on: root.mode === "volume"
            width: 330; height: 44

            Ico {
                id: vIcon
                x: 20
                anchors.verticalCenter: parent.verticalCenter
                source: root.volume.muted ? root.ic("isle-speaker-off-symbolic") : root.ic("isle-speaker-3-symbolic")
                size: 18
                tint: root.volume.muted ? "#ff453a" : "white"
            }
            IslandSlider {
                sh: root
                x: 52
                width: parent.width - 52 - 64
                height: 24
                anchors.verticalCenter: parent.verticalCenter
                barHeight: 8
                trackColor: Qt.rgba(1, 1, 1, 0.16)
                fillColor: root.volume.muted ? Qt.rgba(1, 1, 1, 0.35) : "white"
                value: root.volume.muted ? 0 : root.volume.level / 100
                onMoved: v => root.send("vol_set", Math.round(v * 100))
            }
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                horizontalAlignment: Text.AlignRight
                text: root.volume.muted ? root.t("Sessiz") : root.volume.level
                color: root.volume.muted ? "#ff453a" : "white"
                font.pixelSize: root.volume.muted ? 11 : 14
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
        }

        // ==============================================================
        // RAFA BIRAK (dosya sürüklenirken)
        // ==============================================================
        View {
            id: dropView
            on: root.mode === "drop"
            width: 300; height: 56

            PeekRow {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 18
                icon: root.ic("isle-shelf")
                badgeColor: "#0a84ff"
                title: root.t("Rafa bırak")
                subtitle: root.t("Dosyayı bırakınca rafa eklenir")
            }
        }

        // ==============================================================
        // KISA BİLDİRİM (toast)
        // ==============================================================
        Text {
            id: toastMeasure
            visible: false
            text: root.toastText
            font.family: "Inter"
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
        View {
            id: toastView
            on: root.mode === "toast"
            width: root.islandW; height: 52
            readonly property bool bad: root.toastIcon === "media-record" || root.toastIcon === "dialog-warning"

            PeekRow {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 20
                icon: root.toastIcon === "chronometer" ? root.ic("isle-timer")
                    : toastView.bad ? root.ic(root.toastIcon === "media-record" ? "isle-record-symbolic" : "isle-warning-symbolic")
                    : root.toastIcon === "folder-download" ? root.ic("isle-shelf")
                    : root.ic("isle-check-symbolic")
                badgeColor: root.toastIcon === "chronometer" ? root.focusColor : toastView.bad ? "#ff453a" : "#30d158"
                title: root.toastText
            }
        }

        // ==============================================================
        // CLAUDE CODE İZİN İSTEĞİ: Reddet / İzin ver / Her zaman
        // ==============================================================
        View {
            id: askView
            on: root.mode === "ask"
            width: 480; height: 132
            readonly property var a: root.ask || ({})

            Item {
                x: 20; y: 16
                width: 40; height: 40
                Rectangle {
                    anchors.fill: parent
                    radius: 20
                    color: "#2a1c16"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                }
                Image {
                    anchors.centerIn: parent
                    width: 22; height: 22
                    sourceSize: Qt.size(44, 44)
                    source: root.ic("isle-claude")
                }
                Rectangle {   // bekleyen başka istek varsa sayısı
                    visible: root.agents.asks.length > 1
                    x: 26; y: -4
                    width: 18; height: 18; radius: 9
                    color: "#ff9f0a"
                    Text {
                        anchors.centerIn: parent
                        text: root.agents.asks.length
                        color: "black"
                        font.family: "Inter"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                    }
                }
            }
            Column {
                x: 74; y: 14
                width: parent.width - 74 - 20
                spacing: 6
                Column {
                    width: parent.width
                    spacing: 1
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: parent.width
                        text: root.t("%1 izin istiyor").arg(askView.a.project || "Claude Code")
                        color: "white"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: parent.width
                        text: "Claude Code · " + (askView.a.tool || "")
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    width: Math.min(parent.width, cmdText.implicitWidth + 18)
                    height: 26
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.08)
                    Text {
                        id: cmdText
                        x: 9
                        width: parent.width - 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: askView.a.input || ""
                        color: Qt.rgba(1, 1, 1, 0.9)
                        font.family: "monospace"
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }
                }
                Row {
                    spacing: 8
                    Repeater {
                        model: askView.a.always ? ["deny", "allow", "always"] : ["deny", "allow"]
                        Rectangle {
                            required property string modelData
                            readonly property bool primary: modelData === (askView.a.always ? "always" : "allow")
                            width: lbl.implicitWidth + 28
                            height: 28; radius: 14
                            color: primary ? (bMa.pressed ? "#d1d1d6" : "white")
                                           : (bMa.pressed ? "#48484a" : bMa.containsMouse ? "#3a3a3c" : Qt.rgba(1, 1, 1, 0.17))
                            Text {
                                id: lbl
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                anchors.centerIn: parent
                                text: modelData === "deny" ? root.t("Reddet") : modelData === "allow" ? root.t("İzin ver") : root.t("Her zaman")
                                color: parent.primary ? "black" : "white"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: bMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.send("agent_answer", { id: askView.a.id, answer: modelData })
                            }
                        }
                    }
                }
            }
            // Turuncu alt ışık: adanın yuvarlak alt köşelerine uyar
            Item {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 26
                clip: true
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 56
                    radius: 28
                    opacity: 0.5
                    gradient: Gradient {
                        GradientStop { position: 0.5; color: "transparent" }
                        GradientStop { position: 1; color: "#5a2a08" }
                    }
                }
            }
        }

        // ==============================================================
        // SİSTEM UYARISI: Caps Lock, Bluetooth cihazı, internet
        // ==============================================================
        View {
            id: alertView
            on: root.mode === "alert"
            width: 330; height: 56
            readonly property var a: root.alertD
            readonly property bool headset: String(a.icon || "").indexOf("audio") >= 0

            PeekRow {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 18
                icon: alertView.a.kind === "caps" ? root.ic("isle-capslock-symbolic")
                    : alertView.a.kind === "call" ? root.ic("isle-phone-symbolic")
                    : alertView.a.kind === "bt" ? (alertView.headset ? root.ic("isle-headphones-symbolic") : root.ic("isle-bluetooth-symbolic"))
                    : alertView.a.connected ? root.ic("isle-wifi-symbolic") : root.ic("isle-wifi-off-symbolic")
                badgeColor: alertView.a.kind === "caps" ? Qt.rgba(1, 1, 1, 0.17)
                          : alertView.a.kind === "call" ? "#30d158"
                          : alertView.a.kind === "bt" ? (alertView.a.connected ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.17))
                          : alertView.a.connected ? "#0a84ff" : "#ff453a"
                level: alertView.a.kind === "bt" && alertView.a.connected && alertView.a.battery >= 0 ? alertView.a.battery / 100 : -1
                levelColor: alertView.a.battery >= 0 && alertView.a.battery <= 20 ? "#ff453a" : "#30d158"
                title: alertView.a.kind === "caps" ? "Caps Lock"
                     : alertView.a.kind === "call" ? alertView.a.name
                     : alertView.a.kind === "bt" ? (alertView.a.name || "Bluetooth")
                     : alertView.a.connected ? root.t("Bağlandı") : root.t("İnternet bağlantısı kesildi")
                subtitle: alertView.a.kind === "call" ? (alertView.a.number || root.t("Telefon çalıyor"))
                        : alertView.a.kind === "bt" ? (alertView.a.connected ? root.t("Bağlandı") : root.t("Bağlantı kesildi"))
                        : alertView.a.kind === "net" ? (alertView.a.connected ? (alertView.a.wired ? root.t("Kablolu ağ") : (alertView.a.ssid || "Wi-Fi"))
                                                                              : root.t("Ağ yok"))
                        : ""
                value: alertView.a.kind === "bt" && alertView.a.connected && alertView.a.battery >= 0 ? root.pct(alertView.a.battery) : ""

                // Caps Lock durumu: renkli hap
                Rectangle {
                    visible: alertView.a.kind === "caps"
                    width: capsText.implicitWidth + 20; height: 24; radius: 12
                    color: alertView.a.on ? Qt.rgba(0.19, 0.82, 0.35, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                    Text {
                        id: capsText
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.centerIn: parent
                        text: alertView.a.on ? root.t("Açık") : root.t("Kapalı")
                        color: alertView.a.on ? "#30d158" : Qt.rgba(1, 1, 1, 0.6)
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        // ==============================================================
        // ŞARJ / PİL UYARISI
        // ==============================================================
        View {
            id: chargeView
            on: root.mode === "charge"
            width: 300; height: 56

            PeekRow {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 20
                readonly property bool low: root.chargeKind === "low"
                icon: low ? root.ic("isle-battery-low-symbolic") : root.ic("isle-bolt")
                badgeColor: low ? "#3a1512" : "#0f3a1c"
                iconTint: low ? "#ff453a" : "#30d158"
                level: root.battery.level / 100
                levelColor: low ? "#ff453a" : "#30d158"
                title: low ? root.t("Pil azaldı") : root.t("Şarj oluyor")
                subtitle: low ? root.t("Şarj aletini tak") : root.t("Şarj aleti bağlı")
                value: root.pct(root.battery.level)
                valueColor: low ? "#ff453a" : "white"
            }
        }

        // ==============================================================
        // PANEL
        // ==============================================================
        Item {
            id: panelView
            readonly property bool on: root.mode === "panel"
            width: root.panelW; height: root.panelH
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: on ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: panelView.on ? 120 : 0 }
                    NumberAnimation { duration: panelView.on ? 260 : 80; easing.type: Easing.OutCubic }
                }
            }
            transformOrigin: Item.Top
            scale: on ? root.panelScale : root.panelScale * 0.95
            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 6
                anchors.bottomMargin: 14
                spacing: 4

                // Sekme çubuğu
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 36
                    Layout.leftMargin: 18
                    Layout.rightMargin: 20
                    spacing: 6

                    IslandTabs { sh: root }

                    Item { Layout.fillWidth: true }

                    // Tarih + saat (tıkla: takvim)
                    Row {
                        spacing: 6
                        Layout.alignment: Qt.AlignVCenter
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            anchors.verticalCenter: parent.verticalCenter
                            text: { root.dateText; return root.locale.toString(new Date(), "ddd d MMM") }
                            color: Qt.rgba(1, 1, 1, 0.9)
                            font.pixelSize: 13
                        }
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.clock
                            color: "white"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                        TapHandler { onTapped: root.tab = 3 }
                    }

                    CtlButton {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        icon: root.ic("isle-settings")
                        iconSize: 15
                        tint: root.tab === 9 ? "white" : Qt.rgba(1, 1, 1, 0.6)
                        filled: root.tab === 9
                        fillColor: Qt.rgba(1, 1, 1, 0.12)
                        onClicked: root.tab = root.tab === 9 ? root.tabOrder[0] : 9
                    }
                    CtlButton {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        // Açık göz: ada hep görünür. Kapalı göz: gizli mod (üst kenara çekilir).
                        icon: root.ui.hidden ? "view-hidden" : "view-visible"
                        iconSize: 15
                        tint: root.ui.hidden ? "#636366" : "#aeaeb2"
                        onClicked: root.send("toggle_hide")
                    }
                    CtlButton {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        icon: "go-up"
                        iconSize: 15
                        tint: "#8e8e93"
                        onClicked: root.panelOpen = false
                    }
                }

                // Sayfalar (162 px yükseklik, kenarlardan 28 px)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.panelH - 62
                    Layout.leftMargin: 28
                    Layout.rightMargin: 28
                    Layout.topMargin: 6

                    PageFade {
                        anchors.fill: parent
                        index: 0
                        current: root.tab
                        order: root.tabOrder
                        PageMusic { id: pageMusic; anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 1
                        current: root.tab
                        order: root.tabOrder
                        PageNotifs { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 2
                        current: root.tab
                        order: root.tabOrder
                        PageFocus { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 3
                        current: root.tab
                        order: root.tabOrder
                        PageCalendar { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 4
                        current: root.tab
                        order: root.tabOrder
                        PageControls { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 5
                        current: root.tab
                        order: root.tabOrder
                        PageApps { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 6
                        current: root.tab
                        order: root.tabOrder
                        PageSystem { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 7
                        current: root.tab
                        order: root.tabOrder
                        PageTools { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 8
                        current: root.tab
                        order: root.tabOrder
                        PageWeather { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 9
                        current: root.tab
                        order: root.tabOrder
                        PageSettings { anchors.fill: parent; sh: root }
                    }
                }
                Item { Layout.fillHeight: true }
            }

            // Ses çıkışı seçici (Ana sayfadaki hoparlör düğmesinden açılır)
            Rectangle {
                id: deviceMenuBox
                visible: root.deviceMenu && root.tab === 4
                z: 10
                x: 28
                y: 74
                width: 300
                height: Math.min(4, Math.max(1, root.audio.sinks.length)) * 44 + 12
                radius: 18
                color: "#232325"
                border.width: 1
                border.color: "#3a3a3c"

                Column {
                    anchors.fill: parent
                    anchors.margins: 6
                    Repeater {
                        model: root.audio.sinks
                        Rectangle {
                            required property var modelData
                            readonly property bool current: modelData.name === root.audio["default"]
                            width: parent.width
                            height: 44
                            radius: 12
                            color: devMa.containsMouse ? Qt.rgba(1, 1, 1, 0.17) : "transparent"

                            Ico {
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                source: root.sinkIcon(modelData.kind)
                                size: 18
                                tint: parent.current ? root.accent : "white"
                            }
                            Text {
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                x: 40
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 40 - 36
                                text: modelData.desc
                                color: parent.current ? root.accent : "white"
                                font.pixelSize: 12
                                font.weight: parent.current ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }
                            Ico {
                                visible: parent.current
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                source: "task-complete"
                                size: 14
                                tint: root.accent
                            }
                            MouseArea {
                                id: devMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.send("audio_set", modelData.name)
                                    root.deviceMenu = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Boyun: ayrılırken/birleşirken iki gövdeyi bir damla gibi bağlar, uzadıkça incelip kopar
    Shape {
        id: neck
        readonly property real aR: root.satOnLeft ? sat.edge + root.satW : root.ear + island.width   // soldaki gövdenin sağ kenarı
        readonly property real bL: root.satOnLeft ? root.ear : sat.edge                              // sağdaki gövdenin sol kenarı
        readonly property real d: bL - aR
        readonly property real yEnd: root.satH * 0.8
        readonly property real yMid: yEnd * Math.max(0, Math.min(1, 1 - d / 7))
        visible: d > -4 && d < 7 && yMid > 0.4 && Math.abs(root.satP) > 0.003
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "#000000"
            strokeWidth: -1
            startX: neck.aR - 6; startY: 0
            PathLine { x: neck.bL + 6; y: 0 }
            PathLine { x: neck.bL + 6; y: neck.yEnd }
            PathQuad { x: neck.aR - 6; y: neck.yEnd; controlX: (neck.aR + neck.bL) / 2; controlY: 2 * neck.yMid - neck.yEnd }
            PathLine { x: neck.aR - 6; y: 0 }
        }
    }

    // ---- Ayrılan küçük ada (aynı çentik biçimi, küçük): kapak ya da ikinci etkinlik/odak halkası
    Item {
        id: sat
        // gövdenin sol kenarı (notch koordinatı): birleşikken ana adanın içinde, ayrılınca yanında
        readonly property real edge: root.satOnLeft ? root.ear - (root.satW + root.satGap) * root.satP
                                                    : root.ear + island.width - root.satW + (root.satW + root.satGap) * root.satP
        readonly property real vis: Math.max(0, Math.min(1, root.satP))
        x: edge - root.ear
        y: 0
        width: root.satW + 2 * root.ear
        height: root.satH
        visible: Math.abs(root.satP) > 0.003

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                id: so
                readonly property real e: root.ear
                readonly property real w: root.satW
                readonly property real h: root.satH
                readonly property real r: Math.min(h / 2, w / 2)
                fillColor: "#000000"
                strokeWidth: -1
                startX: 0; startY: 0
                PathLine { x: 2 * so.e + so.w; y: 0 }
                PathArc { x: so.e + so.w; y: so.e; radiusX: so.e; radiusY: so.e; direction: PathArc.Counterclockwise }
                PathLine { x: so.e + so.w; y: so.h - so.r }
                PathArc { x: so.e + so.w - so.r; y: so.h; radiusX: so.r; radiusY: so.r; direction: PathArc.Clockwise }
                PathLine { x: so.e + so.r; y: so.h }
                PathArc { x: so.e; y: so.h - so.r; radiusX: so.r; radiusY: so.r; direction: PathArc.Clockwise }
                PathLine { x: so.e; y: so.e }
                PathArc { x: 0; y: 0; radiusX: so.e; radiusY: so.e; direction: PathArc.Counterclockwise }
            }
        }
        // ince kenar ışığı (ana adayla uyumlu)
        Item {
            x: root.ear; width: root.satW; height: root.satH
            opacity: sat.vis
            Item {   // kapak yeri
                id: satArt
                visible: root.satLast === "media"
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                width: 22; height: 22
            }
            ActRing {
                visible: root.satLast === "act2"
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                width: 20; height: 20
                property var a2: root.live.items.length > 1 ? root.live.items[root.live.items.length - 2] : null
                frac: root.actFrac(a2)
                color: root.actColor(a2)
                live: sat.visible
            }
            ActRing {
                visible: root.satLast === "focus"
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                width: 20; height: 20
                frac: root.focusFrac
                color: root.focusColor
                live: sat.visible
            }
        }
        MouseArea {
            x: root.ear; width: root.satW; height: root.satH
            enabled: root.satP > 0.6
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.satLast === "media") root.tab = 0
                else if (root.satLast === "focus") root.tab = 2
                root.panelOpen = true
            }
        }
    }

    // ---- Uçan kapak: ada, ayrılan daire, müzik görünümü ve panel arasında akan tek kapak
    ArtImage {
        id: flyArt
        z: 60
        width: 22; height: 22; radius: 6
        opacity: root.artHome === "none" ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 180 } }
        source: root.hasMedia ? (root.media.artUrl || "") : ""
        MouseArea {
            anchors.fill: parent
            enabled: root.artHome === "media" || root.artHome === "panel"
            onClicked: root.send("raise")
        }
    }
    }
}
