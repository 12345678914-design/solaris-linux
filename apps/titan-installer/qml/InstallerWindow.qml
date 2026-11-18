import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

TitanWindow {
    id: window
    width: 920
    height: 640
    minimumWidth: 820
    minimumHeight: 560
    title: "Instalador de Inti OS"
    showSidebar: true
    expandedSidebarWidth: 236
    showStatusBar: false

    // ---------- Colores: los del tema del sistema (claro/oscuro y acento) ----------
    readonly property bool dark: window.theme.isDark
    readonly property color txt: window.theme.contentTextPrimary
    readonly property color txt2: window.theme.contentTextSecondary
    readonly property color accent: window.theme.accent
    readonly property color okColor: dark ? "#30d158" : "#28a745"
    readonly property color warnColor: dark ? "#ff9f0a" : "#c66b00"
    readonly property color errColor: dark ? "#ff453a" : "#d70015"
    readonly property int rCtl: window.theme.controlRadius
    readonly property int rCard: window.theme.cardRadius
    // Velo: blanco translúcido en oscuro, negro translúcido en claro.
    function veil(a) { return dark ? Qt.rgba(1, 1, 1, a) : Qt.rgba(0, 0, 0, a * 0.7) }
    function tintOf(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    readonly property color campoFondo: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.92)
    readonly property color tarjetaFondo: veil(0.04)
    readonly property color tarjetaBorde: veil(0.10)
    // validatePartitionPlan() es una función: se nombran aquí sus datos para
    // que el aviso y el botón Siguiente se recalculen al cambiar el plan.
    readonly property string planError: {
        installerBackend.tablaManual
        installerBackend.selectedDiskPath
        installerBackend.modoDisco
        installerBackend.disks
        return installerBackend.validatePartitionPlan()
    }
    // Cifrado del disco: contrasena (minimo 8) repetida igual
    readonly property string cifradoError: {
        if (!installerBackend.cifrar || installerBackend.modoDisco === "manual") return ""
        if (claveCifradoField.text.length < 8) return "La contraseña del disco debe tener al menos 8 caracteres."
        if (claveCifradoField.text !== claveCifrado2Field.text) return "Las dos contraseñas del disco no coinciden."
        return ""
    }
    readonly property var disco: installerBackend.discoElegido
    readonly property string nombreOtro: disco.otroSistema ? disco.otroSistema : "otro sistema"

    // ======================= Controles con estilo propio =======================
    // Todos los controles se dibujan aquí: el estilo Basic de Qt (puntos negros,
    // casillas grises) no encajaba con el resto del sistema.

    component Boton: Button {
        id: btn
        font.pixelSize: window.theme.fontBody
        font.weight: btn.highlighted ? Font.DemiBold : Font.Medium
        implicitHeight: 34
        leftPadding: 18
        rightPadding: 18
        contentItem: Text {
            text: btn.text
            font: btn.font
            color: btn.highlighted ? "#ffffff" : window.txt
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: window.rCtl
            opacity: btn.enabled ? 1.0 : 0.45
            color: btn.highlighted
                   ? (btn.down ? Qt.darker(window.accent, 1.15) : (btn.hovered ? Qt.lighter(window.accent, 1.08) : window.accent))
                   : (btn.down ? window.veil(0.16) : (btn.hovered ? window.veil(0.11) : window.veil(0.06)))
            border.width: btn.highlighted ? 0 : 1
            border.color: window.veil(0.12)
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }

    component Campo: TextField {
        id: campo
        property bool invalido: false
        // Se marca al escribir: los errores solo se enseñan en campos tocados,
        // para no recibir al usuario con el formulario en rojo.
        property bool tocado: false
        onTextEdited: tocado = true
        font.pixelSize: window.theme.fontBody
        implicitHeight: 36
        leftPadding: 12
        rightPadding: 12
        color: window.txt
        placeholderTextColor: window.tintOf(window.txt2, 0.85)
        selectionColor: window.accent
        selectedTextColor: "#ffffff"
        background: Rectangle {
            radius: window.rCtl
            color: window.campoFondo
            border.width: campo.activeFocus ? 2 : 1
            border.color: campo.invalido ? window.errColor
                                         : (campo.activeFocus ? window.accent : window.veil(0.16))
            Behavior on border.color { ColorAnimation { duration: 120 } }
        }
    }

    component Selector: ComboBox {
        id: sel
        font.pixelSize: window.theme.fontBody
        implicitHeight: 36
        leftPadding: 12
        rightPadding: 34
        function textoDe(m) { return sel.textRole ? m[sel.textRole] : m }
        contentItem: Text {
            text: sel.displayText
            font: sel.font
            color: window.txt
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        indicator: Canvas {
            x: sel.width - width - 13
            y: (sel.height - height) / 2
            width: 10
            height: 6
            property color c: window.txt2
            onCChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = c
                ctx.lineWidth = 1.6
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(1, 1); ctx.lineTo(5, 5); ctx.lineTo(9, 1)
                ctx.stroke()
            }
        }
        background: Rectangle {
            radius: window.rCtl
            color: sel.hovered ? Qt.tint(window.campoFondo, window.veil(0.04)) : window.campoFondo
            border.width: sel.activeFocus ? 2 : 1
            border.color: sel.activeFocus ? window.accent : window.veil(0.16)
        }
        delegate: ItemDelegate {
            id: opc
            required property int index
            required property var modelData
            width: ListView.view ? ListView.view.width : 0
            height: 32
            highlighted: sel.highlightedIndex === index
            leftPadding: 10
            contentItem: Text {
                text: sel.textoDe(opc.modelData)
                font.pixelSize: window.theme.fontBody
                font.weight: sel.currentIndex === opc.index ? Font.DemiBold : Font.Normal
                color: opc.highlighted ? "#ffffff" : window.txt
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: Rectangle {
                radius: window.rCtl - 2
                color: opc.highlighted ? window.accent : "transparent"
            }
        }
        popup: Popup {
            y: sel.height + 4
            width: sel.width
            implicitHeight: Math.min(contentItem.implicitHeight + 12, 280)
            padding: 6
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: sel.popup.visible ? sel.delegateModel : null
                currentIndex: sel.highlightedIndex
                ScrollIndicator.vertical: ScrollIndicator {}
            }
            background: Rectangle {
                radius: window.rCard - 2
                color: window.dark ? "#2a2d36" : "#ffffff"
                border.color: window.veil(0.14)
            }
        }
    }

    // Opción excluyente en forma de tarjeta (esquema de disco). Lo que se pone
    // dentro se muestra debajo del texto.
    component Opcion: Rectangle {
        id: op
        property string titulo: ""
        property string detalle: ""
        property bool seleccionado: false
        signal elegido()
        default property alias extra: extraCol.data
        implicitHeight: col.implicitHeight + 26
        radius: window.rCard
        color: seleccionado ? window.tintOf(window.accent, window.dark ? 0.16 : 0.07) : window.tarjetaFondo
        border.width: seleccionado ? 1.5 : 1
        border.color: seleccionado ? window.accent : window.tarjetaBorde
        Behavior on color { ColorAnimation { duration: 140 } }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: op.elegido()
        }
        Rectangle {
            x: 14
            y: 14
            width: 18
            height: 18
            radius: 9
            color: op.seleccionado ? window.accent : window.campoFondo
            border.width: op.seleccionado ? 0 : 1.5
            border.color: window.veil(0.3)
            Rectangle {
                anchors.centerIn: parent
                width: 7
                height: 7
                radius: 3.5
                color: "#ffffff"
                visible: op.seleccionado
            }
        }
        Column {
            id: col
            x: 44
            y: 13
            width: op.width - 58
            spacing: 3
            Text {
                text: op.titulo
                width: parent.width
                color: window.txt
                font.pixelSize: window.theme.fontBody
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                text: op.detalle
                visible: text !== ""
                width: parent.width
                color: window.txt2
                font.pixelSize: window.theme.fontCaption + 1
                wrapMode: Text.WordWrap
            }
            Column {
                id: extraCol
                width: parent.width
                topPadding: children.length > 0 ? 8 : 0
                spacing: 8
            }
        }
    }

    component Interruptor: Switch {
        id: sw
        font.pixelSize: window.theme.fontBody
        padding: 0
        indicator: Rectangle {
            implicitWidth: 40
            implicitHeight: 24
            x: sw.leftPadding
            y: (sw.height - height) / 2
            radius: 12
            color: sw.checked ? window.accent : window.veil(0.2)
            Behavior on color { ColorAnimation { duration: 140 } }
            Rectangle {
                x: sw.checked ? parent.width - width - 2 : 2
                y: 2
                width: 20
                height: 20
                radius: 10
                color: "#ffffff"
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }
        contentItem: Text {
            text: sw.text
            font: sw.font
            color: window.txt
            leftPadding: sw.indicator.width + 12
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
        }
    }

    // Aviso en línea: tono "aviso" (naranja), "peligro" (rojo) o "info" (acento).
    component Aviso: Rectangle {
        id: av
        property string tono: "aviso"
        property string texto: ""
        readonly property color c: tono === "peligro" ? window.errColor : (tono === "info" ? window.accent : window.warnColor)
        implicitHeight: Math.max(42, avTexto.implicitHeight + 22)
        radius: window.rCard - 2
        color: window.tintOf(c, window.dark ? 0.15 : 0.08)
        border.color: window.tintOf(c, 0.35)
        Rectangle {
            x: 13
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            radius: 9
            color: av.c
            Text {
                anchors.centerIn: parent
                text: av.tono === "info" ? "i" : "!"
                color: "#ffffff"
                font.pixelSize: 11
                font.bold: true
            }
        }
        Text {
            id: avTexto
            x: 42
            width: av.width - 56
            anchors.verticalCenter: parent.verticalCenter
            text: av.texto
            color: window.txt
            font.pixelSize: window.theme.fontCaption + 1
            wrapMode: Text.WordWrap
        }
    }

    component Tarjeta: Rectangle {
        radius: window.rCard
        color: window.tarjetaFondo
        border.color: window.tarjetaBorde
    }

    component Encabezado: Column {
        id: enc
        property string titulo: ""
        property string subtitulo: ""
        spacing: 4
        bottomPadding: 6
        Text {
            text: enc.titulo
            color: window.txt
            font.pixelSize: window.theme.fontTitle
            font.weight: Font.Bold
        }
        Text {
            text: enc.subtitulo
            visible: text !== ""
            width: enc.width
            color: window.txt2
            font.pixelSize: window.theme.fontBody
            wrapMode: Text.WordWrap
        }
    }

    component Etiqueta: Text {
        color: window.txt
        font.pixelSize: window.theme.fontBody
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
    }

    // Texto bajo un campo: ayuda en gris o error en rojo.
    component Ayuda: Text {
        property bool error: false
        color: error ? window.errColor : window.txt2
        font.pixelSize: window.theme.fontCaption
        wrapMode: Text.WordWrap
    }

    // Fila del resumen: etiqueta a la izquierda, valor a la derecha.
    component Dato: Item {
        id: dato
        property string etiqueta: ""
        property string valor: ""
        property bool ultima: false
        implicitHeight: 36
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: dato.etiqueta
            color: window.txt2
            font.pixelSize: window.theme.fontBody
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.62
            horizontalAlignment: Text.AlignRight
            text: dato.valor
            color: window.txt
            font.pixelSize: window.theme.fontBody
            font.weight: Font.Medium
            elide: Text.ElideMiddle
        }
        Rectangle {
            visible: !dato.ultima
            anchors.bottom: parent.bottom
            x: 16
            width: parent.width - 32
            height: 1
            color: window.veil(0.08)
        }
    }

    // Requisito de la bienvenida: círculo de estado + texto.
    component Requisito: Row {
        id: req
        property int estado: 1   // 1 bien, 0 aviso, -1 mal
        property string texto: ""
        spacing: 10
        Rectangle {
            width: 18
            height: 18
            radius: 9
            anchors.verticalCenter: parent.verticalCenter
            color: req.estado > 0 ? window.okColor : (req.estado === 0 ? window.warnColor : window.errColor)
            Text {
                anchors.centerIn: parent
                text: req.estado > 0 ? "✓" : (req.estado === 0 ? "!" : "✕")
                color: "#ffffff"
                font.pixelSize: 10
                font.bold: true
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: req.texto
            color: window.txt
            font.pixelSize: window.theme.fontBody
        }
    }

    // Página de un paso: desplazable si la ventana es baja.
    component Pagina: ScrollView {
        id: pg
        default property alias contenido: pgCol.data
        clip: true
        contentWidth: availableWidth
        Column {
            id: pgCol
            width: pg.availableWidth
            spacing: 14
        }
    }

    // ============================== Datos ==============================
    property var steps: [
        "Bienvenida",
        "Ubicación y teclado",
        "Disco de destino",
        "Cuenta de usuario",
        "Resumen",
        "Instalación",
        "Finalizado"
    ]

    property string selectedLang: "es_ES.UTF-8"
    property string selectedTimezone: "Europe/Madrid"
    property string selectedTimezoneLabel: "España (Madrid)"
    property string selectedKeymap: "es"
    property string selectedKeymapLabel: "Español (España)"
    property string selectedFs: "ext4"
    property bool autoLogin: false

    readonly property var zonas: [
        { t: "España (Madrid)", v: "Europe/Madrid" },
        { t: "México (Ciudad de México)", v: "America/Mexico_City" },
        { t: "Colombia (Bogotá)", v: "America/Bogota" },
        { t: "Perú (Lima)", v: "America/Lima" },
        { t: "Argentina (Buenos Aires)", v: "America/Argentina/Buenos_Aires" },
        { t: "Chile (Santiago)", v: "America/Santiago" },
        { t: "Venezuela (Caracas)", v: "America/Caracas" },
        { t: "Ecuador (Guayaquil)", v: "America/Guayaquil" },
        { t: "Bolivia (La Paz)", v: "America/La_Paz" },
        { t: "Uruguay (Montevideo)", v: "America/Montevideo" },
        { t: "Paraguay (Asunción)", v: "America/Asuncion" },
        { t: "Guatemala", v: "America/Guatemala" },
        { t: "Costa Rica", v: "America/Costa_Rica" },
        { t: "Panamá", v: "America/Panama" },
        { t: "República Dominicana", v: "America/Santo_Domingo" },
        { t: "Cuba (La Habana)", v: "America/Havana" },
        { t: "Estados Unidos (Nueva York)", v: "America/New_York" },
        { t: "Estados Unidos (Los Ángeles)", v: "America/Los_Angeles" },
        { t: "UTC (tiempo universal)", v: "UTC" }
    ]
    readonly property var teclados: [
        { t: "Español (España)", v: "es" },
        { t: "Español (Latinoamérica)", v: "latam" },
        { t: "Inglés (EE. UU.)", v: "us" }
    ]

    // ---------- Cuenta, como Calamares ----------
    // Los campos empiezan vacíos. Al escribir el nombre se propone el usuario,
    // y del usuario el nombre del equipo, hasta que el usuario los cambie a mano.
    property bool usuarioManual: false
    property bool equipoManual: false
    property bool mostrarClave: false

    function usuarioDesde(nombre) {
        var mapa = { "á": "a", "à": "a", "ä": "a", "â": "a", "é": "e", "è": "e", "ë": "e", "ê": "e",
                     "í": "i", "ì": "i", "ï": "i", "î": "i", "ó": "o", "ò": "o", "ö": "o", "ô": "o",
                     "ú": "u", "ù": "u", "ü": "u", "û": "u", "ñ": "n", "ç": "c" }
        var s = (nombre.trim().toLowerCase().split(/\s+/)[0] || "")
        s = s.replace(/[áàäâéèëêíìïîóòöôúùüûñç]/g, function (c) { return mapa[c] })
        s = s.replace(/[^a-z0-9_-]/g, "").replace(/^[^a-z_]+/, "")
        return s.substr(0, 32)
    }
    function equipoDesde(usuario) {
        var s = usuario.replace(/_/g, "-").replace(/^-+|-+$/g, "")
        return s.length > 0 ? (s + "-pc").substr(0, 63) : ""
    }
    function iniciales(nombre, usuario) {
        var partes = nombre.trim().split(/\s+/).filter(function (p) { return p.length > 0 })
        if (partes.length >= 2) return (partes[0][0] + partes[1][0]).toUpperCase()
        if (partes.length === 1) return partes[0].substr(0, 2).toUpperCase()
        return usuario.length > 0 ? usuario.substr(0, 2).toUpperCase() : ""
    }

    // Las mismas reglas que useradd/hostnamectl: si no se cumplen, la cuenta
    // no se crea y el sistema instalado se quedaría sin usuario.
    readonly property var reservados: ["root", "bin", "daemon", "mail", "ftp", "http", "nobody", "dbus",
                                       "greeter", "polkitd", "rtkit", "avahi", "colord", "git", "uuidd",
                                       "systemd-network", "systemd-resolve", "systemd-timesync",
                                       "systemd-journal-remote", "systemd-coredump", "admin", "wheel", "users"]
    function errorUsuario(u) {
        if (u.length === 0) return "Escribe un nombre de usuario."
        if (!/^[a-z_]/.test(u)) return "Debe empezar por una letra minúscula."
        if (!/^[a-z_][a-z0-9_-]*$/.test(u)) return "Solo minúsculas sin tildes, números, «-» y «_»."
        if (u.length > 32) return "Como máximo 32 caracteres."
        if (reservados.indexOf(u) !== -1) return "«" + u + "» está reservado por el sistema."
        return ""
    }
    function errorEquipo(h) {
        if (h.length === 0) return "Escribe un nombre para el equipo."
        if (!/^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(h))
            return "Solo letras sin tildes, números y «-» (sin empezar ni acabar en «-»)."
        return ""
    }
    function errorClave(p) {
        if (p.length === 0) return "Elige una contraseña."
        if (p.length < 4) return "Usa al menos 4 caracteres."
        return ""
    }
    function errorConfirmacion(p, c) {
        if (c.length === 0) return "Repite la contraseña."
        if (p !== c) return "Las contraseñas no coinciden."
        return ""
    }
    // 0 vacía, 1 débil, 2 aceptable, 3 fuerte.
    function fuerza(p) {
        if (p.length === 0) return 0
        if (p.length < 6) return 1
        var n = 0
        if (p.length >= 10) n++
        if (/[a-z]/.test(p) && /[A-Z]/.test(p)) n++
        if (/[0-9]/.test(p)) n++
        if (/[^A-Za-z0-9]/.test(p)) n++
        return n <= 1 ? 1 : (n <= 2 ? 2 : 3)
    }
    function accountError() {
        return errorUsuario(userField.text) || errorEquipo(hostnameField.text)
               || errorClave(passField.text) || errorConfirmacion(passField.text, confirmPassField.text)
    }

    // ==============================================================================
    // BARRA LATERAL (PASOS DE INSTALACIÓN): la tarjeta flotante de TitanWindow
    // ==============================================================================
    sidebarContentData: [
        Column {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 6
            spacing: 14

            Row {
                spacing: 12
                Image {
                    source: "qrc:/icons/solaris-logo.png"
                    width: 38
                    height: 38
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "Inti OS"
                        color: window.txt
                        font.pixelSize: window.theme.fontHeadline
                        font.bold: true
                    }
                    Text {
                        text: "Instalador del sistema"
                        color: window.txt2
                        font.pixelSize: window.theme.fontCaption
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: window.veil(0.1)
            }

            // Pasos: el actual va resaltado (como una barra lateral de macOS);
            // los hechos llevan ✓ en verde.
            Column {
                width: parent.width
                spacing: 2
                Repeater {
                    model: steps
                    delegate: Rectangle {
                        id: stepRow
                        required property int index
                        required property string modelData
                        readonly property bool current: installerBackend.currentStep === index
                        readonly property bool done: index < installerBackend.currentStep
                        width: parent.width
                        height: 32
                        radius: window.rCtl
                        color: current ? window.tintOf(window.accent, window.dark ? 0.30 : 0.14) : "transparent"
                        Behavior on color { ColorAnimation { duration: 160 } }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 8
                            spacing: 10

                            Rectangle {
                                width: 20
                                height: 20
                                radius: 10
                                anchors.verticalCenter: parent.verticalCenter
                                color: stepRow.done ? window.okColor : (stepRow.current ? window.accent : "transparent")
                                border.width: (stepRow.done || stepRow.current) ? 0 : 1.5
                                border.color: window.veil(0.3)

                                Text {
                                    anchors.centerIn: parent
                                    text: stepRow.done ? "✓" : (stepRow.index + 1)
                                    color: (stepRow.done || stepRow.current) ? "#ffffff" : window.txt2
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: stepRow.modelData
                                color: stepRow.current || stepRow.done ? window.txt : window.txt2
                                font.pixelSize: window.theme.fontBody
                                font.weight: stepRow.current ? Font.DemiBold : Font.Normal
                            }
                        }
                    }
                }
            }
        }
    ]

    // ==============================================================================
    // ÁREA DE CONTENIDO PRINCIPAL
    // ==============================================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: 22
        anchors.bottomMargin: 18
        spacing: 14

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: installerBackend.currentStep

            // -------------------------------------------------------------
            // PASO 0: BIENVENIDA
            // -------------------------------------------------------------
            Item {
                Column {
                    anchors.centerIn: parent
                    spacing: 18
                    width: Math.min(parent.width - 40, 520)

                    Image {
                        source: "qrc:/icons/solaris-logo.png"
                        width: 84
                        height: 84
                        anchors.horizontalCenter: parent.horizontalCenter
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    Text {
                        text: "Bienvenido a Inti OS"
                        color: window.txt
                        font.pixelSize: window.theme.fontLargeTitle
                        font.bold: true
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "Este asistente instalará Inti OS en tu equipo. Te llevará unos minutos y podrás revisarlo todo antes de que se toque el disco."
                        color: window.txt2
                        font.pixelSize: window.theme.fontBody
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }

                    Tarjeta {
                        width: parent.width
                        height: reqCol.implicitHeight + 28

                        Column {
                            id: reqCol
                            x: 16
                            y: 14
                            width: parent.width - 32
                            spacing: 10

                            Text {
                                text: "Requisitos"
                                color: window.txt2
                                font.pixelSize: window.theme.fontCaption
                                font.weight: Font.DemiBold
                                font.capitalization: Font.AllUppercase
                            }
                            Requisito {
                                estado: installerBackend.reqRamOk ? 1 : -1
                                texto: "Memoria: " + Math.round(installerBackend.ramMb / 1024) + " GB (mínimo 2 GB)"
                            }
                            Requisito {
                                estado: installerBackend.reqDiskOk ? 1 : -1
                                texto: installerBackend.reqDiskOk
                                       ? ("Discos disponibles: " + installerBackend.disks.length)
                                       : "No se ha encontrado ningún disco donde instalar"
                            }
                            Requisito {
                                estado: installerBackend.reqPowerOk ? 1 : 0
                                texto: installerBackend.reqPowerOk ? "Conectado a la corriente"
                                                                   : "Batería baja: conecta el cargador"
                            }
                        }
                    }
                }
            }

            // -------------------------------------------------------------
            // PASO 1: UBICACIÓN Y TECLADO
            // -------------------------------------------------------------
            Pagina {
                Encabezado {
                    width: parent.width
                    titulo: "Ubicación y teclado"
                    subtitulo: "Elige tu zona horaria y la distribución de tu teclado."
                }

                Etiqueta { text: "Zona horaria" }
                Selector {
                    width: parent.width
                    model: window.zonas
                    textRole: "t"
                    valueRole: "v"
                    Component.onCompleted: currentIndex = indexOfValue(window.selectedTimezone)
                    onActivated: {
                        window.selectedTimezone = currentValue
                        window.selectedTimezoneLabel = currentText
                    }
                }

                Item { width: 1; height: 4 }

                Etiqueta { text: "Distribución del teclado" }
                Selector {
                    width: parent.width
                    model: window.teclados
                    textRole: "t"
                    valueRole: "v"
                    Component.onCompleted: currentIndex = indexOfValue(window.selectedKeymap)
                    onActivated: {
                        window.selectedKeymap = currentValue
                        window.selectedKeymapLabel = currentText
                    }
                }
                Campo {
                    width: parent.width
                    placeholderText: "Escribe aquí para probar el teclado: ñ, á, @, #, €…"
                }
            }

            // -------------------------------------------------------------
            // PASO 2: DISCO DE DESTINO Y PARTICIONADO
            // -------------------------------------------------------------
            Pagina {
                Encabezado {
                    width: parent.width
                    titulo: "Disco de destino"
                    subtitulo: "Elige dónde instalar Inti OS y cómo preparar el disco."
                }

                Aviso {
                    visible: installerBackend.disks.length === 0
                    width: parent.width
                    texto: "No se ha encontrado ningún disco donde instalar (de al menos 8 GB). El USB desde el que arranca Inti OS no aparece, para no borrarlo por error."
                }

                Repeater {
                    model: installerBackend.disks
                    delegate: Rectangle {
                        id: discoFila
                        required property int index
                        required property var modelData
                        readonly property bool elegido: installerBackend.selectedDiskIndex === index
                        width: parent.width
                        height: 56
                        radius: window.rCard
                        color: elegido ? window.tintOf(window.accent, window.dark ? 0.16 : 0.07) : window.tarjetaFondo
                        border.width: elegido ? 1.5 : 1
                        border.color: elegido ? window.accent : window.tarjetaBorde
                        Behavior on color { ColorAnimation { duration: 140 } }

                        Image {
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            source: "qrc:/icons/system.png"
                            width: 30
                            height: 30
                            smooth: true
                        }
                        Column {
                            x: 56
                            width: parent.width - 100
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                width: parent.width
                                text: (discoFila.modelData.model || discoFila.modelData.path) + "  ·  " + discoFila.modelData.size
                                color: window.txt
                                font.pixelSize: window.theme.fontBody
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                text: discoFila.modelData.path + (discoFila.modelData.tran ? "  ·  " + String(discoFila.modelData.tran).toUpperCase() : "")
                                color: window.txt2
                                font.pixelSize: window.theme.fontCaption + 1
                            }
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            radius: 10
                            visible: discoFila.elegido
                            color: window.accent
                            Text {
                                anchors.centerIn: parent
                                text: "✓"
                                color: "#ffffff"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: installerBackend.selectedDiskIndex = discoFila.index
                        }
                    }
                }

                Item { width: 1; height: 2 }
                Etiqueta { text: "Cómo preparar el disco" }

                Opcion {
                    width: parent.width
                    visible: window.disco.particiones > 0 && installerBackend.isUefi
                    titulo: "Instalar junto a " + window.nombreOtro
                    detalle: "Inti OS usa el espacio libre del disco (" + (window.disco.libreTexto || "0 GB") + " sin particionar) y deja " + window.nombreOtro + " y sus archivos como están. Al encender el equipo podrás elegir cuál arrancar."
                    seleccionado: installerBackend.modoDisco === "junto"
                    onElegido: installerBackend.modoDisco = "junto"

                    Column {
                        visible: installerBackend.modoDisco === "junto"
                        width: parent.width
                        spacing: 8
                        Row {
                            spacing: 12
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Sistema de archivos"
                                color: window.txt2
                                font.pixelSize: window.theme.fontBody
                            }
                            Selector {
                                implicitWidth: 230
                                model: [
                                    { t: "ext4 (recomendado)", v: "ext4" },
                                    { t: "btrfs (puntos de restauración)", v: "btrfs" }
                                ]
                                textRole: "t"
                                valueRole: "v"
                                Component.onCompleted: currentIndex = indexOfValue(window.selectedFs)
                                onActivated: window.selectedFs = currentValue
                            }
                        }
                        Ayuda {
                            width: parent.width
                            error: true
                            text: window.planError
                            visible: text !== ""
                        }
                        Flow {
                            width: parent.width
                            spacing: 8
                            Boton {
                                text: "Volver a buscar"
                                onClicked: installerBackend.refreshDisks()
                            }
                            Boton {
                                text: "Abrir GParted (reducir una partición)"
                                onClicked: installerBackend.openExternalPartitioner()
                            }
                        }
                    }
                }

                Opcion {
                    width: parent.width
                    titulo: "Borrar el disco e instalar Inti OS"
                    detalle: "Recomendado si el disco no tiene nada que quieras conservar. Crea automáticamente las particiones necesarias (arranque " + (installerBackend.isUefi ? "EFI de 512 MB" : "BIOS") + " y sistema)."
                    seleccionado: installerBackend.modoDisco === "borrar"
                    onElegido: installerBackend.modoDisco = "borrar"

                    Row {
                        visible: installerBackend.modoDisco === "borrar"
                        spacing: 12
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Sistema de archivos"
                            color: window.txt2
                            font.pixelSize: window.theme.fontBody
                        }
                        Selector {
                            implicitWidth: 230
                            model: [
                                { t: "ext4 (recomendado)", v: "ext4" },
                                { t: "btrfs (puntos de restauración)", v: "btrfs" }
                            ]
                            textRole: "t"
                            valueRole: "v"
                            Component.onCompleted: currentIndex = indexOfValue(window.selectedFs)
                            onActivated: window.selectedFs = currentValue
                        }
                    }
                }

                Opcion {
                    width: parent.width
                    titulo: "Particionado manual"
                    detalle: "Para usuarios avanzados: elige qué particiones usar (/, /boot/efi, /home…), si se formatean, y crea o borra particiones."
                    seleccionado: installerBackend.modoDisco === "manual"
                    onElegido: installerBackend.modoDisco = "manual"

                    Column {
                        id: manualCol
                        visible: installerBackend.manualPartitioning
                        width: parent.width
                        spacing: 10
                        property int sel: -1
                        property string errorAplicar: ""
                        readonly property var tabla: installerBackend.tablaManual
                        readonly property var fila: sel >= 0 && sel < tabla.length ? tabla[sel] : null
                        readonly property string tipoFila: fila ? fila.tipo : ""
                        onTablaChanged: if (sel >= tabla.length) sel = -1

                        function corto(n) { return n && n.indexOf("/dev/") === 0 ? n.substring(5) : n }
                        function colorDe(f) {
                            if (f.tipo === "libre") return window.veil(0.10)
                            if (f.tipo === "nueva") return window.accent
                            if (f.borrar) return window.errColor
                            var fl = f.flags || "", fs = f.fsActual || ""
                            if (fl.indexOf("esp") !== -1) return "#ff9f0a"
                            if (fs === "ntfs" || fl.indexOf("msftres") !== -1) return "#5e5ce6"
                            if (fs === "swap") return "#bf5af2"
                            if (fs === "ext4" || fs === "btrfs" || fs === "xfs" || fs === "ext3") return "#30d158"
                            return "#8e8e93"
                        }
                        function descripcion(f) {
                            if (f.tipo === "libre") return "Espacio libre"
                            if (f.tipo === "nueva") return "Nueva (pendiente) · " + f.fsTexto
                            var d = f.fsTexto
                            if (f.uso) d += " · " + f.uso
                            if (f.etiqueta) d += " · «" + f.etiqueta + "»"
                            return d
                        }
                        function destino(f) {
                            if (f.tipo === "libre") return ""
                            if (f.borrar) return "Se borrará"
                            if (f.montada) return "En uso (" + f.montada + ")"
                            if (!f.montaje) return "—"
                            if (f.tipo === "nueva") return f.montaje
                            return f.montaje + (f.formatear ? " · formatear" : " · sin formatear")
                        }
                        // Los selectores del editor siguen a la fila elegida
                        function sincronizar() {
                            if (!fila) return
                            selMontaje.currentIndex = Math.max(0, selMontaje.model.indexOf(fila.montaje ? fila.montaje : "(no usar)"))
                            selFs.currentIndex = Math.max(0, selFs.model.indexOf(fila.fs ? fila.fs : "ext4"))
                        }
                        onFilaChanged: sincronizar()

                        Text {
                            width: parent.width
                            text: installerBackend.selectedDiskName + (installerBackend.tipoTablaManual === "unknown" ? " · sin tabla de particiones"
                                  : " · tabla " + (installerBackend.tipoTablaManual === "gpt" ? "GPT" : "MBR"))
                            color: window.txt2
                            font.pixelSize: window.theme.fontCaption
                        }

                        // Barra del disco (proporcional)
                        Row {
                            id: barraDisco
                            width: parent.width
                            height: 30
                            spacing: 2
                            Repeater {
                                model: manualCol.tabla
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: Math.max(5, (barraDisco.width - 2 * Math.max(0, manualCol.tabla.length - 1)) * modelData.proporcion)
                                    height: barraDisco.height
                                    radius: 5
                                    color: manualCol.colorDe(modelData)
                                    opacity: modelData.borrar ? 0.45 : 1
                                    border.width: manualCol.sel === index ? 2 : 0
                                    border.color: window.txt
                                    Text {
                                        anchors.centerIn: parent
                                        visible: parent.width > 54
                                        text: modelData.tipo === "libre" ? "libre" : manualCol.corto(modelData.nodo)
                                        color: modelData.tipo === "libre" ? window.txt2 : "#ffffff"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manualCol.sel = index }
                                }
                            }
                        }

                        // Lista
                        Column {
                            width: parent.width
                            spacing: 2
                            Repeater {
                                model: manualCol.tabla
                                Rectangle {
                                    id: filaRect
                                    required property var modelData
                                    required property int index
                                    width: parent.width
                                    height: 38
                                    radius: 8
                                    color: manualCol.sel === index ? window.tintOf(window.accent, 0.16)
                                           : filaZona.containsMouse ? window.veil(0.05) : "transparent"
                                    Row {
                                        x: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10
                                        Rectangle { width: 12; height: 12; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: manualCol.colorDe(filaRect.modelData); opacity: filaRect.modelData.borrar ? 0.45 : 1 }
                                        Text {
                                            width: 92
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: filaRect.modelData.tipo === "parte" ? manualCol.corto(filaRect.modelData.nodo) : (filaRect.modelData.tipo === "nueva" ? "Nueva" : "Libre")
                                            color: window.txt
                                            font.pixelSize: window.theme.fontBody
                                            font.weight: Font.DemiBold
                                            font.strikeout: !!filaRect.modelData.borrar
                                        }
                                        Text { width: 70; anchors.verticalCenter: parent.verticalCenter; text: filaRect.modelData.tamanoTexto; color: window.txt2; font.pixelSize: window.theme.fontCaption + 1 }
                                        Text {
                                            width: filaRect.width - 92 - 70 - 170 - 70
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: manualCol.descripcion(filaRect.modelData)
                                            color: window.txt2
                                            font.pixelSize: window.theme.fontCaption + 1
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: 170
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: manualCol.destino(filaRect.modelData)
                                            color: filaRect.modelData.borrar ? window.errColor : (filaRect.modelData.montaje ? window.accent : window.txt2)
                                            font.pixelSize: window.theme.fontCaption + 1
                                            font.weight: filaRect.modelData.montaje ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                        }
                                    }
                                    MouseArea { id: filaZona; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: manualCol.sel = filaRect.index }
                                }
                            }
                        }

                        // Editor de la fila elegida
                        Tarjeta {
                            visible: manualCol.fila !== null
                            width: parent.width
                            height: editorCol.implicitHeight + 24
                            Column {
                                id: editorCol
                                x: 12
                                y: 12
                                width: parent.width - 24
                                spacing: 10

                                Text {
                                    text: !manualCol.fila ? "" : manualCol.tipoFila === "libre" ? "Crear una partición en este espacio libre (" + manualCol.fila.tamanoTexto + ")"
                                          : manualCol.tipoFila === "nueva" ? "Partición nueva de " + manualCol.fila.tamanoTexto + " (pendiente de aplicar)"
                                          : "Partición " + manualCol.corto(manualCol.fila.nodo) + " · " + manualCol.fila.tamanoTexto
                                    color: window.txt
                                    font.pixelSize: window.theme.fontBody
                                    font.weight: Font.DemiBold
                                }

                                Ayuda {
                                    width: parent.width
                                    visible: manualCol.fila !== null && manualCol.tipoFila === "parte" && (manualCol.fila.borrar || manualCol.fila.montada !== "")
                                    text: !manualCol.fila ? "" : manualCol.fila.montada ? "Está en uso ahora mismo (" + manualCol.fila.montada + "): no se puede cambiar."
                                          : "Marcada para borrar. Pulsa «No borrar» para conservarla."
                                }

                                Row {
                                    spacing: 12
                                    visible: manualCol.fila !== null && (manualCol.tipoFila === "nueva" || manualCol.tipoFila === "libre"
                                             || (manualCol.tipoFila === "parte" && !manualCol.fila.borrar && manualCol.fila.montada === ""))
                                    Column {
                                        spacing: 4
                                        visible: manualCol.tipoFila === "libre"
                                        Etiqueta { text: "Tamaño (MB)" }
                                        Campo { id: tamNueva; width: 120; placeholderText: "Todo"; validator: IntValidator { bottom: 1 } }
                                    }
                                    Column {
                                        spacing: 4
                                        Etiqueta { text: "Punto de montaje" }
                                        Selector {
                                            id: selMontaje
                                            width: 150
                                            model: ["(no usar)", "/", "/boot/efi", "/home", "/boot", "/var", "swap"]
                                            onActivated: if (manualCol.tipoFila !== "libre")
                                                             installerBackend.editarParticion(manualCol.sel, currentText, manualCol.fila.formatear, selFs.currentText)
                                        }
                                    }
                                    Column {
                                        spacing: 4
                                        visible: manualCol.tipoFila === "parte"
                                        Etiqueta { text: "Formatear" }
                                        Interruptor {
                                            text: checked ? "Sí (se borra su contenido)" : "No (se conserva)"
                                            checked: manualCol.fila ? manualCol.fila.formatear : false
                                            enabled: manualCol.fila !== null && !!manualCol.fila.montaje && manualCol.fila.montaje !== "/"
                                            onToggled: installerBackend.editarParticion(manualCol.sel, manualCol.fila.montaje, checked, selFs.currentText)
                                        }
                                    }
                                    Column {
                                        spacing: 4
                                        Etiqueta { text: "Formato" }
                                        Selector {
                                            id: selFs
                                            width: 104
                                            model: ["ext4", "btrfs", "xfs", "fat32", "swap"]
                                            enabled: manualCol.tipoFila !== "parte" || (manualCol.fila !== null && manualCol.fila.formatear)
                                            onActivated: if (manualCol.tipoFila !== "libre")
                                                             installerBackend.editarParticion(manualCol.sel, manualCol.fila.montaje ? manualCol.fila.montaje : "(no usar)",
                                                                                              manualCol.fila.formatear, currentText)
                                        }
                                    }
                                }

                                Ayuda {
                                    width: parent.width
                                    visible: manualCol.tipoFila === "parte" && manualCol.fila !== null && !manualCol.fila.borrar && manualCol.fila.montada === ""
                                    text: "Esto solo cambia la información: el disco no se toca ahora. Al instalar se formatea (si lo pides) y se monta donde digas."
                                }

                                Flow {
                                    width: parent.width
                                    spacing: 8
                                    Boton {
                                        visible: manualCol.tipoFila === "libre"
                                        text: "Añadir partición"
                                        highlighted: true
                                        onClicked: {
                                            installerBackend.crearEnHueco(manualCol.sel, parseInt(tamNueva.text) || 0, selMontaje.currentText, selFs.currentText)
                                            tamNueva.text = ""
                                        }
                                    }
                                    Boton {
                                        visible: manualCol.tipoFila === "nueva"
                                        text: "Quitar"
                                        onClicked: installerBackend.quitarNueva(manualCol.sel)
                                    }
                                    Boton {
                                        visible: manualCol.tipoFila === "parte" && manualCol.fila !== null && manualCol.fila.montada === ""
                                        text: manualCol.fila && manualCol.fila.borrar ? "No borrar" : "Borrar partición"
                                        onClicked: installerBackend.marcarBorrar(manualCol.sel, !manualCol.fila.borrar)
                                    }
                                }
                            }
                        }

                        // Cambios pendientes en la tabla
                        Aviso {
                            width: parent.width
                            visible: installerBackend.cambiosPendientes.length > 0
                            tono: "aviso"
                            texto: "Cambios pendientes (todavía no se ha tocado el disco):\n• " + installerBackend.cambiosPendientes.join("\n• ")
                        }

                        Flow {
                            width: parent.width
                            spacing: 8
                            Boton {
                                text: "Aplicar cambios…"
                                highlighted: true
                                enabled: installerBackend.cambiosPendientes.length > 0
                                onClicked: dlgAplicar.open()
                            }
                            Boton {
                                text: "Descartar"
                                enabled: installerBackend.cambiosPendientes.length > 0
                                onClicked: { installerBackend.descartarCambios(); manualCol.errorAplicar = "" }
                            }
                            Boton {
                                text: "Tabla nueva…"
                                onClicked: { installerBackend.tablaNueva(); manualCol.sel = -1 }
                            }
                            Boton {
                                text: "Volver a leer el disco"
                                onClicked: { installerBackend.leerTablaManual(); manualCol.errorAplicar = "" }
                            }
                            Boton {
                                text: "Abrir GParted"
                                onClicked: installerBackend.openExternalPartitioner()
                            }
                        }

                        Ayuda {
                            width: parent.width
                            error: true
                            text: manualCol.errorAplicar !== "" ? manualCol.errorAplicar : window.planError
                            visible: text !== ""
                        }
                    }
                }

                // Cifrado (solo en los modos automaticos)
                Tarjeta {
                    visible: installerBackend.disks.length > 0 && installerBackend.modoDisco !== "manual"
                    width: parent.width
                    height: cifradoCol.implicitHeight + 28
                    Column {
                        id: cifradoCol
                        x: 14
                        y: 14
                        width: parent.width - 28
                        spacing: 10
                        Interruptor {
                            width: parent.width
                            text: "Cifrar el disco"
                            checked: installerBackend.cifrar
                            onToggled: installerBackend.cifrar = checked
                        }
                        Ayuda {
                            width: parent.width
                            text: "Si pierdes o te roban el equipo, nadie puede leer tus archivos sin esta contraseña. Se pide cada vez que lo enciendes. Si la olvidas, los datos no se pueden recuperar."
                        }
                        Column {
                            visible: installerBackend.cifrar
                            width: parent.width
                            spacing: 6
                            Etiqueta { text: "Contraseña del disco" }
                            Campo {
                                id: claveCifradoField
                                width: parent.width
                                echoMode: TextInput.Password
                                invalido: tocado && text.length < 8
                            }
                            Etiqueta { text: "Repite la contraseña" }
                            Campo {
                                id: claveCifrado2Field
                                width: parent.width
                                echoMode: TextInput.Password
                                invalido: tocado && text !== claveCifradoField.text
                            }
                            Ayuda {
                                width: parent.width
                                error: true
                                text: window.cifradoError
                                visible: text !== "" && (claveCifradoField.tocado || claveCifrado2Field.tocado)
                            }
                        }
                    }
                }

                Aviso {
                    visible: installerBackend.disks.length > 0 && installerBackend.modoDisco !== "junto"
                    width: parent.width
                    tono: "aviso"
                    texto: installerBackend.modoDisco === "manual"
                           ? "Solo se toca lo que elijas: los cambios de la tabla piden confirmación al aplicarlos y lo que marques para formatear se borra al instalar. Haz una copia de seguridad antes."
                           : "Se borrará todo lo que haya en " + installerBackend.selectedDiskName + ". Haz una copia de seguridad de lo que quieras conservar."
                }
                Aviso {
                    visible: installerBackend.modoDisco === "junto"
                    width: parent.width
                    tono: "info"
                    texto: "No se borra ni se mueve nada de " + window.nombreOtro + ". Aun así, es buena idea tener una copia de seguridad antes de tocar las particiones de un disco."
                }
            }

            // -------------------------------------------------------------
            // PASO 3: CUENTA DE USUARIO (como Calamares: todo vacío al empezar)
            // -------------------------------------------------------------
            Pagina {
                Row {
                    width: parent.width
                    spacing: 16

                    // Avatar con las iniciales; se rellena según escribes.
                    Rectangle {
                        width: 56
                        height: 56
                        radius: 28
                        anchors.verticalCenter: parent.verticalCenter
                        color: avatarTexto.text !== "" ? window.accent : window.veil(0.10)
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Text {
                            id: avatarTexto
                            anchors.centerIn: parent
                            text: window.iniciales(fullNameField.text, userField.text)
                            color: "#ffffff"
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                        }
                        // Silueta mientras no hay nombre.
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            visible: avatarTexto.text === ""
                            Rectangle { width: 16; height: 16; radius: 8; color: window.txt2; anchors.horizontalCenter: parent.horizontalCenter }
                            Rectangle { width: 28; height: 12; radius: 6; color: window.txt2 }
                        }
                    }

                    Encabezado {
                        width: parent.width - 72
                        anchors.verticalCenter: parent.verticalCenter
                        bottomPadding: 0
                        titulo: "Crea tu cuenta"
                        subtitulo: "Será la cuenta de administrador del equipo. Después podrás añadir más usuarios desde la pantalla de inicio."
                    }
                }

                Item { width: 1; height: 2 }

                // Nombre
                Column {
                    width: parent.width
                    spacing: 6
                    Etiqueta { text: "¿Cómo te llamas?" }
                    Campo {
                        id: fullNameField
                        objectName: "campoNombre"
                        width: parent.width
                        placeholderText: "Nombre y apellidos"
                        maximumLength: 64
                        onTextEdited: {
                            if (!window.usuarioManual)
                                userField.text = window.usuarioDesde(text)
                        }
                    }
                    Ayuda {
                        width: parent.width
                        text: "Es el nombre que verás en la pantalla de inicio. Puede llevar tildes y espacios."
                    }
                }

                // Usuario y equipo, uno al lado del otro
                Row {
                    width: parent.width
                    spacing: 16

                    Column {
                        width: (parent.width - 16) / 2
                        spacing: 6
                        Etiqueta { text: "Nombre de usuario" }
                        Campo {
                            id: userField
                            width: parent.width
                            placeholderText: "p. ej. ana"
                            maximumLength: 32
                            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhLowercaseOnly
                            invalido: tocado && window.errorUsuario(text) !== ""
                            onTextEdited: window.usuarioManual = text.length > 0
                            onTextChanged: {
                                if (text.length > 0) tocado = true
                                if (!window.equipoManual)
                                    hostnameField.text = window.equipoDesde(text)
                            }
                        }
                        Ayuda {
                            width: parent.width
                            error: userField.invalido
                            text: userField.invalido ? window.errorUsuario(userField.text)
                                                     : "Para iniciar sesión. Minúsculas, sin espacios."
                        }
                    }

                    Column {
                        width: (parent.width - 16) / 2
                        spacing: 6
                        Etiqueta { text: "Nombre del equipo" }
                        Campo {
                            id: hostnameField
                            width: parent.width
                            placeholderText: "p. ej. ana-pc"
                            maximumLength: 63
                            invalido: tocado && window.errorEquipo(text) !== ""
                            onTextEdited: window.equipoManual = text.length > 0
                        }
                        Ayuda {
                            width: parent.width
                            error: hostnameField.invalido
                            text: hostnameField.invalido ? window.errorEquipo(hostnameField.text)
                                                         : "Así se verá el equipo en la red."
                        }
                    }
                }

                // Contraseña
                Row {
                    width: parent.width
                    spacing: 16

                    Column {
                        width: (parent.width - 16) / 2
                        spacing: 6
                        Etiqueta { text: "Contraseña" }
                        Campo {
                            id: passField
                            width: parent.width
                            echoMode: window.mostrarClave ? TextInput.Normal : TextInput.Password
                            invalido: tocado && window.errorClave(text) !== ""
                        }
                        // Medidor de seguridad
                        Row {
                            width: parent.width
                            spacing: 4
                            Repeater {
                                model: 3
                                Rectangle {
                                    required property int index
                                    width: (passField.width - 8) / 3
                                    height: 4
                                    radius: 2
                                    readonly property int f: window.fuerza(passField.text)
                                    color: index < f ? (f === 1 ? window.errColor : (f === 2 ? window.warnColor : window.okColor))
                                                     : window.veil(0.10)
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                }
                            }
                        }
                        Ayuda {
                            width: parent.width
                            error: passField.invalido
                            text: {
                                if (passField.invalido) return window.errorClave(passField.text)
                                var f = window.fuerza(passField.text)
                                if (f === 0) return "Mejor larga y con números o símbolos."
                                return ["", "Contraseña débil", "Contraseña aceptable", "Contraseña segura"][f]
                            }
                        }
                    }

                    Column {
                        width: (parent.width - 16) / 2
                        spacing: 6
                        Etiqueta { text: "Repite la contraseña" }
                        Campo {
                            id: confirmPassField
                            width: parent.width
                            echoMode: window.mostrarClave ? TextInput.Normal : TextInput.Password
                            invalido: tocado && window.errorConfirmacion(passField.text, text) !== ""
                        }
                        Item { width: 1; height: 4 }
                        Ayuda {
                            width: parent.width
                            error: confirmPassField.invalido
                            color: error ? window.errColor
                                         : (confirmPassField.text.length > 0 && confirmPassField.text === passField.text ? window.okColor : window.txt2)
                            text: confirmPassField.invalido ? window.errorConfirmacion(passField.text, confirmPassField.text)
                                                            : (confirmPassField.text.length > 0 ? "Las contraseñas coinciden" : "Para evitar errores al escribir.")
                        }
                    }
                }

                Interruptor {
                    text: "Mostrar las contraseñas"
                    checked: window.mostrarClave
                    onToggled: window.mostrarClave = checked
                }
                Interruptor {
                    width: parent.width
                    text: "Entrar sin contraseña la primera vez (después siempre la pedirá)"
                    checked: window.autoLogin
                    onToggled: window.autoLogin = checked
                }

                Aviso {
                    width: parent.width
                    tono: "info"
                    texto: "Esta contraseña también será la del administrador del sistema (root)."
                }
            }

            // -------------------------------------------------------------
            // PASO 4: RESUMEN
            // -------------------------------------------------------------
            Pagina {
                Encabezado {
                    width: parent.width
                    titulo: "Resumen"
                    subtitulo: "Revisa que todo esté bien. Hasta que pulses «Instalar ahora» no se cambiará nada en el disco."
                }

                Text {
                    text: "Región"
                    color: window.txt2
                    font.pixelSize: window.theme.fontCaption
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                }
                Tarjeta {
                    width: parent.width
                    height: regionCol.implicitHeight
                    Column {
                        id: regionCol
                        width: parent.width
                        Dato { width: parent.width; etiqueta: "Zona horaria"; valor: window.selectedTimezoneLabel }
                        Dato { width: parent.width; etiqueta: "Teclado"; valor: window.selectedKeymapLabel; ultima: true }
                    }
                }

                Text {
                    text: "Disco"
                    color: window.txt2
                    font.pixelSize: window.theme.fontCaption
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                }
                Tarjeta {
                    width: parent.width
                    height: discoCol.implicitHeight
                    Column {
                        id: discoCol
                        width: parent.width
                        Dato { width: parent.width; etiqueta: "Destino"; valor: installerBackend.selectedDiskName }
                        Dato {
                            width: parent.width
                            etiqueta: "Particionado"
                            valor: installerBackend.modoDisco === "manual"
                                   ? ("Manual: " + installerBackend.resumenManual.length + (installerBackend.resumenManual.length === 1 ? " partición" : " particiones"))
                                   : installerBackend.modoDisco === "junto"
                                     ? ("Junto a " + window.nombreOtro + " · " + window.selectedFs)
                                     : ("Borrar el disco · " + window.selectedFs)
                        }
                        Dato {
                            width: parent.width
                            etiqueta: "Cifrado"
                            valor: installerBackend.cifrar && installerBackend.modoDisco !== "manual" ? "Sí (LUKS2): contraseña al encender" : "No"
                        }
                        Dato { width: parent.width; etiqueta: "Arranque"; valor: installerBackend.isUefi ? "UEFI (GPT)" : "BIOS (MBR)"; ultima: true }
                    }
                }

                Text {
                    text: "Cuenta"
                    color: window.txt2
                    font.pixelSize: window.theme.fontCaption
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                }
                Tarjeta {
                    width: parent.width
                    height: cuentaCol.implicitHeight
                    Column {
                        id: cuentaCol
                        width: parent.width
                        Dato { width: parent.width; etiqueta: "Nombre"; valor: fullNameField.text.trim() !== "" ? fullNameField.text.trim() : "—" }
                        Dato { width: parent.width; etiqueta: "Usuario"; valor: userField.text }
                        Dato { width: parent.width; etiqueta: "Equipo"; valor: hostnameField.text }
                        Dato { width: parent.width; etiqueta: "Primer inicio"; valor: window.autoLogin ? "Sin contraseña (solo la primera vez)" : "Pide la contraseña"; ultima: true }
                    }
                }

                Aviso {
                    width: parent.width
                    tono: installerBackend.modoDisco === "junto" ? "info" : "peligro"
                    texto: installerBackend.modoDisco === "junto"
                           ? "Al pulsar «Instalar ahora» se crearán las particiones de Inti OS en el espacio libre de " + installerBackend.selectedDiskName + ". " + window.nombreOtro + " no se toca."
                           : installerBackend.modoDisco === "manual"
                             ? "Al pulsar «Instalar ahora»:\n• " + installerBackend.resumenManual.join("\n• ") + "\nEl resto del disco no se toca."
                             : "Al pulsar «Instalar ahora» se borrará " + installerBackend.selectedDiskName + ". No se puede deshacer."
                }
            }

            // -------------------------------------------------------------
            // PASO 5: INSTALANDO (PROGRESO)
            // -------------------------------------------------------------
            Item {
                Column {
                    anchors.centerIn: parent
                    spacing: 18
                    width: Math.min(parent.width - 40, 560)

                    Image {
                        source: "qrc:/icons/solaris-logo.png"
                        width: 76
                        height: 76
                        anchors.horizontalCenter: parent.horizontalCenter
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    Text {
                        text: installerBackend.errorMessage !== "" ? "La instalación se ha detenido" : "Instalando Inti OS"
                        color: window.txt
                        font.pixelSize: window.theme.fontTitle
                        font.bold: true
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        visible: installerBackend.errorMessage === ""
                        text: "Puedes seguir usando el equipo mientras tanto. No lo apagues."
                        color: window.txt2
                        font.pixelSize: window.theme.fontBody
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Rectangle {
                        width: parent.width
                        height: 8
                        radius: 4
                        color: window.veil(0.1)

                        Rectangle {
                            width: parent.width * (installerBackend.progressPercent / 100.0)
                            height: parent.height
                            radius: 4
                            color: installerBackend.errorMessage !== "" ? window.errColor : window.accent
                            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 20
                        Text {
                            anchors.left: parent.left
                            anchors.right: porcentaje.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: installerBackend.progressMessage
                            color: window.txt2
                            font.pixelSize: window.theme.fontBody
                            elide: Text.ElideRight
                        }
                        Text {
                            id: porcentaje
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: installerBackend.progressPercent + " %"
                            color: window.txt
                            font.weight: Font.DemiBold
                            font.pixelSize: window.theme.fontBody
                        }
                    }

                    Aviso {
                        visible: installerBackend.errorMessage !== ""
                        width: parent.width
                        tono: "peligro"
                        texto: installerBackend.errorMessage
                    }

                    // Si falla, que haya salida.
                    Row {
                        visible: !installerBackend.installing && installerBackend.errorMessage !== ""
                        spacing: 12
                        anchors.horizontalCenter: parent.horizontalCenter
                        Boton {
                            text: "Cerrar el instalador"
                            onClicked: installerBackend.closeInstaller()
                        }
                        Boton {
                            text: "Volver al resumen"
                            highlighted: true
                            onClicked: installerBackend.currentStep = 4
                        }
                    }
                }
            }

            // -------------------------------------------------------------
            // PASO 6: COMPLETADO
            // -------------------------------------------------------------
            Item {
                Column {
                    anchors.centerIn: parent
                    spacing: 18
                    width: Math.min(parent.width - 40, 520)

                    Rectangle {
                        width: 72
                        height: 72
                        radius: 36
                        color: window.okColor
                        anchors.horizontalCenter: parent.horizontalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            color: "#ffffff"
                            font.pixelSize: 36
                            font.bold: true
                        }
                    }

                    Text {
                        text: "Inti OS está instalado"
                        color: window.txt
                        font.pixelSize: window.theme.fontLargeTitle
                        font.bold: true
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: (installerBackend.isUefi ? "El disco ya es la primera opción de arranque. "
                                                       : "El cargador de arranque (GRUB) está instalado en el disco. ")
                              + "Reinicia y retira el USB cuando se apague la pantalla."
                        color: window.txt2
                        font.pixelSize: window.theme.fontBody
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }

                    Row {
                        spacing: 12
                        anchors.horizontalCenter: parent.horizontalCenter

                        Boton {
                            text: "Seguir probando"
                            onClicked: installerBackend.closeInstaller()
                        }
                        Boton {
                            text: "Reiniciar ahora"
                            highlighted: true
                            onClicked: installerBackend.rebootSystem()
                        }
                    }
                }
            }
        }

        // ==============================================================================
        // BARRA INFERIOR DE NAVEGACIÓN
        // ==============================================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: installerBackend.currentStep < 5
            color: window.veil(0.08)
        }

        RowLayout {
            Layout.fillWidth: true
            visible: installerBackend.currentStep < 5
            spacing: 10

            Boton {
                text: "Cancelar"
                onClicked: installerBackend.closeInstaller()
            }

            Item { Layout.fillWidth: true }

            Boton {
                text: "Atrás"
                visible: installerBackend.currentStep > 0
                onClicked: installerBackend.currentStep--
            }

            Boton {
                text: installerBackend.currentStep === 4 ? "Instalar ahora" : "Siguiente"
                highlighted: true
                enabled: {
                    if (installerBackend.currentStep === 0) return installerBackend.reqRamOk && installerBackend.reqDiskOk
                    if (installerBackend.currentStep === 2)
                        return installerBackend.disks.length > 0
                               && window.planError === ""
                               && window.cifradoError === ""
                    if (installerBackend.currentStep === 3) return window.accountError() === ""
                    return true
                }
                onClicked: {
                    if (installerBackend.currentStep === 4) {
                        installerBackend.setClaveCifrado(installerBackend.cifrar ? claveCifradoField.text : "")
                        installerBackend.startInstallation(
                            window.selectedFs,
                            fullNameField.text.trim(),
                            userField.text,
                            passField.text,
                            hostnameField.text,
                            window.autoLogin,
                            window.selectedTimezone,
                            window.selectedKeymap
                        )
                    } else {
                        installerBackend.currentStep++
                    }
                }
            }
        }
    }

    // Confirmación antes de escribir la tabla de particiones (modo manual)
    Popup {
        id: dlgAplicar
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(520, window.width - 60)
        modal: true
        padding: 22
        closePolicy: Popup.CloseOnEscape
        background: Rectangle {
            radius: 16
            color: window.dark ? "#26272c" : "#ffffff"
            border.color: window.tarjetaBorde
        }
        contentItem: Column {
            spacing: 12
            Text {
                width: parent.width
                text: "¿Aplicar estos cambios en " + installerBackend.selectedDiskName + "?"
                color: window.txt
                font.pixelSize: window.theme.fontBody + 2
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: "• " + installerBackend.cambiosPendientes.join("\n• ")
                color: window.txt
                font.pixelSize: window.theme.fontBody
                wrapMode: Text.WordWrap
                lineHeight: 1.25
            }
            Aviso {
                width: parent.width
                tono: "peligro"
                texto: "Se escribirá ahora en el disco y no se puede deshacer. Lo que haya en las particiones borradas se perderá."
            }
            Row {
                anchors.right: parent.right
                spacing: 10
                Boton { text: "Cancelar"; onClicked: dlgAplicar.close() }
                Boton {
                    text: "Aplicar"
                    highlighted: true
                    onClicked: {
                        dlgAplicar.close()
                        manualCol.errorAplicar = installerBackend.aplicarCambios()
                    }
                }
            }
        }
    }
}
