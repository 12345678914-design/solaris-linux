import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: lockScreenRoot
    anchors.fill: parent

    property bool isUnlocking: false
    property bool hasError: false

    // Al activarse la pantalla de bloqueo, enfocar el campo de texto
    onVisibleChanged: {
        if (visible) {
            hasError = false;
            passInput.text = "";
            passInput.forceActiveFocus();
        }
    }

    // 1. FONDO DIFUMINADO ESTILO macOS CON WALLPAPER ACTUAL
    Rectangle {
        anchors.fill: parent
        color: "#08090d"

        Image {
            anchors.fill: parent
            source: shellBackend.currentWallpaper.length > 0 ? ("file://" + shellBackend.currentWallpaper) : ""
            fillMode: Image.PreserveAspectCrop
            opacity: 0.28
        }

        // Tinte de vidrio oscuro líquido
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.04, 0.05, 0.08, 0.88) }
                GradientStop { position: 0.5; color: Qt.rgba(0.07, 0.09, 0.14, 0.82) }
                GradientStop { position: 1.0; color: Qt.rgba(0.03, 0.04, 0.07, 0.92) }
            }
        }
    }

    // Timer para el reloj en tiempo real
    Timer {
        id: clockTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            var now = new Date();
            timeText.text = Qt.formatTime(now, "hh:mm");
            dateText.text = Qt.formatDate(now, "dddd, d 'de' MMMM");
        }
    }

    // 2. CABECERA: RELOJ ELEGANTE ESTILO macOS
    Column {
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.12
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4

        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(new Date(), "dddd, d 'de' MMMM")
            color: "#e2e6f0"
            font.pixelSize: 18
            font.weight: Font.Medium
        }

        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(new Date(), "hh:mm")
            color: "#ffffff"
            font.pixelSize: 76
            font.weight: Font.Light
            font.letterSpacing: -1.5
        }
    }

    // 3. CENTRO: TARJETA DE PERFIL Y CAMPO DE CONTRASEÑA
    Item {
        id: profileCard
        anchors.centerIn: parent
        width: 320
        height: 240

        property real shakeOffset: 0
        x: (parent.width - width) / 2 + shakeOffset

        Column {
            anchors.fill: parent
            spacing: 14

            // A. Avatar circular con monograma
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 92
                height: 92
                radius: 46
                color: "#1e2433"
                border.color: Qt.rgba(1, 1, 1, 0.28)
                border.width: 2.5

                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#007aff" }
                    GradientStop { position: 1.0; color: "#0040a8" }
                }

                Text {
                    anchors.centerIn: parent
                    text: (shellBackend.userDisplayName.length > 0) ? shellBackend.userDisplayName.charAt(0).toUpperCase() : "I"
                    color: "#ffffff"
                    font.pixelSize: 42
                    font.bold: true
                }
            }

            // B. Nombre del usuario
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: shellBackend.userDisplayName
                color: "#ffffff"
                font.pixelSize: 17
                font.bold: true
                font.letterSpacing: 0.3
            }

            // C. Campo de texto redondeado para contraseña estilo macOS
            Rectangle {
                id: passFieldContainer
                anchors.horizontalCenter: parent.horizontalCenter
                width: 230
                height: 34
                radius: 17
                color: Qt.rgba(1, 1, 1, 0.12)
                border.color: passInput.activeFocus ? "#0a84ff" : (hasError ? "#ff453a" : Qt.rgba(1, 1, 1, 0.24))
                border.width: passInput.activeFocus || hasError ? 1.5 : 1

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 6
                    spacing: 6

                    TextField {
                        id: passInput
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 34
                        echoMode: TextInput.Password
                        placeholderText: "Contraseña"
                        color: "#ffffff"
                        placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)
                        font.pixelSize: 13
                        background: null
                        focus: true

                        onTextChanged: {
                            if (hasError) hasError = false;
                        }

                        onAccepted: tryUnlock()
                    }

                    // Botón flecha derecha (Enter gráfico)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        radius: 12
                        color: submitMouse.containsMouse ? "#0062cc" : (passInput.text.length > 0 || shellBackend.isLiveSystem ? "#007aff" : Qt.rgba(1, 1, 1, 0.2))

                        Text {
                            anchors.centerIn: parent
                            text: "→"
                            color: "#ffffff"
                            font.pixelSize: 13
                            font.bold: true
                        }

                        MouseArea {
                            id: submitMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tryUnlock()
                        }
                    }
                }
            }

            // D. Mensaje de error si la contraseña no coincide
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Contraseña incorrecta"
                color: "#ff453a"
                font.pixelSize: 11
                font.bold: true
                opacity: hasError ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 150 } }
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

    // 4. PIE DE PÁGINA: ACCIONES DE ENERGÍA ESTILO macOS
    Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 36

        // Suspender
        Column {
            spacing: 6
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 40
                height: 40
                radius: 20
                color: suspMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1)

                Text {
                    anchors.centerIn: parent
                    text: "🌙"
                    font.pixelSize: 16
                }

                MouseArea {
                    id: suspMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.suspend()
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Reposo"
                color: "#c0c4d2"
                font.pixelSize: 11
            }
        }

        // Reiniciar
        Column {
            spacing: 6
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 40
                height: 40
                radius: 20
                color: reBootMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1)

                Text {
                    anchors.centerIn: parent
                    text: "🔄"
                    font.pixelSize: 16
                }

                MouseArea {
                    id: reBootMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.reboot()
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Reiniciar"
                color: "#c0c4d2"
                font.pixelSize: 11
            }
        }

        // Apagar
        Column {
            spacing: 6
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 40
                height: 40
                radius: 20
                color: pwrMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1)

                Text {
                    anchors.centerIn: parent
                    text: "⏻"
                    font.pixelSize: 16
                    color: "#ffffff"
                }

                MouseArea {
                    id: pwrMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.powerOff()
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Apagar"
                color: "#c0c4d2"
                font.pixelSize: 11
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
