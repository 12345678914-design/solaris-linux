import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs

TitanWindow {
    id: ventana

    width: 1180
    height: 740
    minimumWidth: 860
    minimumHeight: 520
    sidebarWidth: 214
    title: musicaBackend.actual.titulo
           ? (musicaBackend.actual.titulo + " — " + musicaBackend.actual.artista)
           : "Música"

    property bool panelAbierto: false
    property string pestanaPanel: "cola"   // "cola" | "letra"
    readonly property var actual: musicaBackend.actual
    readonly property string tipoVista: musicaBackend.infoVista.tipo || "canciones"
    readonly property bool vistaRejilla: tipoVista === "albumes" || tipoVista === "artistas" || tipoVista === "generos"

    function tiempo(ms) {
        if (!ms || ms < 0) return "0:00"
        var s = Math.floor(ms / 1000)
        var m = Math.floor(s / 60)
        s = s % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }
    function abrirMenu(cancion, indice, item, x, y) {
        menuCancion.cancion = cancion
        menuCancion.indice = indice
        menuCancion.popup(item, x, y)
    }

    Connections {
        target: musicaBackend
        function onLevantarVentana() { ventana.raise(); ventana.requestActivate() }
        function onAvisoChanged() { if (musicaBackend.aviso !== "") avisoTimer.restart() }
    }

    Shortcut { sequence: "Space"; onActivated: musicaBackend.togglePlay() }
    Shortcut { sequence: "Ctrl+Right"; onActivated: musicaBackend.siguiente() }
    Shortcut { sequence: "Ctrl+Left"; onActivated: musicaBackend.anterior() }
    Shortcut { sequence: "Ctrl+Up"; onActivated: musicaBackend.setVolumen(musicaBackend.volumen + 0.05) }
    Shortcut { sequence: "Ctrl+Down"; onActivated: musicaBackend.setVolumen(musicaBackend.volumen - 0.05) }
    Shortcut { sequence: "Ctrl+M"; onActivated: musicaBackend.toggleSilencio() }
    Shortcut { sequence: "Ctrl+R"; onActivated: musicaBackend.cicloRepetir() }
    Shortcut { sequence: "Ctrl+S"; onActivated: musicaBackend.toggleAleatorio() }
    Shortcut { sequence: "Ctrl+L"; onActivated: if (ventana.actual.ruta) musicaBackend.alternarFavorita(ventana.actual.ruta) }
    Shortcut { sequence: "Ctrl+F"; onActivated: { buscador.forceActiveFocus(); buscador.selectAll() } }
    Shortcut { sequence: "Ctrl+N"; onActivated: dlgLista.nueva([]) }
    Shortcut { sequence: "Ctrl+Alt+Q"; onActivated: { ventana.panelAbierto = !(ventana.panelAbierto && ventana.pestanaPanel === "cola"); ventana.pestanaPanel = "cola" } }
    Shortcut { sequence: "Alt+Left"; onActivated: musicaBackend.volver() }
    Shortcut { sequence: "Escape"; onActivated: { if (musicaBackend.busqueda !== "") musicaBackend.busqueda = ""; else musicaBackend.volver() } }

    // ================================================================ BARRA SUPERIOR
    headerContentData: Item {
        anchors.fill: parent

        Row {
            id: transporte
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            BotonM {
                texto: "🔀"; tam: 12; pista: "Aleatorio (Ctrl+S)"
                activo: musicaBackend.aleatorio; acento: theme.accent; tinta: theme.headerText
                onPulsado: musicaBackend.toggleAleatorio()
            }
            BotonM {
                texto: "⏮"; pista: "Anterior (Ctrl+←)"; tinta: theme.headerText
                onPulsado: musicaBackend.anterior()
            }
            Rectangle {
                width: 36; height: 36; radius: 18
                anchors.verticalCenter: parent.verticalCenter
                color: playZona.pressed ? Qt.darker(theme.accent, 1.15) : (playZona.containsMouse ? theme.accentHover : theme.accent)
                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: musicaBackend.reproduciendo ? 0 : 1
                    text: musicaBackend.reproduciendo ? "❚❚" : "▶"
                    color: "#ffffff"
                    font.pixelSize: musicaBackend.reproduciendo ? 11 : 14
                }
                MouseArea {
                    id: playZona
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: musicaBackend.togglePlay()
                }
            }
            BotonM {
                texto: "⏭"; pista: "Siguiente (Ctrl+→)"; tinta: theme.headerText
                onPulsado: musicaBackend.siguiente()
            }
            BotonM {
                texto: musicaBackend.repetir === 2 ? "🔂" : "🔁"; tam: 12
                pista: musicaBackend.repetir === 0 ? "Repetir: no" : (musicaBackend.repetir === 1 ? "Repetir: todo" : "Repetir: esta canción")
                activo: musicaBackend.repetir > 0; acento: theme.accent; tinta: theme.headerText
                onPulsado: musicaBackend.cicloRepetir()
            }
        }

        // Lo que suena: carátula, título, artista y posición
        Rectangle {
            id: lcd
            anchors.left: transporte.right
            anchors.leftMargin: 12
            anchors.right: derecha.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 44
            radius: 9
            color: theme.isDark ? Qt.rgba(0, 0, 0, 0.25) : Qt.rgba(0, 0, 0, 0.05)
            border.color: theme.headerBorder

            Portada {
                id: lcdPortada
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 4
                width: height
                radio: 5
                fuente: ventana.actual.portada || ""
                semilla: ventana.actual.album || "inti"
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { ventana.panelAbierto = true }
                }
            }
            Item {
                anchors.left: lcdPortada.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                Text {
                    id: lcdTitulo
                    anchors.top: parent.top
                    anchors.topMargin: 5
                    anchors.left: parent.left
                    anchors.right: lcdFav.left
                    anchors.rightMargin: 6
                    horizontalAlignment: Text.AlignHCenter
                    text: ventana.actual.titulo
                          ? ventana.actual.titulo + "  —  " + ventana.actual.artista
                          : (musicaBackend.totalCanciones > 0 ? "Elige una canción" : "Música")
                    color: theme.headerText
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    id: lcdFav
                    anchors.right: parent.right
                    anchors.verticalCenter: lcdTitulo.verticalCenter
                    visible: !!ventana.actual.ruta
                    readonly property bool fav: { musicaBackend.datosVersion; return musicaBackend.esFavorita(ventana.actual.ruta || "") }
                    text: fav ? "♥" : "♡"
                    color: fav ? "#ff2d55" : theme.headerTextMuted
                    font.pixelSize: 14
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: musicaBackend.alternarFavorita(ventana.actual.ruta)
                    }
                }
                Text {
                    id: tIzq
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    text: ventana.tiempo(posBarra.arrastrando ? posBarra.mostrado * musicaBackend.duracion : musicaBackend.posicion)
                    color: theme.headerTextMuted
                    font.pixelSize: 10
                    font.features: { "tnum": 1 }
                    width: 34
                }
                Barra {
                    id: posBarra
                    anchors.left: tIzq.right
                    anchors.right: tDer.left
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    anchors.verticalCenter: tIzq.verticalCenter
                    grosor: 3
                    color: theme.accent
                    fondo: theme.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.12)
                    enabled: musicaBackend.duracion > 0
                    valor: musicaBackend.duracion > 0 ? musicaBackend.posicion / musicaBackend.duracion : 0
                    onSoltado: (v) => musicaBackend.seek(v * musicaBackend.duracion)
                }
                Text {
                    id: tDer
                    anchors.right: parent.right
                    anchors.verticalCenter: tIzq.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: musicaBackend.duracion > 0 ? "-" + ventana.tiempo(musicaBackend.duracion - (posBarra.arrastrando ? posBarra.mostrado * musicaBackend.duracion : musicaBackend.posicion)) : "--:--"
                    color: theme.headerTextMuted
                    font.pixelSize: 10
                    font.features: { "tnum": 1 }
                    width: 38
                }
            }
        }

        Row {
            id: derecha
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: musicaBackend.silencio || musicaBackend.volumen === 0 ? "🔇" : (musicaBackend.volumen > 0.5 ? "🔊" : "🔉")
                font.pixelSize: 12
                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: musicaBackend.toggleSilencio() }
            }
            Barra {
                width: 74
                anchors.verticalCenter: parent.verticalCenter
                color: theme.isDark ? "#ffffff" : "#3a3a3c"
                fondo: theme.isDark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.12)
                valor: musicaBackend.silencio ? 0 : musicaBackend.volumen
                onMovido: (v) => musicaBackend.setVolumen(v)
                onSoltado: (v) => musicaBackend.setVolumen(v)
            }
            Item { width: 4; height: 1 }
            BotonM {
                texto: "❝"; tam: 15; pista: "Letra"
                activo: ventana.panelAbierto && ventana.pestanaPanel === "letra"; acento: theme.accent; tinta: theme.headerText
                onPulsado: { ventana.panelAbierto = !activo; ventana.pestanaPanel = "letra" }
            }
            BotonM {
                texto: "☰"; tam: 14; pista: "A continuación"
                activo: ventana.panelAbierto && ventana.pestanaPanel === "cola"; acento: theme.accent; tinta: theme.headerText
                onPulsado: { ventana.panelAbierto = !activo; ventana.pestanaPanel = "cola" }
            }
            Item { width: 4; height: 1 }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 170; height: 28; radius: 7
                color: theme.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
                border.color: buscador.activeFocus ? theme.accent : "transparent"
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "🔍"; font.pixelSize: 10; opacity: 0.6
                }
                TextField {
                    id: buscador
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 22
                    placeholderText: "Buscar en Música"
                    font.pixelSize: 12
                    color: theme.headerText
                    placeholderTextColor: theme.headerTextMuted
                    background: null
                    verticalAlignment: TextInput.AlignVCenter
                    text: musicaBackend.busqueda
                    onTextEdited: musicaBackend.busqueda = text
                    Keys.onEscapePressed: { musicaBackend.busqueda = ""; focus = false }
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: buscador.text !== ""
                    text: "✕"; font.pixelSize: 10; color: theme.headerTextMuted
                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: musicaBackend.busqueda = "" }
                }
            }
        }
    }

    component Col: Text {
        property string campo: ""
        height: 30
        verticalAlignment: Text.AlignVCenter
        property string etiqueta: ""
                                        text: etiqueta + (musicaBackend.orden === campo && campo !== "" ? (musicaBackend.ordenAsc ? "  ▲" : "  ▼") : "")
        color: musicaBackend.orden === campo && campo !== "" ? theme.accent : theme.contentTextSecondary
        font.pixelSize: 11
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        visible: width > 0
        MouseArea {
            anchors.fill: parent
            enabled: parent.campo !== ""
            cursorShape: Qt.PointingHandCursor
            onClicked: musicaBackend.ordenarPor(parent.campo)
        }
    }
    component Mini: Text {
        signal pulsado()
        color: theme.contentTextSecondary
        font.pixelSize: 11
        width: 18
        horizontalAlignment: Text.AlignHCenter
        MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: parent.pulsado() }
    }
    component Pildora: Rectangle {
        property string texto: ""
        property bool principal: false
        signal pulsado()
        width: pt.implicitWidth + 28
        height: 30
        radius: 8
        color: principal ? (pz.containsMouse ? theme.accentHover : theme.accent)
                         : (pz.containsMouse ? theme.itemHover : (theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)))
        Text { id: pt; anchors.centerIn: parent; text: parent.texto; color: parent.principal ? "#ffffff" : theme.accent; font.pixelSize: 13; font.weight: Font.DemiBold }
        MouseArea { id: pz; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.pulsado() }
    }
    component Campo: Row {
        property alias texto: tf.text
        property string etiqueta: ""
        property alias pista: tf.placeholderText
        spacing: 10
        Text { width: 110; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; text: parent.etiqueta; color: theme.contentTextSecondary; font.pixelSize: 12 }
        TextField { id: tf; width: 340; enabled: dlgInfo.d.editable === true; selectByMouse: true }
    }
    // ================================================================ BARRA LATERAL
    component ItemLateral: Rectangle {
        id: il
        property string glifo: ""
        property string texto: ""
        property string vista: ""
        property color tintaGlifo: theme.accent
        readonly property bool elegido: {
            var v = musicaBackend.vista
            if (musicaBackend.busqueda !== "") return false
            if (v === vista) return true
            if (vista === "albumes" && v.indexOf("album:") === 0) return true
            if (vista === "artistas" && v.indexOf("artista:") === 0) return true
            if (vista === "generos" && v.indexOf("genero:") === 0) return true
            return false
        }
        signal derecho(real x, real y)
        width: parent ? parent.width : 0
        height: 30
        radius: 7
        color: elegido ? theme.selectionBg : (ilZona.containsMouse ? theme.itemHover : "transparent")
        Text {
            id: ilGlifo
            anchors.left: parent.left; anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            horizontalAlignment: Text.AlignHCenter
            text: il.glifo
            color: il.tintaGlifo
            font.pixelSize: 13
        }
        Text {
            anchors.left: ilGlifo.right; anchors.leftMargin: 8
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: il.texto
            color: theme.sidebarText
            font.pixelSize: 13
            font.weight: il.elegido ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }
        MouseArea {
            id: ilZona
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (e) => {
                if (e.button === Qt.RightButton) il.derecho(e.x, e.y)
                else musicaBackend.abrir(il.vista)
            }
        }
    }
    component Seccion: Text {
        color: theme.sidebarTextMuted
        font.pixelSize: 11
        font.weight: Font.DemiBold
        leftPadding: 10
        topPadding: 12
        bottomPadding: 2
    }

    sidebarContentData: Flickable {
        anchors.fill: parent
        anchors.topMargin: 6
        contentHeight: lateral.height + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: lateral
            x: 8
            width: parent.width - 16
            spacing: 1

            Seccion { text: "Biblioteca" }
            ItemLateral { glifo: "🕘"; texto: "Añadidas recientemente"; vista: "recientes" }
            ItemLateral { glifo: "🎤"; texto: "Artistas"; vista: "artistas" }
            ItemLateral { glifo: "💿"; texto: "Álbumes"; vista: "albumes" }
            ItemLateral { glifo: "♪"; texto: "Canciones"; vista: "canciones" }
            ItemLateral { glifo: "🎼"; texto: "Géneros"; vista: "generos" }

            Seccion { text: "Favoritos" }
            ItemLateral { glifo: "♥"; tintaGlifo: "#ff2d55"; texto: "Me gusta"; vista: "favoritas" }
            ItemLateral { glifo: "📈"; texto: "Más escuchadas"; vista: "masEscuchadas" }

            Seccion { text: "Listas" }
            Repeater {
                model: musicaBackend.listas
                ItemLateral {
                    required property var modelData
                    glifo: "≡"; texto: modelData.nombre; vista: "lista:" + modelData.id
                    onDerecho: (x, y) => { menuLista.lista = modelData; menuLista.popup() }
                    DropArea {
                        anchors.fill: parent
                        keys: ["text/x-titan-ruta"]
                        onDropped: (d) => musicaBackend.anadirALista(modelData.id, [d.getDataAsString("text/x-titan-ruta")])
                    }
                }
            }
            ItemLateral {
                glifo: "＋"; texto: "Nueva lista"; vista: "__nueva"
                tintaGlifo: theme.sidebarTextMuted
                MouseArea { anchors.fill: parent; onClicked: dlgLista.nueva([]) }
            }
        }
    }

    // ================================================================ CONTENIDO
    Rectangle {
        anchors.fill: parent
        color: theme.contentBackground

        DropArea {
            anchors.fill: parent
            keys: ["text/uri-list"]
            onDropped: (d) => { if (d.hasUrls) musicaBackend.abrirArchivos(d.urls.map(u => u.toString())) }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 8
                radius: 12
                color: "transparent"
                border.color: theme.accent
                border.width: 2
                visible: parent.containsDrag
            }
        }

        Item {
            id: principal
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: panel.left

            // Volver
            Rectangle {
                id: botonVolver
                z: 5
                x: 18; y: 12
                visible: musicaBackend.puedeVolver && musicaBackend.busqueda === ""
                width: volverFila.width + 18; height: 26; radius: 13
                color: volverZona.containsMouse ? theme.itemHover : (theme.isDark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.7))
                border.color: theme.contentCardBorder
                Row {
                    id: volverFila
                    anchors.centerIn: parent
                    spacing: 4
                    Text { text: "‹"; color: theme.contentTextPrimary; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Volver"; color: theme.contentTextPrimary; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: volverZona; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: musicaBackend.volver() }
            }

            // ---------------- Rejillas: álbumes, artistas, géneros
            GridView {
                id: rejilla
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 6
                visible: ventana.vistaRejilla
                clip: true
                readonly property int columnas: Math.max(2, Math.floor((width - 4) / 190))
                cellWidth: Math.floor((width - 4) / columnas)
                cellHeight: ventana.tipoVista === "generos" ? cellWidth * 0.62 : cellWidth + 52
                model: ventana.tipoVista === "albumes" ? musicaBackend.albumes
                     : ventana.tipoVista === "artistas" ? musicaBackend.artistas
                     : ventana.tipoVista === "generos" ? musicaBackend.generos : []
                ScrollBar.vertical: ScrollBar {}

                header: Column {
                    width: rejilla.width
                    topPadding: 22
                    bottomPadding: 14
                    Text {
                        text: musicaBackend.infoVista.titulo || ""
                        color: theme.contentTextPrimary
                        font.pixelSize: 28
                        font.weight: Font.Bold
                    }
                }

                delegate: Item {
                    id: celda
                    required property var modelData
                    required property int index
                    width: rejilla.cellWidth
                    height: rejilla.cellHeight
                    readonly property bool esArtista: ventana.tipoVista === "artistas"
                    readonly property bool esGenero: ventana.tipoVista === "generos"

                    Portada {
                        id: celdaPortada
                        x: 4
                        width: parent.width - 18
                        height: celda.esGenero ? parent.height - 16 : width
                        radio: celda.esArtista ? width / 2 : 10
                        fuente: celda.esGenero ? "" : (modelData.portada || "")
                        semilla: modelData.titulo || modelData.nombre || ""
                        glifo: celda.esArtista ? "🎤" : (celda.esGenero ? "" : "♪")
                        sombra: celdaZona.containsMouse
                        scale: celdaZona.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        Text {
                            visible: celda.esGenero
                            anchors.left: parent.left; anchors.bottom: parent.bottom
                            anchors.margins: 12
                            width: parent.width - 24
                            text: modelData.nombre || ""
                            color: "#ffffff"
                            font.pixelSize: 17
                            font.weight: Font.Bold
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        // Reproducir el álbum sin abrirlo
                        Rectangle {
                            visible: ventana.tipoVista === "albumes" && celdaZona.containsMouse
                            anchors.left: parent.left; anchors.bottom: parent.bottom
                            anchors.margins: 10
                            width: 34; height: 34; radius: 17
                            color: playAlbum.containsMouse ? theme.accent : Qt.rgba(0, 0, 0, 0.55)
                            Text { anchors.centerIn: parent; anchors.horizontalCenterOffset: 1; text: "▶"; color: "#ffffff"; font.pixelSize: 13 }
                            MouseArea {
                                id: playAlbum
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: musicaBackend.reproducirAlbum(modelData.clave, false)
                            }
                            z: 3
                        }
                    }
                    Column {
                        visible: !celda.esGenero
                        anchors.top: celdaPortada.bottom
                        anchors.topMargin: 6
                        x: celda.esArtista ? 4 : 4
                        width: celdaPortada.width
                        spacing: 1
                        Text {
                            width: parent.width
                            horizontalAlignment: celda.esArtista ? Text.AlignHCenter : Text.AlignLeft
                            text: modelData.titulo || modelData.nombre || ""
                            color: theme.contentTextPrimary
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: celda.esArtista ? Text.AlignHCenter : Text.AlignLeft
                            text: celda.esArtista
                                  ? ((modelData.albumes === 1 ? "1 álbum" : modelData.albumes + " álbumes") + " · " + modelData.n + (modelData.n === 1 ? " canción" : " canciones"))
                                  : (modelData.artista + (modelData.anio > 0 ? " · " + modelData.anio : ""))
                            color: theme.contentTextSecondary
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: celdaZona
                        anchors.fill: celdaPortada
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (ventana.tipoVista === "albumes") musicaBackend.abrir("album:" + modelData.clave)
                            else if (celda.esArtista) musicaBackend.abrir("artista:" + modelData.nombre)
                            else musicaBackend.abrir("genero:" + modelData.nombre)
                        }
                    }
                }
            }

            // ---------------- Lista de canciones (con cabecera según la vista)
            ListView {
                id: lista
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 6
                visible: !ventana.vistaRejilla
                clip: true
                model: musicaBackend.canciones
                cacheBuffer: 600
                ScrollBar.vertical: ScrollBar {}
                bottomMargin: 20

                readonly property bool enAlbum: ventana.tipoVista === "album"
                readonly property var columnas: {
                    var w = width - 24 - 6
                    var fijo = 38 + 26 + 50 + 24 + 10 * 5
                    var resto = Math.max(160, w - fijo)
                    var conColumnas = resto > 420
                    if (enAlbum) return { num: 38, titulo: resto * 0.62, artista: conColumnas ? resto * 0.38 - 10 : 0, album: 0, fav: 26, dur: 50, mas: 24 }
                    return { num: 38, titulo: conColumnas ? resto * 0.40 : resto, artista: conColumnas ? resto * 0.28 - 5 : 0,
                             album: conColumnas ? resto * 0.32 - 5 : 0, fav: 26, dur: 50, mas: 24 }
                }

                header: Column {
                    width: lista.width - 10
                    spacing: 0

                    // Portada grande (álbum, artista, lista, género)
                    Item {
                        width: parent.width
                        height: heroe.visible ? heroe.height + 52 : tituloSimple.height + 34
                        Row {
                            id: heroe
                            visible: ["album", "artista", "lista", "genero"].indexOf(ventana.tipoVista) >= 0
                            y: 46
                            x: 6
                            spacing: 22
                            height: 190

                            Item {
                                width: 190; height: 190
                                Portada {
                                    anchors.fill: parent
                                    visible: ventana.tipoVista !== "lista" || (musicaBackend.infoVista.portadas || []).length < 4
                                    radio: ventana.tipoVista === "artista" ? 95 : 12
                                    sombra: true
                                    fuente: ventana.tipoVista === "lista" ? ((musicaBackend.infoVista.portadas || [])[0] || "") : (musicaBackend.infoVista.portada || "")
                                    semilla: musicaBackend.infoVista.titulo || ""
                                    glifo: ventana.tipoVista === "artista" ? "🎤" : (ventana.tipoVista === "lista" ? "≡" : "♪")
                                }
                                Grid {
                                    anchors.fill: parent
                                    visible: ventana.tipoVista === "lista" && (musicaBackend.infoVista.portadas || []).length >= 4
                                    columns: 2
                                    Repeater {
                                        model: (musicaBackend.infoVista.portadas || []).slice(0, 4)
                                        Portada { width: 95; height: 95; radio: 0; fuente: modelData }
                                    }
                                }
                            }
                            Column {
                                anchors.bottom: parent.bottom
                                spacing: 6
                                width: lista.width - 240
                                Text {
                                    text: ({ album: "ÁLBUM", artista: "ARTISTA", lista: "LISTA", genero: "GÉNERO" })[ventana.tipoVista] || ""
                                    color: theme.contentTextSecondary
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 1
                                }
                                Text {
                                    width: parent.width
                                    text: musicaBackend.infoVista.titulo || ""
                                    color: theme.contentTextPrimary
                                    font.pixelSize: 30
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: ventana.tipoVista === "album"
                                    text: musicaBackend.infoVista.artista || ""
                                    color: theme.accent
                                    font.pixelSize: 18
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: musicaBackend.abrir("artista:" + musicaBackend.infoVista.artista)
                                    }
                                }
                                Text {
                                    text: musicaBackend.infoVista.detalle || ""
                                    color: theme.contentTextSecondary
                                    font.pixelSize: 12
                                }
                                Item { width: 1; height: 6 }
                                Botonera {}
                            }
                        }
                        Column {
                            id: tituloSimple
                            visible: !heroe.visible
                            y: 20
                            x: 6
                            spacing: 4
                            Text {
                                text: musicaBackend.infoVista.titulo || ""
                                color: theme.contentTextPrimary
                                font.pixelSize: 28
                                font.weight: Font.Bold
                            }
                            Row {
                                spacing: 14
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: musicaBackend.infoVista.detalle || ""
                                    color: theme.contentTextSecondary
                                    font.pixelSize: 12
                                }
                                Botonera { visible: musicaBackend.canciones.length > 0 }
                            }
                        }
                    }

                    // Discografía del artista
                    Column {
                        visible: ventana.tipoVista === "artista" && musicaBackend.albumesArtista.length > 0
                        width: parent.width
                        spacing: 8
                        Text { text: "Álbumes"; color: theme.contentTextPrimary; font.pixelSize: 18; font.weight: Font.Bold; leftPadding: 6 }
                        ListView {
                            width: parent.width
                            height: 200
                            orientation: ListView.Horizontal
                            spacing: 14
                            clip: true
                            leftMargin: 6
                            model: musicaBackend.albumesArtista
                            delegate: Column {
                                width: 150
                                spacing: 4
                                Portada {
                                    width: 150; height: 150; radio: 10
                                    fuente: modelData.portada || ""; semilla: modelData.titulo
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: musicaBackend.abrir("album:" + modelData.clave) }
                                }
                                Text { width: 150; text: modelData.titulo; color: theme.contentTextPrimary; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                Text { width: 150; text: modelData.anio > 0 ? modelData.anio : ""; color: theme.contentTextSecondary; font.pixelSize: 11 }
                            }
                        }
                        Text { text: "Canciones"; color: theme.contentTextPrimary; font.pixelSize: 18; font.weight: Font.Bold; leftPadding: 6 }
                    }

                    // Cabecera de columnas (clic para ordenar)
                    Item {
                        visible: musicaBackend.canciones.length > 0
                        width: parent.width
                        height: 30
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10
                            Col { width: lista.columnas.num; etiqueta: "#"; horizontalAlignment: Text.AlignHCenter }
                            Col { width: lista.columnas.titulo; etiqueta: "Título"; campo: "titulo" }
                            Col { width: lista.columnas.artista; etiqueta: "Artista"; campo: "artista" }
                            Col { width: lista.columnas.album; etiqueta: "Álbum"; campo: "album" }
                            Col { width: lista.columnas.fav; etiqueta: "" }
                            Col { width: lista.columnas.dur; etiqueta: "⏱"; campo: "duracion"; horizontalAlignment: Text.AlignRight }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.contentCardBorder }
                    }
                }

                delegate: FilaCancion {
                    id: filaDel
                    required property var modelData
                    required property int index
                    width: lista.width - 10
                    tema: theme
                    cancion: modelData
                    numero: index + 1
                    columnas: lista.columnas
                    enAlbum: lista.enAlbum
                    onReproducir: musicaBackend.playTrack(index)
                    onMenu: (x, y) => ventana.abrirMenu(modelData, index, filaDel, x, y)

                }

                // Vacío
                Column {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 60
                    spacing: 10
                    visible: musicaBackend.canciones.length === 0 && !musicaBackend.escaneando
                    width: 360
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: musicaBackend.busqueda !== "" ? "🔍" : (ventana.tipoVista === "favoritas" ? "♡" : "🎵")
                        font.pixelSize: 44
                        color: theme.contentTextSecondary
                        opacity: 0.7
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: musicaBackend.busqueda !== "" ? "Sin resultados"
                            : musicaBackend.totalCanciones === 0 ? "Tu biblioteca está vacía"
                            : ventana.tipoVista === "favoritas" ? "Aún no tienes canciones favoritas"
                            : ventana.tipoVista === "lista" ? "Esta lista está vacía"
                            : ventana.tipoVista === "masEscuchadas" ? "Todavía no has escuchado nada"
                            : "No hay canciones"
                        color: theme.contentTextPrimary
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: musicaBackend.totalCanciones === 0
                              ? "Pon canciones en tu carpeta Música, arrástralas aquí o añade otra carpeta."
                              : ventana.tipoVista === "favoritas" ? "Pulsa ♡ en una canción para guardarla aquí."
                              : ventana.tipoVista === "lista" ? "Usa «Añadir a lista» en el menú de una canción, o arrástrala a la lista."
                              : ""
                        color: theme.contentTextSecondary
                        font.pixelSize: 12
                    }
                    Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: musicaBackend.totalCanciones === 0
                        text: "Añadir carpeta…"
                        onClicked: dlgCarpeta.open()
                    }
                }
            }

            BusyIndicator {
                anchors.centerIn: parent
                running: musicaBackend.escaneando && musicaBackend.totalCanciones === 0
                visible: running
            }
        }

        // ================================================================ PANEL DERECHO
        Rectangle {
            id: panel
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: ventana.panelAbierto ? 300 : 0
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            clip: true
            color: theme.isDark ? Qt.rgba(0, 0, 0, 0.18) : Qt.rgba(1, 1, 1, 0.35)
            Rectangle { width: 1; height: parent.height; color: theme.contentCardBorder }

            Item {
                x: 1
                width: 299
                height: parent.height

                Column {
                    id: panelArriba
                    x: 16; y: 16
                    width: parent.width - 32
                    spacing: 10

                    Portada {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: ventana.pestanaPanel === "letra" ? 96 : 220
                        height: width
                        Behavior on width { NumberAnimation { duration: 180 } }
                        radio: 10
                        sombra: true
                        fuente: ventana.actual.portada || ""
                        semilla: ventana.actual.album || "inti"
                    }
                    Column {
                        width: parent.width
                        spacing: 2
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: ventana.actual.titulo || "Nada sonando"
                            color: theme.contentTextPrimary
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: ventana.actual.artista ? ventana.actual.artista + " — " + ventana.actual.album : ""
                            color: theme.accent
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: !!ventana.actual.claveAlbum
                                onClicked: musicaBackend.abrir("album:" + ventana.actual.claveAlbum)
                            }
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: ventana.actual.calidad || ""
                            color: theme.contentTextSecondary
                            font.pixelSize: 10
                        }
                    }
                    // Pestañas
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 8
                        color: theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)
                        Row {
                            anchors.fill: parent
                            anchors.margins: 2
                            Repeater {
                                model: [{ id: "cola", t: "A continuación" }, { id: "letra", t: "Letra" }]
                                Rectangle {
                                    width: parent.width / 2
                                    height: parent.height
                                    radius: 6
                                    color: ventana.pestanaPanel === modelData.id ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.16) : "#ffffff") : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.t
                                        color: theme.contentTextPrimary
                                        font.pixelSize: 12
                                        font.weight: ventana.pestanaPanel === modelData.id ? Font.DemiBold : Font.Normal
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: ventana.pestanaPanel = modelData.id }
                                }
                            }
                        }
                    }
                }

                // Cola
                ListView {
                    id: listaCola
                    visible: ventana.pestanaPanel === "cola"
                    anchors.top: panelArriba.bottom
                    anchors.topMargin: 8
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    clip: true
                    model: musicaBackend.cola
                    ScrollBar.vertical: ScrollBar {}
                    header: Item {
                        width: listaCola.width
                        height: 30
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: musicaBackend.cola.length > 0 ? "Siguientes (" + musicaBackend.cola.length + ")" : "No hay nada después"
                            color: theme.contentTextSecondary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            visible: musicaBackend.cola.length > 0
                            text: "Vaciar"
                            color: theme.accent
                            font.pixelSize: 12
                            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: musicaBackend.vaciarCola() }
                        }
                    }
                    delegate: Rectangle {
                        id: colaDel
                        required property var modelData
                        required property int index
                        width: listaCola.width
                        height: 46
                        radius: 7
                        color: colaZona.containsMouse ? theme.itemHover : "transparent"
                        Portada {
                            id: colaPortada
                            x: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36; height: 36; radio: 5
                            fuente: modelData.portada || ""; semilla: modelData.album || ""
                        }
                        Column {
                            anchors.left: colaPortada.right; anchors.leftMargin: 8
                            anchors.right: colaBotones.left; anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            Text { width: parent.width; text: modelData.titulo; color: theme.contentTextPrimary; font.pixelSize: 12; elide: Text.ElideRight }
                            Text { width: parent.width; text: modelData.artista; color: theme.contentTextSecondary; font.pixelSize: 11; elide: Text.ElideRight }
                        }
                        Row {
                            id: colaBotones
                            anchors.right: parent.right; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            opacity: colaZona.containsMouse ? 1 : 0
                            Mini { text: "▲"; visible: index > 0; onPulsado: musicaBackend.moverEnCola(index, index - 1) }
                            Mini { text: "▼"; visible: index < musicaBackend.cola.length - 1; onPulsado: musicaBackend.moverEnCola(index, index + 1) }
                            Mini { text: "✕"; onPulsado: musicaBackend.quitarDeCola(index) }
                        }
                        MouseArea {
                            id: colaZona
                            anchors.fill: parent
                            hoverEnabled: true
                            z: -1
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onDoubleClicked: musicaBackend.saltarACola(index)
                            onClicked: (e) => { if (e.button === Qt.RightButton) ventana.abrirMenu(modelData, -1, colaDel, e.x, e.y) }
                        }
                    }
                }

                // Letra (sincronizada si el .lrc lleva tiempos)
                ListView {
                    id: listaLetra
                    visible: ventana.pestanaPanel === "letra"
                    anchors.top: panelArriba.bottom
                    anchors.topMargin: 10
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 18
                    anchors.rightMargin: 14
                    clip: true
                    spacing: 8
                    model: musicaBackend.letra
                    preferredHighlightBegin: height * 0.35
                    preferredHighlightEnd: height * 0.45
                    highlightRangeMode: musicaBackend.letraSincronizada && !moving ? ListView.ApplyRange : ListView.NoHighlightRange
                    highlightMoveDuration: 350
                    currentIndex: {
                        if (!musicaBackend.letraSincronizada) return -1
                        var l = musicaBackend.letra, p = musicaBackend.posicion + 250, r = -1
                        for (var i = 0; i < l.length; ++i) { if (l[i].ms <= p) r = i; else break }
                        return r
                    }
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Text {
                        required property var modelData
                        required property int index
                        width: listaLetra.width
                        text: modelData.texto === "" ? " " : modelData.texto
                        wrapMode: Text.Wrap
                        readonly property bool esActual: index === listaLetra.currentIndex
                        color: !musicaBackend.letraSincronizada || esActual ? theme.contentTextPrimary : theme.contentTextSecondary
                        opacity: !musicaBackend.letraSincronizada || esActual ? 1 : 0.55
                        font.pixelSize: musicaBackend.letraSincronizada ? 17 : 14
                        font.weight: musicaBackend.letraSincronizada ? Font.Bold : Font.Normal
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.ms >= 0
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: musicaBackend.seek(modelData.ms)
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 20
                        visible: musicaBackend.letra.length === 0
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: ventana.actual.ruta
                              ? "Esta canción no tiene letra.\n\nPon un archivo .lrc con el mismo nombre al lado de la canción y aparecerá aquí, sincronizada."
                              : "Cuando suene una canción, aquí verás su letra."
                        color: theme.contentTextSecondary
                        font.pixelSize: 12
                    }
                }
            }
        }

        // Aviso flotante
        Rectangle {
            id: avisoCaja
            anchors.horizontalCenter: principal.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: musicaBackend.aviso !== "" && avisoTimer.running ? 18 : -60
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            width: avisoTexto.implicitWidth + 32
            height: 34
            radius: 17
            color: theme.isDark ? "#2c2c2e" : "#1d1d1f"
            Text { id: avisoTexto; anchors.centerIn: parent; text: musicaBackend.aviso; color: "#ffffff"; font.pixelSize: 12 }
            Timer { id: avisoTimer; interval: 3200; onTriggered: musicaBackend.cerrarAviso() }
        }
    }

    // Botones Reproducir / Aleatorio (y opciones de la lista)
    component Botonera: Row {
        spacing: 8
        Pildora { texto: "▶  Reproducir"; principal: true; onPulsado: musicaBackend.reproducirVista(false) }
        Pildora { texto: "🔀  Aleatorio"; onPulsado: musicaBackend.reproducirVista(true) }
        Pildora {
            visible: ventana.tipoVista === "lista"
            texto: "•••"
            onPulsado: { menuLista.lista = { id: musicaBackend.infoVista.id, nombre: musicaBackend.infoVista.titulo }; menuLista.popup() }
        }
    }

    // ================================================================ BARRA DE ESTADO
    statusBarContentData: Item {
        anchors.fill: parent
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Text {
                text: musicaBackend.totalCanciones === 1 ? "1 canción en la biblioteca" : musicaBackend.totalCanciones + " canciones en la biblioteca"
                color: theme.contentTextSecondary
                font.pixelSize: 11
            }
            Text {
                visible: musicaBackend.escaneando
                text: "· Buscando música…"
                color: theme.accent
                font.pixelSize: 11
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 16
            Text {
                text: musicaBackend.temporizador === 0 ? "⏾ Temporizador"
                    : musicaBackend.temporizador < 0 ? "⏾ Al acabar la canción"
                    : "⏾ " + musicaBackend.temporizador + " min"
                color: musicaBackend.temporizador !== 0 ? theme.accent : theme.contentTextSecondary
                font.pixelSize: 11
                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: menuTemporizador.popup() }
            }
            Text {
                text: "📁 Carpetas"
                color: theme.contentTextSecondary
                font.pixelSize: 11
                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: dlgCarpetas.open() }
            }
        }
    }

    // ================================================================ MENÚS
    Menu {
        id: menuCancion
        property var cancion: ({})
        property int indice: -1
        readonly property bool fav: { musicaBackend.datosVersion; return musicaBackend.esFavorita(cancion.ruta || "") }

        MenuItem { text: "Reproducir"; onTriggered: menuCancion.indice >= 0 ? musicaBackend.playTrack(menuCancion.indice) : musicaBackend.reproducirRutas([menuCancion.cancion.ruta], 0, false) }
        MenuItem { text: "Reproducir a continuación"; onTriggered: musicaBackend.aContinuacion([menuCancion.cancion.ruta]) }
        MenuItem { text: "Añadir a la cola"; onTriggered: musicaBackend.aLaCola([menuCancion.cancion.ruta]) }
        MenuSeparator {}
        Menu {
            id: subListas
            title: "Añadir a lista"
            Instantiator {
                model: musicaBackend.listas
                delegate: MenuItem {
                    required property var modelData
                    text: modelData.nombre
                    onTriggered: musicaBackend.anadirALista(modelData.id, [menuCancion.cancion.ruta])
                }
                onObjectAdded: (i, o) => subListas.insertItem(i, o)
                onObjectRemoved: (i, o) => subListas.removeItem(o)
            }
            MenuSeparator {}
            MenuItem { text: "Nueva lista…"; onTriggered: dlgLista.nueva([menuCancion.cancion.ruta]) }
        }
        MenuItem {
            text: menuCancion.fav ? "Ya no me gusta" : "Me gusta"
            onTriggered: musicaBackend.alternarFavorita(menuCancion.cancion.ruta)
        }
        MenuSeparator {}
        MenuItem { text: "Ir al álbum"; onTriggered: musicaBackend.abrir("album:" + menuCancion.cancion.claveAlbum) }
        MenuItem { text: "Ir al artista"; onTriggered: musicaBackend.abrir("artista:" + menuCancion.cancion.artistaAlbum) }
        MenuItem { text: "Información y etiquetas…"; onTriggered: dlgInfo.abrirPara(menuCancion.cancion.ruta) }
        MenuItem { text: "Mostrar en el Explorador"; onTriggered: musicaBackend.mostrarEnFinder(menuCancion.cancion.ruta) }
        MenuSeparator {}
        MenuItem {
            text: "Quitar de la lista"
            visible: ventana.tipoVista === "lista" && menuCancion.indice >= 0
            height: visible ? implicitHeight : 0
            onTriggered: musicaBackend.quitarDeLista(musicaBackend.infoVista.id, menuCancion.indice)
        }
        MenuItem { text: "Mover a la papelera…"; onTriggered: dlgPapelera.abrirPara(menuCancion.cancion) }
    }

    Menu {
        id: menuLista
        property var lista: ({})
        MenuItem { text: "Reproducir"; onTriggered: { musicaBackend.abrir("lista:" + menuLista.lista.id); musicaBackend.reproducirVista(false) } }
        MenuItem { text: "Renombrar…"; onTriggered: dlgLista.renombrar(menuLista.lista) }
        MenuSeparator {}
        MenuItem { text: "Borrar lista"; onTriggered: musicaBackend.borrarLista(menuLista.lista.id) }
    }

    Menu {
        id: menuTemporizador
        MenuItem { text: "15 minutos"; onTriggered: musicaBackend.setTemporizador(15) }
        MenuItem { text: "30 minutos"; onTriggered: musicaBackend.setTemporizador(30) }
        MenuItem { text: "45 minutos"; onTriggered: musicaBackend.setTemporizador(45) }
        MenuItem { text: "1 hora"; onTriggered: musicaBackend.setTemporizador(60) }
        MenuItem { text: "Al acabar la canción"; onTriggered: musicaBackend.setTemporizador(-1) }
        MenuSeparator {}
        MenuItem { text: "Desactivar"; enabled: musicaBackend.temporizador !== 0; onTriggered: musicaBackend.setTemporizador(0) }
    }

    // ================================================================ DIÁLOGOS
    component Dialogo: Popup {
        anchors.centerIn: Overlay.overlay
        modal: true
        focus: true
        padding: 22
        background: Rectangle {
            radius: 14
            color: theme.isDark ? "#26272d" : "#ffffff"
            border.color: theme.contentCardBorder
        }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }
    }

    Dialogo {
        id: dlgLista
        property var rutas: []
        property string idRenombrar: ""
        width: 360
        function nueva(r) { rutas = r; idRenombrar = ""; campoLista.text = ""; open(); campoLista.forceActiveFocus() }
        function renombrar(l) { rutas = []; idRenombrar = l.id; campoLista.text = l.nombre; open(); campoLista.forceActiveFocus(); campoLista.selectAll() }
        function aceptar() {
            if (idRenombrar !== "") musicaBackend.renombrarLista(idRenombrar, campoLista.text)
            else {
                var id = musicaBackend.crearLista(campoLista.text, rutas)
                if (rutas.length === 0) musicaBackend.abrir("lista:" + id)
            }
            close()
        }
        contentItem: Column {
            spacing: 14
            Text { text: dlgLista.idRenombrar !== "" ? "Renombrar lista" : "Nueva lista"; color: theme.contentTextPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            TextField {
                id: campoLista
                width: parent.width
                placeholderText: "Nombre de la lista"
                onAccepted: dlgLista.aceptar()
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button { text: "Cancelar"; onClicked: dlgLista.close() }
                Button { text: dlgLista.idRenombrar !== "" ? "Renombrar" : "Crear"; highlighted: true; onClicked: dlgLista.aceptar() }
            }
        }
    }

    Dialogo {
        id: dlgPapelera
        property var cancion: ({})
        width: 380
        function abrirPara(c) { cancion = c; open() }
        contentItem: Column {
            spacing: 12
            Text { width: parent.width; text: "¿Mover «" + (dlgPapelera.cancion.titulo || "") + "» a la papelera?"; wrapMode: Text.Wrap; color: theme.contentTextPrimary; font.pixelSize: 15; font.weight: Font.Bold }
            Text { width: parent.width; text: "El archivo se quita de la biblioteca. Puedes recuperarlo desde la Papelera del Explorador de archivos."; wrapMode: Text.Wrap; color: theme.contentTextSecondary; font.pixelSize: 12 }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button { text: "Cancelar"; onClicked: dlgPapelera.close() }
                Button { text: "Mover a la papelera"; highlighted: true; onClicked: { musicaBackend.moverAPapelera([dlgPapelera.cancion.ruta]); dlgPapelera.close() } }
            }
        }
    }

    Dialogo {
        id: dlgInfo
        property var d: ({})
        property string error: ""
        width: 520
        function abrirPara(ruta) {
            d = musicaBackend.detalles(ruta)
            error = ""
            fTitulo.text = d.titulo || ""; fArtista.text = d.artista || ""; fAlbum.text = d.album || ""
            fArtistaAlbum.text = d.artistaAlbum !== d.artista ? (d.artistaAlbum || "") : ""
            fGenero.text = d.genero || ""; fAnio.text = d.anio > 0 ? d.anio : ""; fNumero.text = d.numero > 0 ? d.numero : ""
            open()
        }
        contentItem: Column {
            spacing: 8
            Row {
                spacing: 16
                Portada { width: 84; height: 84; radio: 8; fuente: dlgInfo.d.portada || ""; semilla: dlgInfo.d.album || "" }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text { text: dlgInfo.d.titulo || ""; color: theme.contentTextPrimary; font.pixelSize: 16; font.weight: Font.Bold; width: 360; elide: Text.ElideRight }
                    Text { text: (dlgInfo.d.artista || "") + " — " + (dlgInfo.d.album || ""); color: theme.contentTextSecondary; font.pixelSize: 12; width: 360; elide: Text.ElideRight }
                    Text {
                        text: (dlgInfo.d.calidad || "") + " · " + (dlgInfo.d.duracionTexto || "") + " · " + (dlgInfo.d.tamTexto || "")
                        color: theme.contentTextSecondary; font.pixelSize: 11
                    }
                    Text {
                        text: "Reproducida " + (dlgInfo.d.reproducciones || 0) + (dlgInfo.d.reproducciones === 1 ? " vez" : " veces")
                              + (dlgInfo.d.ultimaVez ? " · última: " + dlgInfo.d.ultimaVez : "")
                        color: theme.contentTextSecondary; font.pixelSize: 11
                    }
                }
            }
            Item { width: 1; height: 6 }
            Campo { id: fTitulo; etiqueta: "Título" }
            Campo { id: fArtista; etiqueta: "Artista" }
            Campo { id: fAlbum; etiqueta: "Álbum" }
            Campo { id: fArtistaAlbum; etiqueta: "Artista del álbum"; pista: "Igual que el artista" }
            Campo { id: fGenero; etiqueta: "Género" }
            Row {
                spacing: 10
                Text { width: 110; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; text: "Año"; color: theme.contentTextSecondary; font.pixelSize: 12 }
                TextField { id: fAnio; width: 90; enabled: dlgInfo.d.editable === true; validator: IntValidator { bottom: 0; top: 9999 } }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Pista"; color: theme.contentTextSecondary; font.pixelSize: 12 }
                TextField { id: fNumero; width: 70; enabled: dlgInfo.d.editable === true; validator: IntValidator { bottom: 0; top: 999 } }
            }
            Text {
                width: parent.width
                text: dlgInfo.d.editable === false ? "No tienes permiso para cambiar este archivo: las etiquetas solo se pueden ver." : (dlgInfo.d.carpeta || "")
                color: theme.contentTextSecondary; font.pixelSize: 10; elide: Text.ElideMiddle
            }
            Text { visible: dlgInfo.error !== ""; text: dlgInfo.error; color: "#ff453a"; font.pixelSize: 12 }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button { text: "Mostrar en el Explorador"; onClicked: musicaBackend.mostrarEnFinder(dlgInfo.d.ruta) }
                Button { text: "Cancelar"; onClicked: dlgInfo.close() }
                Button {
                    text: "Guardar"
                    highlighted: true
                    enabled: dlgInfo.d.editable === true
                    onClicked: {
                        var e = musicaBackend.guardarEtiquetas(dlgInfo.d.ruta, {
                            titulo: fTitulo.texto, artista: fArtista.texto, album: fAlbum.texto,
                            artistaAlbum: fArtistaAlbum.texto, genero: fGenero.texto,
                            anio: parseInt(fAnio.text) || 0, numero: parseInt(fNumero.text) || 0 })
                        if (e === "") dlgInfo.close(); else dlgInfo.error = e
                    }
                }
            }
        }
    }

    Dialogo {
        id: dlgCarpetas
        width: 460
        contentItem: Column {
            spacing: 12
            Text { text: "Carpetas de la biblioteca"; color: theme.contentTextPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            Text { width: parent.width; wrapMode: Text.Wrap; text: "Música busca canciones en estas carpetas (y en sus subcarpetas) y se actualiza sola cuando añades archivos."; color: theme.contentTextSecondary; font.pixelSize: 12 }
            Rectangle {
                width: parent.width
                height: Math.min(220, Math.max(44, musicaBackend.carpetas.length * 40 + 4))
                radius: 10
                color: theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04)
                ListView {
                    anchors.fill: parent
                    anchors.margins: 2
                    clip: true
                    model: musicaBackend.carpetas
                    delegate: Item {
                        required property string modelData
                        width: ListView.view.width
                        height: 40
                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 60; text: "📁  " + modelData; color: theme.contentTextPrimary; font.pixelSize: 12; elide: Text.ElideMiddle }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Quitar"; color: "#ff453a"; font.pixelSize: 12
                            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: musicaBackend.quitarCarpeta(modelData) }
                        }
                    }
                    Text { anchors.centerIn: parent; visible: musicaBackend.carpetas.length === 0; text: "Ninguna carpeta"; color: theme.contentTextSecondary; font.pixelSize: 12 }
                }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button { text: "Volver a buscar"; onClicked: musicaBackend.refrescar() }
                Button { text: "Añadir carpeta…"; onClicked: dlgCarpeta.open() }
                Button { text: "Listo"; highlighted: true; onClicked: dlgCarpetas.close() }
            }
        }
    }

    FolderDialog {
        id: dlgCarpeta
        title: "Elige una carpeta con música"
        onAccepted: musicaBackend.anadirCarpeta(selectedFolder.toString())
    }
}
