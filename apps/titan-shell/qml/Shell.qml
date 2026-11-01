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

    // 2. Dock flotante estilo macOS centrado en la parte inferior
    property var dockWin: Window {
        objectName: "dockWindow"
        visible: false
        width: Screen.width
        height: 82
        color: "transparent"
        flags: Qt.FramelessWindowHint

        Dock {
            id: dock
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
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

    // 6. Pantalla de carga (Splash Screen) con el mismo tamaño al de la ventana que abre
    property var splashWin: Window {
        objectName: "splashWindow"
        visible: false
        width: Screen.width
        height: Screen.height
        color: "transparent"
        flags: Qt.FramelessWindowHint

        SplashScreen {
            anchors.centerIn: parent
            width: shellBackend.splashWidth
            height: shellBackend.splashHeight
        }
    }

    // 7. Alerta de Batería Baja a pantalla completa oscurecida
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
                        color: "#0071e3"

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
}
