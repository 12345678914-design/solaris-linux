// Inti OS - pregunta al abrir un AppImage (lo lanza /usr/local/bin/titan-appimage
// con el runtime "qml" de Qt). Argumentos tras "--":
//   nombre  icono  oscuro(true/false)  acento(#rrggbb)  carpeta
// Sale con 10 = Instalar, 11 = Abrir solo esta vez, 0 = Cancelar.
import QtQuick
import QtQuick.Window

Window {
    id: ventana
    readonly property var args: {
        var a = Qt.application.arguments
        var i = a.indexOf("--")
        return i >= 0 ? a.slice(i + 1) : []
    }
    readonly property string nombre: args.length > 0 && args[0] ? args[0] : "Aplicación"
    readonly property string icono: args.length > 1 ? args[1] : ""
    readonly property bool oscuro: args.length > 2 && args[2] === "true"
    readonly property color acento: args.length > 3 && /^#[0-9a-fA-F]{6}$/.test(args[3]) ? args[3] : "#0071e3"
    readonly property string carpeta: args.length > 4 ? args[4] : ""

    readonly property color fondo: oscuro ? "#111113" : "#ffffff"
    readonly property color texto: oscuro ? "#f2f2f5" : "#1d1d1f"
    readonly property color tenue: oscuro ? "#a2aab8" : "#6e6e73"
    readonly property color boton: oscuro ? "#232326" : "#ebebef"

    title: "Instalar " + nombre
    width: 470
    height: Math.max(250, contenido.implicitHeight + 48)
    minimumWidth: 470
    minimumHeight: 250
    color: fondo
    visible: true
    flags: Qt.Dialog

    function terminar(codigo) { Qt.exit(codigo) }

    Shortcut { sequence: "Escape"; onActivated: ventana.terminar(0) }
    Shortcut { sequences: ["Return", "Enter"]; onActivated: ventana.terminar(10) }

    Column {
        id: contenido
        x: 24; y: 24
        width: parent.width - 48
        spacing: 16

        Row {
            spacing: 16
            width: parent.width
            Rectangle {
                width: 64; height: 64; radius: 14
                color: ventana.icono === "" ? Qt.rgba(ventana.acento.r, ventana.acento.g, ventana.acento.b, 0.18) : "transparent"
                Image {
                    anchors.fill: parent
                    source: ventana.icono === "" ? "" : "file://" + ventana.icono
                    sourceSize: Qt.size(128, 128)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                Text {
                    visible: ventana.icono === ""
                    anchors.centerIn: parent
                    text: ventana.nombre.charAt(0).toUpperCase()
                    color: ventana.acento
                    font.pixelSize: 30; font.bold: true
                }
            }
            Column {
                width: parent.width - 80
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    text: "¿Instalar «" + ventana.nombre + "»?"
                    color: ventana.texto
                    font.pixelSize: 17; font.bold: true
                    wrapMode: Text.Wrap
                }
                Text {
                    width: parent.width
                    text: "Aplicación AppImage"
                    color: ventana.tenue
                    font.pixelSize: 13
                }
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            color: ventana.texto
            font.pixelSize: 13
            lineHeight: 1.15
            text: "Al instalarla se guarda en tu cuenta y aparece en el menú de inicio. "
                  + "No hace falta la contraseña de administrador."
        }
        Rectangle {
            width: parent.width
            height: aviso.implicitHeight + 20
            radius: 10
            color: ventana.oscuro ? "#2a2410" : "#fff6dc"
            Text {
                id: aviso
                x: 12; y: 10
                width: parent.width - 24
                wrapMode: Text.Wrap
                color: ventana.oscuro ? "#ffd60a" : "#7a5a00"
                font.pixelSize: 12
                text: "⚠ Instala solo aplicaciones de quien confíes: un programa descargado "
                      + "puede hacer lo mismo que tú en tu cuenta."
            }
        }

        Row {
            spacing: 10
            x: parent.width - width
            component Boton: Rectangle {
                id: b
                property string texto: ""
                property bool principal: false
                signal pulsado()
                width: etiqueta.implicitWidth + 32
                height: 34; radius: 9
                color: principal ? (zona.pressed ? Qt.darker(ventana.acento, 1.15) : ventana.acento)
                                 : (zona.containsMouse ? Qt.darker(ventana.boton, ventana.oscuro ? 0.8 : 1.05) : ventana.boton)
                Text {
                    id: etiqueta
                    anchors.centerIn: parent
                    text: b.texto
                    color: b.principal ? "white" : ventana.texto
                    font.pixelSize: 13
                    font.weight: b.principal ? Font.DemiBold : Font.Normal
                }
                MouseArea { id: zona; anchors.fill: parent; hoverEnabled: true; onClicked: b.pulsado() }
            }
            Boton { texto: "Cancelar"; onPulsado: ventana.terminar(0) }
            Boton { texto: "Abrir solo esta vez"; onPulsado: ventana.terminar(11) }
            Boton { texto: "Instalar"; principal: true; onPulsado: ventana.terminar(10) }
        }
    }
}
