import QtQuick
import QtQuick.Effects

// Carátula con esquinas redondeadas (o círculo). Sin imagen: degradado con ♪
// de un color que sale del nombre, para que cada álbum se distinga.
Item {
    id: raiz
    property url fuente: ""
    property real radio: 8
    property string semilla: ""
    property bool sombra: false
    property string glifo: "♪"

    readonly property real tono: {
        var h = 0
        for (var i = 0; i < semilla.length; ++i)
            h = (h * 31 + semilla.charCodeAt(i)) % 360
        return h / 360
    }
    readonly property bool hayImagen: imagen.status === Image.Ready && fuente != ""
    readonly property bool conMascara: GraphicsInfo.api !== GraphicsInfo.Software

    Rectangle {
        anchors.fill: parent
        radius: raiz.radio
        visible: !raiz.hayImagen
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.hsla(raiz.tono, 0.45, 0.55, 1) }
            GradientStop { position: 1; color: Qt.hsla((raiz.tono + 0.08) % 1, 0.55, 0.32, 1) }
        }
        Text {
            anchors.centerIn: parent
            text: raiz.glifo
            color: Qt.rgba(1, 1, 1, 0.85)
            font.pixelSize: Math.max(10, Math.min(raiz.width, raiz.height) * 0.38)
        }
    }

    Image {
        id: imagen
        anchors.fill: parent
        source: raiz.fuente
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: Math.ceil(raiz.width * 2)
        sourceSize.height: Math.ceil(raiz.height * 2)
        visible: raiz.hayImagen && !raiz.conMascara
    }

    Rectangle {
        id: mascara
        anchors.fill: parent
        radius: raiz.radio
        visible: false
        layer.enabled: raiz.conMascara
    }

    MultiEffect {
        anchors.fill: parent
        source: imagen
        visible: raiz.hayImagen && raiz.conMascara
        maskEnabled: true
        maskSource: mascara
        shadowEnabled: raiz.sombra
        shadowBlur: 0.6
        shadowOpacity: 0.35
        shadowVerticalOffset: 4
    }
}
