// Ajustes > Concentración: No molestar ahora o con horario.
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Concentración"
    descripcion: "Con No molestar activo, las notificaciones se guardan en el centro de notificaciones pero no aparecen ni suenan. Los avisos urgentes (batería agotándose) sí se ven."

    TitanTheme { id: tema }

    // 00:00, 00:30 ... 23:30
    readonly property var horas: {
        var r = []
        for (var h = 0; h < 24; ++h)
            for (var m = 0; m < 60; m += 30) {
                var t = (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
                r.push({ valor: t, texto: t })
            }
        return r
    }

    Grupo {
        etiqueta: "No molestar"
        Fila {
            titulo: "Activar ahora"
            detalle: { prefs.version; return prefs.noMolestarActivo() ? "Ahora mismo está activo" : "Ahora mismo está desactivado" }
            separador: false
            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                activo: { prefs.version; return prefs.b("Notificaciones/noMolestar") }
                onAlternado: (v) => prefs.poner("Notificaciones/noMolestar", v)
            }
        }
    }

    Grupo {
        etiqueta: "Horario"
        nota: "Si «Hasta» es antes que «Desde», el horario pasa la medianoche (por ejemplo, de 22:00 a 07:00)."
        Fila {
            titulo: "Activar No molestar con horario"
            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                activo: { prefs.version; return prefs.b("Concentracion/programado") }
                onAlternado: (v) => prefs.poner("Concentracion/programado", v)
            }
        }
        Fila {
            titulo: "Desde"
            Desplegable {
                anchors.verticalCenter: parent.verticalCenter
                ancho: 100
                opciones: vista.horas
                habilitado: { prefs.version; return prefs.b("Concentracion/programado") }
                valor: { prefs.version; return prefs.s("Concentracion/desde") }
                onElegido: (v) => prefs.poner("Concentracion/desde", v)
            }
        }
        Fila {
            titulo: "Hasta"
            separador: false
            Desplegable {
                anchors.verticalCenter: parent.verticalCenter
                ancho: 100
                opciones: vista.horas
                habilitado: { prefs.version; return prefs.b("Concentracion/programado") }
                valor: { prefs.version; return prefs.s("Concentracion/hasta") }
                onElegido: (v) => prefs.poner("Concentracion/hasta", v)
            }
        }
    }
}
