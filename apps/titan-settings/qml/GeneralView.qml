import QtQuick 2.15
import QtQuick.Controls 2.15

ScrollView {
    id: generalView
    contentWidth: width
    clip: true

    TitanTheme { id: theme }

    Column {
        width: parent.width - 48
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 20
        topPadding: 16
        bottomPadding: 32

        // 1. IDIOMA
        Column {
            width: parent.width
            spacing: 8

            Text {
                text: "Idioma"
                color: theme.contentTextPrimary
                font.pixelSize: 13
                font.bold: true
            }

            Row {
                width: parent.width
                spacing: 12

                Text {
                    text: "Automático sigue el idioma del sistema"
                    color: theme.contentTextSecondary
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 340
                    wrapMode: Text.WordWrap
                }

                // Control segmentado de idioma estilo macOS
                Rectangle {
                    width: 320
                    height: 28
                    radius: 7
                    color: theme.isDark ? Qt.rgba(0.18, 0.20, 0.26, 0.8) : Qt.rgba(0.0, 0.0, 0.0, 0.08)
                    border.color: theme.contentCardBorder
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: 2
                        spacing: 2

                        Repeater {
                            model: [
                                { id: "auto", name: "Automático" },
                                { id: "en", name: "English" },
                                { id: "ru", name: "Русский" },
                                { id: "es", name: "Español" }
                            ]

                            delegate: Rectangle {
                                width: (parent.width - 6) / 4
                                height: parent.height
                                radius: 5
                                color: settingsBackend.language === modelData.id ?
                                       (theme.isDark ? "#323644" : "#ffffff") : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    color: theme.contentTextPrimary
                                    font.pixelSize: 10
                                    font.bold: settingsBackend.language === modelData.id
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: settingsBackend.language = modelData.id
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. SHELL
        Column {
            width: parent.width
            spacing: 8

            Text {
                text: "Shell"
                color: theme.contentTextSecondary
                font.pixelSize: 12
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: 128
                radius: 10
                color: theme.contentCardBg
                border.color: theme.contentCardBorder
                border.width: 1

                Column {
                    anchors.fill: parent

                    // Fila 1: Dock
                    Item {
                        width: parent.width
                        height: 63

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Text {
                                text: "Dock"
                                color: theme.contentTextPrimary
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text {
                                text: "Mostrar el Dock en la parte inferior de la pantalla"
                                color: theme.contentTextSecondary
                                font.pixelSize: 11
                            }
                        }

                        // Toggle verde estilo iOS
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44
                            height: 24
                            radius: 12
                            color: settingsBackend.dockEnabled ? "#34c759" : (theme.isDark ? "#39393d" : "#e5e5ea")
                            Behavior on color { ColorAnimation { duration: 160 } }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: settingsBackend.dockEnabled ? 22 : 2
                                width: 20
                                height: 20
                                radius: 10
                                color: "#ffffff"
                                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settingsBackend.dockEnabled = !settingsBackend.dockEnabled
                            }
                        }
                    }

                    // Separador 1px
                    Rectangle {
                        width: parent.width - 32
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 1
                        color: theme.contentCardBorder
                    }

                    // Fila 2: Barra de menús
                    Item {
                        width: parent.width
                        height: 64

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            width: parent.width - 80

                            Text {
                                text: "Barra de menús"
                                color: theme.contentTextPrimary
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text {
                                text: "Mostrar el panel en la parte superior de la pantalla. Spotlight, el Centro de control y el calendario están en él."
                                color: theme.contentTextSecondary
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        // Toggle verde estilo iOS
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44
                            height: 24
                            radius: 12
                            color: settingsBackend.topBarEnabled ? "#34c759" : (theme.isDark ? "#39393d" : "#e5e5ea")
                            Behavior on color { ColorAnimation { duration: 160 } }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: settingsBackend.topBarEnabled ? 22 : 2
                                width: 20
                                height: 20
                                radius: 10
                                color: "#ffffff"
                                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settingsBackend.topBarEnabled = !settingsBackend.topBarEnabled
                            }
                        }
                    }
                }
            }

            Text {
                text: "Si desactivas ambos, reabre esta ventana con: titan-settings"
                color: theme.contentTextSecondary
                font.pixelSize: 11
                leftPadding: 4
            }
        }

        // 3. ACTUALIZACIÓN DE SOFTWARE
        Column {
            width: parent.width
            spacing: 8

            Text {
                text: "Actualización de software"
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
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    Text {
                        text: "🔄"
                        font.pixelSize: 16
                    }

                    Text {
                        text: settingsBackend.updateStatus
                        color: theme.contentTextPrimary
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: updateBtnText.implicitWidth + 24
                    height: 28
                    radius: 6
                    color: updateMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.08) : (theme.isDark ? "#2c303c" : "#f0f0f4")
                    border.color: Qt.rgba(0, 0, 0, 0.15)
                    border.width: 1

                    Text {
                        id: updateBtnText
                        anchors.centerIn: parent
                        text: "Buscar actualizaciones"
                        color: theme.contentTextPrimary
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        id: updateMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: settingsBackend.checkUpdates()
                    }
                }
            }
        }
    }
}

