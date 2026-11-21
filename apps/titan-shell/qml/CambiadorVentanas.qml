// Alt+Tab de Inti OS: muestra a qué app se cambia (como macOS y Windows).
//
// El compositor manda "titan-shell --tecla alt-tab" en cada Alt+Tab (y
// "alt-tab-atras" con Mayús). La primera vez se abre con la ventana usada antes
// elegida; las siguientes avanzan. Al soltar Alt se trae la elegida. Esta capa
// toma el teclado para enterarse de que se soltó Alt; mientras no lo tiene, un
// toque rápido (Alt+Tab y soltar) cambia sin llegar a dibujar el panel.
import QtQuick

Item {
    id: cambiador
    anchors.fill: parent

    property var lista: []
    property int elegido: 0
    // El panel se dibuja tras un instante: un toque rápido no parpadea
    property bool dibujar: false
    // ¿Ya tiene el teclado esta capa? (antes no se puede saber si Alt sigue)
    property bool conTeclado: false

    readonly property int tamIcono: Math.max(40, Math.min(72, (width - 160) / Math.max(1, lista.length) - 28))
    readonly property int celda: tamIcono + 28
    readonly property var actual: lista.length > 0 && elegido < lista.length ? lista[elegido] : null

    TitanTheme { id: tema }

    function paso(p) {
        if (!shellBackend.cambiadorVisible) {
            var l = windowTracker.ventanasRecientes()
            if (l.length === 0) return
            if (l.length === 1) {
                // Una sola ventana: si estaba minimizada, se trae
                if (l[0].minimized) windowTracker.traerVentana(l[0].id)
                return
            }
            lista = l
            elegido = p > 0 ? 1 : l.length - 1
            dibujar = false
            conTeclado = false
            shellBackend.cambiadorVisible = true
            retraso.restart()
            sinTeclado.restart()
        } else if (lista.length > 0) {
            elegido = (elegido + p + lista.length) % lista.length
            dibujar = true
        }
    }

    function confirmar() {
        if (!shellBackend.cambiadorVisible) return
        var v = actual
        cerrar()
        if (v) windowTracker.traerVentana(v.id)
    }

    function cerrar() {
        retraso.stop(); sinTeclado.stop()
        dibujar = false
        shellBackend.cambiadorVisible = false
    }

    Connections {
        target: shellBackend
        function onAltTab(p) { cambiador.paso(p) }
    }

    Timer { id: retraso; interval: 130; onTriggered: cambiador.dibujar = true }

    // Si la capa no llega a tener el teclado, se toma como toque rápido
    Timer { id: sinTeclado; interval: 450; onTriggered: if (!cambiador.conTeclado) cambiador.confirmar() }

    // Soltar Alt: el evento de tecla llega casi siempre; esto cubre el resto
    Timer {
        interval: 50
        repeat: true
        running: shellBackend.cambiadorVisible && cambiador.conTeclado
        onTriggered: if (!shellBackend.altPulsada()) cambiador.confirmar()
    }

    Item {
        id: teclas
        focus: true
        Keys.onReleased: (e) => {
            if (e.key === Qt.Key_Alt || e.key === Qt.Key_Meta || !(e.modifiers & Qt.AltModifier)) {
                cambiador.confirmar(); e.accepted = true
            }
        }
        Keys.onPressed: (e) => {
            cambiador.conTeclado = true
            if (e.key === Qt.Key_Escape) { cambiador.cerrar(); e.accepted = true }
            else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Right) { cambiador.paso(1); e.accepted = true }
            else if (e.key === Qt.Key_Backtab || e.key === Qt.Key_Left) { cambiador.paso(-1); e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { cambiador.confirmar(); e.accepted = true }
        }
    }

    // Clic fuera: cancelar
    MouseArea {
        anchors.fill: parent
        enabled: cambiador.dibujar
        onClicked: cambiador.cerrar()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: fila.width + 32
        height: fila.height + textos.height + 40
        radius: 26
        color: tema.isDark ? Qt.rgba(0.11, 0.115, 0.13, 0.86) : Qt.rgba(0.97, 0.97, 0.98, 0.88)
        border.width: 1
        border.color: tema.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
        opacity: cambiador.dibujar ? 1 : 0
        scale: cambiador.dibujar ? 1 : 0.96
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 110 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Row {
            id: fila
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            Repeater {
                model: cambiador.lista
                delegate: Item {
                    id: celdaVentana
                    required property var modelData
                    required property int index
                    readonly property bool esElegida: index === cambiador.elegido
                    width: cambiador.celda
                    height: cambiador.celda

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 18
                        color: celdaVentana.esElegida
                               ? (tema.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.09))
                               : (raton.containsMouse ? tema.itemHover : "transparent")
                        border.width: celdaVentana.esElegida ? 1 : 0
                        border.color: tema.isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.12)
                    }
                    Image {
                        anchors.centerIn: parent
                        width: cambiador.tamIcono
                        height: cambiador.tamIcono
                        sourceSize: Qt.size(128, 128)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        source: tema.tinte(dockModel.iconoVentana(celdaVentana.modelData.appId, celdaVentana.modelData.title))
                        opacity: celdaVentana.modelData.minimized ? 0.55 : 1
                    }
                    MouseArea {
                        id: raton
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: cambiador.elegido = celdaVentana.index
                        onClicked: { cambiador.elegido = celdaVentana.index; cambiador.confirmar() }
                    }
                }
            }
        }

        Column {
            id: textos
            anchors.top: fila.bottom
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(fila.width, 520)
            spacing: 2
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: cambiador.actual ? cambiador.nombreApp(cambiador.actual) : ""
                color: tema.contentTextPrimary
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                visible: text.length > 0
                text: {
                    if (!cambiador.actual) return ""
                    var t = cambiador.actual.title || ""
                    if (t === cambiador.nombreApp(cambiador.actual)) t = ""
                    return cambiador.actual.minimized ? (t ? t + " · minimizada" : "Minimizada") : t
                }
                color: tema.contentTextSecondary
                font.pixelSize: 12
            }
        }
    }

    // Nombre legible: el de la app en el Dock si lo tiene; si no, el app_id
    // sin dominio ("org.gnome.TextEditor" -> "TextEditor").
    function nombreApp(v) {
        var n = dockModel.nombreVentana ? dockModel.nombreVentana(v.appId, v.title) : ""
        if (n) return n
        var a = v.appId || ""
        if (a.indexOf(".") !== -1) a = a.substring(a.lastIndexOf(".") + 1)
        return a ? a.charAt(0).toUpperCase() + a.substring(1) : (v.title || "")
    }
}
