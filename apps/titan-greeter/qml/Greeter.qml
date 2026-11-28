import QtQuick
import QtQuick.Window
import QtQuick.Controls

// Pantalla de inicio de sesion de Inti OS, con el mismo aspecto que la de
// bloqueo de titan-shell: reloj arriba, la cuenta elegida en el centro y el
// resto de cuentas debajo para cambiar con un clic.
Window {
    id: ventana
    visible: true
    visibility: Window.FullScreen
    width: 1280
    height: 800
    color: "#08090d"
    title: "Inti OS"

    property string elegido: ""
    property bool hayError: false
    property string textoError: ""
    property bool panelAbierto: false

    // La cuenta elegida ya tiene la sesion abierta (bloqueada): se vuelve a
    // ella en vez de entrar dos veces.
    readonly property bool conSesion: elegido !== "" && sistema.sesiones[elegido] !== undefined
    readonly property var cuenta: {
        var l = usuarios.usuarios
        for (var i = 0; i < l.length; ++i)
            if (l[i].usuario === elegido) return l[i]
        return null
    }

    function elegir(usuario) {
        elegido = usuario
        hayError = false
        clave.text = ""
        clave.forceActiveFocus()
    }

    function entrar() {
        if (!cuenta || greetd.ocupado) return
        if (conSesion) { volver(); return }
        hayError = false
        greetd.entrar(elegido, clave.text)
    }

    function volver() {
        if (!sistema.irASesion(elegido)) {
            textoError = "No se pudo volver a esa sesión"
            hayError = true
        }
    }

    function colorDe(nombre) {
        var colores = ["#0a84ff", "#30d158", "#ff9f0a", "#bf5af2", "#ff375f", "#64d2ff", "#ffd60a"]
        var h = 0
        for (var i = 0; i < nombre.length; ++i) h = (h * 31 + nombre.charCodeAt(i)) % 997
        return colores[h % colores.length]
    }

    Component.onCompleted: {
        var l = usuarios.usuarios
        var ultimo = sistema.ultimoUsuario
        var elegible = l.length > 0 ? l[0].usuario : ""
        for (var i = 0; i < l.length; ++i)
            if (l[i].usuario === ultimo) elegible = ultimo
        // Al cambiar de usuario, se propone una cuenta que no este ya dentro
        if (sistema.modoCambio && sistema.sesiones[elegible] !== undefined) {
            for (var j = 0; j < l.length; ++j)
                if (sistema.sesiones[l[j].usuario] === undefined) { elegible = l[j].usuario; break }
        }
        elegir(elegible)
    }

    // Las sesiones se abren y cierran mientras esta pantalla espera
    Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: sistema.actualizarSesiones()
    }

    Connections {
        target: greetd
        function onFallo(mensaje) {
            ventana.textoError = mensaje
            ventana.hayError = true
            clave.text = ""
            sacudida.restart()
            clave.forceActiveFocus()
        }
        function onSesionLista() {
            sistema.recordarUsuario(ventana.elegido)
        }
    }

    // ── Fondo: nítido, como la pantalla de bloqueo ───────────────────────
    Image {
        anchors.fill: parent
        source: sistema.fondo.length > 0 ? "file://" + sistema.fondo : ""
        sourceSize: Qt.size(ventana.width, ventana.height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: parent.height * 0.42
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.30) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
        }
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: parent.height * 0.45
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.42) }
        }
    }

    // ── Reloj ────────────────────────────────────────────────────────────
    Column {
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.10
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4
        Text {
            id: fecha
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#e2e6f0"
            font.pixelSize: 18
            font.weight: Font.Medium
        }
        Text {
            id: hora
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#ffffff"
            font.pixelSize: 76
            font.weight: Font.Light
            font.letterSpacing: -1.5
        }
        Timer {
            interval: 1000; running: true; repeat: true; triggeredOnStart: true
            onTriggered: {
                var ahora = new Date()
                hora.text = Qt.formatTime(ahora, "hh:mm")
                var f = ahora.toLocaleDateString(Qt.locale("es_ES"), "dddd, d 'de' MMMM")
                fecha.text = f.charAt(0).toUpperCase() + f.slice(1)
            }
        }
    }

    // ── Cuenta elegida ───────────────────────────────────────────────────
    Item {
        id: tarjeta
        width: 320
        height: 250
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 20
        property real desvio: 0
        x: (parent.width - width) / 2 + desvio

        Column {
            anchors.fill: parent
            spacing: 14

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96; height: 96; radius: 48
                color: ventana.cuenta ? ventana.colorDe(ventana.cuenta.nombre) : "#1e2433"
                border.color: Qt.rgba(1, 1, 1, 0.28)
                border.width: 2.5
                Text {
                    anchors.centerIn: parent
                    text: ventana.cuenta ? ventana.cuenta.nombre.charAt(0).toUpperCase() : "?"
                    color: "#ffffff"
                    font.pixelSize: 44
                    font.bold: true
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ventana.cuenta ? ventana.cuenta.nombre : "No hay cuentas en este sistema"
                color: "#ffffff"
                font.pixelSize: 18
                font.bold: true
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 240
                height: 36
                radius: 18
                visible: ventana.cuenta !== null && !ventana.conSesion
                color: Qt.rgba(0, 0, 0, 0.24)
                border.color: ventana.hayError ? "#ff453a" : (clave.activeFocus ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.24))
                border.width: clave.activeFocus || ventana.hayError ? 1.5 : 1

                TextField {
                    id: clave
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: flecha.left
                    anchors.verticalCenter: parent.verticalCenter
                    echoMode: TextInput.Password
                    placeholderText: greetd.ocupado ? "Entrando…" : "Contraseña"
                    enabled: !greetd.ocupado
                    color: "#ffffff"
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)
                    font.pixelSize: 13
                    background: null
                    focus: true
                    onTextChanged: if (text.length > 0) ventana.hayError = false
                    onAccepted: ventana.entrar()
                }

                Rectangle {
                    id: flecha
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26; height: 26; radius: 13
                    color: flechaRaton.pressed ? "#0062cc" : (clave.text.length > 0 ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.2))
                    Image { anchors.centerIn: parent; width: 15; height: 15; source: "qrc:/icons/simbolos/flecha.svg"; sourceSize: Qt.size(30, 30) }
                    MouseArea {
                        id: flechaRaton
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ventana.entrar()
                    }
                }
            }

            // Cuenta con la sesion abierta: volver a ella (pide su contrasena
            // en su pantalla de bloqueo, que sigue puesta)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: ventana.conSesion
                width: volverTexto.implicitWidth + 36
                height: 36
                radius: 18
                color: volverRaton.pressed ? "#0062cc" : (volverRaton.containsMouse ? "#2b95ff" : "#0a84ff")
                Text {
                    id: volverTexto
                    anchors.centerIn: parent
                    text: "Volver a su sesión"
                    color: "#ffffff"
                    font.pixelSize: 13
                    font.bold: true
                }
                MouseArea {
                    id: volverRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ventana.volver()
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: ventana.conSesion
                text: "La sesión ya está abierta"
                color: "#ffffff"
                font.pixelSize: 12
                font.bold: true
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.45)
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: ventana.textoError
                color: "#ff453a"
                font.pixelSize: 12
                font.bold: true
                opacity: ventana.hayError ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }
    }

    SequentialAnimation {
        id: sacudida
        NumberAnimation { target: tarjeta; property: "desvio"; to: -14; duration: 50 }
        NumberAnimation { target: tarjeta; property: "desvio"; to: 14; duration: 50 }
        NumberAnimation { target: tarjeta; property: "desvio"; to: -9; duration: 50 }
        NumberAnimation { target: tarjeta; property: "desvio"; to: 9; duration: 50 }
        NumberAnimation { target: tarjeta; property: "desvio"; to: 0; duration: 40 }
    }

    // ── Resto de cuentas ─────────────────────────────────────────────────
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: pieEnergia.top
        anchors.bottomMargin: 36
        spacing: 22
        visible: usuarios.usuarios.length > 1

        Repeater {
            model: usuarios.usuarios
            Column {
                spacing: 6
                opacity: modelData.usuario === ventana.elegido ? 1 : (otraRaton.containsMouse ? 0.95 : 0.65)
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 52; height: 52; radius: 26
                    color: ventana.colorDe(modelData.nombre)
                    border.width: modelData.usuario === ventana.elegido ? 2.5 : 0
                    border.color: "#ffffff"
                    Text {
                        anchors.centerIn: parent
                        text: modelData.nombre.charAt(0).toUpperCase()
                        color: "#ffffff"; font.pixelSize: 22; font.bold: true
                    }
                    // Sesion abierta
                    Rectangle {
                        visible: sistema.sesiones[modelData.usuario] !== undefined
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: 14; height: 14; radius: 7
                        color: "#30d158"
                        border.color: "#ffffff"
                        border.width: 2
                    }
                    MouseArea {
                        id: otraRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ventana.elegir(modelData.usuario)
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.nombre
                    color: "#e2e6f0"
                    font.pixelSize: 12
                }
            }
        }
    }

    // ── Pie: usuarios y grupos, energia ──────────────────────────────────
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 28
        width: gestionTexto.implicitWidth + 30
        height: 34
        radius: 17
        visible: usuarios.gestionDisponible
        color: gestionRaton.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.16)
        border.color: Qt.rgba(1, 1, 1, 0.30)
        Row {
            id: gestionTexto
            anchors.centerIn: parent
            spacing: 8
            Image { anchors.verticalCenter: parent.verticalCenter; width: 17; height: 17; source: "qrc:/icons/simbolos/usuarios.svg"; sourceSize: Qt.size(34, 34) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Usuarios y grupos"; color: "#ffffff"; font.pixelSize: 13 }
        }
        MouseArea {
            id: gestionRaton
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { usuarios.recargar(); ventana.panelAbierto = true }
        }
    }

    Row {
        id: pieEnergia
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 36

        Repeater {
            model: [
                { icono: "qrc:/icons/simbolos/reposo.svg", texto: "Reposo", accion: "suspender" },
                { icono: "qrc:/icons/simbolos/reiniciar.svg", texto: "Reiniciar", accion: "reiniciar" },
                { icono: "qrc:/icons/simbolos/apagar.svg", texto: "Apagar", accion: "apagar" }
            ]
            Column {
                spacing: 6
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 40; height: 40; radius: 20
                    color: energiaRaton.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.16)
                    border.color: Qt.rgba(1, 1, 1, 0.30)
                    Image { anchors.centerIn: parent; width: 20; height: 20; source: modelData.icono; sourceSize: Qt.size(40, 40) }
                    MouseArea {
                        id: energiaRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sistema[modelData.accion]()
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.texto
                    color: "#c0c4d2"
                    font.pixelSize: 11
                }
            }
        }
    }

    Loader {
        id: cargador
        anchors.fill: parent
        active: ventana.panelAbierto
        source: "qrc:/qml/PanelUsuarios.qml"
        onLoaded: item.forceActiveFocus()
        Connections {
            target: cargador.item
            function onCerrar() {
                ventana.panelAbierto = false
                usuarios.recargar()
                clave.forceActiveFocus()
            }
        }
    }
}
