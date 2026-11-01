import QtQuick 2.15
import QtQuick.Controls 2.15

TitanWindow {
    id: finderWindow

    title: "Finder - " + finderBackend.currentPathName
    expandedSidebarWidth: 200
    collapsedSidebarWidth: 54

    // Atajos de teclado estilo macOS
    Shortcut {
        sequence: "Alt+Left"
        onActivated: finderBackend.goBack()
    }
    Shortcut {
        sequence: "Alt+Right"
        onActivated: finderBackend.goForward()
    }
    Shortcut {
        sequence: "Backspace"
        onActivated: finderBackend.goUp()
    }
    Shortcut {
        sequence: "Ctrl+H"
        onActivated: finderBackend.showHiddenFiles = !finderBackend.showHiddenFiles
    }
    Shortcut {
        sequence: "Ctrl+R"
        onActivated: finderBackend.refresh()
    }
    Shortcut {
        sequence: "F5"
        onActivated: finderBackend.refresh()
    }
    Shortcut {
        sequence: "Ctrl+T"
        onActivated: finderBackend.openTerminal()
    }
    Shortcut {
        sequence: "Ctrl+Shift+N"
        onActivated: fileList.openNewFolderDialog()
    }

    // 1. CONTENIDO DE LA BARRA SUPERIOR (TOOLBAR / PANEL NORMAL CON BLUR)
    headerContentData: Item {
        anchors.fill: parent

        // Izquierda: Botón Sidebar, Navegación y Título de carpeta
        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // Botón para comprimir / expandir la barra lateral
            Rectangle {
                width: 28; height: 26; radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: sidebarToggleMouse.containsMouse ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                border.color: theme.glassBorder
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 2
                    Rectangle {
                        width: 5; height: 12; radius: 1
                        color: !finderWindow.sidebarCollapsed ? theme.accent : theme.contentTextSecondary
                    }
                    Rectangle {
                        width: 10; height: 12; radius: 1
                        color: "transparent"
                        border.color: !finderWindow.sidebarCollapsed ? theme.accent : theme.contentTextSecondary
                        border.width: 1
                    }
                }

                MouseArea {
                    id: sidebarToggleMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: finderWindow.sidebarCollapsed = !finderWindow.sidebarCollapsed
                }
            }

            // Botones de Navegación (Atrás, Adelante, Subir)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                // Botón Atrás
                Rectangle {
                    width: 28; height: 26; radius: 5
                    color: backMouse.containsMouse && finderBackend.canGoBack ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                    opacity: finderBackend.canGoBack ? 1.0 : 0.35

                    Text {
                        anchors.centerIn: parent
                        text: "‹"
                        color: theme.headerText
                        font.pixelSize: 18
                        font.bold: true
                    }

                    MouseArea {
                        id: backMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: finderBackend.canGoBack ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: finderBackend.goBack()
                    }
                }

                // Botón Adelante
                Rectangle {
                    width: 28; height: 26; radius: 5
                    color: fwdMouse.containsMouse && finderBackend.canGoForward ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                    opacity: finderBackend.canGoForward ? 1.0 : 0.35

                    Text {
                        anchors.centerIn: parent
                        text: "›"
                        color: theme.headerText
                        font.pixelSize: 18
                        font.bold: true
                    }

                    MouseArea {
                        id: fwdMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: finderBackend.canGoForward ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: finderBackend.goForward()
                    }
                }

                // Botón Subir nivel
                Rectangle {
                    width: 28; height: 26; radius: 5
                    color: upMouse.containsMouse && finderBackend.canGoUp ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                    opacity: finderBackend.canGoUp ? 1.0 : 0.35

                    Text {
                        anchors.centerIn: parent
                        text: "▲"
                        color: theme.headerText
                        font.pixelSize: 10
                    }

                    MouseArea {
                        id: upMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: finderBackend.canGoUp ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: finderBackend.goUp()
                    }
                }
            }

            // Título de la carpeta activa
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: finderBackend.currentPathName
                color: theme.headerText
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideRight
                width: Math.min(160, implicitWidth)
            }
        }

        // Centro: Barra de búsqueda Spotlight con soporte completo de modo oscuro/claro
        Rectangle {
            anchors.centerIn: parent
            width: Math.max(180, Math.min(260, parent.width - 440))
            height: 28
            radius: 7
            color: theme.isDark ? "#24252a" : "#ffffff"
            border.color: searchInput.activeFocus ? theme.accent : theme.glassBorder
            border.width: searchInput.activeFocus ? 1.5 : 1

            Behavior on border.color { ColorAnimation { duration: 140 } }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                Item {
                    width: 14; height: 14
                    anchors.verticalCenter: parent.verticalCenter

                    Canvas {
                        id: searchIcon
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            ctx.strokeStyle = searchInput.activeFocus ? theme.accent : theme.contentTextSecondary;
                            ctx.lineWidth = 1.6;
                            ctx.lineCap = "round";

                            ctx.beginPath();
                            ctx.arc(5.5, 5.5, 4.0, 0, Math.PI * 2);
                            ctx.stroke();

                            ctx.beginPath();
                            ctx.moveTo(8.5, 8.5);
                            ctx.lineTo(12.5, 12.5);
                            ctx.stroke();
                        }
                        Connections {
                            target: searchInput
                            function onActiveFocusChanged() { searchIcon.requestPaint(); }
                        }
                    }
                }

                TextField {
                    id: searchInput
                    width: parent.width - 38
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "Buscar..."
                    font.pixelSize: 11
                    color: theme.contentTextPrimary
                    background: null
                    placeholderTextColor: theme.contentTextSecondary
                    text: finderBackend.searchQuery
                    onTextChanged: finderBackend.searchQuery = text
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text.length > 0
                    text: "✕"
                    color: theme.contentTextSecondary
                    font.pixelSize: 10
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: searchInput.text = ""
                    }
                }
            }
        }

        // Derecha: Botones de acciones
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            // Botón Nueva Carpeta (+)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 26; radius: 5
                color: newFolderMouse.containsMouse ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                border.color: theme.glassBorder
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: theme.headerText
                    font.pixelSize: 16
                    font.bold: true
                }

                MouseArea {
                    id: newFolderMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fileList.openNewFolderDialog()
                }
            }

            // Botón Abrir Terminal (>_)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 26; radius: 5
                color: termMouse.containsMouse ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                border.color: theme.glassBorder
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: ">_"
                    color: theme.accent
                    font.pixelSize: 11
                    font.bold: true
                }

                MouseArea {
                    id: termMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: finderBackend.openTerminal()
                }
            }

            // Botón Archivos Ocultos (.*)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 26; radius: 5
                color: finderBackend.showHiddenFiles ? theme.accent :
                       hiddenMouse.containsMouse ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                border.color: finderBackend.showHiddenFiles ? theme.accent : theme.glassBorder
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: ".*"
                    color: finderBackend.showHiddenFiles ? "#ffffff" : theme.headerText
                    font.pixelSize: 12
                    font.bold: true
                }

                MouseArea {
                    id: hiddenMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: finderBackend.showHiddenFiles = !finderBackend.showHiddenFiles
                }
            }
        }
    }

    // 2. SIDEBAR TRANSLÚCIDO
    sidebarContentData: Sidebar {
        anchors.fill: parent
    }

    // 3. CONTENIDO CENTRAL SÓLIDO BLANCO
    FileList {
        id: fileList
        anchors.fill: parent
    }

    // 4. BARRA DE ESTADO INFERIOR
    statusBarContentData: Item {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        // Segmentos interactivos de la ruta
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            width: parent.width - 240

            Repeater {
                model: finderBackend.pathSegments
                delegate: Row {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: modelData.name
                        color: segMouse.containsMouse ? theme.accent : theme.contentTextSecondary
                        font.pixelSize: 10
                        font.weight: index === finderBackend.pathSegments.length - 1 ? Font.Bold : Font.Normal

                        MouseArea {
                            id: segMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: finderBackend.goTo(modelData.path)
                        }
                    }

                    Text {
                        visible: index < finderBackend.pathSegments.length - 1
                        text: "›"
                        color: Qt.rgba(0, 0, 0, 0.25)
                        font.pixelSize: 10
                    }
                }
            }
        }

        Item { width: 10; height: 1 }

        // Cantidad de elementos y espacio libre
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            spacing: 12

            Text {
                text: finderBackend.totalItemsText
                color: theme.contentTextSecondary
                font.pixelSize: 10
            }

            Text {
                text: "•"
                color: Qt.rgba(0, 0, 0, 0.25)
                font.pixelSize: 10
            }

            Text {
                text: finderBackend.freeSpaceText
                color: theme.contentTextSecondary
                font.pixelSize: 10
            }
        }
    }
}
