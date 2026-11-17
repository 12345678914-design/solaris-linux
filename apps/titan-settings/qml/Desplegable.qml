// Lista desplegable de Ajustes: opciones = [{valor, texto}].
import QtQuick
import QtQuick.Controls

Rectangle {
    id: desp
    property var opciones: []
    property var valor: ""
    property int ancho: 220
    property bool habilitado: true
    signal elegido(var valor)
    width: ancho
    height: 28
    radius: 7
    color: raton.containsMouse ? (tema.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06))
                               : (tema.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.85))
    border.color: lista.opened ? tema.accent : tema.contentCardBorder
    border.width: 1
    opacity: habilitado ? 1 : 0.5

    TitanTheme { id: tema }

    function textoDe(v) {
        for (var i = 0; i < opciones.length; ++i)
            if (opciones[i].valor === v) return opciones[i].texto
        return opciones.length > 0 && v === "" ? "" : String(v)
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: flecha.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: desp.textoDe(desp.valor)
        color: tema.contentTextPrimary
        font.pixelSize: 12
        elide: Text.ElideRight
    }
    Text {
        id: flecha
        anchors.right: parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: "⌄"
        color: tema.contentTextSecondary
        font.pixelSize: 12
    }
    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        enabled: desp.habilitado
        cursorShape: Qt.PointingHandCursor
        onClicked: lista.opened ? lista.close() : lista.open()
    }

    Popup {
        id: lista
        y: desp.height + 4
        width: desp.width
        height: Math.min(260, columna.implicitHeight + 8)
        padding: 4
        background: Rectangle {
            radius: 8
            color: tema.isDark ? "#2a2c35" : "#ffffff"
            border.color: tema.contentCardBorder
            border.width: 1
        }
        contentItem: Flickable {
            clip: true
            contentHeight: columna.implicitHeight
            Column {
                id: columna
                width: parent.width
                Repeater {
                    model: desp.opciones
                    delegate: Rectangle {
                        required property var modelData
                        width: columna.width
                        height: 26
                        radius: 5
                        color: opRaton.containsMouse ? tema.accent : "transparent"
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: (desp.valor === modelData.valor ? "✓ " : "   ") + modelData.texto
                            color: opRaton.containsMouse ? "#ffffff" : tema.contentTextPrimary
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: opRaton
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { lista.close(); desp.elegido(modelData.valor) }
                        }
                    }
                }
            }
        }
    }
}
