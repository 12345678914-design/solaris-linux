import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: dockContainer
    anchors.fill: parent

    property int hoveredIndex: -1
    property int draggedIndex: -1
    property int targetDropIndex: -1
    readonly property bool isMaximized: windowTracker.hasMaximizedWindow || windowTracker.hasFullscreenWindow
    property bool dockRevealed: false

    function refreshMask() {
        if (!dockContainer.Window || !dockContainer.Window.window) return
        var win = dockContainer.Window.window
        var gx = dockBg.x - 8
        var gy = dockBg.y - 8
        var gw = dockBg.width + 16
        var gh = dockBg.height + 16
        shellBackend.updateDockMask(win, gx, gy, gw, gh, dockContainer.isMaximized, dockContainer.dockRevealed, dockContainer.ctxMenuVisible)
    }

    onCtxMenuVisibleChanged: {
        refreshMask()
    }

    // Si no está maximizado, el dock está siempre visible por defecto.
    // Si la ventana se maximiza, se oculta automáticamente hasta que el usuario apunte abajo.
    onIsMaximizedChanged: {
        if (!isMaximized) {
            dockRevealed = true
            hideDelayTimer.stop()
        } else {
            dockRevealed = false
        }
        refreshMask()
    }

    onDockRevealedChanged: {
        refreshMask()
    }

    Component.onCompleted: {
        dockRevealed = !isMaximized
        Qt.callLater(dockContainer.refreshMask)
    }

    onHoveredIndexChanged: {
        if (hoveredIndex >= 0) {
            hideDelayTimer.stop()
            dockRevealed = true
        } else if (isMaximized && !dockHoverArea.containsMouse && !bottomTrigger.containsMouse) {
            hideDelayTimer.restart()
        }
    }

    // 1. Hotspot en el borde inferior absoluto (solo 3 píxeles) para activar el dock en maximizado
    MouseArea {
        id: bottomTrigger
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 3
        hoverEnabled: true
        enabled: dockContainer.isMaximized
        z: 10

        onEntered: {
            hideDelayTimer.stop()
            dockContainer.dockRevealed = true
        }
    }

    // 2. Zona ajustada que envuelve estrictamente al dock
    MouseArea {
        id: dockHoverArea
        anchors.horizontalCenter: dockBg.horizontalCenter
        anchors.bottom: parent.bottom
        width: dockBg.width + 24
        height: dockBg.height + 16
        hoverEnabled: true
        enabled: dockContainer.shouldShowDock
        z: 5

        onEntered: {
            hideDelayTimer.stop()
            dockContainer.dockRevealed = true
        }

        onExited: {
            if (dockContainer.isMaximized) {
                hideDelayTimer.restart()
            }
        }
    }

    Timer {
        id: hideDelayTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (dockContainer.isMaximized) {
                if (!dockHoverArea.containsMouse && !bottomTrigger.containsMouse && dockContainer.hoveredIndex === -1) {
                    dockContainer.dockRevealed = false
                }
            }
        }
    }

    readonly property bool shouldShowDock: !shellBackend.launcherVisible && (!isMaximized || dockRevealed)

    Rectangle {
        id: dockBg
        height: 55
        width: dockRow.width + 20
        radius: 18
        clip: false
        z: 20
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        onWidthChanged: dockContainer.refreshMask()
        onXChanged: dockContainer.refreshMask()

        TitanTheme { id: titanTheme }

        // Sombra exterior suave difusa
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: 19
            color: Qt.rgba(0, 0, 0, titanTheme.isDark ? 0.35 : 0.14)
            z: -1
        }

        // Fondo borroso y translúcido (Frosted Liquid Glass estilo macOS)
        color: titanTheme.isDark ? Qt.rgba(0.12, 0.13, 0.18, 0.72) : Qt.rgba(0.95, 0.95, 0.98, 0.70)
        border.color: titanTheme.glassBorder
        border.width: 1

        // Capa de desenfoque difuso / frosted glass
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 17
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, titanTheme.isDark ? 0.14 : 0.35) }
                GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, titanTheme.isDark ? 0.04 : 0.10) }
                GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, titanTheme.isDark ? 0.08 : 0.02) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, titanTheme.isDark ? 0.22 : 0.08) }
            }
        }

        // Brillo especular superior del cristal acrílico
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 20
            height: 1
            color: titanTheme.specularGlow
            radius: 1
        }

        // Reflejo interior sutil inferior
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 24
            height: 1
            color: Qt.rgba(1, 1, 1, 0.06)
            radius: 1
        }

        Row {
            id: dockRow
            anchors.centerIn: parent
            spacing: 3

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

        Behavior on width {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        opacity: dockContainer.shouldShowDock ? 1.0 : 0.0
        transform: Translate {
            y: dockContainer.shouldShowDock ? 0 : 85
            Behavior on y {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
    }

    // Context Menu State
    property string ctxAppId: ""
    property string ctxAppName: ""
    property string ctxAppIcon: ""
    property bool ctxIsPinned: false
    property bool ctxIsRunning: false
    property real ctxMenuX: 0
    property real ctxMenuY: 0
    property bool ctxMenuVisible: false
    property var ctxWindows: []

    function openContextMenu(appId, appName, appIcon, isPinned, isRunning, clickX, clickY) {
        ctxAppId = appId
        ctxAppName = appName
        ctxAppIcon = appIcon
        ctxIsPinned = isPinned
        ctxIsRunning = isRunning
        ctxWindows = dockModel.getWindowsForApp(appId)
        
        // Calcular posición X centrada en el icono y contenida dentro de la pantalla
        var targetX = clickX - 100
        if (targetX < 12) targetX = 12
        if (targetX + 210 > dockContainer.width) targetX = dockContainer.width - 222
        ctxMenuX = targetX
        
        ctxMenuVisible = true
    }

    // Capa de cierre al hacer clic fuera del menú contextual
    MouseArea {
        anchors.fill: parent
        enabled: dockContainer.ctxMenuVisible
        z: 9000
        onClicked: dockContainer.ctxMenuVisible = false
    }

    // Menú contextual estilo macOS Liquid Glass
    Rectangle {
        id: contextMenu
        visible: dockContainer.ctxMenuVisible
        z: 9999
        width: 210
        height: menuCol.height + 16
        x: dockContainer.ctxMenuX
        anchors.bottom: dockBg.top
        anchors.bottomMargin: 10
        radius: 12
        clip: true

        TitanTheme { id: menuTheme }

        // Cristal translúcido con blur
        color: menuTheme.isDark ? Qt.rgba(0.12, 0.14, 0.20, 0.94) : Qt.rgba(0.96, 0.97, 1.0, 0.94)
        border.color: menuTheme.glassBorder
        border.width: 1

        // Brillo especular
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 16
            height: 1
            color: menuTheme.specularGlow
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

            // Encabezado: Icono + Nombre de la App
            Item {
                width: parent.width
                height: 30

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        width: 18
                        height: 18
                        sourceSize: Qt.size(48, 48)
                        anchors.verticalCenter: parent.verticalCenter
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        source: {
                            if (dockContainer.ctxAppIcon && dockContainer.ctxAppIcon.indexOf("/") !== -1) return dockContainer.ctxAppIcon;
                            if (dockContainer.ctxAppId.indexOf("finder") !== -1) return "qrc:/icons/finder.png";
                            if (dockContainer.ctxAppId.indexOf("terminal") !== -1) return "qrc:/icons/terminal.png";
                            if (dockContainer.ctxAppId.indexOf("firefox") !== -1) return "qrc:/icons/firefox.png";
                            if (dockContainer.ctxAppId.indexOf("settings") !== -1) return "qrc:/icons/system.png";
                            return "qrc:/icons/apps-folder.png";
                        }
                    }

                    Text {
                        text: dockContainer.ctxAppName
                        color: menuTheme.headerText
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        width: parent.width - 32
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Separador
            Rectangle {
                width: parent.width
                height: 1
                color: menuTheme.headerBorder
            }

            // Lista de Ventanas Abiertas
            Repeater {
                model: dockContainer.ctxWindows
                delegate: Rectangle {
                    width: parent.width
                    height: 26
                    radius: 6
                    color: winItemMouse.containsMouse ? (menuTheme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: 5
                            height: 5
                            radius: 2.5
                            color: "#0a84ff"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: modelData.title ? modelData.title : "Ventana"
                            color: menuTheme.headerText
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                            width: parent.width - 18
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: winItemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dockModel.activateWindowById(modelData.id)
                            dockContainer.ctxMenuVisible = false
                        }
                    }
                }
            }

            // Separador si hay ventanas
            Rectangle {
                visible: dockContainer.ctxWindows.length > 0
                width: parent.width
                height: 1
                color: menuTheme.headerBorder
            }

            // Opción Fijar / Desanclar
            Rectangle {
                width: parent.width
                height: 26
                radius: 6
                color: pinItemMouse.containsMouse ? (menuTheme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: dockContainer.ctxIsPinned ? "Desanclar del Dock" : "Fijar en el Dock"
                    color: menuTheme.headerText
                    font.pixelSize: 11
                }

                MouseArea {
                    id: pinItemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (dockContainer.ctxIsPinned) {
                            dockModel.unpinApp(dockContainer.ctxAppId)
                        } else {
                            dockModel.pinApp(dockContainer.ctxAppId)
                        }
                        dockContainer.ctxMenuVisible = false
                    }
                }
            }

            // Opción Abrir (si no está corriendo)
            Rectangle {
                visible: !dockContainer.ctxIsRunning
                width: parent.width
                height: 26
                radius: 6
                color: openItemMouse.containsMouse ? (menuTheme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Abrir"
                    color: menuTheme.headerText
                    font.pixelSize: 11
                }

                MouseArea {
                    id: openItemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        dockModel.activateApp(dockContainer.ctxAppId)
                        dockContainer.ctxMenuVisible = false
                    }
                }
            }

            // Opción Cerrar (si está corriendo)
            Rectangle {
                visible: dockContainer.ctxIsRunning
                width: parent.width
                height: 26
                radius: 6
                color: closeItemMouse.containsMouse ? Qt.rgba(1, 0.2, 0.2, 0.22) : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cerrar"
                    color: closeItemMouse.containsMouse ? "#ff4d4d" : menuTheme.headerText
                    font.pixelSize: 11
                }

                MouseArea {
                    id: closeItemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        dockModel.closeApp(dockContainer.ctxAppId)
                        dockContainer.ctxMenuVisible = false
                    }
                }
            }
        }
    }
}
