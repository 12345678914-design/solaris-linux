// Ajustes > Almacenamiento: espacio usado y discos.
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Almacenamiento"

    Component.onCompleted: sistema.refrescar("Almacenamiento")

    TitanTheme { id: tema }

    Grupo {
        etiqueta: "Espacio"
        Repeater {
            model: sistema.volumenes
            delegate: Item {
                required property var modelData
                required property int index
                width: parent.width
                height: 74
                readonly property real usado: modelData.total > 0 ? (modelData.total - modelData.libre) / modelData.total : 0
                Column {
                    x: 16
                    width: parent.width - 32
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Item {
                        width: parent.width
                        height: 16
                        Text {
                            text: modelData.nombre
                            color: tema.contentTextPrimary
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Text {
                            anchors.right: parent.right
                            text: sistema.tamanoLegible(modelData.libre) + " libres de " + sistema.tamanoLegible(modelData.total)
                            color: tema.contentTextSecondary
                            font.pixelSize: 11
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 10
                        radius: 5
                        color: tema.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                        Rectangle {
                            width: parent.width * usado
                            height: parent.height
                            radius: 5
                            color: usado > 0.9 ? "#ff453a" : usado > 0.75 ? "#ff9f0a" : tema.accent
                        }
                    }
                    Text {
                        text: modelData.ruta + " · " + modelData.dispositivo + " · " + modelData.sistema
                        color: tema.contentTextSecondary
                        font.pixelSize: 10
                    }
                }
                Rectangle {
                    visible: index < sistema.volumenes.length - 1
                    anchors.bottom: parent.bottom
                    x: 16
                    width: parent.width - 32
                    height: 1
                    color: tema.contentCardBorder
                }
            }
        }
    }

    Grupo {
        etiqueta: "Discos"
        Repeater {
            model: sistema.discos
            delegate: Fila {
                required property var modelData
                required property int index
                separador: index < sistema.discos.length - 1
                titulo: modelData.nombre
                detalle: modelData.clase + " · " + modelData.dispositivo
                Text {
                    text: sistema.tamanoLegible(modelData.tamano)
                    color: tema.contentTextSecondary
                    font.pixelSize: 12
                }
            }
        }
    }

    Row {
        spacing: 10
        Boton {
            texto: "Abrir Discos…"
            principal: true
            onPulsado: sistema.abrir("gnome-disks")
        }
    }
    Text {
        width: parent.width
        text: "Discos formatea, crea particiones, comprueba la salud (SMART) y crea imágenes. Las memorias USB, los móviles (MTP) y las carpetas compartidas de la red se abren desde Finder."
        color: tema.contentTextSecondary
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
}
