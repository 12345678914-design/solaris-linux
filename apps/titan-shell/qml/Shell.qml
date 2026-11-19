import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

// Shell raíz: QtObject invisible que instancia las ventanas del sistema
// Esto asegura que las ventanas sean root objects del engine y
// que main.cpp las encuentre correctamente via engine.rootObjects()
QtObject {
    id: shellRoot

    // 1. Barra de menús superior estilo macOS (TopBar / Menu Bar)
    property var topBarWin: Window {
        objectName: "topBarWindow"
        visible: false
        width: Screen.width
        height: 28
        color: "transparent"
        flags: Qt.FramelessWindowHint

        TopBar {
            id: topBar
            anchors.fill: parent
        }
    }

    // 2. Dock flotante estilo macOS centrado en la parte inferior (LayerOverlay)
    property var dockWin: Window {
        objectName: "dockWindow"
        visible: false
        width: Screen.width
        height: 320
        color: "transparent"
        flags: Qt.FramelessWindowHint

        Dock {
            id: dock
            anchors.fill: parent
        }
    }

    // 3. Lanzador Launchpad / Spotlight sobre capa Overlay translúcida
    property var launcherWin: Window {
        objectName: "launcherWindow"
        visible: false
        width: Screen.width
        height: Screen.height
        color: "transparent"
        flags: Qt.FramelessWindowHint

        // Backdrop neutro casi transparente (sin color oscuro opaco)
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.04)
            opacity: shellBackend.launcherVisible ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            MouseArea {
                anchors.fill: parent
                onClicked: shellBackend.closeLauncher()
            }
        }

        Launcher {
            id: launcher
            anchors.centerIn: parent
            visible: shellBackend.launcherVisible
        }

        Item {
            focus: true
            Keys.onEscapePressed: shellBackend.closeLauncher()
        }
    }

    // 4. Iconos del escritorio (posicionamiento libre con drag & drop)
    property var desktopWin: Window {
        objectName: "desktopIconsWindow"
        visible: false
        width: Screen.width
        height: Screen.height
        color: "transparent"
        flags: Qt.FramelessWindowHint

        DesktopIcons {
            anchors.fill: parent
        }
    }

    // 5. Selector de Fondos de Pantalla (Ctrl+W / Mod+W)
    property var wallpaperWin: Window {
        objectName: "wallpaperPickerWindow"
        visible: false
        width: Screen.width
        height: Screen.height
        color: "transparent"
        flags: Qt.FramelessWindowHint

        // Backdrop tenue
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.22)
            opacity: shellBackend.wallpaperPickerVisible ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            MouseArea {
                anchors.fill: parent
                onClicked: shellBackend.closeWallpaperPicker()
            }
        }

        WallpaperPicker {
            anchors.centerIn: parent
            visible: shellBackend.wallpaperPickerVisible
            scale: shellBackend.wallpaperPickerVisible ? 1.0 : 0.92
            opacity: shellBackend.wallpaperPickerVisible ? 1.0 : 0.0
            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.06 } }
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
    }

    // 6. Alerta de Batería Baja a pantalla completa oscurecida
    property var lowBatteryWin: Window {
        objectName: "lowBatteryWindow"
        visible: false
        width: Screen.width
        height: Screen.height
        color: "transparent"
        flags: Qt.FramelessWindowHint

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.78)
            opacity: shellBackend.lowBatteryAlert ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.centerIn: parent
                width: 440
                height: 240
                radius: 20
                color: Qt.rgba(0.12, 0.13, 0.17, 0.96)
                border.color: Qt.rgba(1, 1, 1, 0.22)
                border.width: 1

                Column {
                    anchors.centerIn: parent
                    spacing: 14
                    width: parent.width - 40

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "🪫"
                        font.pixelSize: 42
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Batería baja, por favor conectar"
                        color: "#ffffff"
                        font.pixelSize: 17
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "El nivel de carga es inferior al 10%. Conecta el equipo a una fuente de alimentación."
                        color: Qt.rgba(1, 1, 1, 0.70)
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        width: parent.width
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 110
                        height: 32
                        radius: 8
                        color: (typeof titanThemeManager !== "undefined" ? titanThemeManager.accent : "#0071e3")

                        Text {
                            anchors.centerIn: parent
                            text: "Entendido"
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shellBackend.dismissBatteryAlert()
                        }
                    }
                }
            }
        }
    }

    // 8. Centro de Control en ventana Overlay independiente (evita clipping de la TopBar)
    property var controlCenterWin: Window {
        objectName: "controlCenterWindow"
        visible: false
        width: Screen.width
        height: Screen.height
        color: "transparent"
        flags: Qt.FramelessWindowHint

        MouseArea {
            anchors.fill: parent
            onClicked: shellBackend.closeControlCenter()
        }

        ControlCenter {
            id: controlCenter
            anchors.top: parent.top
            anchors.topMargin: 34
            anchors.right: parent.right
            anchors.rightMargin: 12
            visible: shellBackend.controlCenterVisible
            scale: shellBackend.controlCenterVisible ? 1.0 : 0.94
            opacity: shellBackend.controlCenterVisible ? 1.0 : 0.0
            transformOrigin: Item.TopRight

            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.05 } }
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }

        Item {
            focus: true
            Keys.onEscapePressed: shellBackend.closeControlCenter()
        }
    }

    // 9. Centro de Notificaciones en ventana Overlay independiente
    property var notificationCenterWin: Window {
        objectName: "notificationCenterWindow"
        visible: false
        width: Screen.width
        height: Screen.height
        color: "transparent"
        flags: Qt.FramelessWindowHint

        MouseArea {
            anchors.fill: parent
            onClicked: shellBackend.closeNotificationCenter()
        }

        NotificationCenter {
            id: notifCenter
            anchors.top: parent.top
            anchors.topMargin: 34
            anchors.right: parent.right
            anchors.rightMargin: 12
            visible: shellBackend.notificationCenterVisible
            scale: shellBackend.notificationCenterVisible ? 1.0 : 0.94
            opacity: shellBackend.notificationCenterVisible ? 1.0 : 0.0
            transformOrigin: Item.TopRight

            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.05 } }
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }

        Item {
            focus: true
            Keys.onEscapePressed: shellBackend.closeNotificationCenter()
        }
    }

    // 10. Isla Dinámica (Notificación emergente en la parte superior)
    property var dynamicIslandWin: Window {
        objectName: "dynamicIslandWindow"
        visible: false
        id: ventanaIsla
        // Del tamaño de la isla, para no tapar ni robar clics a las ventanas
        // de debajo. Antes seguía cada fotograma de la animación (unos 60
        // cambios de tamaño de la superficie Wayland por transición): ahora
        // crece de una vez al tamaño final y solo encoge cuando la animación
        // ha terminado. (Una máscara de entrada con ventana fija no sirve:
        // su commit a mitad de animación deja a Qt sin frame callback.)
        property real anchoV: 40
        property real altoV: 28
        width: anchoV
        height: altoV
        color: "transparent"
        flags: Qt.FramelessWindowHint

        function ajustar() {
            var w = Math.ceil(Math.max(isla.anchoObjetivo, isla.width)) + 16
            var h = Math.ceil(Math.max(isla.altoObjetivo, isla.height)) + 8
            var quieta = Math.abs(isla.width - isla.anchoObjetivo) < 1 && Math.abs(isla.height - isla.altoObjetivo) < 1
            if (w > anchoV || quieta) anchoV = Math.max(40, w)
            if (h > altoV || quieta) altoV = Math.max(28, h)
        }
        Connections {
            target: isla
            function onAnchoObjetivoChanged() { ventanaIsla.ajustar() }
            function onAltoObjetivoChanged() { ventanaIsla.ajustar() }
            function onWidthChanged() { ventanaIsla.ajustar() }
            function onHeightChanged() { ventanaIsla.ajustar() }
        }

        // Sobre la barra superior (28 px): en reposo cabe dentro de ella.
        DynamicIsland {
            id: isla
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 2
        }
    }

    // 11. Sistema de Escritorios / Mission Control (Hot Corner superior derecho)
    property var workspacesWin: Window {
        objectName: "workspacesWindow"
        visible: false
        width: Screen.width
        height: Screen.height
        color: "transparent"
        flags: Qt.FramelessWindowHint

        WorkspacesView {
            anchors.fill: parent
        }
    }

    // 12. Animación Cinematográfica de Arranque (BootSplash: Logo centrado -> desliza a izquierda + Nombre Inti OS)
    property var bootSplashWin: Window {
        objectName: "bootSplashWindow"
        visible: shellBackend.bootSplashActive
        width: Screen.width
        height: Screen.height
        color: "#000000"
        flags: Qt.FramelessWindowHint

        BootSplash {
            anchors.fill: parent
        }
    }

    // 13. Pantalla de Bloqueo (Lock Screen: Mod + L en Live, o pantalla inicial en Instalado)
    property var lockScreenWin: Window {
        objectName: "lockScreenWindow"
        visible: shellBackend.lockScreenActive && shellBackend.bootSplashFinished
        width: Screen.width
        height: Screen.height
        color: "transparent"
        flags: Qt.FramelessWindowHint

        LockScreen {
            anchors.fill: parent
        }
    }
}
