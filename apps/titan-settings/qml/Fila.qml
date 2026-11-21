// Fila de una tarjeta: titulo, detalle y controles a la derecha.
import QtQuick

Item {
    id: fila
    property string titulo: ""
    property string detalle: ""
    property bool separador: true
    default property alias controles: zona.data
    width: parent ? parent.width : 400
    height: Math.max(50, textos.implicitHeight + 22)

    TitanTheme { id: tema }

    Column {
        id: textos
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: zona.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
            width: parent.width
            text: fila.titulo
            color: tema.contentTextPrimary
            font.pixelSize: 12
            font.bold: true
            wrapMode: Text.WordWrap
        }
        Text {
            visible: text.length > 0
            width: parent.width
            text: fila.detalle
            color: tema.contentTextSecondary
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }
    Row {
        id: zona
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
    }
    Rectangle {
        visible: fila.separador
        anchors.bottom: parent.bottom
        x: 16
        width: parent.width - 32
        height: 1
        color: tema.contentCardBorder
    }
}
