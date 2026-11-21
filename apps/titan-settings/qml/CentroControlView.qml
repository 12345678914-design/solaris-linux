// Ajustes > Centro de control: qué módulos aparecen.
import QtQuick

PaginaAjustes {
    titulo: "Centro de control"
    descripcion: "Elige qué aparece al abrir el Centro de control desde la barra de menús."

    component Modulo: Fila {
        property string clave: ""
        Interruptor {
            anchors.verticalCenter: parent.verticalCenter
            activo: { prefs.version; return prefs.b(clave) }
            onAlternado: (v) => prefs.poner(clave, v)
        }
    }

    Grupo {
        etiqueta: "Módulos"
        Modulo { titulo: "Wi-Fi y Bluetooth"; clave: "Centro/conectividad" }
        Modulo { titulo: "Ahorro de batería y tema claro/oscuro"; clave: "Centro/energia" }
        Modulo { titulo: "No molestar"; detalle: "Silencia los avisos (Concentración)"; clave: "Centro/noMolestar" }
        Modulo { titulo: "Brillo de la pantalla"; clave: "Centro/brillo" }
        Modulo { titulo: "Volumen"; clave: "Centro/sonido"; separador: false }
    }
}
