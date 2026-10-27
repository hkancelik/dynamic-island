import QtQuick

// Mini çizgi grafik (son N örnek). maxValue: 0 ise otomatik ölçeklenir.
Canvas {
    id: c

    property var values: []
    property color lineColor: "#6ea8fe"
    property real maxValue: 0

    onValuesChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var v = values
        if (!v || v.length < 2 || width < 4 || height < 4) return
        var mx = maxValue > 0 ? maxValue : Math.max(1, Math.max.apply(null, v))
        var n = v.length, w = width, h = height
        function py(i) { return h - 2 - Math.min(1, v[i] / mx) * (h - 4) }

        ctx.beginPath()
        ctx.moveTo(0, py(0))
        for (var i = 1; i < n; i++) ctx.lineTo(i * w / (n - 1), py(i))
        ctx.strokeStyle = lineColor
        ctx.lineWidth = 1.6
        ctx.lineJoin = "round"
        ctx.stroke()

        ctx.lineTo(w, h)
        ctx.lineTo(0, h)
        ctx.closePath()
        var g = ctx.createLinearGradient(0, 0, 0, h)
        g.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.32))
        g.addColorStop(1, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.0))
        ctx.fillStyle = g
        ctx.fill()
    }
}
