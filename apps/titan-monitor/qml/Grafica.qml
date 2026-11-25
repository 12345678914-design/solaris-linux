import QtQuick

// Gráfica de línea con área rellena, en el color de acento de Inti.
//  valores: historial (el último a la derecha); valores2: segunda serie
//  (escritura, subida) en línea discontinua. maximo: 0 = se ajusta solo.
Canvas {
    id: g
    property var valores: []
    property var valores2: []
    property real maximo: 100
    property int muestras: 60
    property color color: theme.accent
    property bool rejilla: true
    property bool borde: true
    readonly property real tope: {
        if (maximo > 0) return maximo
        var m = 1024
        for (var i = 0; i < valores.length; ++i) m = Math.max(m, valores[i])
        for (var j = 0; j < valores2.length; ++j) m = Math.max(m, valores2[j])
        return m * 1.15
    }

    TitanTheme { id: theme }

    onValoresChanged: requestPaint()
    onValores2Changed: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Connections { target: theme; function onIsDarkChanged() { g.requestPaint() } }

    function xDe(i, n) { return width - (n - 1 - i) * (width / (muestras - 1)) }
    function yDe(v) { return height - 1 - Math.min(1, Math.max(0, v / tope)) * (height - 2) }

    onPaint: {
        var c = getContext("2d")
        c.reset()
        var r = g.color
        if (rejilla) {
            c.strokeStyle = theme.isDark ? "rgba(255,255,255,0.07)" : "rgba(0,0,0,0.07)"
            c.lineWidth = 1
            for (var k = 1; k < 4; ++k) {
                var y = Math.round(height * k / 4) + 0.5
                c.beginPath(); c.moveTo(0, y); c.lineTo(width, y); c.stroke()
            }
            for (var v = 1; v < 6; ++v) {
                var x = Math.round(width * v / 6) + 0.5
                c.beginPath(); c.moveTo(x, 0); c.lineTo(x, height); c.stroke()
            }
        }
        function serie(datos, relleno, discontinua) {
            var n = datos.length
            if (n < 2) return
            c.beginPath()
            c.moveTo(xDe(0, n), yDe(datos[0]))
            for (var i = 1; i < n; ++i) c.lineTo(xDe(i, n), yDe(datos[i]))
            if (relleno) {
                c.save()
                c.lineTo(xDe(n - 1, n), height)
                c.lineTo(xDe(0, n), height)
                c.closePath()
                var grad = c.createLinearGradient(0, 0, 0, height)
                grad.addColorStop(0, Qt.rgba(r.r, r.g, r.b, theme.isDark ? 0.42 : 0.30))
                grad.addColorStop(1, Qt.rgba(r.r, r.g, r.b, 0.03))
                c.fillStyle = grad
                c.fill()
                c.restore()
                c.beginPath()
                c.moveTo(xDe(0, n), yDe(datos[0]))
                for (var j = 1; j < n; ++j) c.lineTo(xDe(j, n), yDe(datos[j]))
            }
            c.strokeStyle = discontinua ? Qt.rgba(r.r, r.g, r.b, 0.85) : r
            c.lineWidth = height > 80 ? 2 : 1.5
            c.lineJoin = "round"
            if (discontinua) c.setLineDash([4, 3]); else c.setLineDash([])
            c.stroke()
        }
        serie(valores2, false, true)
        serie(valores, true, false)
        if (borde) {
            c.setLineDash([])
            c.strokeStyle = Qt.rgba(r.r, r.g, r.b, 0.45)
            c.lineWidth = 1
            c.strokeRect(0.5, 0.5, width - 1, height - 1)
        }
    }
}
