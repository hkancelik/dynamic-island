import QtQuick

// Tek bir "sıvı cam" öğe (shaders/glass.frag). docs/liquid-glass.md'deki fiziği çizer:
// mercek (kenarda arka planı bükme), özel parlama (rim), ton, buzlu bulanıklık, basınca aydınlanma.
// Arka plan olarak GlassBackdrop'un dokularını örnekler; konumu `tick` değiştikçe yeniden bulunur.
//
//   GlassSurface { glassLayer: sh.glassBackdrop; radius: 14 }                    // tam mercek
//   GlassSurface { glassLayer: ...; thin: true }                                 // ince: yalnızca parıltı ve ton
ShaderEffect {
    id: g

    // ---- arka plan
    property var glassLayer                      // GlassBackdrop
    property real tick: 0                       // konum yeniden hesabı için (her karede artar)

    // ---- biçim
    property real radius: 14
    property real radiusTL: radius
    property real radiusTR: radius
    property real radiusBR: radius
    property real radiusBL: radius

    // ---- malzeme
    property bool thin: false                   // cam üstüne cam olmasın: iç kartlar ince sürümü kullanır
    property real lensAmount: 1.0               // 0..1 (materialization: kaybolurken/belirirken bu değişir)
    property real frostAmount: 0.35             // 0..1
    property real rimAmount: 1.0
    property color tintColor: "#ffffff"
    property real tintAmount: 0.0
    property real bodyOpacity: 1.0              // 1: opak (iç öğeler), <1: ada gövdesi (altı bulanık masaüstü)
    property real adaptAmount: 1.0
    property real saturationAmount: 1.25
    property real liftAmount: 0.05
    property real chromaAmount: 0.025
    property real iorValue: 1.5
    property real bezelPx: Math.max(3, Math.min(Math.min(width, height) * 0.34, 18))
    property real thicknessPx: bezelPx * (thin ? 0.55 : 1.15)

    // ---- etkileşim
    property real glow: 0                       // 0..1 içeriden aydınlanma (basınç)
    property point glowAt: Qt.point(width / 2, height / 2)
    property real lightAngle: -125              // derece; -90 = tam yukarıdan, sola doğru -135
    property color glowTone: "#ffffff"

    // ---- gölgelendirici girdileri (adlar glass.frag'daki uniform'larla aynı olmalı)
    readonly property size size: Qt.size(width, height)
    readonly property vector4d radii: Qt.vector4d(radiusTL, radiusTR, radiusBR, radiusBL)
    readonly property vector4d tint: Qt.vector4d(tintColor.r, tintColor.g, tintColor.b, tintAmount)
    readonly property vector4d glowColor: Qt.vector4d(glowTone.r, glowTone.g, glowTone.b, glow)
    readonly property vector2d glowPos: Qt.vector2d(glowAt.x, glowAt.y)
    readonly property vector2d lightDir: Qt.vector2d(Math.cos(lightAngle * Math.PI / 180), Math.sin(lightAngle * Math.PI / 180))
    readonly property vector4d backRect: {
        tick                                      // bağımlılık: konum değişince yeniden hesapla
        if (!glassLayer || glassLayer.width <= 0 || glassLayer.height <= 0) return Qt.vector4d(0, 0, 1, 1)
        var p = g.mapToItem(glassLayer, 0, 0)
        return Qt.vector4d(p.x / glassLayer.width, p.y / glassLayer.height, g.width / glassLayer.width, g.height / glassLayer.height)
    }
    readonly property real bezel: bezelPx
    readonly property real thickness: thicknessPx
    readonly property real ior: iorValue
    readonly property real lens: thin ? lensAmount * 0.25 : lensAmount
    readonly property real frost: frostAmount
    readonly property real rim: thin ? rimAmount * 0.55 : rimAmount
    readonly property real saturation: saturationAmount
    readonly property real lift: liftAmount
    readonly property real chroma: chromaAmount
    readonly property real bodyAlpha: bodyOpacity
    readonly property real adapt: adaptAmount

    // sampler'lar: adlar glass.frag'daki `backdrop` ve `backdropBlur` ile eşleşir
    property variant backdrop: glassLayer ? glassLayer.sharp : null
    property variant backdropBlur: glassLayer ? glassLayer.soft : null

    fragmentShader: Qt.resolvedUrl("../shaders/glass.frag.qsb")
    blending: true
    supportsAtlasTextures: false
}
