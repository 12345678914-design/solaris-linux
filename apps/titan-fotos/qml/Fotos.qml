import QtQuick 2.15
import QtQuick.Controls 2.15

TitanWindow {
    id: fotosWindow

    title: fotosBackend.currentIndex >= 0 ? (fotosBackend.currentPhoto.name + " — Fotos") : "Fotos"
    sidebarWidth: 195

    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (fotosBackend.currentIndex >= 0) {
                fotosBackend.selectPhoto(-1)
            }
        }
    }
    Shortcut {
        sequence: "Ctrl+W"
        onActivated: fotosBackend.setAsWallpaper()
    }
    Shortcut {
        sequence: "Left"
        onActivated: {
            if (fotosBackend.currentIndex >= 0) {
                fotosBackend.previousPhoto()
            }
        }
    }
    Shortcut {
        sequence: "Right"
        onActivated: {
            if (fotosBackend.currentIndex >= 0) {
                fotosBackend.nextPhoto()
            }
        }
    }
    Shortcut {
        sequence: "Ctrl++"
        onActivated: fotosBackend.zoomIn()
    }
    Shortcut {
        sequence: "Ctrl+="
        onActivated: fotosBackend.zoomIn()
    }
    Shortcut {
        sequence: "Ctrl+-"
        onActivated: fotosBackend.zoomOut()
    }
    Shortcut {
        sequence: "Ctrl+0"
        onActivated: fotosBackend.resetZoom()
    }
    Shortcut {
        sequence: "Ctrl+R"
        onActivated: fotosBackend.rotateClockwise()
    }

    // 1. TOOLBAR SUPERIOR CON BLUR ACRÍLICO
    headerContentData: Row {
        anchors.fill: parent
        spacing: 10

        // Botón Volver a la galería (si estamos viendo una foto)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: fotosBackend.currentIndex >= 0
            width: 82; height: 26; radius: 6
            color: backGalleryMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
            border.color: Qt.rgba(1, 1, 1, 0.15)

            Row {
                anchors.centerIn: parent
                spacing: 4
                Text {
                    text: "‹"
                    color: theme.headerText
                    font.pixelSize: 15
                    font.bold: true
                }
                Text {
                    text: "Galería"
                    color: theme.headerText
                    font.pixelSize: 11
                    font.bold: true
                }
            }

            MouseArea {
                id: backGalleryMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: fotosBackend.selectPhoto(-1)
            }
        }

        // Controles de foto individual: anterior / siguiente
        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: fotosBackend.currentIndex >= 0
            spacing: 2

            Rectangle {
                width: 28; height: 26; radius: 5
                color: prevMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.12)
                Text { anchors.centerIn: parent; text: "‹"; color: theme.headerText; font.pixelSize: 18; font.bold: true }
                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fotosBackend.previousPhoto()
                }
            }

            Rectangle {
                width: 28; height: 26; radius: 5
                color: nextMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.12)
                Text { anchors.centerIn: parent; text: "›"; color: theme.headerText; font.pixelSize: 18; font.bold: true }
                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fotosBackend.nextPhoto()
                }
            }
        }

        // Título de la vista / Categoría
        Item {
            width: Math.max(120, parent.width - 520)
            height: parent.height
            clip: true

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                text: fotosBackend.currentIndex >= 0
                      ? fotosBackend.currentPhoto.name
                      : (fotosBackend.currentCategory === "fondos" ? "Fondos de Pantalla" :
                         fotosBackend.currentCategory === "descargas" ? "Descargas" : "Fototeca")
                color: theme.headerText
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideMiddle
                width: parent.width - 16
            }
        }

        Item { width: 10; height: 1 }

        // Botones de zoom y rotación
        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: fotosBackend.currentIndex >= 0
            spacing: 4

            // Rotar
            Rectangle {
                width: 30; height: 26; radius: 5
                color: rotMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.12)
                Text { anchors.centerIn: parent; text: "↻"; color: theme.headerText; font.pixelSize: 14; font.bold: true }
                MouseArea {
                    id: rotMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fotosBackend.rotateClockwise()
                }
            }

            // Zoom out
            Rectangle {
                width: 28; height: 26; radius: 5
                color: zoomOutMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.12)
                Text { anchors.centerIn: parent; text: "−"; color: theme.headerText; font.pixelSize: 14; font.bold: true }
                MouseArea {
                    id: zoomOutMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fotosBackend.zoomOut()
                }
            }

            // Porcentaje zoom
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(fotosBackend.zoomFactor * 100) + "%"
                color: theme.headerText
                font.pixelSize: 11
                font.bold: true
                width: 38
                horizontalAlignment: Text.AlignHCenter
            }

            // Zoom in
            Rectangle {
                width: 28; height: 26; radius: 5
                color: zoomInMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.12)
                Text { anchors.centerIn: parent; text: "+"; color: theme.headerText; font.pixelSize: 14; font.bold: true }
                MouseArea {
                    id: zoomInMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fotosBackend.zoomIn()
                }
            }

            // Establecer como fondo
            Rectangle {
                width: 140; height: 26; radius: 6
                color: wpMouse.containsMouse ? Qt.rgba(0, 0.44, 0.89, 0.6) : Qt.rgba(0, 0.44, 0.89, 0.35)
                border.color: theme.accent

                Row {
                    anchors.centerIn: parent
                    spacing: 4
                    Text { text: "🖼️"; font.pixelSize: 11 }
                    Text { text: "Fondo de pantalla"; color: "#ffffff"; font.pixelSize: 11; font.bold: true }
                }

                MouseArea {
                    id: wpMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fotosBackend.setAsWallpaper()
                }
            }
        }

        // Barra de búsqueda Spotlight en el toolbar
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 140; height: 28; radius: 6
            color: Qt.rgba(1, 1, 1, 0.12)
            border.color: searchInput.activeFocus ? theme.accent : Qt.rgba(1, 1, 1, 0.18)

            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "🔍"
                    font.pixelSize: 10
                    opacity: 0.7
                }

                TextField {
                    id: searchInput
                    width: parent.width - 32
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "Buscar..."
                    font.pixelSize: 11
                    color: theme.headerText
                    background: null
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)
                    text: fotosBackend.searchQuery
                    onTextChanged: fotosBackend.searchQuery = text
                }
            }
        }
    }

    // 2. SIDEBAR TRANSLÚCIDO
    sidebarContentData: Column {
        anchors.fill: parent
        anchors.topMargin: 12
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 4

        Text {
            text: "BIBLIOTECA"
            color: theme.sidebarTextMuted
            font.pixelSize: 10
            font.bold: true
            anchors.left: parent.left
            anchors.leftMargin: 8
        }

        Repeater {
            model: fotosBackend.categories
            delegate: Rectangle {
                width: parent.width
                height: 32
                radius: 6
                color: isSelected ? theme.selectionBg : (catMouse.containsMouse ? theme.itemHover : "transparent")

                readonly property bool isSelected: fotosBackend.currentCategory === modelData.id

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16; height: 16
                        source: modelData.icon
                        sourceSize.width: 16
                        sourceSize.height: 16
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: isSelected ? "#ffffff" : theme.sidebarText
                        font.pixelSize: 12
                        font.weight: isSelected ? Font.DemiBold : Font.Normal
                    }
                }

                MouseArea {
                    id: catMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        fotosBackend.selectCategory(modelData.id)
                        fotosBackend.selectPhoto(-1)
                    }
                }
            }
        }
    }

    // 3. CONTENIDO CENTRAL TRANSLÚCIDO (VIDRIO FROSTED)
    Rectangle {
        anchors.fill: parent
        color: theme.contentBackground

        // Vista de cuadrícula de fotos
        GridView {
            id: photoGrid
            anchors.fill: parent
            anchors.margins: 14
            cellWidth: 160
            cellHeight: 160
            clip: true
            visible: fotosBackend.currentIndex < 0
            model: fotosBackend.photos

            delegate: Rectangle {
                width: 148
                height: 148
                radius: 10
                color: itemMouse.containsMouse ? theme.contentCardBg : Qt.rgba(1, 1, 1, 0.03)
                border.color: itemMouse.containsMouse ? theme.accent : theme.contentCardBorder
                border.width: 1

                scale: itemMouse.containsMouse ? 1.03 : 1.0
                Behavior on scale { NumberAnimation { duration: 120 } }

                Column {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4

                    Rectangle {
                        width: parent.width
                        height: 100
                        radius: 6
                        color: Qt.rgba(0, 0, 0, 0.15)
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: modelData.url
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }
                    }

                    Text {
                        width: parent.width
                        text: modelData.name
                        color: theme.contentTextPrimary
                        font.pixelSize: 11
                        font.bold: true
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        width: parent.width
                        text: modelData.dimensions.length > 0 ? (modelData.dimensions + " • " + modelData.size) : modelData.size
                        color: theme.contentTextSecondary
                        font.pixelSize: 9
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fotosBackend.selectPhoto(index)
                }
            }
        }

        // Estado vacío
        Column {
            anchors.centerIn: parent
            spacing: 12
            visible: fotosBackend.photos.length === 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "📷"
                font.pixelSize: 48
                opacity: 0.6
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No se encontraron fotografías"
                color: theme.contentTextSecondary
                font.pixelSize: 14
                font.bold: true
            }
        }

        // Vista de foto individual a pantalla completa con zoom y rotación
        Item {
            id: singleView
            anchors.fill: parent
            visible: fotosBackend.currentIndex >= 0
            clip: true

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)
            }

            Flickable {
                id: flickable
                anchors.fill: parent
                contentWidth: imageItem.width * fotosBackend.zoomFactor
                contentHeight: imageItem.height * fotosBackend.zoomFactor
                clip: true

                Item {
                    id: imageItem
                    width: flickable.width
                    height: flickable.height
                    scale: fotosBackend.zoomFactor
                    rotation: fotosBackend.rotationAngle
                    transformOrigin: Item.Center

                    Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    Image {
                        id: mainImg
                        anchors.fill: parent
                        anchors.margins: 20
                        source: fotosBackend.currentPhoto.url ? fotosBackend.currentPhoto.url : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                }
            }

            // Flechas flotantes laterales
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 40; radius: 20
                color: floatPrevMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.65) : Qt.rgba(0, 0, 0, 0.35)
                border.color: Qt.rgba(1, 1, 1, 0.2)

                Text { anchors.centerIn: parent; text: "‹"; color: "#ffffff"; font.pixelSize: 24; font.bold: true }

                MouseArea {
                    id: floatPrevMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fotosBackend.previousPhoto()
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 40; radius: 20
                color: floatNextMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.65) : Qt.rgba(0, 0, 0, 0.35)
                border.color: Qt.rgba(1, 1, 1, 0.2)

                Text { anchors.centerIn: parent; text: "›"; color: "#ffffff"; font.pixelSize: 24; font.bold: true }

                MouseArea {
                    id: floatNextMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fotosBackend.nextPhoto()
                }
            }
        }
    }

    // 4. BARRA DE ESTADO INFERIOR
    statusBarContentData: Row {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: fotosBackend.statusText
            color: theme.contentTextSecondary
            font.pixelSize: 10
        }

        Item { width: 12; height: 1 }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: fotosBackend.currentIndex >= 0 && fotosBackend.currentPhoto.dimensions.length > 0
            text: "•  " + fotosBackend.currentPhoto.dimensions + "  •  " + fotosBackend.currentPhoto.size
            color: theme.contentTextSecondary
            font.pixelSize: 10
        }

        Item { width: 10; height: 1 }

        // Botón abrir en Finder
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            visible: fotosBackend.currentIndex >= 0
            spacing: 4

            Text {
                text: "Mostrar en Finder"
                color: finderLinkMouse.containsMouse ? theme.accent : theme.contentTextSecondary
                font.pixelSize: 10
                font.underline: finderLinkMouse.containsMouse

                MouseArea {
                    id: finderLinkMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fotosBackend.openInFinder()
                }
            }
        }
    }
}

