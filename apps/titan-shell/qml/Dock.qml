import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Effects   // MultiEffect (Qt 6.5+), solo para recortar esquinas

Item {
    id: dockContainer
    anchors.fill: parent

    // ---------- Estado ----------
    property int hoveredIndex: -1
    property int draggedIndex: -1
    property int targetDropIndex: -1
    // ---------- Preferencias (Ajustes > Escritorio y Dock) ----------
    readonly property string posicion: { prefs.version; var p = prefs.s("Dock/posicion"); return (p === "izquierda" || p === "derecha") ? p : "abajo" }
    readonly property bool vertical: posicion !== "abajo"
    readonly property int iconSize: { prefs.version; return Math.max(28, Math.min(64, prefs.i("Dock/tamano"))) }
    readonly property int slot: iconSize + 8          // casilla de cada icono
    readonly property int paso: slot + 4              // casilla + separacion
    readonly property bool ampliacion: { prefs.version; return prefs.b("Dock/ampliacion") && !prefs.b("Rendimiento/ligero") }
    readonly property bool ocultarAuto: { prefs.version; return prefs.b("Dock/ocultarAuto") }

    // "isMaximized" = el Dock se esconde y sale al acercar el raton al borde:
    // con ventanas maximizadas o si se pide ocultarlo siempre.
    readonly property bool isMaximized: ocultarAuto || windowTracker.hasMaximizedWindow || windowTracker.hasFullscreenWindow
    property bool dockRevealed: false
    readonly property bool shouldShowDock: !shellBackend.launcherVisible && (!isMaximized || dockRevealed)

    // ---------- Vidrio ----------
    // Refleja el fondo de pantalla ACTUAL (ver GlassPanel.qml): se decodifica en minúscula y se
    // amplía, así que no hace falta pre-desenfocar nada ni usar blur en vivo.
    readonly property string wallpaperPath: shellBackend.currentWallpaper ? shellBackend.currentWallpaper : ""
    readonly property bool hasGlass: wallpaperPath !== ""
    readonly property real dockRadius: 22
    readonly property int maskPad: 8

    // Tinte del cristal: translúcido si hay wallpaper borroso, más opaco si no lo hay
    readonly property color dockTint: hasGlass
        ? (theme.isDark ? Qt.rgba(0.10, 0.11, 0.16, 0.32) : Qt.rgba(1, 1, 1, 0.30))
        : (theme.isDark ? Qt.rgba(0.12, 0.13, 0.18, 0.82) : Qt.rgba(0.95, 0.95, 0.98, 0.80))
    readonly property color menuTint: hasGlass
        ? (theme.isDark ? Qt.rgba(0.10, 0.12, 0.18, 0.55) : Qt.rgba(0.97, 0.97, 1.0, 0.55))
        : (theme.isDark ? Qt.rgba(0.12, 0.14, 0.20, 0.95) : Qt.rgba(0.96, 0.97, 1.0, 0.95))

    TitanTheme { id: theme }   // una sola instancia para dock y menú

    // ---------- Menú contextual: estado ----------
    property string ctxAppId: ""
    property string ctxAppName: ""
    property string ctxAppIcon: ""
    property bool ctxIsPinned: false
    property bool ctxIsRunning: false
    property real ctxMenuX: 0
    property real ctxMenuY: 0
    property bool ctxMenuVisible: false
    property var ctxWindows: []

    // ---------- Máscara de entrada (limitada a ~60 fps) ----------
    function refreshMask() {
        if (!dockContainer.Window || !dockContainer.Window.window) return
        var win = dockContainer.Window.window
        var gx = dockBg.x - maskPad
        var gy = dockBg.y - maskPad
        var gw = dockBg.width + maskPad * 2
        var gh = dockBg.height + maskPad * 2
        shellBackend.updateDockMask(win, gx, gy, gw, gh, isMaximized, dockRevealed, ctxMenuVisible, posicion)
    }

    Timer {
        id: maskTimer
        interval: 24
        repeat: false
        onTriggered: dockContainer.refreshMask()
    }

    onCtxMenuVisibleChanged: refreshMask()
    onPosicionChanged: { ctxMenuVisible = false; maskTimer.restart() }
    onWidthChanged: maskTimer.restart()
    onHeightChanged: maskTimer.restart()
    onDockRevealedChanged: refreshMask()

    onIsMaximizedChanged: {
        if (!isMaximized) {
            dockRevealed = true
            hideDelayTimer.stop()
        } else {
            dockRevealed = false
        }
        refreshMask()
    }

    Component.onCompleted: {
        dockRevealed = !isMaximized
        Qt.callLater(refreshMask)
    }

    onHoveredIndexChanged: {
        if (hoveredIndex >= 0) {
            hideDelayTimer.stop()
            dockRevealed = true
        } else if (isMaximized && !dockHoverArea.containsMouse && !bottomTrigger.containsMouse) {
            hideDelayTimer.restart()
        }
    }

    // ---------- Componentes reutilizables ----------

    // Superficie de vidrio: recorte del wallpaper desenfocado + tinte + borde fino.
    // Fila del menú contextual
    component MenuRow: Rectangle {
        id: row
        property string label: ""
        property bool danger: false
        property bool showDot: false
        property bool isDark: true
        property color textColor: "white"
        signal activated()

        width: parent ? parent.width : 0
        height: 26
        radius: 6
        color: rowMouse.containsMouse
               ? (danger ? Qt.rgba(1, 0.2, 0.2, 0.22)
                         : (isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)))
               : "transparent"

        Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            Rectangle {
                visible: row.showDot
                width: 5; height: 5; radius: 2.5
                color: theme.accent
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: row.label
                color: row.danger && rowMouse.containsMouse ? "#ff4d4d" : row.textColor
                font.pixelSize: 11
                elide: Text.ElideMiddle
                width: parent.width - (row.showDot ? 11 : 0)
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.activated()
        }
    }

    // ---------- Zonas de activación (auto-ocultar) ----------
    MouseArea {
        id: bottomTrigger
        // Franja de 3 px pegada al borde donde vive el Dock
        x: dockContainer.posicion === "derecha" ? parent.width - 3 : 0
        y: dockContainer.vertical ? 0 : parent.height - 3
        width: dockContainer.vertical ? 3 : parent.width
        height: dockContainer.vertical ? parent.height : 3
        hoverEnabled: true
        enabled: dockContainer.isMaximized
        z: 10
        onEntered: {
            hideDelayTimer.stop()
            dockContainer.dockRevealed = true
        }
    }

    MouseArea {
        id: dockHoverArea
        x: dockBg.x - 12
        y: dockBg.y - 12
        width: dockBg.width + 24
        height: dockBg.height + 24
        hoverEnabled: true
        enabled: dockContainer.shouldShowDock
        z: 5
        onEntered: {
            hideDelayTimer.stop()
            dockContainer.dockRevealed = true
        }
        onExited: {
            if (dockContainer.isMaximized) hideDelayTimer.restart()
        }
    }

    Timer {
        id: hideDelayTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (dockContainer.isMaximized
                && !dockHoverArea.containsMouse
                && !bottomTrigger.containsMouse
                && dockContainer.hoveredIndex === -1) {
                dockContainer.dockRevealed = false
            }
        }
    }

    // ---------- DOCK ----------
    Item {
        id: dockBg
        width: dockContainer.vertical ? dockContainer.slot + 14 : dockRow.width + 24
        height: dockContainer.vertical ? dockRow.height + 24 : dockContainer.slot + 14
        z: 20
        x: dockContainer.posicion === "izquierda" ? 8
           : dockContainer.posicion === "derecha" ? parent.width - width - 8
           : (parent.width - width) / 2
        y: dockContainer.vertical ? (parent.height - height) / 2 : parent.height - height - 8

        onWidthChanged: maskTimer.restart()
        onHeightChanged: maskTimer.restart()
        onXChanged: maskTimer.restart()
        onYChanged: maskTimer.restart()

        // Se deja de dibujar por completo cuando está oculto (costo cero)
        opacity: dockContainer.shouldShowDock ? 1.0 : 0.0
        visible: opacity > 0.01

        Behavior on width {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running) dockContainer.refreshMask()
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running) dockContainer.refreshMask()
            }
        }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // Al esconderse se desliza hacia su borde
        transform: Translate {
            x: dockContainer.shouldShowDock ? 0 : (dockContainer.posicion === "izquierda" ? -85 : dockContainer.posicion === "derecha" ? 85 : 0)
            y: dockContainer.shouldShowDock || dockContainer.vertical ? 0 : 85
            Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        }

        // Sombra barata (dos capas translúcidas, sin efectos de GPU)
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            anchors.topMargin: 0
            anchors.bottomMargin: -4
            radius: dockContainer.dockRadius + 2
            color: Qt.rgba(0, 0, 0, theme.isDark ? 0.16 : 0.07)
            z: -2
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            anchors.bottomMargin: -2
            radius: dockContainer.dockRadius + 1
            color: Qt.rgba(0, 0, 0, theme.isDark ? 0.28 : 0.12)
            z: -1
        }

        GlassPanel {
            anchors.fill: parent
            radius: dockContainer.dockRadius
            tint: dockContainer.dockTint
            wallpaper: dockContainer.wallpaperPath
            originX: dockContainer.pantallaX(dockBg.x)
            originY: (typeof Screen !== "undefined" && Screen.height > 0) ? (Screen.height - dockContainer.height + dockBg.y) : dockBg.y
            sceneWidth: (typeof Screen !== "undefined" && Screen.width > 0) ? Screen.width : dockContainer.width
            sceneHeight: (typeof Screen !== "undefined" && Screen.height > 0) ? Screen.height : 1080
            borderColor: theme.glassBorder
            highlightColor: theme.specularGlow
        }

        // Fila (abajo) o columna (a los lados)
        Grid {
            id: dockRow
            anchors.centerIn: parent
            spacing: 4
            flow: dockContainer.vertical ? Grid.TopToBottom : Grid.LeftToRight
            columns: dockContainer.vertical ? 1 : Math.max(1, dockRepeater.count)
            rows: dockContainer.vertical ? Math.max(1, dockRepeater.count) : 1

            Repeater {
                id: dockRepeater
                model: dockModel
                delegate: DockItem {
                    itemIndex: index
                    appId: model.appId
                    appName: model.name
                    appIcon: model.icon
                    appExec: model.exec
                    isRunning: model.running
                    hasWindow: model.hasWindow
                    active: model.active
                    isLaunching: model.launching
                    isPinned: model.isPinned
                    showSeparator: model.showSeparator
                }
            }
        }
    }

    // X en pantalla de algo del Dock (la ventana del Dock a la derecha no empieza en 0)
    function pantallaX(xLocal) {
        if (posicion === "derecha" && typeof Screen !== "undefined" && Screen.width > 0)
            return Screen.width - dockContainer.width + xLocal
        return xLocal
    }

    // ---------- Menú contextual ----------
    function openContextMenu(appId, appName, appIcon, isPinned, isRunning, clickX, clickY) {
        ctxAppId = appId
        ctxAppName = appName
        ctxAppIcon = appIcon
        ctxIsPinned = isPinned
        ctxIsRunning = isRunning
        ctxWindows = dockModel.getWindowsForApp(appId)

        var targetX = clickX - contextMenu.width / 2
        if (targetX < 12) targetX = 12
        if (targetX + contextMenu.width > dockContainer.width - 12)
            targetX = dockContainer.width - contextMenu.width - 12
        ctxMenuX = targetX

        var targetY = clickY - contextMenu.height / 2
        if (targetY < 12) targetY = 12
        if (targetY + contextMenu.height > dockContainer.height - 12)
            targetY = dockContainer.height - contextMenu.height - 12
        ctxMenuY = targetY

        ctxMenuVisible = true
        contextMenu.forceActiveFocus()
    }

    // Capa que cierra el menú al hacer clic fuera
    MouseArea {
        anchors.fill: parent
        enabled: dockContainer.ctxMenuVisible
        z: 9000
        onClicked: dockContainer.ctxMenuVisible = false
    }

    Item {
        id: contextMenu
        z: 9999
        width: 220
        height: menuCol.height + 16
        // Encima del Dock, o a su lado si el Dock esta en un lateral
        x: dockContainer.posicion === "izquierda" ? dockBg.x + dockBg.width + 10
           : dockContainer.posicion === "derecha" ? dockBg.x - width - 10
           : dockContainer.ctxMenuX
        y: dockContainer.vertical ? dockContainer.ctxMenuY : dockBg.y - height - 10

        // Aparece con fundido + escala suave
        opacity: dockContainer.ctxMenuVisible ? 1.0 : 0.0
        scale: dockContainer.ctxMenuVisible ? 1.0 : 0.94
        visible: opacity > 0.01
        transformOrigin: dockContainer.posicion === "izquierda" ? Item.Left : dockContainer.posicion === "derecha" ? Item.Right : Item.Bottom
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        focus: dockContainer.ctxMenuVisible
        Keys.onEscapePressed: dockContainer.ctxMenuVisible = false

        // Fondo opaco (como los menús de Windows y macOS): se lee mejor que el vidrio
        Rectangle { anchors.fill: parent; anchors.bottomMargin: -3; radius: 13; color: Qt.rgba(0, 0, 0, theme.isDark ? 0.35 : 0.12) }
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: theme.isDark ? "#161618" : "#ffffff"
            border.color: theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.14)
        }

        Column {
            id: menuCol
            anchors.top: parent.top
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 8
            spacing: 3

            // Encabezado: icono + nombre
            Item {
                width: parent.width
                height: 30

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 8

                    Image {
                        width: 18
                        height: 18
                        sourceSize: Qt.size(48, 48)
                        anchors.verticalCenter: parent.verticalCenter
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        source: {
                            var id = dockContainer.ctxAppId
                            if (dockContainer.ctxAppIcon && dockContainer.ctxAppIcon.indexOf("/") !== -1)
                                return dockContainer.ctxAppIcon
                            if (id.indexOf("finder") !== -1) return "qrc:/icons/finder.png"
                            if (id.indexOf("terminal") !== -1) return "qrc:/icons/terminal.png"
                            if (id.indexOf("firefox") !== -1) return "qrc:/icons/firefox.png"
                            if (id.indexOf("settings") !== -1) return "qrc:/icons/system.png"
                            return "qrc:/icons/apps-folder.png"
                        }
                    }

                    Text {
                        text: dockContainer.ctxAppName
                        color: theme.headerText
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        width: parent.width - 26
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: theme.headerBorder }

            // Ventanas abiertas
            Repeater {
                model: dockContainer.ctxWindows
                delegate: MenuRow {
                    label: modelData.title ? modelData.title : qsTr("Ventana")
                    showDot: true
                    isDark: theme.isDark
                    textColor: theme.headerText
                    onActivated: {
                        dockModel.activateWindowById(modelData.id)
                        dockContainer.ctxMenuVisible = false
                    }
                }
            }

            Rectangle {
                visible: dockContainer.ctxWindows.length > 0
                width: parent.width
                height: 1
                color: theme.headerBorder
            }

            MenuRow {
                label: dockContainer.ctxIsPinned ? qsTr("Desanclar del Dock") : qsTr("Fijar en el Dock")
                isDark: theme.isDark
                textColor: theme.headerText
                onActivated: {
                    if (dockContainer.ctxIsPinned) dockModel.unpinApp(dockContainer.ctxAppId)
                    else dockModel.pinApp(dockContainer.ctxAppId)
                    dockContainer.ctxMenuVisible = false
                }
            }

            MenuRow {
                visible: !dockContainer.ctxIsRunning
                label: qsTr("Abrir")
                isDark: theme.isDark
                textColor: theme.headerText
                onActivated: {
                    dockModel.activateApp(dockContainer.ctxAppId)
                    dockContainer.ctxMenuVisible = false
                }
            }

            MenuRow {
                visible: dockContainer.ctxIsRunning
                label: qsTr("Cerrar")
                danger: true
                isDark: theme.isDark
                textColor: theme.headerText
                onActivated: {
                    dockModel.closeApp(dockContainer.ctxAppId)
                    dockContainer.ctxMenuVisible = false
                }
            }
        }
    }
}
