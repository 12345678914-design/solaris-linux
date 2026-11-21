import QtQuick

// Barra para la posición y el volumen: clic o arrastre. Mientras se arrastra
// muestra lo que marca el ratón (no lo que llega del reproductor).
Item {
    id: raiz
    property real valor: 0            // 0..1
    property color color: "#0071e3"
    property color fondo: Qt.rgba(1, 1, 1, 0.2)
    property real grosor: 4
    readonly property bool arrastrando: zona.pressed
    readonly property real mostrado: zona.pressed ? zona.v : valor
    signal movido(real v)
    signal soltado(real v)

    implicitHeight: 14

    Rectangle {
        id: carril
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: zona.containsMouse || zona.pressed ? raiz.grosor + 2 : raiz.grosor
        radius: height / 2
        color: raiz.fondo
        Behavior on height { NumberAnimation { duration: 90 } }

        Rectangle {
            width: Math.max(0, Math.min(1, raiz.mostrado)) * parent.width
            height: parent.height
            radius: parent.radius
            color: raiz.color
        }
    }
    Rectangle {
        width: 12; height: 12; radius: 6
        color: "#ffffff"
        border.color: Qt.rgba(0, 0, 0, 0.2)
        x: Math.max(0, Math.min(1, raiz.mostrado)) * (raiz.width) - width / 2
        anchors.verticalCenter: parent.verticalCenter
        visible: zona.containsMouse || zona.pressed
    }
    MouseArea {
        id: zona
        property real v: 0
        anchors.fill: parent
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        function calc(x) { return Math.max(0, Math.min(1, x / width)) }
        onPressed: (e) => { v = calc(e.x); raiz.movido(v) }
        onPositionChanged: (e) => { if (pressed) { v = calc(e.x); raiz.movido(v) } }
        onReleased: raiz.soltado(v)
        onWheel: (e) => { raiz.soltado(Math.max(0, Math.min(1, raiz.valor + (e.angleDelta.y > 0 ? 0.05 : -0.05)))) }
    }
}
