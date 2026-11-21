// Ajustes > Barra de menús: estilo, reloj e iconos (titan-shell en vivo).
import QtQuick

PaginaAjustes {
    titulo: "Barra de menús"
    descripcion: "La barra de arriba: su aspecto, el reloj y qué iconos enseña."

    TitanTheme { id: tema }

    component Opcion: Fila {
        property string clave: ""
        Interruptor {
            anchors.verticalCenter: parent.verticalCenter
            activo: { prefs.version; return prefs.b(clave) }
            onAlternado: (v) => prefs.poner(clave, v)
        }
    }

    Grupo {
        etiqueta: "Aspecto"
        Opcion { titulo: "Mostrar la barra de menús"; detalle: "Oculta, las ventanas usan toda la pantalla"; clave: "Barra/visible" }
        Fila {
            titulo: "Estilo"
            detalle: "Transparente: el texto se adapta al fondo de pantalla"
            separador: false
            Segmentos {
                anchors.verticalCenter: parent.verticalCenter
                anchoSegmento: 92
                opciones: [{ valor: "transparente", texto: "Transparente" }, { valor: "vidrio", texto: "Vidrio" }, { valor: "solido", texto: "Sólida" }]
                valor: { prefs.version; return prefs.s("Barra/estilo") }
                onElegido: (v) => prefs.poner("Barra/estilo", v)
            }
        }
    }

    Grupo {
        etiqueta: "Reloj"
        nota: { prefs.version; return "Así se verá: " + Qt.formatDateTime(new Date(),
            (prefs.b("Barra/diaSemana") ? "ddd " : "") + (prefs.b("Barra/fecha") ? "d MMM  " : "")
            + (prefs.b("Barra/reloj24h") ? "HH:mm" : "h:mm") + (prefs.b("Barra/segundos") ? ":ss" : "") + (prefs.b("Barra/reloj24h") ? "" : " AP")) }
        Opcion { titulo: "Reloj de 24 horas"; clave: "Barra/reloj24h" }
        Opcion { titulo: "Mostrar los segundos"; clave: "Barra/segundos" }
        Opcion { titulo: "Mostrar la fecha"; clave: "Barra/fecha" }
        Opcion { titulo: "Mostrar el día de la semana"; clave: "Barra/diaSemana"; separador: false }
    }

    Grupo {
        etiqueta: "Iconos"
        Opcion { titulo: "Porcentaje de batería"; clave: "Barra/bateriaPorcentaje" }
        Opcion { titulo: "Wi-Fi"; clave: "Barra/iconoWifi" }
        Opcion { titulo: "Bluetooth"; clave: "Barra/iconoBluetooth" }
        Opcion { titulo: "Botón de fondos de pantalla"; clave: "Barra/iconoFondo"; separador: false }
    }
}
