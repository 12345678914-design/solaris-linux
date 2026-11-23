import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Effects   // MultiEffect (Qt 6.5+), solo para recortar esquinas

Item {
    id: launcher
    width: 740
    height: 530

    // ---------- Estado ----------
    readonly property real panelRadius: 24
    readonly property int columns: 5
    readonly property bool open: shellBackend.launcherVisible
    property int selectedIndex: -1
    property string pendingPower: ""          // "", "reboot" o "poweroff"

    // Refleja el fondo de pantalla ACTUAL (ver GlassPanel.qml): se decodifica en minúscula y se
    // amplía, así que no hace falta pre-desenfocar nada ni usar blur en vivo.
    readonly property string wallpaperPath: shellBackend.currentWallpaper ? shellBackend.currentWallpaper : ""
    readonly property bool hasGlass: wallpaperPath !== ""

    // Opcional: lista de apps recientes. Si no existe, la fila "Recientes" no se muestra.
    readonly property var recents: launcherBackend.recentApps ? launcherBackend.recentApps : []
    readonly property bool showRecents: searchField.text.length === 0 && recents.length > 0

    TitanTheme { id: titanTheme }   // una sola instancia

    // Posición en pantalla para alinear el wallpaper borroso
    property real glassOriginX: 0
    property real glassOriginY: 0
    function updateOrigin() {
        if (!launcher) return
        var p = launcher.mapToGlobal(0, 0)
        var vx = (typeof Screen !== "undefined" && typeof Screen.virtualX !== "undefined") ? Screen.virtualX : 0
        var vy = (typeof Screen !== "undefined" && typeof Screen.virtualY !== "undefined") ? Screen.virtualY : 0
        glassOriginX = p.x - vx
        glassOriginY = p.y - vy
    }

    // ---------- Iconos (tabla en vez de cadena de if) ----------
    readonly property string fallbackIcon: "qrc:/icons/system.png"
    readonly property var iconMap: ({
        "folder": "qrc:/icons/finder.png",
        "titan-finder": "qrc:/icons/finder.png",
        "utilities-terminal": "qrc:/icons/terminal.png",
        "terminal": "qrc:/icons/terminal.png",
        "titan-terminal": "qrc:/icons/terminal.png",
        "system-file-manager": "qrc:/icons/files.png",
        "pcmanfm-qt": "qrc:/icons/files.png",
        "files": "qrc:/icons/files.png",
        "help-about": "qrc:/icons/about.png",
        "titan-acerca": "qrc:/icons/about.png",
        "firefox": "qrc:/icons/firefox.png",
        "safari": "qrc:/icons/firefox.png",
        "vscode": "qrc:/icons/vscode.png",
        "code": "qrc:/icons/vscode.png",
        "system": "qrc:/icons/system.png",
        "titan-settings": "qrc:/icons/system.png",
        "onlyoffice": "qrc:/icons/onlyoffice.png",
        "onlyoffice-desktopeditors": "qrc:/icons/onlyoffice.png",
        "developer": "qrc:/icons/developer.png",
        "vim": "qrc:/icons/developer.png",
        "calculator": "qrc:/icons/calculator.png",
        "titan-calc": "qrc:/icons/calculator.png",
        "calendar": "qrc:/icons/calendar.png",
        "titan-calendar": "qrc:/icons/calendar.png",
        "clock": "qrc:/icons/clock.png",
        "titan-clock": "qrc:/icons/clock.png",
        "video": "qrc:/icons/video.png",
        "titan-video": "qrc:/icons/video.png",
        "music": "qrc:/icons/music-app.png",
        "titan-musica": "qrc:/icons/music-app.png",
        "pictures": "qrc:/icons/pictures.png",
        "titan-fotos": "qrc:/icons/pictures.png"
    })
    function iconFor(ic) {
        if (!ic) return fallbackIcon
        if (ic.indexOf("/") !== -1) return ic
        return iconMap[ic] ? iconMap[ic] : fallbackIcon
    }

    // ---------- Menú del clic derecho de cada app ----------
    property var menuApp: null          // la app del menú abierto
    property var menuOpciones: ({ acciones: [], desinstalable: false, motivo: "" })
    property real menuX: 0
    property real menuY: 0
    property bool propsVisible: false
    property var propsLista: []
    property bool confirmarQuitar: false
    property var appQuitar: null
    property string aviso: ""

    function abrirMenu(app, celda, x, y) {
        if (!app) return
        var p = celda.mapToItem(launcher, x, y)
        menuOpciones = launcherBackend.opcionesApp(app.desktop || "")
        menuX = p.x
        menuY = p.y
        menuApp = app
    }
    function cerrarMenus() {
        menuApp = null
        propsVisible = false
        confirmarQuitar = false
    }
    // Junto al puntero; si no cabe, hacia el otro lado (como Windows)
    function posMenu(p, tam, total) {
        var m = 8
        var q = p + tam + m <= total ? p : p - tam
        return Math.max(m, Math.min(q, total - tam - m))
    }
    function avisar(t) { aviso = t; avisoTimer.restart() }
    function opcionesMenu() {
        var app = menuApp
        if (!app) return []
        var o = [{ t: "Abrir", a: function () { launcher.launchApp(app) } }]
        var acc = menuOpciones.acciones || []
        for (var i = 0; i < acc.length; ++i) {
            (function (id, t) {
                o.push({ t: t, a: function () {
                    launcherBackend.lanzarAccion(app.desktop, id, launcher.iconFor(app.icon))
                    shellBackend.closeLauncher()
                } })
            })(acc[i].id, acc[i].t)
        }
        o.push({ sep: true })
        if (app.desktop) {
            o.push({ t: "Enviar al escritorio", a: function () { launcher.avisar(launcherBackend.enviarAlEscritorio(app.desktop)) } })
            o.push({ t: "Propiedades", a: function () {
                launcher.propsLista = launcherBackend.propiedadesApp(app.desktop)
                launcher.propsVisible = true
            } })
            o.push({ sep: true })
        }
        o.push({ t: "Desinstalar", peligro: true, off: !menuOpciones.desinstalable, nota: menuOpciones.motivo || "",
                 a: function () { launcher.appQuitar = app; launcher.confirmarQuitar = true } })
        return o
    }

    Connections {
        target: launcherBackend
        function onDesinstalacionTerminada(nombre, ok, mensaje) {
            if (mensaje !== "Cancelado") shellBackend.notify(ok ? "Desinstalado" : "No se ha desinstalado", mensaje)
        }
    }

    // ---------- Acciones ----------
    function launchApp(app) {
        if (!app) return
        // Rebota en el Dock si está allí; si no, indicador junto al puntero
        var enDock = dockModel.setAppLaunching(app.exec, app.exec, app.name, app.icon)
        launcherBackend.launch(app.exec, enDock, launcher.iconFor(app.icon))
        shellBackend.closeLauncher()
    }

    function moveSelection(delta) {
        var n = appGrid.count
        if (n <= 0) return
        if (selectedIndex < 0) { selectedIndex = 0; return }
        var t = selectedIndex + delta
        if (t < 0) return
        if (t > n - 1) {
            // Bajar desde una fila completa hacia una última fila incompleta
            if (Math.floor(selectedIndex / columns) < Math.floor((n - 1) / columns)) t = n - 1
            else return
        }
        selectedIndex = t
    }

    function elegirCategoria(id) {
        launcherBackend.categoria = id
        selectedIndex = appGrid.count > 0 ? 0 : -1
        appGrid.positionViewAtBeginning()
        searchField.forceActiveFocus()
    }

    // Tab / Mayús+Tab: siguiente / anterior categoría
    function cambiarCategoria(paso) {
        var c = launcherBackend.categorias, n = c.length
        if (n === 0) return
        var i = 0
        for (var k = 0; k < n; ++k) if (c[k].id === launcherBackend.categoria) i = k
        elegirCategoria(c[(i + paso + n) % n].id)
    }

    function resetState() {
        launcherBackend.categoria = "todas"
        searchField.text = ""
        pendingPower = ""
        selectedIndex = appGrid.count > 0 ? 0 : -1
        searchField.forceActiveFocus()
    }

    function runPower(kind) {
        pendingPower = ""
        shellBackend.closeLauncher()
        if (kind === "poweroff") shellBackend.powerOff()
        else if (kind === "reboot") shellBackend.reboot()
    }

    function cancelPower() { pendingPower = "" }

    onSelectedIndexChanged: {
        if (selectedIndex >= 0) appGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
    }

    onPendingPowerChanged: {
        if (pendingPower !== "") Qt.callLater(function() { confirmCard.forceActiveFocus() })
        else searchField.forceActiveFocus()
    }

    onOpenChanged: {
        if (!open) cerrarMenus()
        if (open) {
            resetState()
            Qt.callLater(updateOrigin)
        }
    }

    Component.onCompleted: {
        resetState()
        Qt.callLater(updateOrigin)
    }

    // Entrada / salida suave, guiada por el estado real del lanzador
    opacity: open ? 1.0 : 0.0
    scale: open ? 1.0 : 0.94
    visible: open || opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on scale   { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    // ---------- Componentes reutilizables ----------

    // Celda de aplicación (rejilla y recientes)
    component AppCell: Item {
        id: cell
        property string appName: ""
        property string iconSource: ""
        property bool selected: false
        property color textColor: "white"
        property color hoverColor: Qt.rgba(1, 1, 1, 0.12)
        property color ringColor: Qt.rgba(1, 1, 1, 0.3)
        signal clicked()
        signal entered()
        signal exited()
        signal menuPedido(real x, real y)   // clic derecho (en coordenadas de la celda)

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: 14
            color: cell.selected ? cell.hoverColor : "transparent"
            border.color: cell.selected ? cell.ringColor : "transparent"
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        Column {
            anchors.centerIn: parent
            spacing: 7

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 54
                height: 54
                scale: cell.selected ? 1.08 : 1.0
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                Image {
                    anchors.fill: parent
                    sourceSize: Qt.size(80, 80)
                    asynchronous: true
                    cache: true
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    source: cell.iconSource
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: cell.appName
                color: cell.textColor
                font.pixelSize: 11
                font.weight: Font.Medium
                width: cell.width - 16
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: cell.entered()
            onExited: cell.exited()
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) cell.menuPedido(mouse.x, mouse.y)
                else cell.clicked()
            }
            onPressAndHold: (mouse) => cell.menuPedido(mouse.x, mouse.y)
        }
    }

    // Botón de energía con icono dibujado (sin emojis)
    component PowerButton: Rectangle {
        id: pb
        property string kind: "power"          // "lock" | "sleep" | "reboot" | "power"
        property color iconColor: "white"
        property color baseColor: Qt.rgba(1, 1, 1, 0.08)
        property color hoverColor: Qt.rgba(1, 1, 1, 0.18)
        signal clicked()

        width: 34
        height: 28
        radius: 8
        color: pbMouse.containsMouse ? hoverColor : baseColor
        Behavior on color { ColorAnimation { duration: 100 } }

        onIconColorChanged: pbCanvas.requestPaint()

        Canvas {
            id: pbCanvas
            anchors.centerIn: parent
            width: 16
            height: 16
            onPaint: {
                var c = getContext("2d")
                c.reset()
                c.strokeStyle = pb.iconColor
                c.fillStyle = pb.iconColor
                c.lineWidth = 1.6
                c.lineCap = "round"
                c.lineJoin = "round"
                if (pb.kind === "power") {
                    c.beginPath()
                    c.arc(8, 9, 5.5, -Math.PI / 2 + 0.65, -Math.PI / 2 - 0.65 + 2 * Math.PI)
                    c.stroke()
                    c.beginPath()
                    c.moveTo(8, 2)
                    c.lineTo(8, 8)
                    c.stroke()
                } else if (pb.kind === "lock") {
                    // Candado cerrado estilo Apple
                    c.beginPath()
                    c.arc(8, 6.2, 3.2, Math.PI, 0, false)
                    c.stroke()
                    c.beginPath()
                    c.rect(3.5, 6.5, 9, 6.8)
                    c.fill()
                    c.fillStyle = pbMouse.containsMouse ? pb.hoverColor : pb.baseColor
                    c.beginPath()
                    c.arc(8, 9.5, 1.2, 0, 2 * Math.PI)
                    c.fill()
                } else if (pb.kind === "reboot") {
                    c.beginPath()
                    c.arc(8, 8, 5.5, -0.4, 4.5)
                    c.stroke()
                    c.beginPath()
                    c.moveTo(4.7, 4.9)
                    c.lineTo(6.8, 2.6)
                    c.lineTo(3.9, 1.4)
                    c.stroke()
                } else {
                    c.beginPath()
                    c.arc(8, 8, 6, 0, 2 * Math.PI)
                    c.fill()
                    c.globalCompositeOperation = "destination-out"
                    c.beginPath()
                    c.arc(11.5, 5.5, 5, 0, 2 * Math.PI)
                    c.fill()
                }
            }
        }

        MouseArea {
            id: pbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pb.clicked()
        }
    }

    // Chip de atajo de teclado
    component KeyChip: Rectangle {
        property string label: ""
        property color chipColor: "white"
        height: 18
        width: chipText.implicitWidth + 12
        radius: 5
        color: "transparent"
        border.color: Qt.rgba(chipColor.r, chipColor.g, chipColor.b, 0.35)
        border.width: 1
        Text {
            id: chipText
            anchors.centerIn: parent
            text: parent.label
            color: parent.chipColor
            font.pixelSize: 10
        }
    }

    // ---------- FONDO DE VIDRIO ----------
    GlassPanel {
        anchors.fill: parent
        radius: launcher.panelRadius
        dark: titanTheme.isDark
        tint: launcher.hasGlass
              ? (titanTheme.isDark ? Qt.rgba(0.09, 0.10, 0.14, 0.50) : Qt.rgba(0.97, 0.97, 0.99, 0.50))
              : (titanTheme.isDark ? Qt.rgba(0.12, 0.12, 0.14, 0.88) : Qt.rgba(0.96, 0.96, 0.97, 0.88))
        wallpaper: launcher.wallpaperPath
        originX: launcher.glassOriginX
        originY: launcher.glassOriginY
        sceneWidth: (typeof Screen !== "undefined" && Screen.width > 0) ? Screen.width : 1920
        sceneHeight: (typeof Screen !== "undefined" && Screen.height > 0) ? Screen.height : 1080
        borderColor: titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.45)
        highlightColor: titanTheme.specularGlow
    }

    // ---------- 1. BUSCADOR ----------
    Rectangle {
        id: searchContainer
        anchors.top: parent.top
        anchors.topMargin: 20
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        height: 46
        radius: 15
        color: titanTheme.contentCardBg
        border.color: searchField.activeFocus ? titanTheme.accent : titanTheme.contentCardBorder
        border.width: searchField.activeFocus ? 1.5 : 1
        Behavior on border.color { ColorAnimation { duration: 160 } }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            spacing: 10

            Item {
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter

                Canvas {
                    id: searchIconCanvas
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = searchField.activeFocus ? titanTheme.accent : titanTheme.contentTextSecondary
                        ctx.lineWidth = 2.0
                        ctx.lineCap = "round"
                        ctx.beginPath()
                        ctx.arc(8, 8, 5.5, 0, Math.PI * 2)
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.moveTo(12.5, 12.5)
                        ctx.lineTo(17, 17)
                        ctx.stroke()
                    }
                    Connections {
                        target: searchField
                        function onActiveFocusChanged() { searchIconCanvas.requestPaint() }
                    }
                    Connections {
                        target: titanTheme
                        function onIsDarkChanged() { searchIconCanvas.requestPaint() }
                    }
                }
            }

            TextField {
                id: searchField
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 64
                placeholderText: qsTr("Buscar aplicaciones…")
                font.pixelSize: 13
                focus: true
                background: null
                color: titanTheme.contentTextPrimary
                placeholderTextColor: titanTheme.contentTextSecondary

                onTextChanged: {
                    launcherBackend.search(text)
                    launcher.selectedIndex = appGrid.count > 0 ? 0 : -1
                }

                Keys.onEscapePressed: {
                    if (launcher.menuApp !== null || launcher.propsVisible || launcher.confirmarQuitar) launcher.cerrarMenus()
                    else if (text.length > 0) text = ""
                    else shellBackend.closeLauncher()
                }

                Keys.onPressed: (event) => {
                    if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && text.length === 0) {
                        launcher.cambiarCategoria(event.key === Qt.Key_Backtab ? -1 : 1); event.accepted = true
                    } else if (event.key === Qt.Key_Down) {
                        launcher.moveSelection(launcher.columns); event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                        launcher.moveSelection(-launcher.columns); event.accepted = true
                    } else if (event.key === Qt.Key_Right && cursorPosition === text.length) {
                        launcher.moveSelection(1); event.accepted = true
                    } else if (event.key === Qt.Key_Left && cursorPosition === 0) {
                        launcher.moveSelection(-1); event.accepted = true
                    }
                }

                Keys.onReturnPressed: launcher.launchApp(launcherBackend.apps[launcher.selectedIndex])
                Keys.onEnterPressed: launcher.launchApp(launcherBackend.apps[launcher.selectedIndex])
            }

            // Botón limpiar (cruz dibujada)
            Item {
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                visible: searchField.text.length > 0

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: clearMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.18) : Qt.rgba(0, 0, 0, 0.10)
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                Rectangle { anchors.centerIn: parent; width: 9; height: 1.5; radius: 1; rotation: 45;  color: titanTheme.contentTextPrimary }
                Rectangle { anchors.centerIn: parent; width: 9; height: 1.5; radius: 1; rotation: -45; color: titanTheme.contentTextPrimary }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { searchField.text = ""; searchField.forceActiveFocus() }
                }
            }
        }
    }

    // ---------- 2. RECIENTES (solo sin búsqueda y si el backend las ofrece) ----------
    Item {
        id: recentsBlock
        anchors.top: searchContainer.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        height: launcher.showRecents ? 118 : 0
        visible: launcher.showRecents
        clip: true

        Text {
            id: recentsLabel
            x: 4
            anchors.top: parent.top
            anchors.topMargin: 2
            text: qsTr("Recientes")
            color: titanTheme.contentTextSecondary
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        Row {
            anchors.top: recentsLabel.bottom
            anchors.topMargin: 4
            Repeater {
                model: launcher.recents.length > launcher.columns ? launcher.columns : launcher.recents.length
                delegate: AppCell {
                    width: appGrid.cellWidth
                    height: 92
                    appName: launcher.recents[index].name
                    iconSource: launcher.iconFor(launcher.recents[index].icon)
                    textColor: titanTheme.contentTextPrimary
                    hoverColor: titanTheme.itemHover
                    ringColor: titanTheme.glassBorder
                    selected: recentMouseHover
                    property bool recentMouseHover: false
                    onEntered: recentMouseHover = true
                    onExited: recentMouseHover = false
                    onClicked: launcher.launchApp(launcher.recents[index])
                    onMenuPedido: (x, y) => launcher.abrirMenu(launcher.recents[index], this, x, y)
                }
            }
        }
    }

    // ---------- 3. ENCABEZADO DE SECCIÓN ----------
    Item {
        id: headerRow
        anchors.top: recentsBlock.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        height: 28

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            visible: searchField.text.length > 0
            text: qsTr("Resultados de búsqueda")
            color: titanTheme.contentTextSecondary
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        // Categorías (Todas, Productividad, Internet...). "Todas" deja fuera
        // las herramientas del sistema; están en "Sistema" y al buscar.
        ListView {
            id: filaCategorias
            anchors.fill: parent
            visible: searchField.text.length === 0
            orientation: ListView.Horizontal
            spacing: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: launcherBackend.categorias
            currentIndex: {
                for (var i = 0; i < count; ++i)
                    if (launcherBackend.categorias[i].id === launcherBackend.categoria) return i
                return 0
            }
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool elegida: launcherBackend.categoria === modelData.id
                height: 26
                width: textoCategoria.implicitWidth + 24
                radius: 13
                color: elegida ? titanTheme.accent
                       : (ratonCategoria.containsMouse ? titanTheme.itemHover : "transparent")
                border.width: elegida ? 0 : 1
                border.color: titanTheme.contentCardBorder
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    id: textoCategoria
                    anchors.centerIn: parent
                    text: modelData.nombre
                    color: elegida ? "#ffffff" : titanTheme.contentTextPrimary
                    font.pixelSize: 12
                    font.weight: elegida ? Font.DemiBold : Font.Medium
                }
                MouseArea {
                    id: ratonCategoria
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: launcher.elegirCategoria(modelData.id)
                }
            }
        }
    }

    // ---------- 4. REJILLA ----------
    GridView {
        id: appGrid
        anchors.top: headerRow.bottom
        anchors.topMargin: 6
        anchors.bottom: footer.top
        anchors.bottomMargin: 4
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        clip: true

        cellWidth: Math.floor(width / launcher.columns)
        cellHeight: 100
        model: launcherBackend.apps
        cacheBuffer: 500
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        onCountChanged: {
            if (count === 0) launcher.selectedIndex = -1
            else if (launcher.selectedIndex < 0) launcher.selectedIndex = 0
            else if (launcher.selectedIndex > count - 1) launcher.selectedIndex = count - 1
        }

        ScrollBar.vertical: ScrollBar {
            id: vScrollBar
            active: appGrid.moving || appGrid.flicking || hovered
            width: 6
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: vScrollBar.pressed ? titanTheme.accent
                       : (vScrollBar.hovered ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(1, 1, 1, 0.28))
                Behavior on color { ColorAnimation { duration: 140 } }
            }
        }

        delegate: AppCell {
            width: appGrid.cellWidth
            height: appGrid.cellHeight
            appName: modelData ? modelData.name : ""
            iconSource: launcher.iconFor(modelData ? modelData.icon : "")
            selected: launcher.selectedIndex === index
            textColor: titanTheme.contentTextPrimary
            hoverColor: titanTheme.itemHover
            ringColor: titanTheme.glassBorder
            onEntered: launcher.selectedIndex = index
            onClicked: launcher.launchApp(modelData)
            onMenuPedido: (x, y) => launcher.abrirMenu(modelData, this, x, y)
        }
    }

    // Estado vacío
    Column {
        anchors.centerIn: appGrid
        spacing: 6
        visible: appGrid.count === 0 && searchField.text.length > 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Sin resultados para «%1»").arg(searchField.text)
            color: titanTheme.contentTextPrimary
            font.pixelSize: 14
            font.weight: Font.Medium
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Revisa la ortografía o prueba con otro nombre.")
            color: titanTheme.contentTextSecondary
            font.pixelSize: 12
        }
    }

    // ---------- 5. BARRA INFERIOR: atajos + energía ----------
    Item {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 46

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            height: 1
            color: titanTheme.glassBorder
            opacity: 0.6
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 26
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            Row {
                spacing: 6
                KeyChip { label: "←↑↓→"; chipColor: titanTheme.contentTextSecondary; anchors.verticalCenter: parent.verticalCenter }
                Text { text: qsTr("navegar"); color: titanTheme.contentTextSecondary; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
            }
            Row {
                spacing: 6
                KeyChip { label: "↵"; chipColor: titanTheme.contentTextSecondary; anchors.verticalCenter: parent.verticalCenter }
                Text { text: qsTr("abrir"); color: titanTheme.contentTextSecondary; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
            }
            Row {
                spacing: 6
                KeyChip { label: "esc"; chipColor: titanTheme.contentTextSecondary; anchors.verticalCenter: parent.verticalCenter }
                Text { text: qsTr("cerrar"); color: titanTheme.contentTextSecondary; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            PowerButton {
                kind: "lock"
                iconColor: titanTheme.contentTextPrimary
                baseColor: Qt.rgba(1, 1, 1, titanTheme.isDark ? 0.08 : 0.14)
                hoverColor: Qt.rgba(1, 1, 1, titanTheme.isDark ? 0.18 : 0.28)
                onClicked: { shellBackend.closeLauncher(); shellBackend.lockScreen() }
            }
            PowerButton {
                kind: "sleep"
                iconColor: titanTheme.contentTextPrimary
                baseColor: Qt.rgba(1, 1, 1, titanTheme.isDark ? 0.08 : 0.14)
                hoverColor: Qt.rgba(1, 1, 1, titanTheme.isDark ? 0.18 : 0.28)
                onClicked: { shellBackend.closeLauncher(); shellBackend.suspend() }
            }
            PowerButton {
                kind: "reboot"
                iconColor: titanTheme.contentTextPrimary
                baseColor: Qt.rgba(1, 1, 1, titanTheme.isDark ? 0.08 : 0.14)
                hoverColor: Qt.rgba(1, 1, 1, titanTheme.isDark ? 0.18 : 0.28)
                onClicked: launcher.pendingPower = "reboot"
            }
            PowerButton {
                kind: "power"
                iconColor: "#ff6b63"
                baseColor: Qt.rgba(1, 0.27, 0.23, 0.18)
                hoverColor: Qt.rgba(1, 0.27, 0.23, 0.34)
                onClicked: launcher.pendingPower = "poweroff"
            }
        }
    }

    // ---------- 6. CONFIRMACIÓN DE REINICIO / APAGADO ----------
    Rectangle {
        id: confirmOverlay
        anchors.fill: parent
        radius: launcher.panelRadius
        color: Qt.rgba(0, 0, 0, 0.42)
        z: 200
        opacity: launcher.pendingPower !== "" ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; onClicked: launcher.cancelPower() }

        Rectangle {
            id: confirmCard
            width: 300
            height: confirmCol.height + 36
            anchors.centerIn: parent
            radius: 16
            color: titanTheme.isDark ? Qt.rgba(0.16, 0.17, 0.22, 0.97) : Qt.rgba(0.98, 0.98, 1.0, 0.97)
            border.color: titanTheme.glassBorder
            border.width: 1
            focus: confirmOverlay.visible
            scale: launcher.pendingPower !== "" ? 1.0 : 0.94
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Keys.onEscapePressed: launcher.cancelPower()
            Keys.onReturnPressed: launcher.runPower(launcher.pendingPower)
            Keys.onEnterPressed: launcher.runPower(launcher.pendingPower)

            MouseArea { anchors.fill: parent }

            Column {
                id: confirmCol
                anchors.top: parent.top
                anchors.topMargin: 18
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 6

                Text {
                    width: parent.width
                    text: launcher.pendingPower === "poweroff" ? qsTr("¿Apagar el equipo?") : qsTr("¿Reiniciar el equipo?")
                    color: titanTheme.contentTextPrimary
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width
                    text: qsTr("Se cerrarán todas las aplicaciones abiertas.")
                    color: titanTheme.contentTextSecondary
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Item { width: 1; height: 8 }

                Row {
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 32
                        radius: 9
                        color: cancelMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.10)
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Cancelar")
                            color: titanTheme.contentTextPrimary
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: launcher.cancelPower()
                        }
                    }

                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 32
                        radius: 9
                        color: okMouse.containsMouse ? "#ff6259" : "#ff453a"
                        Text {
                            anchors.centerIn: parent
                            text: launcher.pendingPower === "poweroff" ? qsTr("Apagar") : qsTr("Reiniciar")
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            id: okMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: launcher.runPower(launcher.pendingPower)
                        }
                    }
                }
            }
        }
    }
    // ================= Menú del clic derecho, Propiedades y Desinstalar =================
    Item {
        id: capaMenu
        anchors.fill: parent
        z: 300
        visible: launcher.menuApp !== null || launcher.propsVisible || launcher.confirmarQuitar

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: launcher.cerrarMenus()
            onWheel: (w) => { w.accepted = true }
        }

        // Menú opaco junto al puntero
        Rectangle {
            id: menuCaja
            visible: launcher.menuApp !== null
            width: 230
            height: menuCol.implicitHeight + 12
            x: launcher.posMenu(launcher.menuX, width, launcher.width)
            y: launcher.posMenu(launcher.menuY, height, launcher.height)
            radius: 9
            color: titanTheme.isDark ? "#161618" : "#ffffff"
            border.color: titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.14)
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
            Column {
                id: menuCol
                x: 6; y: 6
                width: parent.width - 12
                Repeater {
                    model: launcher.menuApp !== null ? launcher.opcionesMenu() : []
                    delegate: Item {
                        id: fila
                        required property var modelData
                        width: menuCol.width
                        height: modelData.sep ? 9 : (modelData.off && modelData.nota ? 40 : 28)
                        Rectangle {
                            visible: !!fila.modelData.sep
                            anchors.centerIn: parent
                            width: parent.width - 16; height: 1
                            color: titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)
                        }
                        Rectangle {
                            visible: !fila.modelData.sep
                            anchors.fill: parent
                            radius: 5
                            readonly property bool activa: zonaFila.containsMouse && !fila.modelData.off
                            color: activa ? (fila.modelData.peligro ? "#e5372c" : titanTheme.accent) : "transparent"
                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    width: parent.width
                                    text: fila.modelData.t || ""
                                    elide: Text.ElideRight
                                    font.pixelSize: 12
                                    color: parent.parent.activa ? "#ffffff"
                                         : fila.modelData.off ? titanTheme.contentTextSecondary
                                         : (fila.modelData.peligro ? "#e5372c" : titanTheme.contentTextPrimary)
                                }
                                Text {
                                    visible: !!fila.modelData.off && !!fila.modelData.nota
                                    text: fila.modelData.nota || ""
                                    font.pixelSize: 10
                                    color: titanTheme.contentTextSecondary
                                }
                            }
                            MouseArea {
                                id: zonaFila
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !fila.modelData.sep && !fila.modelData.off
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var accion = fila.modelData.a
                                    launcher.menuApp = null
                                    accion()
                                }
                            }
                        }
                    }
                }
            }
        }

        // Propiedades
        Rectangle {
            visible: launcher.propsVisible
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 460)
            height: propsCol.implicitHeight + 36
            radius: 14
            color: titanTheme.isDark ? "#161618" : "#ffffff"
            border.color: titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.14)
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
            Column {
                id: propsCol
                x: 20; y: 18
                width: parent.width - 40
                spacing: 8
                Text { text: "Propiedades"; font.pixelSize: 15; font.bold: true; color: titanTheme.contentTextPrimary }
                Repeater {
                    model: launcher.propsLista
                    delegate: Row {
                        required property var modelData
                        width: propsCol.width
                        spacing: 10
                        Text { width: 92; text: modelData.k; font.pixelSize: 12; color: titanTheme.contentTextSecondary; horizontalAlignment: Text.AlignRight }
                        Text { width: parent.width - 102; text: modelData.v; font.pixelSize: 12; color: titanTheme.contentTextPrimary; wrapMode: Text.WrapAnywhere }
                    }
                }
                Item { width: 1; height: 4 }
                Rectangle {
                    anchors.right: parent.right
                    width: 90; height: 30; radius: 8
                    color: titanTheme.accent
                    Text { anchors.centerIn: parent; text: "Cerrar"; color: "#ffffff"; font.pixelSize: 12; font.bold: true }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: launcher.propsVisible = false }
                }
            }
        }

        // Confirmar desinstalación (luego polkit pide la contraseña)
        Rectangle {
            visible: launcher.confirmarQuitar
            anchors.centerIn: parent
            width: 340
            height: quitarCol.implicitHeight + 40
            radius: 14
            color: titanTheme.isDark ? "#161618" : "#ffffff"
            border.color: titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.14)
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
            Column {
                id: quitarCol
                x: 20; y: 20
                width: parent.width - 40
                spacing: 12
                Text {
                    width: parent.width
                    text: "¿Desinstalar " + (launcher.appQuitar ? launcher.appQuitar.name : "") + "?"
                    font.pixelSize: 15; font.bold: true; wrapMode: Text.Wrap
                    color: titanTheme.contentTextPrimary
                }
                Text {
                    width: parent.width
                    text: "Se quitará del equipo para todas las cuentas. Por tu seguridad, se pedirá la contraseña de administrador."
                    font.pixelSize: 12; wrapMode: Text.Wrap
                    color: titanTheme.contentTextSecondary
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Rectangle {
                        width: 90; height: 30; radius: 8
                        color: titanTheme.isDark ? "#2a2a2e" : "#ececf0"
                        Text { anchors.centerIn: parent; text: "Cancelar"; color: titanTheme.contentTextPrimary; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: launcher.confirmarQuitar = false }
                    }
                    Rectangle {
                        width: 100; height: 30; radius: 8
                        color: "#e5372c"
                        Text { anchors.centerIn: parent; text: "Desinstalar"; color: "#ffffff"; font.pixelSize: 12; font.bold: true }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var app = launcher.appQuitar
                                launcher.confirmarQuitar = false
                                // Se cierra el menú de inicio: la ventana de la
                                // contraseña no debe quedar tapada
                                shellBackend.closeLauncher()
                                launcherBackend.desinstalar(app.desktop, app.name)
                            }
                        }
                    }
                }
            }
        }
    }

    // Aviso breve (acceso directo creado, desinstalado...)
    Rectangle {
        z: 310
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        visible: launcher.aviso !== "" && avisoTimer.running
        width: avisoTexto.implicitWidth + 28
        height: 30
        radius: 15
        color: titanTheme.isDark ? "#161618" : "#ffffff"
        border.color: titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.14)
        Text { id: avisoTexto; anchors.centerIn: parent; text: launcher.aviso; font.pixelSize: 12; color: titanTheme.contentTextPrimary }
    }
    Timer { id: avisoTimer; interval: 3000 }
}
