// Interruptor verde estilo macOS.
import QtQuick

Rectangle {
    id: interruptor
    property bool activo: false
    property bool habilitado: true
    signal alternado(bool valor)
    width: 44
    height: 24
    radius: 12
    opacity: habilitado ? 1 : 0.45
    color: activo ? "#34c759" : (tema.isDark ? "#39393d" : "#e5e5ea")
    Behavior on color { ColorAnimation { duration: 160 } }

    TitanTheme { id: tema }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: interruptor.activo ? 22 : 2
        width: 20
        height: 20
        radius: 10
        color: "#ffffff"
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        anchors.fill: parent
        enabled: interruptor.habilitado
        cursorShape: Qt.PointingHandCursor
        onClicked: interruptor.alternado(!interruptor.activo)
    }
}
