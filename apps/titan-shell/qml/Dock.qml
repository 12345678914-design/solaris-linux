import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: dockContainer
    height: 70
    width: parent ? parent.width : dockBg.width

    property int hoveredIndex: -1
    property bool isMaximized: windowTracker.hasMaximizedWindow || windowTracker.hasFullscreenWindow
    property bool pointerNearBottom: triggerArea.containsMouse || dockMouseArea.containsMouse

    // Zona sensible a lo largo de toda la parte inferior para revelar el dock al apuntar hacia abajo
    MouseArea {
        id: triggerArea
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 24
        hoverEnabled: true
    }

    Rectangle {
        id: dockBg
        height: 55
        width: dockRow.width + 20
        radius: 18
        clip: false
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4

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

        MouseArea {
            id: dockMouseArea
            anchors.fill: parent
            hoverEnabled: true
            onExited: dockContainer.hoveredIndex = -1
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
                }
            }
        }

        Behavior on width {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        // Ocultación automática cuando una ventana está MAXIMIZADA o en pantalla completa,
        // revelándose de inmediato al mover el puntero al borde inferior de la pantalla
        property bool shouldHide: shellBackend.launcherVisible || (dockContainer.isMaximized && !dockContainer.pointerNearBottom)

        opacity: shouldHide ? 0.0 : 1.0
        transform: Translate {
            y: dockBg.shouldHide ? 64 : 0
            Behavior on y {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
    }
}
