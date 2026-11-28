// Control segmentado: opciones = [{valor, texto}, ...]
import QtQuick

Rectangle {
    id: seg
    property var opciones: []
    property string valor: ""
    property int anchoSegmento: 96
    signal elegido(string valor)
    width: opciones.length * anchoSegmento + 4
    height: 28
    radius: 7
    color: tema.isDark ? Qt.rgba(0.18, 0.20, 0.26, 0.8) : Qt.rgba(0, 0, 0, 0.08)
    border.color: tema.contentCardBorder
    border.width: 1

    TitanTheme { id: tema }

    Row {
        anchors.fill: parent
        anchors.margins: 2
        Repeater {
            model: seg.opciones
            delegate: Rectangle {
                required property var modelData
                width: seg.anchoSegmento
                height: parent.height
                radius: 5
                color: seg.valor === modelData.valor ? (tema.isDark ? "#3a3f4f" : "#ffffff") : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: modelData.texto
                    color: tema.contentTextPrimary
                    font.pixelSize: 11
                    font.bold: seg.valor === modelData.valor
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.elegido(modelData.valor)
                }
            }
        }
    }
}
