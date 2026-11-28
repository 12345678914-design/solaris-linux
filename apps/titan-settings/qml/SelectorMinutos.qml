// Desplegable de tiempos ("Nunca", "5 min", "1 hora"...).
import QtQuick
import QtQuick.Controls

Rectangle {
    id: selector
    property int valor: 0
    property var opciones: [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 120]
    property bool habilitado: true
    signal elegido(int minutos)

    function texto(m) {
        if (m === 0) return "Nunca"
        if (m < 60) return m + " min"
        if (m % 60 === 0) return (m / 60) + (m === 60 ? " hora" : " horas")
        return m + " min"
    }

    width: 118
    height: 26
    radius: 6
    opacity: habilitado ? 1 : 0.5
    color: raton.containsMouse ? (tema.isDark ? "#363b49" : "#e6e6ec") : (tema.isDark ? "#2c303c" : "#f0f0f4")
    border.color: Qt.rgba(0, 0, 0, 0.15)
    border.width: 1

    TitanTheme { id: tema }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: selector.texto(selector.valor)
        color: tema.contentTextPrimary
        font.pixelSize: 11
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: "▾"
        color: tema.contentTextSecondary
        font.pixelSize: 10
    }
    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        enabled: selector.habilitado
        cursorShape: Qt.PointingHandCursor
        onClicked: lista.open()
    }

    Popup {
        id: lista
        y: selector.height + 4
        width: selector.width
        padding: 4
        margins: 8
        background: Rectangle {
            radius: 8
            color: tema.isDark ? "#252833" : "#ffffff"
            border.color: tema.contentCardBorder
            border.width: 1
        }
        contentItem: Column {
            Repeater {
                model: selector.opciones
                delegate: Rectangle {
                    required property var modelData
                    width: selector.width - 8
                    height: 24
                    radius: 5
                    color: ratonOpcion.containsMouse ? tema.accent : "transparent"
                    Text {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: selector.texto(modelData)
                        color: ratonOpcion.containsMouse ? "#ffffff" : tema.contentTextPrimary
                        font.pixelSize: 11
                        font.bold: modelData === selector.valor
                    }
                    MouseArea {
                        id: ratonOpcion
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            lista.close()
                            selector.elegido(modelData)
                        }
                    }
                }
            }
        }
    }
}
