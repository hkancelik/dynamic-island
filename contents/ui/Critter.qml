pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

// Adanın küçük sakini. Tamamen vektör (resim yok): yaylı fizik, göz kırpma, fareyi izleyen gözler,
// müziğe dans, odakta laptop, gece uyku, sevinçte konfeti.
//
//   Critter { size: 24; mood: "music"; bass: root.bass; body: root.accent }
//   critter.cheer(); critter.love(); critter.startle()
//
// Çizim 100x100'lük bir tuvalde yapılır ve `size` kadar ölçeklenir; küçükken ayrıntı kaybolmaz, büyüyünce keskin kalır.
Item {
    id: c

    property real size: 24
    property string mood: "idle"          // idle | music | focus | sleep | sad
    property real bass: 0                 // 0..1, müzik vuruşları
    property color body: "#f08aa0"
    property bool active: true
    property bool pointerOn: false        // fare adanın üstünde mi
    property real pointerX: 0             // yerel koordinat (px)
    property real pointerY: 0
    property bool fidgets: true           // boşta kendi kendine yaptığı küçük şovlar

    implicitWidth: size
    implicitHeight: size

    // geçici duygu (emote); bitince `mood`a döner
    property string emoteName: ""
    readonly property string face: emoteName !== "" ? emoteName : mood

    // ---- fiziksel durum
    property real t: 0
    property real hop: 0                  // zeminden yükseklik (birim)
    property real vy: 0
    property real sq: 0                   // ezilme (+) / uzama (-)
    property real sqv: 0
    property real lean: 0
    property real spin: 0
    property real pendT: 0
    property real pendV: 0
    property real earA: 0
    property real earV: 0
    property real lookX: 0
    property real lookY: 0
    property real wanderX: 0
    property real wanderY: 0
    property real wanderT: 0
    property real blinkIn: 2
    property real blinkT: 0
    property real fidgetIn: 6
    property real armL: 8
    property real armR: 8
    property real cheerJumps: 0
    property real kickCool: 0
    property real bassPrev: 0
    // ---- yumuşatılmış hedefler
    property real smile: 0.5
    property real mouthOpen: 0
    property real blush: 0.15
    property real happyA: 0
    property real closedA: 0
    property real squint: 0
    property real eyeScale: 1
    property real phonesA: 0
    property real laptopA: 0
    property real glassesA: 0
    property real zzzA: 0
    property real notesA: 0
    property real footL: 0
    property real footR: 0
    // ---- tek seferlik efektler (0..1)
    property real confetti: 1
    property real hearts: 1
    property real bang: 0                 // "!" belirmesi

    readonly property color ink: "#1d1d26"
    readonly property color white: "#fbfbff"
    readonly property color pink: "#ff8fa3"

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

    function jump(v) {                    // hazırlık çömelmesi, sonra sıçrayış
        pendV = v
        pendT = 0.09
        sqv += 7
    }
    function emote(name, ms) {
        emoteName = name
        emoteTimer.interval = ms || 1800
        emoteTimer.restart()
        if (name === "cheer") { confetti = 0; confettiAnim.restart(); cheerJumps = 2; jump(215) }
        else if (name === "love") { hearts = 0; heartsAnim.restart(); sqv += 5 }
        else if (name === "surprise") { bang = 0; bangAnim.restart(); jump(120) }
        else if (name === "greet") { jump(90) }
    }
    function cheer() { emote("cheer", 2700) }
    function love() { emote("love", 2300) }
    function startle() { emote("surprise", 1500) }

    Timer { id: emoteTimer; onTriggered: c.emoteName = "" }
    NumberAnimation { id: confettiAnim; target: c; property: "confetti"; from: 0; to: 1; duration: 1900; easing.type: Easing.OutQuad }
    NumberAnimation { id: heartsAnim; target: c; property: "hearts"; from: 0; to: 1; duration: 2100; easing.type: Easing.OutSine }
    SequentialAnimation {
        id: bangAnim
        NumberAnimation { target: c; property: "bang"; from: 0; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 3 }
        PauseAnimation { duration: 700 }
        NumberAnimation { target: c; property: "bang"; to: 0; duration: 240 }
    }

    onPointerOnChanged: if (pointerOn && (face === "idle" || face === "music") && !fidgetBlock) emote("greet", 1500)
    property bool fidgetBlock: false

    // Adanın içinde küçükken 30 kare/sn yeter; sakin (boşta/uyku) haldeyken 20; büyük önizleme 60.
    property real lastMs: 0
    readonly property bool calm: (face === "idle" || face === "sleep") && !pointerOn && hop <= 0.01 && pendT <= 0
    Timer {
        interval: c.size > 60 ? 16 : c.calm ? 50 : 33
        repeat: true
        running: c.active && c.visible && c.size > 0
        onRunningChanged: if (running) c.lastMs = Date.now()
        onTriggered: {
            var now = Date.now()
            var dt = Math.min(0.06, (now - c.lastMs) / 1000)
            c.lastMs = now
            c.step(dt)
        }
    }

    function ease(cur, tgt, k, dt) { return cur + (tgt - cur) * Math.min(1, dt * k) }

    function step(dt) {
        t += dt
        var f = face
        var isMusic = f === "music", isFocus = f === "focus", isSleep = f === "sleep"

        // ---- yüz hedefleri
        var sm = 0.5, op = 0, bl = 0.15, hp = 0, cl = 0, sqn = 0, es = 1
        var ph = 0, lp = 0, gl = 0, zz = 0, nt = 0
        if (isMusic) { sm = 0.9; op = 0.12 + bass * 0.55; bl = 0.3; ph = 1; nt = 1 }
        else if (isFocus) { sm = 0.05; bl = 0.1; lp = 1; gl = 1 }
        else if (isSleep) { sm = 0.15; op = 0.06 + 0.08 * (1 + Math.sin(t * 1.6)) / 2; bl = 0.25; cl = 1; zz = 1 }
        else if (f === "cheer") { sm = 1; op = 0.75; bl = 0.8; hp = 1 }
        else if (f === "love") { sm = 1; op = 0.2; bl = 1; hp = 1 }
        else if (f === "surprise") { sm = 0; op = 0.95; bl = 0.1; es = 1.28 }
        else if (f === "sad") { sm = -0.85; op = 0.05; bl = 0.05; sqn = 0.2 }
        else if (f === "yawn") { sm = 0; op = 1; bl = 0.1; sqn = 0.8 }
        else if (f === "stretch") { sm = 0.4; bl = 0.1; hp = 0.0; sqn = 0.7 }
        else if (f === "greet") { sm = 1; op = 0.25; bl = 0.5; hp = 0.0 }
        smile = ease(smile, sm, 12, dt)
        mouthOpen = ease(mouthOpen, op, 16, dt)
        blush = ease(blush, bl, 6, dt)
        happyA = ease(happyA, hp, 20, dt)
        closedA = ease(closedA, cl, 9, dt)
        squint = ease(squint, sqn, 12, dt)
        eyeScale = ease(eyeScale, es, 18, dt)
        phonesA = ease(phonesA, ph, 5, dt)
        laptopA = ease(laptopA, lp, 5, dt)
        glassesA = ease(glassesA, gl, 7, dt)
        zzzA = ease(zzzA, zz, 3, dt)
        notesA = ease(notesA, nt, 4, dt)

        // ---- göz kırpma
        blinkIn -= dt
        if (blinkIn <= 0) { blinkT = 0.17; blinkIn = Math.random() < 0.2 ? 0.28 : 2 + Math.random() * 3.6 }
        if (blinkT > 0) blinkT -= dt

        // ---- bakış: fareyi izler, yoksa dolanır; odakta ekrana bakar
        var tx = 0, ty = 0
        if (pointerOn && !isSleep) {
            tx = clamp((pointerX - width / 2) / 46, -1, 1)
            ty = clamp((pointerY - height / 2) / 26, -1, 1)
        } else if (isFocus) {
            tx = Math.sin(t * 0.9) * 0.25
            ty = 0.55 + 0.3 * Math.max(0, Math.sin(t * 0.37))
        } else if (isMusic) {
            tx = Math.sin(t * 5.65) * 0.35
            ty = -0.2
        } else if (!isSleep) {
            wanderT -= dt
            if (wanderT <= 0) { wanderT = 1.1 + Math.random() * 2.6; wanderX = (Math.random() - 0.5) * 1.7; wanderY = (Math.random() - 0.5) * 0.9 }
            tx = wanderX; ty = wanderY
        }
        lookX = ease(lookX, tx, 11, dt)
        lookY = ease(lookY, ty, 11, dt)

        // ---- boşta küçük şovlar
        if (fidgets && f === "idle" && !pointerOn) {
            fidgetIn -= dt
            if (fidgetIn <= 0) {
                fidgetIn = 7 + Math.random() * 8
                var r = Math.floor(Math.random() * 5)
                if (r === 0) { wanderT = 2.4; wanderX = (Math.random() < 0.5 ? -1 : 1) * 0.95; wanderY = -0.2 }
                else if (r === 1) emote("yawn", 1900)
                else if (r === 2) emote("greet", 1700)
                else if (r === 3) jump(120)
                else emote("stretch", 1500)
            }
        }

        // ---- vuruş yakalama: kick'te küçük sıçrayış
        kickCool -= dt
        if (isMusic) {
            if (bass > 0.5 && bassPrev < 0.38 && kickCool <= 0 && pendT <= 0 && hop <= 0.01) {
                kickCool = 0.2
                vy = 85 + bass * 70
                sqv -= 3
            }
        }
        bassPrev = bass

        // ---- sevinç: art arda sıçrayıp takla
        if (f === "cheer" && cheerJumps > 0 && hop <= 0.01 && pendT <= 0 && vy <= 0) { cheerJumps -= 1; jump(205) }

        // ---- sıçrama fiziği
        if (pendT > 0) {
            pendT -= dt
            if (pendT <= 0) { vy = pendV; sqv -= 6 }
        }
        if (hop > 0 || vy > 0) {
            vy -= 620 * dt
            hop += vy * dt
            if (f === "cheer") spin += 590 * dt
            if (hop <= 0) {
                sqv += Math.min(9, -vy * 0.04)
                hop = 0
                vy = 0
                spin = 0
            }
        }
        var sqTarget = sqn
        sqv += (-230 * (sq - sqTarget) - 15 * sqv) * dt
        sq += sqv * dt

        // ---- eğilme ve kulaklar
        var lt = 0
        if (isMusic) lt = Math.sin(t * 5.65) * (4 + 7 * (0.4 + bass))
        else if (f === "sad") lt = 5
        else if (isFocus) lt = 2.5
        else if (pointerOn && !isSleep) lt = lookX * 5
        lean = ease(lean, lt, 14, dt)
        var et = clamp(-vy * 0.07, -30, 30) - lean * 0.9
        earV += (-140 * (earA - et) - 9 * earV) * dt
        earA += earV * dt

        // ---- kollar
        var aL = 8 + Math.sin(t * 1.3) * 3, aR = 8 + Math.sin(t * 1.3 + 1) * 3
        var k = 14
        if (f === "greet") { aR = 138 + 26 * Math.sin(t * 15); k = 24 }
        else if (f === "cheer") { aL = 152 + 22 * Math.sin(t * 17); aR = 152 + 22 * Math.sin(t * 17 + 1.6); k = 26 }
        else if (f === "love") { aL = 42 + 8 * Math.sin(t * 6); aR = 42 + 8 * Math.sin(t * 6 + 1); }
        else if (f === "surprise") { aL = 92 + 6 * Math.sin(t * 40); aR = 92 + 6 * Math.sin(t * 40 + 1); k = 30 }
        else if (f === "yawn") { aR = 155; k = 10 }
        else if (f === "stretch") { aL = 168; aR = 168; k = 7 }
        else if (isMusic) {
            var m = (0.45 + bass) * 34
            aL = 38 + m * Math.sin(t * 11.3); aR = 38 + m * Math.sin(t * 11.3 + Math.PI); k = 22
        } else if (isFocus) {
            aL = -34 + 13 * Math.sin(t * 23); aR = -34 + 13 * Math.sin(t * 23 + 2.4); k = 30
        } else if (isSleep) { aL = 4; aR = 4 }
        else if (f === "sad") { aL = 2; aR = 2 }
        armL = ease(armL, aL, k, dt)
        armR = ease(armR, aR, k, dt)

        // ---- ayaklar
        var fl = 0, fr = 0
        if (isMusic) { var s = Math.sin(t * 5.65); fl = Math.max(0, s) * 4; fr = Math.max(0, -s) * 4 }
        else if (f === "cheer") { fl = 3 + 2 * Math.sin(t * 20); fr = 3 + 2 * Math.sin(t * 20 + 3) }
        footL = ease(footL, fl, 22, dt)
        footR = ease(footR, fr, 22, dt)
        advance(dt)
    }

    // ==================== çizim: videodan alınan kareler ====================
    // contents/critter/sheet.png: 77 kare (128x92), 10 sütun. 0-19 ayakta bekleme, 20-31 meraklı bakış,
    // 32-51 oturma, 52-56 uzanma, 57-76 uyku. Durumlar arası geçiş kareleri ileri/geri oynatarak yapılır
    // (uyurken ayağa kalk → otur → uzan; uyanırken tersi).
    readonly property int frameCount: 77
    property real pos: 0
    property int dirn: 1
    readonly property int fidx: Math.max(0, Math.min(frameCount - 1, Math.floor(pos)))

    // yüz ifadesine göre hedef kare ve döngü aralığı
    function plan() {
        var f = face
        if (f === "sleep") return { target: 60, lo: 57, hi: 76, fps: 5 }
        if (f === "focus" || f === "sad") return { target: 42, lo: 38, hi: 46, fps: 4 }
        if (f === "cheer" || f === "surprise" || f === "greet" || f === "love") return { target: 26, lo: 21, hi: 31, fps: 9 }
        if (f === "yawn" || f === "stretch") return { target: 28, lo: 24, hi: 31, fps: 6 }
        if (f === "music") return { target: 8, lo: 0, hi: 19, fps: 22 }
        return { target: 8, lo: 0, hi: 19, fps: 11 }
    }
    function advance(dt) {
        var pl = plan()
        if (pos < pl.lo - 0.5 || pos > pl.hi + 0.5) {          // geçiş: hedefe doğru kareleri oynat
            pos += (pos < pl.lo ? 1 : -1) * 15 * dt
            dirn = pos < pl.lo ? 1 : -1
            if (pos >= pl.lo && pos <= pl.hi) pos = Math.max(pl.lo, Math.min(pl.hi, pos))
        } else {                                                  // aralık içinde ileri-geri döngü
            pos += dirn * pl.fps * dt
            if (pos >= pl.hi) { pos = pl.hi; dirn = -1 }
            else if (pos <= pl.lo) { pos = pl.lo; dirn = 1 }
        }
    }

    Item {
        id: st
        width: 100; height: 100
        scale: c.size / 100
        transformOrigin: Item.TopLeft

        Rectangle {   // zemin gölgesi
            x: 50 - w / 2; y: 91
            readonly property real w: 52 * (1 - Math.min(0.5, c.hop / 90))
            width: w; height: 6; radius: 3
            color: "black"
            opacity: 0.30 * (1 - Math.min(0.7, c.hop / 80))
        }

        Item {
            id: rig
            width: 100; height: 100
            transform: [
                Scale {
                    origin.x: 50; origin.y: 96
                    readonly property real s: c.sq + Math.sin(c.t * (c.face === "sleep" ? 1.6 : 3.7)) * (c.face === "sleep" ? 0.03 : 0.02)
                                              - Math.max(0, Math.min(0.35, c.vy / 600))
                    xScale: 1 + s * 0.20
                    yScale: 1 - s * 0.26
                },
                Rotation { origin.x: 50; origin.y: 96; angle: c.lean },
                Rotation { origin.x: 50; origin.y: 60; angle: c.spin },
                Translate { y: -c.hop }
            ]

            Item {   // sprite sayfasından tek kare: büyük resim kaydırılıp kırpılır (yeniden yükleme yok)
                readonly property real k: 100 / 128
                x: 0; y: 96 - 92 * k
                width: 128 * k; height: 92 * k
                clip: true
                Image {
                    x: -(c.fidx % 10) * 128 * parent.k
                    y: -Math.floor(c.fidx / 10) * 92 * parent.k
                    width: 1280 * parent.k; height: 736 * parent.k
                    source: Qt.resolvedUrl("../critter/sheet.png")
                    smooth: true
                    mipmap: true
                    asynchronous: false
                }
            }
        }

        // ================= piksel parçacıklar =================
        component Pix: Item {
            id: pix
            property var rows: []
            property color color: "white"
            property real u: 3.125
            readonly property var cells: {
                var out = []
                for (var y = 0; y < rows.length; y++)
                    for (var x = 0; x < rows[y].length; x++)
                        if (rows[y][x] === "X") out.push({ x: x, y: y })
                return out
            }
            Repeater {
                model: pix.cells
                Rectangle {
                    required property var modelData
                    x: modelData.x * pix.u; y: modelData.y * pix.u
                    width: pix.u; height: pix.u
                    color: pix.color
                }
            }
        }

        Loader {   // müzik notaları
            active: c.notesA > 0.03
            sourceComponent: Item {
                Repeater {
                    model: 4
                    Pix {
                        required property int index
                        readonly property real p: (c.t * 0.55 + index / 4) % 1
                        rows: ["..XX", "..X.", "..X.", "XXX.", "XX.."]
                        color: ["#ff8fa3", "#7fd1ff", "#ffc66e", "#b69cff"][index]
                        x: Math.round(((index % 2 ? 76 : 8) + Math.sin(p * 7 + index * 1.7) * 6) / 3.125) * 3.125
                        y: Math.round((30 - p * 34) / 3.125) * 3.125
                        opacity: Math.sin(p * Math.PI) * c.notesA
                    }
                }
            }
        }
        Loader {   // uyku Zzz
            active: c.zzzA > 0.03
            sourceComponent: Item {
                Repeater {
                    model: 3
                    Pix {
                        required property int index
                        readonly property real p: (c.t * 0.32 + index / 3) % 1
                        rows: ["XXX", "..X", ".X.", "X..", "XXX"]
                        color: "#cfe3ff"
                        u: 2.6 + p * 2.2
                        x: Math.round((82 + p * 14) / 3.125) * 3.125
                        y: Math.round((34 - p * 30) / 3.125) * 3.125
                        opacity: Math.sin(p * Math.PI) * c.zzzA
                    }
                }
            }
        }
        Loader {   // kalpler
            active: c.hearts < 1
            sourceComponent: Item {
                Repeater {
                    model: 5
                    Pix {
                        required property int index
                        readonly property real p: Math.max(0, Math.min(1, c.hearts * 1.15 - index * 0.05))
                        rows: [".X.X.", "XXXXX", "XXXXX", ".XXX.", "..X.."]
                        color: index % 2 ? "#ff6b8a" : "#ff9eb5"
                        u: 2.4 + (index % 3) * 0.7
                        visible: p > 0
                        x: Math.round((50 + (index - 2) * 14 + Math.sin(p * 9 + index) * 4 - 6) / 3.125) * 3.125
                        y: Math.round((36 - p * 34) / 3.125) * 3.125
                        opacity: Math.sin(Math.min(1, p) * Math.PI)
                    }
                }
            }
        }
        Loader {   // konfeti ve ışıltılar
            active: c.confetti > 0 && c.confetti < 1
            sourceComponent: Item {
                Repeater {
                    model: 24
                    Rectangle {
                        required property int index
                        readonly property real ang: (index * 137.5) * Math.PI / 180
                        readonly property real spd: 34 + (index * 7) % 27
                        readonly property real f: c.confetti
                        width: 3.125; height: index % 3 === 0 ? 8.3 : 3.125
                        x: Math.round((50 + Math.cos(ang) * spd * Math.sqrt(f) * 1.5) / 3.125) * 3.125
                        y: Math.round((42 + Math.sin(ang) * spd * Math.sqrt(f) * 1.1 - 22 * Math.sqrt(f) + 54 * f * f) / 3.125) * 3.125
                        color: ["#ff5f6d", "#ffc371", "#7bed9f", "#70a1ff", "#eccc68", "#ff7eb3", "#a29bfe"][index % 7]
                        opacity: 1 - Math.max(0, (f - 0.72) / 0.28)
                    }
                }
                Repeater {
                    model: 4
                    Pix {
                        required property int index
                        readonly property real f: c.confetti
                        rows: ["..X..", "..X..", "XXXXX", "..X..", "..X.."]
                        color: "#ffe28a"
                        u: 2.6
                        x: [8, 80, 16, 72][index]; y: [34, 28, 10, 6][index]
                        visible: Math.sin(Math.min(1, f * 2.2 + index * 0.18) * Math.PI) > 0.3
                    }
                }
            }
        }
        Pix {   // şaşkınlık "!"
            rows: ["X", "X", "X", ".", "X"]
            color: "#ffcf40"
            u: 3.125
            x: 79; y: 8
            visible: c.bang > 0.3
        }
    }
}
