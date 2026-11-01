import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: dockItem
    width: 44
    height: 44

    property int itemIndex: 0
    property string appId: ""
    property string appName: ""
    property string appIcon: ""
    property string appExec: ""
    property bool isRunning: false
    property bool hasWindow: false
    property bool active: false

    // Efecto de magnificación macOS:
    // La app apuntada es la más alta (1.34x, y: -9), y sus dos vecinas contiguas se agrandan un poco (1.16x, y: -4)
    readonly property int hoveredIdx: dockContainer.hoveredIndex
    readonly property int distanceToHovered: hoveredIdx >= 0 ? Math.abs(hoveredIdx - itemIndex) : 99

    readonly property real targetScale: {
        if (distanceToHovered === 0) return 1.34;
        if (distanceToHovered === 1) return 1.16;
        return 1.0;
    }

    readonly property real targetY: {
        if (distanceToHovered === 0) return -9;
        if (distanceToHovered === 1) return -4;
        return 0;
    }

    scale: targetScale
    y: targetY

    Behavior on scale {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    Behavior on y {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    Item {
        id: iconContainer
        anchors.centerIn: parent
        width: 36
        height: 36

        Image {
            id: iconImg
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            source: {
                if (appIcon.indexOf("/") !== -1) return appIcon;
                if (appIcon === "folder" || appIcon === "titan-finder") return "qrc:/icons/finder.png";
                if (appIcon === "view-app-grid" || appIcon === "launchpad") return "qrc:/icons/launchpad.png";
                if (appIcon === "utilities-terminal" || appIcon === "terminal" || appIcon === "titan-terminal") return "qrc:/icons/terminal.png";
                if (appIcon === "system-file-manager" || appIcon === "pcmanfm-qt" || appIcon === "files") return "qrc:/icons/files.png";
                if (appIcon === "help-about" || appIcon === "titan-acerca") return "qrc:/icons/about.png";
                if (appIcon === "firefox" || appIcon === "safari") return "qrc:/icons/safari.png";
                if (appIcon === "vscode" || appIcon === "code") return "qrc:/icons/vscode.png";
                if (appIcon === "system" || appIcon === "titan-settings") return "qrc:/icons/system.png";
                if (appIcon === "onlyoffice" || appIcon === "onlyoffice-desktopeditors") return "qrc:/icons/onlyoffice.png";
                return "qrc:/icons/developer.png";
            }
        }
    }

    // Indicador de app en ejecución estilo macOS (punto luminoso centrado debajo)
    Rectangle {
        visible: isRunning || hasWindow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        width: active ? 10 : 4
        height: 4
        radius: 2
        color: active ? "#0071e3" : (typeof titanThemeManager !== "undefined" && !titanThemeManager.isDark ? "#444444" : "#D0D6E2")
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 180 } }
    }

    // Animación de rebote al hacer clic
    SequentialAnimation {
        id: bounceAnim
        NumberAnimation { target: iconContainer; property: "scale"; to: 0.82; duration: 80; easing.type: Easing.InQuad }
        NumberAnimation { target: iconContainer; property: "scale"; to: 1.22; duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        NumberAnimation { target: iconContainer; property: "scale"; to: 1.0; duration: 120; easing.type: Easing.InOutQuad }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        property real globalPressX: 0
        property bool isDraggingApp: false

        onPressed: (mouse) => {
            globalPressX = mouse.x
            isDraggingApp = false
        }

        onPositionChanged: (mouse) => {
            dockContainer.hoveredIndex = itemIndex
            if (pressed && Math.abs(mouse.x - globalPressX) > 28) {
                isDraggingApp = true
            }
        }

        onReleased: (mouse) => {
            if (isDraggingApp) {
                var delta = mouse.x - globalPressX
                var steps = Math.round(delta / 44)
                if (steps !== 0) {
                    var newIdx = Math.max(0, Math.min(dockModel.rowCount() - 1, itemIndex + steps))
                    if (newIdx !== itemIndex) {
                        dockModel.moveItem(itemIndex, newIdx)
                    }
                }
            }
            isDraggingApp = false
            dockContainer.hoveredIndex = -1
        }

        onEntered: {
            dockContainer.hoveredIndex = itemIndex
        }

        onExited: {
            if (dockContainer.hoveredIndex === itemIndex && !pressed) {
                dockContainer.hoveredIndex = -1
            }
        }

        onClicked: (mouse) => {
            if (!isDraggingApp) {
                bounceAnim.start()
                // Solo mostrar la pantalla de carga (splash) si la app no está corriendo
                if (!isRunning && !hasWindow) {
                    shellBackend.showSplash(appName, appIcon, appExec)
                }
                dockModel.activateApp(appId)
            }
        }
    }

    // Tooltip Liquid Glass estilo macOS
    Rectangle {
        id: tooltip
        visible: mouseArea.containsMouse && !mouseArea.pressed && !mouseArea.drag.active
        opacity: visible ? 1.0 : 0.0
        anchors.bottom: parent.top
        anchors.bottomMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        width: tooltipText.width + 16
        height: 24
        radius: 6
        z: 200

        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.08, 0.10, 0.16, 0.96) }
            GradientStop { position: 1.0; color: Qt.rgba(0.06, 0.08, 0.12, 0.96) }
        }
        border.color: Qt.rgba(1, 1, 1, 0.22)
        border.width: 1

        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 10
            height: 1
            color: Qt.rgba(1, 1, 1, 0.28)
        }

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Text {
            id: tooltipText
            anchors.centerIn: parent
            text: appName
            color: "#F2F4F8"
            font.pixelSize: 11
            font.weight: Font.Medium
        }
    }
}
