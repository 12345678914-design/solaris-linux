import QtQuick
import QtQuick.Controls

// Panel de detalles del Explorador de archivos: vista previa grande, datos y
// acciones del elemento seleccionado (o de la carpeta abierta si no hay nada).
Rectangle {
    id: panel
    property var lista
    TitanTheme { id: theme }

    color: theme.isDark ? "#0e0e10" : "#f6f6f8"
    Rectangle { width: 1; height: parent.height; color: theme.contentCardBorder }

    readonly property int nSel: lista ? lista.nSel : 0
    readonly property string ruta: nSel === 1 ? lista.selectedPaths[0] : ""
    property var d: ({})
    function actualizar() {
        if (nSel > 1) d = ({})
        else if (nSel === 0 && finderBackend.enRecientes)
            d = { nombre: "Recientes", tipo: "Lo último que has abierto", icono: "qrc:/icons/notes.png" }
        else d = finderBackend.detalles(ruta)
    }
    onRutaChanged: actualizar()
    onNSelChanged: actualizar()
    Component.onCompleted: actualizar()
    Connections {
        target: finderBackend
        function onEntriesChanged() { panel.actualizar() }
        function onCurrentPathChanged() { panel.actualizar() }
    }

    function urlDe(p) { return "file://" + p.split("/").map(encodeURIComponent).join("/") }

    component Accion: Rectangle {
        id: a
        property string texto: ""
        property bool primario: false
        signal pulsado()
        width: parent ? parent.width : 100
        height: 32; radius: 8
        color: primario ? (z1.containsMouse ? Qt.darker(theme.accent, 1.1) : theme.accent)
                        : (z1.containsMouse ? theme.itemHover : theme.contentBackground)
        border.color: primario ? "transparent" : theme.contentCardBorder
        Text {
            anchors.centerIn: parent
            text: a.texto
            color: a.primario ? "#ffffff" : theme.contentTextPrimary
            font.pixelSize: 12
            font.weight: a.primario ? Font.DemiBold : Font.Normal
        }
        MouseArea { id: z1; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: a.pulsado() }
    }
    component Dato: Item {
        property string k: ""
        property string v: ""
        visible: v !== ""
        width: parent ? parent.width : 100
        height: visible ? 24 : 0
        Text { id: clave; text: parent.k; color: theme.contentTextSecondary; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: parent.v; color: theme.contentTextPrimary; font.pixelSize: 12
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - clave.implicitWidth - 10); elide: Text.ElideMiddle; horizontalAlignment: Text.AlignRight
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 1
        contentHeight: col.implicitHeight + 36
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: col
            x: 18; y: 18
            width: panel.width - 37
            spacing: 14

            // Vista previa
            Rectangle {
                width: parent.width
                height: Math.round(width * 0.72)
                radius: 12
                clip: true
                color: theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04)
                Image {
                    id: foto
                    anchors.fill: parent
                    visible: !!panel.d.esFoto && status === Image.Ready
                    source: panel.d.esFoto ? panel.urlDe(panel.d.ruta) : ""
                    sourceSize.width: 520
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                }
                Image {
                    visible: !foto.visible
                    anchors.centerIn: parent
                    width: 96; height: 96
                    source: panel.nSel > 1 ? "qrc:/icons/file-generic.png" : (panel.d.icono ? theme.tinte(panel.d.icono) : "")
                    sourceSize: Qt.size(128, 128)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                Rectangle {
                    visible: panel.nSel > 1
                    anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 12
                    width: 34; height: 34; radius: 17
                    color: theme.accent
                    Text { anchors.centerIn: parent; text: panel.nSel; color: "#ffffff"; font.pixelSize: 14; font.bold: true }
                }
            }

            Column {
                width: parent.width
                spacing: 3
                Text {
                    width: parent.width
                    text: panel.nSel > 1 ? panel.nSel + " elementos seleccionados" : (panel.d.nombre || "")
                    color: theme.contentTextPrimary
                    font.pixelSize: 15; font.bold: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: panel.nSel <= 1
                    text: (panel.d.tipo || "") + (panel.d.tamano ? " · " + panel.d.tamano : "")
                    color: theme.contentTextSecondary
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            Rectangle { visible: panel.nSel <= 1; width: parent.width; height: 1; color: theme.contentCardBorder }

            Column {
                visible: panel.nSel <= 1
                width: parent.width
                Dato { k: "Dimensiones"; v: panel.d.dimensiones || "" }
                Dato { k: "Creado"; v: panel.d.creado || "" }
                Dato { k: "Modificado"; v: panel.d.modificado || "" }
                Dato { k: "Dónde"; v: panel.d.carpeta || "" }
            }

            Column {
                width: parent.width
                spacing: 8
                Accion {
                    visible: panel.nSel === 1
                    texto: panel.d.esCarpeta ? "Abrir carpeta" : "Abrir"
                    primario: true
                    onPulsado: finderBackend.openItem(panel.ruta)
                }
                Accion {
                    visible: panel.nSel === 1 && (finderBackend.enRecientes || finderBackend.searchQuery !== "")
                    texto: "Abrir la carpeta donde está"
                    onPulsado: panel.lista.mostrarEnSuCarpeta(panel.ruta)
                }
                Accion {
                    visible: panel.nSel === 1 && !!panel.d.esFoto
                    texto: "Poner como fondo de pantalla"
                    onPulsado: titanThemeManager.wallpaper = panel.ruta
                }
                Accion {
                    visible: panel.nSel === 0 && !finderBackend.enPapelera && !finderBackend.enRecientes && !finderBackend.enRed
                    texto: "Abrir en Terminal"
                    onPulsado: finderBackend.openTerminal()
                }
                Accion {
                    visible: !finderBackend.enPapelera && !finderBackend.enRed && (panel.nSel > 0 || !finderBackend.enRecientes)
                    texto: panel.nSel > 1 ? "Copiar las rutas" : "Copiar ruta"
                    onPulsado: finderBackend.copiarRuta(panel.nSel > 0 ? panel.lista.objetivo() : [finderBackend.currentPath])
                }
                Accion {
                    visible: panel.nSel > 0 && !finderBackend.enPapelera && !finderBackend.enRed
                    texto: "Propiedades"
                    onPulsado: panel.lista.openProperties(panel.nSel === 1 ? panel.ruta : panel.lista.selectedPath)
                }
            }
        }
    }
}
