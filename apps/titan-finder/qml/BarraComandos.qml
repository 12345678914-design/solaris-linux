import QtQuick

// Barra de comandos del Explorador de archivos (como Windows 11):
// Nuevo ▾ | Cortar Copiar Pegar Renombrar Eliminar | Ordenar ▾ Ver ▾ ⋯ | Detalles
// Con poco ancho los botones de edición se quedan solo con el icono.
Rectangle {
    id: barra
    property var lista            // FileList: selección, acciones y menús
    TitanTheme { id: theme }

    height: 44
    color: theme.contentBackground
    readonly property bool compacta: width < 860
    readonly property int nSel: lista ? lista.nSel : 0

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.contentCardBorder }

    component Boton: Rectangle {
        id: b
        property string icono: ""
        property string texto: ""
        property bool conTexto: true
        property bool desplegable: false
        property bool activo: true
        property bool marcado: false
        property bool primario: false
        signal pulsado()
        height: 30
        width: fila.implicitWidth + 18
        radius: 6
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        opacity: activo ? 1 : 0.38
        color: primario ? (zona.containsMouse && activo ? Qt.darker(theme.accent, 1.1) : theme.accent)
             : marcado ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.22)
             : zona.containsMouse && activo ? theme.itemHover : "transparent"
        Row {
            id: fila
            anchors.centerIn: parent
            spacing: 7
            Icono {
                nombre: b.icono
                color: b.primario ? "#ffffff" : (b.marcado ? theme.accent : theme.contentTextPrimary)
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: b.conTexto && b.texto !== ""
                text: b.texto
                color: b.primario ? "#ffffff" : theme.contentTextPrimary
                font.pixelSize: 13
                font.weight: b.primario ? Font.DemiBold : Font.Normal
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: b.desplegable
                text: "▾"
                color: b.primario ? "#ffffff" : theme.contentTextSecondary
                font.pixelSize: 10
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: zona
            anchors.fill: parent
            hoverEnabled: true
            enabled: b.activo
            cursorShape: b.activo ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: b.pulsado()
        }
        // Nombre al pasar el ratón cuando solo se ve el icono
        Rectangle {
            visible: zona.containsMouse && !b.conTexto && b.texto !== ""
            z: 50
            y: parent.height + 6
            x: (parent.width - width) / 2
            width: pista.implicitWidth + 14; height: 22; radius: 5
            color: theme.isDark ? "#2c2c30" : "#1d1d1f"
            Text { id: pista; anchors.centerIn: parent; text: b.texto; color: "#ffffff"; font.pixelSize: 11 }
        }
    }
    component Separador: Rectangle { width: 1; height: 22; color: theme.contentCardBorder; anchors.verticalCenter: parent ? parent.verticalCenter : undefined }

    function opcionesNuevo() {
        var o = [{ t: "Carpeta", i: "▣", k: "Ctrl+Mayús+N", a: function () { barra.lista.openNewFolderDialog() } }, { sep: true }]
        return o.concat(finderBackend.tiposNuevos().map(function (d) {
            return { t: d.t, i: d.i, a: function () { barra.lista.crearDocumento(d.tipo) } }
        }))
    }
    function opcionesOrdenar() {
        var l = [["name", "Nombre"], ["date", "Fecha de modificación"], ["size", "Tamaño"], ["kind", "Tipo"]].map(function (c) {
            return { t: c[1], marca: finderBackend.sortBy === c[0], a: function () { finderBackend.sortBy = c[0] } }
        })
        l.push({ sep: true })
        l.push({ t: "Ascendente", marca: finderBackend.sortAscending, a: function () { finderBackend.sortAscending = true } })
        l.push({ t: "Descendente", marca: !finderBackend.sortAscending, a: function () { finderBackend.sortAscending = false } })
        return l
    }
    function opcionesVer() {
        return [
            { t: "Iconos grandes", marca: finderBackend.viewMode === "grid", a: function () { finderBackend.viewMode = "grid" } },
            { t: "Lista con detalles", marca: finderBackend.viewMode === "list", a: function () { finderBackend.viewMode = "list" } },
            { sep: true },
            { t: "Panel de detalles", marca: finderBackend.panelDetalles, k: "Alt+P",
              a: function () { finderBackend.panelDetalles = !finderBackend.panelDetalles } },
            { t: "Archivos ocultos", marca: finderBackend.showHiddenFiles, k: "Ctrl+H",
              a: function () { finderBackend.showHiddenFiles = !finderBackend.showHiddenFiles } }
        ]
    }
    function opcionesMas() {
        var o = []
        if (finderBackend.entries.length > 0) o.push({ t: "Seleccionar todo", i: "▦", k: "Ctrl+A", a: function () { barra.lista.seleccionarTodo() } })
        o.push({ t: "Abrir en Terminal", i: ">_", k: "Ctrl+T", a: function () { finderBackend.openTerminal() } })
        o.push({ t: "Copiar ruta", i: "⎘", a: function () { finderBackend.copiarRuta(barra.nSel > 0 ? barra.lista.objetivo() : [finderBackend.currentPath]) } })
        o.push({ sep: true })
        o.push({ t: "Propiedades", i: "ℹ", k: "Ctrl+I", a: function () { barra.lista.openProperties(barra.nSel > 0 ? barra.lista.selectedPath : finderBackend.currentPath) } })
        return o
    }

    Row {
        id: izquierda
        x: 10
        height: parent.height
        spacing: 2

        Boton {
            id: bNuevo
            icono: "nuevo"; texto: "Nuevo"; desplegable: true; primario: true
            activo: finderBackend.puedeEscribir
            onPulsado: barra.lista.mostrarMenu(barra.opcionesNuevo(), bNuevo)
        }
        Item { width: 6; height: 1 }
        Separador {}
        Item { width: 4; height: 1 }
        Boton { icono: "cortar"; texto: "Cortar"; conTexto: !barra.compacta; activo: barra.nSel > 0 && !finderBackend.enPapelera; onPulsado: barra.lista.cortar() }
        Boton { icono: "copiar"; texto: "Copiar"; conTexto: !barra.compacta; activo: barra.nSel > 0; onPulsado: barra.lista.copiar() }
        Boton { icono: "pegar"; texto: "Pegar"; conTexto: !barra.compacta; activo: finderBackend.hasClipboard && finderBackend.puedeEscribir; onPulsado: barra.lista.pegar() }
        Boton { icono: "renombrar"; texto: "Renombrar"; conTexto: !barra.compacta; activo: barra.nSel === 1 && !finderBackend.enPapelera; onPulsado: barra.lista.renombrar() }
        Boton { icono: "eliminar"; texto: "Eliminar"; conTexto: !barra.compacta; activo: barra.nSel > 0; onPulsado: barra.lista.eliminar(false) }
        Item { width: 4; height: 1 }
        Separador {}
        Item { width: 4; height: 1 }
        Boton {
            id: bOrdenar
            icono: "ordenar"; texto: "Ordenar"; desplegable: true
            onPulsado: barra.lista.mostrarMenu(barra.opcionesOrdenar(), bOrdenar)
        }
        Boton {
            id: bVer
            icono: finderBackend.viewMode === "grid" ? "iconos" : "lista"; texto: "Ver"; desplegable: true
            onPulsado: barra.lista.mostrarMenu(barra.opcionesVer(), bVer)
        }
        Boton {
            id: bMas
            icono: "mas"; texto: "Más opciones"; conTexto: false
            onPulsado: barra.lista.mostrarMenu(barra.opcionesMas(), bMas)
        }
    }

    Boton {
        anchors.right: parent.right
        anchors.rightMargin: 10
        icono: "detalles"; texto: "Detalles"; conTexto: barra.width > 640
        marcado: finderBackend.panelDetalles
        onPulsado: finderBackend.panelDetalles = !finderBackend.panelDetalles
    }
}
