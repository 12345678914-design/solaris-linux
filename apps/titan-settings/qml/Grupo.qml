// Grupo de ajustes: etiqueta pequena encima y una tarjeta con filas.
import QtQuick

Column {
    id: grupo
    property string etiqueta: ""
    property string nota: ""
    default property alias filas: columna.data
    width: parent ? parent.width : 400
    spacing: 8

    TitanTheme { id: tema }

    Text {
        visible: grupo.etiqueta.length > 0
        text: grupo.etiqueta
        color: tema.contentTextSecondary
        font.pixelSize: 12
        font.bold: true
    }
    Rectangle {
        id: tarjeta
        width: parent.width
        height: columna.implicitHeight
        radius: 10
        color: tema.contentCardBg
        border.color: tema.contentCardBorder
        border.width: 1
        Column {
            id: columna
            width: parent.width
        }
    }
    Text {
        visible: grupo.nota.length > 0
        width: parent.width
        text: grupo.nota
        color: tema.contentTextSecondary
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
}
