// Contorno fino: círculos de línea; el contorno toma el acento (rojo en cerrar) al pasar el ratón.
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


    implicitWidth: fila.width
    implicitHeight: fila.height
    Row {
        id: fila
        spacing: 7
        Repeater {
            model: ["min", "max", "close"]
            delegate: Rectangle {
                id: b
                required property string modelData
                readonly property color tinte: modelData === "close" ? "#e5484d" : raiz.acento
                width: 23; height: 23; radius: 11.5
                color: zona.containsMouse ? Qt.rgba(tinte.r, tinte.g, tinte.b, zona.pressed ? 0.3 : 0.15) : "transparent"
                border.width: 1.2
                border.color: zona.containsMouse ? tinte
                            : Qt.rgba(raiz.tinta.r, raiz.tinta.g, raiz.tinta.b, raiz.activa ? 0.45 : 0.25)
                Behavior on color { ColorAnimation { duration: 100 } }
                Simbolo {
                    anchors.centerIn: parent
                    tipo: b.modelData; lado: 7.5; grosor: 1.4
                    color: zona.containsMouse ? b.tinte : raiz.tinta
                    opacity: raiz.activa || zona.containsMouse ? 1 : 0.45
                }
                MouseArea { id: zona; anchors.fill: parent; hoverEnabled: true; onClicked: raiz.accion(b.modelData) }
            }
        }
    }
}
