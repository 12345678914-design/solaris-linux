// Ajustes > Usuarios y grupos.
//  - Cualquiera: cambiar su propia contraseña (con la actual).
//  - Administradores (grupo wheel), tras desbloquear con su contraseña:
//    añadir cuentas, cambiar contraseñas, hacer/quitar administrador,
//    grupos y borrar cuentas (no la propia ni una con la sesión abierta).
// Todo pasa por titan-usuarios-helper (root), que vuelve a comprobarlo.
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Usuarios y grupos"
    descripcion: "Las cuentas de las personas que usan este equipo."
    mensaje: textoAviso

    TitanTheme { id: tema }

    property string textoAviso: ""
    onMensajeCerrado: textoAviso = ""

    readonly property string yo: usuarios.usuarioActual()
    readonly property bool soyAdmin: usuarios.administradores.indexOf(yo) >= 0
    readonly property bool desbloqueado: usuarios.adminActivo.length > 0
    property var miCuenta: {
        for (var i = 0; i < usuarios.usuarios.length; ++i)
            if (usuarios.usuarios[i].usuario === yo) return usuarios.usuarios[i]
        return ({ usuario: yo, nombre: yo, esAdmin: false, grupos: [] })
    }
    readonly property var otras: usuarios.usuarios.filter(function (u) { return u.usuario !== vista.yo })
    // Grupos de personas (no wheel: eso es "administrador")
    readonly property var gruposPropios: usuarios.grupos.filter(function (g) { return g.grupo !== "wheel" })

    property string expandido: ""        // cuenta con el panel de cambios abierto
    property string borrando: ""         // cuenta pendiente de confirmar borrado
    property bool formNueva: false
    property bool formMiClave: false

    Component.onCompleted: usuarios.recargar()
    Component.onDestruction: usuarios.cerrarAdmin()

    Connections {
        target: usuarios
        function onTerminado(accion, ok, error) {
            var textos = {
                "verificar": "Desbloqueado: ya puedes hacer cambios",
                "crear-usuario": "Cuenta creada. Ya aparece en la pantalla de inicio.",
                "cambiar-clave": "Contraseña cambiada",
                "cambiar-mi-clave": "Tu contraseña se ha cambiado",
                "borrar-usuario": "Cuenta borrada",
                "agregar-a-grupo": "Cambios guardados",
                "quitar-de-grupo": "Cambios guardados",
                "crear-grupo": "Grupo creado",
                "cambiar-nombre": "Nombre cambiado"
            }
            vista.textoAviso = ok ? (textos[accion] || "Hecho") : error
            if (ok) {
                if (accion === "crear-usuario") { vista.formNueva = false; nuevoNombre.limpiar(); nuevoUsuario.limpiar(); nuevaClave.limpiar(); nuevaClave2.limpiar() }
                if (accion === "cambiar-mi-clave") { vista.formMiClave = false; claveActual.limpiar(); claveNueva.limpiar(); claveNueva2.limpiar() }
                if (accion === "borrar-usuario") { vista.borrando = ""; vista.expandido = "" }
                if (accion === "verificar") claveAdmin.limpiar()
            }
        }
    }

    // Usuario a partir del nombre: "Ana María" -> "anamaria"
    function sugerirUsuario(nombre) {
        var s = nombre.normalize ? nombre.normalize("NFD") : nombre
        s = s.toLowerCase().replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]/g, "")
        if (s.length > 0 && !/^[a-z_]/.test(s)) s = "u" + s
        return s.substring(0, 24)
    }

    component Avatar: Rectangle {
        property string nombre: ""
        property int tam: 36
        width: tam; height: tam; radius: tam / 2
        color: {
            var colores = ["#0a84ff", "#30d158", "#ff9f0a", "#bf5af2", "#ff375f", "#64d2ff", "#ffd60a"]
            var h = 0
            for (var i = 0; i < nombre.length; ++i) h = (h * 31 + nombre.charCodeAt(i)) % 997
            return colores[h % colores.length]
        }
        Text {
            anchors.centerIn: parent
            text: parent.nombre.length > 0 ? parent.nombre[0].toUpperCase() : "?"
            color: "#ffffff"
            font.pixelSize: parent.tam * 0.42
            font.bold: true
        }
    }

    // ---------------------------------------------------------- Tu cuenta
    Grupo {
        etiqueta: "Tu cuenta"
        Item {
            width: parent.width
            height: 64
            Avatar { x: 16; anchors.verticalCenter: parent.verticalCenter; nombre: vista.miCuenta.nombre; tam: 42 }
            Column {
                x: 70
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { text: vista.miCuenta.nombre; color: tema.contentTextPrimary; font.pixelSize: 14; font.bold: true }
                Text {
                    text: vista.yo + " · " + (vista.soyAdmin ? "Administrador" : "Estándar")
                    color: tema.contentTextSecondary
                    font.pixelSize: 11
                }
            }
            Boton {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                texto: vista.formMiClave ? "Cancelar" : "Cambiar contraseña…"
                onPulsado: { vista.formMiClave = !vista.formMiClave; if (vista.formMiClave) claveActual.enfocar() }
            }
        }
        Column {
            visible: vista.formMiClave
            width: parent.width
            Fila {
                titulo: "Contraseña actual"
                Campo { id: claveActual; secreto: true; anchors.verticalCenter: parent.verticalCenter; onAceptado: claveNueva.enfocar() }
            }
            Fila {
                titulo: "Contraseña nueva"
                detalle: claveNueva.texto.length > 0 && claveNueva.texto.length < 6 ? "Muy corta: mejor 8 caracteres o más" : ""
                Campo { id: claveNueva; secreto: true; anchors.verticalCenter: parent.verticalCenter; onAceptado: claveNueva2.enfocar() }
            }
            Fila {
                titulo: "Repite la contraseña nueva"
                detalle: claveNueva2.texto.length > 0 && claveNueva2.texto !== claveNueva.texto ? "No coinciden" : ""
                separador: false
                Campo { id: claveNueva2; secreto: true; anchors.verticalCenter: parent.verticalCenter; onAceptado: guardarMiClave.pulsado() }
                Boton {
                    id: guardarMiClave
                    anchors.verticalCenter: parent.verticalCenter
                    texto: usuarios.ocupado ? "Guardando…" : "Guardar"
                    principal: true
                    habilitado: !usuarios.ocupado && claveActual.texto.length > 0 && claveNueva.texto.length >= 4
                                && claveNueva.texto === claveNueva2.texto
                    onPulsado: if (habilitado) usuarios.cambiarMiClave(claveActual.texto, claveNueva.texto)
                }
            }
        }
    }

    // ---------------------------------------------------------- Desbloquear
    Grupo {
        visible: !usuarios.gestionDisponible
        Fila {
            titulo: "El servicio de usuarios no está disponible"
            detalle: "Falta titan-usuarios.socket: no se pueden hacer cambios desde aquí."
            separador: false
        }
    }

    Grupo {
        visible: usuarios.gestionDisponible && !vista.soyAdmin
        Fila {
            titulo: "Para añadir o borrar cuentas hace falta un administrador"
            detalle: "Tu cuenta es estándar: puedes cambiar tu contraseña. Pide a un administrador que haga los demás cambios."
            separador: false
        }
    }

    Grupo {
        visible: usuarios.gestionDisponible && vista.soyAdmin
        etiqueta: "Administración"
        Fila {
            titulo: vista.desbloqueado ? "Desbloqueado" : "Bloqueado"
            detalle: vista.desbloqueado ? "Puedes añadir, cambiar y borrar cuentas" : "Escribe tu contraseña para hacer cambios"
            separador: false
            Campo {
                id: claveAdmin
                visible: !vista.desbloqueado
                secreto: true
                pista: "Tu contraseña"
                ancho: 170
                anchors.verticalCenter: parent.verticalCenter
                onAceptado: desbloquear.pulsado()
            }
            Boton {
                id: desbloquear
                anchors.verticalCenter: parent.verticalCenter
                texto: vista.desbloqueado ? "🔓 Bloquear" : (usuarios.ocupado ? "Comprobando…" : "🔒 Desbloquear")
                principal: !vista.desbloqueado
                habilitado: !usuarios.ocupado
                onPulsado: {
                    if (vista.desbloqueado) usuarios.cerrarAdmin()
                    else if (claveAdmin.texto.length > 0) usuarios.iniciarAdmin(vista.yo, claveAdmin.texto)
                }
            }
        }
    }

    // ---------------------------------------------------------- Otras cuentas
    Grupo {
        etiqueta: "Otras cuentas"
        nota: vista.otras.length === 0 ? "No hay más cuentas en este equipo." : ""
        Repeater {
            model: vista.otras
            delegate: Column {
                id: cuenta
                required property var modelData
                required property int index
                width: parent ? parent.width : 400
                readonly property bool abierto: vista.expandido === modelData.usuario && vista.desbloqueado
                Item {
                    width: parent.width
                    height: 56
                    Avatar { x: 16; anchors.verticalCenter: parent.verticalCenter; nombre: cuenta.modelData.nombre }
                    Column {
                        x: 62
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text { text: cuenta.modelData.nombre; color: tema.contentTextPrimary; font.pixelSize: 12; font.bold: true }
                        Text {
                            text: cuenta.modelData.usuario + " · " + (cuenta.modelData.esAdmin ? "Administrador" : "Estándar")
                            color: tema.contentTextSecondary
                            font.pixelSize: 11
                        }
                    }
                    Boton {
                        visible: vista.desbloqueado
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        texto: cuenta.abierto ? "Cerrar" : "Cambiar…"
                        onPulsado: { vista.expandido = cuenta.abierto ? "" : cuenta.modelData.usuario; vista.borrando = "" }
                    }
                }
                // Panel de cambios
                Column {
                    visible: cuenta.abierto
                    width: parent.width
                    Fila {
                        titulo: "Nueva contraseña"
                        Campo { id: otraClave; secreto: true; ancho: 170; anchors.verticalCenter: parent.verticalCenter }
                        Boton {
                            anchors.verticalCenter: parent.verticalCenter
                            texto: "Cambiar"
                            habilitado: otraClave.texto.length >= 4 && !usuarios.ocupado
                            onPulsado: { usuarios.cambiarClave(cuenta.modelData.usuario, otraClave.texto); otraClave.limpiar() }
                        }
                    }
                    Fila {
                        titulo: "Administrador"
                        detalle: "Puede instalar programas y cambiar el sistema"
                        Interruptor {
                            anchors.verticalCenter: parent.verticalCenter
                            activo: cuenta.modelData.esAdmin
                            habilitado: !usuarios.ocupado
                            onAlternado: (v) => v ? usuarios.agregarAGrupo(cuenta.modelData.usuario, "wheel")
                                                  : usuarios.quitarDeGrupo(cuenta.modelData.usuario, "wheel")
                        }
                    }
                    Fila {
                        visible: vista.gruposPropios.length > 0
                        titulo: "Grupos"
                        detalle: "Pulsa un grupo para añadir o quitar"
                        Flow {
                            width: Math.min(320, cuenta.width * 0.5)
                            spacing: 6
                            Repeater {
                                model: vista.gruposPropios
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool dentro: cuenta.modelData.grupos.indexOf(modelData.grupo) >= 0
                                    width: textoGrupo.implicitWidth + 18
                                    height: 22
                                    radius: 11
                                    color: dentro ? tema.accent : "transparent"
                                    border.color: dentro ? tema.accent : tema.contentCardBorder
                                    border.width: 1
                                    Text {
                                        id: textoGrupo
                                        anchors.centerIn: parent
                                        text: modelData.grupo
                                        color: parent.dentro ? "#ffffff" : tema.contentTextPrimary
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: parent.dentro ? usuarios.quitarDeGrupo(cuenta.modelData.usuario, modelData.grupo)
                                                                 : usuarios.agregarAGrupo(cuenta.modelData.usuario, modelData.grupo)
                                    }
                                }
                            }
                        }
                    }
                    Fila {
                        titulo: vista.borrando === cuenta.modelData.usuario ? "¿Borrar la cuenta de " + cuenta.modelData.nombre + "?" : "Borrar esta cuenta"
                        detalle: vista.borrando === cuenta.modelData.usuario
                                 ? "No se puede deshacer. Elige si se borran también sus archivos (carpeta personal)."
                                 : "Tiene que tener la sesión cerrada"
                        separador: false
                        Boton {
                            visible: vista.borrando !== cuenta.modelData.usuario
                            anchors.verticalCenter: parent.verticalCenter
                            texto: "Borrar…"
                            peligro: true
                            onPulsado: vista.borrando = cuenta.modelData.usuario
                        }
                        Boton {
                            visible: vista.borrando === cuenta.modelData.usuario
                            anchors.verticalCenter: parent.verticalCenter
                            texto: "Cancelar"
                            onPulsado: vista.borrando = ""
                        }
                        Boton {
                            visible: vista.borrando === cuenta.modelData.usuario
                            anchors.verticalCenter: parent.verticalCenter
                            texto: "Borrar y conservar archivos"
                            peligro: true
                            habilitado: !usuarios.ocupado
                            onPulsado: usuarios.borrarUsuario(cuenta.modelData.usuario, false)
                        }
                        Boton {
                            visible: vista.borrando === cuenta.modelData.usuario
                            anchors.verticalCenter: parent.verticalCenter
                            texto: "Borrar todo"
                            peligro: true
                            habilitado: !usuarios.ocupado
                            onPulsado: usuarios.borrarUsuario(cuenta.modelData.usuario, true)
                        }
                    }
                }
                Rectangle {
                    visible: cuenta.index < vista.otras.length - 1
                    x: 16; width: parent.width - 32; height: 1
                    color: tema.contentCardBorder
                }
            }
        }
    }

    Row {
        visible: vista.desbloqueado && !vista.formNueva
        spacing: 8
        Boton { texto: "＋ Añadir usuario…"; principal: true; onPulsado: { vista.formNueva = true; nuevoNombre.enfocar() } }
    }

    // ---------------------------------------------------------- Nueva cuenta
    Grupo {
        visible: vista.desbloqueado && vista.formNueva
        etiqueta: "Nueva cuenta"
        Fila {
            titulo: "Nombre completo"
            Campo {
                id: nuevoNombre
                anchors.verticalCenter: parent.verticalCenter
                pista: "Ana García"
                onTextoChanged: if (!nuevoUsuario.tocado) nuevoUsuario.texto = vista.sugerirUsuario(texto)
                onAceptado: nuevoUsuario.enfocar()
            }
        }
        Fila {
            titulo: "Nombre de usuario"
            detalle: "Minúsculas y números; con él se entra al equipo"
            Campo {
                id: nuevoUsuario
                property bool tocado: false
                anchors.verticalCenter: parent.verticalCenter
                pista: "ana"
                onAceptado: { tocado = true; nuevaClave.enfocar() }
            }
        }
        Fila {
            titulo: "Contraseña"
            Campo { id: nuevaClave; secreto: true; anchors.verticalCenter: parent.verticalCenter; onAceptado: nuevaClave2.enfocar() }
        }
        Fila {
            titulo: "Repite la contraseña"
            detalle: nuevaClave2.texto.length > 0 && nuevaClave2.texto !== nuevaClave.texto ? "No coinciden" : ""
            Campo { id: nuevaClave2; secreto: true; anchors.verticalCenter: parent.verticalCenter }
        }
        Fila {
            titulo: "Administrador"
            detalle: "Podrá instalar programas y gestionar otras cuentas"
            Interruptor { id: nuevaAdmin; anchors.verticalCenter: parent.verticalCenter; onAlternado: (v) => activo = v }
        }
        Fila {
            titulo: ""
            separador: false
            Boton { anchors.verticalCenter: parent.verticalCenter; texto: "Cancelar"; onPulsado: vista.formNueva = false }
            Boton {
                anchors.verticalCenter: parent.verticalCenter
                texto: usuarios.ocupado ? "Creando…" : "Crear cuenta"
                principal: true
                habilitado: !usuarios.ocupado && /^[a-z_][a-z0-9_-]{0,31}$/.test(nuevoUsuario.texto)
                            && nuevaClave.texto.length >= 4 && nuevaClave.texto === nuevaClave2.texto
                onPulsado: if (habilitado) usuarios.crearUsuario(nuevoUsuario.texto, nuevoNombre.texto, nuevaClave.texto, nuevaAdmin.activo, [])
            }
        }
    }

    // ---------------------------------------------------------- Grupos
    Grupo {
        visible: vista.desbloqueado
        etiqueta: "Grupos"
        nota: "Sirven para compartir carpetas o permisos entre varias cuentas."
        Repeater {
            model: vista.gruposPropios
            delegate: Fila {
                required property var modelData
                titulo: modelData.grupo
                detalle: modelData.miembros.length > 0 ? modelData.miembros.join(", ") : "Sin miembros"
            }
        }
        Fila {
            titulo: "Nuevo grupo"
            separador: false
            Campo { id: nuevoGrupo; ancho: 160; pista: "familia"; anchors.verticalCenter: parent.verticalCenter }
            Boton {
                anchors.verticalCenter: parent.verticalCenter
                texto: "Crear grupo"
                habilitado: /^[a-z_][a-z0-9_-]{0,31}$/.test(nuevoGrupo.texto) && !usuarios.ocupado
                onPulsado: { usuarios.crearGrupo(nuevoGrupo.texto); nuevoGrupo.limpiar() }
            }
        }
    }
}
