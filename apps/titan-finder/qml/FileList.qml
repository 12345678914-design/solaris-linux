import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: fileListRoot

    TitanTheme { id: theme }

    color: theme.contentBackground

    property string selectedPath: ""
    property string selectedName: ""
    property bool selectedIsDir: false

    function openNewFolderDialog() {
        folderNameField.text = "Nueva carpeta"
        newFolderDialog.open()
        folderNameField.forceActiveFocus()
        folderNameField.selectAll()
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

    // Menú contextual estilo macOS
    Menu {
        id: contextMenu
        background: Rectangle {
            color: Qt.rgba(0.98, 0.98, 1.0, 0.96)
            radius: 8
            border.color: Qt.rgba(0, 0, 0, 0.14)
            border.width: 1
        }

        Action {
            text: "Abrir"
            onTriggered: {
                if (fileListRoot.selectedPath.length > 0) {
                    finderBackend.openItem(fileListRoot.selectedPath)
                }
            }
        }
        Action {
            text: "Abrir en Terminal"
            onTriggered: {
                finderBackend.openTerminal(fileListRoot.selectedPath)
            }
        }
        MenuSeparator {}
        Action {
            text: "Enviar al escritorio"
            enabled: fileListRoot.selectedPath.length > 0
            onTriggered: {
                finderBackend.sendToDesktop(fileListRoot.selectedPath)
            }
        }
        MenuSeparator {}
        Action {
            text: "Nueva carpeta"
            onTriggered: {
                folderNameField.text = "Nueva carpeta"
                newFolderDialog.open()
                folderNameField.selectAll()
            }
        }
        Action {
            text: "Renombrar..."
            enabled: fileListRoot.selectedPath.length > 0
            onTriggered: {
                renameField.text = fileListRoot.selectedName
                renameDialog.open()
                renameField.selectAll()
            }
        }
        MenuSeparator {}
        Action {
            text: "Trasladar a la papelera"
            enabled: fileListRoot.selectedPath.length > 0
            onTriggered: {
                finderBackend.deleteItem(fileListRoot.selectedPath)
            }
        }
    }

    // Fondo para clics en área vacía y menú contextual general
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | Qt.LeftButton
        onClicked: {
            if (mouse.button === Qt.RightButton) {
                fileListRoot.selectedPath = ""
                fileListRoot.selectedName = ""
                contextMenu.popup()
            } else {
                fileListRoot.selectedPath = ""
                fileListRoot.selectedName = ""
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
                        width: 58
                        height: 58
                        anchors.horizontalCenter: parent.horizontalCenter
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
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
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        fileListRoot.selectedPath = modelData.path
                        fileListRoot.selectedName = modelData.name
                        fileListRoot.selectedIsDir = modelData.isDir

                        if (mouse.button === Qt.RightButton) {
                            contextMenu.popup()
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
                            width: 18
                            height: 18
                            anchors.verticalCenter: parent.verticalCenter
                            fillMode: Image.PreserveAspectFit
                            smooth: true
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
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        fileListRoot.selectedPath = modelData.path
                        fileListRoot.selectedName = modelData.name
                        fileListRoot.selectedIsDir = modelData.isDir

                        if (mouse.button === Qt.RightButton) {
                            contextMenu.popup()
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
