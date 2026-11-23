// Estilo Windows: _ □ X planos a la derecha, zonas anchas de todo el alto; cerrar se pone rojo.
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
    readonly property real margen: 0

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


    implicitWidth: fila.width
    implicitHeight: altoBarra
    Row {
        id: fila
        Repeater {
            model: ["min", "max", "close"]
            delegate: Rectangle {
                id: b
                required property string modelData
                required property int index
                readonly property bool cierre: modelData === "close"
                width: 46; height: raiz.altoBarra
                topRightRadius: cierre ? raiz.radioEsquina : 0
                color: zona.pressed ? (cierre ? "#b3261e" : Qt.rgba(raiz.tinta.r, raiz.tinta.g, raiz.tinta.b, 0.05))
                     : zona.containsMouse ? (cierre ? "#c42b1c" : Qt.rgba(raiz.tinta.r, raiz.tinta.g, raiz.tinta.b, 0.09))
                     : "transparent"
                Behavior on color { ColorAnimation { duration: 90 } }
                Simbolo {
                    anchors.centerIn: parent
                    tipo: b.modelData; lado: 10; grosor: 1.1
                    color: (b.cierre && zona.containsMouse) ? "white" : raiz.tinta
                    opacity: raiz.activa || zona.containsMouse ? 1 : 0.45
                }
                MouseArea { id: zona; anchors.fill: parent; hoverEnabled: true; onClicked: raiz.accion(b.modelData) }
            }
        }
    }
}
