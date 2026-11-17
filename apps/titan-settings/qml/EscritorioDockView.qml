// Ajustes > Escritorio y Dock (lo aplica titan-shell en vivo).
import QtQuick

PaginaAjustes {
    titulo: "Escritorio y Dock"
    descripcion: "Los cambios se ven al momento en el Dock y el escritorio."

    TitanTheme { id: tema }

    Grupo {
        etiqueta: "Dock"
        Fila {
            titulo: "Mostrar el Dock"
            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                activo: { prefs.version; return prefs.b("Dock/visible") }
                onAlternado: (v) => prefs.poner("Dock/visible", v)
            }
        }
        Fila {
            titulo: "Posición en la pantalla"
            Segmentos {
                anchors.verticalCenter: parent.verticalCenter
                anchoSegmento: 84
                opciones: [{ valor: "izquierda", texto: "Izquierda" }, { valor: "abajo", texto: "Abajo" }, { valor: "derecha", texto: "Derecha" }]
                valor: { prefs.version; return prefs.s("Dock/posicion") }
                onElegido: (v) => prefs.poner("Dock/posicion", v)
            }
        }
        Fila {
            titulo: "Tamaño"
            detalle: { prefs.version; return prefs.i("Dock/tamano") + " px" }
            Deslizador {
                anchors.verticalCenter: parent.verticalCenter
                ancho: 200
                desde: 28; hasta: 64; paso: 2
                valor: { prefs.version; return prefs.i("Dock/tamano") }
                onSoltado: (v) => prefs.poner("Dock/tamano", Math.round(v))
            }
        }
        Fila {
            titulo: "Ampliación"
            detalle: "Los iconos crecen al pasar el ratón"
            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                activo: { prefs.version; return prefs.b("Dock/ampliacion") }
                onAlternado: (v) => prefs.poner("Dock/ampliacion", v)
            }
        }
        Fila {
            titulo: "Ocultar y mostrar el Dock automáticamente"
            detalle: "Aparece al llevar el ratón al borde. Sin esto, solo se esconde con ventanas maximizadas."
            separador: false
            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                activo: { prefs.version; return prefs.b("Dock/ocultarAuto") }
                onAlternado: (v) => prefs.poner("Dock/ocultarAuto", v)
            }
        }
    }

    Grupo {
        etiqueta: "Escritorio"
        Fila {
            titulo: "Mostrar iconos en el escritorio"
            detalle: "Archivos de la carpeta Escritorio y unidades conectadas"
            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                activo: { prefs.version; return prefs.b("Escritorio/iconos") }
                onAlternado: (v) => prefs.poner("Escritorio/iconos", v)
            }
        }
        Fila {
            titulo: "Fondo de pantalla"
            separador: false
            Boton {
                anchors.verticalCenter: parent.verticalCenter
                texto: "Cambiar fondo…"
                onPulsado: settingsBackend.currentSection = "Fondo de pantalla"
            }
        }
    }
}
