import QtQuick 2.15
import QtQuick.Controls 2.15

// Pantalla de bloqueo estilo macOS Tahoe: el fondo de pantalla actual se ve
// tal cual (sin velo oscuro), con el reloj grande arriba y los controles de
// cristal encima. Solo dos degradados suaves arriba y abajo para que el texto
// se lea sobre cualquier fondo.
//
// Las ventanas abiertas NUNCA se ven: la capa es opaca (el fondo de pantalla
// se pinta aqui mismo), asi que bloquear no deja leer nada del escritorio.
Item {
    id: lockScreenRoot
    anchors.fill: parent

    property bool isUnlocking: false
    property bool hasError: false
    property bool confirmarCambio: false
    property bool panelUsuarios: false

    // Al activarse la pantalla de bloqueo, enfocar el campo de texto
    onVisibleChanged: {
        panelUsuarios = false;
        confirmarCambio = false;
        if (visible) {
            hasError = false;
            passInput.text = "";
            passInput.forceActiveFocus();
        }
    }

    // ── 1. FONDO: el fondo de pantalla actual, nítido ──────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#101218"

        Image {
            anchors.fill: parent
            source: shellBackend.currentWallpaper.length > 0 ? ("file://" + shellBackend.currentWallpaper) : ""
            sourceSize: Qt.size(lockScreenRoot.width, lockScreenRoot.height)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }

        // Legibilidad: sombra suave solo donde hay texto (reloj y controles)
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: parent.height * 0.42
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.30) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
            }
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height * 0.40
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.38) }
            }
        }
    }

    // Componentes de cristal reutilizados
    component Cristal: Rectangle {
        color: Qt.rgba(1, 1, 1, 0.16)
        border.color: Qt.rgba(1, 1, 1, 0.30)
        border.width: 1
    }

    component BotonRedondo: Item {
        id: botonRedondo
        property string icono: ""
        property string texto: ""
        signal pulsado()
        width: 64
        height: 66
        Cristal {
            id: circulo
            anchors.horizontalCenter: parent.horizontalCenter
            width: 44; height: 44; radius: 22
            color: zona.pressed ? Qt.rgba(1, 1, 1, 0.34) : (zona.containsMouse ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(1, 1, 1, 0.16))
            Behavior on color { ColorAnimation { duration: 120 } }
            Image {
                anchors.centerIn: parent
                width: 22; height: 22
                source: botonRedondo.icono
                sourceSize: Qt.size(44, 44)
            }
            MouseArea {
                id: zona
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: botonRedondo.pulsado()
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: circulo.bottom
            anchors.topMargin: 5
            text: botonRedondo.texto
            color: "#ffffff"
            opacity: zona.containsMouse ? 1 : 0.85
            font.pixelSize: 11
            font.weight: Font.Medium
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.25)
        }
    }

    component BotonPildora: Cristal {
        id: pildora
        property string icono: ""
        property string texto: ""
        property bool aviso: false
        signal pulsado()
        height: 36
        radius: 18
        width: filaPildora.implicitWidth + 30
        color: aviso ? Qt.rgba(1, 0.62, 0.04, 0.85)
                     : (zonaPildora.containsMouse ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(1, 1, 1, 0.16))
        Behavior on color { ColorAnimation { duration: 120 } }
        Row {
            id: filaPildora
            anchors.centerIn: parent
            spacing: 8
            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: 17; height: 17
                source: pildora.icono
                sourceSize: Qt.size(34, 34)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pildora.texto
                color: "#ffffff"
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }
        MouseArea {
            id: zonaPildora
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pildora.pulsado()
        }
    }

    // Timer para el reloj en tiempo real
    Timer {
        id: clockTimer
        interval: 1000
        running: lockScreenRoot.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = new Date();
            timeText.text = Qt.formatTime(now, "hh:mm");
            var fecha = now.toLocaleDateString(Qt.locale("es_ES"), "dddd, d 'de' MMMM");
            dateText.text = fecha.charAt(0).toUpperCase() + fecha.slice(1);
        }
    }

    // ── 2. CABECERA: candado, fecha y hora grande ──────────────────────────
    Column {
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.07
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 20; height: 20
            source: "qrc:/icons/simbolos/candado.svg"
            sourceSize: Qt.size(40, 40)
            opacity: 0.9
        }

        Item { width: 1; height: 8 }

        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#ffffff"
            opacity: 0.92
            font.pixelSize: 21
            font.weight: Font.DemiBold
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.18)
        }

        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#ffffff"
            opacity: 0.96
            font.pixelSize: Math.round(Math.min(lockScreenRoot.height * 0.16, 132))
            font.weight: Font.Bold
            font.letterSpacing: -2
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.18)
        }
    }

    // ── 3. ABAJO EN EL CENTRO: cuenta y contraseña (como macOS) ────────────
    Item {
        id: profileCard
        width: 300
        height: 190
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.max(110, parent.height * 0.13)

        property real shakeOffset: 0
        x: (parent.width - width) / 2 + shakeOffset

        Column {
            anchors.fill: parent
            spacing: 10

            // Avatar con monograma, borde de cristal
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 72
                height: 72
                radius: 36
                border.color: Qt.rgba(1, 1, 1, 0.55)
                border.width: 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#5aa9ff" }
                    GradientStop { position: 1.0; color: "#0a5bd6" }
                }

                Text {
                    anchors.centerIn: parent
                    text: (shellBackend.userDisplayName.length > 0) ? shellBackend.userDisplayName.charAt(0).toUpperCase() : "I"
                    color: "#ffffff"
                    font.pixelSize: 32
                    font.bold: true
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: shellBackend.userDisplayName
                color: "#ffffff"
                font.pixelSize: 16
                font.weight: Font.DemiBold
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.25)
            }

            // Campo de contraseña: píldora de cristal
            Cristal {
                id: passFieldContainer
                anchors.horizontalCenter: parent.horizontalCenter
                width: 220
                height: 36
                radius: 18
                // Cristal oscuro: se lee igual sobre fondos claros y oscuros
                color: Qt.rgba(0, 0, 0, passInput.activeFocus ? 0.30 : 0.22)
                border.color: hasError ? "#ff6961" : Qt.rgba(1, 1, 1, passInput.activeFocus ? 0.55 : 0.32)
                border.width: hasError ? 1.5 : 1

                TextField {
                    id: passInput
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: submitButton.left
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    echoMode: TextInput.Password
                    placeholderText: "Introduce la contraseña"
                    color: "#ffffff"
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.70)
                    font.pixelSize: 13
                    background: null
                    focus: true

                    onTextChanged: {
                        if (hasError) hasError = false;
                    }

                    onAccepted: tryUnlock()
                }

                // Flecha para entrar (aparece al escribir)
                Rectangle {
                    id: submitButton
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    radius: 13
                    opacity: passInput.text.length > 0 || shellBackend.isLiveSystem ? 1 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    color: submitMouse.pressed ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.30)

                    Image {
                        anchors.centerIn: parent
                        width: 15; height: 15
                        source: "qrc:/icons/simbolos/flecha.svg"
                        sourceSize: Qt.size(30, 30)
                    }

                    MouseArea {
                        id: submitMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tryUnlock()
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: hasError ? "Contraseña incorrecta" : (shellBackend.isLiveSystem ? "Pulsa Intro para entrar" : "")
                color: hasError ? "#ffb3ae" : Qt.rgba(1, 1, 1, 0.8)
                font.pixelSize: 12
                font.weight: Font.DemiBold
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.3)
            }
        }
    }

    // ANIMACIÓN SHAKE (SACUDIDA LATERAL ESTILO macOS CUANDO FALLA LA CONTRASEÑA)
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: profileCard; property: "shakeOffset"; to: -14; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: profileCard; property: "shakeOffset"; to: 14; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: profileCard; property: "shakeOffset"; to: -10; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: profileCard; property: "shakeOffset"; to: 10; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: profileCard; property: "shakeOffset"; to: -5; duration: 40; easing.type: Easing.OutQuad }
        NumberAnimation { target: profileCard; property: "shakeOffset"; to: 5; duration: 40; easing.type: Easing.OutQuad }
        NumberAnimation { target: profileCard; property: "shakeOffset"; to: 0; duration: 30; easing.type: Easing.OutQuad }
    }

    // ── 4. ABAJO A LA IZQUIERDA: cuentas ───────────────────────────────────
    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 28
        spacing: 10

        BotonPildora {
            visible: shellBackend.canSwitchUser
            icono: "qrc:/icons/simbolos/usuario.svg"
            texto: lockScreenRoot.confirmarCambio ? "Se cerrarán tus apps · pulsa otra vez" : "Cambiar de usuario"
            aviso: lockScreenRoot.confirmarCambio
            onPulsado: {
                if (lockScreenRoot.confirmarCambio) shellBackend.switchUser()
                else { lockScreenRoot.confirmarCambio = true; confirmarTimer.restart() }
            }
        }

        BotonPildora {
            visible: !shellBackend.isLiveSystem && usuarios.gestionDisponible
            icono: "qrc:/icons/simbolos/usuarios.svg"
            texto: "Usuarios y grupos"
            onPulsado: { usuarios.recargar(); lockScreenRoot.panelUsuarios = true }
        }
    }

    Timer {
        id: confirmarTimer
        interval: 4000
        onTriggered: lockScreenRoot.confirmarCambio = false
    }

    // ── 5. ABAJO A LA DERECHA: energía ─────────────────────────────────────
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 18
        spacing: 6

        BotonRedondo { icono: "qrc:/icons/simbolos/reposo.svg"; texto: "Reposo"; onPulsado: shellBackend.suspend() }
        BotonRedondo { icono: "qrc:/icons/simbolos/reiniciar.svg"; texto: "Reiniciar"; onPulsado: shellBackend.reboot() }
        BotonRedondo { icono: "qrc:/icons/simbolos/apagar.svg"; texto: "Apagar"; onPulsado: shellBackend.powerOff() }
    }

    // Panel de usuarios y grupos (compartido con titan-greeter)
    Loader {
        id: cargadorPanel
        anchors.fill: parent
        active: lockScreenRoot.panelUsuarios
        source: "qrc:/qml/PanelUsuarios.qml"
        onLoaded: item.forceActiveFocus()
        Connections {
            target: cargadorPanel.item
            function onCerrar() {
                lockScreenRoot.panelUsuarios = false
                passInput.forceActiveFocus()
            }
        }
    }

    function tryUnlock() {
        var success = shellBackend.authenticateLock(passInput.text);
        if (success) {
            hasError = false;
            passInput.text = "";
        } else {
            hasError = true;
            passInput.text = "";
            shakeAnim.start();
            passInput.forceActiveFocus();
        }
    }
}
