// Explorador de archivos: pestañas, como en el Explorador de Windows 11.
//  - Clic: ir a la pestaña. Clic central o ×: cerrarla. +: una nueva.
//  - Arrastrar dentro de la tira: cambiar el orden.
//  - Arrastrar a otra ventana del Explorador: se junta con las suyas.
//  - Soltarla fuera de cualquier ventana: se abre en una ventana nueva.
// Cada ventana es un proceso: la pestaña viaja por arrastrar y soltar del
// sistema (tipo application/x-inti-pestana) con su carpeta y su historial.
import QtQuick

Rectangle {
    id: tira
    property var alCerrar: function (i) {}
    property var alQuedarseSin: function () {}
    // La que se está arrastrando desde esta ventana (-1 = ninguna)
    property int origen: -1
    // true si se soltó en esta misma ventana (Wayland no distingue la acción)
    property bool soltadaAqui: false
    // Hueco donde caería al soltar (-1 = ninguno)
    property int destino: -1
    readonly property int n: finderBackend.pestanas.length
    readonly property real anchoPestana: Math.max(90, Math.min(220, (width - 52) / Math.max(1, n)))

    height: 36
    color: theme.isDark ? "#0b0b0d" : "#ebebef"
    TitanTheme { id: theme }

    // Índice de la pestaña bajo la x de la tira
    function indiceEn(x) { return Math.max(0, Math.min(n, Math.round((x - 6) / anchoPestana))) }

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.contentCardBorder }

    Row {
        id: fila
        x: 6
        anchors.bottom: parent.bottom
        spacing: 0
        Repeater {
            model: finderBackend.pestanas
            delegate: Item {
                id: pes
                required property var modelData
                required property int index
                readonly property bool actual: index === finderBackend.pestanaActual
                width: tira.anchoPestana
                height: 31
                opacity: tira.origen === index ? 0.45 : 1

                // Forma de pestaña: esquinas de arriba redondeadas
                Rectangle {
                    anchors.fill: parent
                    anchors.bottomMargin: pes.actual ? -1 : 3
                    anchors.topMargin: pes.actual ? 0 : 2
                    radius: 8
                    color: pes.actual ? theme.contentBackground
                                      : (zonaPes.containsMouse ? theme.itemHover : "transparent")
                    border.color: pes.actual ? theme.contentCardBorder : "transparent"
                    Rectangle {   // tapa el borde de abajo para que se una al contenido
                        visible: pes.actual
                        anchors.bottom: parent.bottom
                        x: 1; width: parent.width - 2; height: 9
                        color: theme.contentBackground
                    }
                }
                // Separador fino entre pestañas inactivas
                Rectangle {
                    visible: !pes.actual && pes.index + 1 !== finderBackend.pestanaActual && pes.index < tira.n - 1
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1; height: 14
                    color: theme.contentCardBorder
                }
                // Marca de dónde caerá al soltar
                Rectangle {
                    visible: tira.destino === pes.index
                    x: -1; width: 3; height: parent.height - 6; y: 3; radius: 1.5
                    color: theme.accent
                    z: 3
                }
                Image {
                    id: icoPes
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    source: pes.modelData.titulo === "Papelera" ? "qrc:/icons/trash.png"
                            : pes.modelData.titulo === "Red" || pes.modelData.ruta.indexOf("://") > 0 && pes.modelData.ruta.indexOf("recent:") !== 0 ? "qrc:/icons/monitor.png"
                            : "qrc:/icons/folder.png"
                    sourceSize: Qt.size(32, 32)
                    smooth: true
                }
                Text {
                    anchors.left: icoPes.right; anchors.leftMargin: 7
                    anchors.right: cerrar.left; anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: pes.modelData.titulo
                    elide: Text.ElideRight
                    color: pes.actual ? theme.contentTextPrimary : theme.contentTextSecondary
                    font.pixelSize: 12
                    font.weight: pes.actual ? Font.DemiBold : Font.Normal
                }

                // Lo que se arrastra (invisible): así la pestaña no se mueve sola
                Item {
                    id: fantasma
                    width: pes.width; height: pes.height
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.MoveAction | Qt.CopyAction
                    Drag.mimeData: ({ "application/x-inti-pestana": tira.datos })
                    Drag.active: zonaPes.drag.active
                    Drag.onDragStarted: { tira.origen = pes.index; tira.soltadaAqui = false }
                    Drag.onDragFinished: (accion) => {
                        const i = tira.origen
                        tira.origen = -1
                        tira.destino = -1
                        fantasma.x = 0; fantasma.y = 0
                        if (tira.soltadaAqui) {
                            // Se reordenó en esta ventana: nada más
                        } else if (accion !== Qt.IgnoreAction) {
                            // Se la quedó otra ventana: aquí se cierra
                            tira.alCerrar(i)
                        } else if (tira.n > 1) {
                            // Soltada fuera: a una ventana nueva
                            finderBackend.separarPestana(i)
                        }
                    }
                }
                MouseArea {
                    id: zonaPes
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    drag.target: fantasma
                    drag.threshold: 12
                    onPressed: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            finderBackend.irAPestana(pes.index)
                            tira.datos = finderBackend.datosPestana(pes.index)
                            pes.grabToImage(function (r) { fantasma.Drag.imageSource = r.url })
                        }
                    }
                    onClicked: (mouse) => { if (mouse.button === Qt.MiddleButton) tira.alCerrar(pes.index) }
                }
                // ×
                Rectangle {
                    id: cerrar
                    anchors.right: parent.right; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20; radius: 5
                    visible: pes.actual || zonaPes.containsMouse || zonaCerrar.containsMouse
                    color: zonaCerrar.containsMouse ? theme.itemHover : "transparent"
                    Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 10; color: theme.contentTextSecondary }
                    MouseArea {
                        id: zonaCerrar
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: tira.alCerrar(pes.index)
                    }
                }
            }
        }
        // +
        Item {
            width: 36; height: 31
            Rectangle {
                anchors.centerIn: parent
                width: 26; height: 26; radius: 6
                color: zonaMas.containsMouse ? theme.itemHover : "transparent"
                Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 17; color: theme.contentTextSecondary }
            }
            MouseArea { id: zonaMas; anchors.fill: parent; hoverEnabled: true; onClicked: finderBackend.nuevaPestana() }
        }
    }
    property string datos: ""
}
