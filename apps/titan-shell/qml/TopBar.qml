import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: topBar
    height: 28

    TitanTheme { id: titanTheme }

    gradient: Gradient {
        GradientStop { position: 0.0; color: titanTheme.headerTop }
        GradientStop { position: 1.0; color: titanTheme.headerBottom }
    }
    
    border.width: 0
    
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: titanTheme.headerBorder
    }
    
    // 1. LADO IZQUIERDO: ÚNICAMENTE EL BOTÓN INICIO
    Row {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        
        // Botón Inicio estilo macOS Launchpad
        Item {
            id: inicioBtn
            width: inicioContent.width + 16
            height: 22
            anchors.verticalCenter: parent.verticalCenter
            
            Rectangle {
                anchors.fill: parent
                radius: 5
                color: inicioMouseArea.containsMouse ? (titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            
            Row {
                id: inicioContent
                anchors.centerIn: parent
                spacing: 6
                
                Image {
                    source: "qrc:/icons/launchpad.png"
                    width: 15
                    height: 15
                    anchors.verticalCenter: parent.verticalCenter
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                
                Text {
                    text: "Inicio"
                    color: titanTheme.headerText
                    font.pixelSize: 12
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            
            MouseArea {
                id: inicioMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: shellBackend.toggleLauncher()
            }
        }
    }
    
    // 2. LADO DERECHO: SELECTOR FONDO (BROCHA), WIFI, BLUETOOTH, CENTRO DE CONTROL, BATERÍA Y HORA
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        
        // Botón Selector de Fondo de Pantalla (Brocheta / Brocha de pintar - Ctrl + W)
        Item {
            id: wallpaperBtn
            width: 24
            height: 22
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: 5
                color: shellBackend.wallpaperPickerVisible || wpMouse.containsMouse
                       ? (titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.10))
                       : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Canvas {
                id: brushCanvas
                width: 16; height: 16
                anchors.centerIn: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = titanTheme.headerText;
                    ctx.strokeStyle = titanTheme.headerText;
                    ctx.lineWidth = 1.3;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    
                    // Mango de la brocha
                    ctx.beginPath();
                    ctx.moveTo(3, 14);
                    ctx.lineTo(6, 11);
                    ctx.lineTo(8, 13);
                    ctx.lineTo(5, 16);
                    ctx.closePath();
                    ctx.fill();

                    // Férula de metal
                    ctx.beginPath();
                    ctx.moveTo(5, 10);
                    ctx.lineTo(9, 6);
                    ctx.lineTo(12, 9);
                    ctx.lineTo(8, 13);
                    ctx.closePath();
                    ctx.stroke();

                    // Cerdas con pintura
                    ctx.beginPath();
                    ctx.moveTo(9, 6);
                    ctx.lineTo(13, 2);
                    ctx.lineTo(15, 4);
                    ctx.lineTo(12, 9);
                    ctx.closePath();
                    ctx.fill();
                }
            }

            MouseArea {
                id: wpMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: shellBackend.toggleWallpaperPicker()
            }
        }

        // Icono de Wi-Fi fiel al estado (encendido y conectado, oculto si hay cable Ethernet)
        Item {
            id: wifiItem
            visible: !shellBackend.ethernetConnected
            width: 22
            height: 22
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: wifiMouse.containsMouse ? (titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
            }

            Canvas {
                width: 16; height: 16
                anchors.centerIn: parent
                opacity: shellBackend.wifiEnabled ? (shellBackend.wifiConnected ? 1.0 : 0.65) : 0.30
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = titanTheme.headerText;
                    ctx.lineWidth = 1.6;
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    ctx.arc(8, 13, 10, -Math.PI * 0.75, -Math.PI * 0.25);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.arc(8, 13, 6.5, -Math.PI * 0.75, -Math.PI * 0.25);
                    ctx.stroke();
                    ctx.fillStyle = titanTheme.headerText;
                    ctx.beginPath();
                    ctx.arc(8, 13, 1.5, 0, Math.PI * 2);
                    ctx.fill();
                }
            }

            MouseArea {
                id: wifiMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (shellBackend.controlCenterVisible && shellBackend.controlCenterPage === 1) {
                        shellBackend.closeControlCenter()
                    } else {
                        shellBackend.openControlCenterWifi()
                    }
                }
            }
        }

        // Icono de Bluetooth fiel al estado (encendido y conectado)
        Item {
            width: 20
            height: 22
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: btMouse.containsMouse ? (titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
            }

            Canvas {
                width: 15; height: 15
                anchors.centerIn: parent
                opacity: shellBackend.bluetoothEnabled ? 1.0 : 0.30
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = shellBackend.bluetoothConnected ? titanTheme.accent : titanTheme.headerText;
                    ctx.lineWidth = 1.6;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    ctx.beginPath();
                    ctx.moveTo(7.5, 1.5);
                    ctx.lineTo(7.5, 13.5);
                    ctx.moveTo(3.5, 4.5);
                    ctx.lineTo(11.5, 10.5);
                    ctx.lineTo(7.5, 13.5);
                    ctx.lineTo(3.5, 10.5);
                    ctx.lineTo(11.5, 4.5);
                    ctx.lineTo(7.5, 1.5);
                    ctx.stroke();
                }
            }

            MouseArea {
                id: btMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (shellBackend.controlCenterVisible && shellBackend.controlCenterPage === 2) {
                        shellBackend.closeControlCenter()
                    } else {
                        shellBackend.openControlCenterBluetooth()
                    }
                }
            }
        }

        // Botón del Centro de Control estilo macOS (switches / sliders)
        Item {
            id: controlCenterBtn
            width: 24
            height: 22
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: 5
                color: shellBackend.controlCenterVisible || ccMouse.containsMouse
                       ? (titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.10))
                       : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Column {
                anchors.centerIn: parent
                spacing: 3

                Row {
                    spacing: 2
                    Rectangle { width: 4; height: 3; radius: 1.5; color: titanTheme.headerText }
                    Rectangle { width: 10; height: 3; radius: 1.5; color: Qt.rgba(titanTheme.headerText.r, titanTheme.headerText.g, titanTheme.headerText.b, 0.4) }
                }

                Row {
                    spacing: 2
                    Rectangle { width: 8; height: 3; radius: 1.5; color: Qt.rgba(titanTheme.headerText.r, titanTheme.headerText.g, titanTheme.headerText.b, 0.4) }
                    Rectangle { width: 6; height: 3; radius: 1.5; color: titanTheme.headerText }
                }
            }

            MouseArea {
                id: ccMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: shellBackend.toggleControlCenter()
            }
        }

        // Icono de Ethernet (visible al conectar cable, situado a lado de la batería)
        Item {
            id: ethItem
            visible: shellBackend.ethernetConnected
            width: 22
            height: 22
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: ethMouse.containsMouse ? (titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
            }

            Canvas {
                width: 16; height: 16
                anchors.centerIn: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = titanTheme.headerText;
                    ctx.fillStyle = "#30d158";
                    ctx.lineWidth = 1.3;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    ctx.beginPath();
                    ctx.rect(2.5, 3.5, 11, 9);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.moveTo(5, 5.5); ctx.lineTo(5, 8.5);
                    ctx.moveTo(8, 5.5); ctx.lineTo(8, 8.5);
                    ctx.moveTo(11, 5.5); ctx.lineTo(11, 8.5);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.moveTo(5.5, 12.5); ctx.lineTo(5.5, 14);
                    ctx.lineTo(10.5, 14); ctx.lineTo(10.5, 12.5);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.arc(11.5, 5, 1.2, 0, Math.PI * 2);
                    ctx.fill();
                }
            }

            MouseArea {
                id: ethMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: shellBackend.toggleControlCenter()
            }
        }

        // A lado de Centro de Control: Icono de Batería con su número al lado
        Row {
            id: batteryWidget
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            // Borde negro en modo claro, blanco en modo oscuro
            readonly property color batBorderColor: titanTheme.isDark ? "#ffffff" : "#000000"
            // Relleno verde si está cargando, blanco si no está cargando
            readonly property color batFillColor: shellBackend.isCharging ? "#30d158" : "#ffffff"
            // Color de texto
            readonly property color batTextColor: shellBackend.isCharging ? "#30d158" : (titanTheme.isDark ? "#ffffff" : "#1d1d1f")

            Text {
                text: (shellBackend.isCharging ? "⚡ " : "") + shellBackend.batteryPercent + "%"
                color: batteryWidget.batTextColor
                font.pixelSize: 11
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            Rectangle {
                width: 22
                height: 12
                radius: 3
                color: "transparent"
                border.color: batteryWidget.batBorderColor
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 1.5
                    width: Math.max(1.5, (parent.width - 3) * Math.min(1.0, Math.max(0.0, shellBackend.batteryPercent / 100.0)))
                    radius: 1.5
                    color: batteryWidget.batFillColor
                    Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                Rectangle {
                    anchors.left: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1.5
                    height: 4.5
                    radius: 0.8
                    color: batteryWidget.batBorderColor
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }

        // Fecha y Reloj digital
        Text {
            id: clockText
            text: Qt.formatDateTime(new Date(), "ddd d MMM  hh:mm")
            color: titanTheme.headerText
            font.pixelSize: 11
            font.weight: Font.Medium
            anchors.verticalCenter: parent.verticalCenter
            
            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: clockText.text = Qt.formatDateTime(new Date(), "ddd d MMM  hh:mm")
            }
        }

        // Botón de Notificaciones (Campana) a lado de la fecha/reloj
        Item {
            id: notifBellBtn
            width: 24
            height: 22
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: 5
                color: shellBackend.notificationCenterVisible || bellMouse.containsMouse
                       ? (titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.10))
                       : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Canvas {
                id: bellCanvas
                width: 16; height: 16
                anchors.centerIn: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = titanTheme.headerText;
                    ctx.fillStyle = titanTheme.headerText;
                    ctx.lineWidth = 1.3;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";

                    // Cuerpo de la campana
                    ctx.beginPath();
                    ctx.moveTo(8, 2.5);
                    ctx.bezierCurveTo(5.5, 3, 4.5, 6, 4.5, 9);
                    ctx.lineTo(3.2, 11.5);
                    ctx.lineTo(12.8, 11.5);
                    ctx.lineTo(11.5, 9);
                    ctx.bezierCurveTo(11.5, 6, 10.5, 3, 8, 2.5);
                    ctx.stroke();

                    // Borde inferior
                    ctx.beginPath();
                    ctx.moveTo(2.5, 11.5);
                    ctx.lineTo(13.5, 11.5);
                    ctx.stroke();

                    // Badajo (péndulo)
                    ctx.beginPath();
                    ctx.arc(8, 12.8, 1.3, 0, Math.PI * 2);
                    ctx.fill();

                    // Asa superior
                    ctx.beginPath();
                    ctx.arc(8, 2.2, 1.2, Math.PI, 0);
                    ctx.stroke();
                }
            }

            // Punto indicador rojo de notificaciones sin leer
            Rectangle {
                visible: shellBackend.unreadNotificationCount > 0
                anchors.top: parent.top
                anchors.topMargin: 2
                anchors.right: parent.right
                anchors.rightMargin: 2
                width: 7
                height: 7
                radius: 3.5
                color: "#ff3b30"
                border.color: titanTheme.headerTop
                border.width: 1
            }

            MouseArea {
                id: bellMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: shellBackend.toggleNotificationCenter()
            }
        }
    }

    // ── Hot Corner superior derecho para abrir el Sistema de Escritorios ────────
    Timer {
        id: hotCornerTimer
        interval: 90
        repeat: false
        onTriggered: {
            if (hotCornerWorkspaces.containsMouse && !shellBackend.workspacesVisible) {
                shellBackend.setWorkspacesVisible(true)
            }
        }
    }

    MouseArea {
        id: hotCornerWorkspaces
        anchors.top: parent.top
        anchors.right: parent.right
        width: 28
        height: parent.height
        z: 100
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            hotCornerTimer.start()
        }
        onExited: {
            hotCornerTimer.stop()
        }
        onClicked: {
            hotCornerTimer.stop()
            shellBackend.toggleWorkspaces()
        }
    }
}
