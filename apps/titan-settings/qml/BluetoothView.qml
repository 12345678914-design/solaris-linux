import QtQuick 2.15
import QtQuick.Controls 2.15

ScrollView {
    id: bluetoothView
    contentWidth: width
    clip: true

    TitanTheme { id: theme }

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
                text: "Bluetooth"
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
                color: scanBtMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                border.color: theme.contentCardBorder

                Text {
                    anchors.centerIn: parent
                    text: settingsBackend.bluetoothScanning ? "Buscando…" : "Buscar"
                    color: theme.contentTextPrimary
                    font.pixelSize: 11
                }

                MouseArea {
                    id: scanBtMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: !settingsBackend.bluetoothScanning && settingsBackend.bluetoothEnabled
                    onClicked: settingsBackend.scanBluetooth()
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
                        text: "ᛒ"
                        color: "#ffffff"
                        font.pixelSize: 16
                        font.bold: true
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: "Bluetooth"
                        color: theme.contentTextPrimary
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Text {
                        text: !settingsBackend.bluetoothEnabled ? "Desactivado" :
                              settingsBackend.bluetoothConnected ? ("Conectado a " + settingsBackend.connectedBluetoothDevice) : "Visible para otros dispositivos"
                        color: theme.contentTextSecondary
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                id: btSwitch
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 24
                radius: 12
                color: settingsBackend.bluetoothEnabled ? "#34c759" : (theme.isDark ? "#39393d" : "#e5e5ea")
                Behavior on color { ColorAnimation { duration: 160 } }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: settingsBackend.bluetoothEnabled ? 22 : 2
                    width: 20
                    height: 20
                    radius: 10
                    color: "#ffffff"
                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingsBackend.bluetoothEnabled = !settingsBackend.bluetoothEnabled
                }
            }
        }

        // 3. LISTA DE DISPOSITIVOS
        Column {
            visible: settingsBackend.bluetoothEnabled
            width: parent.width
            spacing: 8

            Text {
                text: "Mis Dispositivos y Cercanos"
                color: theme.contentTextSecondary
                font.pixelSize: 12
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: Math.max(80, btListView.contentHeight + 16)
                radius: 10
                color: theme.contentCardBg
                border.color: theme.contentCardBorder
                border.width: 1

                ListView {
                    id: btListView
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    spacing: 2
                    model: settingsBackend.bluetoothDevices

                    delegate: Rectangle {
                        width: btListView.width
                        height: 38
                        radius: 6
                        color: modelData.connected ? (theme.isDark ? Qt.rgba(0.0, 0.44, 0.89, 0.3) : Qt.rgba(0.0, 0.44, 0.89, 0.15)) :
                               devMouse.containsMouse ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)) : "transparent"

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Text {
                                text: "🎧"
                                font.pixelSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    text: modelData.name || modelData.mac || "Dispositivo Bluetooth"
                                    color: theme.contentTextPrimary
                                    font.pixelSize: 12
                                    font.bold: modelData.connected
                                }

                                Text {
                                    text: modelData.connected ? "Conectado" : modelData.mac
                                    color: modelData.connected ? "#34c759" : theme.contentTextSecondary
                                    font.pixelSize: 9
                                }
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 76
                            height: 24
                            radius: 5
                            color: modelData.connected ? Qt.rgba(1, 0.2, 0.2, 0.15) : (theme.isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.08))
                            border.color: modelData.connected ? Qt.rgba(1, 0.2, 0.2, 0.3) : theme.contentCardBorder

                            Text {
                                anchors.centerIn: parent
                                text: modelData.connected ? "Desconectar" : "Conectar"
                                color: modelData.connected ? "#ff4d4d" : theme.contentTextPrimary
                                font.pixelSize: 10
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.connected) {
                                        settingsBackend.disconnectBluetooth(modelData.mac);
                                    } else {
                                        settingsBackend.connectBluetooth(modelData.mac);
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: devMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            z: -1
                            onClicked: {
                                if (modelData.connected) {
                                    settingsBackend.disconnectBluetooth(modelData.mac);
                                } else {
                                    settingsBackend.connectBluetooth(modelData.mac);
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: settingsBackend.bluetoothDevices.length === 0
                    anchors.centerIn: parent
                    text: settingsBackend.bluetoothScanning ? "Buscando dispositivos cercanos…" : "No se encontraron dispositivos Bluetooth"
                    color: theme.contentTextSecondary
                    font.pixelSize: 12
                }
            }
        }
    }
}
