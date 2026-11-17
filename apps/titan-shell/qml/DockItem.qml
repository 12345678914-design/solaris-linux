import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

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
    property bool isLaunching: false
    property bool isPinned: false
    property bool showSeparator: false

    property real bounceOffset: 0.0
    property real squashX: 1.0
    property real squashY: 1.0

    onIsLaunchingChanged: {
        if (!isLaunching) {
            bounceOffset = 0;
            squashX = 1.0;
            squashY = 1.0;
        }
    }

    onHasWindowChanged: {
        if (hasWindow) {
            bounceOffset = 0;
            squashX = 1.0;
            squashY = 1.0;
        }
        publicarDestino();
    }

    // Le dice al compositor dónde está este icono para que la ventana se
    // "aspire" hacia él al minimizar (squeezimize en Wayfire). Se usa la
    // posición sin magnificar para que el destino no baile con el ratón.
    function publicarDestino() {
        if (!appId || !dockItem.Window.window) return;
        var p = dockItem.mapToItem(null, 0, -targetY);
        windowTracker.setMinimizeTarget(appId, dockItem.Window.window,
                                        p.x, p.y, width, height);
    }
    Timer {
        id: destinoTimer
        interval: 250
        onTriggered: dockItem.publicarDestino()
    }
    onXChanged: destinoTimer.restart()
    onIsRunningChanged: destinoTimer.restart()
    Component.onCompleted: destinoTimer.restart()

    property real dragOffsetX: 0
    readonly property bool isBeingDragged: dockContainer.draggedIndex === itemIndex

    readonly property real shiftX: {
        if (dockContainer.draggedIndex < 0 || dockContainer.draggedIndex === itemIndex) return 0;
        var fromIdx = dockContainer.draggedIndex;
        var toIdx = dockContainer.targetDropIndex;
        if (toIdx < 0 || fromIdx === toIdx) return 0;

        if (fromIdx < toIdx) {
            if (itemIndex > fromIdx && itemIndex <= toIdx) return -47;
        } else if (fromIdx > toIdx) {
            if (itemIndex >= toIdx && itemIndex < fromIdx) return 47;
        }
        return 0;
    }

    transform: Translate {
        x: dockItem.isBeingDragged ? dockItem.dragOffsetX : dockItem.shiftX
        Behavior on x {
            enabled: !dockItem.isBeingDragged
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }

    // Efecto de magnificación macOS:
    // La app apuntada es la más alta (1.34x, y: -9), y sus dos vecinas contiguas se agrandan un poco (1.16x, y: -4)
    readonly property int hoveredIdx: dockContainer.hoveredIndex
    readonly property int distanceToHovered: hoveredIdx >= 0 ? Math.abs(hoveredIdx - itemIndex) : 99

    readonly property real targetScale: {
        if (isBeingDragged) return 1.22;
        if (distanceToHovered === 0) return 1.34;
        if (distanceToHovered === 1) return 1.16;
        return 1.0;
    }

    readonly property real targetY: {
        if (isBeingDragged) return -14;
        if (distanceToHovered === 0) return -9;
        if (distanceToHovered === 1) return -4;
        return 0;
    }

    scale: targetScale
    y: targetY
    z: isBeingDragged ? 9999 : (mouseArea.containsMouse ? 1000 : (isRunning || hasWindow ? 10 : 1))

    Behavior on scale {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    Behavior on y {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    // Sombra dinámica en el suelo del Dock mientras el icono rebota
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        width: Math.max(10, 24 * (1.0 + Math.abs(dockItem.bounceOffset) / 36.0))
        height: 3
        radius: 1.5
        color: Qt.rgba(0, 0, 0, Math.max(0.06, 0.28 - Math.abs(dockItem.bounceOffset) / 80.0))
        visible: dockItem.isLaunching && !dockItem.hasWindow
    }

    // Separador vertical macOS entre apps ancladas y en ejecución, y antes de papelera
    Rectangle {
        visible: dockItem.showSeparator
        anchors.left: parent.left
        anchors.leftMargin: -2
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: 28
        color: Qt.rgba(1, 1, 1, 0.22)
    }

    Item {
        id: iconContainer
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: dockItem.bounceOffset
        width: 36
        height: 36

        transform: Scale {
            origin.x: 18
            origin.y: 36
            xScale: dockItem.squashX
            yScale: dockItem.squashY
        }

        Image {
            id: iconImg
            anchors.fill: parent
            sourceSize: Qt.size(96, 96)
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            source: {
                if (appIcon && appIcon.indexOf("/") !== -1) return appIcon;
                if (appIcon === "folder" || appIcon === "titan-finder") return "qrc:/icons/finder.png";
                if (appIcon === "view-app-grid" || appIcon === "launchpad") return "qrc:/icons/launchpad.png";
                if (appIcon === "utilities-terminal" || appIcon === "terminal" || appIcon === "titan-terminal") return "qrc:/icons/terminal.png";
                if (appIcon === "system-file-manager" || appIcon === "pcmanfm-qt" || appIcon === "files") return "qrc:/icons/files.png";
                if (appIcon === "help-about" || appIcon === "titan-acerca") return "qrc:/icons/about.png";
                if (appIcon === "firefox" || appIcon === "safari") return "qrc:/icons/firefox.png";
                if (appIcon === "vscode" || appIcon === "code") return "qrc:/icons/vscode.png";
                if (appIcon === "system" || appIcon === "titan-settings") return "qrc:/icons/system.png";
                if (appIcon === "onlyoffice" || appIcon === "onlyoffice-desktopeditors") return "qrc:/icons/onlyoffice.png";
                if (appIcon === "developer" || appIcon === "vim") return "qrc:/icons/developer.png";
                if (appIcon === "calculator" || appIcon === "titan-calc") return "qrc:/icons/calculator.png";
                if (appIcon === "calendar" || appIcon === "titan-calendar") return "qrc:/icons/calendar.png";
                if (appIcon === "clock" || appIcon === "titan-clock") return "qrc:/icons/clock.png";
                if (appIcon === "video" || appIcon === "titan-video") return "qrc:/icons/video.png";
                if (appIcon === "music" || appIcon === "titan-musica") return "qrc:/icons/music-app.png";
                if (appIcon === "pictures" || appIcon === "titan-fotos") return "qrc:/icons/pictures.png";
                if (appIcon === "trash" || appIcon === "user-trash" || appIcon === "titan-trash") return "qrc:/icons/trash.png";
                return "qrc:/icons/apps-folder.png";
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

    // Animación de rebote de pelota (sube y baja con física elástica hasta que la app abra su ventana)
    SequentialAnimation {
        id: ballBounceAnim
        running: dockItem.isLaunching && !dockItem.hasWindow
        loops: Animation.Infinite

        // 1. Subida: Despega hacia arriba desacelerando en la cúspide
        ParallelAnimation {
            NumberAnimation {
                target: dockItem
                property: "bounceOffset"
                from: 0
                to: -28
                duration: 250
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: dockItem
                property: "squashY"
                from: 1.0
                to: 1.10
                duration: 170
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: dockItem
                property: "squashX"
                from: 1.0
                to: 0.93
                duration: 170
                easing.type: Easing.OutQuad
            }
        }

        // 2. Caída: Cae acelerando por gravedad hasta el suelo
        ParallelAnimation {
            NumberAnimation {
                target: dockItem
                property: "bounceOffset"
                from: -28
                to: 0
                duration: 220
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: dockItem
                property: "squashY"
                from: 1.10
                to: 0.82
                duration: 220
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: dockItem
                property: "squashX"
                from: 0.93
                to: 1.18
                duration: 220
                easing.type: Easing.InQuad
            }
        }

        // 3. Impacto elástico en el suelo y recuperación de forma
        ParallelAnimation {
            NumberAnimation {
                target: dockItem
                property: "squashY"
                to: 1.0
                duration: 110
                easing.type: Easing.OutBack
                easing.overshoot: 1.15
            }
            NumberAnimation {
                target: dockItem
                property: "squashX"
                to: 1.0
                duration: 110
                easing.type: Easing.OutBack
                easing.overshoot: 1.15
            }
        }

        PauseAnimation { duration: 35 }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: isDraggingApp ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        property real globalPressX: 0
        property bool isDraggingApp: false

        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                return
            }
            globalPressX = mouse.x
            isDraggingApp = false
            dockItem.dragOffsetX = 0
        }

        onPositionChanged: (mouse) => {
            if (pressed && mouse.buttons & Qt.LeftButton) {
                var delta = mouse.x - globalPressX
                dockItem.dragOffsetX += delta
                if (!isDraggingApp && Math.abs(dockItem.dragOffsetX) > 8) {
                    isDraggingApp = true
                    dockContainer.draggedIndex = itemIndex
                    dockContainer.targetDropIndex = itemIndex
                }
                if (isDraggingApp) {
                    var ptInRow = mouseArea.mapToItem(dockRow, mouse.x, mouse.y)
                    var targetSlot = Math.max(0, Math.min(dockModel.rowCount() - 1, Math.round((ptInRow.x - 22) / 47)))
                    if (targetSlot !== dockContainer.targetDropIndex) {
                        dockContainer.targetDropIndex = targetSlot
                    }
                }
            } else {
                dockContainer.hoveredIndex = itemIndex
            }
        }

        onReleased: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                if (isDraggingApp && dockContainer.targetDropIndex >= 0 && dockContainer.targetDropIndex !== itemIndex) {
                    dockModel.moveItem(itemIndex, dockContainer.targetDropIndex)
                }
                isDraggingApp = false
                dockItem.dragOffsetX = 0
                dockContainer.draggedIndex = -1
                dockContainer.targetDropIndex = -1
                dockContainer.hoveredIndex = -1
            }
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
            if (mouse.button === Qt.RightButton) {
                var ptInDock = mouseArea.mapToItem(dockContainer, mouse.x, mouse.y)
                dockContainer.openContextMenu(appId, appName, appIcon, isPinned, isRunning || hasWindow, ptInDock.x, ptInDock.y)
            } else if (!isDraggingApp) {
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
        width: Math.max(48, tooltipText.implicitWidth + 20)
        height: 24
        radius: 7
        z: 9999

        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.08, 0.10, 0.16, 0.96) }
            GradientStop { position: 1.0; color: Qt.rgba(0.06, 0.08, 0.12, 0.96) }
        }
        border.color: Qt.rgba(1, 1, 1, 0.28)
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
            color: "#FFFFFF"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            renderType: Text.QtRendering
        }
    }
}
