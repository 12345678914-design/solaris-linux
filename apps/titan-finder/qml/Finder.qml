import QtQuick 2.15
import QtQuick.Controls 2.15

TitanWindow {
    id: finderWindow

    title: (finderBackend.enPapelera ? "Papelera" : finderBackend.currentPathName) + " — Explorador de archivos"
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
    Shortcut { sequence: "Ctrl+I"; onActivated: fileList.openProperties(fileList.selectedPath) }
    Shortcut { sequence: "Alt+P"; onActivated: finderBackend.panelDetalles = !finderBackend.panelDetalles }
    Shortcut { sequences: ["Ctrl+L", "Alt+D"]; onActivated: direccion.editar() }
    Shortcut { sequences: ["Ctrl+F", "Ctrl+E"]; onActivated: searchInput.forceActiveFocus() }

    component BotonNav: Rectangle {
        id: bn
        property string icono: ""
        property bool activo: true
        property string pista: ""
        signal pulsado()
        width: 30; height: 28; radius: 6
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        opacity: activo ? 1 : 0.35
        color: zn.containsMouse && activo ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.07)) : "transparent"
        Icono { anchors.centerIn: parent; nombre: bn.icono; color: theme.headerText }
        MouseArea {
            id: zn
            anchors.fill: parent
            hoverEnabled: true
            enabled: bn.activo
            cursorShape: bn.activo ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: bn.pulsado()
        }
        ToolTip.visible: zn.containsMouse && pista !== ""
        ToolTip.delay: 600
        ToolTip.text: pista
    }

    // 1. BARRA SUPERIOR: navegación, dirección (ruta en botones) y búsqueda
    headerContentData: Item {
        anchors.fill: parent

        Row {
            id: navegacion
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            BotonNav {
                icono: "panel"; pista: "Mostrar u ocultar el panel de navegación"
                onPulsado: finderWindow.sidebarCollapsed = !finderWindow.sidebarCollapsed
            }
            Item { width: 6; height: 1 }
            BotonNav { icono: "atras"; activo: finderBackend.canGoBack; pista: "Atrás (Alt+←)"; onPulsado: finderBackend.goBack() }
            BotonNav { icono: "adelante"; activo: finderBackend.canGoForward; pista: "Adelante (Alt+→)"; onPulsado: finderBackend.goForward() }
            BotonNav { icono: "arriba"; activo: finderBackend.canGoUp; pista: "Subir un nivel"; onPulsado: finderBackend.goUp() }
            BotonNav { icono: "recargar"; pista: "Actualizar (F5)"; onPulsado: finderBackend.refresh() }
        }

        // Dirección: la ruta en botones; con un clic en el hueco se escribe
        Rectangle {
            id: direccion
            anchors.left: navegacion.right
            anchors.leftMargin: 10
            anchors.right: buscador.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 30
            radius: 7
            color: theme.isDark ? "#1c1c1f" : "#ffffff"
            border.color: campoRuta.activeFocus ? theme.accent : theme.glassBorder
            border.width: campoRuta.activeFocus ? 1.5 : 1
            property bool escribiendo: false
            function editar() {
                campoRuta.text = finderBackend.currentPath
                escribiendo = true
                campoRuta.forceActiveFocus()
                campoRuta.selectAll()
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onClicked: direccion.editar()
            }
            Icono {
                id: icDir
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                nombre: "casa"
                color: theme.contentTextSecondary
            }
            Flickable {
                id: migas
                visible: !direccion.escribiendo
                anchors.left: icDir.right
                anchors.leftMargin: 4
                anchors.right: parent.right
                anchors.rightMargin: 6
                height: parent.height
                contentWidth: filaMigas.width
                clip: true
                interactive: false
                // Si la ruta no cabe se ve el final (la carpeta actual)
                contentX: Math.max(0, contentWidth - width)
                Row {
                    id: filaMigas
                    height: parent.height
                    Repeater {
                        model: finderBackend.enPapelera ? [{ name: "Papelera", path: finderBackend.currentPath }] : finderBackend.pathSegments
                        delegate: Row {
                            required property var modelData
                            required property int index
                            height: filaMigas.height
                            Text {
                                visible: index > 0
                                text: "›"
                                color: theme.contentTextSecondary
                                font.pixelSize: 14
                                anchors.verticalCenter: parent.verticalCenter
                                leftPadding: 1; rightPadding: 1
                            }
                            Rectangle {
                                height: 22; radius: 5
                                width: miga.implicitWidth + 12
                                anchors.verticalCenter: parent.verticalCenter
                                color: zMiga.containsMouse ? theme.itemHover : "transparent"
                                Text {
                                    id: miga
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    color: theme.contentTextPrimary
                                    font.pixelSize: 12
                                    font.weight: index === finderBackend.pathSegments.length - 1 ? Font.DemiBold : Font.Normal
                                }
                                MouseArea {
                                    id: zMiga
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: finderBackend.goTo(modelData.path)
                                }
                            }
                        }
                    }
                }
            }
            TextField {
                id: campoRuta
                visible: direccion.escribiendo
                anchors.left: icDir.right
                anchors.leftMargin: 4
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 12
                color: theme.contentTextPrimary
                background: null
                selectByMouse: true
                onAccepted: { finderBackend.goTo(text.trim()); direccion.escribiendo = false; fileList.forceActiveFocus() }
                onActiveFocusChanged: if (!activeFocus) direccion.escribiendo = false
                Keys.onEscapePressed: { direccion.escribiendo = false; fileList.forceActiveFocus() }
            }
        }

        // Búsqueda en la carpeta abierta
        Rectangle {
            id: buscador
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(150, Math.min(250, parent.width * 0.28))
            height: 30
            radius: 7
            color: theme.isDark ? "#1c1c1f" : "#ffffff"
            border.color: searchInput.activeFocus ? theme.accent : theme.glassBorder
            border.width: searchInput.activeFocus ? 1.5 : 1
            Behavior on border.color { ColorAnimation { duration: 140 } }

            Icono {
                id: icLupa
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                nombre: "lupa"
                color: searchInput.activeFocus ? theme.accent : theme.contentTextSecondary
            }
            TextField {
                id: searchInput
                anchors.left: icLupa.right
                anchors.leftMargin: 4
                anchors.right: borrarBusqueda.left
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: "Buscar en " + (finderBackend.enPapelera ? "Papelera" : finderBackend.currentPathName)
                font.pixelSize: 12
                color: theme.contentTextPrimary
                background: null
                placeholderTextColor: theme.contentTextSecondary
                text: finderBackend.searchQuery
                onTextChanged: finderBackend.searchQuery = text
                Keys.onEscapePressed: { text = ""; fileList.forceActiveFocus() }
            }
            Text {
                id: borrarBusqueda
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: searchInput.text.length > 0 ? implicitWidth : 0
                visible: searchInput.text.length > 0
                text: "✕"
                color: theme.contentTextSecondary
                font.pixelSize: 11
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: searchInput.text = ""
                }
            }
        }
    }

    // 2. PANEL DE NAVEGACIÓN (acceso rápido, este equipo, dispositivos)
    sidebarContentData: Sidebar {
        anchors.fill: parent
    }

    // 3. CONTENIDO: barra de comandos, archivos y panel de detalles
    Item {
        anchors.fill: parent

        BarraComandos {
            id: comandos
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            lista: fileList
            z: 2
        }

        FileList {
            id: fileList
            anchors.top: comandos.bottom
            anchors.left: parent.left
            anchors.right: detalles.visible ? detalles.left : parent.right
            anchors.bottom: parent.bottom
        }

        PanelDetalles {
            id: detalles
            visible: finderBackend.panelDetalles && parent.width > 620
            anchors.top: comandos.bottom
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.min(290, Math.max(230, parent.width * 0.3))
            lista: fileList
        }
    }

    // 4. BARRA DE ESTADO: elementos, selección y espacio libre
    statusBarContentData: Item {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: finderBackend.totalItemsText
                  + (fileList.nSel > 0 ? "      " + fileList.nSel + (fileList.nSel === 1 ? " elemento seleccionado" : " elementos seleccionados") : "")
            color: theme.contentTextSecondary
            font.pixelSize: 11
        }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            spacing: 12
            BotonNav {
                width: 24; height: 20
                icono: "iconos"; pista: "Iconos grandes"
                color: finderBackend.viewMode === "grid" ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.25) : "transparent"
                onPulsado: finderBackend.viewMode = "grid"
            }
            BotonNav {
                width: 24; height: 20
                icono: "lista"; pista: "Lista con detalles"
                color: finderBackend.viewMode === "list" ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.25) : "transparent"
                onPulsado: finderBackend.viewMode = "list"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: finderBackend.freeSpaceText
                color: theme.contentTextSecondary
                font.pixelSize: 11
            }
        }
    }
}
