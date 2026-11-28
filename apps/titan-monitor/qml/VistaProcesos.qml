import QtQuick
import QtQuick.Controls

// Procesos: las aplicaciones agrupadas (Firefox = una fila con todos sus
// procesos) y debajo los procesos en segundo plano. Las celdas se tiñen con
// el acento según lo que gastan, como en Windows.
Rectangle {
    id: vista
    TitanTheme { id: theme }
    color: theme.contentBackground

    // La selección se guarda por clave: sigue marcada aunque la lista se reordene
    property string claveSel: ""
    readonly property var seleccion: {
        var l = filas
        for (var i = 0; i < l.length; ++i) if (!l[i].seccion && clave(l[i]) === claveSel) return l[i]
        return null
    }
    function clave(f) { return f.icono !== undefined ? "app:" + f.nombre : "pid:" + f.pid }

    readonly property var filas: {
        var a = monitor.aplicaciones, b = monitor.segundoPlano, l = []
        if (a.length > 0) l.push({ seccion: "Aplicaciones (" + a.length + ")" })
        l = l.concat(a)
        if (b.length > 0) l.push({ seccion: "Procesos en segundo plano (" + b.length + ")" })
        return l.concat(b)
    }

    function finalizarSeleccion(forzar) {
        if (seleccion && !seleccion.critico) monitor.finalizar(seleccion.pids, seleccion.nombre, forzar)
    }

    readonly property real memTotal: monitor.memoria.total || 1
    readonly property int anchoCol: Math.max(84, Math.min(120, width * 0.12))

    focus: visible
    Keys.onDeletePressed: finalizarSeleccion(false)

    // Cabecera de columnas (pulsar = ordenar)
    Rectangle {
        id: cabecera
        width: parent.width
        height: 44
        color: theme.contentBackground
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.contentCardBorder }

        component Columna: Item {
            id: col
            property string clave: ""
            property string titulo: ""
            property string resumen: ""
            property bool izquierda: false
            height: parent.height
            readonly property bool activa: monitor.orden === clave
            Column {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: col.izquierda ? undefined : parent.right
                anchors.left: col.izquierda ? parent.left : undefined
                anchors.rightMargin: 12
                anchors.leftMargin: 14
                Text {
                    anchors.right: col.izquierda ? undefined : parent.right
                    text: col.resumen
                    visible: text !== ""
                    color: col.activa ? theme.accent : theme.contentTextPrimary
                    font.pixelSize: 15; font.bold: true
                }
                Text {
                    anchors.right: col.izquierda ? undefined : parent.right
                    text: col.titulo + (col.activa ? (monitor.ordenDescendente ? "  ▾" : "  ▴") : "")
                    color: col.activa ? theme.accent : theme.contentTextSecondary
                    font.pixelSize: 11
                    font.weight: col.activa ? Font.DemiBold : Font.Normal
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (monitor.orden === col.clave) monitor.ordenDescendente = !monitor.ordenDescendente
                    else monitor.orden = col.clave
                }
            }
        }
        Columna { x: 0; width: parent.width - 3 * vista.anchoCol; clave: "nombre"; titulo: "Nombre"; izquierda: true }
        Columna { x: parent.width - 3 * vista.anchoCol; width: vista.anchoCol; clave: "cpu"; titulo: "CPU"; resumen: Math.round(monitor.cpu.uso || 0) + " %" }
        Columna { x: parent.width - 2 * vista.anchoCol; width: vista.anchoCol; clave: "memoria"; titulo: "Memoria"; resumen: Math.round(monitor.memoria.uso || 0) + " %" }
        Columna {
            x: parent.width - vista.anchoCol; width: vista.anchoCol; clave: "disco"; titulo: "Disco"
            resumen: {
                var d = monitor.discos, m = 0
                for (var i = 0; i < d.length; ++i) m = Math.max(m, d[i].uso)
                return Math.round(m) + " %"
            }
        }
    }

    ListView {
        id: lista
        anchors.top: cabecera.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: vista.filas
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // Sin animaciones al reordenar: cada segundo cambia
        reuseItems: true
        footer: Item { width: 1; height: 52 }   // que el interruptor de abajo no tape la última fila

        delegate: Item {
            id: fila
            required property var modelData
            required property int index
            width: lista.width
            height: modelData.seccion ? 34 : 30
            readonly property bool esSel: !modelData.seccion && vista.clave(modelData) === vista.claveSel

            // Título de sección
            Text {
                visible: !!fila.modelData.seccion
                x: 14
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 7
                text: fila.modelData.seccion || ""
                color: theme.accent
                font.pixelSize: 12
                font.bold: true
            }

            Rectangle {
                visible: !fila.modelData.seccion
                anchors.fill: parent
                color: fila.esSel ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.30)
                     : zonaFila.containsMouse ? theme.itemHover : "transparent"

                // Icono (o la inicial) y nombre
                Item {
                    id: icono
                    x: 14
                    width: 18; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    Image {
                        id: img
                        anchors.fill: parent
                        source: fila.modelData.icono || ""
                        sourceSize: Qt.size(36, 36)
                        visible: status === Image.Ready
                        asynchronous: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: !img.visible
                        radius: 5
                        color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.20)
                        Text {
                            anchors.centerIn: parent
                            text: (fila.modelData.nombre || "?").charAt(0).toUpperCase()
                            color: theme.accent
                            font.pixelSize: 10; font.bold: true
                        }
                    }
                }
                Text {
                    anchors.left: icono.right
                    anchors.leftMargin: 10
                    anchors.right: celdas.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: (fila.modelData.nombre || "") + (fila.modelData.cantidad > 1 ? "  (" + fila.modelData.cantidad + ")" : "")
                    color: theme.contentTextPrimary
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                Row {
                    id: celdas
                    anchors.right: parent.right
                    height: parent.height
                    component Celda: Rectangle {
                        property string texto: ""
                        property real nivel: 0     // 0..1: cuánto gasta
                        width: vista.anchoCol
                        height: parent.height
                        color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, Math.min(0.55, nivel * 0.55 + (nivel > 0.005 ? 0.06 : 0)))
                        Rectangle { width: 1; height: parent.height; color: theme.contentCardBorder; opacity: 0.6 }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.texto
                            color: theme.contentTextPrimary
                            font.pixelSize: 12
                        }
                    }
                    Celda {
                        texto: (fila.modelData.cpu || 0).toLocaleString(Qt.locale("es_ES"), "f", 1) + " %"
                        nivel: (fila.modelData.cpu || 0) / 100
                    }
                    Celda {
                        texto: monitor.bytes(fila.modelData.memoria || 0)
                        nivel: (fila.modelData.memoria || 0) / vista.memTotal * 4
                    }
                    Celda {
                        texto: monitor.mbs(fila.modelData.disco || 0)
                        nivel: (fila.modelData.disco || 0) / (20 * 1024 * 1024)
                    }
                }

                MouseArea {
                    id: zonaFila
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        vista.claveSel = vista.clave(fila.modelData)
                        vista.forceActiveFocus()
                        if (mouse.button === Qt.RightButton) {
                            menu.x = mouse.x + fila.x
                            menu.y = fila.mapToItem(vista, 0, mouse.y).y
                            menu.open()
                        }
                    }
                }
            }
        }
    }

    Menu {
        id: menu
        MenuItem {
            text: "Finalizar tarea"
            enabled: !!vista.seleccion && !vista.seleccion.critico
            onTriggered: vista.finalizarSeleccion(false)
        }
        MenuItem {
            text: "Forzar el cierre"
            enabled: !!vista.seleccion && !vista.seleccion.critico
            onTriggered: vista.finalizarSeleccion(true)
        }
    }

    // Todos los usuarios (abajo a la izquierda, sin estorbar)
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 10
        width: filaTodos.implicitWidth + 20
        height: 28
        radius: 14
        color: theme.isDark ? "#1c1c1f" : "#f2f2f5"
        border.color: theme.contentCardBorder
        Row {
            id: filaTodos
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                width: 28; height: 16; radius: 8
                anchors.verticalCenter: parent.verticalCenter
                color: monitor.todosLosUsuarios ? theme.accent : (theme.isDark ? "#3a3a3e" : "#c7c7cc")
                Rectangle { width: 12; height: 12; radius: 6; y: 2; x: monitor.todosLosUsuarios ? 14 : 2; color: "#ffffff"; Behavior on x { NumberAnimation { duration: 120 } } }
            }
            Text { text: "Procesos de todos los usuarios"; color: theme.contentTextSecondary; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: monitor.todosLosUsuarios = !monitor.todosLosUsuarios }
    }
}
