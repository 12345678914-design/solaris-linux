import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: controlCenterRoot
    width: 340
    height: shellBackend.controlCenterPage === 0 ? (contentCol.implicitHeight + 28) : 440
    radius: 18
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

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

    // Absorber clics dentro de la tarjeta para evitar que caigan en el fondo y cierren el Centro de Control
    MouseArea {
        anchors.fill: parent
        onClicked: {}
    }

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
    readonly property bool wifiActive: shellBackend.wifiEnabled && !shellBackend.wifiSuspendedForEthernet
    readonly property bool wifiConn: shellBackend.wifiConnected && !shellBackend.wifiSuspendedForEthernet
    readonly property bool btActive: shellBackend.bluetoothEnabled
    readonly property bool btConn: shellBackend.bluetoothConnected
    property bool batterySaverEnabled: false
    property bool wifiExpanded: false
    property bool btExpanded: false
    property string wifiConnectingSsid: ""

    Column {
        id: contentCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 14
        spacing: 12
        visible: shellBackend.controlCenterPage === 0

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
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    // Botón circular para alternar Encendido / Apagado
                    Rectangle {
                        width: 32; height: 32; radius: 16
                        color: controlCenterRoot.wifiActive ? titanTheme.accent : Qt.rgba(0.5, 0.5, 0.5, 0.3)
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Canvas {
                            id: wifiCanvas
                            width: 16; height: 16
                            anchors.centerIn: parent
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                ctx.strokeStyle = "#ffffff";
                                ctx.lineWidth = 1.8;
                                ctx.lineCap = "round";
                                ctx.beginPath();
                                ctx.arc(8, 13, 10, -Math.PI * 0.75, -Math.PI * 0.25);
                                ctx.stroke();
                                ctx.beginPath();
                                ctx.arc(8, 13, 6.5, -Math.PI * 0.75, -Math.PI * 0.25);
                                ctx.stroke();
                                ctx.fillStyle = "#ffffff";
                                ctx.beginPath();
                                ctx.arc(8, 13, 1.6, 0, Math.PI * 2);
                                ctx.fill();
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shellBackend.toggleWifi()
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 32 - 16 - 8
                        spacing: 2
                        Text {
                            text: "Wi-Fi"
                            color: titanTheme.contentTextPrimary
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Text {
                            text: !controlCenterRoot.wifiActive ? "Desactivado" : (controlCenterRoot.wifiConn ? (shellBackend.wifiSsid || "Conectado") : "Activado")
                            color: titanTheme.contentTextSecondary
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    // Flecha desplegable chevron
                    Text {
                        text: "›"
                        color: titanTheme.contentTextSecondary
                        font.pixelSize: 16
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.leftMargin: 42
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        shellBackend.openControlCenterWifi();
                    }
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
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    // Botón circular para alternar Encendido / Apagado
                    Rectangle {
                        width: 32; height: 32; radius: 16
                        color: controlCenterRoot.btActive ? titanTheme.accent : Qt.rgba(0.5, 0.5, 0.5, 0.3)
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Canvas {
                            id: btCanvas
                            width: 16; height: 16
                            anchors.centerIn: parent
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                ctx.strokeStyle = "#ffffff";
                                ctx.lineWidth = 1.8;
                                ctx.lineCap = "round";
                                ctx.lineJoin = "round";
                                ctx.beginPath();
                                ctx.moveTo(8, 2);
                                ctx.lineTo(8, 14);
                                ctx.moveTo(4, 5);
                                ctx.lineTo(12, 11);
                                ctx.lineTo(8, 14);
                                ctx.lineTo(4, 11);
                                ctx.lineTo(12, 5);
                                ctx.lineTo(8, 2);
                                ctx.stroke();
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shellBackend.toggleBluetooth()
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 32 - 16 - 8
                        spacing: 2
                        Text {
                            text: "Bluetooth"
                            color: titanTheme.contentTextPrimary
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Text {
                            text: !controlCenterRoot.btActive ? "Desactivado" : (controlCenterRoot.btConn ? (shellBackend.connectedBluetoothDevice || "Conectado") : "Activado")
                            color: titanTheme.contentTextSecondary
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    // Flecha desplegable chevron
                    Text {
                        text: "›"
                        color: titanTheme.contentTextSecondary
                        font.pixelSize: 16
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.leftMargin: 42
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        shellBackend.openControlCenterBluetooth();
                    }
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
                        
                        Canvas {
                            width: 16; height: 16
                            anchors.centerIn: parent
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                ctx.strokeStyle = "#ffffff";
                                ctx.fillStyle = "#ffffff";
                                ctx.lineWidth = 1.3;
                                ctx.beginPath();
                                ctx.rect(2, 4, 11, 8);
                                ctx.stroke();
                                ctx.fillRect(13, 6, 1.8, 4);
                                // Rayo de energía
                                ctx.beginPath();
                                ctx.moveTo(8, 5);
                                ctx.lineTo(6, 8.5);
                                ctx.lineTo(8.5, 8.5);
                                ctx.lineTo(6.5, 12);
                                ctx.lineTo(9.5, 7.5);
                                ctx.lineTo(7.5, 7.5);
                                ctx.closePath();
                                ctx.fill();
                            }
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
                        
                        Canvas {
                            width: 16; height: 16
                            anchors.centerIn: parent
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                ctx.fillStyle = "#ffffff";
                                ctx.beginPath();
                                if (titanTheme.isDark) {
                                    // Luna
                                    ctx.arc(8, 8, 6, 0, Math.PI * 2);
                                    ctx.fill();
                                    ctx.globalCompositeOperation = "destination-out";
                                    ctx.beginPath();
                                    ctx.arc(10.5, 6, 5.2, 0, Math.PI * 2);
                                    ctx.fill();
                                } else {
                                    // Sol
                                    ctx.arc(8, 8, 4, 0, Math.PI * 2);
                                    ctx.fill();
                                }
                            }
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
            radius: 14
            color: titanTheme.contentCardBg
            border.color: titanTheme.contentCardBorder
            border.width: 1
            clip: true

            Rectangle {
                id: brightFill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(12, parent.width * shellBackend.brightness)
                radius: 14
                color: titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.12)
                Behavior on width { NumberAnimation { duration: 60 } }
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Canvas {
                    id: sunCanvas
                    width: 18; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.strokeStyle = titanTheme.contentTextPrimary;
                        ctx.fillStyle = titanTheme.contentTextPrimary;
                        ctx.lineWidth = 1.6;
                        ctx.lineCap = "round";
                        ctx.beginPath();
                        ctx.arc(9, 9, 3.8, 0, Math.PI * 2);
                        ctx.fill();
                        for (var a = 0; a < 8; a++) {
                            var rad = a * Math.PI / 4;
                            ctx.beginPath();
                            ctx.moveTo(9 + Math.cos(rad) * 6, 9 + Math.sin(rad) * 6);
                            ctx.lineTo(9 + Math.cos(rad) * 8.2, 9 + Math.sin(rad) * 8.2);
                            ctx.stroke();
                        }
                    }
                }

                Text {
                    text: "Pantalla • " + Math.round(shellBackend.brightness * 100) + "%"
                    color: titanTheme.contentTextPrimary
                    font.pixelSize: 11
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function updateFromMouse(mouse) {
                    var val = Math.max(0.05, Math.min(1.0, mouse.x / width));
                    shellBackend.setBrightness(val);
                }
                onPressed: updateFromMouse(mouse)
                onPositionChanged: {
                    if (pressed) updateFromMouse(mouse);
                }
            }
        }

        // 4. DESLIZADOR DE VOLUMEN / SONIDO ESTILO macOS
        Rectangle {
            width: parent.width
            height: 48
            radius: 14
            color: titanTheme.contentCardBg
            border.color: titanTheme.contentCardBorder
            border.width: 1
            clip: true

            Rectangle {
                id: volFill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(0, parent.width * shellBackend.volume)
                radius: 14
                color: titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.12)
                Behavior on width { NumberAnimation { duration: 60 } }
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Canvas {
                    id: volCanvas
                    width: 18; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.strokeStyle = titanTheme.contentTextPrimary;
                        ctx.fillStyle = titanTheme.contentTextPrimary;
                        ctx.lineWidth = 1.6;
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        ctx.beginPath();
                        ctx.moveTo(3, 6);
                        ctx.lineTo(6, 6);
                        ctx.lineTo(10, 3);
                        ctx.lineTo(10, 15);
                        ctx.lineTo(6, 12);
                        ctx.lineTo(3, 12);
                        ctx.closePath();
                        ctx.fill();
                        ctx.beginPath();
                        ctx.arc(10, 9, 4, -Math.PI * 0.3, Math.PI * 0.3);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.arc(10, 9, 7, -Math.PI * 0.35, Math.PI * 0.35);
                        ctx.stroke();
                    }
                }

                Text {
                    text: "Sonido • " + Math.round(shellBackend.volume * 100) + "%"
                    color: titanTheme.contentTextPrimary
                    font.pixelSize: 11
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function updateFromMouse(mouse) {
                    var val = Math.max(0.0, Math.min(1.0, mouse.x / width));
                    shellBackend.setVolume(val);
                }
                onPressed: updateFromMouse(mouse)
                onPositionChanged: {
                    if (pressed) updateFromMouse(mouse);
                }
            }
        }
    }

    // ── SUBPÁGINA DEDICADA DE CONEXIÓN WI-FI ──────────────────────────
    Item {
        id: wifiSubPage
        anchors.fill: parent
        anchors.margins: 14
        visible: shellBackend.controlCenterPage === 1

        Column {
            anchors.fill: parent
            spacing: 12

            // Barra superior de navegación: Botón Volver + Título + Toggle Switch
            Item {
                width: parent.width
                height: 32

                // Botón Volver con área generosa (flecha + título interactivo)
                Rectangle {
                    id: backWifiBtn
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: backWifiRow.implicitWidth + 16
                    height: 30
                    radius: 8
                    color: backWifiMouse.containsMouse ? (titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"

                    Row {
                        id: backWifiRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "‹"
                            color: titanTheme.accent
                            font.pixelSize: 22
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "Wi-Fi"
                            color: titanTheme.contentTextPrimary
                            font.pixelSize: 15
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: backWifiMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shellBackend.controlCenterPage = 0
                    }
                }

                // Switch estilo iOS / macOS
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 24
                    radius: 12
                    color: controlCenterRoot.wifiActive ? titanTheme.accent : Qt.rgba(0.5, 0.5, 0.5, 0.35)
                    Behavior on color { ColorAnimation { duration: 140 } }

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                        x: controlCenterRoot.wifiActive ? parent.width - width - 2 : 2
                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shellBackend.toggleWifi()
                    }
                }
            }

            // Subcabecera con botón de escanear/refrescar
            Item {
                width: parent.width
                height: 24

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Redes conocidas y cercanas"
                    color: titanTheme.contentTextSecondary
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: scanSubWifiText.implicitWidth + 20
                    height: 22
                    radius: 11
                    color: scanSubWifiMouse.containsMouse ? Qt.rgba(0.5, 0.5, 0.5, 0.25) : Qt.rgba(0.5, 0.5, 0.5, 0.12)

                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            text: "↻"
                            color: titanTheme.accent
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Text {
                            id: scanSubWifiText
                            text: shellBackend.wifiScanning ? "Buscando..." : "Buscar"
                            color: titanTheme.contentTextSecondary
                            font.pixelSize: 10
                        }
                    }

                    MouseArea {
                        id: scanSubWifiMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shellBackend.scanWifi()
                    }
                }
            }

            // Lista desplazable de redes Wi-Fi
            ScrollView {
                width: parent.width
                height: parent.height - 76
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                Column {
                    width: wifiSubPage.width
                    spacing: 6

                    Repeater {
                        model: shellBackend.wifiNetworks
                        delegate: Column {
                            width: wifiSubPage.width
                            spacing: 4

                            Rectangle {
                                width: parent.width
                                height: 42
                                radius: 10
                                color: subNetMouse.containsMouse ? (titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : (modelData.connected ? Qt.rgba(0, 0.44, 0.89, 0.15) : titanTheme.contentCardBg)
                                border.color: modelData.connected ? titanTheme.accent : titanTheme.contentCardBorder
                                border.width: 1

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10

                                    // Icono señal Wi-Fi
                                    Canvas {
                                        width: 16; height: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        property int sig: modelData.signal || 50
                                        property bool isConn: modelData.connected || false
                                        onPaint: {
                                            var ctx = getContext("2d");
                                            ctx.reset();
                                            ctx.lineWidth = 1.5;
                                            ctx.lineCap = "round";
                                            ctx.strokeStyle = (sig >= 70) ? (isConn ? titanTheme.accent : "#ffffff") : Qt.rgba(1, 1, 1, 0.25);
                                            ctx.beginPath();
                                            ctx.arc(8, 13, 10, -Math.PI * 0.75, -Math.PI * 0.25);
                                            ctx.stroke();
                                            ctx.strokeStyle = (sig >= 40) ? (isConn ? titanTheme.accent : "#ffffff") : Qt.rgba(1, 1, 1, 0.25);
                                            ctx.beginPath();
                                            ctx.arc(8, 13, 6.5, -Math.PI * 0.75, -Math.PI * 0.25);
                                            ctx.stroke();
                                            ctx.fillStyle = (sig >= 10) ? (isConn ? titanTheme.accent : "#ffffff") : Qt.rgba(1, 1, 1, 0.25);
                                            ctx.beginPath();
                                            ctx.arc(8, 13, 1.5, 0, Math.PI * 2);
                                            ctx.fill();
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 26 - subActionBtn.width - 12
                                        spacing: 2

                                        Text {
                                            text: modelData.ssid || "Red Desconocida"
                                            color: titanTheme.contentTextPrimary
                                            font.pixelSize: 12
                                            font.bold: true
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }

                                        Text {
                                            text: modelData.connected ? "Conectado" : (modelData.signal + "% • " + (modelData.security || "WPA2"))
                                            color: modelData.connected ? "#30d158" : titanTheme.contentTextSecondary
                                            font.pixelSize: 10
                                            font.bold: modelData.connected
                                        }
                                    }

                                    Item {
                                        id: subActionBtn
                                        width: subActBtnBg.width
                                        height: 26
                                        anchors.verticalCenter: parent.verticalCenter

                                        Rectangle {
                                            id: subActBtnBg
                                            width: subActText.implicitWidth + 16
                                            height: 24
                                            radius: 12
                                            color: modelData.connected ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : (subActMouse.containsMouse ? titanTheme.accent : Qt.rgba(0.5, 0.5, 0.5, 0.2))
                                            border.color: modelData.connected ? "#ff453a" : "transparent"
                                            border.width: 1

                                            Text {
                                                id: subActText
                                                anchors.centerIn: parent
                                                text: modelData.connected ? "Desconectar" : "Conectar"
                                                color: modelData.connected ? "#ff453a" : (subActMouse.containsMouse ? "#ffffff" : titanTheme.contentTextPrimary)
                                                font.pixelSize: 10
                                                font.bold: true
                                            }

                                            MouseArea {
                                                id: subActMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (modelData.connected) {
                                                        shellBackend.disconnectWifi();
                                                    } else {
                                                        if (modelData.security === "Abierta" || modelData.security === "NONE") {
                                                            shellBackend.connectWifi(modelData.ssid);
                                                        } else {
                                                            controlCenterRoot.wifiConnectingSsid = (controlCenterRoot.wifiConnectingSsid === modelData.ssid) ? "" : modelData.ssid;
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: subNetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData.connected) {
                                            shellBackend.disconnectWifi();
                                        } else if (modelData.security === "Abierta" || modelData.security === "NONE") {
                                            shellBackend.connectWifi(modelData.ssid);
                                        } else {
                                            controlCenterRoot.wifiConnectingSsid = (controlCenterRoot.wifiConnectingSsid === modelData.ssid) ? "" : modelData.ssid;
                                        }
                                    }
                                }
                            }

                            // Password prompt
                            Rectangle {
                                visible: controlCenterRoot.wifiConnectingSsid === modelData.ssid && !modelData.connected
                                width: parent.width
                                height: 36
                                radius: 8
                                color: titanTheme.isDark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.4)
                                border.color: titanTheme.accent
                                border.width: 1

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 6

                                    TextInput {
                                        id: subPassInput
                                        width: parent.width - subJoinBtn.width - 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        echoMode: TextInput.Password
                                        color: titanTheme.contentTextPrimary
                                        font.pixelSize: 11
                                        selectByMouse: true
                                        Keys.onReturnPressed: {
                                            shellBackend.connectWifi(modelData.ssid, subPassInput.text);
                                            controlCenterRoot.wifiConnectingSsid = "";
                                        }
                                        Text {
                                            text: "Contraseña de la red..."
                                            color: titanTheme.contentTextSecondary
                                            visible: !subPassInput.text && !subPassInput.activeFocus
                                            font.pixelSize: 11
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    Rectangle {
                                        id: subJoinBtn
                                        width: 56
                                        height: parent.height
                                        radius: 6
                                        color: titanTheme.accent

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Unirse"
                                            color: "#ffffff"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                shellBackend.connectWifi(modelData.ssid, subPassInput.text);
                                                controlCenterRoot.wifiConnectingSsid = "";
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: shellBackend.wifiNetworks.length === 0
                        text: shellBackend.wifiScanning ? "Buscando redes Wi-Fi cercanas..." : "No se encontraron redes Wi-Fi"
                        color: titanTheme.contentTextSecondary
                        font.pixelSize: 11
                        font.italic: true
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }
                }
            }
        }
    }

    // ── SUBPÁGINA DEDICADA DE CONEXIÓN BLUETOOTH ───────────────────────
    Item {
        id: btSubPage
        anchors.fill: parent
        anchors.margins: 14
        visible: shellBackend.controlCenterPage === 2

        Column {
            anchors.fill: parent
            spacing: 12

            // Barra superior de navegación: Botón Volver + Título + Toggle Switch
            Item {
                width: parent.width
                height: 32

                // Botón Volver con área generosa (flecha + título interactivo)
                Rectangle {
                    id: backBtBtn
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: backBtRow.implicitWidth + 16
                    height: 30
                    radius: 8
                    color: backBtMouse.containsMouse ? (titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"

                    Row {
                        id: backBtRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "‹"
                            color: titanTheme.accent
                            font.pixelSize: 22
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "Bluetooth"
                            color: titanTheme.contentTextPrimary
                            font.pixelSize: 15
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: backBtMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shellBackend.controlCenterPage = 0
                    }
                }

                // Switch estilo iOS / macOS
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 24
                    radius: 12
                    color: controlCenterRoot.btActive ? titanTheme.accent : Qt.rgba(0.5, 0.5, 0.5, 0.35)
                    Behavior on color { ColorAnimation { duration: 140 } }

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                        x: controlCenterRoot.btActive ? parent.width - width - 2 : 2
                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shellBackend.toggleBluetooth()
                    }
                }
            }

            // Subcabecera con botón de escanear/refrescar
            Item {
                width: parent.width
                height: 24

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Dispositivos conocidos y cercanos"
                    color: titanTheme.contentTextSecondary
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: scanSubBtText.implicitWidth + 20
                    height: 22
                    radius: 11
                    color: scanSubBtMouse.containsMouse ? Qt.rgba(0.5, 0.5, 0.5, 0.25) : Qt.rgba(0.5, 0.5, 0.5, 0.12)

                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            text: "↻"
                            color: titanTheme.accent
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Text {
                            id: scanSubBtText
                            text: shellBackend.bluetoothScanning ? "Buscando..." : "Buscar"
                            color: titanTheme.contentTextSecondary
                            font.pixelSize: 10
                        }
                    }

                    MouseArea {
                        id: scanSubBtMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shellBackend.scanBluetooth()
                    }
                }
            }

            // Lista desplazable de dispositivos Bluetooth
            ScrollView {
                width: parent.width
                height: parent.height - 76
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                Column {
                    width: btSubPage.width
                    spacing: 6

                    Repeater {
                        model: shellBackend.bluetoothDevices
                        delegate: Rectangle {
                            width: btSubPage.width
                            height: 42
                            radius: 10
                            color: subDevMouse.containsMouse ? (titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : (modelData.connected ? Qt.rgba(0, 0.44, 0.89, 0.15) : titanTheme.contentCardBg)
                            border.color: modelData.connected ? titanTheme.accent : titanTheme.contentCardBorder
                            border.width: 1

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                // Icono Bluetooth
                                Canvas {
                                    width: 16; height: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    property bool isConn: modelData.connected || false
                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.reset();
                                        ctx.strokeStyle = isConn ? titanTheme.accent : "#ffffff";
                                        ctx.lineWidth = 1.4;
                                        ctx.lineCap = "round";
                                        ctx.lineJoin = "round";
                                        ctx.beginPath();
                                        ctx.moveTo(8, 2);
                                        ctx.lineTo(8, 14);
                                        ctx.moveTo(4, 5);
                                        ctx.lineTo(12, 11);
                                        ctx.lineTo(8, 14);
                                        ctx.lineTo(4, 11);
                                        ctx.lineTo(12, 5);
                                        ctx.lineTo(8, 2);
                                        ctx.stroke();
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 26 - subBtActBtn.width - 12
                                    spacing: 2

                                    Text {
                                        text: modelData.name || modelData.mac || "Dispositivo Bluetooth"
                                        color: titanTheme.contentTextPrimary
                                        font.pixelSize: 12
                                        font.bold: true
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }

                                    Text {
                                        text: modelData.connected ? "Conectado" : (modelData.paired ? "Enlazado" : "Disponible")
                                        color: modelData.connected ? "#30d158" : titanTheme.contentTextSecondary
                                        font.pixelSize: 10
                                        font.bold: modelData.connected
                                    }
                                }

                                Item {
                                    id: subBtActBtn
                                    width: subBtActBtnBg.width
                                    height: 26
                                    anchors.verticalCenter: parent.verticalCenter

                                    Rectangle {
                                        id: subBtActBtnBg
                                        width: subBtActText.implicitWidth + 16
                                        height: 24
                                        radius: 12
                                        color: modelData.connected ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : (subBtActMouse.containsMouse ? titanTheme.accent : Qt.rgba(0.5, 0.5, 0.5, 0.2))
                                        border.color: modelData.connected ? "#ff453a" : "transparent"
                                        border.width: 1

                                        Text {
                                            id: subBtActText
                                            anchors.centerIn: parent
                                            text: modelData.connected ? "Desconectar" : "Conectar"
                                            color: modelData.connected ? "#ff453a" : (subBtActMouse.containsMouse ? "#ffffff" : titanTheme.contentTextPrimary)
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        MouseArea {
                                            id: subBtActMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.connected) {
                                                    shellBackend.disconnectBluetooth(modelData.mac);
                                                } else {
                                                    shellBackend.connectBluetooth(modelData.mac);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: subDevMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.connected) {
                                        shellBackend.disconnectBluetooth(modelData.mac);
                                    } else {
                                        shellBackend.connectBluetooth(modelData.mac);
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: shellBackend.bluetoothDevices.length === 0
                        text: shellBackend.bluetoothScanning ? "Buscando dispositivos Bluetooth cercanos..." : "No se detectaron dispositivos Bluetooth"
                        color: titanTheme.contentTextSecondary
                        font.pixelSize: 11
                        font.italic: true
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }
                }
            }
        }
    }
}

