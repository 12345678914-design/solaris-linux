// Ajustes > Ventanas: cambiar el estilo de los botones de ventana (_ □ X).
// Cada estilo es un fichero aparte (botones/Botones*.qml en las apps de Inti,
// estilo-*.cpp en Wayfire, /usr/share/titan/ventanas/<estilo>/ para GTK y
// labwc). Solo se usa el elegido: al cambiarlo se cierra el anterior y se
// abre el nuevo. Las vistas previas solo existen mientras esta página está abierta.
import QtQuick
import QtQuick.Controls

PaginaAjustes {
    id: vista
    titulo: "Ventanas"
    descripcion: "Elige cómo se ven los botones para minimizar, maximizar y cerrar las ventanas. El cambio llega al momento a las apps de Inti, al terminal y a las apps con barra del sistema; Firefox y las apps GTK lo toman al volver a abrirlas."
    mensaje: ""

    TitanTheme { id: tema }

    readonly property string elegido: (typeof titanThemeManager !== "undefined") ? titanThemeManager.windowStyle : "actual"
    function elegir(id) {
        if (typeof titanThemeManager !== "undefined")
            titanThemeManager.windowStyle = id
    }

    readonly property var estilos: [
        { id: "actual",   nombre: "Actual",            archivo: "BotonesActual.qml",
          texto: "Semáforo de colores a la izquierda; los símbolos salen al pasar el ratón." },
        { id: "windows",  nombre: "Estilo Windows",    archivo: "BotonesWindows.qml",
          texto: "_ □ X planos a la derecha, fáciles de pulsar; cerrar se pone rojo." },
        { id: "circulos", nombre: "Círculos grises",   archivo: "BotonesCirculos.qml",
          texto: "Círculos suaves con el símbolo siempre visible, a la derecha." },
        { id: "acento",   nombre: "Inti acento",       archivo: "BotonesAcento.qml",
          texto: "A la derecha; se tiñen del color de acento y cerrar se pone rojo." },
        { id: "capsula",  nombre: "Cápsula",           archivo: "BotonesCapsula.qml",
          texto: "Los tres botones juntos en una cápsula. Moderno y compacto." },
        { id: "contorno", nombre: "Contorno fino",     archivo: "BotonesContorno.qml",
          texto: "Círculos de línea fina; toman el acento al pasar el ratón." },
        { id: "color",    nombre: "Color a la derecha", archivo: "BotonesColor.qml",
          texto: "Círculos de color con su símbolo, en el orden de Windows." }
    ]

    Grupo {
        etiqueta: "Cambiar estilo de ventana"
        nota: "Pasa el ratón por los botones de cada muestra para ver cómo responden."

        Flow {
            id: rejilla
            width: parent.width
            padding: 14
            spacing: 14
            readonly property real anchoTarjeta: Math.floor((width - 2 * padding - spacing) / 2)

            Repeater {
                model: vista.estilos
                delegate: Rectangle {
                    id: tarjeta
                    required property var modelData
                    readonly property bool marcado: vista.elegido === modelData.id
                    width: rejilla.anchoTarjeta
                    height: 178
                    radius: 12
                    color: "transparent"
                    border.width: marcado ? 2 : 1
                    border.color: marcado ? tema.accent : tema.contentCardBorder

                    TapHandler { onTapped: vista.elegir(tarjeta.modelData.id) }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }

                    // Ventana de muestra con los botones reales del estilo
                    Rectangle {
                        id: muestra
                        x: 12; y: 12
                        width: parent.width - 24
                        height: 96
                        radius: 10
                        clip: true
                        color: tema.contentBackground
                        border.width: 1
                        border.color: tema.accent
                        Rectangle {
                            id: barra
                            width: parent.width
                            height: 50
                            color: tema.headerTop
                            topLeftRadius: 10; topRightRadius: 10
                            Text {
                                // Lejos de los botones: la muestra es estrecha
                                anchors.verticalCenter: parent.verticalCenter
                                x: botones.derecha ? 16 : (parent.width - width) / 2 + 20
                                text: "Ventana"
                                color: tema.headerText
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                            Loader {
                                id: botones
                                source: "botones/" + tarjeta.modelData.archivo
                                readonly property bool derecha: item ? item.derecha : false
                                readonly property real margen: item ? item.margen : 18
                                anchors.left: derecha ? undefined : parent.left
                                anchors.right: derecha ? parent.right : undefined
                                anchors.leftMargin: margen
                                anchors.rightMargin: margen
                                y: item && item.height >= barra.height ? 0 : Math.round((barra.height - height) / 2)
                                onLoaded: {
                                    item.tema = tema
                                    item.altoBarra = 50
                                    item.radioEsquina = 10
                                    var id = tarjeta.modelData.id
                                    item.cerrar.connect(function() { vista.elegir(id) })
                                    item.minimizar.connect(function() { vista.elegir(id) })
                                    item.maximizar.connect(function() { vista.elegir(id) })
                                }
                            }
                        }
                        Rectangle {   // contenido de mentira
                            x: 12; y: 62; width: 60; height: 8; radius: 4
                            color: tema.contentTextSecondary; opacity: 0.35
                        }
                        Rectangle {
                            x: 12; y: 76; width: 110; height: 8; radius: 4
                            color: tema.contentTextSecondary; opacity: 0.2
                        }
                    }

                    Row {
                        x: 14; y: 116
                        spacing: 8
                        Rectangle {
                            width: 18; height: 18; radius: 9
                            anchors.verticalCenter: parent.verticalCenter
                            color: tarjeta.marcado ? tema.accent : "transparent"
                            border.width: tarjeta.marcado ? 0 : 1.5
                            border.color: tema.contentTextSecondary
                            Text {
                                anchors.centerIn: parent
                                visible: tarjeta.marcado
                                text: "✓"; color: "white"
                                font.pixelSize: 12; font.bold: true
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tarjeta.modelData.nombre
                            color: tema.contentTextPrimary
                            font.pixelSize: 14
                            font.bold: true
                        }
                    }
                    Text {
                        x: 14; y: 140
                        width: parent.width - 28
                        text: tarjeta.modelData.texto
                        color: tema.contentTextSecondary
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
