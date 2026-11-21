import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: desktopIconsRoot
    anchors.fill: parent
    focus: true

    TitanTheme { id: titanTheme }

    // Parámetros de la rejilla simétrica estilo macOS
    readonly property real cellWidth: 96
    readonly property real cellHeight: 102
    readonly property real gridTop: 36
    readonly property real gridRight: 16
    readonly property int maxRows: Math.max(1, Math.floor((height - gridTop - 74) / cellHeight))

    // Estado de selección múltiple (Recuadro azul / Rubberband)
    property var selectedPaths: []
    property bool rubberBandActive: false
    property real rbStartX: 0
    property real rbStartY: 0
    property real rbCurrentX: 0
    property real rbCurrentY: 0

    // Estado del menú contextual
    property string ctxPath: ""
    property real ctxX: 0
    property real ctxY: 0
    property bool ctxVisible: false

    // Atajos de teclado para selección múltiple
    Keys.onPressed: (event) => {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) {
            if (selectedPaths.length > 0) {
                desktopBackend.copyItems(selectedPaths)
            }
            event.accepted = true
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
            desktopBackend.pasteItems(-1, -1)
            event.accepted = true
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            if (selectedPaths.length > 0) {
                desktopBackend.deleteItems(selectedPaths)
                selectedPaths = []
            }
            event.accepted = true
        }
    }

    // Área de recepción de archivos arrastrados hacia el escritorio
    DropArea {
        id: desktopDropArea
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: (drop) => {
            if (drop.hasUrls) {
                var isMoveAction = (drop.action === Qt.MoveAction || drop.proposedAction === Qt.MoveAction || drop.proposedAction === undefined)
                for (var i = 0; i < drop.urls.length; ++i) {
                    var snapped = desktopIconsRoot.snapToGrid(drop.x + (i * 14), drop.y + (i * 14), "")
                    desktopBackend.importFile(drop.urls[i], snapped.x, snapped.y, isMoveAction)
                }
                drop.acceptProposedAction()
            }
        }
    }

    // Fondo del escritorio: maneja la creación del recuadro azul y la deselección al hacer clic
    MouseArea {
        id: bgMouseArea
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: false

        onPressed: (mouse) => {
            desktopIconsRoot.forceActiveFocus()
            desktopIconsRoot.ctxVisible = false

            // "si da click izquierdo a cualquier lugar, incluyendo los miembros desaparece y se limpia"
            desktopIconsRoot.selectedPaths = []

            if (mouse.button === Qt.LeftButton) {
                desktopIconsRoot.rbStartX = mouse.x
                desktopIconsRoot.rbStartY = mouse.y
                desktopIconsRoot.rbCurrentX = mouse.x
                desktopIconsRoot.rbCurrentY = mouse.y
                desktopIconsRoot.rubberBandActive = false
            }
        }

        onPositionChanged: (mouse) => {
            if (pressed && (mouse.buttons & Qt.LeftButton)) {
                if (!desktopIconsRoot.rubberBandActive) {
                    if (Math.abs(mouse.x - desktopIconsRoot.rbStartX) > 4 || Math.abs(mouse.y - desktopIconsRoot.rbStartY) > 4) {
                        desktopIconsRoot.rubberBandActive = true
                    }
                }
                if (desktopIconsRoot.rubberBandActive) {
                    desktopIconsRoot.rbCurrentX = mouse.x
                    desktopIconsRoot.rbCurrentY = mouse.y
                    desktopIconsRoot.updateSelectionFromRubberBand()
                }
            }
        }

        onReleased: (mouse) => {
            desktopIconsRoot.rubberBandActive = false
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                desktopIconsRoot.ctxPath = ""
                desktopIconsRoot.ctxX = mouse.x
                desktopIconsRoot.ctxY = mouse.y
                desktopIconsRoot.ctxVisible = true
            }
        }
    }

    // Recuadro azul de selección múltiple (Rubberband selector)
    Rectangle {
        id: rubberBand
        visible: desktopIconsRoot.rubberBandActive
        x: Math.min(desktopIconsRoot.rbStartX, desktopIconsRoot.rbCurrentX)
        y: Math.min(desktopIconsRoot.rbStartY, desktopIconsRoot.rbCurrentY)
        width: Math.abs(desktopIconsRoot.rbCurrentX - desktopIconsRoot.rbStartX)
        height: Math.abs(desktopIconsRoot.rbCurrentY - desktopIconsRoot.rbStartY)
        color: Qt.rgba(0.0, 0.48, 1.0, 0.22)
        border.color: Qt.rgba(0.1, 0.55, 1.0, 0.88)
        border.width: 1.5
        radius: 3
        z: 25
    }

    // Calcula intersección con el recuadro azul para seleccionar carpetas y archivos
    function updateSelectionFromRubberBand() {
        var rx = Math.min(rbStartX, rbCurrentX)
        var ry = Math.min(rbStartY, rbCurrentY)
        var rw = Math.abs(rbCurrentX - rbStartX)
        var rh = Math.abs(rbCurrentY - rbStartY)

        var newSelected = []
        for (var i = 0; i < iconRepeater.count; ++i) {
            var it = iconRepeater.itemAt(i)
            if (!it || !it.itemPath) continue

            var ix = it.x
            var iy = it.y
            var iw = it.width
            var ih = it.height

            // Colisión por AABB (caja delimitadora)
            if (rx < ix + iw && rx + rw > ix && ry < iy + ih && ry + rh > iy) {
                newSelected.push(it.itemPath)
            }
        }
        selectedPaths = newSelected
    }

    // Función para obtener la posición por defecto simétrica en columnas desde la derecha
    function defaultPositionForIndex(idx) {
        var w = (desktopIconsRoot.width > 200) ? desktopIconsRoot.width : Screen.width
        var col = Math.floor(idx / maxRows)
        var row = idx % maxRows
        var posX = w - gridRight - 90 - (col * cellWidth)
        var posY = gridTop + (row * cellHeight)
        return { x: posX, y: posY }
    }

    // Función para calcular la celda de la rejilla más cercana y evitar colisiones
    function snapToGrid(reqX, reqY, currentItemPath) {
        var w = (desktopIconsRoot.width > 200) ? desktopIconsRoot.width : Screen.width
        var rawCol = Math.round((w - gridRight - 90 - reqX) / cellWidth)
        var rawRow = Math.round((reqY - gridTop) / cellHeight)
        var col = Math.max(0, rawCol)
        var row = Math.max(0, Math.min(maxRows - 1, rawRow))

        var occupied = true
        var attempts = 0
        while (occupied && attempts < 50) {
            occupied = false
            for (var i = 0; i < iconRepeater.count; ++i) {
                var it = iconRepeater.itemAt(i)
                if (it && it.itemPath && it.itemPath !== currentItemPath && desktopIconsRoot.selectedPaths.indexOf(it.itemPath) === -1) {
                    var itCol = Math.round((w - gridRight - 90 - it.x) / cellWidth)
                    var itRow = Math.round((it.y - gridTop) / cellHeight)
                    if (itCol === col && itRow === row) {
                        occupied = true
                        row++
                        if (row >= maxRows) {
                            row = 0
                            col++
                        }
                        break
                    }
                }
            }
            attempts++
        }

        var snapX = w - gridRight - 90 - (col * cellWidth)
        var snapY = gridTop + (row * cellHeight)
        return { x: snapX, y: snapY, col: col, row: row }
    }

    Repeater {
        id: iconRepeater
        // Ajustes > Escritorio y Dock > Mostrar iconos en el escritorio
        model: { prefs.version; return prefs.b("Escritorio/iconos") ? desktopBackend.items : [] }

        delegate: Item {
            id: iconWrapper

            readonly property string itemPath: modelData.path
            readonly property bool isSelected: desktopIconsRoot.selectedPaths.indexOf(itemPath) !== -1
            readonly property bool hasSaved: (modelData.hasSavedPos === true && modelData.savedX !== undefined && modelData.savedX >= 0)
            // Casilla guardada (columna desde la derecha, fila). Si en esta
            // pantalla caben menos filas, sigue en la columna siguiente.
            readonly property int filaReal: modelData.gridRow !== undefined ? modelData.gridRow : index
            readonly property int colReal: (modelData.gridCol !== undefined ? modelData.gridCol : 0)
                                           + Math.floor(filaReal / desktopIconsRoot.maxRows)
            readonly property real targetX: {
                if (hasSaved) return modelData.savedX;
                var w = (desktopIconsRoot.width > 200) ? desktopIconsRoot.width : Screen.width;
                return w - desktopIconsRoot.gridRight - 90 - (colReal * desktopIconsRoot.cellWidth);
            }
            readonly property real targetY: {
                if (hasSaved) return modelData.savedY;
                return desktopIconsRoot.gridTop + ((filaReal % desktopIconsRoot.maxRows) * desktopIconsRoot.cellHeight);
            }

            x: targetX
            y: targetY

            onTargetXChanged: {
                if (!iconMouse.drag.active) x = targetX
            }
            onTargetYChanged: {
                if (!iconMouse.drag.active) y = targetY
            }

            width: 90
            height: 92
            z: iconMouse.drag.active ? 20 : (isSelected ? 5 : 1)

            Behavior on x {
                enabled: !iconMouse.drag.active
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                enabled: !iconMouse.drag.active
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            property bool isHovered: iconMouse.containsMouse

            // Resaltado de selección / hover
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: iconWrapper.isSelected ? Qt.rgba(0.0, 0.48, 1.0, 0.32) : (iconWrapper.isHovered ? Qt.rgba(1, 1, 1, 0.16) : "transparent")
                border.color: iconWrapper.isSelected ? Qt.rgba(0.1, 0.55, 1.0, 0.9) : (iconWrapper.isHovered ? Qt.rgba(1, 1, 1, 0.25) : "transparent")
                border.width: iconWrapper.isSelected ? 1.5 : 1
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 6
                spacing: 4
                width: parent.width

                // Icono de la aplicación / archivo con sombreado sutil
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 54
                    height: 54
                    scale: iconWrapper.isHovered ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -1
                        radius: modelData.isApp ? 14 : 6
                        color: Qt.rgba(0, 0, 0, 0.22)
                        visible: modelData.isApp
                        z: -1
                    }

                    Image {
                        id: appIconImage
                        anchors.fill: parent
                        source: titanTheme.tinte(modelData.icon ? modelData.icon : (modelData.isApp ? "qrc:/icons/apps-folder.png" : "qrc:/icons/file-generic.png"))
                        sourceSize: Qt.size(128, 128)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        cache: true

                        onStatusChanged: {
                            if (status === Image.Error && source !== "qrc:/icons/apps-folder.png" && source !== "qrc:/icons/file-generic.png") {
                                source = modelData.isApp ? "qrc:/icons/apps-folder.png" : "qrc:/icons/file-generic.png";
                            }
                        }
                    }
                }

                // Etiqueta con fondo redondeado
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(84, labelText.implicitWidth + 10)
                    height: Math.min(32, labelText.implicitHeight + 4)
                    radius: 4
                    color: iconWrapper.isSelected ? Qt.rgba(0, 0.44, 0.89, 0.95) : (iconWrapper.isHovered ? Qt.rgba(0, 0.44, 0.89, 0.88) : Qt.rgba(0, 0, 0, 0.44))
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        id: labelText
                        anchors.centerIn: parent
                        text: modelData.name ? modelData.name : ""
                        color: "#ffffff"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        elide: Text.ElideMiddle
                        maximumLineCount: 2
                        wrapMode: Text.WrapAnywhere
                        horizontalAlignment: Text.AlignHCenter
                        width: 80
                    }
                }
            }

            MouseArea {
                id: iconMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: iconMouse.drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                drag.target: iconWrapper
                drag.axis: Drag.XAndYAxis
                drag.minimumX: 8
                drag.maximumX: Math.max(8, desktopIconsRoot.width - iconWrapper.width - 8)
                drag.minimumY: desktopIconsRoot.gridTop
                drag.maximumY: Math.max(desktopIconsRoot.gridTop, desktopIconsRoot.height - iconWrapper.height - 70)

                property real pressStartX: 0
                property real pressStartY: 0
                property bool wasDragged: false
                property var initialGroupPositions: ({})

                onPressed: (mouse) => {
                    desktopIconsRoot.forceActiveFocus()
                    pressStartX = iconWrapper.x
                    pressStartY = iconWrapper.y
                    wasDragged = false

                    if (mouse.button === Qt.LeftButton) {
                        // Si este elemento no está seleccionado, seleccionarlo
                        if (desktopIconsRoot.selectedPaths.indexOf(modelData.path) === -1) {
                            desktopIconsRoot.selectedPaths = [modelData.path]
                        }

                        // Guardar posiciones iniciales del grupo para moverlos juntos si se arrastra
                        var map = {}
                        for (var p = 0; p < desktopIconsRoot.selectedPaths.length; ++p) {
                            var pth = desktopIconsRoot.selectedPaths[p]
                            for (var k = 0; k < iconRepeater.count; ++k) {
                                var itm = iconRepeater.itemAt(k)
                                if (itm && itm.itemPath === pth) {
                                    map[pth] = { x: itm.x, y: itm.y }
                                }
                            }
                        }
                        initialGroupPositions = map
                    }
                }

                onPositionChanged: (mouse) => {
                    if (pressed && (mouse.buttons & Qt.LeftButton)) {
                        if (Math.abs(iconWrapper.x - pressStartX) > 4 || Math.abs(iconWrapper.y - pressStartY) > 4) {
                            wasDragged = true
                            var dx = iconWrapper.x - pressStartX
                            var dy = iconWrapper.y - pressStartY

                            // Mover todo el grupo seleccionado arrastrando
                            if (desktopIconsRoot.selectedPaths.length > 1) {
                                for (var p = 0; p < desktopIconsRoot.selectedPaths.length; ++p) {
                                    var pth = desktopIconsRoot.selectedPaths[p]
                                    if (pth === modelData.path) continue
                                    var orig = initialGroupPositions[pth]
                                    if (orig) {
                                        for (var k = 0; k < iconRepeater.count; ++k) {
                                            var itm = iconRepeater.itemAt(k)
                                            if (itm && itm.itemPath === pth) {
                                                itm.x = orig.x + dx
                                                itm.y = orig.y + dy
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                onReleased: (mouse) => {
                    if (wasDragged) {
                        // Reubicar cada elemento seleccionado en la rejilla
                        for (var p = 0; p < desktopIconsRoot.selectedPaths.length; ++p) {
                            var pth = desktopIconsRoot.selectedPaths[p]
                            for (var k = 0; k < iconRepeater.count; ++k) {
                                var itm = iconRepeater.itemAt(k)
                                if (itm && itm.itemPath === pth) {
                                    var snapped = desktopIconsRoot.snapToGrid(itm.x, itm.y, pth)
                                    desktopBackend.moveItemToSlot(pth, snapped.col, snapped.row)
                                    itm.x = snapped.x
                                    itm.y = snapped.y
                                }
                            }
                        }
                    }
                }

                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        // "si da click izquierdo a cualquier lugar, incluyendo los miembros desaparece y se limpia"
                        if (!wasDragged) {
                            desktopIconsRoot.selectedPaths = []
                            desktopIconsRoot.ctxVisible = false
                        }
                    } else if (mouse.button === Qt.RightButton) {
                        // "disponible si da click derecho en cualquier miembro del grupo"
                        if (desktopIconsRoot.selectedPaths.indexOf(modelData.path) === -1) {
                            desktopIconsRoot.selectedPaths = [modelData.path]
                        }
                        desktopIconsRoot.ctxPath = modelData.path
                        var pt = iconWrapper.mapToItem(desktopIconsRoot, mouse.x, mouse.y)
                        desktopIconsRoot.ctxX = pt.x
                        desktopIconsRoot.ctxY = pt.y
                        desktopIconsRoot.ctxVisible = true
                    }
                }

                onDoubleClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        var enDock = modelData.isApp
                            && dockModel.setAppLaunching(modelData.exec ? modelData.exec : modelData.name, modelData.exec, modelData.name, modelData.icon)
                        desktopBackend.openItem(modelData.path, enDock)
                        desktopIconsRoot.selectedPaths = []
                    }
                }
            }
        }
    }

    // ── Menú Contextual Liquid Glass (Orden estricto: Copiar, Mover, Eliminar) ──────────────────────────────────────────
    Rectangle {
        id: contextMenu
        visible: desktopIconsRoot.ctxVisible
        // Como en Windows: se abre hacia la derecha y abajo del puntero; si no
        // cabe, hacia el otro lado (con su tamaño real), y nunca se sale.
        // ctxX/ctxY siguen siendo el punto del clic (ahí va "Nueva carpeta").
        x: {
            var m = 8, w = width, W = desktopIconsRoot.width
            var px = desktopIconsRoot.ctxX + w + m <= W ? desktopIconsRoot.ctxX : desktopIconsRoot.ctxX - w
            return Math.max(m, Math.min(px, W - w - m))
        }
        y: {
            var m = 8, h = height, H = desktopIconsRoot.height
            var py = desktopIconsRoot.ctxY + h + m <= H ? desktopIconsRoot.ctxY : desktopIconsRoot.ctxY - h
            return Math.max(m, Math.min(py, H - h - m))
        }
        width: 232
        height: ctxCol.implicitHeight + 16
        radius: 13
        z: 35

        opacity: visible ? 1.0 : 0.0
        scale: visible ? 1.0 : 0.92
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

        // Fondo opaco (como los menús de Windows y macOS): se lee mejor que el vidrio
        color: titanTheme.isDark ? "#161618" : "#ffffff"
        border.color: titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.14)
        border.width: 1

        Column {
            id: ctxCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 2

            // Opción "Abrir" (si es un único elemento)
            Rectangle {
                width: parent.width
                height: 32
                radius: 6
                visible: desktopIconsRoot.selectedPaths.length <= 1 && desktopIconsRoot.ctxPath.length > 0
                color: openMouse.containsMouse ? titanTheme.itemHover : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    spacing: 8
                    Text { text: "↗"; color: titanTheme.contentTextPrimary; font.pixelSize: 13 }
                    Text { text: "Abrir"; color: titanTheme.contentTextPrimary; font.pixelSize: 13 }
                }

                MouseArea {
                    id: openMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        desktopIconsRoot.ctxVisible = false
                        desktopBackend.openItem(desktopIconsRoot.ctxPath)
                        desktopIconsRoot.selectedPaths = []
                    }
                }
            }

            // Separador si "Abrir" está visible
            Rectangle {
                width: parent.width - 16
                height: 1
                anchors.horizontalCenter: parent.horizontalCenter
                color: titanTheme.glassBorder
                opacity: 0.6
                visible: desktopIconsRoot.selectedPaths.length <= 1 && desktopIconsRoot.ctxPath.length > 0
            }

            // 1. COPIAR (Orden estricto solicitado: copiar-mover-eliminar)
            Rectangle {
                width: parent.width
                height: 32
                radius: 6
                visible: desktopIconsRoot.selectedPaths.length > 0
                color: copyMouse.containsMouse ? titanTheme.itemHover : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    spacing: 8
                    Text { text: "📋"; color: titanTheme.contentTextPrimary; font.pixelSize: 13 }
                    Text {
                        text: desktopIconsRoot.selectedPaths.length > 1 ? ("Copiar (" + desktopIconsRoot.selectedPaths.length + ")") : "Copiar"
                        color: titanTheme.contentTextPrimary
                        font.pixelSize: 13
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    text: "⌘C"
                    color: titanTheme.contentTextSecondary
                    font.pixelSize: 11
                }

                MouseArea {
                    id: copyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        desktopIconsRoot.ctxVisible = false
                        desktopBackend.copyItems(desktopIconsRoot.selectedPaths)
                    }
                }
            }

            // 2. MOVER (Orden estricto solicitado: copiar-mover-eliminar)
            Rectangle {
                width: parent.width
                height: 32
                radius: 6
                visible: desktopIconsRoot.selectedPaths.length > 0
                color: moveMouse.containsMouse ? titanTheme.itemHover : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    spacing: 8
                    Text { text: "📦"; color: titanTheme.contentTextPrimary; font.pixelSize: 13 }
                    Text {
                        text: desktopIconsRoot.selectedPaths.length > 1 ? ("Mover (" + desktopIconsRoot.selectedPaths.length + ")") : "Mover a..."
                        color: titanTheme.contentTextPrimary
                        font.pixelSize: 13
                    }
                }

                MouseArea {
                    id: moveMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        desktopIconsRoot.ctxVisible = false
                        desktopBackend.moveItems(desktopIconsRoot.selectedPaths, "")
                        desktopIconsRoot.selectedPaths = []
                    }
                }
            }

            // 3. QUITAR DEL ESCRITORIO (a la Papelera, recuperable)
            Rectangle {
                width: parent.width
                height: 32
                radius: 6
                visible: desktopIconsRoot.selectedPaths.length > 0
                color: deleteMouse.containsMouse ? Qt.rgba(0.9, 0.12, 0.12, 0.18) : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    spacing: 8
                    Text { text: "🗑"; color: deleteMouse.containsMouse ? "#ff4444" : titanTheme.contentTextPrimary; font.pixelSize: 13 }
                    Text {
                        text: desktopIconsRoot.selectedPaths.length > 1 ? ("Quitar del escritorio (" + desktopIconsRoot.selectedPaths.length + ")") : "Quitar del escritorio"
                        color: deleteMouse.containsMouse ? "#ff4444" : titanTheme.contentTextPrimary
                        font.pixelSize: 13
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    text: "⌫"
                    color: deleteMouse.containsMouse ? "#ff4444" : titanTheme.contentTextSecondary
                    font.pixelSize: 11
                }

                MouseArea {
                    id: deleteMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        desktopIconsRoot.ctxVisible = false
                        desktopBackend.deleteItems(desktopIconsRoot.selectedPaths)
                        desktopIconsRoot.selectedPaths = []
                    }
                }
            }

            // Opción "Pegar" (cuando se da clic derecho en el fondo del escritorio)
            Rectangle {
                width: parent.width
                height: 32
                radius: 6
                visible: desktopIconsRoot.selectedPaths.length === 0 && desktopBackend.hasClipboard()
                color: pasteMouse.containsMouse ? titanTheme.itemHover : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    spacing: 8
                    Text { text: "📥"; color: titanTheme.contentTextPrimary; font.pixelSize: 13 }
                    Text { text: "Pegar"; color: titanTheme.contentTextPrimary; font.pixelSize: 13 }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    text: "⌘V"
                    color: titanTheme.contentTextSecondary
                    font.pixelSize: 11
                }

                MouseArea {
                    id: pasteMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        desktopIconsRoot.ctxVisible = false
                        var snapped = desktopIconsRoot.snapToGrid(desktopIconsRoot.ctxX, desktopIconsRoot.ctxY, "")
                        desktopBackend.pasteItems(snapped.x, snapped.y)
                    }
                }
            }

            // Opción "Abrir en Finder"
            Rectangle {
                width: parent.width
                height: 32
                radius: 6
                visible: desktopIconsRoot.selectedPaths.length === 0
                color: finderMouse.containsMouse ? titanTheme.itemHover : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    spacing: 8
                    Text { text: "📂"; color: titanTheme.contentTextPrimary; font.pixelSize: 13 }
                    Text { text: "Abrir en Finder"; color: titanTheme.contentTextPrimary; font.pixelSize: 13 }
                }

                MouseArea {
                    id: finderMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        desktopIconsRoot.ctxVisible = false
                        desktopBackend.openInFinder()
                    }
                }
            }
        }
    }
}
