// Ajustes > Bluetooth: dispositivos emparejados (guardados: se reconectan
// solos) y dispositivos cercanos para emparejar.
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Bluetooth"
    descripcion: "Los dispositivos emparejados quedan guardados y se vuelven a conectar solos al encenderlos."
    mensaje: conexiones.mensaje
    onMensajeCerrado: conexiones.limpiarMensaje()

    TitanTheme { id: tema }

    readonly property var mios: conexiones.dispositivos.filter(function (d) { return d.emparejado })
    readonly property var otros: conexiones.dispositivos.filter(function (d) { return !d.emparejado && d.nombre !== d.mac })

    Component.onCompleted: conexiones.leerBt()
    Timer { running: conexiones.btActivo; repeat: true; interval: 6000; onTriggered: if (!conexiones.buscando && conexiones.btOcupado === "") conexiones.leerBt() }

    function icono(tipo) {
        return { "Audio": "🎧", "Teclado": "⌨️", "Ratón": "🖱️", "Mando": "🎮", "Teléfono": "📱", "Ordenador": "💻" }[tipo] || "ᛒ"
    }

    Grupo {
        Fila {
            titulo: "Bluetooth"
            detalle: !conexiones.hayBt ? "No se encuentra ningún adaptador Bluetooth" : conexiones.btActivo ? "Encendido" : "Apagado"
            separador: false
            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                habilitado: conexiones.hayBt
                activo: conexiones.btActivo
                onAlternado: (v) => conexiones.setBt(v)
            }
        }
    }

    Grupo {
        visible: conexiones.btActivo
        etiqueta: "Mis dispositivos"
        nota: vista.mios.length === 0 ? "Aún no hay dispositivos emparejados." : ""
        Repeater {
            model: vista.mios
            delegate: Fila {
                required property var modelData
                required property int index
                titulo: vista.icono(modelData.tipo) + "  " + modelData.nombre
                detalle: (conexiones.btOcupado === modelData.mac ? "Conectando…" : modelData.conectado ? "Conectado" : "No conectado")
                         + (modelData.bateria >= 0 ? " · batería " + modelData.bateria + " %" : "")
                separador: index < vista.mios.length - 1
                Boton {
                    anchors.verticalCenter: parent.verticalCenter
                    texto: modelData.conectado ? "Desconectar" : "Conectar"
                    habilitado: conexiones.btOcupado === ""
                    onPulsado: modelData.conectado ? conexiones.desconectarBt(modelData.mac) : conexiones.conectarBt(modelData.mac)
                }
                Boton {
                    anchors.verticalCenter: parent.verticalCenter
                    texto: "Olvidar"
                    peligro: true
                    onPulsado: conexiones.olvidarBt(modelData.mac)
                }
            }
        }
    }

    Grupo {
        visible: conexiones.btActivo
        etiqueta: conexiones.buscando ? "Dispositivos cercanos · buscando…" : "Dispositivos cercanos"
        nota: "Pon el dispositivo en modo de emparejamiento y pulsa «Buscar»."
        Repeater {
            model: vista.otros
            delegate: Fila {
                required property var modelData
                required property int index
                titulo: vista.icono(modelData.tipo) + "  " + modelData.nombre
                detalle: conexiones.btOcupado === modelData.mac ? "Emparejando…" : modelData.tipo
                separador: index < vista.otros.length - 1
                Boton {
                    anchors.verticalCenter: parent.verticalCenter
                    texto: "Conectar"
                    principal: true
                    habilitado: conexiones.btOcupado === ""
                    onPulsado: conexiones.conectarBt(modelData.mac)
                }
            }
        }
    }

    Row {
        visible: conexiones.btActivo
        spacing: 8
        Boton { texto: conexiones.buscando ? "Buscando…" : "Buscar"; habilitado: !conexiones.buscando; onPulsado: conexiones.buscarBt() }
    }
}
