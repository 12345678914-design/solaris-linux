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
    
    // 2. LADO DERECHO: BATERÍA, WIFI, BLUETOOTH, CENTRO DE CONTROL, FECHA Y HORA
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        
        // Icono de Batería fiel al estado real del sistema
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            readonly property color batColor: {
                if (shellBackend.isCharging) return "#27ae60"; // verde cargando
                if (shellBackend.batteryPercent < 10) return "#e74c3c"; // rojo < 10%
                if (shellBackend.batteryPercent <= 20) return "#f39c12"; // amarillo <= 20%
                return titanTheme.isDark ? "#ffffff" : titanTheme.headerText; // blanco cuando no carga
            }

            Text {
                text: (shellBackend.isCharging ? "⚡ " : "") + shellBackend.batteryPercent + "%"
                color: parent.batColor
                font.pixelSize: 11
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: 20
                height: 11
                radius: 2.5
                color: "transparent"
                border.color: parent.batColor
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 1.5
                    width: Math.max(2, (parent.width - 3) * (shellBackend.batteryPercent / 100.0))
                    radius: 1.5
                    color: parent.parent.batColor
                }

                Rectangle {
                    anchors.left: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1.5
                    height: 4
                    radius: 0.5
                    color: parent.batColor
                }
            }
        }

        // Icono de Wi-Fi fiel al estado (encendido y conectado)
        Item {
            width: 22
            height: 22
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: wifiMouse.containsMouse ? (titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
            }

            Text {
                anchors.centerIn: parent
                text: "📶"
                font.pixelSize: 12
                opacity: shellBackend.wifiEnabled ? (shellBackend.wifiConnected ? 1.0 : 0.65) : 0.30
                color: titanTheme.headerText
            }

            MouseArea {
                id: wifiMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: shellBackend.toggleControlCenter()
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

            Text {
                anchors.centerIn: parent
                text: "ᛒ"
                font.pixelSize: 12
                font.bold: true
                color: shellBackend.bluetoothConnected ? titanTheme.accent : titanTheme.headerText
                opacity: shellBackend.bluetoothEnabled ? 1.0 : 0.30
            }

            MouseArea {
                id: btMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: shellBackend.toggleControlCenter()
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

            // Icono de dos sliders horizontales estilo macOS Control Center
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
    }
}
