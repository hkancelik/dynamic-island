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
    readonly property Item sharp: sharpSrc
    readonly property Item soft: softSrc

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
