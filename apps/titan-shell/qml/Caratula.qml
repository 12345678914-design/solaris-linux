// Carátula de la canción con esquinas redondeadas (isla y pantalla de
// bloqueo). Sin carátula, una nota musical.
import QtQuick
import QtQuick.Effects

Item {
    id: caratula
    property real radio: 8
    property string fuente: ""

    Rectangle {
        anchors.fill: parent
        radius: caratula.radio
        color: Qt.rgba(1, 1, 1, 0.10)
        Text {
            anchors.centerIn: parent
            visible: imagen.status !== Image.Ready
            text: "♪"
            color: Qt.rgba(1, 1, 1, 0.7)
            font.pixelSize: parent.height * 0.5
        }
    }
    Image {
        id: imagen
        anchors.fill: parent
        source: caratula.fuente
        sourceSize: Qt.size(160, 160)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: imagen
        visible: imagen.status === Image.Ready
        maskEnabled: true
        maskSource: mascara
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
    Rectangle {
        id: mascara
        anchors.fill: parent
        radius: caratula.radio
        visible: false
        layer.enabled: true
    }
}
