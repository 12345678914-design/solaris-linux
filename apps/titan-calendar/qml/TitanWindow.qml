import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Effects   // MultiEffect (Qt 6.5+)

Window {
    id: rootWindow

    default property alias mainContentData: contentSlot.data
    property alias content: contentSlot.data
    property alias headerContentData: headerSlot.data
    property alias sidebarContentData: sidebarSlot.data
    property alias statusBarContentData: statusBarSlot.data
    property alias backdropData: backdrop.data   // contenido extra que se desenfoca

    property alias theme: titanTheme
    property bool sidebarCollapsed: false
    property int expandedSidebarWidth: 205
    property int collapsedSidebarWidth: 54
    property int sidebarWidth: sidebarCollapsed ? collapsedSidebarWidth : expandedSidebarWidth
    property bool showSidebar: true
    property real effectiveSidebarWidth: showSidebar ? sidebarWidth : 0
    Behavior on effectiveSidebarWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    property bool showStatusBar: true
    property int statusBarHeight: 26

    // ---------- BLUR ----------
    property bool blurActive: true          // activa/desactiva el desenfoque
    property real blurAmount: 1.0           // 0.0 - 1.0
    property int  blurMax: 64               // radio máximo (más alto = más suave y más costoso)
    property url  backdropImage: ""         // fondo/wallpaper a desenfocar (vacío = manchas de color)

    // Opacidad del vidrio por zona (menor = se ve más el blur)
    property real headerGlass: 0.45
    property real sidebarGlass: 0.50
    property real contentGlass: 0.62
    property real statusGlass: 0.50

    function glass(c, a) {
        if (!c) return Qt.rgba(0.1, 0.1, 0.1, a !== undefined ? a : 0.5)
        var col = Qt.color(c)
        return Qt.rgba(col.r, col.g, col.b, a !== undefined ? a : col.a)
    }

    property real cornerRadius: visibility === Window.Maximized ? 0 : titanTheme.windowRadius

    width: 960
    height: 620
    minimumWidth: 680
    minimumHeight: 440
    visible: true
    flags: Qt.FramelessWindowHint | Qt.Window
    color: "transparent"

    property bool isDragging: false
    property bool isMinimizing: false

    TitanTheme { id: titanTheme }

    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on x { enabled: !rootWindow.isDragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !rootWindow.isDragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Item {
        id: windowContainer
        anchors.fill: parent

        opacity: rootWindow.isMinimizing ? 0.0 : 1.0
        scale: rootWindow.isMinimizing ? 0.85 : 1.0
        transformOrigin: Item.Bottom

        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Component.onCompleted: openContainerAnim.start()

        ParallelAnimation {
            id: openContainerAnim
            NumberAnimation { target: windowContainer; property: "opacity"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: windowContainer; property: "scale"; from: 0.94; to: 1.0; duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.06 }
        }

        SequentialAnimation {
            id: closeContainerAnim
            ParallelAnimation {
                NumberAnimation { target: windowContainer; property: "opacity"; to: 0.0; duration: 150; easing.type: Easing.InCubic }
                NumberAnimation { target: windowContainer; property: "scale"; to: 0.94; duration: 150; easing.type: Easing.InCubic }
            }
            ScriptAction { script: rootWindow.close() }
        }

        SequentialAnimation {
            id: minimizeContainerAnim
            ParallelAnimation {
                NumberAnimation { target: windowContainer; property: "opacity"; to: 0.0; duration: 160; easing.type: Easing.InCubic }
                NumberAnimation { target: windowContainer; property: "scale"; to: 0.88; duration: 180; easing.type: Easing.InCubic }
            }
            ScriptAction {
                script: {
                    rootWindow.showMinimized()
                    windowContainer.opacity = 1.0
                    windowContainer.scale = 1.0
                    rootWindow.isMinimizing = false
                }
            }
        }

        // Máscara para recortar TODO con esquinas redondeadas (clip no redondea)
        Rectangle {
            id: clipMask
            anchors.fill: parent
            radius: rootWindow.cornerRadius
            visible: false
            layer.enabled: true
        }

        Item {
            id: glassRoot
            anchors.fill: parent

            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: clipMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            // 0. FONDO A DESENFOCAR (no se muestra directo, solo su versión borrosa)
            Item {
                id: backdrop
                anchors.fill: parent
                visible: false

                Rectangle { anchors.fill: parent; color: "#1b1f2e" }

                Image {
                    anchors.fill: parent
                    source: rootWindow.backdropImage
                    fillMode: Image.PreserveAspectCrop
                    visible: source != ""
                }

                // Manchas de color por defecto (se ven suaves tras el blur)
                Item {
                    anchors.fill: parent
                    visible: rootWindow.backdropImage == ""
                    Rectangle { x: parent.width * 0.04; y: parent.height * 0.10; width: parent.width * 0.45; height: width; radius: width / 2; color: "#6a5cff" }
                    Rectangle { x: parent.width * 0.55; y: -parent.height * 0.10; width: parent.width * 0.40; height: width; radius: width / 2; color: "#ff5fa2" }
                    Rectangle { x: parent.width * 0.35; y: parent.height * 0.45; width: parent.width * 0.42; height: width; radius: width / 2; color: "#2ad4c6" }
                }
            }

            // 1. CAPA ESCARCHADA: blur de todo el fondo (cabecera, sidebar y contenido lo atraviesan)
            MultiEffect {
                id: frosted
                anchors.fill: parent
                source: backdrop
                visible: rootWindow.blurActive
                blurEnabled: true
                blurMax: rootWindow.blurMax
                blur: rootWindow.blurAmount
                saturation: 0.25
                brightness: -0.04
            }

            // Respaldo sin blur
            Rectangle {
                anchors.fill: parent
                visible: !rootWindow.blurActive
                gradient: Gradient {
                    GradientStop { position: 0.0; color: titanTheme.windowBgTop }
                    GradientStop { position: 0.5; color: titanTheme.windowBgMid }
                    GradientStop { position: 1.0; color: titanTheme.windowBgBottom }
                }
            }

            // 2. CABECERA: vidrio translúcido sobre el blur
            Rectangle {
                id: headerPanel
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 50
                z: 10

                gradient: Gradient {
                    GradientStop { position: 0.0; color: rootWindow.glass(titanTheme.headerTop, rootWindow.headerGlass) }
                    GradientStop { position: 1.0; color: rootWindow.glass(titanTheme.headerBottom, rootWindow.headerGlass) }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: titanTheme.headerBorder
                }

                // Arrastre nativo (Wayland startSystemMove / X11)
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    property point pressPos
                    property bool systemMoveStarted: false

                    onPressed: (mouse) => {
                        pressPos = Qt.point(mouse.x, mouse.y)
                        systemMoveStarted = false
                    }
                    onPositionChanged: (mouse) => {
                        if (!systemMoveStarted) {
                            var dx = mouse.x - pressPos.x
                            var dy = mouse.y - pressPos.y
                            if (Math.abs(dx) > 3 || Math.abs(dy) > 3) {
                                rootWindow.isDragging = true
                                if (rootWindow.startSystemMove()) {
                                    systemMoveStarted = true
                                } else {
                                    rootWindow.x += dx
                                    rootWindow.y += dy
                                }
                            }
                        }
                    }
                    onReleased: { rootWindow.isDragging = false; systemMoveStarted = false }
                    onCanceled: { rootWindow.isDragging = false; systemMoveStarted = false }
                    onDoubleClicked: rootWindow.toggleMaximize()
                }

                // Zona de sidebar dentro de la cabecera (donde van los botones): también con blur
                Rectangle {
                    visible: rootWindow.effectiveSidebarWidth > 0
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: rootWindow.effectiveSidebarWidth
                    clip: true
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: rootWindow.glass(titanTheme.sidebarTop, rootWindow.sidebarGlass) }
                        GradientStop { position: 1.0; color: rootWindow.glass(titanTheme.sidebarBottom, rootWindow.sidebarGlass) }
                    }
                    Rectangle {
                        anchors.right: parent.right
                        width: 1
                        height: parent.height
                        color: titanTheme.sidebarBorder
                    }
                }

                // Semáforos macOS
                Row {
                    id: trafficLightsRow
                    x: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    z: 20

                    Rectangle {
                        width: 12; height: 12; radius: 6
                        color: "#ff5f57"; border.color: "#e0443e"; border.width: 0.5
                        scale: closeMouse.containsMouse ? 1.15 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: closeContainerAnim.start() }
                    }
                    Rectangle {
                        width: 12; height: 12; radius: 6
                        color: "#febc2e"; border.color: "#dea123"; border.width: 0.5
                        scale: minMouse.containsMouse ? 1.15 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        MouseArea {
                            id: minMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: { rootWindow.isMinimizing = true; minimizeContainerAnim.start() }
                        }
                    }
                    Rectangle {
                        width: 12; height: 12; radius: 6
                        color: "#28c840"; border.color: "#1aab29"; border.width: 0.5
                        scale: maxMouse.containsMouse ? 1.15 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        MouseArea { id: maxMouse; anchors.fill: parent; hoverEnabled: true; onClicked: rootWindow.toggleMaximize() }
                    }
                }

                Item {
                    id: headerSlot
                    anchors.left: parent.left
                    anchors.leftMargin: rootWindow.effectiveSidebarWidth > 0 ? (rootWindow.effectiveSidebarWidth + 14) : (trafficLightsRow.x + trafficLightsRow.width + 16)
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    height: parent.height
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on anchors.leftMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
            }

            // 3. CUERPO
            Item {
                id: bodyContainer
                anchors.top: headerPanel.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: rootWindow.showStatusBar ? statusBarPanel.top : parent.bottom

                Rectangle {
                    id: sidebarPanel
                    visible: rootWindow.effectiveSidebarWidth > 0
                    width: rootWindow.effectiveSidebarWidth
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    clip: true

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: rootWindow.glass(titanTheme.sidebarTop, rootWindow.sidebarGlass) }
                        GradientStop { position: 1.0; color: rootWindow.glass(titanTheme.sidebarBottom, rootWindow.sidebarGlass) }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        width: 1
                        height: parent.height
                        color: titanTheme.sidebarBorder
                    }

                    Item { id: sidebarSlot; anchors.fill: parent }
                }

                Rectangle {
                    id: contentPanel
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: rootWindow.showSidebar ? sidebarPanel.right : parent.left
                    anchors.right: parent.right
                    color: rootWindow.glass(titanTheme.contentBackground, rootWindow.contentGlass)

                    Item { id: contentSlot; anchors.fill: parent }
                }
            }

            // 4. BARRA DE ESTADO
            Rectangle {
                id: statusBarPanel
                visible: rootWindow.showStatusBar
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: rootWindow.statusBarHeight

                gradient: Gradient {
                    GradientStop { position: 0.0; color: rootWindow.glass(titanTheme.sidebarTop, rootWindow.statusGlass) }
                    GradientStop { position: 1.0; color: rootWindow.glass(titanTheme.sidebarBottom, rootWindow.statusGlass) }
                }

                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: 1
                    color: titanTheme.sidebarBorder
                }

                Item { id: statusBarSlot; anchors.fill: parent }
            }

            // Brillo especular superior
            Rectangle {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 32
                height: 1
                color: titanTheme.specularGlow
                z: 25
            }
        }

        // Borde exterior redondeado, por encima de todo
        Rectangle {
            anchors.fill: parent
            radius: rootWindow.cornerRadius
            color: "transparent"
            border.color: titanTheme.glassBorder
            border.width: 1
            z: 100
        }
    }

    function toggleMaximize() {
        if (rootWindow.visibility === Window.Maximized)
            rootWindow.showNormal()
        else
            rootWindow.showMaximized()
    }
}
