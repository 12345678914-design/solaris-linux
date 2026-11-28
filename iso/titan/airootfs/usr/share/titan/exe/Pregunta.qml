// Inti OS - pregunta al abrir un programa de Windows sin Wine (la lanza
// /usr/local/bin/titan-exe con el runtime "qml" de Qt). Argumentos tras "--":
//   fichero  oscuro(true/false)  acento(#rrggbb)  vivo(true/false)
// Sale con 10 = Instalar Wine y abrir, 12 = Buscar en la App Store, 0 = Cancelar.
import QtQuick
import QtQuick.Window

Window {
    id: ventana
    readonly property var args: {
        var a = Qt.application.arguments
        var i = a.indexOf("--")
        return i >= 0 ? a.slice(i + 1) : []
    }
    readonly property string fichero: args.length > 0 && args[0] ? args[0] : "programa.exe"
    readonly property bool oscuro: args.length > 1 && args[1] === "true"
    readonly property color acento: args.length > 2 && /^#[0-9a-fA-F]{6}$/.test(args[2]) ? args[2] : "#0071e3"
    readonly property bool vivo: args.length > 3 && args[3] === "true"

    readonly property color fondo: oscuro ? "#111113" : "#ffffff"
    readonly property color texto: oscuro ? "#f2f2f5" : "#1d1d1f"
    readonly property color tenue: oscuro ? "#a2aab8" : "#6e6e73"
    readonly property color boton: oscuro ? "#232326" : "#ebebef"

    title: "Programa de Windows"
    width: 520
    height: Math.max(260, contenido.implicitHeight + 48)
    minimumWidth: 520
    minimumHeight: 260
    color: fondo
    visible: true
    flags: Qt.Dialog

    function terminar(codigo) { Qt.exit(codigo) }

    Shortcut { sequence: "Escape"; onActivated: ventana.terminar(0) }
    Shortcut { sequences: ["Return", "Enter"]; onActivated: ventana.terminar(ventana.vivo ? 0 : 10) }

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
                color: Qt.rgba(ventana.acento.r, ventana.acento.g, ventana.acento.b, 0.16)
                // Ventanita de 4 cuadros (programa de Windows)
                Grid {
                    anchors.centerIn: parent
                    columns: 2; spacing: 3
                    Repeater {
                        model: 4
                        delegate: Rectangle { width: 14; height: 14; radius: 2; color: ventana.acento }
                    }
                }
            }
            Column {
                width: parent.width - 80
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    text: "«" + ventana.fichero + "» es un programa de Windows"
                    color: ventana.texto
                    font.pixelSize: 17; font.bold: true
                    wrapMode: Text.Wrap
                }
                Text {
                    width: parent.width
                    text: ventana.vivo ? "Sesión en vivo" : "Se puede abrir con Wine"
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
            text: ventana.vivo
                  ? "En la sesión en vivo no se pueden instalar programas. Instala Inti OS en el equipo y vuelve a abrirlo."
                  : "Inti abre muchos programas de Windows con Wine. Hace falta instalarlo una vez (unos 600 MB de descarga) y "
                    + "te pedirá la contraseña de administrador.\n\nAntes mira si el programa está en la App Store: "
                    + "la versión para Linux suele ir mejor."
        }
        Rectangle {
            visible: !ventana.vivo
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
                text: "⚠ Abre solo programas de quien confíes. Algunos programas de Windows (juegos con antitrampas, "
                      + "controladores, antivirus) no funcionan con Wine."
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
            Boton { texto: ventana.vivo ? "Cerrar" : "Cancelar"; principal: ventana.vivo; onPulsado: ventana.terminar(0) }
            Boton { visible: !ventana.vivo; texto: "Buscar en la App Store"; onPulsado: ventana.terminar(12) }
            Boton { visible: !ventana.vivo; texto: "Instalar Wine y abrir"; principal: true; onPulsado: ventana.terminar(10) }
        }
    }
}
