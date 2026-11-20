// Ajustes > Ratón y panel táctil (como en Ubuntu, Fedora o macOS): velocidad,
// desplazamiento natural, tocar para hacer clic... Se guarda en [input] de
// ~/.config/wayfire.ini y Wayfire lo aplica al momento.
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Ratón y panel táctil"

    Component.onCompleted: sistema.refrescar("Ratón y panel táctil")

    readonly property var r: sistema.raton || ({})

    component Velocidad: Row {
        id: vel
        property string clave: ""
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        spacing: 8
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Lenta"; color: tema.contentTextSecondary; font.pixelSize: 10 }
        Deslizador {
            anchors.verticalCenter: parent.verticalCenter
            ancho: 180
            desde: -1; hasta: 1; paso: 0.05
            valor: vista.r[vel.clave] !== undefined ? vista.r[vel.clave] : 0
            onSoltado: (v) => sistema.setRaton(vel.clave, v)
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Rápida"; color: tema.contentTextSecondary; font.pixelSize: 10 }
    }

    Grupo {
        etiqueta: "Ratón"
        Fila {
            titulo: "Velocidad del puntero"
            Velocidad { clave: "mouse_cursor_speed" }
        }
        Fila {
            titulo: "Desplazamiento natural"
            detalle: "El contenido sigue al dedo en la rueda, como en un móvil."
            Interruptor {
                activo: vista.r.mouse_natural_scroll === true
                onAlternado: (v) => sistema.setRaton("mouse_natural_scroll", v)
            }
        }
        Fila {
            separador: false
            titulo: "Botón principal a la derecha"
            detalle: "Para personas zurdas."
            Interruptor {
                activo: vista.r.left_handed_mode === true
                onAlternado: (v) => sistema.setRaton("left_handed_mode", v)
            }
        }
    }

    Grupo {
        etiqueta: "Panel táctil"
        visible: sistema.hayPanelTactil
        Fila {
            titulo: "Velocidad del puntero"
            Velocidad { clave: "touchpad_cursor_speed" }
        }
        Fila {
            titulo: "Tocar para hacer clic"
            Interruptor {
                activo: vista.r.tap_to_click === true
                onAlternado: (v) => sistema.setRaton("tap_to_click", v)
            }
        }
        Fila {
            titulo: "Desplazamiento natural"
            detalle: "Con dos dedos, el contenido sigue a los dedos (como en macOS)."
            Interruptor {
                activo: vista.r.natural_scroll === true
                onAlternado: (v) => sistema.setRaton("natural_scroll", v)
            }
        }
        Fila {
            separador: false
            titulo: "Desactivar mientras escribes"
            detalle: "Evita clics sin querer con la palma de la mano."
            Interruptor {
                activo: vista.r.disable_touchpad_while_typing === true
                onAlternado: (v) => sistema.setRaton("disable_touchpad_while_typing", v)
            }
        }
    }

    Grupo {
        etiqueta: "Gestos"
        visible: sistema.hayPanelTactil
        nota: "Como en Ubuntu, Fedora y macOS. Con dos dedos se desplaza y se pellizca para hacer zoom en las apps."
        Fila {
            titulo: "Gestos con tres y cuatro dedos"
            Interruptor {
                activo: vista.r.gestos !== false
                onAlternado: (v) => sistema.setRaton("gestos", v)
            }
        }
        Repeater {
            model: [
                ["3 dedos a los lados", "Cambiar de escritorio"],
                ["3 dedos arriba", "Ver todas las ventanas"],
                ["3 dedos abajo", "Mostrar el escritorio"],
                ["4 dedos arriba o pellizcar", "Launchpad (todas las apps)"],
                ["4 dedos abajo", "Ver los escritorios"]
            ]
            delegate: Fila {
                required property var modelData
                required property int index
                separador: index < 4
                titulo: modelData[0]
                opacity: vista.r.gestos !== false ? 1 : 0.45
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData[1]
                    color: tema.contentTextSecondary
                    font.pixelSize: 12
                }
            }
        }
    }
}
