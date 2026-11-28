// Ajustes > Apariencia: claro/oscuro, color de acento (llega a todas las apps
// de Inti, a GTK/libadwaita, kitty y la pantalla de bloqueo), temas guardados,
// y lo principal del Dock y la barra de menús.
import QtQuick
import QtQuick.Controls

PaginaAjustes {
    id: vista
    titulo: "Apariencia"
    descripcion: "El color de acento se usa en botones, selecciones e interruptores del Explorador de archivos, Música, Fotos, Ajustes, el Dock y las apps GTK."

    TitanTheme { id: tema }

    readonly property string acento: settingsBackend.accent
    readonly property var presets: [
        { color: "#0071e3", nombre: "Azul" }, { color: "#5e5ce6", nombre: "Índigo" },
        { color: "#af52de", nombre: "Morado" }, { color: "#ff2d55", nombre: "Rosa" },
        { color: "#ff3b30", nombre: "Rojo" }, { color: "#ff9500", nombre: "Naranja" },
        { color: "#ffcc00", nombre: "Amarillo" }, { color: "#34c759", nombre: "Verde" },
        { color: "#00a3a3", nombre: "Turquesa" }, { color: "#8e8e93", nombre: "Grafito" }
    ]
    function esPreset(c) {
        for (var i = 0; i < presets.length; ++i)
            if (presets[i].color.toLowerCase() === String(c).toLowerCase()) return true
        return false
    }

    // ---------------------------------------------------------- Aspecto
    Grupo {
        etiqueta: "Aspecto"
        Item {
            width: parent.width
            height: 150
            Row {
                anchors.centerIn: parent
                spacing: 22
                Repeater {
                    model: [
                        { modo: "light", texto: "Claro", fondo: "#f5f5f7", lado: "#e3e3e8", panel: "#ffffff" },
                        { modo: "dark", texto: "Oscuro", fondo: "#1e1f26", lado: "#15161c", panel: "#2a2c35" },
                        { modo: "auto", texto: "Automático", fondo: "", lado: "", panel: "" }
                    ]
                    delegate: Item {
                        id: opModo
                        required property var modelData
                        readonly property bool elegido: modelData.modo === "auto" ? false
                                                        : (modelData.modo === "dark") === settingsBackend.isDark
                        width: 128
                        height: 112
                        Rectangle {
                            width: 128; height: 82; radius: 9
                            clip: true
                            color: opModo.modelData.fondo !== "" ? opModo.modelData.fondo : "#f5f5f7"
                            border.color: opModo.elegido ? vista.acento : tema.contentCardBorder
                            border.width: opModo.elegido ? 3 : 1
                            Rectangle {   // mitad oscura de "Automático"
                                visible: opModo.modelData.modo === "auto"
                                anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                                anchors.margins: 1
                                width: parent.width / 2
                                color: "#1e1f26"
                            }
                            Rectangle {
                                x: 8; y: 18; width: 30; height: parent.height - 26; radius: 4
                                color: opModo.modelData.lado !== "" ? opModo.modelData.lado : "#e3e3e8"
                            }
                            Rectangle {
                                x: 44; y: 18; width: parent.width - 52; height: parent.height - 26; radius: 4
                                color: opModo.modelData.panel !== "" ? opModo.modelData.panel : "#ffffff"
                                opacity: opModo.modelData.modo === "auto" ? 0.5 : 1
                                Rectangle { x: 8; y: 8; width: 34; height: 8; radius: 4; color: vista.acento }
                            }
                            Row {
                                x: 8; y: 7; spacing: 4
                                Rectangle { width: 6; height: 6; radius: 3; color: "#ff5f57" }
                                Rectangle { width: 6; height: 6; radius: 3; color: "#febc2e" }
                                Rectangle { width: 6; height: 6; radius: 3; color: "#28c840" }
                            }
                        }
                        Text {
                            y: 90
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: opModo.modelData.texto
                            color: tema.contentTextPrimary
                            font.pixelSize: 12
                            font.bold: opModo.elegido
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: settingsBackend.setThemeMode(opModo.modelData.modo)
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- Acento
    Grupo {
        etiqueta: "Color de acento"
        nota: "También cambia el cursor y la selección de la Terminal, y el botón de la pantalla de bloqueo."
        Item {
            width: parent.width
            height: 62
            Row {
                anchors.centerIn: parent
                spacing: 13
                Repeater {
                    model: vista.presets
                    delegate: Item {
                        required property var modelData
                        width: 28; height: 40
                        Rectangle {
                            id: punto
                            width: 26; height: 26; radius: 13
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: modelData.color
                            scale: puntoRaton.containsMouse ? 1.15 : 1
                            Behavior on scale { NumberAnimation { duration: 110 } }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 34; height: 34; radius: 17
                                color: "transparent"
                                border.color: modelData.color
                                border.width: 2
                                visible: vista.acento.toLowerCase() === modelData.color
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8; height: 8; radius: 4
                                color: "#ffffff"
                                visible: vista.acento.toLowerCase() === modelData.color
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: punto.bottom
                            anchors.topMargin: 4
                            visible: puntoRaton.containsMouse
                            text: modelData.nombre
                            color: tema.contentTextSecondary
                            font.pixelSize: 9
                        }
                        MouseArea {
                            id: puntoRaton
                            anchors.fill: punto
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: settingsBackend.accent = modelData.color
                        }
                    }
                }
            }
        }
        Fila {
            titulo: "Color personalizado"
            detalle: vista.esPreset(vista.acento) ? "Elige cualquier tono en la barra o escribe un código #RRGGBB"
                                                  : "Ahora: " + vista.acento.toUpperCase()
            separador: false
            // Barra de tonos
            Rectangle {
                width: 180; height: 18; radius: 9
                anchors.verticalCenter: parent.verticalCenter
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.00; color: Qt.hsla(0.00, 0.78, 0.50, 1) }
                    GradientStop { position: 0.17; color: Qt.hsla(0.17, 0.78, 0.50, 1) }
                    GradientStop { position: 0.33; color: Qt.hsla(0.33, 0.78, 0.50, 1) }
                    GradientStop { position: 0.50; color: Qt.hsla(0.50, 0.78, 0.50, 1) }
                    GradientStop { position: 0.67; color: Qt.hsla(0.67, 0.78, 0.50, 1) }
                    GradientStop { position: 0.83; color: Qt.hsla(0.83, 0.78, 0.50, 1) }
                    GradientStop { position: 1.00; color: Qt.hsla(0.99, 0.78, 0.50, 1) }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    function elegir(mx) {
                        var h = Math.max(0, Math.min(0.99, mx / width))
                        var c = Qt.hsla(h, 0.78, 0.50, 1)
                        settingsBackend.accent = c.toString()
                    }
                    onReleased: (m) => elegir(m.x)
                }
            }
            Campo {
                id: hex
                ancho: 90
                pista: "#RRGGBB"
                anchors.verticalCenter: parent.verticalCenter
                onAceptado: {
                    var t = texto.trim()
                    if (t.length > 0 && t[0] !== "#") t = "#" + t
                    if (/^#[0-9a-fA-F]{6}$/.test(t)) { settingsBackend.accent = t.toLowerCase(); limpiar() }
                }
            }
        }
    }

    // ---------------------------------------------------------- Temas
    Grupo {
        etiqueta: "Temas"
        nota: "Un tema guarda claro/oscuro, el color de acento, el fondo, el Dock y la barra de menús. Los de Inti no cambian tu fondo."
        Flow {
            width: parent.width
            padding: 14
            spacing: 14
            Repeater {
                model: personalizar.temas
                delegate: Item {
                    required property var modelData
                    width: 132; height: 112
                    Rectangle {
                        id: mini
                        width: 132; height: 82; radius: 9
                        clip: true
                        color: modelData.oscuro ? "#1e1f26" : "#f5f5f7"
                        border.color: modelData.actual ? vista.acento : tema.contentCardBorder
                        border.width: modelData.actual ? 3 : 1
                        Image {
                            anchors.fill: parent
                            anchors.margins: 1
                            source: modelData.fondoUrl
                            sourceSize: Qt.size(264, 164)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            opacity: 0.9
                        }
                        // Barra de menus en miniatura
                        Rectangle {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 1
                            height: 8
                            color: modelData.barraEstilo === "solido" ? (modelData.oscuro ? "#1c1d23" : "#f2f2f7")
                                   : modelData.barraEstilo === "vidrio" ? (modelData.oscuro ? Qt.rgba(0.1, 0.11, 0.16, 0.6) : Qt.rgba(1, 1, 1, 0.6))
                                   : "transparent"
                        }
                        // Ventana con el acento
                        Rectangle {
                            x: 30; y: 18; width: 72; height: 40; radius: 5
                            color: modelData.oscuro ? "#2a2c35" : "#ffffff"
                            Rectangle { x: 6; y: 8; width: 30; height: 6; radius: 3; color: modelData.acento }
                            Rectangle { x: 6; y: 20; width: 50; height: 4; radius: 2; color: modelData.oscuro ? "#4a4d5a" : "#dcdce2" }
                        }
                        // Dock en miniatura en su borde
                        Rectangle {
                            readonly property bool lado: modelData.dockPosicion !== "abajo"
                            width: lado ? 8 : 52
                            height: lado ? 40 : 8
                            radius: 3
                            x: modelData.dockPosicion === "izquierda" ? 4 : modelData.dockPosicion === "derecha" ? parent.width - width - 4 : (parent.width - width) / 2
                            y: lado ? (parent.height - height) / 2 + 4 : parent.height - height - 4
                            color: modelData.oscuro ? Qt.rgba(0.2, 0.21, 0.27, 0.85) : Qt.rgba(1, 1, 1, 0.8)
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: personalizar.aplicarTema(modelData.id)
                        }
                        // Borrar (solo los propios)
                        Rectangle {
                            visible: modelData.propio
                            anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 4
                            width: 18; height: 18; radius: 9
                            color: Qt.rgba(0, 0, 0, 0.55)
                            Text { anchors.centerIn: parent; text: "✕"; color: "#ffffff"; font.pixelSize: 9 }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: personalizar.borrarTema(modelData.id)
                            }
                        }
                    }
                    Text {
                        anchors.top: mini.bottom
                        anchors.topMargin: 6
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: (modelData.actual ? "✓ " : "") + modelData.nombre
                        color: tema.contentTextPrimary
                        font.pixelSize: 11
                        font.bold: modelData.actual
                        elide: Text.ElideRight
                    }
                }
            }
        }
        Fila {
            titulo: "Guardar el aspecto actual"
            detalle: errorTema.length > 0 ? errorTema : "Para volver a él con un clic"
            separador: false
            property string errorTema: ""
            id: filaGuardar
            Campo {
                id: nombreTema
                ancho: 160
                pista: "Nombre del tema"
                anchors.verticalCenter: parent.verticalCenter
                onAceptado: guardar.pulsado()
            }
            Boton {
                id: guardar
                texto: "Guardar tema"
                principal: true
                anchors.verticalCenter: parent.verticalCenter
                onPulsado: {
                    filaGuardar.errorTema = personalizar.guardarTema(nombreTema.texto)
                    if (filaGuardar.errorTema.length === 0) nombreTema.limpiar()
                }
            }
        }
    }

    // ---------------------------------------------------------- Dock y barra
    Grupo {
        etiqueta: "Dock y barra de menús"
        nota: "Más opciones en «Escritorio y Dock» y «Barra de menús»."
        Fila {
            titulo: "Posición del Dock en la pantalla"
            Segmentos {
                anchors.verticalCenter: parent.verticalCenter
                anchoSegmento: 84
                opciones: [{ valor: "izquierda", texto: "Izquierda" }, { valor: "abajo", texto: "Abajo" }, { valor: "derecha", texto: "Derecha" }]
                valor: { prefs.version; return prefs.s("Dock/posicion") }
                onElegido: (v) => prefs.poner("Dock/posicion", v)
            }
        }
        Fila {
            titulo: "Tamaño de los iconos del Dock"
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Pequeño"; color: tema.contentTextSecondary; font.pixelSize: 10 }
            Deslizador {
                anchors.verticalCenter: parent.verticalCenter
                ancho: 160
                desde: 28; hasta: 64; paso: 2
                valor: { prefs.version; return prefs.i("Dock/tamano") }
                onSoltado: (v) => prefs.poner("Dock/tamano", Math.round(v))
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Grande"; color: tema.contentTextSecondary; font.pixelSize: 10 }
        }
        Fila {
            titulo: "Barra de menús"
            detalle: "Transparente sobre el fondo, de vidrio o sólida"
            separador: false
            Segmentos {
                anchors.verticalCenter: parent.verticalCenter
                anchoSegmento: 92
                opciones: [{ valor: "transparente", texto: "Transparente" }, { valor: "vidrio", texto: "Vidrio" }, { valor: "solido", texto: "Sólida" }]
                valor: { prefs.version; return prefs.s("Barra/estilo") }
                onElegido: (v) => prefs.poner("Barra/estilo", v)
            }
        }
    }
}
