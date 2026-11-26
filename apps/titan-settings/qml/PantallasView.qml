// Ajustes > Pantallas: resolución, escala, giro (wlr-randr), brillo y luz nocturna.
import QtQuick

PaginaAjustes {
    id: vista
    property bool masResoluciones: false
    titulo: "Pantallas"
    descripcion: "Los cambios de resolución hay que confirmarlos: si la imagen no se ve bien, se deshacen solos en 15 segundos."
    mensaje: dispositivos.aviso

    TitanTheme { id: tema }

    Component.onCompleted: { dispositivos.leerPantallas(); dispositivos.leerBrillo() }

    property int cuenta: 15
    Timer {
        running: dispositivos.pendienteConfirmar
        interval: 1000
        repeat: true
        onRunningChanged: vista.cuenta = 15
        onTriggered: vista.cuenta = Math.max(0, vista.cuenta - 1)
    }

    // Confirmar o deshacer
    Rectangle {
        visible: dispositivos.pendienteConfirmar
        width: parent.width
        height: 58
        radius: 10
        color: Qt.rgba(tema.accent.r, tema.accent.g, tema.accent.b, 0.14)
        border.color: tema.accent
        border.width: 1
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "¿Mantener esta configuración? Se deshace en " + vista.cuenta + " s"
            color: tema.contentTextPrimary
            font.pixelSize: 12
            font.bold: true
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Boton { texto: "Deshacer"; onPulsado: dispositivos.deshacerPantallas() }
            Boton { texto: "Mantener"; principal: true; onPulsado: dispositivos.confirmarPantallas() }
        }
    }

    Grupo {
        visible: !dispositivos.pantallasDisponibles
        etiqueta: "Pantallas"
        Fila {
            titulo: "No se pueden leer las pantallas"
            detalle: "Hace falta wlr-randr y una sesión Wayland (Wayfire o labwc)."
            separador: false
            Boton { anchors.verticalCenter: parent.verticalCenter; texto: "Reintentar"; onPulsado: dispositivos.leerPantallas() }
        }
    }

    Repeater {
        model: dispositivos.pantallas
        delegate: Grupo {
            id: grupoPantalla
            required property var modelData
            width: vista.width - 48
            etiqueta: modelData.nombre + (modelData.descripcion ? " · " + modelData.descripcion : "")
                      + (modelData.pulgadas ? " · " + modelData.pulgadas + "″" : "")
            function aplicar(modo, escala, giro, activa) {
                dispositivos.aplicarPantalla(modelData.nombre, modo, escala, giro, activa)
            }
            Fila {
                titulo: "Encendida"
                Interruptor {
                    anchors.verticalCenter: parent.verticalCenter
                    activo: grupoPantalla.modelData.activa
                    onAlternado: (v) => grupoPantalla.aplicar(grupoPantalla.modelData.modo, grupoPantalla.modelData.escala, grupoPantalla.modelData.giro, v)
                }
            }
            Fila {
                titulo: "Resolución"
                visible: grupoPantalla.modelData.activa
                Desplegable {
                    anchors.verticalCenter: parent.verticalCenter
                    ancho: 230
                    // Las mayores que la pantalla no anuncia, solo con «Mostrar más
                    // resoluciones» (o si ya está puesta una)
                    opciones: grupoPantalla.modelData.modos.filter(function (m) {
                        return !m.mayor || vista.masResoluciones || m.id === grupoPantalla.modelData.modo
                    }).map(function (m) {
                        return { valor: m.id, texto: m.texto + (m.preferido ? "  (recomendada)" : m.mayor ? "  (probar)" : "") }
                    })
                    valor: grupoPantalla.modelData.modo || ""
                    onElegido: (v) => grupoPantalla.aplicar(v, grupoPantalla.modelData.escala, grupoPantalla.modelData.giro, true)
                }
            }
            Fila {
                titulo: "Mostrar más resoluciones"
                detalle: "Añade resoluciones mayores que la pantalla no anuncia. Si la pantalla no la acepta, se deshace sola en 15 segundos."
                visible: grupoPantalla.modelData.activa
                Interruptor {
                    anchors.verticalCenter: parent.verticalCenter
                    activo: vista.masResoluciones
                    onAlternado: (v) => vista.masResoluciones = v
                }
            }
            Fila {
                titulo: "Escala"
                detalle: "Más grande hace los textos y botones más grandes"
                visible: grupoPantalla.modelData.activa
                Segmentos {
                    anchors.verticalCenter: parent.verticalCenter
                    anchoSegmento: 56
                    opciones: [{ valor: "1.00", texto: "100 %" }, { valor: "1.25", texto: "125 %" }, { valor: "1.50", texto: "150 %" },
                               { valor: "1.75", texto: "175 %" }, { valor: "2.00", texto: "200 %" }]
                    valor: Number(grupoPantalla.modelData.escala).toFixed(2)
                    onElegido: (v) => grupoPantalla.aplicar(grupoPantalla.modelData.modo, Number(v), grupoPantalla.modelData.giro, true)
                }
            }
            Fila {
                titulo: "Giro"
                visible: grupoPantalla.modelData.activa
                separador: false
                Segmentos {
                    anchors.verticalCenter: parent.verticalCenter
                    anchoSegmento: 62
                    opciones: [{ valor: "normal", texto: "Normal" }, { valor: "90", texto: "90°" }, { valor: "180", texto: "180°" }, { valor: "270", texto: "270°" }]
                    valor: grupoPantalla.modelData.giro
                    onElegido: (v) => grupoPantalla.aplicar(grupoPantalla.modelData.modo, grupoPantalla.modelData.escala, v, true)
                }
            }
        }
    }

    Row {
        spacing: 8
        visible: dispositivos.pantallas.length > 1
        Boton { texto: "Identificar pantallas"; onPulsado: dispositivos.identificar() }
    }

    Grupo {
        etiqueta: "Brillo"
        visible: dispositivos.brillo >= 0
        Fila {
            titulo: "Brillo de la pantalla"
            detalle: dispositivos.brillo + " %"
            separador: false
            Deslizador {
                anchors.verticalCenter: parent.verticalCenter
                ancho: 240
                desde: 5; hasta: 100
                valor: dispositivos.brillo
                onMovido: (v) => dispositivos.setBrillo(Math.round(v))
            }
        }
    }

    Grupo {
        etiqueta: "Luz nocturna"
        nota: dispositivos.luzNocturna.instalada ? "Colores más cálidos por la noche: cansan menos la vista. El cambio es gradual (15 minutos)."
                                                 : "Falta el programa wlsunset."
        Fila {
            titulo: "Luz nocturna con horario"
            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                habilitado: dispositivos.luzNocturna.instalada === true
                activo: dispositivos.luzNocturna.activa === true
                onAlternado: (v) => dispositivos.setLuzNocturna("activa", v)
            }
        }
        Fila {
            titulo: "Desde"
            Desplegable {
                anchors.verticalCenter: parent.verticalCenter
                ancho: 100
                habilitado: dispositivos.luzNocturna.activa === true
                opciones: { var r = []; for (var h = 0; h < 24; ++h) { var t = (h < 10 ? "0" : "") + h + ":00"; r.push({ valor: t, texto: t }) } return r }
                valor: dispositivos.luzNocturna.desde || "20:00"
                onElegido: (v) => dispositivos.setLuzNocturna("desde", v)
            }
        }
        Fila {
            titulo: "Hasta"
            Desplegable {
                anchors.verticalCenter: parent.verticalCenter
                ancho: 100
                habilitado: dispositivos.luzNocturna.activa === true
                opciones: { var r = []; for (var h = 0; h < 24; ++h) { var t = (h < 10 ? "0" : "") + h + ":00"; r.push({ valor: t, texto: t }) } return r }
                valor: dispositivos.luzNocturna.hasta || "07:00"
                onElegido: (v) => dispositivos.setLuzNocturna("hasta", v)
            }
        }
        Fila {
            titulo: "Temperatura de color"
            detalle: (dispositivos.luzNocturna.temperatura || 4000) + " K"
            separador: false
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Más cálida"; color: tema.contentTextSecondary; font.pixelSize: 10 }
            Deslizador {
                anchors.verticalCenter: parent.verticalCenter
                ancho: 170
                desde: 2500; hasta: 5500; paso: 100
                habilitado: dispositivos.luzNocturna.activa === true
                valor: dispositivos.luzNocturna.temperatura || 4000
                onSoltado: (v) => dispositivos.setLuzNocturna("temperatura", Math.round(v))
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Menos"; color: tema.contentTextSecondary; font.pixelSize: 10 }
        }
    }
}
