// Ajustes > Compartir: escritorio remoto (VNC), como "Compartir escritorio"
// en Ubuntu/Fedora o "Compartir pantalla" en macOS. Lo hace
// titan-escritorio-remoto (wayvnc, cifrado y con la contraseña de la cuenta).
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Compartir"
    descripcion: "Deja que otro equipo de tu red vea y maneje este escritorio."

    Component.onCompleted: sistema.refrescar("Compartir")

    TitanTheme { id: tema }

    readonly property bool activo: sistema.escritorioRemoto === "activo"

    Grupo {
        etiqueta: "Escritorio remoto"
        nota: sistema.escritorioRemoto === "no-instalado"
              ? "Falta el programa wayvnc: instálalo desde la App Store o con «sudo pacman -S wayvnc»."
              : "La conexión va cifrada y pide el usuario y la contraseña de esta cuenta. Desde otro equipo, usa un visor VNC (Remmina, TigerVNC, RealVNC...). Se vuelve a activar solo al entrar en la sesión."
        Fila {
            titulo: "Compartir este escritorio"
            detalle: vista.activo ? "Activado: cualquiera con tu contraseña puede conectarse"
                                  : "Desactivado"
            separador: vista.activo
            Interruptor {
                activo: vista.activo
                habilitado: sistema.ocupado === "" && sistema.escritorioRemoto !== "no-instalado"
                onAlternado: function(v) { sistema.setEscritorioRemoto(v) }
            }
        }
        Fila {
            visible: vista.activo
            titulo: "Dirección para conectarse"
            detalle: "Usuario: la misma cuenta con la que has entrado"
            separador: false
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: sistema.direccionesIp.length > 0
                      ? sistema.direccionesIp.map(function(ip) { return ip + ":5900" }).join("   ")
                      : "Sin red"
                color: tema.contentTextPrimary
                font.pixelSize: 13
                font.family: "monospace"
            }
        }
    }
}
