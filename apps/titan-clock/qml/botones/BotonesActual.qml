// Actual: semáforo de colores a la izquierda; los símbolos salen al pasar el ratón.
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

    readonly property bool derecha: false
    readonly property real margen: 18


    implicitWidth: fila.width
    implicitHeight: fila.height
    HoverHandler { id: grupo }
    Row {
        id: fila
        spacing: 8
        Repeater {
            model: [
                { col: "#ff5f57", borde: "#e0443e", glifo: "\u00d7", t: "close" },
                { col: "#febc2e", borde: "#dea123", glifo: "\u2212", t: "min" },
                { col: "#28c840", borde: "#1aab29", glifo: "+",      t: "max" }
            ]
            delegate: Rectangle {
                required property var modelData
                readonly property bool encendido: raiz.activa || grupo.hovered
                width: 12; height: 12; radius: 6
                color: encendido ? modelData.col : (raiz.oscuro ? "#5c5c60" : "#c8c8cc")
                border.color: encendido ? modelData.borde : (raiz.oscuro ? "#4a4a4e" : "#b4b4b8")
                border.width: 0.5
                scale: zona.pressed ? 0.9 : 1.0
                Behavior on scale { NumberAnimation { duration: 90 } }
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -0.5
                    text: modelData.glifo
                    visible: grupo.hovered
                    color: Qt.rgba(0, 0, 0, 0.6)
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
                MouseArea { id: zona; anchors.fill: parent; onClicked: raiz.accion(modelData.t) }
            }
        }
    }
}
