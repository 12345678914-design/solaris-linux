import QtQuick
import QtQuick.Controls

// Aplicaciones de inicio: lo que se abre solo al entrar en la sesión.
// Desactivar no borra nada (se puede volver a activar) ni pide contraseña.
Rectangle {
    id: vista
    TitanTheme { id: theme }
    color: theme.contentBackground

    Text {
        id: explicacion
        x: 20; y: 16
        width: parent.width - 40
        wrapMode: Text.Wrap
        text: "Programas que se abren solos al iniciar sesión. Desactivar los que no usas hace que el equipo arranque antes."
        color: theme.contentTextSecondary
        font.pixelSize: 12
    }

    Text {
        visible: monitor.inicio.length === 0
        anchors.centerIn: parent
        text: "No hay programas que se abran al iniciar sesión"
        color: theme.contentTextSecondary
        font.pixelSize: 14
    }

    ListView {
        id: lista
        anchors.top: explicacion.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: monitor.inicio
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Rectangle {
            required property var modelData
            width: lista.width
            height: 54
            radius: 10
            color: zona.containsMouse ? theme.itemHover : "transparent"

            Item {
                id: icono
                x: 10
                width: 30; height: 30
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    id: img
                    anchors.fill: parent
                    source: modelData.icono || ""
                    sourceSize: Qt.size(60, 60)
                    visible: status === Image.Ready
                    asynchronous: true
                }
                Rectangle {
                    anchors.fill: parent
                    visible: !img.visible
                    radius: 8
                    color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.2)
                    Text { anchors.centerIn: parent; text: modelData.nombre.charAt(0).toUpperCase(); color: theme.accent; font.pixelSize: 14; font.bold: true }
                }
            }
            Column {
                anchors.left: icono.right
                anchors.leftMargin: 12
                anchors.right: interruptor.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { width: parent.width; text: modelData.nombre; color: theme.contentTextPrimary; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: modelData.comentario
                    color: theme.contentTextSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
            Text {
                anchors.right: interruptor.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.activado ? "Activado" : "Desactivado"
                color: modelData.activado ? theme.accent : theme.contentTextSecondary
                font.pixelSize: 11
            }
            Rectangle {
                id: interruptor
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 22; radius: 11
                color: modelData.activado ? theme.accent : (theme.isDark ? "#3a3a3e" : "#c7c7cc")
                Behavior on color { ColorAnimation { duration: 120 } }
                Rectangle {
                    width: 18; height: 18; radius: 9; y: 2
                    x: modelData.activado ? 20 : 2
                    color: "#ffffff"
                    Behavior on x { NumberAnimation { duration: 120 } }
                }
            }
            MouseArea {
                id: zona
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: monitor.activarInicio(modelData.id, !modelData.activado)
            }
        }
    }
}
