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

    TitanTheme {
        id: titanTheme
        effects: windowContainer.GraphicsInfo.api !== GraphicsInfo.Software
    }

    // Paleta de los controles estándar (estilo Basic) según el tema: sin esto,
    // ComboBox, TextField, etc. salen con la paleta clara por defecto de Qt
    // aunque el tema sea oscuro, o con colores fijos que no se leen en el claro.
    palette.window: titanTheme.isDark ? "#1c1d22" : "#f5f5f7"
    palette.windowText: titanTheme.contentTextPrimary
    palette.base: titanTheme.isDark ? "#26272d" : "#ffffff"
    palette.alternateBase: titanTheme.isDark ? "#2c2d33" : "#f2f2f5"
    palette.text: titanTheme.contentTextPrimary
    palette.placeholderText: titanTheme.contentTextSecondary
    palette.button: titanTheme.isDark ? "#3a3b41" : "#ffffff"
    palette.buttonText: titanTheme.contentTextPrimary
    palette.highlight: titanTheme.accent
    palette.highlightedText: "#ffffff"
    palette.light: titanTheme.isDark ? "#4a4b52" : "#ffffff"
    palette.midlight: titanTheme.isDark ? "#3a3b41" : "#e8e8ed"
    palette.mid: titanTheme.isDark ? "#55565c" : "#c7c7cc"
    palette.dark: titanTheme.isDark ? "#101114" : "#a1a1a6"
    palette.shadow: "#000000"
    palette.toolTipBase: titanTheme.isDark ? "#2c2d33" : "#ffffff"
    palette.toolTipText: titanTheme.contentTextPrimary

    // Barra lateral flotante (estilo Tahoe): una tarjeta separada del borde.
    readonly property int sidebarInset: 7
    readonly property real sidebarCardRadius: Math.max(titanTheme.controlRadius, titanTheme.windowRadius - sidebarInset + 2)

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
            effects: titanTheme.effects
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

            // Título de la ventana, centrado
            Text {
                id: titleText
                visible: rootWindow.showTitle && headerSlot.children.length === 0
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 260)
                text: rootWindow.title
                color: titanTheme.headerText
                font.family: titanTheme.fontFamily
                font.pixelSize: titanTheme.fontBody
                font.weight: Font.Medium
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                opacity: rootWindow.active ? 1.0 : 0.5
                Behavior on opacity { NumberAnimation { duration: 150 } }
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

            // Hueco que reserva la barra lateral; la tarjeta visible es sidebarCard.
            Item {
                id: sidebarPanel
                visible: rootWindow.effectiveSidebarWidth > 0
                width: rootWindow.effectiveSidebarWidth
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
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

        // ---------- 2b. BARRA LATERAL FLOTANTE ----------
        // Cubre también la zona de la cabecera (los semáforos quedan dentro, como
        // en Tahoe). El contenido de la app empieza debajo de la cabecera, igual
        // que antes, para no mover lo que ya dibujan las apps.
        Rectangle {
            id: sidebarCard
            visible: rootWindow.effectiveSidebarWidth > 0
            z: 15
            x: rootWindow.sidebarInset
            y: rootWindow.sidebarInset
            width: Math.max(0, rootWindow.effectiveSidebarWidth - rootWindow.sidebarInset)
            height: (rootWindow.showStatusBar ? statusBarPanel.y : parent.height) - y - rootWindow.sidebarInset
            radius: rootWindow.sidebarCardRadius
            clip: true
            gradient: Gradient {
                GradientStop { position: 0.0; color: rootWindow.glass(titanTheme.sidebarTop, Math.min(0.92, rootWindow.sidebarGlass + 0.2)) }
                GradientStop { position: 1.0; color: rootWindow.glass(titanTheme.sidebarBottom, Math.min(0.92, rootWindow.sidebarGlass + 0.2)) }
            }
            border.color: titanTheme.sidebarBorder
            border.width: 1

            // Luz en el borde superior de la tarjeta
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - parent.radius * 2
                height: 1
                color: titanTheme.specularGlow
                opacity: titanTheme.isDark ? 0.5 : 0.9
            }

            // La tarjeta tapa la cabecera en su zona: ahí también se arrastra la ventana.
            MouseArea {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: headerPanel.height - rootWindow.sidebarInset
                onPressed: rootWindow.startSystemMove()
                onDoubleClicked: rootWindow.toggleMaximize()
            }

            Item {
                id: sidebarSlot
                anchors.fill: parent
                anchors.topMargin: headerPanel.height - rootWindow.sidebarInset
            }
        }

        // Semáforos (grises cuando la ventana no tiene el foco). Como en macOS,
        // al pasar el ratón por el grupo aparecen los símbolos de los tres.
        Row {
            id: trafficLightsRow
            x: 18
            y: Math.round((headerPanel.height - height) / 2)
            spacing: 8
            z: 30

            HoverHandler { id: lightsHover }

            Repeater {
                model: [
                    { col: "#ff5f57", edge: "#e0443e", glyph: "\u00d7", act: "close" },
                    { col: "#febc2e", edge: "#dea123", glyph: "\u2212", act: "min" },
                    { col: "#28c840", edge: "#1aab29", glyph: "+",      act: "max" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool lit: rootWindow.active || lightsHover.hovered
                    width: 12; height: 12; radius: 6
                    color: lit ? modelData.col : (titanTheme.isDark ? "#5c5c60" : "#c8c8cc")
                    border.color: lit ? modelData.edge : (titanTheme.isDark ? "#4a4a4e" : "#b4b4b8")
                    border.width: 0.5
                    scale: lightMouse.pressed ? 0.9 : 1.0
                    Behavior on scale { NumberAnimation { duration: 90 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -0.5
                        text: modelData.glyph
                        visible: lightsHover.hovered
                        color: Qt.rgba(0, 0, 0, 0.6)
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: lightMouse
                        anchors.fill: parent
                        onClicked: {
                            if (modelData.act === "close") closeContainerAnim.start()
                            else if (modelData.act === "min") { rootWindow.isMinimizing = true; minimizeContainerAnim.start() }
                            else rootWindow.toggleMaximize()
                        }
                    }
                }
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
