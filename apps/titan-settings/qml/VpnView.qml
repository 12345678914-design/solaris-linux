// Ajustes > VPN (NetworkManager: OpenVPN, WireGuard, OpenConnect).
import QtQuick
import QtQuick.Dialogs

PaginaAjustes {
    id: vista
    titulo: "VPN"
    descripcion: "Importa el fichero que te da tu proveedor o tu empresa: .ovpn (OpenVPN) o .conf (WireGuard)."

    Component.onCompleted: sistema.refrescar("VPN")

    TitanTheme { id: tema }

    Grupo {
        etiqueta: "Conexiones VPN"
        Fila {
            visible: sistema.vpns.length === 0
            separador: false
            titulo: "No hay ninguna VPN"
        }
        Repeater {
            model: sistema.vpns
            delegate: Fila {
                required property var modelData
                required property int index
                separador: index < sistema.vpns.length - 1
                titulo: modelData.nombre
                detalle: modelData.tipo + (modelData.activa ? " · Conectada" : "")
                Interruptor {
                    activo: modelData.activa
                    habilitado: sistema.ocupado === ""
                    onAlternado: function(v) { sistema.setVpn(modelData.nombre, v) }
                }
            }
        }
    }

    Row {
        spacing: 10
        Boton {
            texto: "Importar fichero…"
            principal: true
            habilitado: sistema.ocupado === ""
            onPulsado: selector.open()
        }
        Boton {
            texto: "Configuración avanzada…"
            visible: sistema.instalado("nm-connection-editor")
            onPulsado: sistema.abrir("nm-connection-editor")
        }
    }

    FileDialog {
        id: selector
        title: "Importar una VPN"
        nameFilters: ["Configuración de VPN (*.ovpn *.conf)", "Todos los ficheros (*)"]
        onAccepted: sistema.importarVpn(selectedFile)
    }
}
