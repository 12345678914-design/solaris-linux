// Boton de Ajustes (normal o principal en color de acento).
import QtQuick

Rectangle {
    id: boton
    property string texto: ""
    property bool principal: false
    property bool peligro: false
    property bool habilitado: true
    signal pulsado()
    width: etiqueta.implicitWidth + 24
    height: 28
    radius: 6
    opacity: habilitado ? 1 : 0.5
    color: principal ? (raton.containsMouse ? tema.accentHover : tema.accent)
                     : raton.containsMouse ? (tema.isDark ? "#363b49" : "#e6e6ec")
                                           : (tema.isDark ? "#2c303c" : "#f0f0f4")
    border.color: principal ? "transparent" : Qt.rgba(0, 0, 0, 0.15)
    border.width: 1

    TitanTheme { id: tema }

    Text {
        id: etiqueta
        anchors.centerIn: parent
        text: boton.texto
        color: boton.principal ? "#ffffff" : boton.peligro ? "#ff453a" : tema.contentTextPrimary
        font.pixelSize: 11
        font.bold: true
    }
    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        enabled: boton.habilitado
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: boton.pulsado()
    }
}
