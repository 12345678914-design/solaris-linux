import QtQuick
import QtQuick.Controls

// Rendimiento: a la izquierda una tarjeta por recurso con su gráfica pequeña;
// a la derecha la gráfica grande y los datos del elegido (como Windows).
Rectangle {
    id: vista
    TitanTheme { id: theme }
    color: theme.contentBackground

    property string elegido: "cpu"
    property bool porNucleo: false
    readonly property var es: Qt.locale("es_ES")

    function pct(v) { return Math.round(v || 0) + " %" }

    readonly property var tarjetas: {
        var l = [{ id: "cpu", t: "CPU", sub: pct(monitor.cpu.uso) + (monitor.cpu.ghz ? "  " + monitor.cpu.ghz : ""), hist: monitor.cpu.hist || [], max: 100 },
                 { id: "mem", t: "Memoria", sub: monitor.bytes(monitor.memoria.usada || 0) + " / " + monitor.bytes(monitor.memoria.total || 0)
                              + " (" + pct(monitor.memoria.uso) + ")", hist: monitor.memoria.hist || [], max: 100 }]
        var d = monitor.discos
        for (var i = 0; i < d.length; ++i)
            l.push({ id: "disco:" + d[i].id, t: d[i].titulo, sub: d[i].tipo + "  " + pct(d[i].uso), hist: d[i].hist, max: 100, dato: d[i] })
        var r = monitor.redes
        for (var j = 0; j < r.length; ++j)
            l.push({ id: "red:" + r[j].id, t: r[j].titulo, sub: r[j].conectada ? "↓ " + monitor.velocidad(r[j].bajada) + "  ↑ " + monitor.velocidad(r[j].subida) : "Sin conexión",
                     hist: r[j].histRx, hist2: r[j].histTx, max: 0, dato: r[j] })
        return l
    }
    readonly property var actual: {
        for (var i = 0; i < tarjetas.length; ++i) if (tarjetas[i].id === elegido) return tarjetas[i]
        return tarjetas[0]
    }

    // ------------------------------------------------------------ tarjetas
    ListView {
        id: lista
        x: 12; y: 12
        width: 230
        height: parent.height - 24
        spacing: 6
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: vista.tarjetas
        delegate: Rectangle {
            required property var modelData
            readonly property bool sel: vista.actual && vista.actual.id === modelData.id
            width: lista.width
            height: 64
            radius: 10
            color: sel ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.16) : zt.containsMouse ? theme.itemHover : "transparent"
            border.color: sel ? theme.accent : "transparent"
            Grafica {
                id: mini
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 72; height: 46
                valores: modelData.hist
                valores2: modelData.hist2 || []
                maximo: modelData.max
                rejilla: false
            }
            Column {
                anchors.left: mini.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text { width: parent.width; text: modelData.t; color: theme.contentTextPrimary; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Text { width: parent.width; text: modelData.sub; color: theme.contentTextSecondary; font.pixelSize: 11; elide: Text.ElideRight }
            }
            MouseArea { id: zt; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: vista.elegido = modelData.id }
        }
    }

    Rectangle { x: lista.x + lista.width + 12; width: 1; height: parent.height; color: theme.contentCardBorder }

    // ------------------------------------------------------------ detalle
    Flickable {
        id: detalle
        x: lista.x + lista.width + 25
        y: 0
        width: parent.width - x - 14
        height: parent.height
        contentHeight: col.implicitHeight + 28
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: col
            y: 14
            width: detalle.width
            spacing: 12

            // Título y modelo
            Item {
                width: parent.width
                height: 34
                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    text: vista.actual ? vista.actual.t : ""
                    color: theme.contentTextPrimary
                    font.pixelSize: 24; font.bold: true
                }
                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3
                    width: Math.min(implicitWidth, parent.width * 0.6)
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    text: !vista.actual ? "" : vista.actual.id === "cpu" ? monitor.cpu.modelo
                         : vista.actual.id === "mem" ? monitor.bytes(monitor.memoria.total || 0) + " en total"
                         : vista.actual.dato && vista.actual.dato.modelo !== undefined ? (vista.actual.dato.modelo || vista.actual.dato.tipo) + " · " + monitor.bytes(vista.actual.dato.tamano)
                         : vista.actual.dato ? vista.actual.dato.id : ""
                    color: theme.contentTextSecondary
                    font.pixelSize: 13
                }
            }

            // Leyenda de la gráfica
            Item {
                width: parent.width
                height: 14
                Text {
                    text: !vista.actual ? "" : vista.actual.id === "cpu" ? "% de uso en 60 segundos"
                         : vista.actual.id === "mem" ? "Memoria en uso"
                         : vista.actual.id.indexOf("disco:") === 0 ? "Tiempo de actividad"
                         : "Bajada (línea) y subida (discontinua)"
                    color: theme.contentTextSecondary
                    font.pixelSize: 11
                }
                Text {
                    anchors.right: parent.right
                    text: vista.actual && vista.actual.max === 0 ? "" : "100 %"
                    color: theme.contentTextSecondary
                    font.pixelSize: 11
                }
            }

            // Gráfica grande (o una por núcleo)
            Grafica {
                visible: !(vista.actual && vista.actual.id === "cpu" && vista.porNucleo)
                width: parent.width
                height: Math.max(170, Math.min(300, vista.height * 0.42))
                valores: vista.actual ? vista.actual.hist : []
                valores2: vista.actual && vista.actual.hist2 ? vista.actual.hist2 : []
                maximo: vista.actual ? vista.actual.max : 100
            }
            Grid {
                id: nucleos
                visible: vista.actual && vista.actual.id === "cpu" && vista.porNucleo
                width: parent.width
                readonly property int n: (monitor.cpu.nucleos || []).length
                columns: n <= 4 ? n : n <= 8 ? 4 : n <= 16 ? 8 : 12
                spacing: 6
                Repeater {
                    model: monitor.cpu.nucleos || []
                    delegate: Grafica {
                        required property var modelData
                        width: (nucleos.width - (nucleos.columns - 1) * nucleos.spacing) / Math.max(1, nucleos.columns)
                        height: Math.max(56, Math.min(110, (vista.height * 0.42) / Math.ceil(nucleos.n / Math.max(1, nucleos.columns))))
                        valores: modelData.hist
                        rejilla: false
                    }
                }
            }

            // Cambiar vista de la CPU
            Row {
                visible: vista.actual && vista.actual.id === "cpu"
                spacing: 6
                Repeater {
                    model: [{ v: false, t: "Total" }, { v: true, t: "Por núcleo" }]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: vista.porNucleo === modelData.v
                        width: tv.implicitWidth + 20; height: 26; radius: 13
                        color: sel ? theme.accent : zv.containsMouse ? theme.itemHover : "transparent"
                        border.color: sel ? theme.accent : theme.contentCardBorder
                        Text { id: tv; anchors.centerIn: parent; text: modelData.t; color: parent.sel ? "#ffffff" : theme.contentTextPrimary; font.pixelSize: 12 }
                        MouseArea { id: zv; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: vista.porNucleo = modelData.v }
                    }
                }
            }

            // Datos
            Flow {
                width: parent.width
                spacing: 22
                component Dato: Column {
                    property string k: ""
                    property string v: ""
                    property bool grande: true
                    visible: v !== ""
                    spacing: 2
                    Text { text: parent.k; color: theme.contentTextSecondary; font.pixelSize: 11 }
                    Text { text: parent.v; color: theme.contentTextPrimary; font.pixelSize: parent.grande ? 20 : 13; font.weight: Font.DemiBold }
                }
                // CPU
                Dato { visible: vista.elegido === "cpu"; k: "Uso"; v: vista.pct(monitor.cpu.uso) }
                Dato { visible: vista.elegido === "cpu"; k: "Velocidad"; v: monitor.cpu.ghz || "" }
                Dato { visible: vista.elegido === "cpu"; k: "Procesos"; v: String(monitor.cpu.procesos || 0) }
                Dato { visible: vista.elegido === "cpu"; k: "Hilos"; v: String(monitor.cpu.hilos || 0) }
                Dato { visible: vista.elegido === "cpu"; k: "Tiempo encendido"; v: monitor.cpu.activo || "" }
                Dato { visible: vista.elegido === "cpu"; k: "Núcleos lógicos"; v: String(monitor.cpu.cantidad || 0); grande: false }
                // Memoria
                Dato { visible: vista.elegido === "mem"; k: "En uso"; v: monitor.bytes(monitor.memoria.usada || 0) }
                Dato { visible: vista.elegido === "mem"; k: "Disponible"; v: monitor.bytes(monitor.memoria.disponible || 0) }
                Dato { visible: vista.elegido === "mem"; k: "En caché"; v: monitor.bytes(monitor.memoria.cache || 0); grande: false }
                Dato { visible: vista.elegido === "mem" && (monitor.memoria.swapTotal || 0) > 0; k: "Memoria de intercambio"
                       v: monitor.bytes(monitor.memoria.swapUsada || 0) + " / " + monitor.bytes(monitor.memoria.swapTotal || 0); grande: false }
                // Disco
                Dato { visible: vista.elegido.indexOf("disco:") === 0; k: "Actividad"; v: vista.actual && vista.actual.dato ? vista.pct(vista.actual.dato.uso) : "" }
                Dato { visible: vista.elegido.indexOf("disco:") === 0; k: "Lectura"; v: vista.actual && vista.actual.dato && vista.actual.dato.lectura !== undefined ? monitor.velocidad(vista.actual.dato.lectura) : "" }
                Dato { visible: vista.elegido.indexOf("disco:") === 0; k: "Escritura"; v: vista.actual && vista.actual.dato && vista.actual.dato.escritura !== undefined ? monitor.velocidad(vista.actual.dato.escritura) : "" }
                // Red
                Dato { visible: vista.elegido.indexOf("red:") === 0; k: "Bajada"; v: vista.actual && vista.actual.dato && vista.actual.dato.bajada !== undefined ? monitor.velocidad(vista.actual.dato.bajada) : "" }
                Dato { visible: vista.elegido.indexOf("red:") === 0; k: "Subida"; v: vista.actual && vista.actual.dato && vista.actual.dato.subida !== undefined ? monitor.velocidad(vista.actual.dato.subida) : "" }
                Dato { visible: vista.elegido.indexOf("red:") === 0; k: "Descargado desde el inicio"; v: vista.actual && vista.actual.dato && vista.actual.dato.totalBajada !== undefined ? monitor.bytes(vista.actual.dato.totalBajada) : ""; grande: false }
                Dato { visible: vista.elegido.indexOf("red:") === 0; k: "Enviado desde el inicio"; v: vista.actual && vista.actual.dato && vista.actual.dato.totalSubida !== undefined ? monitor.bytes(vista.actual.dato.totalSubida) : ""; grande: false }
                Dato { visible: vista.elegido.indexOf("red:") === 0; k: "Adaptador"; v: vista.actual && vista.actual.dato ? vista.actual.dato.id : ""; grande: false }
            }

            // Memoria: barra de reparto
            Column {
                visible: vista.elegido === "mem"
                width: parent.width
                spacing: 6
                Text { text: "Reparto de la memoria"; color: theme.contentTextSecondary; font.pixelSize: 11 }
                Rectangle {
                    width: parent.width
                    height: 22
                    radius: 6
                    color: theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
                    border.color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.45)
                    readonly property real t: monitor.memoria.total || 1
                    Rectangle {
                        id: enUso
                        width: parent.width * (monitor.memoria.usada || 0) / parent.t
                        height: parent.height
                        radius: 6
                        color: theme.accent
                    }
                    Rectangle {
                        x: enUso.width
                        width: Math.max(0, Math.min(parent.width - x, parent.width * (monitor.memoria.cache || 0) / parent.t))
                        height: parent.height
                        color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.35)
                    }
                }
                Row {
                    spacing: 16
                    Row { spacing: 6; Rectangle { width: 10; height: 10; radius: 3; color: theme.accent; anchors.verticalCenter: parent.verticalCenter } Text { text: "En uso"; color: theme.contentTextSecondary; font.pixelSize: 11 } }
                    Row { spacing: 6; Rectangle { width: 10; height: 10; radius: 3; color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.35); anchors.verticalCenter: parent.verticalCenter } Text { text: "En caché (se libera sola si hace falta)"; color: theme.contentTextSecondary; font.pixelSize: 11 } }
                }
            }
        }
    }
}
