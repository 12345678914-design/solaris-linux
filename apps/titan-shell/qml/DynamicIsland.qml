import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Effects   // MultiEffect (Qt 6.5+), solo para las caratulas

Item {
    id: dynamicIslandRoot
    width: islandCard.width
    height: islandCard.height

    TitanTheme { id: theme }

    // ---------- Datos del backend ----------
    readonly property bool active: shellBackend.islandActive
    readonly property var notif: shellBackend.currentIslandNotification
    readonly property var actions: notif && notif.actions ? notif.actions : []          // opcional
    readonly property int queued: shellBackend.islandQueueCount ? shellBackend.islandQueueCount : 0  // opcional

    // ---------- Opciones ----------
    property bool showIdlePill: false        // true = pastilla visible incluso sin notificación
    property real expandedWidth: 380
    property int  compactWidth: 140
    property int  compactHeight: 24

    readonly property real anchoPantalla: (typeof Screen !== "undefined" && Screen.width > 0) ? Screen.width : 1920

    // ---------- Musica (MPRIS) ----------
    // Sin notificacion delante, la isla ensena lo que suena: una pastilla con
    // caratula y titulo que se abre (clic, o sola al cambiar de cancion) en
    // una tarjeta con anterior / pausa / siguiente.
    readonly property bool hayMpris: typeof mpris !== "undefined" && mpris !== null
    readonly property bool musica: hayMpris && mpris.disponible && !active
    property bool musicaAbierta: false
    onMusicaChanged: if (!musica) musicaAbierta = false
    Timer {
        id: cierreMusica
        interval: 4500
        onTriggered: if (!ratonIsla.hovered) dynamicIslandRoot.musicaAbierta = false
    }
    Connections {
        target: dynamicIslandRoot.hayMpris ? mpris : null
        function onCancionNueva() {
            if (!dynamicIslandRoot.active) {
                dynamicIslandRoot.musicaAbierta = true
                cierreMusica.restart()
            }
        }
    }

    // ---------- Indicador de volumen / brillo (teclas) ----------
    // Tiene prioridad mientras dura (1,6 s); luego vuelve lo que hubiera.
    readonly property bool indicando: shellBackend.indicadorActivo
    readonly property var indicador: shellBackend.indicador

    // Dibujar la isla (visible solo si hay algo que mostrar)
    readonly property bool shown: active || showIdlePill || musica || indicando

    signal actionTriggered(var action)       // conecta esto a tu backend

    // Tamaño final de la isla (sin la animación): Shell.qml ajusta la
    // ventana a él una sola vez por transición.
    // (Con prefijo: hay un Item con id musicaAbierta que taparía la propiedad.)
    readonly property real anchoObjetivo: dynamicIslandRoot.indicando ? 236
           : dynamicIslandRoot.active
           ? Math.min(dynamicIslandRoot.expandedWidth, dynamicIslandRoot.anchoPantalla - 32)
           : dynamicIslandRoot.musica ? (dynamicIslandRoot.musicaAbierta ? 360 : 236) : dynamicIslandRoot.compactWidth
    readonly property real altoObjetivo: dynamicIslandRoot.indicando ? 34
           : dynamicIslandRoot.active
           ? Math.max(64, islandCard.contentH + 28)
           : dynamicIslandRoot.musica ? (dynamicIslandRoot.musicaAbierta ? 112 : 24) : dynamicIslandRoot.compactHeight

    Item {
        id: islandCard
        objectName: "islandCard"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top

        readonly property real contentH: Math.max(40, textCol.implicitHeight)
                                         + (actionsRow.visible ? actionsRow.height + 10 : 0)

        width: dynamicIslandRoot.anchoObjetivo
        height: dynamicIslandRoot.altoObjetivo
        readonly property real cornerRadius: Math.min(height / 2, 24)

        // Mismo muelle en ancho y alto: la isla crece sin deformarse
        Behavior on width  { SpringAnimation { spring: 3.4; damping: 0.34; epsilon: 0.25 } }
        Behavior on height { SpringAnimation { spring: 3.4; damping: 0.34; epsilon: 0.25 } }

        // Si no se muestra, no se dibuja ni recibe clics
        opacity: dynamicIslandRoot.shown ? 1.0 : 0.0
        visible: opacity > 0.01
        scale: dynamicIslandRoot.shown ? 1.0 : 0.7
        transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        // Arrastrar hacia arriba para descartar
        transform: Translate { y: Math.min(0, swipe.translation.y) * 0.6 }
        DragHandler {
            id: swipe
            xAxis.enabled: false
            yAxis.enabled: true
            target: null
            enabled: dynamicIslandRoot.active
            onActiveChanged: {
                if (!active && translation.y < -24) shellBackend.dismissIsland()
            }
        }

        // ---------- FONDO: negro casi opaco, como la isla del iPhone ----------
        // Antes era el fondo de pantalla recortado con MultiEffect: esa capa
        // se volvía a pintar en cada fotograma de la animación de tamaño.
        Rectangle {
            anchors.fill: parent
            radius: islandCard.cornerRadius
            color: Qt.rgba(0.02, 0.022, 0.03, 0.96)
            antialiasing: true
        }

        // Borde fino y brillo superior
        Rectangle {
            anchors.fill: parent
            radius: islandCard.cornerRadius
            color: "transparent"
            border.color: dynamicIslandRoot.active ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.12)
            border.width: 1
        }
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - islandCard.cornerRadius * 1.6
            height: 1
            radius: 1
            color: Qt.rgba(1, 1, 1, 0.10)
        }

        // Anillo de acento tenue solo cuando llega una notificación nueva
        Rectangle {
            id: arrivalRing
            anchors.fill: parent
            radius: islandCard.cornerRadius
            color: "transparent"
            border.color: theme.accent
            border.width: 1
            opacity: 0.0

            SequentialAnimation {
                id: ringAnim
                NumberAnimation { target: arrivalRing; property: "opacity"; to: 0.45; duration: 160 }
                NumberAnimation { target: arrivalRing; property: "opacity"; to: 0.0; duration: 500; easing.type: Easing.OutCubic }
            }
        }
        Connections {
            target: dynamicIslandRoot
            function onNotifChanged() { if (dynamicIslandRoot.active) ringAnim.restart() }
            function onActiveChanged() { if (dynamicIslandRoot.active) ringAnim.restart() }
        }

        // Con el ratón encima, el aviso no se va solo
        HoverHandler {
            enabled: dynamicIslandRoot.active
            onHoveredChanged: shellBackend.mantenerIsla(hovered)
        }

        // Clic en la tarjeta: abre el centro de notificaciones
        MouseArea {
            anchors.fill: parent
            z: -1
            enabled: dynamicIslandRoot.active
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (dynamicIslandRoot.notif && dynamicIslandRoot.notif.defaultAction) {
                    shellBackend.invokeNotificationAction(dynamicIslandRoot.notif.id, "default")
                    return
                }
                shellBackend.dismissIsland()
                shellBackend.toggleNotificationCenter()
            }
        }

        // ---------- MUSICA ----------
        HoverHandler {
            id: ratonIsla
            enabled: dynamicIslandRoot.musica
            onHoveredChanged: {
                if (hovered) cierreMusica.stop()
                else if (dynamicIslandRoot.musicaAbierta) cierreMusica.restart()
            }
        }
        MouseArea {
            anchors.fill: parent
            z: -1
            enabled: dynamicIslandRoot.musica
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                dynamicIslandRoot.musicaAbierta = !dynamicIslandRoot.musicaAbierta
                if (dynamicIslandRoot.musicaAbierta) cierreMusica.restart()
            }
        }

        // Pastilla: caratula pequena, titulo y barras de sonido
        Item {
            id: musicaCompacta
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 14
            opacity: dynamicIslandRoot.musica && !dynamicIslandRoot.musicaAbierta && !dynamicIslandRoot.indicando && islandCard.height < 50 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 140 } }

            Caratula {
                id: caratulaPequena
                fuente: dynamicIslandRoot.hayMpris ? mpris.caratula : ""
                width: 18; height: 18; radio: 9
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                anchors.left: caratulaPequena.right
                anchors.leftMargin: 9
                anchors.right: barras.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: dynamicIslandRoot.hayMpris ? mpris.titulo : ""
                color: "#ffffff"
                font.pixelSize: 12
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            BarrasSonido {
                id: barras
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Tarjeta abierta: caratula, titulo, artista y controles
        Item {
            id: musicaAbierta
            anchors.fill: parent
            anchors.margins: 14
            opacity: dynamicIslandRoot.musica && dynamicIslandRoot.musicaAbierta && !dynamicIslandRoot.indicando && islandCard.height > 80 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: dynamicIslandRoot.musicaAbierta ? 90 : 0 }
                    NumberAnimation { duration: 150 }
                }
            }

            Caratula {
                id: caratulaGrande
                fuente: dynamicIslandRoot.hayMpris ? mpris.caratula : ""
                width: 76; height: 76; radio: 14
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mpris.mostrarReproductor()
                }
            }

            Column {
                anchors.left: caratulaGrande.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 2
                spacing: 1
                Row {
                    spacing: 6
                    width: parent.width
                    Text {
                        text: dynamicIslandRoot.hayMpris ? mpris.reproductor : ""
                        color: theme.accent
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }
                }
                Text {
                    width: parent.width - 30
                    text: dynamicIslandRoot.hayMpris ? mpris.titulo : ""
                    color: "#ffffff"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width - 30
                    visible: text.length > 0
                    text: dynamicIslandRoot.hayMpris ? mpris.artista : ""
                    color: Qt.rgba(1, 1, 1, 0.62)
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
            BarrasSonido {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 4
            }

            Row {
                anchors.left: caratulaGrande.right
                anchors.leftMargin: 8
                anchors.bottom: parent.bottom
                spacing: 4
                BotonMedio {
                    tipo: "anterior"
                    activo: dynamicIslandRoot.hayMpris && mpris.puedeAnterior
                    onPulsado: mpris.anterior()
                }
                BotonMedio {
                    tipo: dynamicIslandRoot.hayMpris && mpris.reproduciendo ? "pausa" : "play"
                    grande: true
                    onPulsado: mpris.alternar()
                }
                BotonMedio {
                    tipo: "siguiente"
                    activo: dynamicIslandRoot.hayMpris && mpris.puedeSiguiente
                    onPulsado: mpris.siguiente()
                }
            }
        }

        // ---------- INDICADOR: icono, barra y porcentaje ----------
        Item {
            id: indicadorVista
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            opacity: dynamicIslandRoot.indicando && islandCard.height < 50 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 120 } }

            readonly property string tipo: dynamicIslandRoot.indicador && dynamicIslandRoot.indicador.tipo ? dynamicIslandRoot.indicador.tipo : "volumen"
            readonly property real valor: dynamicIslandRoot.indicador && dynamicIslandRoot.indicador.valor !== undefined ? dynamicIslandRoot.indicador.valor : 0
            readonly property bool silencio: dynamicIslandRoot.indicador ? !!dynamicIslandRoot.indicador.silencio : false

            Canvas {
                id: iconoIndicador
                width: 18; height: 18
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                property string clave: indicadorVista.tipo + (indicadorVista.silencio ? "-mudo" : "") + Math.min(3, Math.ceil(indicadorVista.valor * 3))
                onClaveChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d")
                    c.reset()
                    c.fillStyle = "#ffffff"; c.strokeStyle = "#ffffff"; c.lineWidth = 1.6; c.lineCap = "round"
                    var t = indicadorVista.tipo, v = indicadorVista.valor
                    if (t === "volumen" || t === "micro") {
                        if (t === "volumen") {
                            // altavoz
                            c.beginPath(); c.moveTo(2, 7); c.lineTo(5, 7); c.lineTo(9, 3.5); c.lineTo(9, 14.5); c.lineTo(5, 11); c.lineTo(2, 11); c.closePath(); c.fill()
                        } else {
                            // micrófono
                            c.beginPath(); c.moveTo(7, 3); c.lineTo(11, 3); c.lineTo(11, 10); c.lineTo(7, 10); c.closePath(); c.fill()
                            c.beginPath(); c.arc(9, 9, 5, 0, Math.PI); c.stroke()
                            c.beginPath(); c.moveTo(9, 14); c.lineTo(9, 16.5); c.stroke()
                        }
                        if (indicadorVista.silencio || (t === "volumen" && v <= 0.001)) {
                            var x = t === "volumen" ? 13 : 4
                            c.beginPath(); c.moveTo(x - 2.5, 6.5); c.lineTo(x + 2.5, 11.5); c.moveTo(x + 2.5, 6.5); c.lineTo(x - 2.5, 11.5)
                            if (t === "micro") { c.moveTo(3, 3); c.lineTo(15, 15) }
                            c.stroke()
                        } else if (t === "volumen") {
                            var ondas = Math.max(1, Math.min(3, Math.ceil(v * 3)))
                            for (var i = 1; i <= ondas; ++i) { c.beginPath(); c.arc(9, 9, 2.5 + i * 2.2, -0.75, 0.75); c.stroke() }
                        }
                    } else if (t === "teclado") {
                        c.strokeRect(1.5, 6, 15, 9)
                        for (var k = 0; k < 4; ++k) c.fillRect(3.5 + k * 3, 8.5, 1.6, 1.6)
                        c.fillRect(5.5, 12, 7, 1.4)
                        c.beginPath(); c.moveTo(9, 1); c.lineTo(9, 3.5); c.moveTo(4.5, 2.2); c.lineTo(5.6, 4); c.moveTo(13.5, 2.2); c.lineTo(12.4, 4); c.stroke()
                    } else {
                        // sol: más rayos cuanto más brillo
                        c.beginPath(); c.arc(9, 9, 3.4, 0, 2 * Math.PI); c.fill()
                        for (var r = 0; r < 8; ++r) {
                            var a = r * Math.PI / 4, l = 5.6 + 1.8 * Math.min(1, v + 0.2)
                            c.beginPath(); c.moveTo(9 + Math.cos(a) * 5.2, 9 + Math.sin(a) * 5.2); c.lineTo(9 + Math.cos(a) * l, 9 + Math.sin(a) * l); c.stroke()
                        }
                    }
                }
            }

            Text {
                id: porcentajeIndicador
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                horizontalAlignment: Text.AlignRight
                text: indicadorVista.silencio ? "" : Math.round(indicadorVista.valor * 100) + "%"
                color: "#ffffff"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }

            Rectangle {
                anchors.left: iconoIndicador.right
                anchors.leftMargin: 10
                anchors.right: porcentajeIndicador.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 5
                radius: 2.5
                color: Qt.rgba(1, 1, 1, 0.18)
                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    // Se anima el nivel, no el ancho: así la barra no se queda
                    // atrás mientras la isla crece.
                    property real nivel: indicadorVista.silencio ? 0 : indicadorVista.valor
                    Behavior on nivel { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    width: parent.width * nivel
                    color: "#ffffff"
                }
            }
        }

        // ---------- CONTENIDO (aparece un poco después de crecer) ----------
        Item {
            id: body
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            anchors.topMargin: 14
            anchors.bottomMargin: 14

            opacity: dynamicIslandRoot.active && !dynamicIslandRoot.indicando && islandCard.height > 48 ? 1.0 : 0.0
            visible: opacity > 0.01
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: dynamicIslandRoot.active ? 110 : 0 }
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }

            // Icono
            Item {
                id: iconTile
                width: 40
                height: 40
                anchors.left: parent.left
                anchors.top: parent.top

                Rectangle { anchors.fill: parent; radius: 10; color: Qt.rgba(1, 1, 1, 0.09) }

                Image {
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    source: dynamicIslandRoot.notif && dynamicIslandRoot.notif.icon
                            ? dynamicIslandRoot.notif.icon : "qrc:/icons/system.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }

            // Cierre (cruz dibujada, sin depender de la fuente)
            Item {
                id: closeBtn
                width: 22
                height: 22
                anchors.right: parent.right
                anchors.top: parent.top

                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.12)
                }
                Rectangle { anchors.centerIn: parent; width: 10; height: 1.5; radius: 1; rotation: 45;  color: "#ffffff" }
                Rectangle { anchors.centerIn: parent; width: 10; height: 1.5; radius: 1; rotation: -45; color: "#ffffff" }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.dismissIsland()
                }
            }

            // Contador de cola "+N"
            Rectangle {
                id: queueBadge
                visible: dynamicIslandRoot.queued > 0
                height: 18
                width: queueText.implicitWidth + 14
                radius: 9
                color: theme.accent
                anchors.right: closeBtn.left
                anchors.rightMargin: 8
                anchors.top: parent.top
                anchors.topMargin: 2

                Text {
                    id: queueText
                    anchors.centerIn: parent
                    text: "+" + dynamicIslandRoot.queued
                    color: "#ffffff"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }

            // Textos
            Column {
                id: textCol
                anchors.left: iconTile.right
                anchors.leftMargin: 12
                anchors.right: queueBadge.visible ? queueBadge.left : closeBtn.left
                anchors.rightMargin: 8
                anchors.top: parent.top
                spacing: 2

                Row {
                    spacing: 6
                    Text {
                        text: dynamicIslandRoot.notif && dynamicIslandRoot.notif.appName
                              ? dynamicIslandRoot.notif.appName : qsTr("Sistema")
                        color: theme.accent
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                    Text { text: "•"; color: Qt.rgba(1, 1, 1, 0.4); font.pixelSize: 10 }
                    Text {
                        text: dynamicIslandRoot.notif && dynamicIslandRoot.notif.time
                              ? dynamicIslandRoot.notif.time : qsTr("Ahora")
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 11
                    }
                }

                Text {
                    width: parent.width
                    text: dynamicIslandRoot.notif && dynamicIslandRoot.notif.title ? dynamicIslandRoot.notif.title : ""
                    color: "#ffffff"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: dynamicIslandRoot.notif && dynamicIslandRoot.notif.message ? dynamicIslandRoot.notif.message : ""
                    color: Qt.rgba(1, 1, 1, 0.78)
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            // Botones de acción (si la notificación trae `actions`)
            Row {
                id: actionsRow
                visible: dynamicIslandRoot.actions && dynamicIslandRoot.actions.length > 0
                anchors.left: textCol.left
                anchors.top: textCol.bottom
                anchors.topMargin: 10
                spacing: 8

                Repeater {
                    model: dynamicIslandRoot.actions
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        height: 26
                        width: actionLabel.implicitWidth + 28
                        radius: 13
                        color: index === 0
                               ? (actionMouse.containsMouse ? Qt.lighter(theme.accent, 1.15) : theme.accent)
                               : (actionMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12))

                        Text {
                            id: actionLabel
                            anchors.centerIn: parent
                            text: modelData.label ? modelData.label : modelData
                            color: "#ffffff"
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                dynamicIslandRoot.actionTriggered(modelData)
                                shellBackend.invokeNotificationAction(dynamicIslandRoot.notif.id, modelData.key)
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- Piezas de la musica ----------
    component BarrasSonido: Row {
        spacing: 2
        height: 14
        Repeater {
            model: 4
            Rectangle {
                id: barra
                required property int index
                width: 3
                radius: 1.5
                anchors.bottom: parent.bottom
                color: theme.accent
                readonly property bool suena: dynamicIslandRoot.hayMpris && mpris.reproduciendo && dynamicIslandRoot.musica
                height: suena ? 4 : 3
                SequentialAnimation on height {
                    // Solo se anima la copia que se ve (hay dos: pastilla y tarjeta)
                    running: barra.suena && barra.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 6 + (barra.index * 5) % 9; duration: 220 + barra.index * 60; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 3 + barra.index % 2; duration: 260 + barra.index * 40; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 14 - barra.index * 2; duration: 200 + barra.index * 50; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 4; duration: 240; easing.type: Easing.InOutSine }
                }
            }
        }
    }
}
