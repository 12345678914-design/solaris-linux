import QtQuick 2.15
import QtQuick.Controls 2.15

ScrollView {
    id: appearanceView
    contentWidth: width
    clip: true

    TitanTheme { id: theme }

    Column {
        width: parent.width - 48
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 24
        topPadding: 16
        bottomPadding: 32

        // 1. SELECTOR VISUAL DE MODO CLARO / OSCURO / AUTO
        Column {
            width: parent.width
            spacing: 12

            Text {
                text: "Aspecto"
                color: theme.contentTextSecondary
                font.pixelSize: 12
                font.bold: true
            }

            Row {
                spacing: 20
                anchors.horizontalCenter: parent.horizontalCenter

                // Opción: MODO CLARO
                Item {
                    width: 140
                    height: 120

                    Column {
                        anchors.centerIn: parent
                        spacing: 8

                        // Ilustración ventana clara
                        Rectangle {
                            width: 130
                            height: 80
                            radius: 8
                            color: "#f5f5f7"
                            border.color: !settingsBackend.isDark ? "#0071e3" : Qt.rgba(0, 0, 0, 0.15)
                            border.width: !settingsBackend.isDark ? 2.5 : 1

                            Row {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: 6
                                spacing: 4
                                Rectangle { width: 6; height: 6; radius: 3; color: "#ff5f56" }
                                Rectangle { width: 6; height: 6; radius: 3; color: "#febc2e" }
                                Rectangle { width: 6; height: 6; radius: 3; color: "#28c840" }
                            }

                            // Barra lateral y contenido miniatura
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.topMargin: 18
                                anchors.leftMargin: 4
                                anchors.bottomMargin: 4
                                width: 34
                                radius: 4
                                color: "#e8e8ed"
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.topMargin: 18
                                anchors.leftMargin: 42
                                anchors.rightMargin: 4
                                anchors.bottomMargin: 4
                                radius: 4
                                color: "#ffffff"
                            }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6

                            Rectangle {
                                width: 14
                                height: 14
                                radius: 7
                                color: !settingsBackend.isDark ? "#0071e3" : "transparent"
                                border.color: !settingsBackend.isDark ? "#0071e3" : theme.contentTextSecondary
                                border.width: 1.5

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: "#ffffff"
                                    visible: !settingsBackend.isDark
                                }
                            }

                            Text {
                                text: "Claro"
                                color: theme.contentTextPrimary
                                font.pixelSize: 12
                                font.bold: !settingsBackend.isDark
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: settingsBackend.setThemeMode("light")
                    }
                }

                // Opción: MODO OSCURO
                Item {
                    width: 140
                    height: 120

                    Column {
                        anchors.centerIn: parent
                        spacing: 8

                        // Ilustración ventana oscura
                        Rectangle {
                            width: 130
                            height: 80
                            radius: 8
                            color: "#1e1e24"
                            border.color: settingsBackend.isDark ? "#0071e3" : Qt.rgba(1, 1, 1, 0.15)
                            border.width: settingsBackend.isDark ? 2.5 : 1

                            Row {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: 6
                                spacing: 4
                                Rectangle { width: 6; height: 6; radius: 3; color: "#ff5f56" }
                                Rectangle { width: 6; height: 6; radius: 3; color: "#febc2e" }
                                Rectangle { width: 6; height: 6; radius: 3; color: "#28c840" }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.topMargin: 18
                                anchors.leftMargin: 4
                                anchors.bottomMargin: 4
                                width: 34
                                radius: 4
                                color: "#141418"
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.topMargin: 18
                                anchors.leftMargin: 42
                                anchors.rightMargin: 4
                                anchors.bottomMargin: 4
                                radius: 4
                                color: "#252730"
                            }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6

                            Rectangle {
                                width: 14
                                height: 14
                                radius: 7
                                color: settingsBackend.isDark ? "#0071e3" : "transparent"
                                border.color: settingsBackend.isDark ? "#0071e3" : theme.contentTextSecondary
                                border.width: 1.5

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: "#ffffff"
                                    visible: settingsBackend.isDark
                                }
                            }

                            Text {
                                text: "Oscuro"
                                color: theme.contentTextPrimary
                                font.pixelSize: 12
                                font.bold: settingsBackend.isDark
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: settingsBackend.setThemeMode("dark")
                    }
                }

                // Opción: AUTOMÁTICO
                Item {
                    width: 140
                    height: 120

                    Column {
                        anchors.centerIn: parent
                        spacing: 8

                        Rectangle {
                            width: 130
                            height: 80
                            radius: 8
                            color: "#e8e8ed"
                            border.color: Qt.rgba(0, 0, 0, 0.15)
                            border.width: 1
                            clip: true

                            // Mitad diagonal oscura
                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width / 2
                                color: "#1e1e24"
                            }

                            Row {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: 6
                                spacing: 4
                                Rectangle { width: 6; height: 6; radius: 3; color: "#ff5f56" }
                                Rectangle { width: 6; height: 6; radius: 3; color: "#febc2e" }
                                Rectangle { width: 6; height: 6; radius: 3; color: "#28c840" }
                            }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6

                            Rectangle {
                                width: 14
                                height: 14
                                radius: 7
                                color: "transparent"
                                border.color: theme.contentTextSecondary
                                border.width: 1.5
                            }

                            Text {
                                text: "Automático"
                                color: theme.contentTextPrimary
                                font.pixelSize: 12
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: settingsBackend.setThemeMode("auto")
                    }
                }
            }
        }

        // 2. COLOR DE ACENTO
        Column {
            width: parent.width
            spacing: 12

            Text {
                text: "Color de acento"
                color: theme.contentTextSecondary
                font.pixelSize: 12
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: 54
                radius: 10
                color: theme.contentCardBg
                border.color: theme.contentCardBorder
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 16

                    Repeater {
                        model: [
                            { color: "#0071e3", name: "Azul" },
                            { color: "#af52de", name: "Morado" },
                            { color: "#ff2d55", name: "Rosa" },
                            { color: "#ff3b30", name: "Rojo" },
                            { color: "#ff9500", name: "Naranja" },
                            { color: "#ffcc00", name: "Amarillo" },
                            { color: "#34c759", name: "Verde" },
                            { color: "#8e8e93", name: "Grafito" }
                        ]

                        delegate: Rectangle {
                            width: 26
                            height: 26
                            radius: 13
                            color: modelData.color
                            scale: accentMouse.containsMouse ? 1.15 : 1.0
                            Behavior on scale { NumberAnimation { duration: 120 } }

                            // Anillo concéntrico de selección
                            Rectangle {
                                anchors.centerIn: parent
                                width: 32
                                height: 32
                                radius: 16
                                color: "transparent"
                                border.color: modelData.color
                                border.width: 2
                                visible: settingsBackend.accent === modelData.color
                            }

                            MouseArea {
                                id: accentMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settingsBackend.setAccent(modelData.color)
                            }
                        }
                    }
                }
            }
        }

        // 3. EFECTOS DE VIDRIO LIQUID GLASS
        Column {
            width: parent.width
            spacing: 10

            Text {
                text: "Efectos visuales"
                color: theme.contentTextSecondary
                font.pixelSize: 12
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: 52
                radius: 10
                color: theme.contentCardBg
                border.color: theme.contentCardBorder
                border.width: 1

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    Text {
                        text: "✨"
                        font.pixelSize: 16
                    }

                    Column {
                        spacing: 2
                        Text {
                            text: "Vidrio translúcido y desenfoque (Liquid Glass)"
                            color: theme.contentTextPrimary
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Text {
                            text: "Efecto acrílico moderno en barras, dock y ventanas nativas"
                            color: theme.contentTextSecondary
                            font.pixelSize: 11
                        }
                    }
                }

                // Switch estilo iOS / macOS
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 24
                    radius: 12
                    color: "#34c759"

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        width: 20
                        height: 20
                        radius: 10
                        color: "#ffffff"
                    }
                }
            }
        }
    }
}

