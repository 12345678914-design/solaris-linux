// Color a la derecha: círculos de color con el símbolo siempre visible, en el orden _ □ X.
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
    readonly property real margen: 14

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
    implicitHeight: fila.height
    Row {
        id: fila
        spacing: 9
        Repeater {
            model: [
                { t: "min", col: "#febc2e" },
                { t: "max", col: "#28c840" },
                { t: "close", col: "#ff5f57" }
            ]
            delegate: Rectangle {
                id: b
                required property var modelData
                width: 18; height: 18; radius: 9
                color: raiz.activa || zona.containsMouse ? modelData.col : (raiz.oscuro ? "#4b4e58" : "#cfcfd3")
                border.width: 0.6
                border.color: Qt.rgba(0, 0, 0, 0.15)
                scale: zona.pressed ? 0.9 : zona.containsMouse ? 1.08 : 1.0
                Behavior on scale { NumberAnimation { duration: 90 } }
                Behavior on color { ColorAnimation { duration: 150 } }
                Simbolo {
                    anchors.centerIn: parent
                    tipo: b.modelData.t; lado: b.modelData.t === "max" ? 7 : 7.5; grosor: 1.5
                    color: Qt.rgba(0, 0, 0, raiz.activa || zona.containsMouse ? 0.62 : 0.35)
                }
                MouseArea { id: zona; anchors.fill: parent; hoverEnabled: true; onClicked: raiz.accion(b.modelData.t) }
            }
        }
    }
}
