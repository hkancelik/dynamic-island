import QtQuick
import QtQuick.Effects

// Camın "arkasındaki içerik katmanı": ada içindeki renkli zemin (vurgu renkleri, albüm ışığı).
// Cam öğeler bu katmanın dokusunu (keskin ve bulanık) örnekleyip kırar; böylece mercek bükecek
// gerçek bir görüntü vardır. İçerik `content` altına konur; GlassSurface `sharp`/`soft`'u kullanır.
Item {
    id: bd

    default property alias content: layerContent.data
    property bool live: true               // false: yalnızca update() çağrılınca yenilenir (boştayken ucuz)
    property real blurAmount: 1.0          // 0..1
    property real mat: 1                   // maddeleşme 0..1 (cam yüzeyler okur)
    readonly property Item sharp: sharpSrc
    readonly property Item soft: softSrc

    // imleç: cam kenarları ona doğru parlar (içerik koordinatlarında)
    property point pointerPos: Qt.point(0, 0)
    property real pointerAmount: 0

    // dokunma dalgaları: iki halka dönüşümlü kullanılır; konum ve ilerleme (0..1, 1 = bitti)
    property point rpPos0: Qt.point(0, 0)
    property point rpPos1: Qt.point(0, 0)
    property real rpT0: 1
    property real rpT1: 1
    property real rpAmp: 9
    property int rpNext: 0
    function ripple(x, y) {
        if (rpNext === 0) { rpPos0 = Qt.point(x, y); rpAnim0.restart() }
        else { rpPos1 = Qt.point(x, y); rpAnim1.restart() }
        rpNext = 1 - rpNext
    }
    NumberAnimation { id: rpAnim0; target: bd; property: "rpT0"; from: 0; to: 1; duration: 1100; easing.type: Easing.OutQuad }
    NumberAnimation { id: rpAnim1; target: bd; property: "rpT1"; from: 0; to: 1; duration: 1100; easing.type: Easing.OutQuad }

    function update() { sharpSrc.scheduleUpdate(); softSrc.scheduleUpdate() }

    Item { id: layerContent; anchors.fill: parent }

    ShaderEffectSource {
        id: sharpSrc
        sourceItem: layerContent
        live: bd.live
        hideSource: true
        visible: false
        smooth: true
    }
    // kaynak içerik doğrudan çizilmez (hideSource): ekrana yalnızca cam yüzeyler çıkar.
    // Bulanık sürüm keskin dokudan türetilir
    MultiEffect {
        id: blurFx
        anchors.fill: parent
        source: sharpSrc
        blurEnabled: true
        blur: bd.blurAmount
        blurMax: 40
        saturation: 0.15
    }
    ShaderEffectSource {
        id: softSrc
        sourceItem: blurFx
        live: bd.live
        hideSource: true
        visible: false
        smooth: true
    }
}
