import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: controlCenterRoot
    width: 320
    height: contentCol.implicitHeight + 28
    radius: 18

    TitanTheme { id: titanTheme }

    // Fondo Liquid Glass translúcido puro estilo macOS Sonoma
    gradient: Gradient {
        GradientStop { position: 0.0; color: titanTheme.windowBgTop }
        GradientStop { position: 0.5; color: titanTheme.windowBgMid }
        GradientStop { position: 1.0; color: titanTheme.windowBgBottom }
    }
    border.color: titanTheme.glassBorder
    border.width: 1
    clip: true

    // Brillo especular superior del cristal
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 24
        height: 1
        color: titanTheme.specularGlow
    }

    // Estados reactivos sincronizados con shellBackend
    readonly property bool wifiActive: shellBackend.wifiEnabled
    readonly property bool wifiConn: shellBackend.wifiConnected
    readonly property bool btActive: shellBackend.bluetoothEnabled
    readonly property bool btConn: shellBackend.bluetoothConnected
    property bool batterySaverEnabled: false
    property real brightnessLevel: 0.85
    property real volumeLevel: 0.70

    Column {
        id: contentCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 14
        spacing: 12

        // 1. FILA DE CONECTIVIDAD (WI-FI Y BLUETOOTH)
        Row {
            width: parent.width
            spacing: 10

            // Tarjeta Wi-Fi
            Rectangle {
                width: (parent.width - 10) / 2
                height: 64
                radius: 13
                color: controlCenterRoot.wifiActive ? Qt.rgba(0, 0.44, 0.89, 0.22) : titanTheme.contentCardBg
                border.color: controlCenterRoot.wifiActive ? titanTheme.accent : titanTheme.contentCardBorder
                border.width: 1
                Behavior on color { ColorAnimation { duration: 140 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 10

                    Rectangle {
                        width: 32; height: 32; radius: 16
                        color: controlCenterRoot.wifiActive ? titanTheme.accent : Qt.rgba(0.5, 0.5, 0.5, 0.3)
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "📶"
                            font.pixelSize: 14
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Wi-Fi"
                            color: titanTheme.contentTextPrimary
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Text {
                            text: !controlCenterRoot.wifiActive ? "Desactivado" : (controlCenterRoot.wifiConn ? "Conectado" : "Buscando...")
                            color: titanTheme.contentTextSecondary
                            font.pixelSize: 10
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.toggleWifi()
                }
            }

            // Tarjeta Bluetooth
            Rectangle {
                width: (parent.width - 10) / 2
                height: 64
                radius: 13
                color: controlCenterRoot.btActive ? Qt.rgba(0, 0.44, 0.89, 0.22) : titanTheme.contentCardBg
                border.color: controlCenterRoot.btActive ? titanTheme.accent : titanTheme.contentCardBorder
                border.width: 1
                Behavior on color { ColorAnimation { duration: 140 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 10

                    Rectangle {
                        width: 32; height: 32; radius: 16
                        color: controlCenterRoot.btActive ? titanTheme.accent : Qt.rgba(0.5, 0.5, 0.5, 0.3)
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "ᛒ"
                            color: "#ffffff"
                            font.pixelSize: 14
                            font.bold: true
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Bluetooth"
                            color: titanTheme.contentTextPrimary
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Text {
                            text: !controlCenterRoot.btActive ? "Desactivado" : (controlCenterRoot.btConn ? "Conectado" : "Activado")
                            color: titanTheme.contentTextSecondary
                            font.pixelSize: 10
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.toggleBluetooth()
                }
            }
        }

        // 2. FILA DE AHORRO DE BATERÍA Y MODO CLARO / OSCURO
        Row {
            width: parent.width
            spacing: 10

            // Tarjeta Ahorro de batería
            Rectangle {
                width: (parent.width - 10) / 2
                height: 58
                radius: 13
                color: controlCenterRoot.batterySaverEnabled ? Qt.rgba(0.18, 0.8, 0.44, 0.22) : titanTheme.contentCardBg
                border.color: controlCenterRoot.batterySaverEnabled ? "#27ae60" : titanTheme.contentCardBorder
                border.width: 1
                Behavior on color { ColorAnimation { duration: 140 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: controlCenterRoot.batterySaverEnabled ? "#27ae60" : Qt.rgba(0.5, 0.5, 0.5, 0.3)
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "🔋"
                            font.pixelSize: 13
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: "Ahorro batería"
                            color: titanTheme.contentTextPrimary
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Text {
                            text: controlCenterRoot.batterySaverEnabled ? "Activo" : "Inactivo"
                            color: titanTheme.contentTextSecondary
                            font.pixelSize: 10
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: controlCenterRoot.batterySaverEnabled = !controlCenterRoot.batterySaverEnabled
                }
            }

            // Tarjeta Modo Claro / Oscuro
            Rectangle {
                width: (parent.width - 10) / 2
                height: 58
                radius: 13
                color: titanTheme.isDark ? Qt.rgba(0.15, 0.2, 0.35, 0.35) : Qt.rgba(1, 0.8, 0.2, 0.25)
                border.color: titanTheme.contentCardBorder
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: titanTheme.isDark ? "#2c3e50" : "#f39c12"
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: titanTheme.isDark ? "🌙" : "☀️"
                            font.pixelSize: 13
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: "Tema"
                            color: titanTheme.contentTextPrimary
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Text {
                            text: titanTheme.isDark ? "Oscuro" : "Claro"
                            color: titanTheme.contentTextSecondary
                            font.pixelSize: 10
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof titanThemeManager !== "undefined") {
                            titanThemeManager.toggleTheme()
                        } else {
                            shellBackend.toggleTheme()
                        }
                    }
                }
            }
        }

        // 3. DESLIZADOR DE PANTALLA / BRILLO ESTILO macOS
        Rectangle {
            width: parent.width
            height: 48
            radius: 13
            color: titanTheme.contentCardBg
            border.color: titanTheme.contentCardBorder
            border.width: 1

            Row {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "☀️"
                    font.pixelSize: 15
                }

                Slider {
                    id: brightSlider
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40
                    from: 0.1
                    to: 1.0
                    value: controlCenterRoot.brightnessLevel
                    onMoved: controlCenterRoot.brightnessLevel = value
                }
            }
        }

        // 4. DESLIZADOR DE VOLUMEN / SONIDO ESTILO macOS
        Rectangle {
            width: parent.width
            height: 48
            radius: 13
            color: titanTheme.contentCardBg
            border.color: titanTheme.contentCardBorder
            border.width: 1

            Row {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "🔊"
                    font.pixelSize: 15
                }

                Slider {
                    id: volSlider
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40
                    from: 0.0
                    to: 1.0
                    value: controlCenterRoot.volumeLevel
                    onMoved: controlCenterRoot.volumeLevel = value
                }
            }
        }
    }
}

