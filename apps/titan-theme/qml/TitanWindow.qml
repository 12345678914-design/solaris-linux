import QtQuick
import QtQuick.Controls
import QtQuick.Window

Window {
    id: rootWindow

    default property alias contentData: contentSlot.data
    property alias mainContentData: contentSlot.data
    property alias content: contentSlot.data
    property alias headerContentData: headerSlot.data
    property alias sidebarContentData: sidebarSlot.data
    property alias statusBarContentData: statusBarSlot.data

    property alias theme: titanTheme
    property bool sidebarCollapsed: false
    property int expandedSidebarWidth: 205
    property int collapsedSidebarWidth: 54
    property real sidebarWidth: sidebarCollapsed ? collapsedSidebarWidth : expandedSidebarWidth
    property bool showSidebar: true
    property real effectiveSidebarWidth: showSidebar ? sidebarWidth : 0
    Behavior on effectiveSidebarWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    property bool showStatusBar: true
    property int statusBarHeight: 26

    // ---------- VIDRIO (refleja el fondo de pantalla) ----------
    // Ruta del fondo ACTUAL. Las apps son procesos aparte, así que no ven `shellBackend`:
    // pásala desde donde arrancas la app (variable de entorno, archivo de config o
    // propiedad expuesta por TitanTheme). Si queda vacía, se usa el degradado del tema.
    property string wallpaperSource: ""

    // Wayland no deja que una ventana conozca su posición en pantalla, así que por defecto el
    // fondo se ajusta a la propia ventana. Ponlo en true solo si x/y son fiables (X11).
    property bool alignWallpaper: false

    // Opacidad del vidrio por zona (menor = se ve más el fondo)
    property real headerGlass: 0.45
    property real sidebarGlass: 0.50
    property real contentGlass: 0.62
    property real statusGlass: 0.50

    // Título centrado en la barra superior (se oculta si pones contenido propio en headerSlot)
    property bool showTitle: true

    function glass(c, a) {
        if (!c) return Qt.rgba(0.1, 0.1, 0.1, a !== undefined ? a : 0.5)
        var col = Qt.color(c)
        return Qt.rgba(col.r, col.g, col.b, a !== undefined ? a : col.a)
    }

    readonly property real cornerRadius: visibility === Window.Maximized ? 0 : titanTheme.windowRadius

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

        // ---------- 0. FONDO DE VIDRIO ----------
        // Solo el fondo está recortado con máscara (capa estática). El contenido de la app
        // NO pasa por ninguna capa, así que animaciones y scroll no cuestan extra.
        Rectangle {
            id: fallbackBg
            anchors.fill: parent
            radius: rootWindow.cornerRadius
            visible: !glass.active
            gradient: Gradient {
                GradientStop { position: 0.0; color: titanTheme.windowBgTop }
                GradientStop { position: 0.5; color: titanTheme.windowBgMid }
                GradientStop { position: 1.0; color: titanTheme.windowBgBottom }
            }
        }

        GlassPanel {
            id: glass
            anchors.fill: parent
            radius: rootWindow.cornerRadius
            dark: titanTheme.isDark
            tint: titanTheme.isDark ? Qt.rgba(0.08, 0.09, 0.13, 0.50) : Qt.rgba(0.97, 0.97, 0.99, 0.50)
            wallpaper: rootWindow.wallpaperSource
            aligned: rootWindow.alignWallpaper
            originX: (typeof Screen !== "undefined" && typeof Screen.virtualX !== "undefined") ? (rootWindow.x - Screen.virtualX) : 0
            originY: (typeof Screen !== "undefined" && typeof Screen.virtualY !== "undefined") ? (rootWindow.y - Screen.virtualY) : 0
            sceneWidth: (typeof Screen !== "undefined" && Screen.width > 0) ? Screen.width : 1920
            sceneHeight: (typeof Screen !== "undefined" && Screen.height > 0) ? Screen.height : 1080
            showBorder: false
            showHighlight: false
        }

        // ---------- 1. BARRA SUPERIOR (título + semáforos) ----------
        Rectangle {
            id: headerPanel
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 50
            z: 10
            topLeftRadius: rootWindow.cornerRadius
            topRightRadius: rootWindow.cornerRadius

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

            // Zona de sidebar dentro de la barra (donde van los semáforos): mismo vidrio
            Rectangle {
                visible: rootWindow.effectiveSidebarWidth > 0
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: rootWindow.effectiveSidebarWidth
                topLeftRadius: rootWindow.cornerRadius
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

            // Título de la ventana, centrado
            Text {
                id: titleText
                visible: rootWindow.showTitle && headerSlot.children.length === 0
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 260)
                text: rootWindow.title
                color: titanTheme.headerText
                font.pixelSize: 13
                font.weight: Font.Medium
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                opacity: rootWindow.active ? 1.0 : 0.5
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            // Semáforos macOS (grises cuando la ventana no tiene el foco)
            Row {
                id: trafficLightsRow
                x: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                z: 20

                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: rootWindow.active ? "#ff5f57" : "#5c5c60"
                    border.color: rootWindow.active ? "#e0443e" : "#4a4a4e"
                    border.width: 0.5
                    scale: closeMouse.containsMouse ? 1.15 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: closeContainerAnim.start() }
                }

                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: rootWindow.active ? "#febc2e" : "#5c5c60"
                    border.color: rootWindow.active ? "#dea123" : "#4a4a4e"
                    border.width: 0.5
                    scale: minMouse.containsMouse ? 1.15 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    MouseArea {
                        id: minMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: { rootWindow.isMinimizing = true; minimizeContainerAnim.start() }
                    }
                }

                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: rootWindow.active ? "#28c840" : "#5c5c60"
                    border.color: rootWindow.active ? "#1aab29" : "#4a4a4e"
                    border.width: 0.5
                    scale: maxMouse.containsMouse ? 1.15 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    MouseArea { id: maxMouse; anchors.fill: parent; hoverEnabled: true; onClicked: rootWindow.toggleMaximize() }
                }
            }

            // Contenido propio de la barra (toolbar)
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

        // ---------- 2. CUERPO ----------
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
                bottomLeftRadius: rootWindow.showStatusBar ? 0 : rootWindow.cornerRadius

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
                bottomRightRadius: rootWindow.showStatusBar ? 0 : rootWindow.cornerRadius
                bottomLeftRadius: (rootWindow.showSidebar || rootWindow.showStatusBar) ? 0 : rootWindow.cornerRadius

                Item { id: contentSlot; anchors.fill: parent }
            }
        }

        // ---------- 3. BARRA DE ESTADO ----------
        Rectangle {
            id: statusBarPanel
            visible: rootWindow.showStatusBar
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: rootWindow.statusBarHeight
            bottomLeftRadius: rootWindow.cornerRadius
            bottomRightRadius: rootWindow.cornerRadius

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
