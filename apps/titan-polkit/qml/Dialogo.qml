// Inti OS - ventana de contrasena de administrador (agente de polkit).
import QtQuick
import QtQuick.Controls
import QtQuick.Window

Window {
    id: ventana
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint
    width: Screen.width > 0 ? Screen.width : 1280
    height: Screen.height > 0 ? Screen.height : 800
    title: "Autenticación"

    TitanTheme { id: tema }

    readonly property var usuario: (agente.usuarios.length > agente.usuarioActual)
                                   ? agente.usuarios[agente.usuarioActual] : ({})
    property bool verDetalles: false

    onVisibleChanged: {
        if (visible) {
            campo.text = ""
            verDetalles = false
            campo.forceActiveFocus()
        }
    }

    property int fallosVistos: 0
    Connections {
        target: agente
        function onCambiado() {
            if (agente.esperandoRespuesta) campo.forceActiveFocus()
            if (agente.intentosFallidos > ventana.fallosVistos) {
                ventana.fallosVistos = agente.intentosFallidos
                campo.text = ""
                sacudida.restart()
            } else if (!agente.activo) {
                ventana.fallosVistos = 0
            }
        }
    }

    // Fondo oscurecido: deja claro que hasta responder no se sigue.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.03, 0.06, tema.isDark ? 0.55 : 0.40)
        MouseArea { anchors.fill: parent }   // no deja pasar clics
    }

    Rectangle {
        id: tarjeta
        width: 400
        height: contenido.implicitHeight + 48
        anchors.centerIn: parent
        radius: 18
        color: tema.isDark ? Qt.rgba(0.13, 0.14, 0.19, 0.96) : Qt.rgba(0.97, 0.97, 0.99, 0.97)
        border.color: tema.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
        border.width: 1

        // Sombra suave
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.margins: -1
            anchors.topMargin: 6
            radius: parent.radius + 2
            color: Qt.rgba(0, 0, 0, 0.28)
            opacity: 0.6
        }

        SequentialAnimation {
            id: sacudida
            property real x0: 0
            NumberAnimation { target: tarjeta; property: "anchors.horizontalCenterOffset"; to: -14; duration: 50 }
            NumberAnimation { target: tarjeta; property: "anchors.horizontalCenterOffset"; to: 12; duration: 70 }
            NumberAnimation { target: tarjeta; property: "anchors.horizontalCenterOffset"; to: -8; duration: 60 }
            NumberAnimation { target: tarjeta; property: "anchors.horizontalCenterOffset"; to: 5; duration: 50 }
            NumberAnimation { target: tarjeta; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40 }
        }

        Column {
            id: contenido
            anchors.top: parent.top
            anchors.topMargin: 26
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 52
            spacing: 14

            // Candado
            Item {
                width: parent.width
                height: 58
                Rectangle {
                    anchors.centerIn: parent
                    width: 58; height: 58; radius: 29
                    color: Qt.rgba(tema.accent.r, tema.accent.g, tema.accent.b, 0.16)
                    Canvas {
                        anchors.centerIn: parent
                        width: 26; height: 30
                        onPaint: {
                            var c = getContext("2d")
                            c.reset()
                            c.strokeStyle = tema.accent
                            c.fillStyle = tema.accent
                            c.lineWidth = 3
                            c.beginPath()
                            c.arc(13, 12, 7.5, Math.PI, 0)
                            c.lineTo(20.5, 14)
                            c.moveTo(5.5, 12)
                            c.lineTo(5.5, 14)
                            c.stroke()
                            c.beginPath()
                            c.roundedRect(1, 14, 24, 15, 4, 4)
                            c.fill()
                        }
                    }
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Se necesita la contraseña de administrador"
                color: tema.contentTextPrimary
                font.family: tema.fontFamily
                font.pixelSize: 15
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: agente.mensaje
                color: tema.contentTextSecondary
                font.family: tema.fontFamily
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                lineHeight: 1.15
            }

            // Cuenta con la que se autentica (si hay varias, se puede cambiar)
            Rectangle {
                width: parent.width
                height: 50
                radius: 12
                color: tema.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04)

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Rectangle {
                        width: 32; height: 32; radius: 16
                        color: tema.accent
                        Text {
                            anchors.centerIn: parent
                            text: ventana.usuario.inicial || "?"
                            color: "#ffffff"
                            font.family: tema.fontFamily
                            font.pixelSize: 14
                            font.bold: true
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: ventana.usuario.nombre || ""
                            color: tema.contentTextPrimary
                            font.family: tema.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                        Text {
                            text: ventana.usuario.login || ""
                            color: tema.contentTextSecondary
                            font.family: tema.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }
                Text {
                    visible: agente.usuarios.length > 1
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cambiar"
                    color: tema.accent
                    font.family: tema.fontFamily
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: agente.elegirUsuario((agente.usuarioActual + 1) % agente.usuarios.length)
                    }
                }
            }

            TextField {
                id: campo
                width: parent.width
                height: 38
                enabled: agente.activo
                placeholderText: agente.peticion || "Contraseña"
                echoMode: agente.eco ? TextInput.Normal : TextInput.Password
                passwordCharacter: "●"
                font.family: tema.fontFamily
                font.pixelSize: 14
                color: tema.contentTextPrimary
                placeholderTextColor: tema.contentTextSecondary
                leftPadding: 14
                rightPadding: 14
                background: Rectangle {
                    radius: 10
                    color: tema.isDark ? Qt.rgba(1, 1, 1, 0.08) : "#ffffff"
                    border.width: campo.activeFocus ? 2 : 1
                    border.color: agente.error.length > 0 ? "#ff453a"
                                  : campo.activeFocus ? tema.accent
                                  : (tema.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.16))
                }
                Keys.onReturnPressed: botonAceptar.pulsar()
                Keys.onEnterPressed: botonAceptar.pulsar()
                Keys.onEscapePressed: agente.cancelar()
            }

            Text {
                visible: text.length > 0
                width: parent.width
                text: agente.error
                color: "#ff453a"
                font.family: tema.fontFamily
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
            Text {
                visible: text.length > 0
                width: parent.width
                text: agente.aviso
                color: tema.contentTextSecondary
                font.family: tema.fontFamily
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            // Detalles (que accion y que programa), plegados
            Column {
                width: parent.width
                spacing: 6
                Text {
                    text: (ventana.verDetalles ? "▾ " : "▸ ") + "Detalles"
                    color: tema.contentTextSecondary
                    font.family: tema.fontFamily
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ventana.verDetalles = !ventana.verDetalles
                    }
                }
                Text {
                    visible: ventana.verDetalles
                    width: parent.width
                    text: "Acción: " + agente.accion + (agente.programa.length > 0 ? "\nPrograma: " + agente.programa : "")
                    color: tema.contentTextSecondary
                    font.family: tema.monoFamily
                    font.pixelSize: 10
                    wrapMode: Text.WrapAnywhere
                }
            }

            Row {
                anchors.right: parent.right
                spacing: 10
                topPadding: 4

                Rectangle {
                    width: 104; height: 32; radius: 9
                    color: ratonCancelar.containsMouse ? (tema.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10))
                                                       : (tema.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
                    Text {
                        anchors.centerIn: parent
                        text: "Cancelar"
                        color: tema.contentTextPrimary
                        font.family: tema.fontFamily
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: ratonCancelar
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: agente.cancelar()
                    }
                }
                Rectangle {
                    id: botonAceptar
                    width: 120; height: 32; radius: 9
                    readonly property bool listo: agente.esperandoRespuesta && campo.text.length > 0
                    function pulsar() { if (listo) agente.responder(campo.text) }
                    color: listo ? (ratonAceptar.containsMouse ? tema.accentHover : tema.accent)
                                 : Qt.rgba(tema.accent.r, tema.accent.g, tema.accent.b, 0.45)
                    Text {
                        anchors.centerIn: parent
                        text: agente.activo && !agente.esperandoRespuesta && agente.error.length === 0 ? "Comprobando…" : "Autenticar"
                        color: "#ffffff"
                        font.family: tema.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: ratonAceptar
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: botonAceptar.pulsar()
                    }
                }
            }
        }
    }
}
