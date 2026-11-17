// Ajustes > Teclado: distribucion, metodos de entrada (fcitx5) y corrector.
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Teclado"

    Component.onCompleted: sistema.refrescar("Teclado")

    Grupo {
        etiqueta: "Distribución"
        Fila {
            separador: false
            titulo: "Distribución del teclado"
            detalle: "La que eligió el instalador. Se cambia en ~/.config/wayfire.ini ([input] xkb_layout)."
            Text {
                text: sistema.distribucionTeclado
                color: tema.contentTextPrimary
                font.pixelSize: 12
                font.bold: true
            }
        }
    }

    Grupo {
        etiqueta: "Métodos de entrada"
        nota: "Para escribir en chino (pinyin), japonés (Mozc), coreano (Hangul) y otros idiomas. Con el método activado, Ctrl + Espacio cambia de idioma."
        Fila {
            titulo: "Usar métodos de entrada"
            detalle: "Fcitx 5"
            Interruptor {
                activo: sistema.metodosEntrada
                onAlternado: function(v) { sistema.setMetodosEntrada(v) }
            }
        }
        Fila {
            separador: false
            titulo: "Idiomas y métodos"
            Boton {
                texto: "Configurar…"
                habilitado: sistema.metodosEntrada
                onPulsado: sistema.abrir("fcitx5-configtool")
            }
        }
    }

    Grupo {
        etiqueta: "Corrector ortográfico"
        Fila {
            separador: false
            titulo: "Diccionarios instalados"
            detalle: "Español (todas las variantes) e inglés. Los usan LibreOffice, Firefox, Thunderbird y las apps de GTK y Qt."
        }
    }

    TitanTheme { id: tema }
}
