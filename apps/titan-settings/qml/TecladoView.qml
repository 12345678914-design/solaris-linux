// Ajustes > Teclado: distribucion, metodos de entrada (fcitx5) y corrector.
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Teclado"

    Component.onCompleted: sistema.refrescar("Teclado")

    // Como Ubuntu: la que se eligió al instalar, y se cambia aquí al momento
    readonly property var distribuciones: [
        { valor: "es", texto: "Español (España)" },
        { valor: "latam", texto: "Español (Latinoamérica)" },
        { valor: "us", texto: "Inglés (EE. UU.)" },
        { valor: "us intl", texto: "Inglés (internacional, con acentos)" },
        { valor: "gb", texto: "Inglés (Reino Unido)" },
        { valor: "pt", texto: "Portugués (Portugal)" },
        { valor: "br", texto: "Portugués (Brasil)" },
        { valor: "fr", texto: "Francés" },
        { valor: "de", texto: "Alemán" },
        { valor: "it", texto: "Italiano" }
    ]

    Grupo {
        etiqueta: "Distribución"
        nota: "Se aplica al momento en todas las apps."
        Fila {
            titulo: "Distribución del teclado"
            Desplegable {
                anchors.verticalCenter: parent.verticalCenter
                ancho: 260
                opciones: vista.distribuciones
                valor: sistema.distribucionTeclado
                onElegido: (v) => {
                    var p = String(v).split(" ")
                    sistema.setDistribucion(p[0], p.length > 1 ? p[1] : "")
                }
            }
        }
        Fila {
            separador: false
            titulo: "Pruébala"
            Campo {
                anchors.verticalCenter: parent.verticalCenter
                ancho: 260
                pista: "ñ, á, @, #, €…"
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
