import QtQuick
import QtQuick.Effects

// Ada malzemesi (Ayarlar → Görünüm → Ambiyans): siyah gövdenin içinde
//  * albüm kapağından çok bulanık, rengi kısılmış ince bir ışık (panel ve müzik görünümünde),
//  * alt kenarda basa göre nefes alan nötr, beyaz ışık (müzik çalarken).
// Amaç gösteriş değil derinlik: siyah gövde siyah kalır, yalnızca dokusu değişir.
// Her şey adanın yuvarlak alt köşelerine göre maskelenir; üst kenar ekrana yapışık olduğu için düz.
Item {
    id: amb

    property url art
    property color accent: "#6ea8fe"
    property real radius: 28          // alt köşe yarıçapı (çentikle aynı)
    property real glow: 0             // 0..1 kapak ışığının görünürlüğü
    property real bass: 0             // 0..1 alt ışığın gücü
    property bool vivid: false        // Ambiyans: kapağın renkleri canlı, ışıklar vurgu renginde
    readonly property bool hasArt: String(art) !== ""

    // Maske: adanın biçimi
    Rectangle {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        color: "white"
        bottomLeftRadius: amb.radius
        bottomRightRadius: amb.radius
    }

    // Kapak (yoksa vurgu renginde ışık) + okunabilirlik için koyulaşan perde; katman efektiyle
    // bulanıklaştırılıp adanın biçimine maskelenir
    Item {
        id: src
        anchors.fill: parent
        visible: amb.glow > 0.01
        opacity: amb.glow
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        layer.enabled: visible
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 64
            saturation: amb.vivid ? 0.6 : -0.35     // sade modda kapağın rengi yalnızca bir ima
            maskEnabled: true
            maskSource: mask
        }
        Image {
            visible: amb.hasArt
            anchors.centerIn: parent
            width: Math.max(parent.width, parent.height) * 1.25
            height: width
            source: amb.glow > 0 ? amb.art : ""
            sourceSize: Qt.size(96, 96)          // bulanıklaştırılacak: küçük yeter
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }
        Rectangle {
            visible: !amb.hasArt
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: amb.vivid ? Qt.rgba(amb.accent.r, amb.accent.g, amb.accent.b, 0.55)
                                                             : Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 1; color: "black" }
            }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, amb.vivid ? 0.18 : 0.45) }
                GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, amb.vivid ? 0.50 : 0.72) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, amb.vivid ? 0.78 : 0.88) }
            }
        }
    }

    // Alt ışık: basla nefes alır.
    // Not: Rectangle köşe yarıçapını yüksekliğinin yarısıyla sınırlar; 30 px'lik bir şeridin köşesi
    // en fazla 15 px dönerdi ve adanın 36 px'lik köşesinin dışına taşardı. Bu yüzden şerit
    // yarıçapın iki katı yüksekliğinde; görünen ışık gradyanla yine alttaki 30 px'e sıkıştırılır.
    Rectangle {
        id: under
        objectName: "glowUnder"
        readonly property real lit: 30                            // ışığın görünen yüksekliği
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.min(parent.height, Math.max(lit, amb.radius * 2))
        visible: opacity > 0.01
        opacity: amb.bass
        Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
        bottomLeftRadius: amb.radius
        bottomRightRadius: amb.radius
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: Math.max(0, 1 - under.lit / under.height); color: "transparent" }
            GradientStop { position: 1; color: amb.vivid ? Qt.rgba(amb.accent.r, amb.accent.g, amb.accent.b, 0.55)
                                                         : Qt.rgba(1, 1, 1, 0.16) }   // sade: nötr ışık
        }
    }
}
