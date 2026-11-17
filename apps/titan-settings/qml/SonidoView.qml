// Ajustes > Sonido: salidas y entradas de PipeWire (pactl), volumen y avisos.
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Sonido"
    descripcion: "Elige por dónde sale el sonido y qué micrófono se usa."
    mensaje: dispositivos.aviso

    TitanTheme { id: tema }

    Component.onCompleted: dispositivos.leerSonido()
    // Auriculares conectados mientras la ventana está abierta, etc.
    Timer { running: true; repeat: true; interval: 4000; onTriggered: dispositivos.leerSonido() }

    component Lista: Grupo {
        id: lista
        property bool salida: true
        property var elementos: []
        Repeater {
            model: lista.elementos
            delegate: Item {
                required property var modelData
                required property int index
                width: lista.width
                height: modelData.predeterminado ? 92 : 46
                Rectangle {
                    anchors.fill: parent
                    color: modelData.predeterminado ? Qt.rgba(tema.accent.r, tema.accent.g, tema.accent.b, 0.08) : "transparent"
                    radius: 10
                }
                Rectangle {   // botón de radio
                    x: 16; y: 15
                    width: 16; height: 16; radius: 8
                    color: modelData.predeterminado ? tema.accent : "transparent"
                    border.color: modelData.predeterminado ? tema.accent : tema.contentTextSecondary
                    border.width: 1.5
                    Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "#ffffff"; visible: modelData.predeterminado }
                }
                Text {
                    x: 42; y: 14
                    width: parent.width - 60
                    text: modelData.descripcion
                    color: tema.contentTextPrimary
                    font.pixelSize: 12
                    font.bold: modelData.predeterminado
                    elide: Text.ElideRight
                }
                MouseArea {
                    width: parent.width; height: 46
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dispositivos.setPredeterminado(lista.salida, modelData.nombre)
                }
                Row {
                    visible: modelData.predeterminado
                    x: 42; y: 52
                    spacing: 10
                    Boton {
                        texto: modelData.silencio ? "🔇" : (lista.salida ? "🔊" : "🎙")
                        anchors.verticalCenter: parent.verticalCenter
                        onPulsado: dispositivos.setSilencio(lista.salida, modelData.nombre, !modelData.silencio)
                    }
                    Deslizador {
                        anchors.verticalCenter: parent.verticalCenter
                        ancho: Math.min(320, lista.width - 200)
                        desde: 0; hasta: 100
                        habilitado: !modelData.silencio
                        valor: modelData.volumen
                        onMovido: (v) => dispositivos.setVolumen(lista.salida, modelData.nombre, Math.round(v))
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.silencio ? "Silenciado" : modelData.volumen + " %"
                        color: tema.contentTextSecondary
                        font.pixelSize: 11
                    }
                }
                Rectangle {
                    visible: index < lista.elementos.length - 1
                    anchors.bottom: parent.bottom
                    x: 16; width: parent.width - 32; height: 1
                    color: tema.contentCardBorder
                }
            }
        }
    }

    Grupo {
        visible: !dispositivos.sonidoDisponible
        Fila {
            titulo: "No se encuentra el servidor de sonido"
            detalle: "PipeWire (pipewire-pulse) no responde."
            separador: false
            Boton { anchors.verticalCenter: parent.verticalCenter; texto: "Reintentar"; onPulsado: dispositivos.leerSonido() }
        }
    }

    Lista {
        etiqueta: "Salida"
        salida: true
        elementos: dispositivos.salidas
        visible: dispositivos.salidas.length > 0
    }
    Row {
        spacing: 8
        visible: dispositivos.salidas.length > 0
        Boton { texto: "Probar sonido"; onPulsado: dispositivos.probarSonido() }
    }

    Lista {
        etiqueta: "Entrada"
        salida: false
        elementos: dispositivos.entradas
        visible: dispositivos.entradas.length > 0
    }

    Grupo {
        etiqueta: "Avisos"
        Fila {
            titulo: "Sonido de las notificaciones"
            detalle: "No suena con No molestar activo"
            separador: false
            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                activo: { prefs.version; return prefs.b("Notificaciones/sonido") }
                onAlternado: (v) => prefs.poner("Notificaciones/sonido", v)
            }
        }
    }
}
