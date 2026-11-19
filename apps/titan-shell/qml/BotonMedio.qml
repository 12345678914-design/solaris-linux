// Botón de música dibujado (anterior / play / pausa / siguiente), sin
// depender de que la fuente tenga esos símbolos.
import QtQuick

Item {
    id: boton
    property string tipo: "play"
    property bool grande: false
    property bool activo: true
    property real tamano: 18
    signal pulsado()
    width: grande ? tamano * 2 : tamano * 1.66
    height: tamano * 1.66
    opacity: activo ? 1 : 0.35

    Rectangle {
        anchors.centerIn: parent
        width: boton.height; height: boton.height; radius: height / 2
        color: raton.containsMouse && boton.activo ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
    }
    Canvas {
        anchors.centerIn: parent
        width: 18; height: 18
        scale: boton.tamano / 18
        property string t: boton.tipo
        onTChanged: requestPaint()
        onPaint: {
            var c = getContext("2d")
            c.reset()
            c.fillStyle = "#ffffff"
            function tri(x0, dir) {   // triángulo de 8 px de ancho apuntando a dir
                c.beginPath()
                if (dir > 0) { c.moveTo(x0, 4); c.lineTo(x0 + 8, 9); c.lineTo(x0, 14) }
                else { c.moveTo(x0 + 8, 4); c.lineTo(x0, 9); c.lineTo(x0 + 8, 14) }
                c.closePath(); c.fill()
            }
            if (t === "play") {
                c.beginPath(); c.moveTo(5, 2); c.lineTo(16, 9); c.lineTo(5, 16); c.closePath(); c.fill()
            } else if (t === "pausa") {
                c.fillRect(4, 3, 3.5, 12); c.fillRect(10.5, 3, 3.5, 12)
            } else if (t === "siguiente") {
                tri(2, 1); tri(9, 1)
            } else {
                tri(1, -1); tri(8, -1)
            }
        }
    }
    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        enabled: boton.activo
        cursorShape: Qt.PointingHandCursor
        onClicked: boton.pulsado()
    }
}
