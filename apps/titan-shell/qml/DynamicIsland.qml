import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Effects   // MultiEffect (Qt 6.5+), solo para recortar esquinas

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
    property int  compactHeight: 26

    // Refleja el fondo de pantalla ACTUAL (ver GlassPanel.qml): se decodifica en minúscula y se
    // amplía, así que no hace falta pre-desenfocar nada ni usar blur en vivo.
    readonly property string wallpaperPath: shellBackend.currentWallpaper ? shellBackend.currentWallpaper : ""
    readonly property bool hasGlass: wallpaperPath !== ""

    function toUrl(p) {
        if (!p) return ""
        var s = p.toString()
        if (s.indexOf("://") !== -1 || s.indexOf("qrc:") === 0) return s
        if (s.charAt(0) === "/") return "file://" + s
        return s
    }

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

    // Dibujar la isla (visible solo si hay algo que mostrar)
    readonly property bool shown: active || showIdlePill || musica

    signal actionTriggered(var action)       // conecta esto a tu backend

    // Posición de la isla en pantalla (para alinear el wallpaper borroso)
    property real glassOriginX: 0
    property real glassOriginY: 0
    function updateOrigin() {
        if (!islandCard) return
        var p = islandCard.mapToGlobal(0, 0)
        var vx = (typeof Screen !== "undefined" && typeof Screen.virtualX !== "undefined") ? Screen.virtualX : 0
        var vy = (typeof Screen !== "undefined" && typeof Screen.virtualY !== "undefined") ? Screen.virtualY : 0
        glassOriginX = p.x - vx
        glassOriginY = p.y - vy
    }
    Component.onCompleted: Qt.callLater(updateOrigin)

    Item {
        id: islandCard
        objectName: "islandCard"   // main.cpp limita la zona de clics a esta tarjeta
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top

        readonly property real contentH: Math.max(40, textCol.implicitHeight)
                                         + (actionsRow.visible ? actionsRow.height + 10 : 0)

        width: dynamicIslandRoot.active
               ? Math.min(dynamicIslandRoot.expandedWidth, (typeof Screen !== "undefined" && Screen.width > 0 ? Screen.width : 1920) - 32)
               : dynamicIslandRoot.musica
                 ? (dynamicIslandRoot.musicaAbierta ? 360 : 236)
                 : dynamicIslandRoot.compactWidth
        height: dynamicIslandRoot.active
                ? Math.max(64, contentH + 28)
                : dynamicIslandRoot.musica
                  ? (dynamicIslandRoot.musicaAbierta ? 112 : 34)
                  : dynamicIslandRoot.compactHeight
        readonly property real cornerRadius: Math.min(height / 2, 24)

        onWidthChanged: Qt.callLater(dynamicIslandRoot.updateOrigin)
        onHeightChanged: Qt.callLater(dynamicIslandRoot.updateOrigin)

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

        // ---------- VIDRIO: wallpaper borroso recortado + tinte oscuro ----------
        Item {
            anchors.fill: parent
            layer.enabled: dynamicIslandRoot.hasGlass
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: glassMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Image {
                visible: dynamicIslandRoot.hasGlass
                source: dynamicIslandRoot.toUrl(dynamicIslandRoot.wallpaperPath)
                sourceSize: Qt.size(48, 27)      // decodificación minúscula = desenfoque barato
                x: -dynamicIslandRoot.glassOriginX
                y: -dynamicIslandRoot.glassOriginY
                width: (typeof Screen !== "undefined" && Screen.width > 0) ? Screen.width : 1920
                height: (typeof Screen !== "undefined" && Screen.height > 0) ? Screen.height : 1080
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
            }

            // Tinte: oscuro y casi opaco para un blur "pequeño" y legible
            Rectangle {
                anchors.fill: parent
                radius: islandCard.cornerRadius
                color: dynamicIslandRoot.hasGlass ? Qt.rgba(0.04, 0.045, 0.055, 0.80) : "#0a0b0e"
            }
        }

        Rectangle {
            id: glassMask
            anchors.fill: parent
            radius: islandCard.cornerRadius
            visible: false
            layer.enabled: true
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
            opacity: dynamicIslandRoot.musica && !dynamicIslandRoot.musicaAbierta && islandCard.height < 50 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 140 } }

            Caratula {
                id: caratulaPequena
                width: 24; height: 24; radio: 12
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
            opacity: dynamicIslandRoot.musica && dynamicIslandRoot.musicaAbierta && islandCard.height > 80 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: dynamicIslandRoot.musicaAbierta ? 90 : 0 }
                    NumberAnimation { duration: 150 }
                }
            }

            Caratula {
                id: caratulaGrande
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

        // ---------- CONTENIDO (aparece un poco después de crecer) ----------
        Item {
            id: body
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            anchors.topMargin: 14
            anchors.bottomMargin: 14

            opacity: dynamicIslandRoot.active && islandCard.height > 48 ? 1.0 : 0.0
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
    component Caratula: Item {
        property real radio: 8
        Rectangle {
            id: fondoCaratula
            anchors.fill: parent
            radius: parent.radio
            color: Qt.rgba(1, 1, 1, 0.10)
            // Nota musical si el reproductor no da caratula
            Text {
                anchors.centerIn: parent
                visible: imagenCaratula.status !== Image.Ready
                text: "\u266A"
                color: Qt.rgba(1, 1, 1, 0.7)
                font.pixelSize: parent.height * 0.5
            }
        }
        Image {
            id: imagenCaratula
            anchors.fill: parent
            source: dynamicIslandRoot.hayMpris ? mpris.caratula : ""
            sourceSize: Qt.size(160, 160)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: imagenCaratula
            visible: imagenCaratula.status === Image.Ready
            maskEnabled: true
            maskSource: mascaraCaratula
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
        Rectangle {
            id: mascaraCaratula
            anchors.fill: parent
            radius: parent.radio
            visible: false
            layer.enabled: true
        }
    }

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
                    running: barra.suena
                    loops: Animation.Infinite
                    NumberAnimation { to: 6 + (barra.index * 5) % 9; duration: 220 + barra.index * 60; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 3 + barra.index % 2; duration: 260 + barra.index * 40; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 14 - barra.index * 2; duration: 200 + barra.index * 50; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 4; duration: 240; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    component BotonMedio: Item {
        id: boton
        property string tipo: "play"
        property bool grande: false
        property bool activo: true
        signal pulsado()
        width: grande ? 36 : 30
        height: 30
        opacity: activo ? 1 : 0.35
        Rectangle {
            anchors.centerIn: parent
            width: 30; height: 30; radius: 15
            color: ratonBoton.containsMouse && boton.activo ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
        }
        Canvas {
            id: dibujo
            anchors.centerIn: parent
            width: 18; height: 18
            property string t: boton.tipo
            onTChanged: requestPaint()
            onPaint: {
                var c = getContext("2d")
                c.reset()
                c.fillStyle = "#ffffff"
                function tri(x0, dir) {   // triangulo de 8 px de ancho apuntando a dir
                    c.beginPath()
                    if (dir > 0) { c.moveTo(x0, 4); c.lineTo(x0 + 8, 9); c.lineTo(x0, 14) }
                    else { c.moveTo(x0 + 8, 4); c.lineTo(x0, 9); c.lineTo(x0 + 8, 14) }
                    c.closePath(); c.fill()
                }
                if (t === "play") {
                    c.beginPath(); c.moveTo(5, 2); c.lineTo(16, 9); c.lineTo(5, 16); c.closePath(); c.fill()
                } else if (t === "pausa") {
                    c.fillRect(4, 3, 3.5, 12); c.fillRect(10.5, 3, 3.5, 12)
                } else if (t === "siguiente") {
                    tri(2, 1); tri(9, 1)
                } else {
                    tri(1, -1); tri(8, -1)
                }
            }
        }
        MouseArea {
            id: ratonBoton
            anchors.fill: parent
            hoverEnabled: true
            enabled: boton.activo
            cursorShape: Qt.PointingHandCursor
            onClicked: boton.pulsado()
        }
    }
}
