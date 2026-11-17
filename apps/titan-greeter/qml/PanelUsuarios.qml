import QtQuick
import QtQuick.Controls

// Usuarios y grupos (compartido por titan-greeter y la pantalla de bloqueo de
// titan-shell). Necesita en el contexto el objeto 'usuarios' (clase Usuarios).
//
// 1. Un administrador (grupo wheel) se identifica con su contrasena.
// 2. Puede crear cuentas (normales o de administrador), crear grupos,
//    meter y sacar gente de los grupos y cambiar contrasenas.
// Al cerrar el panel se olvida la contrasena del administrador.
Item {
    id: panel
    anchors.fill: parent

    signal cerrar()

    property string mensaje: ""
    property bool mensajeOk: true
    property int pestana: 0
    property string usuarioSel: ""
    property string grupoSel: ""

    function salir() {
        usuarios.cerrarAdmin()
        claveAdmin.text = ""
        mensaje = ""
        panel.cerrar()
    }

    function datosUsuario(nombre) {
        var l = usuarios.usuarios
        for (var i = 0; i < l.length; ++i)
            if (l[i].usuario === nombre) return l[i]
        return null
    }

    function datosGrupo(nombre) {
        var l = usuarios.grupos
        for (var i = 0; i < l.length; ++i)
            if (l[i].grupo === nombre) return l[i]
        return null
    }

    // Propone un nombre de cuenta a partir del nombre completo.
    function sugerirUsuario(nombre) {
        var s = nombre.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
        s = s.split(" ")[0].replace(/[^a-z0-9_-]/g, "")
        if (s.length > 0 && !/^[a-z_]/.test(s)) s = "u" + s
        return s.substring(0, 32)
    }

    Connections {
        target: usuarios
        function onTerminado(accion, ok, error) {
            panel.mensajeOk = ok
            if (!ok) { panel.mensaje = error; return }
            if (accion === "verificar") { panel.mensaje = ""; claveAdmin.text = ""; return }
            if (accion === "crear-usuario") {
                panel.mensaje = "Cuenta creada: ya puede iniciar sesión"
                panel.usuarioSel = nuevoUsuario.text
                nuevoNombre.text = ""; nuevoUsuario.text = ""; nuevaClave.text = ""; nuevaClave2.text = ""
                nuevoAdmin.checked = false
            } else if (accion === "crear-grupo") {
                panel.mensaje = "Grupo creado"
                panel.grupoSel = nuevoGrupo.text
                nuevoGrupo.text = ""
            } else if (accion === "cambiar-clave") {
                panel.mensaje = "Contraseña cambiada"
                claveCambio.text = ""
            } else {
                panel.mensaje = "Hecho"
            }
        }
    }

    // ── Piezas con el estilo de la pantalla ──────────────────────────────
    component Campo: TextField {
        height: 34
        color: "#ffffff"
        placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)
        font.pixelSize: 13
        leftPadding: 12
        selectByMouse: true
        background: Rectangle {
            radius: 9
            color: Qt.rgba(1, 1, 1, 0.10)
            border.width: parent.activeFocus ? 1.5 : 1
            border.color: parent.activeFocus ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.20)
        }
    }

    component Boton: Rectangle {
        id: boton
        property string texto: ""
        property bool principal: false
        property bool activo: true
        signal pulsado()
        height: 32
        width: Math.max(96, etiqueta.implicitWidth + 28)
        radius: 9
        opacity: activo ? 1 : 0.45
        color: principal ? (zona.pressed ? "#0062cc" : "#0a84ff")
                         : (zona.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.12))
        Text {
            id: etiqueta
            anchors.centerIn: parent
            text: boton.texto
            color: "#ffffff"
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        MouseArea {
            id: zona
            anchors.fill: parent
            hoverEnabled: true
            enabled: boton.activo && !usuarios.ocupado
            cursorShape: Qt.PointingHandCursor
            onClicked: boton.pulsado()
        }
    }

    component Avatar: Rectangle {
        property string nombre: "?"
        width: 34; height: 34; radius: width / 2
        color: {
            var colores = ["#0a84ff", "#30d158", "#ff9f0a", "#bf5af2", "#ff375f", "#64d2ff", "#ffd60a"]
            var h = 0
            for (var i = 0; i < nombre.length; ++i) h = (h * 31 + nombre.charCodeAt(i)) % 997
            return colores[h % colores.length]
        }
        Text {
            anchors.centerIn: parent
            text: parent.nombre.length > 0 ? parent.nombre.charAt(0).toUpperCase() : "?"
            color: "#ffffff"
            font.pixelSize: parent.height * 0.45
            font.bold: true
        }
    }

    // ── Fondo y tarjeta ──────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent }
    }

    Rectangle {
        id: tarjeta
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 820)
        height: Math.min(parent.height - 40, usuarios.adminActivo === "" ? 330 : 600)
        radius: 18
        color: Qt.rgba(0.11, 0.12, 0.16, 0.97)
        border.color: Qt.rgba(1, 1, 1, 0.14)
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // Cabecera
        Item {
            id: cabecera
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            height: 34
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Usuarios y grupos"
                color: "#ffffff"
                font.pixelSize: 19
                font.bold: true
            }
            Text {
                anchors.right: botonCerrar.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: usuarios.adminActivo !== ""
                text: "Autorizado: " + usuarios.adminActivo
                color: "#8e94a6"
                font.pixelSize: 12
            }
            Boton {
                id: botonCerrar
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                texto: "Cerrar"
                onPulsado: panel.salir()
            }
        }

        // ── 1. Autorizacion ─────────────────────────────────────────────
        Column {
            visible: usuarios.adminActivo === ""
            anchors { left: parent.left; right: parent.right; top: cabecera.bottom; margins: 24 }
            anchors.topMargin: 18
            spacing: 12

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: usuarios.gestionDisponible
                      ? "Para crear o cambiar cuentas y grupos, un administrador tiene que confirmar con su contraseña."
                      : "La gestión de usuarios no está disponible en este sistema (falta el servicio titan-usuarios)."
                color: "#c6cad6"
                font.pixelSize: 13
            }
            ComboBox {
                id: elegirAdmin
                width: 280
                model: usuarios.administradores
                enabled: usuarios.gestionDisponible
            }
            Campo {
                id: claveAdmin
                width: 280
                echoMode: TextInput.Password
                placeholderText: "Contraseña del administrador"
                enabled: usuarios.gestionDisponible
                onAccepted: botonAutorizar.pulsado()
            }
            Boton {
                id: botonAutorizar
                texto: usuarios.ocupado ? "Comprobando…" : "Continuar"
                principal: true
                activo: usuarios.gestionDisponible && elegirAdmin.currentText !== "" && claveAdmin.text.length > 0
                onPulsado: { panel.mensaje = ""; usuarios.iniciarAdmin(elegirAdmin.currentText, claveAdmin.text) }
            }
        }

        // ── 2. Gestion ──────────────────────────────────────────────────
        Item {
            visible: usuarios.adminActivo !== ""
            anchors { left: parent.left; right: parent.right; top: cabecera.bottom; bottom: pie.top; margins: 20 }
            anchors.topMargin: 14

            Row {
                id: pestanas
                spacing: 6
                Repeater {
                    model: ["Usuarios", "Grupos"]
                    Rectangle {
                        width: 110; height: 30; radius: 8
                        color: panel.pestana === index ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.08)
                        Text { anchors.centerIn: parent; text: modelData; color: "#ffffff"; font.pixelSize: 13 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: panel.pestana = index }
                    }
                }
            }

            // Lista de la izquierda
            Rectangle {
                id: lista
                anchors { left: parent.left; top: pestanas.bottom; bottom: parent.bottom; topMargin: 12 }
                width: parent.width * 0.46
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.05)

                ListView {
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    spacing: 2
                    model: panel.pestana === 0 ? usuarios.usuarios : usuarios.grupos
                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 50
                        radius: 9
                        readonly property bool sel: panel.pestana === 0 ? panel.usuarioSel === modelData.usuario
                                                                         : panel.grupoSel === modelData.grupo
                        color: sel ? Qt.rgba(0.04, 0.52, 1, 0.30) : (filaRaton.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                        Avatar {
                            id: av
                            anchors.left: parent.left; anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            nombre: panel.pestana === 0 ? modelData.nombre : modelData.grupo
                            radius: panel.pestana === 0 ? width / 2 : 8
                        }
                        Column {
                            anchors.left: av.right; anchors.leftMargin: 10
                            anchors.right: parent.right; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: panel.pestana === 0
                                      ? modelData.nombre + (modelData.esAdmin ? "  · Administrador" : "")
                                      : modelData.grupo + (modelData.grupo === "wheel" ? "  · Administradores" : "")
                                color: "#ffffff"; font.pixelSize: 13; font.weight: Font.Medium
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: panel.pestana === 0
                                      ? "@" + modelData.usuario + " — " + modelData.grupos.join(", ")
                                      : (modelData.miembros.length === 0 ? "Sin miembros" : modelData.miembros.join(", "))
                                color: "#8e94a6"; font.pixelSize: 11
                            }
                        }
                        MouseArea {
                            id: filaRaton
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (panel.pestana === 0) panel.usuarioSel = modelData.usuario
                                else panel.grupoSel = modelData.grupo
                            }
                        }
                    }
                }
            }

            // Formularios de la derecha
            Flickable {
                anchors { left: lista.right; right: parent.right; top: pestanas.bottom; bottom: parent.bottom; leftMargin: 18; topMargin: 12 }
                contentHeight: panel.pestana === 0 ? formUsuarios.height : formGrupos.height
                clip: true

                // Usuarios
                Column {
                    id: formUsuarios
                    visible: panel.pestana === 0
                    width: parent.width
                    spacing: 9

                    Text { text: "Nueva cuenta"; color: "#ffffff"; font.pixelSize: 15; font.bold: true }
                    Campo {
                        id: nuevoNombre
                        width: parent.width
                        placeholderText: "Nombre completo"
                        property string ultimaSugerencia: ""
                        onTextChanged: {
                            var s = panel.sugerirUsuario(text)
                            if (nuevoUsuario.text === "" || nuevoUsuario.text === ultimaSugerencia)
                                nuevoUsuario.text = s
                            ultimaSugerencia = s
                        }
                    }
                    Campo {
                        id: nuevoUsuario
                        width: parent.width
                        placeholderText: "Nombre de usuario (minúsculas)"
                        validator: RegularExpressionValidator { regularExpression: /[a-z_][a-z0-9_-]{0,31}/ }
                    }
                    Campo { id: nuevaClave; width: parent.width; echoMode: TextInput.Password; placeholderText: "Contraseña" }
                    Campo { id: nuevaClave2; width: parent.width; echoMode: TextInput.Password; placeholderText: "Repetir contraseña" }
                    CheckBox {
                        id: nuevoAdmin
                        text: "Administrador (puede instalar programas y gestionar cuentas)"
                        indicator: Rectangle {
                            x: nuevoAdmin.leftPadding
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18; radius: 5
                            color: nuevoAdmin.checked ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.10)
                            border.color: nuevoAdmin.checked ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.35)
                            Text {
                                anchors.centerIn: parent
                                visible: nuevoAdmin.checked
                                text: "✓"; color: "#ffffff"; font.pixelSize: 12; font.bold: true
                            }
                        }
                        contentItem: Text {
                            leftPadding: nuevoAdmin.indicator.width + 6
                            text: nuevoAdmin.text; color: "#c6cad6"; font.pixelSize: 12
                            verticalAlignment: Text.AlignVCenter; wrapMode: Text.WordWrap
                        }
                    }
                    Boton {
                        texto: "Crear cuenta"
                        principal: true
                        activo: nuevoUsuario.acceptableInput && nuevaClave.text.length > 0
                        onPulsado: {
                            if (nuevaClave.text !== nuevaClave2.text) {
                                panel.mensajeOk = false; panel.mensaje = "Las contraseñas no coinciden"; return
                            }
                            panel.mensaje = ""
                            usuarios.crearUsuario(nuevoUsuario.text, nuevoNombre.text, nuevaClave.text, nuevoAdmin.checked, [])
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.10); visible: panel.usuarioSel !== "" }

                    Column {
                        width: parent.width
                        spacing: 9
                        visible: panel.usuarioSel !== ""
                        readonly property var datos: { usuarios.usuarios; return panel.datosUsuario(panel.usuarioSel) }
                        Text {
                            text: "Cuenta @" + panel.usuarioSel
                            color: "#ffffff"; font.pixelSize: 15; font.bold: true
                        }
                        Row {
                            spacing: 8
                            Boton {
                                readonly property bool esAdmin: parent.parent.datos ? parent.parent.datos.esAdmin : false
                                texto: esAdmin ? "Quitar administrador" : "Hacer administrador"
                                activo: panel.usuarioSel !== usuarios.adminActivo || !esAdmin
                                onPulsado: esAdmin ? usuarios.quitarDeGrupo(panel.usuarioSel, "wheel")
                                                   : usuarios.agregarAGrupo(panel.usuarioSel, "wheel")
                            }
                        }
                        Row {
                            spacing: 8
                            width: parent.width
                            Campo {
                                id: claveCambio
                                width: parent.width - 8 - botonClave.width
                                echoMode: TextInput.Password
                                placeholderText: "Nueva contraseña"
                            }
                            Boton {
                                id: botonClave
                                texto: "Cambiar"
                                activo: claveCambio.text.length > 0
                                onPulsado: usuarios.cambiarClave(panel.usuarioSel, claveCambio.text)
                            }
                        }
                    }
                }

                // Grupos
                Column {
                    id: formGrupos
                    visible: panel.pestana === 1
                    width: parent.width
                    spacing: 9

                    Text { text: "Nuevo grupo"; color: "#ffffff"; font.pixelSize: 15; font.bold: true }
                    Row {
                        spacing: 8
                        width: parent.width
                        Campo {
                            id: nuevoGrupo
                            width: parent.width - 8 - botonGrupo.width
                            placeholderText: "Nombre del grupo (minúsculas)"
                            validator: RegularExpressionValidator { regularExpression: /[a-z_][a-z0-9_-]{0,31}/ }
                            onAccepted: botonGrupo.pulsado()
                        }
                        Boton {
                            id: botonGrupo
                            texto: "Crear"
                            principal: true
                            activo: nuevoGrupo.acceptableInput
                            onPulsado: { panel.mensaje = ""; usuarios.crearGrupo(nuevoGrupo.text) }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.10); visible: panel.grupoSel !== "" }

                    Column {
                        id: detalleGrupo
                        width: parent.width
                        spacing: 9
                        visible: panel.grupoSel !== ""
                        readonly property var datos: { usuarios.grupos; return panel.datosGrupo(panel.grupoSel) }
                        readonly property var miembros: datos ? datos.miembros : []
                        readonly property var candidatos: {
                            var l = []
                            var us = usuarios.usuarios
                            for (var i = 0; i < us.length; ++i)
                                if (miembros.indexOf(us[i].usuario) < 0) l.push(us[i].usuario)
                            return l
                        }

                        Text { text: "Miembros de " + panel.grupoSel; color: "#ffffff"; font.pixelSize: 15; font.bold: true }
                        Flow {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: detalleGrupo.miembros
                                Rectangle {
                                    height: 28; radius: 14
                                    width: chipTexto.implicitWidth + 40
                                    color: Qt.rgba(1, 1, 1, 0.10)
                                    Text { id: chipTexto; anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: "#ffffff"; font.pixelSize: 12 }
                                    Text {
                                        anchors.right: parent.right; anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "✕"; color: quitarRaton.containsMouse ? "#ff453a" : "#8e94a6"; font.pixelSize: 11
                                        MouseArea {
                                            id: quitarRaton
                                            anchors.fill: parent; anchors.margins: -6
                                            hoverEnabled: true
                                            enabled: !usuarios.ocupado
                                            onClicked: usuarios.quitarDeGrupo(modelData, panel.grupoSel)
                                        }
                                    }
                                }
                            }
                            Text {
                                visible: detalleGrupo.miembros.length === 0
                                text: "Todavía no hay nadie en este grupo"
                                color: "#8e94a6"; font.pixelSize: 12
                            }
                        }
                        Row {
                            spacing: 8
                            visible: detalleGrupo.candidatos.length > 0
                            ComboBox { id: elegirMiembro; width: 200; model: detalleGrupo.candidatos }
                            Boton {
                                texto: "Añadir"
                                principal: true
                                onPulsado: usuarios.agregarAGrupo(elegirMiembro.currentText, panel.grupoSel)
                            }
                        }
                    }
                }
            }
        }

        // Pie: resultado de la ultima accion
        Text {
            id: pie
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20 }
            height: 20
            text: usuarios.ocupado ? "Aplicando…" : panel.mensaje
            color: usuarios.ocupado ? "#c6cad6" : (panel.mensajeOk ? "#30d158" : "#ff453a")
            font.pixelSize: 12
            font.bold: true
            elide: Text.ElideRight
        }
    }

    Keys.onEscapePressed: salir()
}
