// Cápsula: los tres botones juntos en una cápsula a la derecha.
// Estilo de botones de ventana de Inti OS. Fichero independiente: no depende
// de los otros estilos. TitanWindow carga solo el elegido en Ajustes > Ventanas.
import QtQuick

Item {
    id: raiz
    // ---- Lo que le pasa TitanWindow (igual en todos los estilos) ----
    property var tema: null
    property bool activa: true
    property real radioEsquina: 0
    property real altoBarra: 50
    signal cerrar()
    signal minimizar()
    signal maximizar()
    readonly property bool oscuro: tema ? tema.isDark : false
    readonly property color acento: tema ? tema.accent : "#0071e3"
    readonly property color tinta: oscuro ? "#f2f2f5" : "#1d1d1f"
    function accion(t) { if (t === "close") cerrar(); else if (t === "min") minimizar(); else maximizar() }

    readonly property bool derecha: true
    readonly property real margen: 12

    // Simbolo _ [] X dibujado con rectangulos (nitido a cualquier escala)
    component Simbolo: Item {
        id: sim
        property string tipo: "close"
        property real lado: 10
        property real grosor: 1.4
        property color color: "white"
        width: lado; height: lado
        Rectangle {
            visible: sim.tipo === "min"
            anchors.centerIn: parent
            width: sim.lado; height: sim.grosor; radius: sim.grosor / 2
            color: sim.color
        }
        Rectangle {
            visible: sim.tipo === "max"
            anchors.fill: parent
            color: "transparent"; radius: sim.lado * 0.18
            border.width: sim.grosor; border.color: sim.color
        }
        Repeater {
            model: sim.tipo === "close" ? [45, -45] : []
            Rectangle {
                required property var modelData
                anchors.centerIn: parent
                width: sim.lado * 1.36; height: sim.grosor; radius: sim.grosor / 2
                rotation: modelData
                color: sim.color
            }
        }
    }


    implicitWidth: capsula.width
    implicitHeight: capsula.height
    Rectangle {
        id: capsula
        width: 120; height: 30; radius: 15
        color: Qt.rgba(raiz.tinta.r, raiz.tinta.g, raiz.tinta.b, 0.08)
        Row {
            Repeater {
                model: ["min", "max", "close"]
                delegate: Rectangle {
                    id: b
                    required property string modelData
                    required property int index
                    readonly property bool cierre: modelData === "close"
                    width: 40; height: 30
                    topLeftRadius: index === 0 ? 15 : 0
                    bottomLeftRadius: index === 0 ? 15 : 0
                    topRightRadius: cierre ? 15 : 0
                    bottomRightRadius: cierre ? 15 : 0
                    color: !zona.containsMouse ? "transparent"
                         : cierre ? (zona.pressed ? "#c93a3f" : "#e5484d")
                         : Qt.rgba(raiz.tinta.r, raiz.tinta.g, raiz.tinta.b, zona.pressed ? 0.2 : 0.12)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Rectangle {   // raya entre botones
                        visible: b.index > 0
                        x: 0; anchors.verticalCenter: parent.verticalCenter
                        width: 1; height: 16
                        color: Qt.rgba(raiz.tinta.r, raiz.tinta.g, raiz.tinta.b, 0.15)
                    }
                    Simbolo {
                        anchors.centerIn: parent
                        tipo: b.modelData; lado: 9; grosor: 1.4
                        color: (b.cierre && zona.containsMouse) ? "white" : raiz.tinta
                        opacity: raiz.activa || zona.containsMouse ? 1 : 0.45
                    }
                    MouseArea { id: zona; anchors.fill: parent; hoverEnabled: true; onClicked: raiz.accion(b.modelData) }
                }
            }
        }
    }
}
