import QtQuick

// Albüm kapağından baskın, canlı bir vurgu rengi çıkarır.
// Küçültülmüş görüntüdeki pikselleri tona göre kovalara ayırır; doygun ve orta açıklıktaki
// pikselleri öne çıkarır, en ağır kovanın ortalamasını siyah zeminde okunur aralığa çeker.
// Kapak yoksa ya da gri tonluysa `fallback` kullanılır.
Canvas {
    id: c

    property url source
    property color fallback: "#6ea8fe"
    property color result: fallback

    readonly property int sz: 28
    readonly property int buckets: 12

    width: sz
    height: sz
    opacity: 0.001            // görünmez ama boyanır
    renderTarget: Canvas.Image
    renderStrategy: Canvas.Immediate

    onFallbackChanged: if (!hasArt()) result = fallback

    function hasArt() { return source.toString() !== "" }

    onSourceChanged: {
        if (!hasArt()) { result = fallback; return }
        loadImage(source)
        if (isImageLoaded(source)) requestPaint()
    }
    onImageLoaded: requestPaint()

    onPaint: {
        if (!hasArt() || !isImageLoaded(source)) return
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, sz, sz)
        ctx.drawImage(source, 0, 0, sz, sz)
        var d = ctx.getImageData(0, 0, sz, sz).data

        var w = [], r = [], g = [], b = []
        for (var k = 0; k < buckets; k++) { w.push(0); r.push(0); g.push(0); b.push(0) }

        for (var i = 0; i < d.length; i += 4) {
            if (d[i + 3] < 200) continue
            var R = d[i], G = d[i + 1], B = d[i + 2]
            var mx = Math.max(R, G, B), mn = Math.min(R, G, B)
            var l = (mx + mn) / 510
            if (l < 0.12 || l > 0.93 || mx === mn) continue
            var s = (mx - mn) / (l > 0.5 ? 510 - mx - mn : mx + mn)
            var h
            var dl = mx - mn
            if (mx === R) h = ((G - B) / dl) % 6
            else if (mx === G) h = (B - R) / dl + 2
            else h = (R - G) / dl + 4
            h = (h * 60 + 360) % 360
            // Doygun ve orta açıklıktaki pikseller daha ağır
            var weight = s * s * (1 - Math.abs(l - 0.5) * 1.2)
            var bi = Math.min(buckets - 1, Math.floor(h / (360 / buckets)))
            w[bi] += weight; r[bi] += R * weight; g[bi] += G * weight; b[bi] += B * weight
        }

        var best = 0
        for (var j = 1; j < buckets; j++) if (w[j] > w[best]) best = j
        // Neredeyse gri tonlu kapak: renk uydurma, varsayılanı kullan
        if (w[best] < 0.6) { result = fallback; return }

        var col = Qt.rgba(r[best] / w[best] / 255, g[best] / w[best] / 255, b[best] / w[best] / 255, 1)
        result = Qt.hsla(col.hslHue,
                         Math.max(0.55, Math.min(0.92, col.hslSaturation)),
                         Math.max(0.58, Math.min(0.72, col.hslLightness)), 1)
    }
}
