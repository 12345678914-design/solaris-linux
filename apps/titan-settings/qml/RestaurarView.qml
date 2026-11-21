// Ajustes > Restaurar sistema: puntos de restauracion (snapper o Timeshift).
import QtQuick
import QtQuick.Controls

PaginaAjustes {
    id: vista
    titulo: "Restaurar sistema"
    descripcion: sistema.tipoInstantaneas === "btrfs"
                 ? "Inti OS guarda un punto de restauración antes y después de cada actualización y uno cada hora. Si algo se rompe, elige \"Instantáneas de Inti OS\" en el menú de arranque y arranca un punto anterior."
                 : sistema.tipoInstantaneas === "ext4-timeshift"
                   ? "Este sistema está en ext4: las copias del sistema se hacen con Timeshift."
                   : "Los puntos de restauración necesitan instalar Inti OS en btrfs (el instalador lo usa por defecto)."

    Component.onCompleted: sistema.refrescar("Restaurar sistema")

    TitanTheme { id: tema }

    Grupo {
        visible: sistema.tipoInstantaneas === "btrfs"
        etiqueta: "Crear un punto de restauración"
        Fila {
            separador: false
            titulo: "Descripción"
            TextField {
                id: descripcion
                width: 220
                height: 28
                placeholderText: "Antes de instalar…"
                font.pixelSize: 11
                color: tema.contentTextPrimary
                placeholderTextColor: tema.contentTextSecondary
                background: Rectangle {
                    radius: 6
                    color: tema.isDark ? "#2c303c" : "#ffffff"
                    border.color: descripcion.activeFocus ? tema.accent : tema.contentCardBorder
                    border.width: 1
                }
            }
            Boton {
                texto: sistema.ocupado === "instantanea" ? "Creando…" : "Crear"
                principal: true
                habilitado: sistema.ocupado === ""
                onPulsado: {
                    sistema.crearInstantanea(descripcion.text)
                    descripcion.text = ""
                }
            }
        }
    }

    Grupo {
        visible: sistema.tipoInstantaneas === "btrfs"
        etiqueta: "Puntos de restauración (" + sistema.instantaneas.length + ")"
        Fila {
            visible: sistema.instantaneas.length === 0
            separador: false
            titulo: "Todavía no hay ninguno"
        }
        Repeater {
            model: sistema.instantaneas
            delegate: Fila {
                required property var modelData
                required property int index
                separador: index < sistema.instantaneas.length - 1
                titulo: modelData.descripcion || ("Punto " + modelData.numero)
                detalle: modelData.fecha + " · nº " + modelData.numero
                Boton {
                    texto: "Borrar"
                    peligro: true
                    habilitado: sistema.ocupado === ""
                    onPulsado: sistema.borrarInstantanea(modelData.numero)
                }
            }
        }
    }

    Row {
        spacing: 10
        Boton {
            visible: sistema.tipoInstantaneas === "btrfs"
            texto: "Abrir Btrfs Assistant…"
            onPulsado: sistema.abrir("btrfs-assistant")
        }
        Boton {
            visible: sistema.tipoInstantaneas === "ext4-timeshift"
            texto: "Abrir Timeshift…"
            principal: true
            onPulsado: sistema.abrir("timeshift-launcher")
        }
    }
}
