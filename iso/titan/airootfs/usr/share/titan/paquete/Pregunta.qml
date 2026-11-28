// Inti OS - pregunta al abrir un instalador .deb (Ubuntu/Debian) o .rpm
// (Fedora). La lanza /usr/local/bin/titan-paquete con el runtime "qml" de Qt.
// Argumentos tras "--":
//   nombre  icono  oscuro(true/false)  acento(#rrggbb)  tipo(deb/rpm)  enTienda(nombre o "")  descripcion
// Sale con 12 = App Store (instalar o buscar), 10 = Instalar de todos modos, 0 = Cancelar.
import QtQuick
import QtQuick.Window

Window {
    id: ventana
    readonly property var args: {
        var a = Qt.application.arguments
        var i = a.indexOf("--")
        return i >= 0 ? a.slice(i + 1) : []
    }
    readonly property string nombre: args.length > 0 && args[0] ? args[0] : "Programa"
    readonly property string icono: args.length > 1 ? args[1] : ""
    readonly property bool oscuro: args.length > 2 && args[2] === "true"
    readonly property color acento: args.length > 3 && /^#[0-9a-fA-F]{6}$/.test(args[3]) ? args[3] : "#0071e3"
    readonly property string tipo: args.length > 4 && args[4] === "rpm" ? "rpm" : "deb"
    readonly property string enTienda: args.length > 5 ? args[5] : ""
    readonly property string descripcion: args.length > 6 ? args[6] : ""
    readonly property string sistema: tipo === "rpm" ? "Fedora" : "Ubuntu y Debian"

    readonly property color fondo: oscuro ? "#111113" : "#ffffff"
    readonly property color texto: oscuro ? "#f2f2f5" : "#1d1d1f"
    readonly property color tenue: oscuro ? "#a2aab8" : "#6e6e73"
    readonly property color boton: oscuro ? "#232326" : "#ebebef"
    readonly property color caja: oscuro ? "#161618" : "#f5f5f7"

    title: "Instalar " + nombre
    width: 540
    height: Math.max(280, contenido.implicitHeight + 48)
    minimumWidth: 540
    minimumHeight: 280
    color: fondo
    visible: true
    flags: Qt.Dialog

    function terminar(codigo) { Qt.exit(codigo) }

    Shortcut { sequence: "Escape"; onActivated: ventana.terminar(0) }
    Shortcut { sequences: ["Return", "Enter"]; onActivated: ventana.terminar(ventana.enTienda !== "" ? 12 : 10) }

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
                    text: ventana.descripcion !== "" ? ventana.descripcion : "Instalador ." + ventana.tipo
                    color: ventana.tenue
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            color: ventana.texto
            font.pixelSize: 13
            lineHeight: 1.15
            text: "Este archivo (." + ventana.tipo + ") es un instalador hecho para " + ventana.sistema + "."
                  + (ventana.enTienda !== ""
                     ? " La buena noticia: «" + ventana.enTienda + "» está en la App Store de Inti, donde se instala bien y se actualiza solo."
                     : " No está en la App Store, pero Inti puede instalarlo solo en tu cuenta, sin contraseña.")
        }

        // Recomendado: la App Store
        Rectangle {
            visible: ventana.enTienda !== ""
            width: parent.width
            height: rec.implicitHeight + 22
            radius: 10
            color: Qt.rgba(ventana.acento.r, ventana.acento.g, ventana.acento.b, ventana.oscuro ? 0.18 : 0.10)
            Text {
                id: rec
                x: 12; y: 11
                width: parent.width - 24
                wrapMode: Text.Wrap
                color: ventana.texto
                font.pixelSize: 12
                text: "✓ Recomendado: instalar desde la App Store. Funciona mejor y recibe las actualizaciones automáticamente."
            }
        }

        // Instalar de todos modos: lo que hay que saber
        Rectangle {
            width: parent.width
            height: nota.implicitHeight + 20
            radius: 10
            color: ventana.oscuro ? "#2a2410" : "#fff6dc"
            Text {
                id: nota
                x: 12; y: 10
                width: parent.width - 24
                wrapMode: Text.Wrap
                color: ventana.oscuro ? "#ffd60a" : "#7a5a00"
                font.pixelSize: 12
                text: (ventana.enTienda !== "" ? "Si lo instalas de todos modos: se guarda" : "Se guarda")
                      + " solo en tu cuenta y no se actualiza solo (para actualizar, abre el instalador nuevo). "
                      + "Algunos programas no funcionan así (controladores, VPN, servicios). Instala solo programas de quien confíes."
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
            Boton {
                texto: ventana.enTienda !== "" ? "Instalar de todos modos" : "Buscar en la App Store"
                onPulsado: ventana.terminar(ventana.enTienda !== "" ? 10 : 12)
            }
            Boton {
                principal: true
                texto: ventana.enTienda !== "" ? "Instalar desde la App Store" : "Instalar en mi cuenta"
                onPulsado: ventana.terminar(ventana.enTienda !== "" ? 12 : 10)
            }
        }
    }
}
