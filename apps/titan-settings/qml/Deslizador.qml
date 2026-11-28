// Deslizador de Ajustes: valor entre desde y hasta, relleno con el acento.
import QtQuick

Item {
    id: desl
    property real desde: 0
    property real hasta: 100
    property real valor: 50
    property real paso: 1
    property bool habilitado: true
    property int ancho: 220
    // Mientras se arrastra no se pisa el valor con el que llega del sistema.
    readonly property bool arrastrando: raton.pressed
    signal movido(real valor)
    signal soltado(real valor)
    width: ancho
    height: 22
    opacity: habilitado ? 1 : 0.45

    TitanTheme { id: tema }

    property real _visto: valor
    onValorChanged: if (!raton.pressed) _visto = valor
    readonly property real fraccion: hasta > desde ? Math.max(0, Math.min(1, (_visto - desde) / (hasta - desde))) : 0

    Rectangle {
        id: carril
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: tema.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
        Rectangle {
            width: desl.fraccion * parent.width
            height: parent.height
            radius: 2
            color: tema.accent
        }
    }
    Rectangle {
        x: desl.fraccion * (desl.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18
        radius: 9
        color: "#ffffff"
        border.color: Qt.rgba(0, 0, 0, 0.18)
        border.width: 1
    }
    MouseArea {
        id: raton
        anchors.fill: parent
        enabled: desl.habilitado
        cursorShape: Qt.PointingHandCursor
        function calcular(mx) {
            var f = Math.max(0, Math.min(1, mx / width))
            var v = desl.desde + f * (desl.hasta - desl.desde)
            v = Math.round(v / desl.paso) * desl.paso
            desl._visto = v
            desl.movido(v)
        }
        onPressed: (m) => calcular(m.x)
        onPositionChanged: (m) => { if (pressed) calcular(m.x) }
        onReleased: desl.soltado(desl._visto)
    }
}
