import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: workspacesRoot
    anchors.fill: parent

    TitanTheme { id: theme }

    // Fondo oscurecido con desenfoque translúcido estilo macOS
    Rectangle {
        anchors.fill: parent
        color: theme.isDark ? Qt.rgba(0.04, 0.05, 0.07, 0.85) : Qt.rgba(0.08, 0.10, 0.14, 0.72)
        opacity: shellBackend.workspacesVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked: shellBackend.setWorkspacesVisible(false)
        }
    }

    focus: shellBackend.workspacesVisible
    Keys.onEscapePressed: shellBackend.setWorkspacesVisible(false)

    // Contenedor principal sin barras ni cabeceras extra a su alrededor
    Row {
        anchors.fill: parent
        anchors.margins: 40
        spacing: 28

        opacity: shellBackend.workspacesVisible ? 1.0 : 0.0
        scale: shellBackend.workspacesVisible ? 1.0 : 0.95
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.05 } }

        // ── LADO IZQUIERDO (GRANDE): Escritorio Actual (~68%) ──────────────────
        Item {
            id: leftCol
            width: parent.width * 0.68 - 14
            height: parent.height

            Rectangle {
                id: mainScreenCard
                anchors.fill: parent
                radius: 20
                clip: true
                color: "#0d0e12"
                border.color: theme.accent
                border.width: 2.5

                // Fondo de pantalla del escritorio actual
                Image {
                    anchors.fill: parent
                    source: shellBackend.currentWallpaper.length > 0 ? "file://" + shellBackend.currentWallpaper : ""
                    fillMode: Image.PreserveAspectCrop
                    opacity: 0.90
                }

                // Tinte protector
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.30)
                }

                // Barra superior simulada
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 24
                    color: Qt.rgba(0, 0, 0, 0.50)

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3
                            color: "#0a84ff"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: (shellBackend.workspaces[shellBackend.currentWorkspace] !== undefined ? shellBackend.workspaces[shellBackend.currentWorkspace] : ("Escritorio " + (shellBackend.currentWorkspace + 1)))
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                    }
                }

                // Rejilla de ventanas activas del escritorio actual
                Item {
                    anchors.fill: parent
                    anchors.topMargin: 38
                    anchors.bottomMargin: 46
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24

                    GridView {
                        id: activeWinGrid
                        anchors.fill: parent
                        cellWidth: Math.max(180, (width - 20) / Math.max(1, Math.min(3, windowTracker.currentWorkspaceWindows.length)))
                        cellHeight: Math.min(180, height - 10)
                        clip: true
                        model: windowTracker.currentWorkspaceWindows
                        visible: windowTracker.currentWorkspaceWindows.length > 0

                        delegate: Rectangle {
                            id: winCard
                            width: activeWinGrid.cellWidth - 16
                            height: Math.min(170, activeWinGrid.cellHeight - 16)
                            radius: 12
                            color: winMouse.containsMouse ? Qt.rgba(0.18, 0.20, 0.26, 0.95) : Qt.rgba(0.12, 0.14, 0.18, 0.88)
                            border.color: winMouse.containsMouse ? theme.accent : Qt.rgba(1, 1, 1, 0.22)
                            border.width: winMouse.containsMouse ? 2 : 1
                            scale: winMouse.containsMouse ? 1.02 : 1.0
                            clip: true

                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 120 } }

                            // Barra superior de la ventana en miniatura
                            Rectangle {
                                id: cardHeader
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 26
                                color: Qt.rgba(0, 0, 0, 0.35)
                                z: 2

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    // Botón cerrar estilo macOS
                                    Rectangle {
                                        width: 13
                                        height: 13
                                        radius: 6.5
                                        color: closeMouse.containsMouse ? "#ff453a" : Qt.rgba(1, 0.3, 0.3, 0.85)

                                        Text {
                                            anchors.centerIn: parent
                                            text: "✕"
                                            color: "#ffffff"
                                            font.pixelSize: 8
                                            font.bold: true
                                            visible: closeMouse.containsMouse || winMouse.containsMouse
                                        }

                                        MouseArea {
                                            id: closeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                windowTracker.closeWindowById(modelData.id)
                                            }
                                        }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    width: parent.width - 50
                                    text: modelData.title ? modelData.title : (modelData.appId ? modelData.appId : "Ventana")
                                    color: "#ffffff"
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideMiddle
                                }
                            }

                            // Contenido central con icono y nombre
                            Column {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: 10
                                spacing: 8
                                width: parent.width - 24

                                Rectangle {
                                    width: 44; height: 44; radius: 10
                                    color: Qt.rgba(1, 1, 1, 0.10)
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Image {
                                        anchors.centerIn: parent
                                        width: 28
                                        height: 28
                                        source: "qrc:/icons/apps-folder.png"
                                        smooth: true
                                        mipmap: true
                                    }
                                }

                                Text {
                                    text: modelData.title ? modelData.title : (modelData.appId ? modelData.appId : "Ventana")
                                    color: "#e6e6e6"
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideMiddle
                                    width: parent.width
                                }
                            }

                            MouseArea {
                                id: winMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    windowTracker.activateWindowById(modelData.id)
                                    shellBackend.setWorkspacesVisible(false)
                                }
                            }
                        }
                    }

                    // Estado vacío
                    Item {
                        anchors.centerIn: parent
                        visible: windowTracker.currentWorkspaceWindows.length === 0
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            Image {
                                source: "qrc:/icons/desktop.png"
                                width: 56
                                height: 56
                                fillMode: Image.PreserveAspectFit
                                anchors.horizontalCenter: parent.horizontalCenter
                                opacity: 0.85
                                smooth: true
                                mipmap: true
                            }
                            Text {
                                text: (shellBackend.workspaces[shellBackend.currentWorkspace] !== undefined ? shellBackend.workspaces[shellBackend.currentWorkspace] : "Escritorio Actual") + " — Sin aplicaciones"
                                color: "#ffffff"
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }

                // Badge inferior
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: currentBadgeText.implicitWidth + 24
                    height: 26
                    radius: 13
                    color: theme.accent

                    Text {
                        id: currentBadgeText
                        anchors.centerIn: parent
                        text: "● Escritorio Activo (" + (shellBackend.currentWorkspace + 1) + ")"
                        color: "#ffffff"
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                // Clic en el escritorio actual para salir de la vista
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.setWorkspacesVisible(false)
                }
            }
        }

        // ── LADO DERECHO: Lista scrollable de escritorios creados + botón + (~32%) ──
        Item {
            id: rightCol
            width: parent.width * 0.32 - 14
            height: parent.height

            ScrollView {
                id: rightScroll
                anchors.fill: parent
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                Column {
                    id: cardsColumn
                    width: rightCol.width
                    spacing: 16

                    // Lista de escritorios creados
                    Repeater {
                        model: shellBackend.workspaces

                        Rectangle {
                            id: spaceCard
                            width: cardsColumn.width
                            height: 104
                            radius: 14

                            readonly property bool isCurrent: shellBackend.currentWorkspace === index
                            readonly property var wsWindows: windowTracker.windowsForWorkspace(index)

                            color: isCurrent
                                   ? (theme.isDark ? Qt.rgba(0.0, 0.44, 0.89, 0.32) : Qt.rgba(0.0, 0.44, 0.89, 0.18))
                                   : (cardMouse.containsMouse ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : (theme.isDark ? Qt.rgba(0.12, 0.14, 0.18, 0.65) : Qt.rgba(1, 1, 1, 0.65)))

                            border.color: isCurrent ? theme.accent : (cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.14))
                            border.width: isCurrent ? 2 : 1

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            Row {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 14

                                // Miniatura del fondo
                                Rectangle {
                                    width: 108
                                    height: parent.height
                                    radius: 8
                                    clip: true
                                    color: "#161820"
                                    border.color: isCurrent ? theme.accent : Qt.rgba(1, 1, 1, 0.18)
                                    border.width: 1

                                    Image {
                                        anchors.fill: parent
                                        source: shellBackend.currentWallpaper.length > 0 ? "file://" + shellBackend.currentWallpaper : ""
                                        fillMode: Image.PreserveAspectCrop
                                        opacity: 0.80
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: Qt.rgba(0, 0, 0, 0.25)
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: (index + 1)
                                        color: "#ffffff"
                                        font.pixelSize: 18
                                        font.bold: true
                                    }
                                }

                                // Información: Nombre y aplicaciones
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    width: parent.width - 160

                                    Text {
                                        text: modelData
                                        color: "#ffffff"
                                        font.pixelSize: 14
                                        font.weight: isCurrent ? Font.Bold : Font.Medium
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }

                                    Text {
                                        text: wsWindows.length > 0 ? (wsWindows.length + (wsWindows.length === 1 ? " app abierta" : " apps abiertas")) : (isCurrent ? "● Activo ahora" : "Sin aplicaciones")
                                        color: isCurrent ? theme.accent : theme.contentTextSecondary
                                        font.pixelSize: 11
                                    }
                                }

                                // Botón eliminar escritorio
                                Rectangle {
                                    visible: shellBackend.workspaces.length > 1 && !isCurrent
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24; height: 24; radius: 12
                                    color: delSpaceMouse.containsMouse ? "#ff4d4d" : Qt.rgba(1, 1, 1, 0.15)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                    }

                                    MouseArea {
                                        id: delSpaceMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: shellBackend.removeWorkspace(index)
                                    }
                                }
                            }

                            MouseArea {
                                id: cardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: shellBackend.switchToWorkspace(index)
                            }
                        }
                    }

                    // Botón + del mismo tamaño exacto de las tarjetas, ubicado abajo del último escritorio
                    Rectangle {
                        id: addSpaceCard
                        width: cardsColumn.width
                        height: 104
                        radius: 14
                        color: addSpaceMouse.containsMouse
                               ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                               : (theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.03))
                        border.color: addSpaceMouse.containsMouse ? theme.accent : Qt.rgba(1, 1, 1, 0.22)
                        border.width: addSpaceMouse.containsMouse ? 2 : 1

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                width: 36; height: 36; radius: 18
                                color: addSpaceMouse.containsMouse ? theme.accent : Qt.rgba(1, 1, 1, 0.15)
                                anchors.horizontalCenter: parent.horizontalCenter
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: "#ffffff"
                                    font.pixelSize: 22
                                    font.bold: true
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Nuevo Escritorio"
                                color: addSpaceMouse.containsMouse ? "#ffffff" : theme.contentTextSecondary
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                        }

                        MouseArea {
                            id: addSpaceMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shellBackend.addWorkspace()
                        }
                    }
                }
            }
        }
    }
}
