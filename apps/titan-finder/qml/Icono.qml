import QtQuick

// Iconos de línea del Explorador de archivos (16x16, se escalan). Dibujados
// aquí para que se vean igual en todos los equipos, sin depender de emojis.
Canvas {
    id: icono
    property string nombre: ""
    property color color: "black"
    width: 16; height: 16
    onNombreChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
        var c = getContext("2d")
        c.reset()
        c.scale(width / 16, height / 16)
        c.strokeStyle = icono.color
        c.fillStyle = icono.color
        c.lineWidth = 1.4
        c.lineCap = "round"
        c.lineJoin = "round"
        function linea(p) { c.beginPath(); c.moveTo(p[0], p[1]); for (var i = 2; i < p.length; i += 2) c.lineTo(p[i], p[i + 1]); c.stroke() }
        function caja(x, y, w, h, r) {
            c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r)
            c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); c.stroke()
        }
        function circulo(x, y, r) { c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.stroke() }
        switch (nombre) {
        case "nuevo": linea([8, 2.5, 8, 13.5]); linea([2.5, 8, 13.5, 8]); break
        case "cortar":
            circulo(4.5, 11.5, 2.3); circulo(11.5, 11.5, 2.3)
            linea([6, 9.8, 11.5, 2]); linea([10, 9.8, 4.5, 2]); break
        case "copiar": caja(5.5, 5.5, 8.5, 8.5, 1.6); linea([10.5, 3.5, 10.5, 2.5, 2.5, 2.5, 2.5, 10.5, 3.5, 10.5]); break
        case "pegar": caja(2.8, 3.2, 10.4, 11.3, 1.6); caja(5.6, 1.6, 4.8, 3, 1); linea([5.5, 8.5, 10.5, 8.5]); linea([5.5, 11.2, 9, 11.2]); break
        case "renombrar": linea([3, 13, 3.6, 10.2, 11, 2.8, 13.2, 5, 5.8, 12.4, 3, 13]); linea([9.6, 4.2, 11.8, 6.4]); break
        case "eliminar":
            linea([2.5, 4.2, 13.5, 4.2]); linea([6.2, 4.2, 6.2, 2.4, 9.8, 2.4, 9.8, 4.2])
            linea([4, 4.2, 4.8, 13.8, 11.2, 13.8, 12, 4.2]); linea([6.8, 6.8, 7, 11.4]); linea([9.2, 6.8, 9, 11.4]); break
        case "ordenar": linea([5, 13, 5, 3]); linea([2.5, 5.5, 5, 3, 7.5, 5.5]); linea([11, 3, 11, 13]); linea([8.5, 10.5, 11, 13, 13.5, 10.5]); break
        case "iconos": caja(2.5, 2.5, 4.5, 4.5, 1); caja(9, 2.5, 4.5, 4.5, 1); caja(2.5, 9, 4.5, 4.5, 1); caja(9, 9, 4.5, 4.5, 1); break
        case "lista":
            for (var k = 0; k < 3; ++k) { linea([6, 4 + k * 4, 13.5, 4 + k * 4]); c.beginPath(); c.arc(3.2, 4 + k * 4, 0.9, 0, Math.PI * 2); c.fill() }
            break
        case "mas": for (var j = 0; j < 3; ++j) { c.beginPath(); c.arc(3.5 + j * 4.5, 8, 1.3, 0, Math.PI * 2); c.fill() } break
        case "detalles": caja(1.8, 2.5, 12.4, 11, 1.8); linea([9.8, 2.5, 9.8, 13.5]); linea([11.3, 5.5, 12.7, 5.5]); linea([11.3, 8, 12.7, 8]); break
        case "atras": linea([13, 8, 3, 8]); linea([7.5, 3.5, 3, 8, 7.5, 12.5]); break
        case "adelante": linea([3, 8, 13, 8]); linea([8.5, 3.5, 13, 8, 8.5, 12.5]); break
        case "arriba": linea([8, 13, 8, 3]); linea([3.5, 7.5, 8, 3, 12.5, 7.5]); break
        case "recargar":
            c.beginPath(); c.arc(8, 8, 5, -Math.PI * 0.35, Math.PI * 1.45); c.stroke()
            linea([10, 1.8, 11.4, 3.9, 9, 5.2]); break
        case "terminal": caja(1.8, 2.5, 12.4, 11, 1.8); linea([4.5, 6, 6.8, 8, 4.5, 10]); linea([8.2, 10.5, 11.5, 10.5]); break
        case "ocultos":
            c.beginPath(); c.moveTo(1.5, 8); c.quadraticCurveTo(8, 1, 14.5, 8); c.quadraticCurveTo(8, 15, 1.5, 8); c.stroke()
            circulo(8, 8, 2.2); break
        case "lupa": circulo(6.8, 6.8, 4.3); linea([10, 10, 13.8, 13.8]); break
        case "casa": linea([2, 7.5, 8, 2.5, 14, 7.5]); linea([3.8, 6.3, 3.8, 13.5, 12.2, 13.5, 12.2, 6.3]); break
        case "compartir": linea([8, 10, 8, 2]); linea([5, 5, 8, 2, 11, 5]); linea([5, 7.5, 3, 7.5, 3, 14, 13, 14, 13, 7.5, 11, 7.5]); break
        case "panel": caja(1.8, 2.5, 12.4, 11, 1.8); linea([6, 2.5, 6, 13.5]); break
        }
    }
}
