// Ajustes > Wi-Fi: redes cercanas y redes conocidas (con su contraseña
// guardada en NetworkManager: no se vuelve a pedir).
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Wi-Fi"
    descripcion: "Al conectarte a una red, su contraseña queda guardada y el equipo se vuelve a conectar solo."
    mensaje: conexiones.mensaje
    onMensajeCerrado: conexiones.limpiarMensaje()

    TitanTheme { id: tema }

    property string pidiendo: ""          // red a la que se le está pidiendo contraseña
    property string claveVisible: ""      // uuid cuya contraseña se ve
    property string claveTexto: ""
    property bool formOculta: false

    Component.onCompleted: { conexiones.leerWifi(); conexiones.escanear() }
    Timer { running: conexiones.wifiActivo; repeat: true; interval: 20000; onTriggered: conexiones.escanear() }

    Connections {
        target: conexiones
        function onClaveLeida(uuid, clave) { vista.claveVisible = uuid; vista.claveTexto = clave }
    }

    function elegirRed(red) {
        if (red.conectada) return
        // Conocida o abierta: directamente. Nueva con seguridad: pedir contraseña.
        if (red.conocida || red.seguridad === "") { vista.pidiendo = ""; conexiones.conectar(red.ssid, "") }
        else vista.pidiendo = red.ssid
    }

    component Senal: Canvas {
        property int nivel: 100
        property color colorOn: tema.contentTextPrimary
        width: 18; height: 14
        onNivelChanged: requestPaint()
        onColorOnChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.reset()
            var barras = nivel > 75 ? 3 : nivel > 45 ? 2 : nivel > 20 ? 1 : 0
            for (var i = 0; i < 3; ++i) {
                ctx.strokeStyle = i < barras ? colorOn : Qt.rgba(colorOn.r, colorOn.g, colorOn.b, 0.25)
                ctx.lineWidth = 1.8; ctx.lineCap = "round"
                ctx.beginPath()
                ctx.arc(9, 13, 3 + i * 4, Math.PI * 1.25, Math.PI * 1.75)
                ctx.stroke()
            }
            ctx.fillStyle = colorOn
            ctx.beginPath(); ctx.arc(9, 12.5, 1.4, 0, Math.PI * 2); ctx.fill()
        }
    }

    Grupo {
        Fila {
            titulo: "Wi-Fi"
            detalle: !conexiones.hayWifi ? "No se encuentra ninguna tarjeta Wi-Fi"
                     : conexiones.redActual !== "" ? "Conectado a " + conexiones.redActual
                     : conexiones.wifiActivo ? "Sin conectar" : "Apagado"
            separador: false
            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                habilitado: conexiones.hayWifi
                activo: conexiones.wifiActivo
                onAlternado: (v) => conexiones.setWifi(v)
            }
        }
    }

    Grupo {
        visible: conexiones.wifiActivo
        etiqueta: conexiones.escaneando ? "Redes cercanas · buscando…" : "Redes cercanas"
        nota: conexiones.redes.length === 0 && !conexiones.escaneando ? "No se ve ninguna red." : ""
        Repeater {
            model: conexiones.redes
            delegate: Column {
                id: red
                required property var modelData
                required property int index
                width: parent ? parent.width : 400
                Fila {
                    titulo: red.modelData.ssid
                    detalle: (red.modelData.conectada ? "Conectada" : conexiones.conectando === red.modelData.ssid ? "Conectando…"
                              : red.modelData.conocida ? "Conocida · contraseña guardada" : "")
                             + (red.modelData.seguridad !== "" ? (red.modelData.conectada || red.modelData.conocida || conexiones.conectando === red.modelData.ssid ? " · " : "") + "🔒 " + red.modelData.seguridad : "")
                    separador: red.index < conexiones.redes.length - 1 || vista.pidiendo === red.modelData.ssid
                    Senal { anchors.verticalCenter: parent.verticalCenter; nivel: red.modelData.senal; colorOn: red.modelData.conectada ? tema.accent : tema.contentTextPrimary }
                    Boton {
                        visible: !red.modelData.conectada
                        anchors.verticalCenter: parent.verticalCenter
                        texto: conexiones.conectando === red.modelData.ssid ? "Conectando…" : "Conectar"
                        habilitado: conexiones.conectando === ""
                        onPulsado: vista.elegirRed(red.modelData)
                    }
                    Boton {
                        visible: red.modelData.conectada
                        anchors.verticalCenter: parent.verticalCenter
                        texto: "Desconectar"
                        onPulsado: conexiones.desconectar()
                    }
                }
                Fila {
                    visible: vista.pidiendo === red.modelData.ssid
                    titulo: "Contraseña de " + red.modelData.ssid
                    detalle: "Se guardará para la próxima vez"
                    separador: red.index < conexiones.redes.length - 1
                    onVisibleChanged: if (visible) { claveRed.limpiar(); claveRed.enfocar() }
                    Campo {
                        id: claveRed
                        secreto: !verClaveRed.activo
                        anchors.verticalCenter: parent.verticalCenter
                        ancho: 180
                        onAceptado: unir.pulsado()
                    }
                    Interruptor { id: verClaveRed; anchors.verticalCenter: parent.verticalCenter; onAlternado: (v) => activo = v }
                    Boton {
                        id: unir
                        anchors.verticalCenter: parent.verticalCenter
                        texto: "Unirse"
                        principal: true
                        habilitado: claveRed.texto.length >= 8
                        onPulsado: if (habilitado) { conexiones.conectar(red.modelData.ssid, claveRed.texto); vista.pidiendo = ""; claveRed.limpiar() }
                    }
                }
            }
        }
    }

    Row {
        visible: conexiones.wifiActivo
        spacing: 8
        Boton { texto: conexiones.escaneando ? "Buscando…" : "Buscar redes"; habilitado: !conexiones.escaneando; onPulsado: conexiones.escanear() }
        Boton { texto: "Unirse a otra red…"; onPulsado: vista.formOculta = !vista.formOculta }
    }

    Grupo {
        visible: vista.formOculta && conexiones.wifiActivo
        etiqueta: "Red oculta"
        Fila {
            titulo: "Nombre de la red (SSID)"
            Campo { id: ocultaSsid; anchors.verticalCenter: parent.verticalCenter }
        }
        Fila {
            titulo: "Contraseña"
            detalle: "Déjala vacía si la red es abierta"
            separador: false
            Campo { id: ocultaClave; secreto: true; anchors.verticalCenter: parent.verticalCenter }
            Boton {
                anchors.verticalCenter: parent.verticalCenter
                texto: "Unirse"
                principal: true
                habilitado: ocultaSsid.texto.length > 0 && (ocultaClave.texto.length === 0 || ocultaClave.texto.length >= 8)
                onPulsado: { conexiones.unirseOculta(ocultaSsid.texto, ocultaClave.texto); vista.formOculta = false; ocultaClave.limpiar() }
            }
        }
    }

    Grupo {
        etiqueta: "Redes conocidas"
        nota: conexiones.conocidas.length === 0 ? "Aún no hay redes guardadas." : "Olvidar una red borra su contraseña guardada."
        Repeater {
            model: conexiones.conocidas
            delegate: Column {
                id: conocida
                required property var modelData
                required property int index
                width: parent ? parent.width : 400
                Fila {
                    titulo: conocida.modelData.ssid + (conocida.modelData.activa ? "  ·  conectada" : "")
                    detalle: vista.claveVisible === conocida.modelData.uuid ? "Contraseña: " + vista.claveTexto
                             : (conocida.modelData.ultima > 0 ? "Última vez: " + new Date(conocida.modelData.ultima * 1000).toLocaleDateString(Qt.locale(), "d MMM yyyy") : "")
                    separador: conocida.index < conexiones.conocidas.length - 1
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Auto"
                        color: tema.contentTextSecondary
                        font.pixelSize: 10
                    }
                    Interruptor {
                        anchors.verticalCenter: parent.verticalCenter
                        activo: conocida.modelData.autoconectar === true
                        onAlternado: (v) => conexiones.setAutoconectar(conocida.modelData.uuid, v)
                    }
                    Boton {
                        anchors.verticalCenter: parent.verticalCenter
                        texto: vista.claveVisible === conocida.modelData.uuid ? "Ocultar" : "Ver contraseña"
                        onPulsado: {
                            if (vista.claveVisible === conocida.modelData.uuid) { vista.claveVisible = ""; vista.claveTexto = "" }
                            else conexiones.verClave(conocida.modelData.uuid)
                        }
                    }
                    Boton {
                        anchors.verticalCenter: parent.verticalCenter
                        texto: "Olvidar"
                        peligro: true
                        onPulsado: conexiones.olvidar(conocida.modelData.uuid)
                    }
                }
            }
        }
    }
}
