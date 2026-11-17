// Ajustes > Accesibilidad
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Accesibilidad"
    descripcion: "Herramientas para usar el equipo sin ver la pantalla o con dificultades de visión."

    Component.onCompleted: sistema.refrescar("Accesibilidad")

    Grupo {
        etiqueta: "Visión"
        nota: "Atajo para encender y apagar el lector en cualquier momento: Super + Alt + S. Se recuerda para la próxima sesión."
        Fila {
            titulo: "Lector de pantalla"
            detalle: "Orca lee en voz alta lo que hay en la pantalla."
            Interruptor {
                activo: sistema.lector
                onAlternado: function(v) { sistema.setLector(v) }
            }
        }
        Fila {
            separador: false
            titulo: "Voz, velocidad y teclas de Orca"
            Boton {
                texto: "Configurar…"
                onPulsado: sistema.abrir("orca")
            }
        }
    }
}
