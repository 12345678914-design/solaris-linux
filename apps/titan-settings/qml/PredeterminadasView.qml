// Ajustes > Aplicaciones predeterminadas: con qué app se abre cada cosa.
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Aplicaciones predeterminadas"

    Component.onCompleted: predeterminadas.recargar()

    Grupo {
        etiqueta: "Abrir con"
        nota: "Lo que elijas aquí se usa al hacer doble clic en un archivo o al pulsar un enlace. Solo cambia para tu cuenta. Para un archivo suelto, usa clic derecho › Abrir con."
        Repeater {
            model: predeterminadas.tipos
            delegate: Fila {
                required property var modelData
                required property int index
                separador: index < predeterminadas.tipos.length - 1
                titulo: modelData.simbolo + "  " + modelData.nombre
                detalle: modelData.detalle
                Desplegable {
                    anchors.verticalCenter: parent.verticalCenter
                    ancho: 260
                    habilitado: modelData.opciones.length > 0
                    opciones: modelData.opciones.length > 0 ? modelData.opciones : [{ valor: "", texto: "Ninguna app instalada" }]
                    valor: modelData.actual
                    onElegido: (v) => { if (v !== "") predeterminadas.elegir(modelData.id, v) }
                }
            }
        }
    }

    Grupo {
        etiqueta: "¿Falta alguna?"
        nota: "Si una app no sale en la lista, instálala desde la App Store: aparecerá aquí sola."
    }
}
