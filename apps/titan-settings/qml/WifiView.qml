import QtQuick 2.15
import QtQuick.Controls 2.15

ScrollView {
    id: wifiView
    contentWidth: width
    clip: true

    TitanTheme { id: theme }

    property string selectedSsid: ""
    property string passwordInput: ""

    Column {
        width: parent.width - 48
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 20
        topPadding: 16
        bottomPadding: 32

        // 1. ENCABEZADO
        Row {
            width: parent.width
            spacing: 12

            Text {
                text: "Wi-Fi"
                color: theme.contentTextPrimary
                font.pixelSize: 18
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }

            Item { width: 10 }

            Rectangle {
                width: 80
                height: 26
                radius: 6
                color: scanMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                border.color: theme.contentCardBorder

                Text {
                    anchors.centerIn: parent
                    text: settingsBackend.wifiScanning ? "Buscando…" : "Buscar"
                    color: theme.contentTextPrimary
                    font.pixelSize: 11
                }

                MouseArea {
                    id: scanMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: !settingsBackend.wifiScanning && settingsBackend.wifiEnabled
                    onClicked: settingsBackend.scanWifi()
                }
            }
        }

        // 2. INTERRUPTOR PRINCIPAL
        Rectangle {
            width: parent.width
            height: 60
            radius: 10
            color: theme.contentCardBg
            border.color: theme.contentCardBorder
            border.width: 1

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Rectangle {
                    width: 32
                    height: 32
                    radius: 7
                    color: "#007aff"
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
                        color: theme.contentTextPrimary
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Text {
                        text: !settingsBackend.wifiEnabled ? "Desactivado" :
                              settingsBackend.wifiConnected ? ("Conectado a " + settingsBackend.wifiSsid) : "Buscando redes disponibles…"
                        color: theme.contentTextSecondary
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                id: wifiSwitch
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 24
                radius: 12
                color: settingsBackend.wifiEnabled ? "#34c759" : (theme.isDark ? "#39393d" : "#e5e5ea")
                Behavior on color { ColorAnimation { duration: 160 } }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: settingsBackend.wifiEnabled ? 22 : 2
                    width: 20
                    height: 20
                    radius: 10
                    color: "#ffffff"
                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingsBackend.wifiEnabled = !settingsBackend.wifiEnabled
                }
            }
        }

        // 3. DIÁLOGO DE CONEXIÓN INLINE SI SELECCIONÓ UNA RED
        Rectangle {
            visible: selectedSsid !== "" && settingsBackend.wifiEnabled
            width: parent.width
            height: 115
            radius: 10
            color: theme.contentCardBg
            border.color: "#007aff"
            border.width: 1.5

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Text {
                    text: "Conectar a «" + selectedSsid + "»"
                    color: theme.contentTextPrimary
                    font.pixelSize: 12
                    font.bold: true
                }

                Row {
                    width: parent.width
                    spacing: 10

                    Rectangle {
                        width: parent.width - 160
                        height: 32
                        radius: 6
                        color: theme.isDark ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(1, 1, 1, 0.8)
                        border.color: pwInput.activeFocus ? "#007aff" : theme.contentCardBorder

                        TextField {
                            id: pwInput
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            placeholderText: "Contraseña de la red…"
                            echoMode: TextInput.Password
                            color: theme.contentTextPrimary
                            font.pixelSize: 12
                            background: null
                            onAccepted: connectBtn.clicked()
                        }
                    }

                    Rectangle {
                        id: connectBtn
                        width: 70
                        height: 32
                        radius: 6
                        color: "#007aff"
                        signal clicked()

                        Text {
                            anchors.centerIn: parent
                            text: "Conectar"
                            color: "#ffffff"
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                settingsBackend.connectWifi(selectedSsid, pwInput.text);
                                selectedSsid = "";
                                pwInput.text = "";
                            }
                        }
                    }

                    Rectangle {
                        width: 70
                        height: 32
                        radius: 6
                        color: cancelPwMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                        border.color: theme.contentCardBorder

                        Text {
                            anchors.centerIn: parent
                            text: "Cancelar"
                            color: theme.contentTextPrimary
                            font.pixelSize: 11
                        }

                        MouseArea {
                            id: cancelPwMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { selectedSsid = ""; pwInput.text = ""; }
                        }
                    }
                }
            }
        }

        // 4. LISTA DE REDES DETECTADAS
        Column {
            visible: settingsBackend.wifiEnabled
            width: parent.width
            spacing: 8

            Text {
                text: "Redes Conocidas y Disponibles"
                color: theme.contentTextSecondary
                font.pixelSize: 12
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: Math.max(80, wifiListView.contentHeight + 16)
                radius: 10
                color: theme.contentCardBg
                border.color: theme.contentCardBorder
                border.width: 1

                ListView {
                    id: wifiListView
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    spacing: 2
                    model: settingsBackend.wifiNetworks

                    delegate: Rectangle {
                        width: wifiListView.width
                        height: 38
                        radius: 6
                        color: modelData.connected ? (theme.isDark ? Qt.rgba(0.0, 0.44, 0.89, 0.3) : Qt.rgba(0.0, 0.44, 0.89, 0.15)) :
                               netMouse.containsMouse ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)) : "transparent"

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Text {
                                text: modelData.signal > 75 ? "📶" : (modelData.signal > 40 ? "🛜" : "⋅)")
                                font.pixelSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    text: modelData.ssid || "Red Desconocida"
                                    color: theme.contentTextPrimary
                                    font.pixelSize: 12
                                    font.bold: modelData.connected
                                }

                                Text {
                                    text: modelData.security && modelData.security !== "Abierta" ? "Seguridad: " + modelData.security : "Red Abierta"
                                    color: theme.contentTextSecondary
                                    font.pixelSize: 9
                                }
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Rectangle {
                                visible: modelData.connected
                                width: 80
                                height: 24
                                radius: 5
                                color: Qt.rgba(1, 0.2, 0.2, 0.15)
                                border.color: Qt.rgba(1, 0.2, 0.2, 0.3)

                                Text {
                                    anchors.centerIn: parent
                                    text: "Desconectar"
                                    color: "#ff4d4d"
                                    font.pixelSize: 10
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: settingsBackend.disconnectWifi()
                                }
                            }

                            Text {
                                visible: !modelData.connected && modelData.security && modelData.security !== "Abierta"
                                text: "🔒"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: netMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.connected) return;
                                if (!modelData.security || modelData.security === "Abierta") {
                                    settingsBackend.connectWifi(modelData.ssid, "");
                                } else {
                                    selectedSsid = modelData.ssid;
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: settingsBackend.wifiNetworks.length === 0
                    anchors.centerIn: parent
                    text: settingsBackend.wifiScanning ? "Buscando redes cercanas…" : "No se encontraron redes Wi-Fi"
                    color: theme.contentTextSecondary
                    font.pixelSize: 12
                }
            }
        }
    }
}
