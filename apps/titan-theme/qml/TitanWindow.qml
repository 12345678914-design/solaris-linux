import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

Window {
    id: rootWindow

    default property alias mainContentData: contentSlot.data
    property alias headerContentData: headerSlot.data
    property alias sidebarContentData: sidebarSlot.data
    property alias statusBarContentData: statusBarSlot.data

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

    // Transiciones fluidas de contenedor elástico de macOS
    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on x { enabled: !rootWindow.isDragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !rootWindow.isDragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Rectangle {
        id: windowContainer
        anchors.fill: parent
        radius: rootWindow.visibility === Window.Maximized ? 0 : titanTheme.windowRadius
        border.color: titanTheme.glassBorder
        border.width: 1
        clip: true

        // Fondo de cristal translúcido con degradado acrílico (sin color sólido opaco)
        gradient: Gradient {
            GradientStop { position: 0.0; color: titanTheme.windowBgTop }
            GradientStop { position: 0.5; color: titanTheme.windowBgMid }
            GradientStop { position: 1.0; color: titanTheme.windowBgBottom }
        }

        // Brillo especular superior del cristal estilo macOS
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 32
            height: 1
            color: titanTheme.specularGlow
            z: 25
        }

        // Animación de contenedor estilo macOS al abrir y minimizar
        opacity: rootWindow.isMinimizing ? 0.0 : 1.0
        scale: rootWindow.isMinimizing ? 0.85 : 1.0
        transformOrigin: Item.Bottom

        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Component.onCompleted: openContainerAnim.start()

        // Animación elástica de apertura de contenedor macOS
        ParallelAnimation {
            id: openContainerAnim
            NumberAnimation {
                target: windowContainer
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: 220
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: windowContainer
                property: "scale"
                from: 0.94
                to: 1.0
                duration: 240
                easing.type: Easing.OutBack
                easing.overshoot: 1.06
            }
        }

        // Animación de cierre suave
        SequentialAnimation {
            id: closeContainerAnim
            ParallelAnimation {
                NumberAnimation { target: windowContainer; property: "opacity"; to: 0.0; duration: 150; easing.type: Easing.InCubic }
                NumberAnimation { target: windowContainer; property: "scale"; to: 0.94; duration: 150; easing.type: Easing.InCubic }
            }
            ScriptAction { script: rootWindow.close() }
        }

        // Animación de minimizar estilo contenedor
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

        // 1. PANEL SUPERIOR / TOOLBAR CON DEGRADADO BLUR TRASLÚCIDO
        Rectangle {
            id: headerPanel
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 50
            z: 10

            gradient: Gradient {
                GradientStop { position: 0.0; color: titanTheme.headerTop }
                GradientStop { position: 1.0; color: titanTheme.headerBottom }
            }

            // Borde inferior sutil
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: titanTheme.headerBorder
            }

            // Arrastre nativo de ventanas para Wayland (startSystemMove) y X11
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                property point pressPos
                property bool systemMoveStarted: false

                onPressed: {
                    pressPos = Qt.point(mouse.x, mouse.y)
                    systemMoveStarted = false
                }

                onPositionChanged: {
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

                onReleased: {
                    rootWindow.isDragging = false
                    systemMoveStarted = false
                }
                onCanceled: {
                    rootWindow.isDragging = false
                    systemMoveStarted = false
                }
                onDoubleClicked: toggleMaximize()
            }

            // Fondo de la zona de sidebar en el header (unificado con el sidebar lateral)
            Rectangle {
                visible: rootWindow.effectiveSidebarWidth > 0
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: rootWindow.effectiveSidebarWidth
                clip: true
                gradient: Gradient {
                    GradientStop { position: 0.0; color: titanTheme.sidebarTop }
                    GradientStop { position: 1.0; color: titanTheme.sidebarBottom }
                }
                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: titanTheme.sidebarBorder
                }
            }

            // Botones Traffic Lights de macOS (Cerrar, Minimizar, Maximizar)
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
                    MouseArea {
                        id: closeMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: closeContainerAnim.start()
                    }
                }

                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: "#febc2e"; border.color: "#dea123"; border.width: 0.5
                    scale: minMouse.containsMouse ? 1.15 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }
                    MouseArea {
                        id: minMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            rootWindow.isMinimizing = true
                            minimizeContainerAnim.start()
                        }
                    }
                }

                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: "#28c840"; border.color: "#1aab29"; border.width: 0.5
                    scale: maxMouse.containsMouse ? 1.15 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }
                    MouseArea {
                        id: maxMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: toggleMaximize()
                    }
                }
            }

            // Contenedor para el contenido específico de la cabecera (toolbar alineado)
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

        // 2. CUERPO DE LA APLICACIÓN (SIDEBAR TRANSLÚCIDO + CONTENIDO TRANSLÚCIDO)
        Item {
            id: bodyContainer
            anchors.top: headerPanel.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: showStatusBar ? statusBarPanel.top : parent.bottom

            // SIDEBAR TRASLÚCIDO CON EFECTO BLUR ACRÍLICO
            Rectangle {
                id: sidebarPanel
                visible: rootWindow.effectiveSidebarWidth > 0
                width: rootWindow.effectiveSidebarWidth
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                clip: true

                gradient: Gradient {
                    GradientStop { position: 0.0; color: titanTheme.sidebarTop }
                    GradientStop { position: 1.0; color: titanTheme.sidebarBottom }
                }

                // Borde divisor derecho
                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: titanTheme.sidebarBorder
                }

                Item {
                    id: sidebarSlot
                    anchors.fill: parent
                }
            }

            // CONTENIDO CENTRAL TRANSLÚCIDO (SIN COLOR SÓLIDO OPACO)
            Rectangle {
                id: contentPanel
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: rootWindow.showSidebar ? sidebarPanel.right : parent.left
                anchors.right: parent.right
                color: titanTheme.contentBackground

                Item {
                    id: contentSlot
                    anchors.fill: parent
                }
            }
        }

        // 3. BARRA DE ESTADO / FOOTER INFERIOR (Translúcida)
        Rectangle {
            id: statusBarPanel
            visible: rootWindow.showStatusBar
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: rootWindow.statusBarHeight

            gradient: Gradient {
                GradientStop { position: 0.0; color: titanTheme.sidebarTop }
                GradientStop { position: 1.0; color: titanTheme.sidebarBottom }
            }

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: titanTheme.sidebarBorder
            }

            Item {
                id: statusBarSlot
                anchors.fill: parent
            }
        }
    }

    function toggleMaximize() {
        if (rootWindow.visibility === Window.Maximized) {
            rootWindow.showNormal()
        } else {
            rootWindow.showMaximized()
        }
    }
}
