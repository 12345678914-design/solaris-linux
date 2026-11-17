// Ajustes > Privacidad y seguridad: cortafuegos, arranque seguro y huella.
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Privacidad y seguridad"
    descripcion: "Los cambios de esta sección piden la contraseña de administrador."

    Component.onCompleted: sistema.refrescar("Privacidad y seguridad")

    TitanTheme { id: tema }

    Grupo {
        etiqueta: "Cortafuegos"
        nota: "Rechaza las conexiones que llegan desde la red, salvo SSH y la búsqueda de impresoras y equipos (mDNS). Lo que sale del equipo no se toca."
        Fila {
            separador: false
            titulo: "Cortafuegos"
            detalle: sistema.cortafuegos === "activo" ? "Activado" :
                     sistema.cortafuegos === "inactivo" ? "Desactivado: el equipo acepta conexiones de la red" :
                     "No se puede consultar"
            Interruptor {
                activo: sistema.cortafuegos === "activo"
                habilitado: sistema.ocupado === "" && sistema.cortafuegos !== "desconocido"
                onAlternado: function(v) { sistema.setCortafuegos(v) }
            }
        }
    }

    Grupo {
        etiqueta: "Arranque seguro (Secure Boot)"
        nota: sistema.arranqueSeguro === "configuracion"
              ? "El firmware está en modo de configuración: Inti OS puede crear sus propias claves, inscribirlas junto a las de Microsoft (Windows sigue arrancando) y firmar el arranque. Después, reinicia y activa Secure Boot en la BIOS."
              : sistema.arranqueSeguro === "inactivo"
                ? "Para activarlo: en la BIOS/UEFI, borra las claves de Secure Boot (\"Reset to Setup Mode\"), vuelve aquí y pulsa Preparar."
                : ""
        Fila {
            separador: false
            titulo: "Estado"
            detalle: sistema.arranqueSeguroTexto || "No se puede consultar"
            Boton {
                visible: sistema.arranqueSeguro === "configuracion"
                texto: sistema.ocupado === "arranque-seguro" ? "Preparando…" : "Preparar"
                principal: true
                habilitado: sistema.ocupado === ""
                onPulsado: sistema.prepararArranqueSeguro()
            }
            Text {
                visible: sistema.arranqueSeguro === "activo"
                text: "Activo"
                color: "#34c759"
                font.pixelSize: 12
                font.bold: true
            }
        }
    }

    Grupo {
        etiqueta: "Huella digital"
        visible: sistema.huella !== ""
        Fila {
            titulo: sistema.huella === "sin-lector" ? "No hay lector de huellas" :
                    sistema.huella === "registrada" ? "Huella registrada" : "Ninguna huella registrada"
            detalle: sistema.registrandoHuella ? sistema.mensajeHuella :
                     sistema.huella === "sin-lector" ? "Este equipo no tiene un lector compatible con fprintd." :
                     (sistema.mensajeHuella || "Para entrar sin escribir la contraseña.")
            separador: sistema.huella !== "sin-lector"
            Boton {
                visible: sistema.huella !== "sin-lector"
                texto: sistema.registrandoHuella ? "Cancelar" :
                       sistema.huella === "registrada" ? "Registrar otro dedo" : "Registrar huella"
                principal: !sistema.registrandoHuella && sistema.huella !== "registrada"
                onPulsado: sistema.registrandoHuella ? sistema.cancelarHuella() : sistema.registrarHuella()
            }
        }
        Fila {
            visible: sistema.huella !== "sin-lector"
            separador: false
            titulo: "Usar la huella"
            detalle: "Para desbloquear la pantalla, las contraseñas de administrador y sudo. La contraseña sigue sirviendo siempre."
            Interruptor {
                activo: sistema.huellaActiva
                habilitado: sistema.huella === "registrada" && sistema.ocupado === ""
                onAlternado: function(v) { sistema.setHuellaActiva(v) }
            }
        }
    }

    Grupo {
        etiqueta: "Contraseñas y claves"
        nota: "Las contraseñas que guardan las apps (Wi-Fi, correo, navegador) van al llavero, que se abre al iniciar sesión."
        Fila {
            separador: false
            titulo: "Llavero"
            detalle: "GNOME Keyring, protegido con la contraseña de tu cuenta."
            Text {
                text: "Activo"
                color: "#34c759"
                font.pixelSize: 12
                font.bold: true
            }
        }
    }
}
