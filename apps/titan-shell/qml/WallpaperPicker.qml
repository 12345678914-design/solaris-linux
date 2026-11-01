import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: pickerRoot
    width: Math.min(840, parent ? parent.width - 40 : 840)
    height: Math.min(580, parent ? parent.height - 60 : 580)

    TitanTheme { id: theme }

    // Fondo modal con desenfoque y cristal translúcido estilo macOS (Liquid Glass)
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 20
        gradient: Gradient {
            GradientStop { position: 0.0; color: theme.windowBgTop }
            GradientStop { position: 0.5; color: theme.windowBgMid }
            GradientStop { position: 1.0; color: theme.windowBgBottom }
        }
        border.color: theme.glassBorder
        border.width: 1
        clip: true

        // Brillo superior del cristal
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 32
            height: 1
            color: theme.specularGlow
        }

        // 1. ENCABEZADO
        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 64

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Rectangle {
                    width: 36
                    height: 36
                    radius: 9
                    color: "#0071e3"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "🖌️"
                        font.pixelSize: 18
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: "Fondos de pantalla"
                        color: theme.headerText
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Text {
                        text: "Selecciona un fondo para tu escritorio • Atajo rápido: Ctrl + W"
                        color: theme.contentTextSecondary
                        font.pixelSize: 11
                    }
                }
            }

            // Botón Cerrar (✕)
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                radius: 14
                color: closeMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(0, 0, 0, 0.05)

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: theme.headerText
                    font.pixelSize: 12
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.closeWallpaperPicker()
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: theme.headerBorder
            }
        }

        // 2. CUADRÍCULA DE FONDOS DE PANTALLA
        ScrollView {
            id: scroll
            anchors.top: header.bottom
            anchors.bottom: footer.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 18
            clip: true

            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Grid {
                columns: 3
                spacing: 16
                anchors.horizontalCenter: parent.horizontalCenter

                Repeater {
                    model: shellBackend.wallpapers

                    delegate: Item {
                        id: wpItem
                        width: (card.width - 72) / 3
                        height: 142

                        property bool isSelected: shellBackend.currentWallpaper === modelData.path
                        property bool isHovered: itemMouse.containsMouse

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: isSelected ? Qt.rgba(0, 0.44, 0.89, 0.15) :
                                   isHovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                            border.color: isSelected ? "#0071e3" :
                                          isHovered ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.1)
                            border.width: isSelected ? 3 : 1

                            scale: isHovered ? 1.03 : 1.0
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                            Column {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 6

                                // Miniatura de la imagen
                                Rectangle {
                                    width: parent.width
                                    height: 98
                                    radius: 8
                                    clip: true
                                    color: "#1c1c1e"

                                    Image {
                                        anchors.fill: parent
                                        source: modelData.thumbnail
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                        asynchronous: true
                                    }

                                    // Badge de seleccionado (check azul)
                                    Rectangle {
                                        visible: wpItem.isSelected
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 6
                                        width: 22
                                        height: 22
                                        radius: 11
                                        color: "#0071e3"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "✓"
                                            color: "#ffffff"
                                            font.pixelSize: 12
                                            font.bold: true
                                        }
                                    }
                                }

                                // Título del fondo
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.name
                                    color: wpItem.isSelected ? "#0071e3" : theme.contentTextPrimary
                                    font.pixelSize: 11
                                    font.bold: wpItem.isSelected
                                    elide: Text.ElideRight
                                    width: parent.width - 8
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    shellBackend.setWallpaper(modelData.path)
                                }
                            }
                        }
                    }
                }
            }
        }

        // 3. PIE DE PÁGINA LIQUID GLASS
        Rectangle {
            id: footer
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 52
            gradient: Gradient {
                GradientStop { position: 0.0; color: theme.isDark ? Qt.rgba(0.12, 0.15, 0.22, 0.70) : Qt.rgba(0.96, 0.97, 1.0, 0.70) }
                GradientStop { position: 1.0; color: theme.isDark ? Qt.rgba(0.08, 0.10, 0.16, 0.75) : Qt.rgba(0.90, 0.92, 0.96, 0.75) }
            }
            border.color: theme.headerBorder
            border.width: 1

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Rectangle {
                    width: configBtnText.width + 20
                    height: 28
                    radius: 6
                    color: settingsMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.08) : "transparent"
                    border.color: Qt.rgba(0, 0, 0, 0.15)
                    border.width: 1

                    Text {
                        id: configBtnText
                        anchors.centerIn: parent
                        text: "⚙️ Abrir Ajustes de Pantalla..."
                        color: theme.contentTextPrimary
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: settingsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shellBackend.openSettings("wallpaper")
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 80
                height: 30
                radius: 7
                color: okMouse.pressed ? "#005bb5" : okMouse.containsMouse ? "#0077ed" : "#0071e3"

                Text {
                    anchors.centerIn: parent
                    text: "Listo"
                    color: "#ffffff"
                    font.pixelSize: 12
                    font.bold: true
                }

                MouseArea {
                    id: okMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.closeWallpaperPicker()
                }
            }
        }
    }

    // Tecla Escape para cerrar
    Item {
        focus: pickerRoot.visible
        Keys.onEscapePressed: shellBackend.closeWallpaperPicker()
    }
}

