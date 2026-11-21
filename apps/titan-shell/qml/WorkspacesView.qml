import QtQuick 2.15

// Vista de escritorios estilo GNOME (Actividades):
//  - al abrir, el escritorio actual se encoge desde pantalla completa hasta
//    una tarjeta centrada, con los escritorios vecinos asomando a los lados;
//  - arriba, una tira de miniaturas para elegir otro escritorio o crear uno;
//  - las ventanas se pueden arrastrar a otra miniatura o a otro escritorio;
//  - clic en el escritorio central, Intro o Esc: vuelve a crecer y se cierra.
//
// Pensada para ir fluida tambien con el renderizado por software (QEMU sin
// 3D): una sola animacion (progreso), el fondo se decodifica una vez a
// tamano reducido y en segundo plano, y no hay desenfoques ni sombras.
Item {
    id: vista
    anchors.fill: parent

    TitanTheme { id: theme }

    // 0 = escritorio a pantalla completa, 1 = vista abierta.
    property real progreso: 0
    property bool cerrando: false

    readonly property real anchoPantalla: Math.max(1, width)
    readonly property real altoPantalla: Math.max(1, height)
    readonly property real proporcion: anchoPantalla / altoPantalla

    // Tira de miniaturas
    readonly property real altoMini: Math.round(Math.max(64, Math.min(116, altoPantalla * 0.11)))
    readonly property real anchoMini: Math.round(altoMini * proporcion)
    readonly property real yTira: 26

    // Escritorio central
    readonly property real yCentral: yTira + altoMini + 34
    readonly property real altoCentral: {
        var alto = altoPantalla - yCentral - 56
        return Math.max(120, Math.min(alto, anchoPantalla * 0.78 / proporcion))
    }
    readonly property real anchoCentral: altoCentral * proporcion
    readonly property real escalaInicial: altoPantalla / altoCentral

    readonly property string fondo: shellBackend.currentWallpaper.length > 0
                                    ? "file://" + shellBackend.currentWallpaper : ""
    readonly property size tamFondo: Qt.size(Math.round(anchoCentral), Math.round(altoCentral))

    function ventanasDe(indice) {
        var todas = windowTracker.windows
        var lista = []
        for (var i = 0; i < todas.length; ++i) {
            if (todas[i].workspace === indice)
                lista.push(todas[i])
        }
        return lista
    }

    function iconoDe(appId) {
        var a = (appId || "").toLowerCase()
        if (a.indexOf("/") !== -1) return "file://" + appId
        if (a.indexOf("terminal") !== -1 || a.indexOf("kitty") !== -1 || a.indexOf("foot") !== -1) return "qrc:/icons/terminal.png"
        if (a.indexOf("finder") !== -1) return "qrc:/icons/finder.png"
        if (a.indexOf("dolphin") !== -1 || a.indexOf("pcmanfm") !== -1 || a.indexOf("nautilus") !== -1) return "qrc:/icons/files.png"
        if (a.indexOf("firefox") !== -1 || a.indexOf("browser") !== -1) return "qrc:/icons/firefox.png"
        if (a.indexOf("code") !== -1) return "qrc:/icons/vscode.png"
        if (a.indexOf("settings") !== -1) return "qrc:/icons/system.png"
        if (a.indexOf("onlyoffice") !== -1 || a.indexOf("desktopeditors") !== -1) return "qrc:/icons/onlyoffice.png"
        if (a.indexOf("calc") !== -1) return "qrc:/icons/calculator.png"
        if (a.indexOf("calendar") !== -1) return "qrc:/icons/calendar.png"
        if (a.indexOf("clock") !== -1) return "qrc:/icons/clock.png"
        if (a.indexOf("video") !== -1) return "qrc:/icons/video.png"
        if (a.indexOf("musica") !== -1 || a.indexOf("music") !== -1) return "qrc:/icons/music-app.png"
        if (a.indexOf("fotos") !== -1) return "qrc:/icons/pictures.png"
        if (a.indexOf("acerca") !== -1) return "qrc:/icons/about.png"
        if (a.indexOf("vim") !== -1) return "qrc:/icons/developer.png"
        return "qrc:/icons/apps-folder.png"
    }

    function irA(indice) {
        if (indice < 0 || indice >= shellBackend.workspaces.length) return
        if (indice !== shellBackend.currentWorkspace)
            shellBackend.switchToWorkspace(indice, false)
    }

    function abrir() {
        cerrando = false
        animSalida.stop()
        progreso = 0
        animEntrada.restart()
        vista.forceActiveFocus()
    }

    function cerrar() {
        if (cerrando || !shellBackend.workspacesVisible) return
        cerrando = true
        animEntrada.stop()
        animSalida.restart()
    }

    NumberAnimation {
        id: animEntrada
        target: vista; property: "progreso"
        to: 1; duration: 320; easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: animSalida
        target: vista; property: "progreso"
        to: 0; duration: 240; easing.type: Easing.InOutCubic
        onFinished: {
            vista.cerrando = false
            shellBackend.workspacesVisible = false
        }
    }

    Connections {
        target: shellBackend
        function onWorkspacesVisibleChanged() {
            if (shellBackend.workspacesVisible) vista.abrir()
            else { animEntrada.stop(); animSalida.stop(); vista.progreso = 0; vista.cerrando = false }
        }
        function onWorkspacesCloseRequested() { vista.cerrar() }
    }
    Component.onCompleted: if (shellBackend.workspacesVisible) abrir()

    focus: true
    Keys.onEscapePressed: cerrar()
    Keys.onReturnPressed: cerrar()
    Keys.onEnterPressed: cerrar()
    Keys.onLeftPressed: irA(shellBackend.currentWorkspace - 1)
    Keys.onRightPressed: irA(shellBackend.currentWorkspace + 1)

    // ── Fondo oscuro (aparece mientras el escritorio se encoge) ─────────────
    Rectangle {
        anchors.fill: parent
        opacity: vista.progreso
        gradient: Gradient {
            GradientStop { position: 0.0; color: theme.isDark ? "#1a1c24" : "#2a2e38" }
            GradientStop { position: 1.0; color: theme.isDark ? "#0e0f14" : "#1a1d25" }
        }
    }

    // Clic fuera de todo: cerrar. La rueda cambia de escritorio.
    MouseArea {
        anchors.fill: parent
        onClicked: vista.cerrar()
        property real acumulado: 0
        onWheel: function(rueda) {
            acumulado += rueda.angleDelta.y !== 0 ? rueda.angleDelta.y : -rueda.angleDelta.x
            if (acumulado <= -120) { acumulado = 0; vista.irA(shellBackend.currentWorkspace + 1) }
            else if (acumulado >= 120) { acumulado = 0; vista.irA(shellBackend.currentWorkspace - 1) }
        }
    }

    // ── Escritorios grandes (el actual centrado, vecinos asomando) ──────────
    Item {
        id: carrusel
        x: 0
        width: vista.anchoPantalla
        height: vista.altoCentral
        y: vista.yCentral + (vista.altoPantalla / 2 - (vista.yCentral + vista.altoCentral / 2)) * (1 - vista.progreso)
        scale: 1 + (vista.escalaInicial - 1) * (1 - vista.progreso)
        transformOrigin: Item.Center

        readonly property real paso: vista.anchoCentral + 44
        // Desplazamiento de la fila: el escritorio actual queda centrado.
        property real desplazamiento: (width - vista.anchoCentral) / 2 - shellBackend.currentWorkspace * paso
        Behavior on desplazamiento {
            enabled: vista.progreso > 0.99
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: shellBackend.workspaces
            Item {
                id: escritorio
                x: carrusel.desplazamiento + index * carrusel.paso
                width: vista.anchoCentral
                height: vista.altoCentral
                readonly property int indice: index
                readonly property bool esActual: index === shellBackend.currentWorkspace
                readonly property var ventanas: { windowTracker.windows; return vista.ventanasDe(index) }

                // Los vecinos se ven algo apagados
                opacity: esActual ? 1 : 0.55 + 0.45 * (1 - vista.progreso)

                Rectangle {
                    id: marco
                    anchors.fill: parent
                    radius: 18 * vista.progreso
                    color: "#101218"
                    border.width: soltar.containsDrag ? 3 : 0
                    border.color: theme.accent

                    Image {
                        anchors.fill: parent
                        source: vista.fondo
                        sourceSize: vista.tamFondo
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        smooth: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (escritorio.esActual) vista.cerrar()
                        else vista.irA(escritorio.indice)
                    }
                }

                DropArea {
                    id: soltar
                    anchors.fill: parent
                    keys: ["titan-ventana"]
                    onDropped: function(evento) {
                        windowTracker.moveWindowToWorkspace(evento.source.idVentana, escritorio.indice)
                        evento.accept()
                    }
                }

                // Ventanas del escritorio, repartidas en rejilla
                Grid {
                    id: rejilla
                    anchors.centerIn: parent
                    opacity: vista.progreso
                    visible: opacity > 0.01
                    readonly property int n: escritorio.ventanas.length
                    columns: Math.max(1, Math.ceil(Math.sqrt(n)))
                    readonly property int filas: Math.max(1, Math.ceil(n / columns))
                    spacing: 22
                    readonly property real anchoCelda: Math.min(vista.anchoCentral * 0.36,
                        (vista.anchoCentral * 0.86 - (columns - 1) * spacing) / columns)
                    readonly property real altoCelda: Math.min(anchoCelda / 1.5,
                        (vista.altoCentral * 0.80 - (filas - 1) * spacing) / filas)

                    Repeater {
                        model: escritorio.ventanas

                        Item {
                            id: celda
                            width: rejilla.altoCelda * 1.5
                            height: rejilla.altoCelda

                            Rectangle {
                                id: tarjeta
                                property var idVentana: modelData.id
                                width: celda.width
                                height: celda.height
                                radius: 12
                                color: theme.isDark ? Qt.rgba(0.13, 0.14, 0.18, 0.94) : Qt.rgba(0.96, 0.96, 0.98, 0.94)
                                border.width: raton.containsMouse || modelData.active ? 2 : 1
                                border.color: raton.containsMouse ? theme.accent
                                              : (modelData.active ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.16))
                                opacity: modelData.minimized ? 0.6 : 1
                                z: raton.drag.active ? 100 : 0

                                Drag.active: raton.drag.active
                                Drag.keys: ["titan-ventana"]
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: height / 2

                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                                    height: 26
                                    radius: 11
                                    color: Qt.rgba(0, 0, 0, theme.isDark ? 0.30 : 0.07)
                                    Text {
                                        anchors.centerIn: parent
                                        width: parent.width - 44
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideMiddle
                                        text: modelData.title || modelData.appId || "Ventana"
                                        color: theme.isDark ? "#f2f2f5" : "#1c1c1e"
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                    }
                                    // Cerrar ventana
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 13; height: 13; radius: 6.5
                                        visible: raton.containsMouse || cerrarRaton.containsMouse
                                        color: cerrarRaton.containsMouse ? "#ff453a" : "#ff5f57"
                                        MouseArea {
                                            id: cerrarRaton
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            onClicked: windowTracker.closeWindowById(modelData.id)
                                        }
                                    }
                                }

                                Image {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: 8
                                    width: Math.min(64, parent.height * 0.45)
                                    height: width
                                    source: vista.iconoDe(modelData.appId)
                                    sourceSize: Qt.size(128, 128)
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }

                                MouseArea {
                                    id: raton
                                    anchors.fill: parent
                                    anchors.topMargin: 26
                                    hoverEnabled: true
                                    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                    drag.target: tarjeta
                                    drag.threshold: 8
                                    onReleased: {
                                        if (drag.active || tarjeta.x !== 0 || tarjeta.y !== 0) {
                                            tarjeta.Drag.drop()
                                            tarjeta.x = 0
                                            tarjeta.y = 0
                                        }
                                    }
                                    onClicked: {
                                        windowTracker.activateWindowById(modelData.id)
                                        vista.cerrar()
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: escritorio.ventanas.length === 0 && vista.progreso > 0.01
                    opacity: vista.progreso * 0.85
                    text: "Sin ventanas"
                    color: "#ffffff"
                    font.pixelSize: 15
                    font.weight: Font.Medium
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.4)
                }
            }
        }
    }

    // Nombre del escritorio, bajo la tarjeta central
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: vista.yCentral + vista.altoCentral + 14
        opacity: vista.progreso
        text: shellBackend.workspaces[shellBackend.currentWorkspace] !== undefined
              ? shellBackend.workspaces[shellBackend.currentWorkspace]
              : "Escritorio " + (shellBackend.currentWorkspace + 1)
        color: "#ffffff"
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    // ── Tira de miniaturas ──────────────────────────────────────────────────
    Row {
        id: tira
        anchors.horizontalCenter: parent.horizontalCenter
        y: vista.yTira - (vista.altoMini + vista.yTira) * (1 - vista.progreso)
        opacity: vista.progreso
        spacing: 14

        Repeater {
            model: shellBackend.workspaces

            Item {
                id: mini
                width: vista.anchoMini
                height: vista.altoMini
                readonly property bool esActual: index === shellBackend.currentWorkspace
                readonly property var ventanas: { windowTracker.windows; return vista.ventanasDe(index) }
                scale: miniRaton.containsMouse && !esActual ? 1.05 : 1
                Behavior on scale { NumberAnimation { duration: 120 } }

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: "#101218"
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: vista.fondo
                        sourceSize: Qt.size(vista.anchoMini * 2, vista.altoMini * 2)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        opacity: mini.esActual ? 1 : 0.7
                    }
                }

                // Iconos de las apps de ese escritorio
                Row {
                    anchors.centerIn: parent
                    spacing: 4
                    Repeater {
                        model: Math.min(4, mini.ventanas.length)
                        Image {
                            width: Math.round(vista.altoMini * 0.28)
                            height: width
                            source: vista.iconoDe(mini.ventanas[index].appId)
                            sourceSize: Qt.size(64, 64)
                            asynchronous: true
                            smooth: true
                            mipmap: true
                        }
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    text: index + 1
                    color: "#ffffff"
                    font.pixelSize: 11
                    font.bold: true
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.5)
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: "transparent"
                    border.width: mini.esActual || miniSoltar.containsDrag ? 2.5 : 1
                    border.color: mini.esActual || miniSoltar.containsDrag ? theme.accent : Qt.rgba(1, 1, 1, 0.22)
                }

                MouseArea {
                    id: miniRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: vista.irA(index)
                }

                DropArea {
                    id: miniSoltar
                    anchors.fill: parent
                    keys: ["titan-ventana"]
                    onDropped: function(evento) {
                        windowTracker.moveWindowToWorkspace(evento.source.idVentana, index)
                        evento.accept()
                    }
                }

                // Quitar escritorio (no el actual, y siempre queda uno)
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: -6
                    width: 20; height: 20; radius: 10
                    visible: (miniRaton.containsMouse || quitarRaton.containsMouse)
                             && shellBackend.workspaces.length > 1 && !mini.esActual
                    color: quitarRaton.containsMouse ? "#ff453a" : Qt.rgba(0.2, 0.2, 0.24, 0.95)
                    border.color: Qt.rgba(1, 1, 1, 0.3)
                    Text { anchors.centerIn: parent; text: "✕"; color: "#ffffff"; font.pixelSize: 10 }
                    MouseArea {
                        id: quitarRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: shellBackend.removeWorkspace(index)
                    }
                }
            }
        }

        // Nuevo escritorio
        Rectangle {
            width: Math.round(vista.anchoMini * 0.45)
            height: vista.altoMini
            radius: 10
            color: nuevoRaton.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
            border.color: nuevoRaton.containsMouse ? theme.accent : Qt.rgba(1, 1, 1, 0.2)
            Text {
                anchors.centerIn: parent
                text: "+"
                color: "#ffffff"
                font.pixelSize: 26
                font.weight: Font.Light
            }
            MouseArea {
                id: nuevoRaton
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: shellBackend.addWorkspace()
            }
        }
    }

    // Sin barra superior en esta vista (la tapa entera): solo la hora y la
    // fecha arriba a la derecha, con el formato elegido en Ajustes > Barra.
    Column {
        id: reloj
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 18
        anchors.rightMargin: 28
        spacing: 2
        opacity: vista.progreso
        property date ahora: new Date()
        readonly property bool h24: { prefs.version; return prefs.b("Barra/reloj24h") }
        Timer {
            interval: 1000
            repeat: true
            running: vista.visible && vista.progreso > 0
            triggeredOnStart: true
            onTriggered: reloj.ahora = new Date()
        }
        Text {
            anchors.right: parent.right
            text: Qt.formatTime(reloj.ahora, reloj.h24 ? "HH:mm" : "h:mm AP")
            color: "#ffffff"
            font.pixelSize: 26
            font.weight: Font.DemiBold
        }
        Text {
            anchors.right: parent.right
            text: Qt.formatDate(reloj.ahora, "dddd, d 'de' MMMM")
            color: Qt.rgba(1, 1, 1, 0.7)
            font.pixelSize: 12
        }
    }
}
