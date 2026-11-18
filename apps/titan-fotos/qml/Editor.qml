import QtQuick
import QtQuick.Controls

// Editor: ajustes de luz y color, filtros, recortar, girar y voltear.
// La vista previa la calcula el mismo código que guarda (Edicion.h).
Item {
    id: editor

    required property var theme
    property var foto: ({})
    signal terminado()

    property string pestana: "ajustes"
    property int rot: 0
    property bool fh: false
    property bool fv: false
    property real brillo: 0
    property real contraste: 0
    property real saturacion: 0
    property real calidez: 0
    property string filtro: "ninguno"
    property real cx: 0
    property real cy: 0
    property real cw: 1
    property real ch: 1
    property real proporcion: 0     // 0 libre, -1 original, si no ancho/alto
    property int version: 0

    readonly property bool hayCambios: rot !== 0 || fh || fv || brillo !== 0 || contraste !== 0 || saturacion !== 0
                                       || calidez !== 0 || filtro !== "ninguno" || cx > 0.0005 || cy > 0.0005 || cw < 0.9995 || ch < 0.9995
    function params(conRecorte, otroFiltro) {
        var f = otroFiltro !== undefined ? otroFiltro : filtro
        var p = [rot, fh ? 1 : 0, fv ? 1 : 0, brillo.toFixed(3), contraste.toFixed(3), saturacion.toFixed(3), calidez.toFixed(3), f]
        return p.concat(conRecorte ? [cx.toFixed(4), cy.toFixed(4), cw.toFixed(4), ch.toFixed(4)] : [0, 0, 1, 1]).join(";")
    }
    function empezar(f) {
        foto = f
        rot = 0; fh = false; fv = false
        brillo = 0; contraste = 0; saturacion = 0; calidez = 0
        filtro = "ninguno"
        restablecerRecorte()
        proporcion = 0
        pestana = "ajustes"
        fotosBackend.empezarEdicion(f.path)
        version++
        vistaParams = params(false)
    }
    function restablecerRecorte() { cx = 0; cy = 0; cw = 1; ch = 1 }
    function guardar(copia) {
        var r = fotosBackend.guardarEdicion(foto.path, params(true), copia)
        if (r !== "") terminado()
    }
    function girar(d) {
        rot = (rot + d + 360) % 360
        restablecerRecorte()
        if (proporcion !== 0) aplicarProporcion(proporcion)
    }

    // La vista previa se pide un instante después del último cambio
    property string vistaParams: ""
    Timer { id: retardo; interval: 40; onTriggered: editor.vistaParams = editor.params(false) }
    onRotChanged: retardo.restart()
    onFhChanged: retardo.restart()
    onFvChanged: retardo.restart()
    onBrilloChanged: retardo.restart()
    onContrasteChanged: retardo.restart()
    onSaturacionChanged: retardo.restart()
    onCalidezChanged: retardo.restart()
    onFiltroChanged: retardo.restart()

    // Proporción en píxeles -> recuadro centrado lo más grande posible
    function aplicarProporcion(p) {
        proporcion = p
        if (p === 0) return
        var W = previa.paintedWidth, H = previa.paintedHeight
        if (W <= 0 || H <= 0) return
        var r = p < 0 ? W / H : p
        var w = 1, h = W / (H * r)
        if (h > 1) { h = 1; w = H * r / W }
        cw = w; ch = h; cx = (1 - w) / 2; cy = (1 - h) / 2
    }

    Rectangle { anchors.fill: parent; color: editor.theme.isDark ? "#141416" : "#ececee" }

    // ---------------------------------------------------------------- vista previa
    Item {
        id: lienzo
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: panel.left
        anchors.margins: 28

        Image {
            id: previa
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            retainWhileLoading: true
            sourceSize.width: Math.round(width * Screen.devicePixelRatio)
            sourceSize.height: Math.round(height * Screen.devicePixelRatio)
            source: editor.vistaParams !== "" ? "image://edicion/" + editor.vistaParams + "#" + editor.version : ""
            smooth: true

            // Mantener pulsado: ver la original
            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                visible: verOriginal.pressed
                source: editor.vistaParams !== "" ? "image://edicion/" + [editor.rot, editor.fh ? 1 : 0, editor.fv ? 1 : 0, 0, 0, 0, 0, "ninguno", 0, 0, 1, 1].join(";") + "#" + editor.version : ""
                sourceSize: previa.sourceSize
                asynchronous: true
                cache: false
            }
        }

        // Recuadro de recorte sobre la parte pintada de la imagen
        Item {
            id: marco
            visible: editor.pestana === "recortar"
            x: (previa.width - previa.paintedWidth) / 2
            y: (previa.height - previa.paintedHeight) / 2
            width: previa.paintedWidth
            height: previa.paintedHeight
            readonly property real rx: editor.cx * width
            readonly property real ry: editor.cy * height
            readonly property real rw: editor.cw * width
            readonly property real rh: editor.ch * height

            // Oscurecer lo que queda fuera
            Rectangle { x: 0; y: 0; width: parent.width; height: marco.ry; color: Qt.rgba(0, 0, 0, 0.55) }
            Rectangle { x: 0; y: marco.ry + marco.rh; width: parent.width; height: parent.height - y; color: Qt.rgba(0, 0, 0, 0.55) }
            Rectangle { x: 0; y: marco.ry; width: marco.rx; height: marco.rh; color: Qt.rgba(0, 0, 0, 0.55) }
            Rectangle { x: marco.rx + marco.rw; y: marco.ry; width: parent.width - x; height: marco.rh; color: Qt.rgba(0, 0, 0, 0.55) }

            Rectangle {
                x: marco.rx; y: marco.ry; width: marco.rw; height: marco.rh
                color: "transparent"
                border.color: "#ffffff"
                border.width: 1.5
                // Tercios
                Repeater {
                    model: 2
                    Rectangle { required property int index; x: parent.width * (index + 1) / 3; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.35) }
                }
                Repeater {
                    model: 2
                    Rectangle { required property int index; y: parent.height * (index + 1) / 3; height: 1; width: parent.width; color: Qt.rgba(1, 1, 1, 0.35) }
                }
                // Esquinas
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        width: 18; height: 18
                        color: "transparent"
                        x: (index % 2 === 0) ? -3 : parent.width - 15
                        y: (index < 2) ? -3 : parent.height - 15
                        Rectangle { width: parent.width; height: 4; y: index < 2 ? 0 : parent.height - 4; color: "#ffffff" }
                        Rectangle { width: 4; height: parent.height; x: index % 2 === 0 ? 0 : parent.width - 4; color: "#ffffff" }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -12
                hoverEnabled: true
                property string modo: ""
                property real px: 0
                property real py: 0
                property var inicio: ({})
                function cerca(a, b) { return Math.abs(a - b) < 16 }
                function modoEn(x, y) {
                    x -= 12; y -= 12
                    var l = cerca(x, marco.rx), r = cerca(x, marco.rx + marco.rw)
                    var t = cerca(y, marco.ry), b = cerca(y, marco.ry + marco.rh)
                    var dentroX = x > marco.rx - 16 && x < marco.rx + marco.rw + 16
                    var dentroY = y > marco.ry - 16 && y < marco.ry + marco.rh + 16
                    if ((l || r) && (t || b)) return (t ? "t" : "b") + (l ? "l" : "r")
                    if (l && dentroY) return "l"
                    if (r && dentroY) return "r"
                    if (t && dentroX) return "t"
                    if (b && dentroX) return "b"
                    if (x > marco.rx && x < marco.rx + marco.rw && y > marco.ry && y < marco.ry + marco.rh) return "mover"
                    return ""
                }
                cursorShape: {
                    var m = pressed ? modo : modoEn(mouseX, mouseY)
                    if (m === "mover") return pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    if (m === "tl" || m === "br") return Qt.SizeFDiagCursor
                    if (m === "tr" || m === "bl") return Qt.SizeBDiagCursor
                    if (m === "l" || m === "r") return Qt.SizeHorCursor
                    if (m === "t" || m === "b") return Qt.SizeVerCursor
                    return Qt.ArrowCursor
                }
                onPressed: (e) => {
                    modo = modoEn(e.x, e.y)
                    px = e.x; py = e.y
                    inicio = { x: editor.cx, y: editor.cy, w: editor.cw, h: editor.ch }
                }
                onReleased: modo = ""
                onPositionChanged: (e) => {
                    if (!pressed || modo === "") return
                    var dx = (e.x - px) / marco.width, dy = (e.y - py) / marco.height
                    var i = inicio, minW = 24 / marco.width, minH = 24 / marco.height
                    if (modo === "mover") {
                        editor.cx = Math.max(0, Math.min(1 - i.w, i.x + dx))
                        editor.cy = Math.max(0, Math.min(1 - i.h, i.y + dy))
                        return
                    }
                    var x1 = i.x, y1 = i.y, x2 = i.x + i.w, y2 = i.y + i.h
                    if (modo.indexOf("l") >= 0) x1 = Math.max(0, Math.min(x2 - minW, i.x + dx))
                    if (modo.indexOf("r") >= 0) x2 = Math.min(1, Math.max(x1 + minW, i.x + i.w + dx))
                    if (modo.indexOf("t") >= 0) y1 = Math.max(0, Math.min(y2 - minH, i.y + dy))
                    if (modo.indexOf("b") >= 0) y2 = Math.min(1, Math.max(y1 + minH, i.y + i.h + dy))
                    if (editor.proporcion !== 0) {
                        // Con proporción fija manda el ancho (o el alto en los bordes t/b)
                        var r = editor.proporcion < 0 ? marco.width / marco.height : editor.proporcion
                        var k = marco.width / (marco.height * r)
                        if (modo === "t" || modo === "b") {
                            var w = (y2 - y1) / k
                            x2 = Math.min(1, x1 + w)
                            if (x2 - x1 < w) { w = x2 - x1; if (modo === "t") y1 = y2 - w * k; else y2 = y1 + w * k }
                        } else {
                            var h = (x2 - x1) * k
                            if (modo.indexOf("t") >= 0) y1 = y2 - h; else y2 = y1 + h
                            if (y1 < 0 || y2 > 1) {
                                h = modo.indexOf("t") >= 0 ? y2 : 1 - y1
                                if (modo.indexOf("t") >= 0) y1 = 0; else y2 = 1
                                var w2 = h / k
                                if (modo.indexOf("l") >= 0) x1 = x2 - w2; else x2 = x1 + w2
                            }
                        }
                    }
                    editor.cx = x1; editor.cy = y1; editor.cw = x2 - x1; editor.ch = y2 - y1
                }
            }
        }
    }

    // ---------------------------------------------------------------- panel
    Rectangle {
        id: panel
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 286
        color: editor.theme.contentBackground
        Rectangle { width: 1; height: parent.height; color: editor.theme.contentCardBorder }

        // Pestañas
        Row {
            id: pestanas
            x: 16; y: 16
            width: parent.width - 32
            Repeater {
                model: [["ajustes", "Ajustes"], ["filtros", "Filtros"], ["recortar", "Recortar"]]
                Rectangle {
                    required property var modelData
                    readonly property bool sel: editor.pestana === modelData[0]
                    width: pestanas.width / 3
                    height: 30
                    radius: 8
                    color: sel ? editor.theme.accent : (pz.containsMouse ? editor.theme.itemHover : "transparent")
                    Text { anchors.centerIn: parent; text: modelData[1]; color: parent.sel ? "#ffffff" : editor.theme.contentTextPrimary; font.pixelSize: 12; font.weight: Font.DemiBold }
                    MouseArea { id: pz; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: editor.pestana = parent.modelData[0] }
                }
            }
        }

        Flickable {
            anchors.top: pestanas.bottom
            anchors.topMargin: 16
            anchors.bottom: pie.top
            anchors.left: parent.left
            anchors.right: parent.right
            contentHeight: contenido.height + 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: contenido
                x: 16
                width: parent.width - 32
                spacing: 16

                // --- Ajustes
                Repeater {
                    model: editor.pestana === "ajustes" ? [["brillo", "☀", "Brillo"], ["contraste", "◐", "Contraste"], ["saturacion", "◉", "Saturación"], ["calidez", "🌡", "Calidez"]] : []
                    Column {
                        required property var modelData
                        width: contenido.width
                        spacing: 4
                        Item {
                            width: parent.width
                            height: 18
                            Text { text: modelData[1] + "  " + modelData[2]; color: editor.theme.contentTextPrimary; font.pixelSize: 12; font.weight: Font.DemiBold }
                            Text {
                                anchors.right: parent.right
                                text: Math.round(editor[modelData[0]] * 100)
                                color: editor[modelData[0]] !== 0 ? editor.theme.accent : editor.theme.contentTextSecondary
                                font.pixelSize: 12
                                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: editor[modelData[0]] = 0 }
                            }
                        }
                        Slider {
                            width: parent.width
                            from: -1; to: 1
                            value: editor[modelData[0]]
                            onMoved: editor[modelData[0]] = Math.abs(value) < 0.03 ? 0 : value
                        }
                    }
                }

                // --- Filtros
                Grid {
                    visible: editor.pestana === "filtros"
                    columns: 2
                    spacing: 10
                    Repeater {
                        model: editor.pestana === "filtros" ? [["ninguno", "Original"], ["vivo", "Vivo"], ["dramatico", "Dramático"], ["bn", "Blanco y negro"],
                                                               ["sepia", "Sepia"], ["nostalgia", "Nostalgia"], ["calido", "Cálido"], ["frio", "Frío"]] : []
                        Column {
                            required property var modelData
                            readonly property bool sel: editor.filtro === modelData[0]
                            spacing: 4
                            Rectangle {
                                width: (contenido.width - 10) / 2
                                height: width * 0.72
                                radius: 8
                                color: "transparent"
                                border.width: parent.sel ? 2.5 : 0
                                border.color: editor.theme.accent
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: parent.parent.sel ? 3 : 0
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: false
                                    sourceSize.width: 260
                                    sourceSize.height: 260
                                    source: "image://edicion/" + editor.params(false, modelData[0]) + "#" + editor.version
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: editor.filtro = parent.parent.modelData[0] }
                            }
                            Text {
                                width: (contenido.width - 10) / 2
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData[1]
                                color: parent.sel ? editor.theme.accent : editor.theme.contentTextPrimary
                                font.pixelSize: 11
                                font.weight: parent.sel ? Font.DemiBold : Font.Normal
                            }
                        }
                    }
                }

                // --- Recortar y girar
                Column {
                    visible: editor.pestana === "recortar"
                    width: parent.width
                    spacing: 10
                    Text { text: "Girar y voltear"; color: editor.theme.contentTextSecondary; font.pixelSize: 11; font.weight: Font.DemiBold }
                    Row {
                        spacing: 8
                        Repeater {
                            model: [["⟲", "Girar a la izquierda", -90], ["⟳", "Girar a la derecha", 90], ["⇋", "Voltear horizontal", "h"], ["⇵", "Voltear vertical", "v"]]
                            Rectangle {
                                required property var modelData
                                width: 56; height: 40; radius: 9
                                color: gz.containsMouse ? editor.theme.itemHover : (editor.theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05))
                                Text { anchors.centerIn: parent; text: modelData[0]; color: editor.theme.contentTextPrimary; font.pixelSize: 19 }
                                MouseArea {
                                    id: gz
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var a = parent.modelData[2]
                                        // Voltear sigue lo que se ve aunque esté girada
                                        if (a === "h") { if (editor.rot % 180 === 0) editor.fh = !editor.fh; else editor.fv = !editor.fv; editor.restablecerRecorte(); if (editor.proporcion !== 0) editor.aplicarProporcion(editor.proporcion) }
                                        else if (a === "v") { if (editor.rot % 180 === 0) editor.fv = !editor.fv; else editor.fh = !editor.fh; editor.restablecerRecorte(); if (editor.proporcion !== 0) editor.aplicarProporcion(editor.proporcion) }
                                        else editor.girar(a)
                                    }
                                }
                                ToolTip.visible: gz.containsMouse
                                ToolTip.delay: 500
                                ToolTip.text: modelData[1]
                            }
                        }
                    }
                    Text { text: "Proporción"; color: editor.theme.contentTextSecondary; font.pixelSize: 11; font.weight: Font.DemiBold; topPadding: 6 }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: [["Libre", 0], ["Original", -1], ["Cuadrado", 1], ["4:3", 4 / 3], ["3:2", 3 / 2], ["16:9", 16 / 9], ["3:4", 3 / 4], ["9:16", 9 / 16]]
                            Rectangle {
                                required property var modelData
                                readonly property bool sel: Math.abs(editor.proporcion - modelData[1]) < 0.001
                                width: pt.implicitWidth + 20; height: 28; radius: 14
                                color: sel ? editor.theme.accent : (prz.containsMouse ? editor.theme.itemHover : (editor.theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)))
                                Text { id: pt; anchors.centerIn: parent; text: modelData[0]; color: parent.sel ? "#ffffff" : editor.theme.contentTextPrimary; font.pixelSize: 12 }
                                MouseArea { id: prz; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: editor.aplicarProporcion(parent.modelData[1]) }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        topPadding: 4
                        text: "Arrastra las esquinas o los bordes del recuadro; arrástralo por dentro para moverlo."
                        color: editor.theme.contentTextSecondary
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        // Pie: ver original, restablecer, cancelar y guardar
        Column {
            id: pie
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            x: 16
            width: parent.width - 32
            spacing: 10
            Row {
                spacing: 14
                Text {
                    text: "Mantén para ver la original"
                    color: editor.theme.accent
                    font.pixelSize: 11
                    MouseArea { id: verOriginal; anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor }
                }
                Text {
                    text: "Restablecer"
                    color: editor.hayCambios ? editor.theme.accent : editor.theme.contentTextSecondary
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        enabled: editor.hayCambios
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { editor.empezar(editor.foto) }
                    }
                }
            }
            Row {
                spacing: 8
                Button { text: "Cancelar"; onClicked: editor.terminado() }
                Button {
                    text: editor.foto.editable ? "Guardar" : "Guardar copia"
                    highlighted: true
                    enabled: editor.hayCambios
                    onClicked: editor.guardar(!editor.foto.editable)
                }
                Button {
                    visible: editor.foto.editable === true
                    text: "Copia"
                    enabled: editor.hayCambios
                    onClicked: editor.guardar(true)
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "Guardar como una foto nueva y dejar la original como está"
                }
            }
        }
    }

    Shortcut { sequence: "Escape"; enabled: editor.visible; onActivated: editor.terminado() }
    Shortcut { sequence: "Ctrl+S"; enabled: editor.visible && editor.hayCambios; onActivated: editor.guardar(!editor.foto.editable) }
}
