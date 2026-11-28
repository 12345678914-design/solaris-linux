// Campo de texto de Ajustes (borde con el color de acento al escribir).
import QtQuick

Rectangle {
    id: campo
    property alias texto: entrada.text
    property string pista: ""
    property bool secreto: false
    property bool habilitado: true
    property int ancho: 220
    signal aceptado()
    width: ancho
    height: 30
    radius: 7
    color: tema.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.85)
    border.color: entrada.activeFocus ? tema.accent : tema.contentCardBorder
    border.width: entrada.activeFocus ? 2 : 1
    opacity: habilitado ? 1 : 0.5

    TitanTheme { id: tema }

    function enfocar() { entrada.forceActiveFocus() }
    function limpiar() { entrada.text = "" }

    TextInput {
        id: entrada
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        color: tema.contentTextPrimary
        selectionColor: tema.accent
        selectedTextColor: "#ffffff"
        font.pixelSize: 12
        clip: true
        enabled: campo.habilitado
        echoMode: campo.secreto ? TextInput.Password : TextInput.Normal
        onAccepted: campo.aceptado()
    }
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: entrada.text.length === 0 && !entrada.activeFocus
        text: campo.pista
        color: tema.contentTextSecondary
        font.pixelSize: 12
    }
}
