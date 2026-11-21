import QtQuick
import QtQuick.Controls

// Lista de archivos del Finder.
//  - Selección: clic, Ctrl+clic (añadir/quitar), Mayús+clic (rango) y
//    recuadro arrastrando en el fondo (con Ctrl se suma a lo que había).
//  - Mantener pulsado sobre lo seleccionado lo AGRUPA en un montón con el
//    número de elementos; al arrastrar se mueven todos juntos.
//  - Soltar sobre una carpeta (o en el fondo) mueve; con Ctrl, copia.
//    Mover solo dentro de la carpeta personal (lo demás se copia).
//  - Ctrl+C / Ctrl+X / Ctrl+V con uno o con muchos.
Rectangle {
    id: fileListRoot

    TitanTheme { id: theme }

    color: theme.contentBackground
    focus: true

    // Selección
    property var selectedPaths: []
    property string selectedPath: ""      // el último pulsado (renombrar, propiedades)
    property string selectedName: ""
    property bool selectedIsDir: false
    property int ancla: -1
    property var itemProperties: ({})

    // Recuadro de selección (coordenadas del contenido de la vista)
    property bool rbActivo: false
    property var rbVista: null
    property var rbBase: []
    property real rbX0: 0
    property real rbY0: 0
    property real rbX1: 0
    property real rbY1: 0
    property real rbRaton: 0

    // Pulsación sobre un elemento (para arrastrar o agrupar)
    property bool pActivo: false
    property string pPath: ""
    property real pX: 0
    property real pY: 0
    property bool agrupando: false
    property bool arrastrando: false

    property bool ctxVisible: false
    property real ctxX: 0
    property real ctxY: 0

    readonly property int nSel: selectedPaths.length
    readonly property var vistaActiva: finderBackend.viewMode === "grid" ? gridView : listView

    // ------------------------------------------------------------ selección
    function estaSeleccionado(p) { return selectedPaths.indexOf(p) !== -1 }
    function indiceDe(p) {
        var e = finderBackend.entries
        for (var i = 0; i < e.length; ++i) if (e[i].path === p) return i
        return -1
    }
    function fijarActual(p) {
        var i = indiceDe(p)
        var e = i >= 0 ? finderBackend.entries[i] : null
        selectedPath = p
        selectedName = e ? e.name : ""
        selectedIsDir = e ? e.isDir : false
    }
    function seleccionarSolo(p) {
        selectedPaths = p ? [p] : []
        ancla = indiceDe(p)
        if (p) fijarActual(p); else { selectedPath = ""; selectedName = "" }
    }
    function limpiarSeleccion() { seleccionarSolo("") }
    function alternar(p) {
        var s = selectedPaths.slice()
        var k = s.indexOf(p)
        if (k >= 0) s.splice(k, 1); else s.push(p)
        selectedPaths = s
        ancla = indiceDe(p)
        if (s.length > 0) fijarActual(s[s.length - 1]); else { selectedPath = ""; selectedName = "" }
    }
    function rango(p) {
        var i = indiceDe(p)
        var a = ancla >= 0 ? ancla : i
        var e = finderBackend.entries, s = []
        for (var k = Math.min(a, i); k <= Math.max(a, i); ++k) s.push(e[k].path)
        selectedPaths = s
        fijarActual(p)
    }
    function seleccionarTodo() {
        var e = finderBackend.entries, s = []
        for (var i = 0; i < e.length; ++i) s.push(e[i].path)
        selectedPaths = s
        if (s.length > 0) fijarActual(s[0])
    }
    // Lo que afecta una acción: la selección (o nada)
    function objetivo() { return selectedPaths.length > 0 ? selectedPaths.slice() : (selectedPath ? [selectedPath] : []) }

    // ------------------------------------------------------------ acciones
    function copiar() { var o = objetivo(); if (o.length > 0) finderBackend.copyItems(o) }
    function cortar() { var o = objetivo(); if (o.length > 0) finderBackend.cortar(o) }
    // Ctrl+V pega en la carpeta abierta; "Pegar dentro" (menú) en la carpeta seleccionada.
    function pegar() { finderBackend.paste() }
    function pegarDentro() { if (selectedPaths.length === 1 && selectedIsDir) finderBackend.paste(selectedPaths[0]) }
    function eliminar(definitivo) {
        var o = objetivo()
        if (o.length === 0) return
        if (definitivo || finderBackend.enPapelera) {
            confirmar(o.length === 1 ? "¿Eliminar «" + nombreDe(o[0]) + "» para siempre?" : "¿Eliminar " + o.length + " elementos para siempre?",
                      "No se podrán recuperar.", "Eliminar", function () { finderBackend.eliminarDefinitivamente(o); limpiarSeleccion() })
        } else {
            finderBackend.deleteItems(o)
            limpiarSeleccion()
        }
    }
    function vaciarPapelera() {
        confirmar("¿Vaciar la Papelera?", "Todo lo que hay en la Papelera se eliminará para siempre.", "Vaciar Papelera",
                  function () { finderBackend.vaciarPapelera(); limpiarSeleccion() })
    }
    function nombreDe(p) { var i = p.lastIndexOf("/"); return i >= 0 ? p.substring(i + 1) : p }
    function renombrar() {
        if (!selectedPath) return
        renameField.text = selectedName
        renameDialog.open()
        renameField.forceActiveFocus()
        // Como Windows: se selecciona el nombre sin la extensión
        var punto = selectedName.lastIndexOf(".")
        if (!selectedIsDir && punto > 0) renameField.select(0, punto)
        else renameField.selectAll()
    }
    // Nuevo documento: se crea y se pide el nombre en seguida
    function crearDocumento(tipo) {
        var ruta = finderBackend.nuevoArchivo(tipo)
        if (!ruta) return
        Qt.callLater(function () { fileListRoot.seleccionarSolo(ruta); fileListRoot.renombrar() })
    }
    function confirmar(titulo, texto, boton, accion) {
        dlgConfirmar.titulo = titulo
        dlgConfirmar.texto = texto
        dlgConfirmar.boton = boton
        dlgConfirmar.accion = accion
        dlgConfirmar.open()
    }
    function openProperties(path) {
        var target = path && path.length > 0 ? path : (selectedPath.length > 0 ? selectedPath : finderBackend.currentPath)
        itemProperties = finderBackend.getFileProperties(target)
        propertiesDialog.open()
    }
    function openNewFolderDialog() {
        if (!finderBackend.puedeEscribir) {
            finderBackend.createFolder("") // solo para el aviso
            return
        }
        folderNameField.text = "Nueva carpeta"
        newFolderDialog.open()
        folderNameField.forceActiveFocus()
        folderNameField.selectAll()
    }
    // posX/posY: en coordenadas de la lista; el menú va en la capa de toda la ventana
    function showContextMenu(posX, posY) {
        var q = fileListRoot.mapToItem(capaMenu, posX, posY)
        ctxX = q.x
        ctxY = q.y
        ctxVisible = true
    }

    Connections {
        target: finderBackend
        function onCurrentPathChanged() { fileListRoot.limpiarSeleccion(); fileListRoot.ctxVisible = false }
        function onAvisoChanged() { if (finderBackend.aviso !== "") avisoTimer.restart() }
    }

    Keys.onPressed: (event) => {
        var ctrl = event.modifiers & Qt.ControlModifier
        if (ctrl && event.key === Qt.Key_A) { seleccionarTodo(); event.accepted = true }
        else if (ctrl && event.key === Qt.Key_C) { copiar(); event.accepted = true }
        else if (ctrl && event.key === Qt.Key_X) { cortar(); event.accepted = true }
        else if (ctrl && event.key === Qt.Key_V) { pegar(); event.accepted = true }
        else if (event.key === Qt.Key_Delete) { eliminar(event.modifiers & Qt.ShiftModifier); event.accepted = true }
        else if (event.key === Qt.Key_F2) { renombrar(); event.accepted = true }
        else if (event.key === Qt.Key_Escape) { limpiarSeleccion(); ctxVisible = false; event.accepted = true }
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && selectedPaths.length === 1) {
            finderBackend.openItem(selectedPaths[0]); event.accepted = true
        }
    }

    // ------------------------------------------------------------ pulsar sobre un elemento
    function alPresionar(mouse, entrada, item) {
        fileListRoot.forceActiveFocus()
        ctxVisible = false
        var p = entrada.path
        if (mouse.button === Qt.RightButton) {
            if (!estaSeleccionado(p)) seleccionarSolo(p); else fijarActual(p)
            var q = item.mapToItem(fileListRoot, mouse.x, mouse.y)
            showContextMenu(q.x, q.y)
            return
        }
        if (mouse.modifiers & Qt.ControlModifier) { alternar(p); return }
        if (mouse.modifiers & Qt.ShiftModifier) { rango(p); return }
        if (!estaSeleccionado(p)) seleccionarSolo(p); else fijarActual(p)
        var r = item.mapToItem(fileListRoot, mouse.x, mouse.y)
        pActivo = true
        pPath = p
        pX = r.x
        pY = r.y
    }
    function alMover(mouse, item) {
        if (!pActivo || !(mouse.buttons & Qt.LeftButton)) return
        var r = item.mapToItem(fileListRoot, mouse.x, mouse.y)
        if (Math.abs(r.x - pX) + Math.abs(r.y - pY) > 8) {
            pActivo = false
            var paths = estaSeleccionado(pPath) ? selectedPaths.slice() : [pPath]
            arrastrando = true
            finderBackend.arrastrar(paths)   // bloquea hasta soltar
            arrastrando = false
            agrupando = false
        }
    }
    function alMantener() {
        // Mantener pulsado con varios seleccionados: se juntan en un montón.
        if (pActivo && selectedPaths.length > 1 && estaSeleccionado(pPath)) agrupando = true
    }
    function alSoltarRaton(mouse, entrada) {
        if (pActivo && !agrupando && !(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
                && selectedPaths.length > 1 && mouse.button === Qt.LeftButton)
            seleccionarSolo(entrada.path)
        pActivo = false
        agrupando = false
    }

    // ------------------------------------------------------------ recuadro en el fondo
    function fondoPresionado(mouse, vista) {
        fileListRoot.forceActiveFocus()
        ctxVisible = false
        if (mouse.button === Qt.RightButton) {
            limpiarSeleccion()
            var q = vista.mapToItem(fileListRoot, mouse.x, mouse.y)
            showContextMenu(q.x, q.y)
            return
        }
        var sumar = mouse.modifiers & Qt.ControlModifier
        rbBase = sumar ? selectedPaths.slice() : []
        if (!sumar) limpiarSeleccion()
        rbVista = vista
        rbX0 = rbX1 = mouse.x + vista.contentX
        rbY0 = rbY1 = mouse.y + vista.contentY
        rbRaton = mouse.y
        rbActivo = false
    }
    function fondoMovido(mouse, vista) {
        if (!(mouse.buttons & Qt.LeftButton) || rbVista !== vista) return
        rbRaton = mouse.y
        rbX1 = Math.max(0, Math.min(vista.width, mouse.x)) + vista.contentX
        rbY1 = mouse.y + vista.contentY
        if (!rbActivo && Math.abs(rbX1 - rbX0) + Math.abs(rbY1 - rbY0) > 5) rbActivo = true
        if (rbActivo) actualizarRecuadro()
    }
    function fondoSoltado() { rbActivo = false; rbVista = null }

    function actualizarRecuadro() {
        var v = rbVista
        if (!v) return
        var x1 = Math.min(rbX0, rbX1), x2 = Math.max(rbX0, rbX1)
        var y1 = Math.min(rbY0, rbY1), y2 = Math.max(rbY0, rbY1)
        var e = finderBackend.entries
        var s = rbBase.slice()
        var i
        if (v === gridView) {
            var cw = gridView.cellWidth, ch = gridView.cellHeight
            var cols = Math.max(1, Math.floor(gridView.width / cw))
            for (i = 0; i < e.length; ++i) {
                var cx = (i % cols) * cw + 6, cy = Math.floor(i / cols) * ch + 6
                if (cx < x2 && cx + cw - 12 > x1 && cy < y2 && cy + ch - 12 > y1 && s.indexOf(e[i].path) === -1)
                    s.push(e[i].path)
            }
        } else {
            var desde = Math.max(0, Math.floor(y1 / 30)), hasta = Math.min(e.length - 1, Math.floor(y2 / 30))
            for (i = desde; i <= hasta; ++i) if (s.indexOf(e[i].path) === -1) s.push(e[i].path)
        }
        selectedPaths = s
        if (s.length > 0) fijarActual(s[s.length - 1])
    }

    // Desplazar solo si el recuadro llega al borde
    Timer {
        interval: 30
        repeat: true
        running: fileListRoot.rbActivo && fileListRoot.rbVista !== null
                 && (fileListRoot.rbRaton < 24 || fileListRoot.rbRaton > fileListRoot.rbVista.height - 24)
        onTriggered: {
            var v = fileListRoot.rbVista
            var paso = fileListRoot.rbRaton < 24 ? -14 : 14
            var max = Math.max(0, v.contentHeight - v.height)
            var nuevo = Math.max(0, Math.min(max, v.contentY + paso))
            fileListRoot.rbY1 += nuevo - v.contentY
            v.contentY = nuevo
            fileListRoot.actualizarRecuadro()
        }
    }

    // Soltar en el fondo = a la carpeta actual
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: (drag) => { if (finderBackend.enPapelera && !fileListRoot.arrastrando) drag.accepted = true }
        onDropped: (drop) => {
            if (!drop.hasUrls) return
            finderBackend.soltar(drop.urls.map(u => u.toString()), finderBackend.currentPath, drop.proposedAction === Qt.CopyAction)
            drop.accept(Qt.CopyAction)
        }
    }

    // Diálogo para renombrar archivo o carpeta estilo macOS
    Dialog {
        id: renameDialog
        anchors.centerIn: parent
        width: 360
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0
        header: null
        footer: null

        background: Rectangle {
            color: theme.isDark ? "#24252a" : "#ffffff"
            radius: 14
            border.color: theme.glassBorder
            border.width: 1
        }

        contentItem: Column {
            padding: 20
            spacing: 14

            Row {
                spacing: 12
                anchors.horizontalCenter: parent.horizontalCenter

                Image {
                    source: fileListRoot.selectedIsDir ? "qrc:/icons/folder.png" : "qrc:/icons/notes.png"
                    width: 36
                    height: 36
                    fillMode: Image.PreserveAspectFit
                }

                Column {
                    spacing: 3
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "Renombrar elemento"
                        color: theme.contentTextPrimary
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Text {
                        text: "Introduce el nuevo nombre:"
                        color: theme.contentTextSecondary
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                width: parent.width - 40
                height: 32
                anchors.horizontalCenter: parent.horizontalCenter
                radius: 6
                color: theme.isDark ? "#1a1b1f" : "#f5f5f7"
                border.color: renameField.activeFocus ? theme.accent : theme.glassBorder
                border.width: renameField.activeFocus ? 2 : 1

                TextField {
                    id: renameField
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    text: fileListRoot.selectedName
                    color: theme.contentTextPrimary
                    font.pixelSize: 12
                    background: null
                    verticalAlignment: Text.AlignVCenter
                    selectByMouse: true

                    Keys.onReturnPressed: renameDialog.accept()
                    Keys.onEnterPressed: renameDialog.accept()
                    Keys.onEscapePressed: renameDialog.reject()
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                spacing: 10

                // Botón Cancelar
                Rectangle {
                    width: 78
                    height: 28
                    radius: 6
                    color: cancelRenameMouse.containsMouse ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : (theme.isDark ? "#2e2f36" : "#f5f5f7")
                    border.color: theme.glassBorder
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Cancelar"
                        color: theme.contentTextPrimary
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: cancelRenameMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: renameDialog.reject()
                    }
                }

                // Botón Aceptar / Renombrar
                Rectangle {
                    width: 86
                    height: 28
                    radius: 6
                    color: okRenameMouse.pressed ? Qt.darker(theme.accent, 1.25) : okRenameMouse.containsMouse ? Qt.lighter(theme.accent, 1.08) : theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "Aceptar"
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    MouseArea {
                        id: okRenameMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: renameDialog.accept()
                    }
                }
            }
        }

        onAccepted: {
            if (renameField.text.trim().length > 0) {
                finderBackend.renameItem(fileListRoot.selectedPath, renameField.text.trim())
            }
        }
    }

    // Diálogo para crear nueva carpeta estilo macOS (modal card blanco, bordes redondeados y botón Crear azul)
    Dialog {
        id: newFolderDialog
        anchors.centerIn: parent
        width: 360
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0
        header: null
        footer: null

        background: Rectangle {
            color: theme.isDark ? "#24252a" : "#ffffff"
            radius: 14
            border.color: theme.glassBorder
            border.width: 1
        }

        contentItem: Column {
            padding: 20
            spacing: 14

            Row {
                spacing: 12
                anchors.horizontalCenter: parent.horizontalCenter

                Image {
                    source: "qrc:/icons/folder.png"
                    width: 38
                    height: 38
                    fillMode: Image.PreserveAspectFit
                }

                Column {
                    spacing: 3
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "Nueva carpeta"
                        color: theme.contentTextPrimary
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Text {
                        text: "Introduce el nombre de la carpeta:"
                        color: theme.contentTextSecondary
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                width: parent.width - 40
                height: 32
                anchors.horizontalCenter: parent.horizontalCenter
                radius: 6
                color: theme.isDark ? "#1a1b1f" : "#f5f5f7"
                border.color: folderNameField.activeFocus ? theme.accent : theme.glassBorder
                border.width: folderNameField.activeFocus ? 2 : 1

                TextField {
                    id: folderNameField
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    text: "Nueva carpeta"
                    color: theme.contentTextPrimary
                    font.pixelSize: 12
                    background: null
                    verticalAlignment: Text.AlignVCenter
                    selectByMouse: true

                    Keys.onReturnPressed: newFolderDialog.accept()
                    Keys.onEnterPressed: newFolderDialog.accept()
                    Keys.onEscapePressed: newFolderDialog.reject()
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                spacing: 10

                // Botón Cancelar
                Rectangle {
                    width: 78
                    height: 28
                    radius: 6
                    color: cancelFolderMouse.containsMouse ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : (theme.isDark ? "#2e2f36" : "#f5f5f7")
                    border.color: theme.glassBorder
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Cancelar"
                        color: theme.contentTextPrimary
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: cancelFolderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: newFolderDialog.reject()
                    }
                }

                // Botón Crear (macOS blue)
                Rectangle {
                    width: 86
                    height: 28
                    radius: 6
                    color: okFolderMouse.pressed ? Qt.darker(theme.accent, 1.25) : okFolderMouse.containsMouse ? Qt.lighter(theme.accent, 1.08) : theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "Crear"
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    MouseArea {
                        id: okFolderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: newFolderDialog.accept()
                    }
                }
            }
        }

        onAccepted: {
            finderBackend.createFolder(folderNameField.text.trim())
        }
    }

    // Diálogo "Obtener información / Propiedades" estilo macOS Liquid Glass
    Dialog {
        id: propertiesDialog
        anchors.centerIn: parent
        width: 380
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0
        header: null
        footer: null

        background: Rectangle {
            color: theme.isDark ? "#24252a" : "#ffffff"
            radius: 14
            border.color: theme.glassBorder
            border.width: 1
        }

        contentItem: Column {
            padding: 20
            spacing: 14
            width: parent.width

            // Cabecera con icono grande y nombre
            Row {
                spacing: 14
                width: parent.width - 40
                anchors.horizontalCenter: parent.horizontalCenter

                Image {
                    source: itemProperties.icon ? itemProperties.icon : "qrc:/icons/files.png"
                    width: 48
                    height: 48
                    fillMode: Image.PreserveAspectFit
                }

                Column {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 62

                    Text {
                        text: itemProperties.name ? itemProperties.name : "Propiedades"
                        color: theme.contentTextPrimary
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideMiddle
                        width: parent.width
                    }

                    Text {
                        text: itemProperties.type ? itemProperties.type : ""
                        color: theme.contentTextSecondary
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                width: parent.width - 40
                height: 1
                color: theme.glassBorder
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Datos detallados del archivo o directorio
            Column {
                width: parent.width - 40
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                // Tamaño
                Row {
                    spacing: 10
                    width: parent.width
                    Text { width: 90; text: "Tamaño:"; color: theme.contentTextSecondary; font.pixelSize: 11; font.bold: true }
                    Text { width: parent.width - 100; text: itemProperties.size ? (itemProperties.isDir ? "--" : (itemProperties.size + " (" + itemProperties.bytes + ")")) : "--"; color: theme.contentTextPrimary; font.pixelSize: 11; elide: Text.ElideRight }
                }

                // Ubicación
                Row {
                    spacing: 10
                    width: parent.width
                    Text { width: 90; text: "Ubicación:"; color: theme.contentTextSecondary; font.pixelSize: 11; font.bold: true }
                    Text { width: parent.width - 100; text: itemProperties.dir ? itemProperties.dir : "--"; color: theme.contentTextPrimary; font.pixelSize: 11; elide: Text.ElideMiddle }
                }

                // Modificado
                Row {
                    spacing: 10
                    width: parent.width
                    Text { width: 90; text: "Modificado:"; color: theme.contentTextSecondary; font.pixelSize: 11; font.bold: true }
                    Text { width: parent.width - 100; text: itemProperties.modified ? itemProperties.modified : "--"; color: theme.contentTextPrimary; font.pixelSize: 11 }
                }

                // Creado
                Row {
                    spacing: 10
                    width: parent.width
                    Text { width: 90; text: "Creado:"; color: theme.contentTextSecondary; font.pixelSize: 11; font.bold: true }
                    Text { width: parent.width - 100; text: itemProperties.created ? itemProperties.created : "--"; color: theme.contentTextPrimary; font.pixelSize: 11 }
                }

                // Permisos
                Row {
                    spacing: 10
                    width: parent.width
                    Text { width: 90; text: "Permisos:"; color: theme.contentTextSecondary; font.pixelSize: 11; font.bold: true }
                    Text { width: parent.width - 100; text: itemProperties.permissions ? itemProperties.permissions : "--"; color: theme.contentTextPrimary; font.pixelSize: 11; font.family: "monospace" }
                }

                // Propietario
                Row {
                    spacing: 10
                    width: parent.width
                    Text { width: 90; text: "Propietario:"; color: theme.contentTextSecondary; font.pixelSize: 11; font.bold: true }
                    Text { width: parent.width - 100; text: (itemProperties.owner ? itemProperties.owner : "") + (itemProperties.group ? (" (" + itemProperties.group + ")") : ""); color: theme.contentTextPrimary; font.pixelSize: 11 }
                }
            }

            Rectangle {
                width: parent.width - 40
                height: 1
                color: theme.glassBorder
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Botón Cerrar estilo macOS
            Rectangle {
                width: 90
                height: 28
                radius: 6
                color: closePropsMouse.pressed ? Qt.darker(theme.accent, 1.25) : closePropsMouse.containsMouse ? Qt.lighter(theme.accent, 1.08) : theme.accent
                anchors.horizontalCenter: parent.horizontalCenter

                Text {
                    anchors.centerIn: parent
                    text: "Cerrar"
                    color: "#ffffff"
                    font.pixelSize: 12
                    font.bold: true
                }

                MouseArea {
                    id: closePropsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: propertiesDialog.close()
                }
            }
        }
    }


    // ------------------------------------------------------------ confirmar
    Dialog {
        id: dlgConfirmar
        property string titulo: ""
        property string texto: ""
        property string boton: "Aceptar"
        property var accion: null
        anchors.centerIn: parent
        width: 380
        modal: true
        padding: 22
        header: null
        footer: null
        background: Rectangle {
            color: theme.isDark ? "#24252a" : "#ffffff"
            radius: 14
            border.color: theme.glassBorder
        }
        contentItem: Column {
            spacing: 10
            Text { width: parent.width; text: dlgConfirmar.titulo; wrapMode: Text.Wrap; color: theme.contentTextPrimary; font.pixelSize: 15; font.bold: true }
            Text { width: parent.width; text: dlgConfirmar.texto; wrapMode: Text.Wrap; color: theme.contentTextSecondary; font.pixelSize: 12 }
            Item { width: 1; height: 6 }
            Row {
                anchors.right: parent.right
                spacing: 10
                Button { text: "Cancelar"; onClicked: dlgConfirmar.close() }
                Button {
                    text: dlgConfirmar.boton
                    highlighted: true
                    palette.highlight: "#ff3b30"
                    onClicked: { dlgConfirmar.close(); if (dlgConfirmar.accion) dlgConfirmar.accion() }
                }
            }
        }
    }

    // ------------------------------------------------------------ menú contextual
    function nombreCorto(ruta) {
        var n = ruta.substring(ruta.lastIndexOf("/") + 1)
        return n.length > 18 ? n.substring(0, 16) + "…" : n
    }
    function opcionesMenu() {
        var n = selectedPaths.length
        var cuantos = n > 1 ? " (" + n + ")" : ""
        var o = []
        var pap = finderBackend.enPapelera
        if (n > 0) {
            if (pap) {
                o.push({ t: "Recuperar" + cuantos, i: "↩", a: function () { finderBackend.restaurar(fileListRoot.objetivo()); fileListRoot.limpiarSeleccion() } })
                o.push({ sep: true })
                o.push({ t: "Eliminar para siempre" + cuantos + "…", i: "✕", peligro: true, k: "⌦", a: function () { fileListRoot.eliminar(true) } })
                return o
            }
            if (n === 1) {
                o.push({ t: "Abrir", i: "↗", k: "↵", a: function () { finderBackend.openItem(fileListRoot.selectedPaths[0]) } })
                if (!selectedIsDir) {
                    var ruta = selectedPaths[0]
                    o.push({ t: "Abrir con", i: "⇱", sub: function () {
                        return finderBackend.aplicacionesPara(ruta).map(function (app) {
                            return { t: app.t, a: function () { finderBackend.abrirCon(ruta, app.desktop) } }
                        })
                    } })
                }
                if (selectedIsDir) o.push({ t: "Abrir en Terminal", i: ">_", a: function () { finderBackend.openTerminal(fileListRoot.selectedPaths[0]) } })
                o.push({ sep: true })
            }
            var movibles = true
            for (var i = 0; i < n; ++i) if (!finderBackend.dentroDeCasa(selectedPaths[i]) || finderBackend.esProtegida(selectedPaths[i])) movibles = false
            if (movibles) o.push({ t: "Cortar" + cuantos, i: "✂", k: "Ctrl+X", a: fileListRoot.cortar })
            o.push({ t: "Copiar" + cuantos, i: "⧉", k: "Ctrl+C", a: fileListRoot.copiar })
            var rutas = selectedPaths.slice()
            o.push({ t: n === 1 ? "Copiar ruta" : "Copiar rutas", i: "⌗", a: function () { finderBackend.copiarRuta(rutas) } })
            if (n === 1 && selectedIsDir && finderBackend.hasClipboard)
                o.push({ t: "Pegar dentro" + (finderBackend.portapapelesCantidad > 1 ? " (" + finderBackend.portapapelesCantidad + ")" : ""), i: "📥", a: fileListRoot.pegarDentro })
            if (finderBackend.puedeEscribir)
                o.push({ t: "Duplicar" + cuantos, i: "⊕", a: function () { finderBackend.soltar(fileListRoot.objetivo(), finderBackend.currentPath, true) } })
            if (finderBackend.puedeEscribir) {
                if (n === 1 && finderBackend.esComprimido(selectedPaths[0]))
                    o.push({ t: "Extraer aquí", i: "⇲", a: function () { finderBackend.extraer(fileListRoot.selectedPaths[0]) } })
                o.push({ t: (n === 1 ? "Comprimir «" + fileListRoot.nombreCorto(selectedPaths[0]) + "»" : "Comprimir " + n + " elementos"), i: "⊞",
                         a: function () { finderBackend.comprimir(fileListRoot.objetivo()) } })
            }
            o.push({ sep: true })
            if (n === 1) {
                o.push({ t: "Cambiar nombre…", i: "✎", k: "F2", a: fileListRoot.renombrar })
                o.push({ t: "Ver propiedades", i: "ℹ", k: "Ctrl+I", a: function () { fileListRoot.openProperties(fileListRoot.selectedPath) } })
                o.push({ sep: true })
            }
            o.push({ t: "Mover a la Papelera" + cuantos, i: "🗑", k: "Supr", peligro: true, a: function () { fileListRoot.eliminar(false) } })
            return o
        }
        // Fondo vacío
        if (pap) {
            if (!finderBackend.papeleraVacia) o.push({ t: "Vaciar Papelera…", i: "🗑", peligro: true, a: fileListRoot.vaciarPapelera })
            if (finderBackend.entries.length > 0) o.push({ t: "Seleccionar todo", i: "▦", k: "Ctrl+A", a: fileListRoot.seleccionarTodo })
            return o
        }
        if (finderBackend.puedeEscribir) {
            o.push({ t: "Nueva carpeta", i: "📁", k: "Ctrl+Mayús+N", a: fileListRoot.openNewFolderDialog })
            o.push({ t: "Nuevo documento", i: "📄", sub: function () {
                return finderBackend.tiposNuevos().map(function (d) {
                    return { t: d.t, i: d.i, a: function () { fileListRoot.crearDocumento(d.tipo) } }
                })
            } })
        }
        if (finderBackend.hasClipboard && finderBackend.puedeEscribir) {
            var c = finderBackend.portapapelesCantidad
            o.push({ t: (finderBackend.portapapelesCortado ? "Mover aquí" : "Pegar") + (c > 1 ? " (" + c + ")" : ""), i: "📥", k: "Ctrl+V", a: fileListRoot.pegar })
        }
        o.push({ sep: true })
        o.push({ t: "Ver", i: "▤", sub: function () {
            return [
                { t: "Iconos", marca: finderBackend.viewMode === "grid", a: function () { finderBackend.viewMode = "grid" } },
                { t: "Lista", marca: finderBackend.viewMode === "list", a: function () { finderBackend.viewMode = "list" } },
                { sep: true },
                { t: "Archivos ocultos", k: "Ctrl+H", marca: finderBackend.showHiddenFiles,
                  a: function () { finderBackend.showHiddenFiles = !finderBackend.showHiddenFiles } }
            ]
        } })
        o.push({ t: "Ordenar por", i: "⇅", sub: function () {
            var l = [["name", "Nombre"], ["date", "Fecha de modificación"], ["size", "Tamaño"], ["kind", "Clase"]].map(function (c) {
                return { t: c[1], marca: finderBackend.sortBy === c[0], a: function () { finderBackend.sortBy = c[0] } }
            })
            l.push({ sep: true })
            l.push({ t: "Ascendente", marca: finderBackend.sortAscending, a: function () { finderBackend.sortAscending = true } })
            l.push({ t: "Descendente", marca: !finderBackend.sortAscending, a: function () { finderBackend.sortAscending = false } })
            return l
        } })
        if (finderBackend.entries.length > 0) o.push({ t: "Seleccionar todo", i: "▦", k: "Ctrl+A", a: fileListRoot.seleccionarTodo })
        o.push({ sep: true })
        o.push({ t: "Abrir en Terminal", i: ">_", k: "Ctrl+T", a: function () { finderBackend.openTerminal() } })
        o.push({ t: "Propiedades de la carpeta", i: "ℹ", a: function () { fileListRoot.openProperties(finderBackend.currentPath) } })
        return o
    }

    // ------------------------------------------------------------ menú contextual
    // Se dibuja sobre TODA la ventana (no solo sobre la lista). Se abre en el
    // puntero hacia la derecha y abajo; si no cabe, hacia el otro lado del
    // puntero, pegado a él (como Windows y macOS). Fondo opaco: se lee mejor.
    function posMenu(p, tam, total) {
        var m = 6
        var q = p + tam + m <= total ? p : p - tam
        return Math.max(m, Math.min(q, total - tam - m))
    }
    property var subOpciones: []
    property real subY: 0

    component FilaMenu: Item {
        id: fila
        required property var modelData
        property bool enSub: false
        readonly property bool activa: zona.containsMouse || (!enSub && !!modelData.sub && fileListRoot.subOpciones.length > 0 && fileListRoot.subDe === modelData.t)
        width: parent ? parent.width : 0
        height: modelData.sep ? 9 : (modelData.vacia ? 26 : 28)
        Rectangle {
            visible: !!fila.modelData.sep
            anchors.centerIn: parent
            width: parent.width - 16
            height: 1
            color: theme.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)
        }
        Rectangle {
            visible: !fila.modelData.sep
            anchors.fill: parent
            radius: 5
            color: fila.activa && !fila.modelData.vacia ? (fila.modelData.peligro ? "#e5372c" : theme.accent) : "transparent"
            readonly property color tinta: fila.activa && !fila.modelData.vacia ? "#ffffff"
                                         : fila.modelData.vacia ? theme.contentTextSecondary
                                         : (fila.modelData.peligro ? "#e5372c" : theme.contentTextPrimary)
            Text {
                id: opIcono
                x: 8
                width: 20
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: fila.modelData.marca ? "✓" : (fila.modelData.i || "")
                color: parent.tinta
                font.pixelSize: 11
            }
            Text {
                anchors.left: opIcono.right
                anchors.leftMargin: 8
                anchors.right: opAtajo.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: fila.modelData.t || ""
                color: parent.tinta
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            Text {
                id: opAtajo
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: fila.modelData.sub ? "›" : (fila.modelData.k || "")
                color: fila.activa ? "#ffffff" : theme.contentTextSecondary
                font.pixelSize: fila.modelData.sub ? 15 : 10
            }
        }
        MouseArea {
            id: zona
            anchors.fill: parent
            hoverEnabled: true
            enabled: !fila.modelData.sep && !fila.modelData.vacia
            onContainsMouseChanged: if (containsMouse && !fila.enSub) fila.abrirSub()
            onClicked: {
                if (fila.modelData.sub) { fila.abrirSub(); return }
                // La acción se guarda ANTES de cerrar: al cerrar, el modelo
                // pasa a [] y este delegado (y su modelData) desaparece.
                var accion = fila.modelData.a
                fileListRoot.ctxVisible = false
                accion()
            }
        }
        function abrirSub() {
            if (fila.modelData.sub) {
                fileListRoot.subY = fila.mapToItem(capaMenu, 0, 0).y
                fileListRoot.subDe = fila.modelData.t
                var l = fila.modelData.sub()
                fileListRoot.subOpciones = l.length > 0 ? l : [{ t: "Ninguna aplicación", vacia: true }]
            } else {
                fileListRoot.subOpciones = []
                fileListRoot.subDe = ""
            }
        }
    }
    property string subDe: ""
    onCtxVisibleChanged: if (!ctxVisible) { subOpciones = []; subDe = "" }

    Item {
        id: capaMenu
        parent: fileListRoot.Window.contentItem ? fileListRoot.Window.contentItem : fileListRoot
        anchors.fill: parent
        z: 10000
        visible: fileListRoot.ctxVisible

        // Clic fuera: cierra (y no hace nada más, como en Windows)
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: fileListRoot.ctxVisible = false
            onWheel: (w) => { w.accepted = true }
        }

        CajaMenu {
            id: menuPpal
            width: 250
            opciones: fileListRoot.ctxVisible ? fileListRoot.opcionesMenu() : []
            x: fileListRoot.posMenu(fileListRoot.ctxX, width, capaMenu.width)
            y: fileListRoot.posMenu(fileListRoot.ctxY, height, capaMenu.height)
        }
        // Submenú (Nuevo documento, Abrir con, Ver, Ordenar por): a la
        // derecha del menú, o a la izquierda si allí no cabe.
        CajaMenu {
            esSub: true
            width: 220
            opciones: fileListRoot.subOpciones
            x: menuPpal.x + menuPpal.width - 4 + width + 6 <= capaMenu.width ? menuPpal.x + menuPpal.width - 4
                                                                              : menuPpal.x - width + 4
            y: fileListRoot.posMenu(fileListRoot.subY - 6, height, capaMenu.height)
        }
    }

    component CajaMenu: Item {
        id: caja
        property bool esSub: false
        property var opciones: []
        visible: opciones.length > 0
        height: col.implicitHeight + 12
        // Sombra sencilla (sin desenfoque: no cuesta en equipos lentos)
        Rectangle { anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 1; anchors.bottomMargin: -4; radius: 10; color: Qt.rgba(0, 0, 0, theme.isDark ? 0.30 : 0.10) }
        Rectangle { anchors.fill: parent; anchors.bottomMargin: -2; radius: 9; color: Qt.rgba(0, 0, 0, theme.isDark ? 0.30 : 0.08) }
        Rectangle {
            anchors.fill: parent
            radius: 9
            color: theme.isDark ? "#2b2b2e" : "#ffffff"
            border.color: theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.14)
        }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // pulsar el borde no cierra
        Column {
            id: col
            x: 6
            y: 6
            width: parent.width - 12
            Repeater {
                model: caja.opciones
                delegate: FilaMenu { enSub: caja.esSub }
            }
        }
    }

    // ------------------------------------------------------------ aviso
    Rectangle {
        id: avisoCaja
        z: 90
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: finderBackend.aviso !== "" && (avisoTimer.running || finderBackend.ocupado) ? 14 : -50
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        width: avisoFila.implicitWidth + 30
        height: 32
        radius: 16
        color: theme.isDark ? "#2c2c2e" : "#1d1d1f"
        Row {
            id: avisoFila
            anchors.centerIn: parent
            spacing: 8
            BusyIndicator { width: 18; height: 18; running: finderBackend.ocupado; visible: running; anchors.verticalCenter: parent.verticalCenter }
            Text { anchors.verticalCenter: parent.verticalCenter; text: finderBackend.aviso; color: "#ffffff"; font.pixelSize: 12 }
        }
        Timer { id: avisoTimer; interval: 3800; onTriggered: if (!finderBackend.ocupado) finderBackend.cerrarAviso() }
    }

    // Grupo: el número de elementos sobre el montón
    Rectangle {
        z: 80
        visible: fileListRoot.agrupando
        x: fileListRoot.pX + 14
        y: fileListRoot.pY - 30
        width: Math.max(26, grupoTexto.implicitWidth + 14)
        height: 26
        radius: 13
        color: "#ff3b30"
        Text { id: grupoTexto; anchors.centerIn: parent; text: fileListRoot.selectedPaths.length; color: "#ffffff"; font.pixelSize: 13; font.bold: true }
    }

    // ------------------------------------------------------------ Papelera: barra superior
    Rectangle {
        id: barraPapelera
        visible: finderBackend.enPapelera
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? 44 : 0
        color: theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.035)
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.contentCardBorder }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: barraBotones.left
            anchors.verticalCenter: parent.verticalCenter
            text: finderBackend.papeleraVacia ? "La Papelera está vacía"
                  : fileListRoot.nSel > 0 ? "Seleccionados: " + fileListRoot.nSel + ". Puedes recuperarlos o eliminarlos para siempre."
                  : "Selecciona elementos para recuperarlos o eliminarlos uno a uno, o vacía la Papelera."
            color: theme.contentTextSecondary
            font.pixelSize: 12
            elide: Text.ElideRight
        }
        Row {
            id: barraBotones
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Button {
                visible: fileListRoot.nSel > 0
                text: "Recuperar"
                onClicked: { finderBackend.restaurar(fileListRoot.objetivo()); fileListRoot.limpiarSeleccion() }
            }
            Button {
                visible: fileListRoot.nSel > 0
                text: "Eliminar para siempre"
                onClicked: fileListRoot.eliminar(true)
            }
            Button {
                text: "Vaciar Papelera"
                enabled: !finderBackend.papeleraVacia
                highlighted: true
                palette.highlight: "#ff3b30"
                onClicked: fileListRoot.vaciarPapelera()
            }
        }
    }

    // ------------------------------------------------------------ elementos
    // Lo común a la cuadrícula y a la lista: estado, agrupar y soltar encima.
    component Elemento: Item {
        id: el
        property var entrada: ({})
        readonly property string itemPath: entrada && entrada.path ? entrada.path : ""
        readonly property bool seleccionado: fileListRoot.selectedPaths.indexOf(itemPath) !== -1
        readonly property bool resaltado: soltarAqui.containsDrag
        property real dx: 0
        property real dy: 0
        default property alias contenido: cuerpo.data

        // Agrupar: los seleccionados se juntan donde está el ratón
        Connections {
            target: fileListRoot
            function onAgrupandoChanged() {
                if (fileListRoot.agrupando && el.seleccionado) {
                    var c = el.mapToItem(fileListRoot, el.width / 2, el.height / 2)
                    el.dx = finderBackend.viewMode === "list" ? 0 : fileListRoot.pX - c.x
                    el.dy = fileListRoot.pY - c.y
                } else {
                    el.dx = 0
                    el.dy = 0
                }
            }
        }
        z: dx !== 0 || dy !== 0 ? 10 : 0
        transform: Translate {
            x: el.dx * 0.92
            y: el.dy * 0.92
            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
        opacity: fileListRoot.arrastrando && seleccionado ? 0.45 : 1

        Item { id: cuerpo; anchors.fill: parent }

        MouseArea {
            id: zona
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            pressAndHoldInterval: 380
            cursorShape: fileListRoot.agrupando ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            onPressed: (mouse) => fileListRoot.alPresionar(mouse, el.entrada, zona)
            onPositionChanged: (mouse) => fileListRoot.alMover(mouse, zona)
            onPressAndHold: fileListRoot.alMantener()
            onReleased: (mouse) => fileListRoot.alSoltarRaton(mouse, el.entrada)
            onCanceled: { fileListRoot.pActivo = false; fileListRoot.agrupando = false }
            onDoubleClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton && !finderBackend.enPapelera) finderBackend.openItem(el.itemPath)
            }
        }
        readonly property bool encima: zona.containsMouse

        // Soltar sobre una carpeta: dentro de ella
        DropArea {
            id: soltarAqui
            anchors.fill: parent
            enabled: el.entrada.isDir === true && !finderBackend.enPapelera
            keys: ["text/uri-list"]
            onEntered: (drag) => { if (fileListRoot.arrastrando && el.seleccionado) drag.accepted = false }
            onDropped: (drop) => {
                if (!drop.hasUrls) return
                finderBackend.soltar(drop.urls.map(u => u.toString()), el.itemPath, drop.proposedAction === Qt.CopyAction)
                drop.accept(Qt.CopyAction)
            }
        }
    }

    Item {
        id: zonaVistas
        anchors.top: barraPapelera.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        // Vacío
        Column {
            anchors.centerIn: parent
            spacing: 12
            visible: finderBackend.entries.length === 0
            Image {
                source: finderBackend.enPapelera ? "qrc:/icons/trash.png" : "qrc:/icons/folder.png"
                width: 72; height: 72
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0.35
                smooth: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: finderBackend.searchQuery.length > 0 ? "No se encontraron resultados"
                      : finderBackend.enPapelera ? "La Papelera está vacía" : "Esta carpeta está vacía"
                color: theme.contentTextSecondary
                font.pixelSize: 14
            }
        }

        // ---------------------------------------------------- CUADRÍCULA
        Item {
            anchors.fill: parent
            anchors.margins: 16
            visible: finderBackend.viewMode === "grid"

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: (mouse) => fileListRoot.fondoPresionado(mouse, gridView)
                onPositionChanged: (mouse) => fileListRoot.fondoMovido(mouse, gridView)
                onReleased: fileListRoot.fondoSoltado()
                onCanceled: fileListRoot.fondoSoltado()
            }

            GridView {
                id: gridView
                anchors.fill: parent
                cellWidth: 104
                cellHeight: 116
                clip: true
                interactive: false
                boundsBehavior: Flickable.StopAtBounds
                model: finderBackend.entries
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        var max = Math.max(0, gridView.contentHeight - gridView.height)
                        gridView.contentY = Math.max(0, Math.min(max, gridView.contentY - event.angleDelta.y))
                    }
                }

                Rectangle {
                    parent: gridView.contentItem
                    z: 100
                    visible: fileListRoot.rbActivo && fileListRoot.rbVista === gridView
                    x: Math.min(fileListRoot.rbX0, fileListRoot.rbX1)
                    y: Math.min(fileListRoot.rbY0, fileListRoot.rbY1)
                    width: Math.abs(fileListRoot.rbX1 - fileListRoot.rbX0)
                    height: Math.abs(fileListRoot.rbY1 - fileListRoot.rbY0)
                    color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18)
                    border.color: theme.accent
                    radius: 3
                }

                delegate: Elemento {
                    id: gEl
                    required property var modelData
                    entrada: modelData
                    width: gridView.cellWidth
                    height: gridView.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 8
                        color: gEl.resaltado ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.35)
                             : gEl.seleccionado ? theme.accent
                             : gEl.encima ? theme.itemHover : "transparent"
                        border.color: gEl.resaltado ? theme.accent : "transparent"
                        border.width: 2
                        scale: fileListRoot.agrupando && gEl.seleccionado && gEl.itemPath !== fileListRoot.pPath ? 0.82 : 1
                        Behavior on scale { NumberAnimation { duration: 200 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            width: parent.width - 8
                            Image {
                                source: theme.tinte(modelData.icon)
                                sourceSize: Qt.size(64, 64)
                                width: 58; height: 58
                                anchors.horizontalCenter: parent.horizontalCenter
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                opacity: finderBackend.portapapelesCortado && finderBackend.clipboardPath === modelData.path ? 0.5 : 1
                            }
                            Text {
                                text: modelData.name
                                color: gEl.seleccionado ? "#ffffff" : theme.contentTextPrimary
                                font.pixelSize: 11
                                font.weight: gEl.seleccionado ? Font.DemiBold : Font.Normal
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideMiddle
                                maximumLineCount: 2
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                    }
                }
            }
        }

        // ---------------------------------------------------- LISTA
        Column {
            anchors.fill: parent
            visible: finderBackend.viewMode === "list"

            Rectangle {
                width: parent.width
                height: 28
                color: theme.isDark ? Qt.rgba(1, 1, 1, 0.04) : "#f5f5f7"
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.contentCardBorder }
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    Repeater {
                        model: [
                            { t: "Nombre", c: "name", w: -1 },
                            { t: "Fecha de modificación", c: "date", w: 150 },
                            { t: "Tamaño", c: "size", w: 100 },
                            { t: "Clase", c: "kind", w: 130 }
                        ]
                        Item {
                            required property var modelData
                            width: modelData.w > 0 ? modelData.w : parent.width - 380
                            height: parent.height
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.t + (finderBackend.sortBy === modelData.c ? (finderBackend.sortAscending ? "  ▲" : "  ▼") : "")
                                color: finderBackend.sortBy === modelData.c ? theme.accent : theme.contentTextSecondary
                                font.pixelSize: 11
                                font.bold: true
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: finderBackend.sort(modelData.c) }
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: parent.height - 28

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: (mouse) => fileListRoot.fondoPresionado(mouse, listView)
                    onPositionChanged: (mouse) => fileListRoot.fondoMovido(mouse, listView)
                    onReleased: fileListRoot.fondoSoltado()
                    onCanceled: fileListRoot.fondoSoltado()
                }

                ListView {
                    id: listView
                    anchors.fill: parent
                    clip: true
                    interactive: false
                    boundsBehavior: Flickable.StopAtBounds
                    model: finderBackend.entries
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (event) => {
                            var max = Math.max(0, listView.contentHeight - listView.height)
                            listView.contentY = Math.max(0, Math.min(max, listView.contentY - event.angleDelta.y))
                        }
                    }

                    Rectangle {
                        parent: listView.contentItem
                        z: 100
                        visible: fileListRoot.rbActivo && fileListRoot.rbVista === listView
                        x: Math.min(fileListRoot.rbX0, fileListRoot.rbX1)
                        y: Math.min(fileListRoot.rbY0, fileListRoot.rbY1)
                        width: Math.abs(fileListRoot.rbX1 - fileListRoot.rbX0)
                        height: Math.abs(fileListRoot.rbY1 - fileListRoot.rbY0)
                        color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18)
                        border.color: theme.accent
                        radius: 3
                    }

                    delegate: Elemento {
                        id: lEl
                        required property var modelData
                        required property int index
                        entrada: modelData
                        width: listView.width
                        height: 30

                        Rectangle {
                            anchors.fill: parent
                            color: lEl.resaltado ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.35)
                                 : lEl.seleccionado ? theme.accent
                                 : lEl.encima ? theme.itemHover
                                 : index % 2 === 0 ? "transparent" : (theme.isDark ? Qt.rgba(1, 1, 1, 0.02) : Qt.rgba(0, 0, 0, 0.02))
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                Row {
                                    width: parent.width - 380
                                    height: parent.height
                                    spacing: 8
                                    Image {
                                        source: theme.tinte(modelData.icon)
                                        sourceSize: Qt.size(24, 24)
                                        width: 18; height: 18
                                        anchors.verticalCenter: parent.verticalCenter
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        opacity: finderBackend.portapapelesCortado && finderBackend.clipboardPath === modelData.path ? 0.5 : 1
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.name
                                        color: lEl.seleccionado ? "#ffffff" : theme.contentTextPrimary
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                        width: parent.width - 30
                                    }
                                }
                                Text { width: 150; anchors.verticalCenter: parent.verticalCenter; text: modelData.modified; color: lEl.seleccionado ? "#ffffff" : theme.contentTextSecondary; font.pixelSize: 11 }
                                Text { width: 100; anchors.verticalCenter: parent.verticalCenter; text: modelData.size; color: lEl.seleccionado ? "#ffffff" : theme.contentTextSecondary; font.pixelSize: 11 }
                                Text { width: 130; anchors.verticalCenter: parent.verticalCenter; text: modelData.type; color: lEl.seleccionado ? "#ffffff" : theme.contentTextSecondary; font.pixelSize: 11; elide: Text.ElideRight }
                            }
                        }
                    }
                }
            }
        }
    }
}
