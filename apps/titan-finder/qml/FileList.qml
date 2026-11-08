import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: fileListRoot

    TitanTheme { id: theme }

    color: theme.contentBackground

    property string selectedPath: ""
    property string selectedName: ""
    property bool selectedIsDir: false
    property var itemProperties: ({})

    property bool ctxVisible: false
    property real ctxX: 0
    property real ctxY: 0

    function showContextMenu(posX, posY) {
        ctxX = Math.max(10, Math.min(fileListRoot.width - 230, posX))
        ctxY = Math.max(10, Math.min(fileListRoot.height - 250, posY))
        ctxVisible = true
    }

    function openProperties(path) {
        var target = path && path.length > 0 ? path : (fileListRoot.selectedPath.length > 0 ? fileListRoot.selectedPath : finderBackend.currentPath);
        itemProperties = finderBackend.getFileProperties(target);
        propertiesDialog.open();
    }

    function openNewFolderDialog() {
        folderNameField.text = "Nueva carpeta"
        newFolderDialog.open()
        folderNameField.forceActiveFocus()
        folderNameField.selectAll()
    }

    // Área de recepción de archivos arrastrados hacia Finder
    DropArea {
        id: finderDropArea
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: (drop) => {
            if (drop.hasUrls) {
                for (var i = 0; i < drop.urls.length; ++i) {
                    finderBackend.importFile(drop.urls[i], finderBackend.currentPath)
                }
                drop.acceptProposedAction()
            }
        }
    }

    // Diálogo para renombrar archivo o carpeta estilo macOS
    Dialog {
        id: renameDialog
        anchors.centerIn: parent
        width: 360
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0
        header: null
        footer: null

        background: Rectangle {
            color: theme.isDark ? "#24252a" : "#ffffff"
            radius: 14
            border.color: theme.glassBorder
            border.width: 1
        }

        contentItem: Column {
            padding: 20
            spacing: 14

            Row {
                spacing: 12
                anchors.horizontalCenter: parent.horizontalCenter

                Image {
                    source: fileListRoot.selectedIsDir ? "qrc:/icons/folder.png" : "qrc:/icons/notes.png"
                    width: 36
                    height: 36
                    fillMode: Image.PreserveAspectFit
                }

                Column {
                    spacing: 3
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "Renombrar elemento"
                        color: theme.contentTextPrimary
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Text {
                        text: "Introduce el nuevo nombre:"
                        color: theme.contentTextSecondary
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                width: parent.width - 40
                height: 32
                anchors.horizontalCenter: parent.horizontalCenter
                radius: 6
                color: theme.isDark ? "#1a1b1f" : "#f5f5f7"
                border.color: renameField.activeFocus ? theme.accent : theme.glassBorder
                border.width: renameField.activeFocus ? 2 : 1

                TextField {
                    id: renameField
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    text: fileListRoot.selectedName
                    color: theme.contentTextPrimary
                    font.pixelSize: 12
                    background: null
                    verticalAlignment: Text.AlignVCenter
                    selectByMouse: true

                    Keys.onReturnPressed: renameDialog.accept()
                    Keys.onEnterPressed: renameDialog.accept()
                    Keys.onEscapePressed: renameDialog.reject()
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                spacing: 10

                // Botón Cancelar
                Rectangle {
                    width: 78
                    height: 28
                    radius: 6
                    color: cancelRenameMouse.containsMouse ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : (theme.isDark ? "#2e2f36" : "#f5f5f7")
                    border.color: theme.glassBorder
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Cancelar"
                        color: theme.contentTextPrimary
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: cancelRenameMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: renameDialog.reject()
                    }
                }

                // Botón Aceptar / Renombrar
                Rectangle {
                    width: 86
                    height: 28
                    radius: 6
                    color: okRenameMouse.pressed ? "#005bb5" : okRenameMouse.containsMouse ? "#0077ed" : "#0071e3"

                    Text {
                        anchors.centerIn: parent
                        text: "Aceptar"
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    MouseArea {
                        id: okRenameMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: renameDialog.accept()
                    }
                }
            }
        }

        onAccepted: {
            if (renameField.text.trim().length > 0) {
                finderBackend.renameItem(fileListRoot.selectedPath, renameField.text.trim())
            }
        }
    }

    // Diálogo para crear nueva carpeta estilo macOS (modal card blanco, bordes redondeados y botón Crear azul)
    Dialog {
        id: newFolderDialog
        anchors.centerIn: parent
        width: 360
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0
        header: null
        footer: null

        background: Rectangle {
            color: theme.isDark ? "#24252a" : "#ffffff"
            radius: 14
            border.color: theme.glassBorder
            border.width: 1
        }

        contentItem: Column {
            padding: 20
            spacing: 14

            Row {
                spacing: 12
                anchors.horizontalCenter: parent.horizontalCenter

                Image {
                    source: "qrc:/icons/folder.png"
                    width: 38
                    height: 38
                    fillMode: Image.PreserveAspectFit
                }

                Column {
                    spacing: 3
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "Nueva carpeta"
                        color: theme.contentTextPrimary
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Text {
                        text: "Introduce el nombre de la carpeta:"
                        color: theme.contentTextSecondary
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                width: parent.width - 40
                height: 32
                anchors.horizontalCenter: parent.horizontalCenter
                radius: 6
                color: theme.isDark ? "#1a1b1f" : "#f5f5f7"
                border.color: folderNameField.activeFocus ? theme.accent : theme.glassBorder
                border.width: folderNameField.activeFocus ? 2 : 1

                TextField {
                    id: folderNameField
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    text: "Nueva carpeta"
                    color: theme.contentTextPrimary
                    font.pixelSize: 12
                    background: null
                    verticalAlignment: Text.AlignVCenter
                    selectByMouse: true

                    Keys.onReturnPressed: newFolderDialog.accept()
                    Keys.onEnterPressed: newFolderDialog.accept()
                    Keys.onEscapePressed: newFolderDialog.reject()
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                spacing: 10

                // Botón Cancelar
                Rectangle {
                    width: 78
                    height: 28
                    radius: 6
                    color: cancelFolderMouse.containsMouse ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : (theme.isDark ? "#2e2f36" : "#f5f5f7")
                    border.color: theme.glassBorder
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Cancelar"
                        color: theme.contentTextPrimary
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: cancelFolderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: newFolderDialog.reject()
                    }
                }

                // Botón Crear (macOS blue)
                Rectangle {
                    width: 86
                    height: 28
                    radius: 6
                    color: okFolderMouse.pressed ? "#005bb5" : okFolderMouse.containsMouse ? "#0077ed" : "#0071e3"

                    Text {
                        anchors.centerIn: parent
                        text: "Crear"
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    MouseArea {
                        id: okFolderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: newFolderDialog.accept()
                    }
                }
            }
        }

        onAccepted: {
            finderBackend.createFolder(folderNameField.text.trim())
        }
    }

    // Diálogo "Obtener información / Propiedades" estilo macOS Liquid Glass
    Dialog {
        id: propertiesDialog
        anchors.centerIn: parent
        width: 380
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0
        header: null
        footer: null

        background: Rectangle {
            color: theme.isDark ? "#24252a" : "#ffffff"
            radius: 14
            border.color: theme.glassBorder
            border.width: 1
        }

        contentItem: Column {
            padding: 20
            spacing: 14
            width: parent.width

            // Cabecera con icono grande y nombre
            Row {
                spacing: 14
                width: parent.width - 40
                anchors.horizontalCenter: parent.horizontalCenter

                Image {
                    source: itemProperties.icon ? itemProperties.icon : "qrc:/icons/files.png"
                    width: 48
                    height: 48
                    fillMode: Image.PreserveAspectFit
                }

                Column {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 62

                    Text {
                        text: itemProperties.name ? itemProperties.name : "Propiedades"
                        color: theme.contentTextPrimary
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideMiddle
                        width: parent.width
                    }

                    Text {
                        text: itemProperties.type ? itemProperties.type : ""
                        color: theme.contentTextSecondary
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                width: parent.width - 40
                height: 1
                color: theme.glassBorder
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Datos detallados del archivo o directorio
            Column {
                width: parent.width - 40
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                // Tamaño
                Row {
                    spacing: 10
                    width: parent.width
                    Text { width: 90; text: "Tamaño:"; color: theme.contentTextSecondary; font.pixelSize: 11; font.bold: true }
                    Text { width: parent.width - 100; text: itemProperties.size ? (itemProperties.isDir ? "--" : (itemProperties.size + " (" + itemProperties.bytes + ")")) : "--"; color: theme.contentTextPrimary; font.pixelSize: 11; elide: Text.ElideRight }
                }

                // Ubicación
                Row {
                    spacing: 10
                    width: parent.width
                    Text { width: 90; text: "Ubicación:"; color: theme.contentTextSecondary; font.pixelSize: 11; font.bold: true }
                    Text { width: parent.width - 100; text: itemProperties.dir ? itemProperties.dir : "--"; color: theme.contentTextPrimary; font.pixelSize: 11; elide: Text.ElideMiddle }
                }

                // Modificado
                Row {
                    spacing: 10
                    width: parent.width
                    Text { width: 90; text: "Modificado:"; color: theme.contentTextSecondary; font.pixelSize: 11; font.bold: true }
                    Text { width: parent.width - 100; text: itemProperties.modified ? itemProperties.modified : "--"; color: theme.contentTextPrimary; font.pixelSize: 11 }
                }

                // Creado
                Row {
                    spacing: 10
                    width: parent.width
                    Text { width: 90; text: "Creado:"; color: theme.contentTextSecondary; font.pixelSize: 11; font.bold: true }
                    Text { width: parent.width - 100; text: itemProperties.created ? itemProperties.created : "--"; color: theme.contentTextPrimary; font.pixelSize: 11 }
                }

                // Permisos
                Row {
                    spacing: 10
                    width: parent.width
                    Text { width: 90; text: "Permisos:"; color: theme.contentTextSecondary; font.pixelSize: 11; font.bold: true }
                    Text { width: parent.width - 100; text: itemProperties.permissions ? itemProperties.permissions : "--"; color: theme.contentTextPrimary; font.pixelSize: 11; font.family: "monospace" }
                }

                // Propietario
                Row {
                    spacing: 10
                    width: parent.width
                    Text { width: 90; text: "Propietario:"; color: theme.contentTextSecondary; font.pixelSize: 11; font.bold: true }
                    Text { width: parent.width - 100; text: (itemProperties.owner ? itemProperties.owner : "") + (itemProperties.group ? (" (" + itemProperties.group + ")") : ""); color: theme.contentTextPrimary; font.pixelSize: 11 }
                }
            }

            Rectangle {
                width: parent.width - 40
                height: 1
                color: theme.glassBorder
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Botón Cerrar estilo macOS
            Rectangle {
                width: 90
                height: 28
                radius: 6
                color: closePropsMouse.pressed ? "#005bb5" : closePropsMouse.containsMouse ? "#0077ed" : "#0071e3"
                anchors.horizontalCenter: parent.horizontalCenter

                Text {
                    anchors.centerIn: parent
                    text: "Cerrar"
                    color: "#ffffff"
                    font.pixelSize: 12
                    font.bold: true
                }

                MouseArea {
                    id: closePropsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: propertiesDialog.close()
                }
            }
        }
    }

    // Capa para cerrar el menú contextual al hacer clic fuera
    MouseArea {
        anchors.fill: parent
        visible: fileListRoot.ctxVisible
        z: 95
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: fileListRoot.ctxVisible = false
    }

    // Menú contextual estilo macOS Liquid Glass
    Rectangle {
        id: contextMenu
        visible: fileListRoot.ctxVisible
        x: fileListRoot.ctxX
        y: fileListRoot.ctxY
        width: 220
        height: ctxCol.implicitHeight + 14
        radius: 10
        z: 100
        opacity: visible ? 1.0 : 0.0
        scale: visible ? 1.0 : 0.94
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

        gradient: Gradient {
            GradientStop { position: 0.0; color: theme.isDark ? Qt.rgba(0.18, 0.19, 0.25, 0.97) : Qt.rgba(0.97, 0.97, 0.99, 0.97) }
            GradientStop { position: 1.0; color: theme.isDark ? Qt.rgba(0.13, 0.14, 0.19, 0.97) : Qt.rgba(0.92, 0.93, 0.96, 0.97) }
        }
        border.color: theme.glassBorder
        border.width: 1

        // Brillo superior
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 16
            height: 1
            color: theme.specularGlow
        }

        Column {
            id: ctxCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 7
            spacing: 2

            // 1. Abrir
            Rectangle {
                width: parent.width
                height: 28
                radius: 6
                visible: fileListRoot.selectedPath.length > 0
                color: openMouse.containsMouse ? theme.accent : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 8
                    Text { text: "↗"; color: openMouse.containsMouse ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12 }
                    Text { text: "Abrir"; color: openMouse.containsMouse ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12; font.weight: Font.Medium }
                }

                MouseArea {
                    id: openMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        fileListRoot.ctxVisible = false
                        finderBackend.openItem(fileListRoot.selectedPath)
                    }
                }
            }

            // Separador tras Abrir
            Rectangle {
                width: parent.width - 12
                height: 1
                anchors.horizontalCenter: parent.horizontalCenter
                color: theme.glassBorder
                visible: fileListRoot.selectedPath.length > 0
            }

            // 2. Copiar
            Rectangle {
                width: parent.width
                height: 28
                radius: 6
                visible: fileListRoot.selectedPath.length > 0
                color: copyMouse.containsMouse ? theme.accent : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 8
                    Text { text: "📋"; color: copyMouse.containsMouse ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12 }
                    Text { text: "Copiar"; color: copyMouse.containsMouse ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12; font.weight: Font.Medium }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    text: "⌘C"
                    color: copyMouse.containsMouse ? "#ffffff" : theme.contentTextSecondary
                    font.pixelSize: 11
                }

                MouseArea {
                    id: copyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        fileListRoot.ctxVisible = false
                        finderBackend.copyItem(fileListRoot.selectedPath)
                    }
                }
            }

            // 3. Pegar
            Rectangle {
                width: parent.width
                height: 28
                radius: 6
                opacity: finderBackend.hasClipboard ? 1.0 : 0.4
                color: pasteMouse.containsMouse && finderBackend.hasClipboard ? theme.accent : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 8
                    Text { text: "📥"; color: pasteMouse.containsMouse && finderBackend.hasClipboard ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12 }
                    Text { text: "Pegar"; color: pasteMouse.containsMouse && finderBackend.hasClipboard ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12; font.weight: Font.Medium }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    text: "⌘V"
                    color: pasteMouse.containsMouse && finderBackend.hasClipboard ? "#ffffff" : theme.contentTextSecondary
                    font.pixelSize: 11
                }

                MouseArea {
                    id: pasteMouse
                    anchors.fill: parent
                    enabled: finderBackend.hasClipboard
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        fileListRoot.ctxVisible = false
                        finderBackend.paste()
                    }
                }
            }

            // Separador
            Rectangle {
                width: parent.width - 12
                height: 1
                anchors.horizontalCenter: parent.horizontalCenter
                color: theme.glassBorder
                visible: fileListRoot.selectedPath.length > 0
            }

            // 4. Enviar al Escritorio (crear acceso directo)
            Rectangle {
                width: parent.width
                height: 28
                radius: 6
                visible: fileListRoot.selectedPath.length > 0
                color: sendDeskMouse.containsMouse ? theme.accent : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 8
                    Text { text: "🖥️"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Enviar al Escritorio"; color: sendDeskMouse.containsMouse ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12; font.weight: Font.Medium }
                }

                MouseArea {
                    id: sendDeskMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        fileListRoot.ctxVisible = false
                        finderBackend.sendToDesktop(fileListRoot.selectedPath)
                    }
                }
            }

            // Separador
            Rectangle {
                width: parent.width - 12
                height: 1
                anchors.horizontalCenter: parent.horizontalCenter
                color: theme.glassBorder
                visible: fileListRoot.selectedPath.length > 0
            }

            // 5. Cambiar nombre
            Rectangle {
                width: parent.width
                height: 28
                radius: 6
                visible: fileListRoot.selectedPath.length > 0
                color: renameMouse.containsMouse ? theme.accent : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 8
                    Text { text: "✎"; color: renameMouse.containsMouse ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12 }
                    Text { text: "Cambiar nombre..."; color: renameMouse.containsMouse ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12; font.weight: Font.Medium }
                }

                MouseArea {
                    id: renameMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        fileListRoot.ctxVisible = false
                        renameField.text = fileListRoot.selectedName
                        renameDialog.open()
                        renameField.forceActiveFocus()
                        renameField.selectAll()
                    }
                }
            }

            // 5. Ver propiedades
            Rectangle {
                width: parent.width
                height: 28
                radius: 6
                color: propMouse.containsMouse ? theme.accent : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 8
                    Text { text: "ℹ"; color: propMouse.containsMouse ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12 }
                    Text { text: "Ver propiedades"; color: propMouse.containsMouse ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12; font.weight: Font.Medium }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    text: "⌘I"
                    color: propMouse.containsMouse ? "#ffffff" : theme.contentTextSecondary
                    font.pixelSize: 11
                }

                MouseArea {
                    id: propMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        fileListRoot.ctxVisible = false
                        fileListRoot.openProperties(fileListRoot.selectedPath)
                    }
                }
            }

            // Separador tras propiedades
            Rectangle {
                width: parent.width - 12
                height: 1
                anchors.horizontalCenter: parent.horizontalCenter
                color: theme.glassBorder
                visible: fileListRoot.selectedPath.length > 0
            }

            // 6. Eliminar (envía a la papelera)
            Rectangle {
                width: parent.width
                height: 28
                radius: 6
                visible: fileListRoot.selectedPath.length > 0
                color: deleteMouse.containsMouse ? Qt.rgba(0.9, 0.15, 0.15, 0.25) : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 8
                    Image {
                        source: "qrc:/icons/trash.png"
                        width: 15
                        height: 15
                        anchors.verticalCenter: parent.verticalCenter
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    Text {
                        text: "Eliminar (envía a la papelera)"
                        color: deleteMouse.containsMouse ? "#ff4d4d" : theme.contentTextPrimary
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    text: "⌫"
                    color: deleteMouse.containsMouse ? "#ff4d4d" : theme.contentTextSecondary
                    font.pixelSize: 11
                }

                MouseArea {
                    id: deleteMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        fileListRoot.ctxVisible = false
                        finderBackend.deleteItem(fileListRoot.selectedPath)
                    }
                }
            }

            // 7. Nueva carpeta (cuando se hace clic en fondo vacío)
            Rectangle {
                width: parent.width
                height: 28
                radius: 6
                visible: fileListRoot.selectedPath.length === 0
                color: newFolderMouse.containsMouse ? theme.accent : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 8
                    Text { text: "📁"; color: newFolderMouse.containsMouse ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12 }
                    Text { text: "Nueva carpeta"; color: newFolderMouse.containsMouse ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12; font.weight: Font.Medium }
                }

                MouseArea {
                    id: newFolderMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        fileListRoot.ctxVisible = false
                        fileListRoot.openNewFolderDialog()
                    }
                }
            }
        }
    }

    // Fondo para clics en área vacía y menú contextual general
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | Qt.LeftButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                fileListRoot.selectedPath = ""
                fileListRoot.selectedName = ""
                var pt = mapToItem(fileListRoot, mouse.x, mouse.y)
                fileListRoot.showContextMenu(pt.x, pt.y)
            } else {
                fileListRoot.selectedPath = ""
                fileListRoot.selectedName = ""
                fileListRoot.ctxVisible = false
            }
        }
    }

    // Estado vacío (sin archivos)
    Column {
        anchors.centerIn: parent
        spacing: 12
        visible: finderBackend.entries.length === 0

        Image {
            source: "qrc:/icons/folder.png"
            width: 72
            height: 72
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: 0.35
            smooth: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: finderBackend.searchQuery.length > 0 ? "No se encontraron resultados" : "Esta carpeta está vacía"
            color: theme.contentTextSecondary
            font.pixelSize: 14
        }
    }

    // 1. VISTA EN CUADRÍCULA (GRID VIEW)
    GridView {
        id: gridView
        anchors.fill: parent
        anchors.margins: 16
        cellWidth: 104
        cellHeight: 116
        clip: true
        visible: finderBackend.viewMode === "grid"

        model: finderBackend.entries

        delegate: Item {
            id: gridItem
            width: gridView.cellWidth
            height: gridView.cellHeight

            Item {
                id: gridDragProxy
            }

            Drag.active: itemHover.drag.active
            Drag.source: gridItem
            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
            Drag.keys: ["text/uri-list"]
            Drag.mimeData: {
                "text/uri-list": (modelData.path.indexOf("://") !== -1 ? modelData.path : ("file://" + modelData.path)) + "\r\n",
                "text/plain": modelData.path
            }

            property bool isSelected: fileListRoot.selectedPath === modelData.path

            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: 8
                color: isSelected ? theme.accent :
                       itemHover.containsMouse ? theme.itemHover : "transparent"

                Behavior on color { ColorAnimation { duration: 100 } }

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    width: parent.width - 8

                    Image {
                        source: modelData.icon
                        sourceSize: Qt.size(64, 64)
                        width: 58
                        height: 58
                        anchors.horizontalCenter: parent.horizontalCenter
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                        cache: true
                    }

                    Text {
                        text: modelData.name
                        color: isSelected ? "#ffffff" : theme.contentTextPrimary
                        font.pixelSize: 11
                        font.weight: isSelected ? Font.DemiBold : Font.Normal
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        maximumLineCount: 2
                        wrapMode: Text.WrapAnywhere
                    }
                }

                MouseArea {
                    id: itemHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: (itemHover.drag.active || pressedLeft) ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                    property real pressX: 0
                    property real pressY: 0
                    property bool pressedLeft: false

                    onPressed: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            pressX = mouse.x
                            pressY = mouse.y
                            pressedLeft = true
                            fileListRoot.selectedPath = modelData.path
                            fileListRoot.selectedName = modelData.name
                            fileListRoot.selectedIsDir = modelData.isDir
                        }
                    }

                    onPositionChanged: (mouse) => {
                        if (pressedLeft && (mouse.buttons & Qt.LeftButton)) {
                            var dx = mouse.x - pressX
                            var dy = mouse.y - pressY
                            if ((dx * dx + dy * dy) > 25) {
                                pressedLeft = false
                                finderBackend.startDrag(modelData.path)
                            }
                        }
                    }

                    onPressAndHold: (mouse) => {
                        if (mouse.button === Qt.LeftButton || (mouse.buttons & Qt.LeftButton)) {
                            pressedLeft = false
                            finderBackend.startDrag(modelData.path)
                        }
                    }

                    onReleased: (mouse) => {
                        pressedLeft = false
                    }

                    onCanceled: {
                        pressedLeft = false
                    }

                    onClicked: (mouse) => {
                        fileListRoot.selectedPath = modelData.path
                        fileListRoot.selectedName = modelData.name
                        fileListRoot.selectedIsDir = modelData.isDir

                        if (mouse.button === Qt.RightButton) {
                            var pt = mapToItem(fileListRoot, mouse.x, mouse.y)
                            fileListRoot.showContextMenu(pt.x, pt.y)
                        } else {
                            fileListRoot.ctxVisible = false
                        }
                    }

                    onDoubleClicked: {
                        finderBackend.openItem(modelData.path)
                    }
                }
            }
        }
    }

    // 2. VISTA EN LISTA DETALLADA (LIST VIEW)
    Column {
        anchors.fill: parent
        visible: finderBackend.viewMode === "list"

        // Cabecera de columnas con ordenación interactiva
        Rectangle {
            width: parent.width
            height: 28
            color: "#f5f5f7"

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Qt.rgba(0, 0, 0, 0.08)
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14

                // Columna Nombre
                Item {
                    width: parent.width - 380
                    height: parent.height
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text {
                            text: "Nombre"
                            color: finderBackend.sortBy === "name" ? theme.accent : theme.contentTextSecondary
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Text {
                            visible: finderBackend.sortBy === "name"
                            text: finderBackend.sortAscending ? "▲" : "▼"
                            color: theme.accent
                            font.pixelSize: 9
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: finderBackend.sort("name")
                    }
                }

                // Columna Fecha
                Item {
                    width: 150
                    height: parent.height
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text {
                            text: "Fecha de modificación"
                            color: finderBackend.sortBy === "date" ? theme.accent : theme.contentTextSecondary
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Text {
                            visible: finderBackend.sortBy === "date"
                            text: finderBackend.sortAscending ? "▲" : "▼"
                            color: theme.accent
                            font.pixelSize: 9
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: finderBackend.sort("date")
                    }
                }

                // Columna Tamaño
                Item {
                    width: 100
                    height: parent.height
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text {
                            text: "Tamaño"
                            color: finderBackend.sortBy === "size" ? theme.accent : theme.contentTextSecondary
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Text {
                            visible: finderBackend.sortBy === "size"
                            text: finderBackend.sortAscending ? "▲" : "▼"
                            color: theme.accent
                            font.pixelSize: 9
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: finderBackend.sort("size")
                    }
                }

                // Columna Clase / Tipo
                Item {
                    width: 130
                    height: parent.height
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text {
                            text: "Clase"
                            color: finderBackend.sortBy === "kind" ? theme.accent : theme.contentTextSecondary
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Text {
                            visible: finderBackend.sortBy === "kind"
                            text: finderBackend.sortAscending ? "▲" : "▼"
                            color: theme.accent
                            font.pixelSize: 9
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: finderBackend.sort("kind")
                    }
                }
            }
        }

        // Lista de archivos detallada
        ListView {
            id: listView
            width: parent.width
            height: parent.height - 28
            clip: true

            model: finderBackend.entries

            delegate: Rectangle {
                id: listItem
                width: listView.width
                height: 30

                Item {
                    id: listDragProxy
                }

                Drag.active: listHover.drag.active
                Drag.source: listItem
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                Drag.keys: ["text/uri-list"]
                Drag.mimeData: {
                    "text/uri-list": (modelData.path.indexOf("://") !== -1 ? modelData.path : ("file://" + modelData.path)) + "\r\n",
                    "text/plain": modelData.path
                }

                property bool isSelected: fileListRoot.selectedPath === modelData.path

                color: isSelected ? theme.accent :
                       listHover.containsMouse ? theme.itemHover :
                       index % 2 === 0 ? "transparent" : Qt.rgba(0, 0, 0, 0.02)

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14

                    // Nombre con icono
                    Row {
                        width: parent.width - 380
                        height: parent.height
                        spacing: 8

                        Image {
                            source: modelData.icon
                            sourceSize: Qt.size(24, 24)
                            width: 18
                            height: 18
                            anchors.verticalCenter: parent.verticalCenter
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            asynchronous: true
                            cache: true
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            color: isSelected ? "#ffffff" : theme.contentTextPrimary
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            width: parent.width - 30
                        }
                    }

                    // Fecha
                    Text {
                        width: 150
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.modified
                        color: isSelected ? "#ffffff" : theme.contentTextSecondary
                        font.pixelSize: 11
                    }

                    // Tamaño
                    Text {
                        width: 100
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.size
                        color: isSelected ? "#ffffff" : theme.contentTextSecondary
                        font.pixelSize: 11
                    }

                    // Tipo
                    Text {
                        width: 130
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.type
                        color: isSelected ? "#ffffff" : theme.contentTextSecondary
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: listHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: (listHover.drag.active || pressedLeft) ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                    property real pressX: 0
                    property real pressY: 0
                    property bool pressedLeft: false

                    onPressed: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            pressX = mouse.x
                            pressY = mouse.y
                            pressedLeft = true
                            fileListRoot.selectedPath = modelData.path
                            fileListRoot.selectedName = modelData.name
                            fileListRoot.selectedIsDir = modelData.isDir
                        }
                    }

                    onPositionChanged: (mouse) => {
                        if (pressedLeft && (mouse.buttons & Qt.LeftButton)) {
                            var dx = mouse.x - pressX
                            var dy = mouse.y - pressY
                            if ((dx * dx + dy * dy) > 25) {
                                pressedLeft = false
                                finderBackend.startDrag(modelData.path)
                            }
                        }
                    }

                    onPressAndHold: (mouse) => {
                        if (mouse.button === Qt.LeftButton || (mouse.buttons & Qt.LeftButton)) {
                            pressedLeft = false
                            finderBackend.startDrag(modelData.path)
                        }
                    }

                    onReleased: (mouse) => {
                        pressedLeft = false
                    }

                    onCanceled: {
                        pressedLeft = false
                    }

                    onClicked: (mouse) => {
                        fileListRoot.selectedPath = modelData.path
                        fileListRoot.selectedName = modelData.name
                        fileListRoot.selectedIsDir = modelData.isDir

                        if (mouse.button === Qt.RightButton) {
                            var pt = mapToItem(fileListRoot, mouse.x, mouse.y)
                            fileListRoot.showContextMenu(pt.x, pt.y)
                        } else {
                            fileListRoot.ctxVisible = false
                        }
                    }

                    onDoubleClicked: {
                        finderBackend.openItem(modelData.path)
                    }
                }
            }
        }
    }
}
