import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: topBar
    height: 28

    TitanTheme { id: titanTheme }

    // ---------- Barra de menús transparente (estilo Tahoe) ----------
    // Sin fondo: el texto flota sobre el fondo de pantalla. Para que se lea
    // siempre, se mide el brillo de la franja superior del fondo y se elige
    // texto oscuro (fondo claro) o blanco (fondo oscuro), con una sombra muy
    // suave detrás. Sin fondo de pantalla, se usa el tema.
    readonly property string wallpaperPath: shellBackend.currentWallpaper ? shellBackend.currentWallpaper : ""
    property real wallLuma: -1          // 0..1, -1 = aún sin medir
    readonly property bool wallBright: wallLuma >= 0 ? wallLuma > 0.62 : !titanTheme.isDark
    readonly property color barText: wallBright ? "#1d1d1f" : "#ffffff"
    readonly property color barTextMuted: wallBright ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.65)
    readonly property color barHover: wallBright ? Qt.rgba(0, 0, 0, 0.09) : Qt.rgba(1, 1, 1, 0.20)

    function toUrl(p) {
        if (!p) return ""
        if (p.indexOf("://") !== -1 || p.indexOf("qrc:") === 0) return p
        return "file://" + p
    }

    color: "transparent"
    border.width: 0

    // Sombra suave de arriba abajo: da contraste sin parecer una barra.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: topBar.wallBright ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(0, 0, 0, 0.28) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // Medidor de brillo: dibuja el fondo en 16×40 px y promedia las 3 filas de
    // arriba (lo que queda detrás de la barra). Se repite solo al cambiar el fondo.
    Canvas {
        id: lumaProbe
        width: 16
        height: 40
        visible: false
        renderTarget: Canvas.Image
        property string src: topBar.toUrl(topBar.wallpaperPath)
        onSrcChanged: {
            topBar.wallLuma = -1
            if (src !== "") loadImage(src)
        }
        onImageLoaded: requestPaint()
        onPaint: {
            if (src === "" || !isImageLoaded(src)) return
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.drawImage(src, 0, 0, width, height)
            var d = ctx.getImageData(0, 0, width, 3).data
            var sum = 0, n = 0
            for (var i = 0; i < d.length; i += 4) {
                sum += (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255
                n++
            }
            if (n > 0) topBar.wallLuma = sum / n
        }
        Component.onCompleted: if (src !== "") loadImage(src)
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
                color: inicioMouseArea.containsMouse ? topBar.barHover : "transparent"
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
                    color: topBar.barText
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
                       ? topBar.barHover
                       : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Canvas {

                // Repintar si cambia el color del texto (tema o fondo)

                property color ink: topBar.barText

                onInkChanged: requestPaint()
                id: brushCanvas
                width: 16; height: 16
                anchors.centerIn: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = topBar.barText;
                    ctx.strokeStyle = topBar.barText;
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
                color: wifiMouse.containsMouse ? topBar.barHover : "transparent"
            }

            Canvas {

                // Repintar si cambia el color del texto (tema o fondo)

                property color ink: topBar.barText

                onInkChanged: requestPaint()
                width: 16; height: 16
                anchors.centerIn: parent
                opacity: shellBackend.wifiEnabled ? (shellBackend.wifiConnected ? 1.0 : 0.65) : 0.30
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = topBar.barText;
                    ctx.lineWidth = 1.6;
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    ctx.arc(8, 13, 10, -Math.PI * 0.75, -Math.PI * 0.25);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.arc(8, 13, 6.5, -Math.PI * 0.75, -Math.PI * 0.25);
                    ctx.stroke();
                    ctx.fillStyle = topBar.barText;
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
                color: btMouse.containsMouse ? topBar.barHover : "transparent"
            }

            Canvas {

                // Repintar si cambia el color del texto (tema o fondo)

                property color ink: topBar.barText

                onInkChanged: requestPaint()
                width: 15; height: 15
                anchors.centerIn: parent
                opacity: shellBackend.bluetoothEnabled ? 1.0 : 0.30
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = shellBackend.bluetoothConnected ? titanTheme.accent : topBar.barText;
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
                       ? topBar.barHover
                       : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Column {
                anchors.centerIn: parent
                spacing: 3

                Row {
                    spacing: 2
                    Rectangle { width: 4; height: 3; radius: 1.5; color: topBar.barText }
                    Rectangle { width: 10; height: 3; radius: 1.5; color: Qt.rgba(topBar.barText.r, topBar.barText.g, topBar.barText.b, 0.4) }
                }

                Row {
                    spacing: 2
                    Rectangle { width: 8; height: 3; radius: 1.5; color: Qt.rgba(topBar.barText.r, topBar.barText.g, topBar.barText.b, 0.4) }
                    Rectangle { width: 6; height: 3; radius: 1.5; color: topBar.barText }
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
                color: ethMouse.containsMouse ? topBar.barHover : "transparent"
            }

            Canvas {

                // Repintar si cambia el color del texto (tema o fondo)

                property color ink: topBar.barText

                onInkChanged: requestPaint()
                width: 16; height: 16
                anchors.centerIn: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = topBar.barText;
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
            readonly property color batBorderColor: topBar.wallBright ? "#000000" : "#ffffff"
            // Relleno verde si está cargando, rojo con poca batería; si no, del color del texto
            readonly property color batFillColor: shellBackend.isCharging ? "#30d158" : (shellBackend.batteryPercent <= 20 ? "#ff3b30" : topBar.barText)
            // Color de texto
            readonly property color batTextColor: shellBackend.isCharging ? "#30d158" : topBar.barText

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
            color: topBar.barText
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
                       ? topBar.barHover
                       : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Canvas {

                // Repintar si cambia el color del texto (tema o fondo)

                property color ink: topBar.barText

                onInkChanged: requestPaint()
                id: bellCanvas
                width: 16; height: 16
                anchors.centerIn: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = topBar.barText;
                    ctx.fillStyle = topBar.barText;
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
                border.color: topBar.wallBright ? "#ffffff" : "#1d1d1f"
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
                shellBackend.workspacesVisible = true
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
