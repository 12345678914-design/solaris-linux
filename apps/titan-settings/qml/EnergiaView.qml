// Ajustes > Bateria: estado de la bateria, modo de energia e inactividad.
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Batería y energía"
    descripcion: "Modo de energía y qué hace el equipo cuando no lo usas."

    readonly property var bat: sistema.bateria
    readonly property bool hayBateria: bat.hay === true

    Component.onCompleted: sistema.refrescar("Batería")
    Timer {
        interval: 30000
        repeat: true
        running: vista.visible
        onTriggered: sistema.refrescar("bateria")
    }

    function duracion(min) {
        var h = Math.floor(min / 60), m = min % 60
        if (h === 0) return m + " min"
        return h + " h " + (m < 10 ? "0" : "") + m + " min"
    }
    function textoEstado() {
        var e = bat.estado
        if (e === "Charging")
            return "Cargando" + (bat.minutosHastaLlena ? " · llena en " + duracion(bat.minutosHastaLlena) : "")
        if (e === "Discharging")
            return "Con batería" + (bat.minutosRestantes ? " · quedan " + duracion(bat.minutosRestantes) : "")
        if (e === "Full") return "Cargada"
        if (e === "Not charging") return "Enchufado, sin cargar (protección de la batería)"
        return bat.enchufado ? "Enchufado" : ""
    }

    TitanTheme { id: tema }

    // Bateria
    Grupo {
        etiqueta: "Batería"
        visible: vista.hayBateria
        Item {
            width: parent.width
            height: 86
            Text {
                id: porcentaje
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                text: (vista.bat.porcentaje || 0) + "%"
                color: tema.contentTextPrimary
                font.pixelSize: 34
                font.bold: true
            }
            Column {
                anchors.left: porcentaje.right
                anchors.leftMargin: 18
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7
                Rectangle {
                    width: parent.width
                    height: 10
                    radius: 5
                    color: tema.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(100, vista.bat.porcentaje || 0)) / 100
                        height: parent.height
                        radius: 5
                        color: (vista.bat.porcentaje || 0) <= 15 && vista.bat.estado !== "Charging" ? "#ff453a" : "#34c759"
                    }
                }
                Text {
                    text: vista.textoEstado()
                    color: tema.contentTextSecondary
                    font.pixelSize: 12
                }
            }
        }
        Fila {
            visible: vista.bat.salud !== undefined
            separador: false
            titulo: "Condición"
            detalle: vista.bat.salud !== undefined
                     ? "Capacidad máxima: " + vista.bat.salud + "% de la original" +
                       (vista.bat.ciclos ? " · " + vista.bat.ciclos + " ciclos de carga" : "")
                     : ""
            Text {
                text: vista.bat.salud >= 80 ? "Normal" : "Revisar"
                color: vista.bat.salud >= 80 ? "#34c759" : "#ff9f0a"
                font.pixelSize: 12
                font.bold: true
            }
        }
    }

    // Modo de energia (power-profiles-daemon)
    Grupo {
        etiqueta: "Modo de energía"
        nota: sistema.perfilesEnergia.length === 0
              ? "El servicio de perfiles de energía (power-profiles-daemon) no está en marcha."
              : "Ahorro alarga la batería; Rendimiento da toda la potencia del procesador y la gráfica."
        Fila {
            separador: false
            titulo: "Modo"
            detalle: "Equilibrado es el de serie."
            Segmentos {
                visible: sistema.perfilesEnergia.length > 0
                valor: sistema.perfilEnergia
                anchoSegmento: 98
                opciones: {
                    var nombres = { "power-saver": "Ahorro", "balanced": "Equilibrado", "performance": "Rendimiento" }
                    var r = []
                    for (var i = 0; i < sistema.perfilesEnergia.length; ++i) {
                        var p = sistema.perfilesEnergia[i]
                        r.push({ valor: p, texto: nombres[p] || p })
                    }
                    return r
                }
                onElegido: function(v) { sistema.setPerfilEnergia(v) }
            }
        }
    }

    // Equipo ligero (titan-rendimiento)
    Grupo {
        etiqueta: "Rendimiento del escritorio"
        nota: sistema.ligeroRecomendado !== ""
              ? "Recomendado en este equipo (" + sistema.ligeroRecomendado + "). Se activó solo la primera vez."
              : "Para ordenadores modestos: quita el desenfoque, la gelatina de las ventanas y las animaciones, y el Dock no amplía los iconos."
        Fila {
            separador: false
            titulo: "Equipo ligero"
            detalle: "Todo va más fluido en equipos lentos; se ve más sencillo."
            Interruptor {
                activo: { prefs.version; return prefs.b("Rendimiento/ligero") }
                onAlternado: function(v) { sistema.setEquipoLigero(v) }
            }
        }
    }

    // Inactividad
    Grupo {
        etiqueta: "Cuando no se usa"
        nota: sistema.live ? "En la sesión de prueba (live) el equipo nunca se suspende solo." :
              "Los vídeos a pantalla completa y las videollamadas impiden que se apague la pantalla."
        Fila {
            titulo: "Apagar la pantalla tras"
            SelectorMinutos {
                valor: sistema.inactividad.APAGAR_PANTALLA
                onElegido: function(m) { sistema.setInactividad("APAGAR_PANTALLA", m) }
            }
        }
        Fila {
            visible: vista.hayBateria
            titulo: "Suspender con batería tras"
            SelectorMinutos {
                valor: sistema.inactividad.SUSPENDER_BATERIA
                onElegido: function(m) { sistema.setInactividad("SUSPENDER_BATERIA", m) }
            }
        }
        Fila {
            separador: false
            titulo: vista.hayBateria ? "Suspender enchufado tras" : "Suspender tras"
            SelectorMinutos {
                valor: sistema.inactividad.SUSPENDER_CORRIENTE
                onElegido: function(m) { sistema.setInactividad("SUSPENDER_CORRIENTE", m) }
            }
        }
    }
}
