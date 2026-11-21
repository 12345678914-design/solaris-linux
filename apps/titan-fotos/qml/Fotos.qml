import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs

TitanWindow {
    id: ventana

    width: 1180
    height: 760
    minimumWidth: 820
    minimumHeight: 520
    title: enVisor ? (fotosBackend.currentPhoto.name + " — Fotos") : "Fotos"
    sidebarWidth: 214
    showSidebar: !enVisor

    readonly property bool enVisor: fotosBackend.currentIndex >= 0
    property bool editando: false
    property bool presentacion: false
    property int tamCelda: 150                 // tamaño de las miniaturas
    // Selección en la rejilla (rutas)
    property var seleccion: ({})
    property int nSel: 0
    property int ancla: -1

    function rutasSel() { return Object.keys(seleccion) }
    function limpiarSel() { seleccion = ({}); nSel = 0 }
    function elegir(i, ctrl, shift) {
        var fotos = fotosBackend.photos
        if (i < 0 || i >= fotos.length) return
        var s = ctrl || shift ? Object.assign({}, seleccion) : ({})
        if (shift && ancla >= 0) {
            var a = Math.min(ancla, i), b = Math.max(ancla, i)
            for (var k = a; k <= b; ++k) s[fotos[k].path] = true
        } else if (ctrl && s[fotos[i].path]) {
            delete s[fotos[i].path]
        } else {
            s[fotos[i].path] = true
        }
        if (!shift) ancla = i
        seleccion = s
        nSel = Object.keys(s).length
    }
    function seleccionarTodo() {
        var s = ({})
        var fotos = fotosBackend.photos
        for (var i = 0; i < fotos.length; ++i) s[fotos[i].path] = true
        seleccion = s
        nSel = fotos.length
    }
    // Rutas sobre las que actúa un menú: la selección si la foto está en ella
    function objetivo(ruta) {
        if (enVisor) return [fotosBackend.currentPhoto.path]
        if (ruta && !seleccion[ruta]) return [ruta]
        return rutasSel()
    }
    function abrirVisor(i) { limpiarSel(); fotosBackend.selectPhoto(i) }
    function cerrarVisor() {
        var i = fotosBackend.currentIndex
        fotosBackend.selectPhoto(-1)
        if (i >= 0) rejilla.mostrar(i)
    }
    function empezarPresentacion() {
        if (fotosBackend.count === 0) return
        if (!enVisor) fotosBackend.selectPhoto(Math.max(0, ancla))
        presentacion = true
        ventana.showFullScreen()
        capaPresentacion.open()
    }
    function terminarPresentacion() {
        presentacion = false
        capaPresentacion.close()
        ventana.showNormal()
    }

    Connections {
        target: fotosBackend
        function onLevantarVentana() { ventana.raise(); ventana.requestActivate() }
        function onAvisoChanged() { if (fotosBackend.aviso !== "") avisoTimer.restart() }
        function onVistaChanged() { ventana.limpiarSel(); ventana.editando = false }
        function onPhotosChanged() {
            // Quitar de la selección lo que ya no está
            if (ventana.nSel === 0) return
            var s = ({}), n = 0, f = fotosBackend.photos
            for (var i = 0; i < f.length; ++i) if (ventana.seleccion[f[i].path]) { s[f[i].path] = true; n++ }
            ventana.seleccion = s; ventana.nSel = n
        }
    }

    // ---------------------------------------------------------------- atajos
    Shortcut { sequence: "Escape"; enabled: !ventana.editando && !ventana.presentacion
        onActivated: {
            if (ventana.enVisor) ventana.cerrarVisor()
            else if (ventana.nSel > 0) ventana.limpiarSel()
            else if (fotosBackend.searchQuery !== "") fotosBackend.searchQuery = ""
        }
    }
    Shortcut { sequences: ["Left"]; enabled: ventana.enVisor && !ventana.editando; onActivated: fotosBackend.previousPhoto() }
    Shortcut { sequences: ["Right"]; enabled: ventana.enVisor && !ventana.editando; onActivated: fotosBackend.nextPhoto() }
    Shortcut { sequences: ["Ctrl++", "Ctrl+="]; enabled: ventana.enVisor && !ventana.editando; onActivated: visor.ampliar(1.25) }
    Shortcut { sequence: "Ctrl+-"; enabled: ventana.enVisor && !ventana.editando; onActivated: visor.ampliar(0.8) }
    Shortcut { sequence: "Ctrl+0"; enabled: ventana.enVisor && !ventana.editando; onActivated: visor.ajustar() }
    Shortcut { sequence: "Ctrl+1"; enabled: ventana.enVisor && !ventana.editando; onActivated: visor.tamanoReal() }
    Shortcut { sequence: "Ctrl+R"; enabled: ventana.enVisor && !ventana.editando; onActivated: visor.giro = (visor.giro + 90) % 360 }
    Shortcut { sequence: "Ctrl+I"; enabled: ventana.enVisor && !ventana.editando; onActivated: visor.panelInfo = !visor.panelInfo }
    Shortcut { sequence: "Ctrl+E"; enabled: ventana.enVisor && !ventana.editando; onActivated: ventana.editar() }
    Shortcut { sequence: "Return"; enabled: !ventana.enVisor && ventana.nSel === 1; onActivated: ventana.abrirVisor(fotosBackend.indiceDe(ventana.rutasSel()[0])) }
    Shortcut { sequence: "Ctrl+A"; enabled: !ventana.enVisor && !buscador.activeFocus; onActivated: ventana.seleccionarTodo() }
    Shortcut { sequence: "Ctrl+C"; enabled: !buscador.activeFocus && (ventana.enVisor || ventana.nSel > 0); onActivated: fotosBackend.copiarAlPortapapeles(ventana.objetivo()) }
    Shortcut { sequence: "Delete"; enabled: !buscador.activeFocus && !ventana.editando && (ventana.enVisor || ventana.nSel > 0); onActivated: dlgPapelera.abrirPara(ventana.objetivo()) }
    Shortcut { sequence: "."; enabled: !buscador.activeFocus && !ventana.editando && (ventana.enVisor || ventana.nSel > 0); onActivated: fotosBackend.alternarFavorita(ventana.objetivo()) }
    Shortcut { sequence: "Ctrl+F"; enabled: !ventana.enVisor; onActivated: { buscador.forceActiveFocus(); buscador.selectAll() } }
    Shortcut { sequence: "Ctrl+W"; enabled: ventana.enVisor; onActivated: fotosBackend.setAsWallpaper() }
    Shortcut { sequence: "F5"; onActivated: ventana.empezarPresentacion() }

    function editar() {
        if (!enVisor) return
        editor.empezar(fotosBackend.currentPhoto)
        editando = true
    }

    // ---------------------------------------------------------------- barra superior
    headerContentData: Item {
        anchors.fill: parent

        // --- Rejilla: título, selección, orden, tamaño y búsqueda
        Item {
            anchors.fill: parent
            visible: !ventana.enVisor

            Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: ventana.nSel === 0
                Text { text: fotosBackend.tituloVista; color: theme.headerText; font.pixelSize: 15; font.weight: Font.Bold }
                Text { text: fotosBackend.statusText; color: theme.headerTextMuted; font.pixelSize: 11 }
            }

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: ventana.nSel > 0
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ventana.nSel === 1 ? "1 seleccionada" : ventana.nSel + " seleccionadas"
                    color: theme.headerText
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    rightPadding: 10
                }
                BotonM { texto: "♥"; pista: "Favorita (.)"; tinta: theme.headerText; onPulsado: fotosBackend.alternarFavorita(ventana.rutasSel()) }
                BotonM { texto: "＋"; pista: "Añadir a un álbum"; tinta: theme.headerText; onPulsado: { menuAlbum.rutas = ventana.rutasSel(); menuAlbum.popup() } }
                BotonM { texto: "⧉"; pista: "Copiar (Ctrl+C)"; tinta: theme.headerText; onPulsado: fotosBackend.copiarAlPortapapeles(ventana.rutasSel()) }
                BotonM {
                    visible: fotosBackend.vista.indexOf("album:") === 0
                    texto: "⊖"; pista: "Quitar del álbum"; tinta: theme.headerText
                    onPulsado: fotosBackend.quitarDeAlbum(fotosBackend.vista.substring(6), ventana.rutasSel())
                }
                BotonM { texto: "🗑"; tam: 12; pista: "Mover a la papelera (Supr)"; tinta: theme.headerText; onPulsado: dlgPapelera.abrirPara(ventana.rutasSel()) }
                BotonM { texto: "✕"; pista: "Quitar la selección (Esc)"; tinta: theme.headerText; onPulsado: ventana.limpiarSel() }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                BotonM { texto: "▶"; tam: 12; pista: "Presentación (F5)"; tinta: theme.headerText; anchors.verticalCenter: parent.verticalCenter; onPulsado: ventana.empezarPresentacion() }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: ordenTexto.implicitWidth + 22
                    height: 26
                    radius: 7
                    color: ordenZona.containsMouse ? Qt.rgba(theme.headerText.r, theme.headerText.g, theme.headerText.b, 0.12) : "transparent"
                    border.color: theme.headerBorder
                    Text {
                        id: ordenTexto
                        anchors.centerIn: parent
                        text: (fotosBackend.orden === "nombre" ? "Nombre" : fotosBackend.orden === "tamano" ? "Tamaño" : "Fecha")
                              + (fotosBackend.ordenAsc ? " ↑" : " ↓")
                        color: theme.headerText
                        font.pixelSize: 12
                    }
                    MouseArea { id: ordenZona; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: menuOrden.popup() }
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    BotonM { texto: "−"; pista: "Miniaturas más pequeñas"; tinta: theme.headerText; enabled: ventana.tamCelda > 80; onPulsado: ventana.tamCelda = Math.max(80, ventana.tamCelda - 35) }
                    BotonM { texto: "+"; pista: "Miniaturas más grandes"; tinta: theme.headerText; enabled: ventana.tamCelda < 360; onPulsado: ventana.tamCelda = Math.min(360, ventana.tamCelda + 35) }
                }
                TextField {
                    id: buscador
                    anchors.verticalCenter: parent.verticalCenter
                    width: 200
                    placeholderText: "Buscar (nombre, mes, cámara)"
                    text: fotosBackend.searchQuery
                    onTextEdited: fotosBackend.searchQuery = text
                    selectByMouse: true
                }
            }
        }

        // --- Visor
        Item {
            anchors.fill: parent
            visible: ventana.enVisor

            Row {
                id: izqVisor
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: !ventana.editando
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: volverFila.implicitWidth + 20
                    height: 28
                    radius: 14
                    color: volverZona.containsMouse ? Qt.rgba(theme.headerText.r, theme.headerText.g, theme.headerText.b, 0.14)
                                                    : Qt.rgba(theme.headerText.r, theme.headerText.g, theme.headerText.b, 0.07)
                    Row {
                        id: volverFila
                        anchors.centerIn: parent
                        spacing: 5
                        Text { text: "‹"; color: theme.headerText; font.pixelSize: 17; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -1 }
                        Text { text: fotosBackend.tituloVista; color: theme.headerText; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { id: volverZona; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ventana.cerrarVisor() }
                }
            }

            Column {
                anchors.centerIn: parent
                width: Math.max(100, parent.width - 2 * Math.max(izqVisor.width, derVisor.width) - 40)
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: ventana.editando ? "Editar · " + (fotosBackend.currentPhoto.name || "") : (fotosBackend.currentPhoto.date || "")
                    color: theme.headerText
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    elide: Text.ElideMiddle
                }
                Text {
                    width: parent.width
                    visible: !ventana.editando
                    horizontalAlignment: Text.AlignHCenter
                    text: (fotosBackend.currentIndex + 1) + " de " + fotosBackend.count + "  ·  " + (fotosBackend.currentPhoto.name || "")
                    color: theme.headerTextMuted
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                }
            }

            Row {
                id: derVisor
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                visible: !ventana.editando
                BotonM {
                    texto: fotosBackend.currentPhoto.favorita ? "♥" : "♡"
                    pista: "Favorita (.)"
                    activo: fotosBackend.currentPhoto.favorita === true
                    acento: "#ff2d55"
                    tinta: theme.headerText
                    onPulsado: fotosBackend.alternarFavorita([fotosBackend.currentPhoto.path])
                }
                BotonM { texto: "ⓘ"; pista: "Información (Ctrl+I)"; activo: visor.panelInfo; acento: theme.accent; tinta: theme.headerText; onPulsado: visor.panelInfo = !visor.panelInfo }
                BotonM { texto: "⟳"; pista: "Girar para ver (Ctrl+R)"; tinta: theme.headerText; onPulsado: visor.giro = (visor.giro + 90) % 360 }
                BotonM { texto: "✎"; pista: "Editar (Ctrl+E)"; tinta: theme.headerText; enabled: fotosBackend.currentPhoto.name !== undefined && !String(fotosBackend.currentPhoto.name).match(/\.(svg|gif)$/i); onPulsado: ventana.editar() }
                BotonM { texto: "▶"; tam: 12; pista: "Presentación (F5)"; tinta: theme.headerText; onPulsado: ventana.empezarPresentacion() }
                BotonM { texto: "⋯"; pista: "Más"; tinta: theme.headerText; onPulsado: { menuFoto.rutas = [fotosBackend.currentPhoto.path]; menuFoto.popup() } }
            }
        }
    }

    // ---------------------------------------------------------------- barra lateral
    component Seccion: Text {
        color: theme.sidebarTextMuted
        font.pixelSize: 11
        font.weight: Font.DemiBold
        leftPadding: 10
        topPadding: 12
        bottomPadding: 2
    }
    component ItemLateral: Rectangle {
        id: il
        property string glifo: ""
        property string texto: ""
        property string vista: ""
        property var cuenta: undefined
        property color tintaGlifo: theme.accent
        readonly property bool elegido: fotosBackend.vista === vista
        signal derecho()
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
            anchors.right: ilCuenta.left; anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: il.texto
            color: theme.sidebarText
            font.pixelSize: 13
            font.weight: il.elegido ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }
        Text {
            id: ilCuenta
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: il.cuenta !== undefined && il.cuenta > 0 ? il.cuenta : ""
            color: theme.sidebarTextMuted
            font.pixelSize: 11
        }
        MouseArea {
            id: ilZona
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (e) => {
                if (e.button === Qt.RightButton) il.derecho()
                else fotosBackend.abrir(il.vista)
            }
        }
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

            Seccion { text: "Fotos" }
            ItemLateral { glifo: "🖼"; texto: "Fototeca"; vista: "fototeca"; cuenta: fotosBackend.cuentas.fototeca }
            ItemLateral { glifo: "🕘"; texto: "Recientes"; vista: "recientes"; cuenta: fotosBackend.cuentas.recientes }
            ItemLateral { glifo: "♥"; tintaGlifo: "#ff2d55"; texto: "Favoritas"; vista: "favoritas"; cuenta: fotosBackend.cuentas.favoritas }
            ItemLateral { glifo: "✂"; texto: "Capturas de pantalla"; vista: "capturas"; cuenta: fotosBackend.cuentas.capturas }
            ItemLateral { glifo: "⬇"; texto: "Descargas"; vista: "descargas"; cuenta: fotosBackend.cuentas.descargas }
            ItemLateral { glifo: "🏞"; texto: "Fondos de pantalla"; vista: "fondos"; cuenta: fotosBackend.cuentas.fondos }

            Seccion { text: "Álbumes" }
            Repeater {
                model: fotosBackend.albumes
                ItemLateral {
                    required property var modelData
                    glifo: "▣"; texto: modelData.nombre; vista: "album:" + modelData.id
                    cuenta: fotosBackend.cuentas["album:" + modelData.id]
                    onDerecho: { menuAlbumLateral.album = modelData; menuAlbumLateral.popup() }
                }
            }
            ItemLateral {
                glifo: "＋"; texto: "Nuevo álbum"; vista: "__nuevo"
                tintaGlifo: theme.sidebarTextMuted
                MouseArea { anchors.fill: parent; onClicked: dlgAlbum.nuevo([]) }
            }

            Seccion { text: "Carpetas" }
            ItemLateral {
                visible: fotosBackend.vista === "suelta"
                glifo: "📂"; texto: fotosBackend.vista === "suelta" ? fotosBackend.tituloVista : ""; vista: "suelta"
            }
            Repeater {
                model: fotosBackend.carpetas
                ItemLateral {
                    required property var modelData
                    glifo: "📁"; texto: modelData.substring(modelData.lastIndexOf("/") + 1); vista: "carpeta:" + modelData
                    onDerecho: { menuCarpeta.ruta = modelData; menuCarpeta.popup() }
                }
            }
            ItemLateral {
                glifo: "＋"; texto: "Añadir carpeta…"; vista: "__carpeta"
                tintaGlifo: theme.sidebarTextMuted
                MouseArea { anchors.fill: parent; onClicked: dlgCarpeta.open() }
            }
        }
    }

    // ---------------------------------------------------------------- contenido
    Rectangle {
        anchors.fill: parent
        color: theme.contentBackground

        DropArea {
            anchors.fill: parent
            keys: ["text/uri-list"]
            onDropped: (d) => { if (d.hasUrls && d.urls.length > 0) fotosBackend.openFile(d.urls[0].toString()) }
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

        // --- Rejilla agrupada por meses
        ListView {
            id: rejilla
            anchors.fill: parent
            visible: !ventana.enVisor
            clip: true
            focus: !ventana.enVisor
            boundsBehavior: Flickable.StopAtBounds
            topMargin: 8
            bottomMargin: 16
            readonly property int margen: 16
            readonly property int hueco: 3
            readonly property int columnas: Math.max(1, Math.floor((width - 2 * margen + hueco) / (ventana.tamCelda + hueco)))
            readonly property real celda: (width - 2 * margen - (columnas - 1) * hueco) / columnas
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            // Una fila del modelo = hasta «columnas» fotos del mismo mes
            model: ListModel { id: filas }
            property var porMes: ({})
            function rehacer() {
                var f = fotosBackend.photos, cols = columnas
                var lista = [], cuenta = ({})
                var i = 0
                while (i < f.length) {
                    var mes = f[i].mes, desde = i, n = 0
                    while (i < f.length && n < cols && f[i].mes === mes) { n++; i++ }
                    lista.push({ mes: mes, desde: desde, n: n })
                    cuenta[mes] = (cuenta[mes] || 0) + n
                }
                porMes = cuenta
                var y = contentY
                filas.clear()
                filas.append(lista)
                contentY = y
            }
            function mostrar(indice) {
                for (var r = 0; r < filas.count; ++r) {
                    var fila = filas.get(r)
                    if (indice >= fila.desde && indice < fila.desde + fila.n) { positionViewAtIndex(r, ListView.Contain); return }
                }
            }
            onColumnasChanged: rehacer()
            Connections { target: fotosBackend; function onPhotosChanged() { rejilla.rehacer() } }
            Component.onCompleted: rehacer()

            section.property: "mes"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
                required property string section
                width: rejilla.width
                height: section === "" ? 0 : 46
                visible: section !== ""
                Row {
                    x: rejilla.margen
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    spacing: 8
                    Text {
                        text: section.charAt(0).toUpperCase() + section.slice(1)
                        color: theme.contentTextPrimary
                        font.pixelSize: 17
                        font.weight: Font.Bold
                    }
                    Text {
                        anchors.baseline: parent.children[0].baseline
                        text: (rejilla.porMes[section] || 0) + ((rejilla.porMes[section] || 0) === 1 ? " foto" : " fotos")
                        color: theme.contentTextSecondary
                        font.pixelSize: 12
                    }
                }
            }

            delegate: Item {
                id: fila
                required property int desde
                required property int n
                width: rejilla.width
                height: rejilla.celda + rejilla.hueco
                Row {
                x: rejilla.margen
                spacing: rejilla.hueco
                Repeater {
                    model: fila.n
                    Item {
                        id: celda
                        required property int index
                        readonly property int i: fila.desde + index
                        readonly property var foto: fotosBackend.photos[i] || ({})
                        readonly property bool sel: ventana.nSel > 0 && ventana.seleccion[foto.path] === true
                        width: rejilla.celda
                        height: rejilla.celda

                        Rectangle { anchors.fill: parent; color: theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.05) }
                        Image {
                            anchors.fill: parent
                            anchors.margins: celda.sel ? 5 : 0
                            Behavior on anchors.margins { NumberAnimation { duration: 120 } }
                            source: celda.foto.miniatura || ""
                            sourceSize.width: Math.min(256, Math.round(rejilla.celda * Screen.devicePixelRatio))
                            sourceSize.height: Math.min(256, Math.round(rejilla.celda * Screen.devicePixelRatio))
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }
                        Rectangle {
                            anchors.fill: parent
                            color: celdaZona.containsMouse && !celda.sel ? Qt.rgba(0, 0, 0, 0.12) : "transparent"
                            border.width: celda.sel ? 3 : 0
                            border.color: theme.accent
                        }
                        Text {
                            visible: celda.foto.favorita === true
                            anchors.left: parent.left; anchors.bottom: parent.bottom
                            anchors.margins: 6
                            text: "♥"
                            color: "#ffffff"
                            font.pixelSize: 14
                            style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.4)
                        }
                        Rectangle {
                            visible: celda.sel
                            anchors.right: parent.right; anchors.bottom: parent.bottom
                            anchors.margins: 8
                            width: 20; height: 20; radius: 10
                            color: theme.accent
                            border.color: "#ffffff"
                            border.width: 1.5
                            Text { anchors.centerIn: parent; text: "✓"; color: "#ffffff"; font.pixelSize: 11; font.bold: true }
                        }
                        MouseArea {
                            id: celdaZona
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (e) => {
                                rejilla.forceActiveFocus()
                                if (e.button === Qt.RightButton) {
                                    if (!celda.sel) ventana.elegir(celda.i, false, false)
                                    menuFoto.rutas = ventana.objetivo(celda.foto.path)
                                    menuFoto.popup()
                                    return
                                }
                                ventana.elegir(celda.i, e.modifiers & Qt.ControlModifier, e.modifiers & Qt.ShiftModifier)
                            }
                            onDoubleClicked: (e) => { if (e.button === Qt.LeftButton) ventana.abrirVisor(celda.i) }
                        }
                    }
                }
                }
            }

            // Clic en el fondo: quitar selección
            MouseArea {
                z: -1
                width: rejilla.width
                height: Math.max(rejilla.height, rejilla.contentHeight)
                onClicked: ventana.limpiarSel()
            }

        }

        // Sin fotos
        Column {
            anchors.centerIn: parent
            visible: fotosBackend.count === 0 && !ventana.enVisor
            spacing: 8
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: fotosBackend.cargando ? "⏳" : "🖼"; font.pixelSize: 46; opacity: 0.6 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: fotosBackend.cargando ? "Buscando fotos…"
                      : fotosBackend.searchQuery !== "" ? "Nada coincide con «" + fotosBackend.searchQuery + "»"
                      : fotosBackend.vista === "favoritas" ? "Aún no hay favoritas"
                      : fotosBackend.vista.indexOf("album:") === 0 ? "Este álbum está vacío"
                      : "No hay fotos aquí"
                color: theme.contentTextPrimary
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 360
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: !fotosBackend.cargando && fotosBackend.searchQuery === ""
                text: fotosBackend.vista === "favoritas" ? "Marca una foto con ♥ (o pulsa «.») para verla aquí."
                      : fotosBackend.vista.indexOf("album:") === 0 ? "Selecciona fotos en la Fototeca y usa «Añadir a un álbum»."
                      : "Guarda fotos en Imágenes, o añade otra carpeta desde la barra lateral."
                color: theme.contentTextSecondary
                font.pixelSize: 12
            }
        }

        Visor {
            id: visor
            anchors.fill: parent
            theme: ventana.theme
            visible: ventana.enVisor && !ventana.editando
        }

        Editor {
            id: editor
            anchors.fill: parent
            theme: ventana.theme
            visible: ventana.editando
            onTerminado: ventana.editando = false
        }

        // Aviso breve
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: fotosBackend.aviso !== "" && avisoTimer.running ? (ventana.enVisor && !ventana.editando ? 84 : 18) : -60
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            width: avisoTexto.implicitWidth + 32
            height: 34
            radius: 17
            color: theme.isDark ? "#2c2c2e" : "#1d1d1f"
            Text { id: avisoTexto; anchors.centerIn: parent; text: fotosBackend.aviso; color: "#ffffff"; font.pixelSize: 12 }
            Timer { id: avisoTimer; interval: 3200 }
        }
    }

    statusBarContentData: Item {
        anchors.fill: parent
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: ventana.enVisor ? ((fotosBackend.currentPhoto.dimensions || "") + "   " + (fotosBackend.currentPhoto.size || "")) : fotosBackend.statusText
            color: theme.contentTextSecondary
            font.pixelSize: 11
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            visible: ventana.enVisor && !ventana.editando
            Repeater {
                model: [["−", function () { visor.ampliar(0.8) }], ["Ajustar", function () { visor.ajustar() }],
                        ["100 %", function () { visor.tamanoReal() }], ["+", function () { visor.ampliar(1.25) }],
                        [visor.tira ? "Ocultar tira" : "Mostrar tira", function () { visor.tira = !visor.tira }]]
                Text {
                    required property var modelData
                    text: modelData[0]
                    color: theme.contentTextSecondary
                    font.pixelSize: 11
                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: parent.modelData[1]() }
                }
            }
            Text { text: Math.round(visor.zoomReal * 100) + " %"; color: theme.contentTextPrimary; font.pixelSize: 11; font.weight: Font.DemiBold }
        }
    }

    // ---------------------------------------------------------------- menús
    Menu {
        popupType: Popup.Window   // ventana propia: se ve entera aunque estés al borde
        id: menuOrden
        MenuItem { text: "Fecha"; checkable: true; checked: fotosBackend.orden === "fecha"; onTriggered: fotosBackend.ordenarPor("fecha") }
        MenuItem { text: "Nombre"; checkable: true; checked: fotosBackend.orden === "nombre"; onTriggered: fotosBackend.ordenarPor("nombre") }
        MenuItem { text: "Tamaño"; checkable: true; checked: fotosBackend.orden === "tamano"; onTriggered: fotosBackend.ordenarPor("tamano") }
        MenuSeparator {}
        MenuItem { text: fotosBackend.ordenAsc ? "Invertir (ahora: ascendente)" : "Invertir (ahora: descendente)"; onTriggered: fotosBackend.ordenarPor(fotosBackend.orden) }
    }

    Menu {
        popupType: Popup.Window   // ventana propia: se ve entera aunque estés al borde
        id: menuFoto
        property var rutas: []
        readonly property bool una: rutas.length === 1
        readonly property bool todasFav: {
            for (var i = 0; i < rutas.length; ++i) if (!fotosBackend.esFavorita(rutas[i])) return false
            return rutas.length > 0
        }
        MenuItem { text: "Abrir"; visible: menuFoto.una && !ventana.enVisor; height: visible ? implicitHeight : 0; onTriggered: ventana.abrirVisor(fotosBackend.indiceDe(menuFoto.rutas[0])) }
        MenuItem { text: "Editar"; visible: menuFoto.una; height: visible ? implicitHeight : 0
            onTriggered: { fotosBackend.selectPhoto(fotosBackend.indiceDe(menuFoto.rutas[0])); ventana.editar() } }
        MenuItem { text: menuFoto.todasFav ? "Quitar de favoritas" : "Marcar como favorita"; onTriggered: fotosBackend.alternarFavorita(menuFoto.rutas) }
        MenuItem { text: "Añadir a un álbum…"; onTriggered: { menuAlbum.rutas = menuFoto.rutas; menuAlbum.popup() } }
        MenuItem {
            text: "Quitar del álbum"
            visible: fotosBackend.vista.indexOf("album:") === 0; height: visible ? implicitHeight : 0
            onTriggered: fotosBackend.quitarDeAlbum(fotosBackend.vista.substring(6), menuFoto.rutas)
        }
        MenuSeparator {}
        MenuItem { text: menuFoto.una ? "Copiar" : "Copiar " + menuFoto.rutas.length + " fotos"; onTriggered: fotosBackend.copiarAlPortapapeles(menuFoto.rutas) }
        MenuItem { text: "Usar como fondo de pantalla"; visible: menuFoto.una; height: visible ? implicitHeight : 0; onTriggered: fotosBackend.setAsWallpaper(menuFoto.rutas[0]) }
        MenuItem { text: "Mostrar en el Finder"; visible: menuFoto.una; height: visible ? implicitHeight : 0; onTriggered: fotosBackend.openInFinder(menuFoto.rutas[0]) }
        MenuItem { text: "Cambiar nombre…"; visible: menuFoto.una; height: visible ? implicitHeight : 0; onTriggered: dlgNombre.abrirPara(menuFoto.rutas[0]) }
        MenuItem { text: "Presentación"; onTriggered: ventana.empezarPresentacion() }
        MenuSeparator {}
        MenuItem { text: menuFoto.una ? "Mover a la papelera" : "Mover " + menuFoto.rutas.length + " fotos a la papelera"; onTriggered: dlgPapelera.abrirPara(menuFoto.rutas) }
    }

    Menu {
        popupType: Popup.Window   // ventana propia: se ve entera aunque estés al borde
        id: menuAlbum
        property var rutas: []
        Instantiator {
            model: fotosBackend.albumes
            delegate: MenuItem {
                required property var modelData
                text: modelData.nombre
                onTriggered: fotosBackend.anadirAAlbum(modelData.id, menuAlbum.rutas)
            }
            onObjectAdded: (i, o) => menuAlbum.insertItem(i, o)
            onObjectRemoved: (i, o) => menuAlbum.removeItem(o)
        }
        MenuSeparator { visible: fotosBackend.albumes.length > 0 }
        MenuItem { text: "Nuevo álbum…"; onTriggered: dlgAlbum.nuevo(menuAlbum.rutas) }
    }

    Menu {
        popupType: Popup.Window   // ventana propia: se ve entera aunque estés al borde
        id: menuAlbumLateral
        property var album: ({})
        MenuItem { text: "Cambiar nombre…"; onTriggered: dlgAlbum.renombrar(menuAlbumLateral.album) }
        MenuItem { text: "Presentación"; onTriggered: { fotosBackend.abrir("album:" + menuAlbumLateral.album.id); ventana.empezarPresentacion() } }
        MenuSeparator {}
        MenuItem { text: "Eliminar álbum (las fotos no se borran)"; onTriggered: fotosBackend.borrarAlbum(menuAlbumLateral.album.id) }
    }

    Menu {
        popupType: Popup.Window   // ventana propia: se ve entera aunque estés al borde
        id: menuCarpeta
        property string ruta: ""
        MenuItem { text: "Mostrar en el Finder"; onTriggered: fotosBackend.openInFinder(menuCarpeta.ruta) }
        MenuItem { text: "Quitar de Fotos (no se borra nada)"; onTriggered: fotosBackend.quitarCarpeta(menuCarpeta.ruta) }
    }

    // ---------------------------------------------------------------- diálogos
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
        id: dlgPapelera
        property var rutas: []
        width: 400
        function abrirPara(r) { if (r.length === 0) return; rutas = r; open() }
        contentItem: Column {
            spacing: 12
            Text {
                width: parent.width
                text: dlgPapelera.rutas.length === 1 ? "¿Mover esta foto a la papelera?" : "¿Mover " + dlgPapelera.rutas.length + " fotos a la papelera?"
                wrapMode: Text.Wrap
                color: theme.contentTextPrimary
                font.pixelSize: 15
                font.weight: Font.Bold
            }
            Text {
                width: parent.width
                text: "Se quitan de Fotos y de sus álbumes. Puedes recuperarlas desde la Papelera del Finder."
                wrapMode: Text.Wrap
                color: theme.contentTextSecondary
                font.pixelSize: 12
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button { text: "Cancelar"; onClicked: dlgPapelera.close() }
                Button {
                    text: "Mover a la papelera"
                    highlighted: true
                    onClicked: {
                        var r = dlgPapelera.rutas
                        dlgPapelera.close()
                        fotosBackend.moverAPapelera(r)
                        if (fotosBackend.count === 0) fotosBackend.selectPhoto(-1)
                    }
                }
            }
        }
    }

    Dialogo {
        id: dlgNombre
        property string ruta: ""
        property string error: ""
        width: 380
        function abrirPara(r) {
            ruta = r; error = ""
            var n = r.substring(r.lastIndexOf("/") + 1)
            campoNombre.text = n
            open()
            campoNombre.forceActiveFocus()
            campoNombre.select(0, n.lastIndexOf(".") > 0 ? n.lastIndexOf(".") : n.length)
        }
        function aceptar() {
            error = fotosBackend.renombrar(ruta, campoNombre.text)
            if (error === "") close()
        }
        contentItem: Column {
            spacing: 12
            Text { text: "Cambiar nombre"; color: theme.contentTextPrimary; font.pixelSize: 16; font.weight: Font.Bold }
            TextField { id: campoNombre; width: parent.width; onAccepted: dlgNombre.aceptar(); selectByMouse: true }
            Text { visible: dlgNombre.error !== ""; text: dlgNombre.error; color: "#ff453a"; font.pixelSize: 12 }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button { text: "Cancelar"; onClicked: dlgNombre.close() }
                Button { text: "Cambiar"; highlighted: true; onClicked: dlgNombre.aceptar() }
            }
        }
    }

    Dialogo {
        id: dlgAlbum
        property var rutas: []
        property string idRenombrar: ""
        width: 360
        function nuevo(r) { rutas = r; idRenombrar = ""; campoAlbum.text = ""; open(); campoAlbum.forceActiveFocus() }
        function renombrar(a) { rutas = []; idRenombrar = a.id; campoAlbum.text = a.nombre; open(); campoAlbum.forceActiveFocus(); campoAlbum.selectAll() }
        function aceptar() {
            if (idRenombrar !== "") fotosBackend.renombrarAlbum(idRenombrar, campoAlbum.text)
            else {
                var id = fotosBackend.crearAlbum(campoAlbum.text, rutas)
                if (rutas.length === 0) fotosBackend.abrir("album:" + id)
            }
            close()
        }
        contentItem: Column {
            spacing: 14
            Text {
                text: dlgAlbum.idRenombrar !== "" ? "Cambiar nombre del álbum"
                      : dlgAlbum.rutas.length > 0 ? "Nuevo álbum con " + dlgAlbum.rutas.length + (dlgAlbum.rutas.length === 1 ? " foto" : " fotos") : "Nuevo álbum"
                color: theme.contentTextPrimary
                font.pixelSize: 16
                font.weight: Font.Bold
            }
            TextField { id: campoAlbum; width: parent.width; placeholderText: "Nombre del álbum"; onAccepted: dlgAlbum.aceptar(); selectByMouse: true }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button { text: "Cancelar"; onClicked: dlgAlbum.close() }
                Button { text: dlgAlbum.idRenombrar !== "" ? "Cambiar" : "Crear"; highlighted: true; onClicked: dlgAlbum.aceptar() }
            }
        }
    }

    FolderDialog {
        id: dlgCarpeta
        title: "Añadir una carpeta a Fotos"
        onAccepted: fotosBackend.anadirCarpeta(selectedFolder.toString())
    }

    // ---------------------------------------------------------------- presentación
    Popup {
        id: capaPresentacion
        parent: Overlay.overlay
        x: 0; y: 0
        width: parent ? parent.width : 0
        height: parent ? parent.height : 0
        modal: true
        focus: true
        padding: 0
        closePolicy: Popup.CloseOnEscape
        onClosed: if (ventana.presentacion) ventana.terminarPresentacion()
        Shortcut { sequence: "Escape"; enabled: ventana.presentacion; onActivated: ventana.terminarPresentacion() }
        background: Rectangle { color: "#000000" }
        property bool pausa: false

        contentItem: Item {
            focus: true
            Keys.onSpacePressed: capaPresentacion.pausa = !capaPresentacion.pausa
            Keys.onLeftPressed: { fotosBackend.previousPhoto(); paso.restart() }
            Keys.onRightPressed: { fotosBackend.nextPhoto(); paso.restart() }

            // Dos capas que se funden al cambiar de foto
            Image {
                id: capaA
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                autoTransform: true
                sourceSize.width: 3840
                sourceSize.height: 3840
                source: capaPresentacion.visible ? (fotosBackend.currentPhoto.url || "") : ""
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 600 } }
                scale: 1.0
                // Ligero acercamiento lento (efecto Ken Burns)
                NumberAnimation on scale { id: kenBurns; from: 1.0; to: 1.06; duration: paso.interval + 800; running: capaPresentacion.visible && !capaPresentacion.pausa }
                onSourceChanged: kenBurns.restart()
            }
            Timer {
                id: paso
                interval: 4000
                repeat: true
                running: capaPresentacion.visible && !capaPresentacion.pausa
                onTriggered: fotosBackend.nextPhoto()
            }
            HoverHandler { id: sobrePres }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 30
                width: presFila.implicitWidth + 28
                height: 44
                radius: 22
                color: Qt.rgba(0.1, 0.1, 0.1, 0.75)
                opacity: sobrePres.hovered || capaPresentacion.pausa ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Row {
                    id: presFila
                    anchors.centerIn: parent
                    spacing: 4
                    BotonM { texto: "⏮"; tinta: "#ffffff"; onPulsado: { fotosBackend.previousPhoto(); paso.restart() } }
                    BotonM { texto: capaPresentacion.pausa ? "▶" : "❚❚"; tinta: "#ffffff"; onPulsado: capaPresentacion.pausa = !capaPresentacion.pausa }
                    BotonM { texto: "⏭"; tinta: "#ffffff"; onPulsado: { fotosBackend.nextPhoto(); paso.restart() } }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 8; rightPadding: 8
                        text: (fotosBackend.currentIndex + 1) + " / " + fotosBackend.count
                        color: "#ffffff"
                        font.pixelSize: 12
                    }
                    BotonM {
                        texto: paso.interval / 1000 + " s"; tam: 11; tinta: "#ffffff"; width: 40
                        pista: "Tiempo por foto"
                        onPulsado: paso.interval = paso.interval >= 8000 ? 2000 : paso.interval + 2000
                    }
                    BotonM { texto: "✕"; tinta: "#ffffff"; pista: "Salir (Esc)"; onPulsado: ventana.terminarPresentacion() }
                }
            }
        }
    }
}
