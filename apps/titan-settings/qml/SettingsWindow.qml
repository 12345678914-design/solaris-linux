import QtQuick 2.15
import QtQuick.Controls 2.15

TitanWindow {
    id: settingsWindow

    title: "Ajustes del Sistema - " + settingsBackend.currentSection
    sidebarWidth: 230
    showStatusBar: false

    TitanTheme { id: theme }

    // 1. TOOLBAR SUPERIOR DEL CONTENIDO (BOTONES < > Y TÍTULO DE LA SECCIÓN)
    headerContentData: Row {
        anchors.fill: parent
        spacing: 14

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Rectangle {
                width: 26
                height: 24
                radius: 5
                color: navBackMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.08) : "transparent"
                border.color: Qt.rgba(0, 0, 0, 0.1)

                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    color: theme.headerText
                    font.pixelSize: 16
                    font.bold: true
                }

                MouseArea {
                    id: navBackMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingsBackend.currentSection = "General"
                }
            }

            Rectangle {
                width: 26
                height: 24
                radius: 5
                color: "transparent"
                opacity: 0.35

                Text {
                    anchors.centerIn: parent
                    text: "›"
                    color: theme.headerText
                    font.pixelSize: 16
                    font.bold: true
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: settingsBackend.currentSection
            color: theme.headerText
            font.pixelSize: 14
            font.bold: true
        }
    }

    // 2. BARRA LATERAL TRANSLÚCIDA ESTILO macOS VENTURA / SONOMA
    sidebarContentData: Column {
        anchors.fill: parent
        spacing: 12
        topPadding: 42
        bottomPadding: 12

        // A. BUSCADOR ESTILO macOS
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 24
            height: 28
            radius: 6
            color: theme.isDark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.6)
            border.color: searchInput.activeFocus ? "#0071e3" : Qt.rgba(0, 0, 0, 0.12)
            border.width: searchInput.activeFocus ? 1.5 : 1

            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "🔍"
                    font.pixelSize: 10
                    opacity: 0.6
                }

                TextField {
                    id: searchInput
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 36
                    placeholderText: "Buscar"
                    font.pixelSize: 11
                    color: theme.contentTextPrimary
                    background: null
                    placeholderTextColor: theme.contentTextSecondary
                    text: settingsBackend.searchQuery
                    onTextChanged: settingsBackend.searchQuery = text
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

        // B. TARJETA DE PERFIL DE USUARIO
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 20
            height: 48

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: userMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                spacing: 10

                // Avatar circular con monograma
                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    color: "#8e8e93"

                    Text {
                        anchors.centerIn: parent
                        text: (settingsBackend.systemInfo.user && settingsBackend.systemInfo.user.length > 0) ?
                              settingsBackend.systemInfo.user.charAt(0).toUpperCase() : "I"
                        color: "#ffffff"
                        font.pixelSize: 15
                        font.bold: true
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: settingsBackend.systemInfo.user || "ISAI"
                        color: theme.contentTextPrimary
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Text {
                        text: "Cuenta local"
                        color: theme.contentTextSecondary
                        font.pixelSize: 10
                    }
                }
            }

            MouseArea {
                id: userMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: settingsBackend.currentSection = "Usuarios y grupos"
            }
        }

        // Separador sutil
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 24
            height: 1
            color: theme.sidebarBorder
        }

        // C. LISTA DE CATEGORÍAS
        ScrollView {
            id: sidebarScroll
            width: parent.width
            height: parent.height - 150
            clip: true

            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Column {
                width: parent.width
                spacing: 2

                Repeater {
                    model: settingsBackend.sections

                    delegate: Item {
                        width: parent.width - 16
                        height: 32
                        anchors.horizontalCenter: parent.horizontalCenter

                        property bool isSelected: settingsBackend.currentSection === modelData.name ||
                                                  settingsBackend.currentSection === modelData.id
                        property bool isHovered: rowMouse.containsMouse

                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: isSelected ? "#0071e3" :
                                   isHovered ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)) : "transparent"

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                spacing: 10

                                // Icono redondeado de color característico estilo Apple
                                Rectangle {
                                    width: 20
                                    height: 20
                                    radius: 5
                                    color: modelData.badgeColor || "#007aff"
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.icon
                                        font.pixelSize: 11
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    color: isSelected ? "#ffffff" : theme.contentTextPrimary
                                    font.pixelSize: 11
                                    font.weight: isSelected ? Font.Medium : Font.Normal
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settingsBackend.currentSection = modelData.name
                            }
                        }
                    }
                }
            }
        }
    }

    // 3. CONTENIDO PRINCIPAL DE LA DERECHA
    Loader {
        id: viewLoader
        anchors.fill: parent

        sourceComponent: {
            if (settingsBackend.currentSection === "Apariencia") {
                return appearanceComponent
            } else if (settingsBackend.currentSection === "Fondo de pantalla") {
                return wallpaperComponent
            } else if (settingsBackend.currentSection === "General") {
                return generalComponent
            } else {
                return genericComponent
            }
        }
    }

    Component { id: appearanceComponent; AppearanceView {} }
    Component { id: wallpaperComponent; WallpaperView {} }
    Component { id: generalComponent; GeneralView {} }

    Component {
        id: genericComponent
        ScrollView {
            contentWidth: width
            clip: true

            Column {
                width: parent.width - 48
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18
                topPadding: 24

                Rectangle {
                    width: parent.width
                    height: 110
                    radius: 10
                    color: theme.contentCardBg
                    border.color: theme.contentCardBorder
                    border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: settingsBackend.currentSection
                            color: theme.contentTextPrimary
                            font.pixelSize: 14
                            font.bold: true
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Configuración del sistema administrada por Titan Linux"
                            color: theme.contentTextSecondary
                            font.pixelSize: 11
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Estado: Activo • Compatible con Wayland y labwc"
                            color: "#34c759"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                }
            }
        }
    }
}

