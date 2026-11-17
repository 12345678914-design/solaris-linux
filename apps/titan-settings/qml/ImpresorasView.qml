// Ajustes > Impresoras y escaneres (CUPS + SANE).
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Impresoras y escáneres"
    descripcion: "Las impresoras de la red (AirPrint / IPP Everywhere) y las USB modernas aparecen solas, sin instalar controladores."

    Component.onCompleted: sistema.refrescar("Impresoras y escáneres")
    Timer {
        interval: 8000
        repeat: true
        running: vista.visible
        onTriggered: sistema.refrescar("Impresoras y escáneres")
    }

    TitanTheme { id: tema }

    Grupo {
        etiqueta: "Impresoras"
        Fila {
            visible: sistema.impresoras.length === 0
            separador: false
            titulo: "No hay impresoras"
            detalle: "Enciende la impresora o conéctala por USB; si no aparece, añádela a mano."
        }
        Repeater {
            model: sistema.impresoras
            delegate: Fila {
                required property var modelData
                required property int index
                separador: index < sistema.impresoras.length - 1
                titulo: modelData.nombre.replace(/_/g, " ")
                detalle: modelData.estado + (modelData.predeterminada ? " · Predeterminada" : "")
            }
        }
    }

    Row {
        spacing: 10
        Boton {
            texto: "Añadir impresora…"
            principal: true
            onPulsado: sistema.abrir("system-config-printer")
        }
        Boton {
            texto: "Escanear un documento…"
            onPulsado: sistema.abrir("simple-scan")
        }
    }
}
