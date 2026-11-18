import QtQuick
import QtQuick.Controls

// Botón de la barra: un glifo, resaltado si está activo.
Rectangle {
    id: raiz
    property string texto: ""
    property string pista: ""
    property bool activo: false
    property color acento: "#0071e3"
    property color tinta: "#ffffff"
    property int tam: 13
    signal pulsado()

    width: 30; height: 28; radius: 7
    color: activo ? Qt.rgba(acento.r, acento.g, acento.b, 0.28)
                  : (zona.containsMouse ? Qt.rgba(tinta.r, tinta.g, tinta.b, 0.12) : "transparent")
    Text {
        anchors.centerIn: parent
        text: raiz.texto
        color: raiz.activo ? raiz.acento : raiz.tinta
        font.pixelSize: raiz.tam
        opacity: raiz.enabled ? 1 : 0.35
    }
    MouseArea {
        id: zona
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: raiz.pulsado()
    }
    ToolTip.visible: pista !== "" && zona.containsMouse
    ToolTip.delay: 600
    ToolTip.text: pista
}
