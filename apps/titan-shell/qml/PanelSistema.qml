// Paneles del sistema que se abren con una tecla, como en Windows:
//   seguridad    Ctrl+Alt+Supr: bloquear, cambiar de usuario, cerrar sesión,
//                Monitor de recursos, apagar...
//   portapapeles Win+V: lo último que se ha copiado (solo en memoria)
//   emojis       Win+. : buscar emojis en español y escribirlos
//   atajos       Win+F1: los atajos de teclado de Inti
// Esc o un clic fuera lo cierran. Al elegir algo se cierra primero (el
// teclado vuelve a la ventana de antes) y luego se pega/escribe en ella.
import QtQuick
import QtQuick.Controls

Item {
    id: raiz
    anchors.fill: parent

    TitanTheme { id: tema }

    readonly property string panel: shellBackend.panel
    readonly property color tarjeta: tema.isDark ? Qt.rgba(0.11, 0.115, 0.13, 0.97) : Qt.rgba(0.985, 0.985, 0.99, 0.98)
    readonly property color borde: tema.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color texto: tema.isDark ? "#f2f2f5" : "#1d1d1f"
    readonly property color tenue: tema.isDark ? "#a2aab8" : "#6e6e73"
    readonly property color campo: tema.isDark ? "#1c1c1f" : "#f0f0f3"

    function cerrar() { shellBackend.panel = "" }

    // Al abrir: el teclado al panel que toca
    onPanelChanged: {
        confirmarSalida = false
        if (panel === "emojis") { buscarEmoji.text = ""; grupoEmoji = -1; emojiSel = 0; buscarEmoji.forceActiveFocus() }
        else if (panel === "portapapeles") { clipSel = 0; listaClip.forceActiveFocus() }
        else if (panel !== "") teclas.forceActiveFocus()
    }

    // Fondo: oscuro en Ctrl+Alt+Supr (pantalla de seguridad), suave en el resto
    Rectangle {
        anchors.fill: parent
        color: raiz.panel === "seguridad" ? Qt.rgba(0.02, 0.03, 0.06, 0.82) : Qt.rgba(0, 0, 0, raiz.panel === "atajos" ? 0.35 : 0.12)
        Behavior on color { ColorAnimation { duration: 140 } }
        MouseArea { anchors.fill: parent; onClicked: raiz.cerrar() }
    }

    Item {
        id: teclas
        focus: true
        Keys.onEscapePressed: raiz.cerrar()
    }

    component Boton: Rectangle {
        id: b
        property string texto: ""
        property bool principal: false
        property bool peligro: false
        signal pulsado()
        implicitWidth: tb.implicitWidth + 28
        height: 32
        radius: 8
        color: principal ? (zb.containsMouse ? Qt.darker(tema.accent, 1.1) : tema.accent)
                         : zb.containsMouse ? tema.itemHover : raiz.campo
        Text {
            id: tb
            anchors.centerIn: parent
            text: b.texto
            color: b.principal ? "#ffffff" : b.peligro ? "#ff453a" : raiz.texto
            font.pixelSize: 13
            font.weight: b.principal ? Font.DemiBold : Font.Normal
        }
        MouseArea { id: zb; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.pulsado() }
    }

    // =================================================== Ctrl+Alt+Supr
    property bool confirmarSalida: false
    Timer { id: salidaTimer; interval: 4000; onTriggered: raiz.confirmarSalida = false }

    Item {
        anchors.fill: parent
        visible: raiz.panel === "seguridad"

        component Opcion: Text {
            id: op
            signal pulsado()
            color: zo.containsMouse || activeFocus ? "#ffffff" : Qt.rgba(1, 1, 1, 0.78)
            font.pixelSize: 22
            font.weight: zo.containsMouse || activeFocus ? Font.DemiBold : Font.Normal
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.bottom; anchors.topMargin: 2
                height: 2; radius: 1; color: tema.accent
                visible: zo.containsMouse || op.activeFocus
            }
            Keys.onReturnPressed: op.pulsado()
            Keys.onEnterPressed: op.pulsado()
            Keys.onEscapePressed: raiz.cerrar()
            MouseArea { id: zo; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: op.pulsado() }
        }

        Column {
            anchors.centerIn: parent
            spacing: 26
            Opcion {
                id: opBloquear
                text: "Bloquear"
                KeyNavigation.down: opUsuario.visible ? opUsuario : opMonitor
                onPulsado: { raiz.cerrar(); shellBackend.lockScreen() }
            }
            Opcion {
                id: opUsuario
                visible: shellBackend.canSwitchUser && !shellBackend.isLiveSystem
                text: "Cambiar de usuario"
                KeyNavigation.down: opSalir
                onPulsado: { raiz.cerrar(); shellBackend.cambiarUsuarioSinCerrar() }
            }
            Opcion {
                id: opSalir
                visible: shellBackend.canSwitchUser && !shellBackend.isLiveSystem
                text: raiz.confirmarSalida ? "Cerrar sesión · se cerrarán tus apps, pulsa otra vez" : "Cerrar sesión"
                KeyNavigation.down: opMonitor
                onPulsado: {
                    if (raiz.confirmarSalida) { raiz.cerrar(); shellBackend.switchUser() }
                    else { raiz.confirmarSalida = true; salidaTimer.restart() }
                }
            }
            Opcion {
                id: opMonitor
                text: "Monitor de recursos"
                KeyNavigation.down: opBloquear
                onPulsado: { raiz.cerrar(); shellBackend.abrirApp("titan-monitor") }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 60
            width: 140; height: 38; radius: 19
            color: zc.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12)
            Text { anchors.centerIn: parent; text: "Cancelar"; color: "#ffffff"; font.pixelSize: 15 }
            MouseArea { id: zc; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: raiz.cerrar() }
        }

        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 40
            spacing: 14
            Repeater {
                model: [
                    { i: "reposo", t: "Reposo" },
                    { i: "reiniciar", t: "Reiniciar" },
                    { i: "apagar", t: "Apagar" }
                ]
                delegate: Column {
                    required property var modelData
                    spacing: 6
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 46; height: 46; radius: 23
                        color: zp.containsMouse ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.12)
                        Image { anchors.centerIn: parent; width: 20; height: 20; sourceSize: Qt.size(40, 40); source: "qrc:/icons/simbolos/" + modelData.i + ".svg" }
                        MouseArea {
                            id: zp
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                raiz.cerrar()
                                if (modelData.i === "reposo") shellBackend.suspend()
                                else if (modelData.i === "reiniciar") shellBackend.reboot()
                                else shellBackend.powerOff()
                            }
                        }
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.t; color: Qt.rgba(1, 1, 1, 0.8); font.pixelSize: 11 }
                }
            }
        }
    }

    // =================================================== Win+V: portapapeles
    property int clipSel: 0

    Rectangle {
        id: tarjetaClip
        visible: raiz.panel === "portapapeles"
        width: 400
        height: portapapeles.activo ? Math.min(500, parent.height - 120) : 250
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 90
        radius: 16
        color: raiz.tarjeta
        border.color: raiz.borde
        MouseArea { anchors.fill: parent }   // que el clic dentro no cierre

        Text {
            x: 18; y: 16
            text: "Portapapeles"
            color: raiz.texto
            font.pixelSize: 16
            font.bold: true
        }
        Text {
            visible: portapapeles.activo && portapapeles.elementos.length > 0
            anchors.right: parent.right
            anchors.rightMargin: 18
            y: 18
            text: "Borrar todo"
            color: tema.accent
            font.pixelSize: 12
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: portapapeles.borrarTodo() }
        }

        // Apagado: se explica y se ofrece activarlo
        Column {
            visible: !portapapeles.activo
            anchors.centerIn: parent
            width: parent.width - 60
            spacing: 14
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: "Guarda lo último que copias para pegarlo después"
                color: raiz.texto
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: "Solo se guarda en este equipo y en memoria: se borra al cerrar la sesión. Las contraseñas de los gestores de contraseñas no se guardan."
                color: raiz.tenue
                font.pixelSize: 12
            }
            Boton {
                anchors.horizontalCenter: parent.horizontalCenter
                texto: "Activar"
                principal: true
                onPulsado: portapapeles.activo = true
            }
        }

        Text {
            visible: portapapeles.activo && portapapeles.elementos.length === 0
            anchors.centerIn: parent
            width: parent.width - 60
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "Aún no has copiado nada.\nLo que copies con Ctrl+C aparecerá aquí."
            color: raiz.tenue
            font.pixelSize: 13
        }

        ListView {
            id: listaClip
            visible: portapapeles.activo
            anchors.fill: parent
            anchors.topMargin: 50
            anchors.bottomMargin: 40
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            clip: true
            spacing: 6
            model: portapapeles.elementos
            currentIndex: raiz.clipSel
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Keys.onEscapePressed: raiz.cerrar()
            Keys.onUpPressed: raiz.clipSel = Math.max(0, raiz.clipSel - 1)
            Keys.onDownPressed: raiz.clipSel = Math.min(portapapeles.elementos.length - 1, raiz.clipSel + 1)
            Keys.onReturnPressed: raiz.pegarClip(raiz.clipSel)
            Keys.onEnterPressed: raiz.pegarClip(raiz.clipSel)
            Keys.onDeletePressed: portapapeles.quitar(raiz.clipSel)

            delegate: Rectangle {
                required property string modelData
                required property int index
                width: listaClip.width
                height: Math.min(84, tc.implicitHeight + 22)
                radius: 10
                color: index === raiz.clipSel ? Qt.rgba(tema.accent.r, tema.accent.g, tema.accent.b, tema.isDark ? 0.30 : 0.16)
                     : zcl.containsMouse ? tema.itemHover : raiz.campo
                border.color: index === raiz.clipSel ? tema.accent : "transparent"
                Text {
                    id: tc
                    x: 12; y: 11
                    width: parent.width - 48
                    text: modelData
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    color: raiz.texto
                    font.pixelSize: 12
                }
                MouseArea {
                    id: zcl
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: raiz.clipSel = index
                    onClicked: raiz.pegarClip(index)
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    visible: zcl.containsMouse || zq.containsMouse
                    text: "✕"
                    color: raiz.tenue
                    font.pixelSize: 13
                    MouseArea { id: zq; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: portapapeles.quitar(index) }
                }
            }
        }

        Text {
            visible: portapapeles.activo
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 14
            text: "Se borra al cerrar la sesión"
            color: raiz.tenue
            font.pixelSize: 11
        }
        Text {
            visible: portapapeles.activo
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 14
            text: "Desactivar"
            color: raiz.tenue
            font.pixelSize: 11
            font.underline: zdes.containsMouse
            MouseArea { id: zdes; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: portapapeles.activo = false }
        }
    }

    function pegarClip(i) {
        if (i < 0 || i >= portapapeles.elementos.length) return
        cerrar()
        portapapeles.pegar(i)
    }

    // =================================================== Win+. : emojis
    property var todosEmojis: []
    property int grupoEmoji: -1        // -1 = todos (o resultados de la búsqueda)
    property int emojiSel: 0
    property var recientes: []
    readonly property var grupos: [
        { g: 0, i: "😀", t: "Caras" }, { g: 1, i: "👋", t: "Personas" }, { g: 3, i: "🐶", t: "Animales y naturaleza" },
        { g: 4, i: "🍎", t: "Comida" }, { g: 5, i: "✈️", t: "Viajes y lugares" }, { g: 6, i: "⚽", t: "Actividades" },
        { g: 7, i: "💡", t: "Objetos" }, { g: 8, i: "❤️", t: "Símbolos" }, { g: 9, i: "🏳️", t: "Banderas" }
    ]
    readonly property var emojisVista: {
        var l = todosEmojis, q = buscarEmoji.text.trim().toLowerCase(), r = []
        if (q !== "") {
            // Primero los que empiezan por lo buscado ("corazón rojo"), luego
            // los que lo llevan en el nombre y al final por palabra clave
            var sq = raiz.sinAcentos(q)
            var a = [], b = [], c = []
            for (var i = 0; i < l.length; ++i) {
                var nombre = raiz.sinAcentos(l[i][1].toLowerCase())
                var pos = nombre.indexOf(sq)
                if (pos === 0) a.push(l[i])
                else if (pos !== -1) b.push(l[i])
                else if (raiz.sinAcentos(l[i][2]).indexOf(sq) !== -1) c.push(l[i])
            }
            a.sort(function (x, y) { return x[1].length - y[1].length })
            return a.concat(b, c).slice(0, 240)
        }
        if (grupoEmoji < 0) {
            r = recientes.slice()
            for (var k = 0; k < l.length; ++k) if (l[k][3] === 0) r.push(l[k])
            return r
        }
        for (var j = 0; j < l.length; ++j) if (l[j][3] === grupoEmoji) r.push(l[j])
        return r
    }

    function sinAcentos(t) { return t.normalize("NFD").replace(/[\u0300-\u036f]/g, "") }

    function escribirEmoji(e) {
        if (!e) return
        var r = [e].concat(recientes.filter(function (x) { return x[0] !== e[0] }))
        recientes = r.slice(0, 16)
        cerrar()
        portapapeles.escribir(e[0])
    }

    Rectangle {
        id: tarjetaEmoji
        visible: raiz.panel === "emojis"
        width: 420
        height: 440
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 90
        radius: 16
        color: raiz.tarjeta
        border.color: raiz.borde
        onVisibleChanged: if (visible && raiz.todosEmojis.length === 0) raiz.todosEmojis = shellBackend.emojis()
        MouseArea { anchors.fill: parent }

        Rectangle {
            id: cajaEmoji
            x: 14; y: 14
            width: parent.width - 28
            height: 34
            radius: 9
            color: raiz.campo
            border.color: buscarEmoji.activeFocus ? tema.accent : "transparent"
            TextField {
                id: buscarEmoji
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                placeholderText: "Buscar un emoji (corazón, risa, gato...)"
                placeholderTextColor: raiz.tenue
                color: raiz.texto
                font.pixelSize: 13
                background: null
                onTextChanged: raiz.emojiSel = 0
                Keys.onEscapePressed: raiz.cerrar()
                Keys.onReturnPressed: raiz.escribirEmoji(raiz.emojisVista[raiz.emojiSel])
                Keys.onEnterPressed: raiz.escribirEmoji(raiz.emojisVista[raiz.emojiSel])
                Keys.onRightPressed: (e) => { if (cursorPosition === text.length) raiz.emojiSel = Math.min(raiz.emojisVista.length - 1, raiz.emojiSel + 1); else e.accepted = false }
                Keys.onLeftPressed: (e) => { if (cursorPosition === text.length && raiz.emojiSel > 0) raiz.emojiSel -= 1; else e.accepted = false }
                Keys.onDownPressed: raiz.emojiSel = Math.min(raiz.emojisVista.length - 1, raiz.emojiSel + rejilla.columnas)
                Keys.onUpPressed: raiz.emojiSel = Math.max(0, raiz.emojiSel - rejilla.columnas)
            }
        }

        // Grupos
        Row {
            id: filaGrupos
            x: 10
            anchors.top: cajaEmoji.bottom
            anchors.topMargin: 8
            spacing: 2
            visible: buscarEmoji.text === ""
            height: visible ? 32 : 0
            Repeater {
                model: raiz.grupos
                delegate: Rectangle {
                    required property var modelData
                    width: 42; height: 32; radius: 8
                    color: raiz.grupoEmoji === modelData.g ? Qt.rgba(tema.accent.r, tema.accent.g, tema.accent.b, 0.22)
                         : zg.containsMouse ? tema.itemHover : "transparent"
                    Text { anchors.centerIn: parent; text: modelData.i; font.pixelSize: 18 }
                    MouseArea {
                        id: zg
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { raiz.grupoEmoji = modelData.g; raiz.emojiSel = 0; buscarEmoji.forceActiveFocus() }
                    }
                    ToolTip.visible: zg.containsMouse
                    ToolTip.delay: 400
                    ToolTip.text: modelData.t
                }
            }
        }

        GridView {
            id: rejilla
            readonly property int columnas: Math.max(1, Math.floor(width / cellWidth))
            anchors.top: filaGrupos.bottom
            anchors.topMargin: 6
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: nombreEmoji.top
            anchors.leftMargin: 10
            anchors.rightMargin: 6
            clip: true
            cellWidth: 44
            cellHeight: 44
            boundsBehavior: Flickable.StopAtBounds
            model: raiz.emojisVista
            currentIndex: raiz.emojiSel
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: 40; height: 40; radius: 8
                color: index === raiz.emojiSel ? Qt.rgba(tema.accent.r, tema.accent.g, tema.accent.b, 0.25)
                     : ze.containsMouse ? tema.itemHover : "transparent"
                Text { anchors.centerIn: parent; text: modelData[0]; font.pixelSize: 24 }
                MouseArea {
                    id: ze
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: raiz.emojiSel = index
                    onClicked: raiz.escribirEmoji(modelData)
                }
            }
        }

        Text {
            visible: raiz.emojisVista.length === 0 && raiz.todosEmojis.length > 0
            anchors.centerIn: rejilla
            text: "No hay emojis con «" + buscarEmoji.text + "»"
            color: raiz.tenue
            font.pixelSize: 13
        }

        Text {
            id: nombreEmoji
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 14
            height: 18
            elide: Text.ElideRight
            text: {
                var e = raiz.emojisVista[raiz.emojiSel]
                return e ? e[1] : ""
            }
            color: raiz.tenue
            font.pixelSize: 12
        }
    }

    // =================================================== Win+F1: atajos
    readonly property var atajos: [
        { g: "Lo básico", l: [
            ["Win", "Abrir el menú de inicio"],
            ["Win + E", "Explorador de archivos"],
            ["Win + D", "Ver el escritorio"],
            ["Win + L", "Bloquear el equipo"],
            ["Win + I", "Ajustes"],
            ["Ctrl + Alt + Supr", "Bloquear, cambiar de usuario, apagar..."],
            ["Ctrl + Mayús + Esc", "Monitor de recursos"]
        ] },
        { g: "Ventanas", l: [
            ["Alt + Tab", "Cambiar de ventana"],
            ["Win + Q  o  Alt + F4", "Cerrar la ventana"],
            ["Win + M", "Minimizar"],
            ["Win + F", "Maximizar / restaurar"],
            ["Win + Mayús + F", "Pantalla completa"],
            ["Win + ← / →", "Ventana a media pantalla"]
        ] },
        { g: "Escribir", l: [
            ["Ctrl + C / X / V", "Copiar, cortar y pegar"],
            ["Win + V", "Historial del portapapeles"],
            ["Win + .", "Emojis"],
            ["Ctrl + Z", "Deshacer"]
        ] },
        { g: "Capturas", l: [
            ["Impr Pant", "Captura de toda la pantalla"],
            ["Win + Mayús + S", "Captura de una zona"],
            ["Win + Mayús + 5", "Grabar la pantalla (otra vez para parar)"]
        ] },
        { g: "Escritorios", l: [
            ["Win + ↑", "Ver todos los escritorios"],
            ["Win + 1 … 8", "Ir al escritorio 1 … 8"],
            ["Ctrl + Win + ← / →", "Escritorio anterior / siguiente"]
        ] },
        { g: "Más", l: [
            ["Win + T", "Terminal"],
            ["Win + W", "Cambiar el fondo de pantalla"],
            ["Win + Mayús + D", "Modo claro / oscuro"],
            ["Win + Alt + S", "Leer en voz alta (lector de pantalla)"],
            ["Win + F1", "Esta lista"]
        ] }
    ]

    Rectangle {
        id: tarjetaAtajos
        visible: raiz.panel === "atajos"
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 860)
        height: Math.min(parent.height - 80, columnasAtajos.implicitHeight + 120)
        radius: 18
        color: raiz.tarjeta
        border.color: raiz.borde
        MouseArea { anchors.fill: parent }

        Text {
            x: 26; y: 22
            text: "Atajos de teclado"
            color: raiz.texto
            font.pixelSize: 20
            font.bold: true
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 24
            y: 26
            text: "Win es la tecla con el logotipo de Windows (o Super)"
            color: raiz.tenue
            font.pixelSize: 12
        }

        Flickable {
            anchors.fill: parent
            anchors.topMargin: 62
            anchors.bottomMargin: 58
            anchors.leftMargin: 26
            anchors.rightMargin: 26
            clip: true
            contentHeight: columnasAtajos.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Grid {
                id: columnasAtajos
                width: parent.width
                columns: 2
                columnSpacing: 36
                rowSpacing: 18
                Repeater {
                    model: raiz.atajos
                    delegate: Column {
                        required property var modelData
                        width: (columnasAtajos.width - columnasAtajos.columnSpacing) / 2
                        spacing: 5
                        Text { text: modelData.g; color: tema.accent; font.pixelSize: 13; font.bold: true; bottomPadding: 2 }
                        Repeater {
                            model: modelData.l
                            delegate: Item {
                                required property var modelData
                                width: parent.width
                                height: 24
                                Rectangle {
                                    id: tecla
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: tt.implicitWidth + 14
                                    height: 21
                                    radius: 5
                                    color: raiz.campo
                                    border.color: raiz.borde
                                    Text { id: tt; anchors.centerIn: parent; text: modelData[0]; color: raiz.texto; font.pixelSize: 11; font.weight: Font.DemiBold }
                                }
                                Text {
                                    anchors.left: tecla.right
                                    anchors.leftMargin: 10
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData[1]
                                    elide: Text.ElideRight
                                    color: raiz.texto
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            spacing: 8
            Boton { texto: "Abrir el manual"; onPulsado: { raiz.cerrar(); shellBackend.abrirApp("titan-manual") } }
            Boton { texto: "Cerrar"; principal: true; onPulsado: raiz.cerrar() }
        }
    }
}
