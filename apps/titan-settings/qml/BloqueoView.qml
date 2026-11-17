// Ajustes > Bloquear pantalla
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Bloquear pantalla"
    descripcion: "La sesión se bloquea sola al dejar de usar el equipo, al suspender y con Super + L."

    Component.onCompleted: sistema.refrescar("Bloquear pantalla")

    Grupo {
        etiqueta: "Bloqueo automático"
        nota: sistema.live ? "En la sesión de prueba (live) no se bloquea: la cuenta del live no tiene contraseña." : ""
        Fila {
            titulo: "Bloquear la pantalla tras"
            detalle: "Tiempo sin tocar el teclado ni el ratón."
            SelectorMinutos {
                valor: sistema.inactividad.BLOQUEAR
                onElegido: function(m) { sistema.setInactividad("BLOQUEAR", m) }
            }
        }
        Fila {
            titulo: "Apagar la pantalla tras"
            SelectorMinutos {
                valor: sistema.inactividad.APAGAR_PANTALLA
                onElegido: function(m) { sistema.setInactividad("APAGAR_PANTALLA", m) }
            }
        }
        Fila {
            separador: false
            titulo: "Bloquear ahora"
            detalle: "Atajo de teclado: Super + L"
            Boton {
                texto: "Bloquear"
                habilitado: !sistema.live
                onPulsado: sistema.bloquearAhora()
            }
        }
    }

    Grupo {
        etiqueta: "Huella digital"
        visible: sistema.huella !== "sin-lector" && sistema.huella !== ""
        Fila {
            separador: false
            titulo: "Desbloquear con la huella"
            detalle: sistema.huella === "registrada"
                     ? "También sirve para las contraseñas de administrador y sudo."
                     : "Primero registra una huella en Privacidad y seguridad."
            Interruptor {
                activo: sistema.huellaActiva
                habilitado: sistema.huella === "registrada" && sistema.ocupado === ""
                onAlternado: function(v) { sistema.setHuellaActiva(v) }
            }
        }
    }
}
