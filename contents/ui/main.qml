import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Window
import org.kde.layershell as LayerShell

Window {
    id: root

    color: "transparent"
    title: "dynamic-island"
    // launch.sh ana ekranın adını argüman olarak verir; yoksa Qt'nin birincil ekranı.
    // Qt pencerenin ekranını geometrisinden seçtiği için konum da o ekrana taşınır (yoksa eDP'ye düşer).
    readonly property var targetScreen: {
        const want = Qt.application.arguments[Qt.application.arguments.length - 1]
        for (const s of Qt.application.screens)
            if (s.name === want) return s
        return Qt.application.screens[0]
    }
    flags: Qt.FramelessWindowHint

    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop
    LayerShell.Window.wantsToBeOnActiveScreen: false
    LayerShell.Window.scope: "dynamic-island"
    LayerShell.Window.exclusionZone: -1
    // Klavye yalnızca panel açıkken (not yazmak için) ve tıklayınca odak alır
    LayerShell.Window.keyboardInteractivity: panelOpen ? LayerShell.Window.KeyboardInteractivityOnDemand
                                                       : LayerShell.Window.KeyboardInteractivityNone

    // Pencere, ekran ve layer-shell ayarları uygulandıktan sonra gösterilmeli (sıra önemli)
    property bool placed: false
    visible: placed && !fullscreen

    Item {
        focus: true
        Keys.onEscapePressed: root.panelOpen = false
    }

    readonly property string endpoint: "http://127.0.0.1:47615"
    readonly property var calColors: ["#6ea8fe", "#30d158", "#ffd60a", "#bf5af2", "#ff375f"]

    // Vurgu rengi: çalan parçanın albüm kapağından; kapak yoksa sabit, yumuşak bir mavi.
    // Anlamsal renkler (kırmızı = uyarı/kayıt, sarı = sıcak/Gece Işığı, yeşil = şarj) ayrıdır.
    readonly property color accentDefault: "#6ea8fe"
    property color accent: accentExtractor.result
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
                              lyrics: true, meeting_alerts: true, privacy_dots: true, claudeHooks: false,
                              accounts: [], calendars: 0, shortcuts: {} })
    // Claude Code: bekleyen izin istekleri (en eskisi önce) ve son "bitti" haberi
    property var agents: ({ asks: [], done: { seq: 0 } })
    readonly property var ask: agents.asks.length > 0 ? agents.asks[0] : null
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
    property int tab: 0                 // 0 Müzik, 1 Bildirim, 2 Odak, 3 Takvim, 4 Kontrol, 5 Uygulama, 6 Sistem, 7 Araçlar
    property bool hovered: false
    property string flashKind: ""       // volume | charge | track | notif | event
    property string chargeKind: "charging"
    property var banner: ({})

    readonly property bool isHidden: ui.hidden && !peek && !panelOpen && !dropHover && flashKind === ""

    readonly property string mode: {
        if (panelOpen) return "panel"
        if (dropHover) return "drop"
        if (ask !== null) return "ask"
        if (flashKind === "notif" || flashKind === "event") return "banner"
        if (flashKind === "toast") return "toast"
        if (flashKind === "alert") return "alert"
        if (flashKind === "volume") return "volume"
        if (flashKind === "charge") return "charge"
        if (flashKind === "track" || (hovered && hasMedia)) return "media"
        return "idle"
    }

    // Kapalı ada (Isle): [sol yuva] saat [sağ yuva]. Saat ortada kalsın diye iki yuva eşit genişlikte.
    readonly property string leftSlot: rec.state !== "idle" ? "rec" : hasMedia ? "art" : focusOn ? "ring" : unread > 0 ? "dot" : ""
    readonly property string rightText: rec.state === "recording" ? fmt(secTick - rec.since)
                                      : rec.state !== "idle" ? "" : focusOn ? mmss(focusLeft) : ""
    readonly property bool rightBars: hasMedia && rec.state === "idle"
    readonly property int privW: privDots.length ? privDots.length * 11 - 4 : 0
    readonly property int slotW: {
        var parts = [rightBars ? 18 : 0, rightText !== "" ? 44 : 0, privW].filter(function (w) { return w > 0 })
        var w = 0
        for (var i = 0; i < parts.length; i++) w += parts[i] + (i ? 6 : 0)
        return Math.max(24, w)
    }
    readonly property int idleW: 32 + 2 * slotW + 20 + 46

    // Açık panel: geniş ve alçak (Isle ölçüleri). Başlık 40 + sayfa 150 + alt boşluk 14.
    readonly property real panelScale: 1
    readonly property int panelW: lyricsWant ? 760 : 600
    readonly property int panelH: 212

    readonly property int islandW: {
        switch (mode) {
        case "panel": return panelW
        case "drop": return 300
        case "toast": return Math.min(420, Math.max(260, toastMeasure.implicitWidth + 32 + 10 + 40))
        case "banner": return 440
        case "media": return 400
        case "volume": return 300
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
        case "drop": return 56
        case "toast": return 52
        case "banner": return 64
        case "media": return 84
        case "volume": return 52
        case "charge": return 56
        case "alert": return 56
        case "ask": return 132
        default: return 32
        }
    }

    // Pencere: büyürken anında (yay animasyonunun taşması için boşlukla), animasyon bitince
    // çentiğe sıkıca daralır; böylece altındaki uygulamaların tıklamasını engellemez.
    // Panel açıkken tüm ekranı kaplar (boş alana tıklayınca panel kapansın diye).
    readonly property bool capture: panelOpen && !draggingOut
    readonly property int wantW: capture ? Screen.width : islandW + 2 * ear + 60
    readonly property int wantH: capture ? Screen.height : (isHidden ? 6 : islandH + 30)
    readonly property int restW: capture ? Screen.width : islandW + 2 * ear
    readonly property int restH: capture ? Screen.height : (isHidden ? 6 : islandH + 2)
    width: 256
    height: 92
    onWantWChanged: { if (wantW > width) width = wantW; shrinkTimer.restart() }
    onWantHChanged: { if (wantH > height) height = wantH; shrinkTimer.restart() }
    Timer {
        id: shrinkTimer
        interval: 450
        onTriggered: { root.width = root.restW; root.height = root.restH }
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
        if (s < 60) return "şimdi"
        if (s < 3600) return Math.floor(s / 60) + " dk"
        if (s < 86400) return Math.floor(s / 3600) + " sa"
        return Math.floor(s / 86400) + " g"
    }

    function untilText(ev) {
        var m = Math.ceil((ev.start - nowMs) / 60000)
        if (m <= 0) return "Şimdi · " + clockOf(ev.start)
        if (m < 60) return m + " dk sonra · " + clockOf(ev.start)
        return clockOf(ev.start) + " · " + Math.floor(m / 60) + " sa " + (m % 60) + " dk"
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

    // Isle'nin tek renk ikonları (contents/icons)
    function ic(n) { return Qt.resolvedUrl("../icons/" + n + ".svg") }

    function baseName(p) { return String(p).split("/").pop() }

    function flash(kind, ms) {
        flashKind = kind
        transientTimer.interval = ms
        transientTimer.restart()
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

    function openFromBanner() {
        var k = banner.kind
        flashKind = ""
        if (k === "record") { send("open_recording"); return }
        if (k === "agent") return
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
        if (s.rec !== undefined) rec = s.rec
        if (s.focus !== undefined) { pomo = s.focus; focusNow = Date.now() }
        if (s.lyrics !== undefined) lyr = s.lyrics
        if (s.privacy !== undefined) priv = s.privacy
        if (s.alert !== undefined) alertD = s.alert
        if (s.agents !== undefined) agents = s.agents
        if (s.settings !== undefined) settings = s.settings
        if (s.calendar !== undefined) { cal = s.calendar; updateNext() }
        if (s.calAdd !== undefined && s.calAdd.seq !== calAddSeq) {
            if (calAddSeq >= 0) toast(s.calAdd.ok ? "Eklendi · " + s.calAdd.msg : "Eklenemedi: " + s.calAdd.msg,
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
                    banner = { kind: "notif", icon: n.icon, app: n.app, title: n.title, body: n.body, ts: n.ts }
                    flash("notif", 5500)
                }
            }
            recount()
        }

        if (first) { loaded = true; return }

        // Kısayol (Meta+Alt+I) ile panel aç/kapat
        if (s.panelReq !== undefined && s.panelReq !== o.panelReq) panelOpen = !panelOpen
        if (s.tabReq !== undefined && s.tabReq.seq !== o.tabReq.seq) {
            tab = Math.max(0, Math.min(8, s.tabReq.tab))
            if (s.tabReq.lyrics !== undefined) lyricsOn = s.tabReq.lyrics
            panelOpen = true
        }

        // Claude Code işini bitirdi
        if (s.agents !== undefined && o.agents !== undefined && s.agents.done.seq !== o.agents.done.seq) {
            var dn = s.agents.done
            banner = { kind: "agent", icon: ic("isle-claude"), app: "Claude Code",
                       title: (dn.project ? dn.project + " · " : "") + "Claude Code bitirdi",
                       body: dn.message || "", ts: Date.now() }
            if (!panelOpen) flash("notif", 7000)
        }

        // Sistem uyarısı (bildirim/etkinlik gösterilirken araya girmez)
        if (s.alert !== undefined && (o.alert === undefined || s.alert.seq !== o.alert.seq)
            && flashKind !== "notif" && flashKind !== "event")
            flash("alert", s.alert.kind === "net" && !s.alert.connected ? 4000 : 2200)

        // Odak sayacı: aşama değişti
        if (s.focus !== undefined && o.focus !== undefined && s.focus.seq !== o.focus.seq)
            toast(s.focus.phase === "break" ? "Mola zamanı · " + s.focus.brk + " dk" : "Odak zamanı · " + s.focus.work + " dk",
                  "chronometer")

        // Ekran kaydı: durum bildirimleri
        if (s.rec !== undefined) {
            var or = o.rec, nr = s.rec
            if (nr.state === "starting" && or.state !== "starting") toast("Kayıt başlıyor…", "media-record")
            else if (nr.state === "recording" && or.state !== "recording") toast("Ekran kaydı başladı", "media-record")
            else if (nr.state === "saving" && or.state === "recording") toast("Kayıt kaydediliyor…", "media-record")
            if (nr.last && nr.last !== or.last) {
                banner = { kind: "record", icon: "video-x-generic", app: "Ekran kaydı",
                           title: "Kayıt kaydedildi", body: baseName(nr.last) + " · klasörü açmak için dokun", ts: Date.now() }
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
        if (panelOpen && tab === 1) markSeen()
        if (!panelOpen) { panelAutoClose.stop(); deviceMenu = false }
    }
    onTabChanged: { deviceMenu = false; if (panelOpen && tab === 1) markSeen() }
    onUiChanged: if (ui.hidden) { panelOpen = false; hovered = false }

    // ------------------------------------------------------------------
    // Arka uçla iletişim
    // ------------------------------------------------------------------
    function poll() {
        var x = new XMLHttpRequest()
        x.open("GET", endpoint + "/state?v=" + stateVersion)
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
                retryTimer.start()
            }
        }
        x.send()
    }

    function send(cmd, arg) {
        var x = new XMLHttpRequest()
        x.open("POST", endpoint + "/cmd")
        x.setRequestHeader("X-Island", "1")
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
            if (root.rec.state === "recording") root.secTick = d.getTime()
            if (root.pomo.running) root.focusNow = d.getTime()
            var t = Qt.locale("tr_TR").toString(d, "dddd, d MMMM")
            if (t !== root.dateText) root.dateText = t
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
        interval: 250
        repeat: true
        running: root.playing && (root.mode === "media" || root.mode === "panel")
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
        enabled: root.panelOpen
        onClicked: root.panelOpen = false
    }

    // Çentik: ekranın üst kenarına yapışık siyah gövde + iki yanda içbükey "kulaklar".
    // Böylece ada ayrı bir kutu gibi değil, ekranın bir uzantısı gibi görünür.
    Item {
        id: notch

        width: island.width + 2 * root.ear
        height: island.height
        anchors.top: parent.top
        anchors.topMargin: root.isHidden ? -(height - 3) : 0
        anchors.horizontalCenter: parent.horizontalCenter
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

                fillColor: "#000000"
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
                var hold = root.flashKind === "notif" || root.flashKind === "event"
                if (hovered) {
                    hoverOff.stop()
                    peekOff.stop()
                    panelAutoClose.stop()
                    root.peek = true
                    root.hovered = true
                    if (hold) transientTimer.stop()
                } else {
                    hoverOff.restart()
                    peekOff.restart()
                    if (root.panelOpen) panelAutoClose.restart()
                    if (hold) { transientTimer.interval = 1500; transientTimer.restart() }
                }
            }
        }

        // Boş alana tık: paneli aç/kapat (banner'da ilgili sekmeyi aç). Sağ tık: sessize al / banner'ı kapat.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => {
                if (m.button === Qt.LeftButton) {
                    if (root.mode === "banner") root.openFromBanner()
                    else {
                        if (!root.panelOpen) root.tab = root.tab   // son sekme korunur
                        root.panelOpen = !root.panelOpen
                    }
                } else if (root.mode === "banner") {
                    root.flashKind = ""
                } else {
                    root.send("vol_mute")
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

        // Görünüm geçişi: ada büyürken içerik hafif gecikmeyle belirir
        component View: Item {
            id: v
            property bool on: false
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: on ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: v.on ? 90 : 0 }
                    NumberAnimation { duration: v.on ? 220 : 80; easing.type: Easing.OutCubic }
                }
            }
            transformOrigin: Item.Top
            scale: on ? 1 : 0.94
            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        }

        // Müzik çubukları (Isle): beyaz, duraklayınca soluk
        component Bars: Row {
            id: bars
            property bool live: true
            spacing: 2
            opacity: root.playing ? 1 : 0.43
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    width: 3
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 1.5
                    height: 4
                    color: "white"
                    SequentialAnimation on height {
                        running: root.playing && bars.live
                        loops: Animation.Infinite
                        NumberAnimation { to: 12 - (index % 2) * 3; duration: 260 + index * 90; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 4 + index % 3; duration: 300 + index * 70; easing.type: Easing.InOutSine }
                    }
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
                ArtImage {    // çalan şarkının kapağı
                    visible: root.leftSlot === "art"
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: 6
                    source: root.media.artUrl || ""
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
                    live: idleView.on
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    visible: root.rightText !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.rightText
                    color: root.rec.state !== "idle" ? "#ff6961" : root.focusColor
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
            width: 440; height: 64

            PeekRow {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                icon: bannerView.isEvent ? root.ic("isle-calendar") : ""
                badgeColor: bannerView.isEvent ? root.calColor(root.banner.cal) : "#1c1c1e"
                title: bannerView.isEvent
                    ? (root.banner.title || "") + (function () {
                          var m = Math.round((root.banner.start - root.nowMs) / 60000)
                          return m >= 1 ? " · " + m + " dk sonra" : " · şimdi"
                      })()
                    : (root.banner.title || root.banner.app || "")
                subtitle: bannerView.isEvent
                    ? root.clockOf(root.banner.start) + (root.banner.end > root.banner.start ? " – " + root.clockOf(root.banner.end) : "")
                      + (root.meetingService(root.banner.url) ? " · " + root.meetingService(root.banner.url)
                         : root.banner.location ? " · " + root.banner.location : "")
                    : (root.banner.body ? String(root.banner.body).replace(/\s+/g, " ") : (root.banner.app || ""))

                Rectangle {
                    visible: bannerView.isEvent && !!root.banner.url
                    width: 58; height: 30; radius: 15
                    color: joinMa.pressed ? "#0060c0" : "#0a84ff"
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.centerIn: parent
                        text: "Katıl"
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
                visible: !bannerView.isEvent
                x: 18 + 5; y: (parent.height - 22) / 2
                size: 22
                source: root.banner.icon || "notifications"
            }
        }

        // ==============================================================
        // MEDYA (fare üstünde / parça değişince)
        // ==============================================================
        View {
            id: mediaView
            on: root.mode === "media"
            width: 400; height: 84

            ArtImage {
                id: mArt
                x: 18; y: 12
                width: 44; height: 44; radius: 10
                source: root.media.artUrl || ""
                MouseArea { anchors.fill: parent; onClicked: root.send("raise") }
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
                    text: root.media.title || "Bilinmeyen parça"
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
                x: 18; y: 64
                width: parent.width - 36
                height: 10
                barHeight: 3
                trackColor: Qt.rgba(1, 1, 1, 0.2)
                interactive: root.media.canSeek === true
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
            width: 300; height: 52

            PeekRow {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 20
                icon: root.volume.muted ? root.ic("isle-speaker-off-symbolic") : root.ic("isle-speaker-3-symbolic")
                badgeColor: root.volume.muted ? "#ff453a" : "#2c2c2e"
                level: root.volume.muted ? 0 : root.volume.level / 100
                title: root.volume.muted ? "Sessiz" : "Ses"
                subtitle: {
                    for (var i = 0; i < root.audio.sinks.length; i++)
                        if (root.audio.sinks[i].name === root.audio["default"]) return root.audio.sinks[i].desc
                    return ""
                }
                value: root.volume.muted ? "" : root.volume.level + "%"
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
                title: "Rafa bırak"
                subtitle: "Dosyayı bırakınca rafa eklenir"
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
                        text: (askView.a.project || "Claude Code") + " izin istiyor"
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
                                           : (bMa.pressed ? "#48484a" : bMa.containsMouse ? "#3a3a3c" : "#2c2c2e")
                            Text {
                                id: lbl
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                anchors.centerIn: parent
                                text: modelData === "deny" ? "Reddet" : modelData === "allow" ? "İzin ver" : "Her zaman"
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
            // Turuncu alt ışık (Isle): adanın yuvarlak alt köşelerine uyar
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
                    : alertView.a.kind === "bt" ? (alertView.headset ? root.ic("isle-headphones-symbolic") : root.ic("isle-bluetooth-symbolic"))
                    : alertView.a.connected ? root.ic("isle-wifi-symbolic") : root.ic("isle-wifi-off-symbolic")
                badgeColor: alertView.a.kind === "caps" ? "#2c2c2e"
                          : alertView.a.kind === "bt" ? (alertView.a.connected ? "#0a84ff" : "#2c2c2e")
                          : alertView.a.connected ? "#0a84ff" : "#ff453a"
                level: alertView.a.kind === "bt" && alertView.a.connected && alertView.a.battery >= 0 ? alertView.a.battery / 100 : -1
                levelColor: alertView.a.battery >= 0 && alertView.a.battery <= 20 ? "#ff453a" : "#30d158"
                title: alertView.a.kind === "caps" ? "Caps Lock"
                     : alertView.a.kind === "bt" ? (alertView.a.name || "Bluetooth")
                     : alertView.a.connected ? "Bağlandı" : "İnternet bağlantısı kesildi"
                subtitle: alertView.a.kind === "bt" ? (alertView.a.connected ? "Bağlandı" : "Bağlantı kesildi")
                        : alertView.a.kind === "net" ? (alertView.a.connected ? (alertView.a.wired ? "Kablolu ağ" : (alertView.a.ssid || "Wi-Fi"))
                                                                              : "Ağ yok")
                        : ""
                value: alertView.a.kind === "bt" && alertView.a.connected && alertView.a.battery >= 0 ? alertView.a.battery + "%" : ""

                // Caps Lock durumu: renkli hap (Isle)
                Rectangle {
                    visible: alertView.a.kind === "caps"
                    width: capsText.implicitWidth + 20; height: 24; radius: 12
                    color: alertView.a.on ? Qt.rgba(0.19, 0.82, 0.35, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                    Text {
                        id: capsText
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.centerIn: parent
                        text: alertView.a.on ? "Açık" : "Kapalı"
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
                title: low ? "Pil azaldı" : "Şarj oluyor"
                subtitle: low ? "Şarj aletini tak" : "Şarj aleti bağlı"
                value: root.battery.level + "%"
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

                    Item {
                        id: tabBar
                        Layout.fillHeight: true
                        Layout.preferredWidth: selW + (tabs.length - 1) * otherW

                        readonly property var tabs: [
                            { icon: root.ic("isle-music"), label: "Müzik" },
                            { icon: root.ic("isle-bell"), label: "Bildirim" },
                            { icon: root.ic("isle-timer"), label: "Odak" },
                            { icon: root.ic("isle-calendar"), label: "Takvim" },
                            { icon: root.ic("isle-sun-symbolic"), label: "Kontrol" },
                            { icon: "view-app-grid-symbolic", label: "Uygulama" },
                            { icon: root.ic("isle-gauge"), label: "Sistem" },
                            { icon: root.ic("isle-shelf"), label: "Araçlar" }
                        ]
                        // Seçili sekme etiketiyle birlikte hap; diğerleri yalnızca ikon
                        // Seçili sekmenin genişliği etiketine göre (Isle: 10 px iç boşluk, 6 px ikon arası)
                        readonly property var labelW: [42, 52, 34, 46, 50, 62, 44, 50]
                        // Ayarlar (8) bir sekme değil: o açıkken hiçbir sekme seçili görünmez
                        readonly property real selW: root.tab < 8 ? 20 + 16 + 6 + labelW[root.tab] : otherW
                        readonly property real otherW: 32

                        Rectangle {
                            width: tabBar.selW
                            height: 28
                            y: 4
                            x: root.tab * tabBar.otherW
                            visible: root.tab < 8
                            radius: 14
                            color: Qt.rgba(1, 1, 1, 0.09)
                            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        }

                        Row {
                            anchors.fill: parent
                            Repeater {
                                model: tabBar.tabs
                                Item {
                                    required property var modelData
                                    required property int index
                                    width: root.tab === index ? tabBar.selW : tabBar.otherW
                                    Rectangle {
                                        visible: tabMa.containsMouse && root.tab !== index
                                        anchors.centerIn: parent
                                        width: parent.width; height: 28; radius: 14
                                        color: Qt.rgba(1, 1, 1, 0.05)
                                    }
                                    height: 36
                                    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Ico {
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: modelData.icon
                                            size: 16
                                            tint: "white"
                                            opacity: root.tab === index ? 1 : (tabMa.containsMouse ? 0.9 : 0.55)
                                        }
                                        Text {
                                            renderType: Text.CurveRendering
                                            font.family: "Inter"
                                            opacity: root.tab === index ? 1 : 0
                                            visible: opacity > 0
                                            Behavior on opacity { NumberAnimation { duration: 200 } }
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.label
                                            color: "white"
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                    // rozetler: okunmamış bildirim, kayıt sürüyor
                                    Rectangle {
                                        visible: (index === 1 && root.unread > 0) || (index === 5 && root.rec.state !== "idle")
                                        x: parent.width / 2 + 3; y: 7
                                        width: 6; height: 6; radius: 3
                                        color: "#ff453a"
                                    }
                                    MouseArea {
                                        id: tabMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.tab = index
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Tarih + saat (tıkla: takvim)
                    Row {
                        spacing: 6
                        Layout.alignment: Qt.AlignVCenter
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            anchors.verticalCenter: parent.verticalCenter
                            text: { root.dateText; return Qt.locale().toString(new Date(), "ddd d MMM") }
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
                        tint: root.tab === 8 ? "white" : Qt.rgba(1, 1, 1, 0.6)
                        filled: root.tab === 8
                        fillColor: Qt.rgba(1, 1, 1, 0.12)
                        onClicked: root.tab = root.tab === 8 ? 0 : 8
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

                // Sayfalar (Isle: 150 px yükseklik, kenarlardan 28 px)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    Layout.leftMargin: 28
                    Layout.rightMargin: 28
                    Layout.topMargin: 6

                    PageFade {
                        anchors.fill: parent
                        index: 0
                        current: root.tab
                        PageMusic { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 1
                        current: root.tab
                        PageNotifs { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 2
                        current: root.tab
                        PageFocus { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 3
                        current: root.tab
                        PageCalendar { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 4
                        current: root.tab
                        PageControls { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 5
                        current: root.tab
                        PageApps { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 6
                        current: root.tab
                        PageSystem { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 7
                        current: root.tab
                        PageTools { anchors.fill: parent; sh: root }
                    }
                    PageFade {
                        anchors.fill: parent
                        index: 8
                        current: root.tab
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
                            color: devMa.containsMouse ? "#2c2c2e" : "transparent"

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
    }
}
