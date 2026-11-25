import QtQuick
import QtQuick.Controls

// Monitor de recursos de Inti OS (como el Administrador de tareas de Windows,
// con el estilo, el color de acento y el modo claro/oscuro del sistema).
TitanWindow {
    id: ventana
    title: "Monitor de recursos"
    width: 980
    height: 640
    minimumWidth: 720
    minimumHeight: 480
    expandedSidebarWidth: 222
    collapsedSidebarWidth: 54

    // Minimizada: no se mide nada (no gasta CPU)
    onVisibilityChanged: monitor.activo = visibility !== Window.Minimized && visibility !== Window.Hidden

    Shortcut { sequence: "Ctrl+1"; onActivated: monitor.pagina = "procesos" }
    Shortcut { sequence: "Ctrl+2"; onActivated: monitor.pagina = "rendimiento" }
    Shortcut { sequence: "Ctrl+3"; onActivated: monitor.pagina = "inicio" }
    Shortcut { sequence: "Ctrl+F"; onActivated: { monitor.pagina = "procesos"; buscar.forceActiveFocus() } }
    Shortcut { sequence: "F5"; onActivated: monitor.actualizarAhora() }

    readonly property var paginas: [
        { id: "procesos", t: "Procesos", i: "procesos" },
        { id: "rendimiento", t: "Rendimiento", i: "rendimiento" },
        { id: "inicio", t: "Aplicaciones de inicio", i: "inicio" }
    ]

    // Iconos de la barra lateral, dibujados (iguales en todos los equipos)
    component IconoNav: Canvas {
        id: ic
        property string nombre: ""
        property color color: "white"
        width: 16; height: 16
        onColorChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset()
            c.strokeStyle = ic.color; c.fillStyle = ic.color; c.lineWidth = 1.5; c.lineCap = "round"; c.lineJoin = "round"
            function l(p) { c.beginPath(); c.moveTo(p[0], p[1]); for (var i = 2; i < p.length; i += 2) c.lineTo(p[i], p[i + 1]); c.stroke() }
            if (nombre === "procesos") { for (var k = 0; k < 3; ++k) { c.fillRect(2, 3 + k * 4.5, 2.2, 2.2); l([6.5, 4.1 + k * 4.5, 14, 4.1 + k * 4.5]) } }
            else if (nombre === "rendimiento") { l([1.5, 12, 5, 8, 8, 10, 11, 4, 14.5, 7]); l([1.5, 14.5, 14.5, 14.5]) }
            else if (nombre === "inicio") { c.beginPath(); c.arc(8, 8.5, 5.5, -Math.PI * 0.3, Math.PI * 1.3); c.stroke(); l([8, 1.5, 8, 7]) }
        }
    }

    // ------------------------------------------------------------ barra lateral
    sidebarContentData: Item {
        anchors.fill: parent
        Column {
            anchors.fill: parent
            anchors.margins: 8
            anchors.topMargin: 14
            spacing: 2
            Repeater {
                model: ventana.paginas
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool sel: monitor.pagina === modelData.id
                    width: parent.width
                    height: 34
                    radius: 7
                    color: sel ? theme.accent : zona.containsMouse ? theme.itemHover : "transparent"
                    IconoNav {
                        id: icono
                        x: ventana.sidebarCollapsed ? (parent.width - width) / 2 : 10
                        anchors.verticalCenter: parent.verticalCenter
                        nombre: modelData.i
                        color: parent.sel ? "#ffffff" : theme.accent
                    }
                    Text {
                        visible: !ventana.sidebarCollapsed
                        anchors.left: icono.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.t
                        elide: Text.ElideRight
                        color: parent.sel ? "#ffffff" : theme.sidebarText
                        font.pixelSize: 13
                        font.weight: parent.sel ? Font.DemiBold : Font.Normal
                    }
                    MouseArea { id: zona; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: monitor.pagina = modelData.id }
                    ToolTip.visible: ventana.sidebarCollapsed && zona.containsMouse
                    ToolTip.text: modelData.t
                }
            }
        }
    }

    // ------------------------------------------------------------ barra superior
    headerContentData: Item {
        anchors.fill: parent
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: monitor.pagina === "procesos" ? "Procesos" : monitor.pagina === "rendimiento" ? "Rendimiento" : "Aplicaciones de inicio"
            color: theme.headerText
            font.pixelSize: 15
            font.bold: true
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            visible: monitor.pagina === "procesos"

            Rectangle {
                width: 220; height: 30; radius: 7
                anchors.verticalCenter: parent.verticalCenter
                color: theme.isDark ? "#1c1c1f" : "#ffffff"
                border.color: buscar.activeFocus ? theme.accent : theme.glassBorder
                border.width: buscar.activeFocus ? 1.5 : 1
                TextField {
                    id: buscar
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    placeholderText: "Buscar un proceso"
                    placeholderTextColor: theme.contentTextSecondary
                    color: theme.contentTextPrimary
                    font.pixelSize: 12
                    background: null
                    onTextChanged: monitor.filtro = text
                    Keys.onEscapePressed: text = ""
                }
            }
            Rectangle {
                id: finalizar
                readonly property bool puede: !!procesos.seleccion && !procesos.seleccion.critico
                width: tf.implicitWidth + 28; height: 30; radius: 7
                anchors.verticalCenter: parent.verticalCenter
                opacity: puede ? 1 : 0.4
                color: zf.containsMouse && puede ? Qt.darker(theme.accent, 1.1) : theme.accent
                Text { id: tf; anchors.centerIn: parent; text: "Finalizar tarea"; color: "#ffffff"; font.pixelSize: 12; font.weight: Font.DemiBold }
                MouseArea { id: zf; anchors.fill: parent; hoverEnabled: true; enabled: finalizar.puede; cursorShape: Qt.PointingHandCursor; onClicked: procesos.finalizarSeleccion(false) }
                ToolTip.visible: zf.containsMouse && !!procesos.seleccion && procesos.seleccion.critico
                ToolTip.text: "Es del sistema o de otro usuario: no se puede cerrar desde aquí"
            }
        }
    }

    // ------------------------------------------------------------ páginas
    Item {
        anchors.fill: parent
        VistaProcesos {
            id: procesos
            anchors.fill: parent
            visible: monitor.pagina === "procesos"
        }
        Loader {
            anchors.fill: parent
            active: monitor.pagina === "rendimiento"
            visible: active
            sourceComponent: VistaRendimiento {}
        }
        Loader {
            anchors.fill: parent
            active: monitor.pagina === "inicio"
            visible: active
            sourceComponent: VistaInicio {}
        }

        // Aviso abajo (finalizado, no se puede...)
        Rectangle {
            visible: monitor.aviso !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            width: textoAviso.implicitWidth + 32
            height: 34
            radius: 17
            color: theme.isDark ? "#2c2c30" : "#1d1d1f"
            Text { id: textoAviso; anchors.centerIn: parent; text: monitor.aviso; color: "#ffffff"; font.pixelSize: 12 }
            Timer { running: monitor.aviso !== ""; interval: 3500; onTriggered: monitor.cerrarAviso() }
        }
    }

    // ------------------------------------------------------------ barra de estado
    statusBarContentData: Item {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "CPU " + Math.round(monitor.cpu.uso || 0) + " %      Memoria " + Math.round(monitor.memoria.uso || 0)
                  + " %      " + (monitor.cpu.procesos || 0) + " procesos"
            color: theme.contentTextSecondary
            font.pixelSize: 11
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text { text: "Actualizar:"; color: theme.contentTextSecondary; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter; rightPadding: 4 }
            Repeater {
                model: [{ ms: 500, t: "Rápido" }, { ms: 1000, t: "Normal" }, { ms: 5000, t: "Lento" }, { ms: 0, t: "En pausa" }]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool sel: monitor.intervalo === modelData.ms
                    width: te.implicitWidth + 14; height: 18; radius: 5
                    anchors.verticalCenter: parent.verticalCenter
                    color: sel ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.25) : ze.containsMouse ? theme.itemHover : "transparent"
                    Text { id: te; anchors.centerIn: parent; text: modelData.t; color: parent.sel ? theme.accent : theme.contentTextSecondary; font.pixelSize: 11 }
                    MouseArea { id: ze; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: monitor.intervalo = modelData.ms }
                }
            }
        }
    }
}
