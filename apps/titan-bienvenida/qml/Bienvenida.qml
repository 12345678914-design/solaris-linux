import QtQuick
import QtQuick.Controls

// Bienvenida de Inti OS: 5 pasos cortos. Lo elegido se aplica al momento
// (esta misma ventana cambia sus botones y sus colores) y se puede cambiar
// después en Ajustes.
TitanWindow {
    id: ventana
    title: "Bienvenida"
    width: 820
    height: 600
    minimumWidth: 720
    minimumHeight: 560
    showSidebar: false
    showStatusBar: false

    property int paso: 0
    readonly property int pasos: 5
    readonly property string estilo: titanThemeManager.windowStyle

    onClosing: bienvenida.terminar()

    Shortcut { sequences: ["Right", "Return", "Enter"]; onActivated: ventana.siguiente() }
    Shortcut { sequence: "Left"; onActivated: if (ventana.paso > 0) ventana.paso -= 1 }

    function siguiente() {
        if (paso < pasos - 1) paso += 1
        else { bienvenida.terminar(); Qt.quit() }
    }

    readonly property color texto: theme.contentTextPrimary
    readonly property color tenue: theme.contentTextSecondary
    readonly property color tarjeta: theme.isDark ? "#161618" : "#f5f5f7"

    headerContentData: Item {
        anchors.fill: parent
        Text {
            anchors.centerIn: parent
            text: "Bienvenida a Inti OS"
            color: theme.headerText
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
    }

    // Tarjeta elegible (estilo de botones, modo)
    component Opcion: Rectangle {
        id: op
        property bool elegida: false
        property string titulo: ""
        property string detalle: ""
        default property alias vista: muestra.data
        signal elegir()
        width: 300
        height: 228
        radius: 14
        color: ventana.tarjeta
        border.width: elegida ? 2.5 : 1
        border.color: elegida ? theme.accent : theme.contentCardBorder
        Item {
            id: muestra
            x: 18; y: 18
            width: parent.width - 36
            height: 130
        }
        Text {
            x: 18
            anchors.top: muestra.bottom
            anchors.topMargin: 14
            text: op.titulo
            color: ventana.texto
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
        Text {
            x: 18
            width: parent.width - 36
            anchors.top: muestra.bottom
            anchors.topMargin: 36
            text: op.detalle
            wrapMode: Text.Wrap
            color: ventana.tenue
            font.pixelSize: 12
        }
        Rectangle {
            visible: op.elegida
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            width: 22; height: 22; radius: 11
            color: theme.accent
            Text { anchors.centerIn: parent; text: "✓"; color: "#ffffff"; font.pixelSize: 13; font.bold: true }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: op.elegir() }
    }

    // Ventana en miniatura para enseñar dónde van los botones
    component Miniatura: Rectangle {
        id: mini
        property bool windows: false
        property bool oscura: theme.isDark
        anchors.fill: parent
        radius: 10
        color: oscura ? "#000000" : "#ffffff"
        border.color: oscura ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.14)
        Rectangle {
            id: barra
            width: parent.width; height: 30
            radius: 10
            color: mini.oscura ? "#1c1c1f" : "#ebebef"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 10; color: parent.color }
        }
        Row {
            visible: !mini.windows
            x: 12
            anchors.verticalCenter: barra.verticalCenter
            spacing: 7
            Repeater {
                model: ["#ff5f57", "#febc2e", "#28c840"]
                delegate: Rectangle { required property string modelData; width: 12; height: 12; radius: 6; color: modelData }
            }
        }
        Row {
            visible: mini.windows
            anchors.right: parent.right
            anchors.verticalCenter: barra.verticalCenter
            Repeater {
                model: ["—", "☐", "✕"]
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    width: 34; height: 30
                    color: index === 2 ? "#e81123" : "transparent"
                    radius: index === 2 ? 0 : 0
                    Text { anchors.centerIn: parent; text: modelData; color: index === 2 ? "#ffffff" : (mini.oscura ? "#f2f2f5" : "#1d1d1f"); font.pixelSize: 12 }
                }
            }
        }
        Column {
            x: 14; y: 44
            spacing: 8
            Repeater {
                model: [0.8, 0.55, 0.7]
                delegate: Rectangle {
                    required property real modelData
                    width: (mini.width - 28) * modelData; height: 8; radius: 4
                    color: mini.oscura ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                }
            }
        }
    }

    // ------------------------------------------------------------ pasos
    Rectangle {
        anchors.fill: parent
        color: theme.contentBackground

        Item {
            id: zona
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: pie.top
            anchors.margins: 30

            // 0. Hola
            Column {
                visible: ventana.paso === 0
                anchors.centerIn: parent
                width: Math.min(parent.width, 560)
                spacing: 18
                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: "qrc:/icons/inti.png"
                    width: 170; height: 170
                    sourceSize: Qt.size(340, 340)
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Te damos la bienvenida a Inti OS"
                    color: ventana.texto
                    font.pixelSize: 28
                    font.bold: true
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: "Un sistema fácil de usar, rápido y sin telemetría. En un minuto lo dejamos a tu gusto: si vienes de Windows, te vas a sentir en casa."
                    color: ventana.tenue
                    font.pixelSize: 15
                    lineHeight: 1.15
                }
            }

            // 1. Botones de las ventanas
            Column {
                visible: ventana.paso === 1
                anchors.centerIn: parent
                spacing: 22
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "¿Dónde quieres los botones de las ventanas?"
                    color: ventana.texto
                    font.pixelSize: 22
                    font.bold: true
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 20
                    Opcion {
                        titulo: "Estilo Inti"
                        detalle: "Círculos de colores a la izquierda: cerrar, minimizar y maximizar."
                        elegida: ventana.estilo !== "windows"
                        onElegir: titanThemeManager.windowStyle = "actual"
                        Miniatura { windows: false }
                    }
                    Opcion {
                        titulo: "Estilo Windows"
                        detalle: "_  ☐  ✕ a la derecha, como en Windows."
                        elegida: ventana.estilo === "windows"
                        onElegir: titanThemeManager.windowStyle = "windows"
                        Miniatura { windows: true }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Hay más estilos en Ajustes › Ventanas"
                    color: ventana.tenue
                    font.pixelSize: 12
                }
            }

            // 2. Claro u oscuro y color
            Column {
                visible: ventana.paso === 2
                anchors.centerIn: parent
                spacing: 22
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "¿Claro u oscuro?"
                    color: ventana.texto
                    font.pixelSize: 22
                    font.bold: true
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 20
                    Opcion {
                        titulo: "Claro"
                        detalle: "Fondos blancos. Cómodo de día."
                        elegida: !theme.isDark
                        onElegir: titanThemeManager.isDark = false
                        Miniatura { windows: ventana.estilo === "windows"; oscura: false }
                    }
                    Opcion {
                        titulo: "Oscuro"
                        detalle: "Fondos negros. Descansa la vista de noche."
                        elegida: theme.isDark
                        onElegir: titanThemeManager.isDark = true
                        Miniatura { windows: ventana.estilo === "windows"; oscura: true }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Color de acento"
                    color: ventana.texto
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12
                    Repeater {
                        model: ["#0071e3", "#5e5ce6", "#af52de", "#ff2d55", "#ff3b30", "#ff9500", "#ffcc00", "#34c759", "#00a3a3", "#8e8e93"]
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool sel: String(theme.accent).toLowerCase() === modelData
                            width: 28; height: 28; radius: 14
                            color: modelData
                            border.width: sel ? 3 : 0
                            border.color: theme.isDark ? "#ffffff" : "#1d1d1f"
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: titanThemeManager.accent = modelData }
                        }
                    }
                }
            }

            // 3. Atajos
            Column {
                visible: ventana.paso === 3
                anchors.centerIn: parent
                width: Math.min(parent.width, 620)
                spacing: 16
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Atajos que te sirven desde hoy"
                    color: ventana.texto
                    font.pixelSize: 22
                    font.bold: true
                }
                Grid {
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: 2
                    columnSpacing: 28
                    rowSpacing: 10
                    Repeater {
                        model: [
                            ["Win", "Menú de inicio"], ["Alt + Tab", "Cambiar de ventana"],
                            ["Win + E", "Explorador de archivos"], ["Win + Q  o  Alt + F4", "Cerrar la ventana"],
                            ["Win + D", "Ver el escritorio"], ["Win + F", "Maximizar"],
                            ["Win + L", "Bloquear"], ["Win + V", "Historial del portapapeles"],
                            ["Win + I", "Ajustes"], ["Win + .", "Emojis"],
                            ["Win + Mayús + S", "Captura de una zona"], ["Ctrl + Alt + Supr", "Bloquear, apagar..."]
                        ]
                        delegate: Row {
                            required property var modelData
                            spacing: 10
                            width: 290
                            Rectangle {
                                width: Math.max(44, tt.implicitWidth + 16); height: 24; radius: 6
                                color: ventana.tarjeta
                                border.color: theme.contentCardBorder
                                Text { id: tt; anchors.centerIn: parent; text: modelData[0]; color: ventana.texto; font.pixelSize: 12; font.weight: Font.DemiBold }
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: ventana.texto; font.pixelSize: 13 }
                        }
                    }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: "Win es la tecla con el logotipo de Windows. Con Win + F1 ves todos los atajos cuando quieras."
                    color: ventana.tenue
                    font.pixelSize: 12
                }
            }

            // 4. Listo
            Column {
                visible: ventana.paso === 4
                anchors.centerIn: parent
                width: Math.min(parent.width, 600)
                spacing: 14
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Todo listo"
                    color: ventana.texto
                    font.pixelSize: 26
                    font.bold: true
                }
                Repeater {
                    model: [
                        ["App Store", "Para instalar programas: búscalo y pulsa Instalar.", "tienda"],
                        ["Programas de Windows (.exe)", "Ábrelos con doble clic. La primera vez Inti te ofrece instalar lo necesario.", ""],
                        ["Ajustes", "Wi-Fi, pantalla, impresoras, usuarios, fondo y mucho más.", "ajustes"],
                        ["Manual de Inti", "Cómo hacer cada cosa, explicado paso a paso.", "manual"]
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 58
                        radius: 12
                        color: zl.containsMouse && modelData[2] !== "" ? theme.itemHover : ventana.tarjeta
                        Column {
                            x: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Text { text: modelData[0]; color: ventana.texto; font.pixelSize: 14; font.weight: Font.DemiBold }
                            Text { text: modelData[1]; color: ventana.tenue; font.pixelSize: 12 }
                        }
                        Text {
                            visible: modelData[2] !== ""
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Abrir ›"
                            color: theme.accent
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: zl
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: modelData[2] !== ""
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bienvenida.abrir(modelData[2])
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------------ pie
        Item {
            id: pie
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 70

            Row {
                anchors.centerIn: parent
                spacing: 8
                Repeater {
                    model: ventana.pasos
                    delegate: Rectangle {
                        required property int index
                        width: index === ventana.paso ? 22 : 8
                        height: 8
                        radius: 4
                        color: index === ventana.paso ? theme.accent : theme.contentCardBorder
                        Behavior on width { NumberAnimation { duration: 150 } }
                    }
                }
            }

            Text {
                visible: ventana.paso > 0
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                text: "Atrás"
                color: ventana.tenue
                font.pixelSize: 14
                MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: ventana.paso -= 1 }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                width: tsig.implicitWidth + 40
                height: 38
                radius: 10
                color: zs.containsMouse ? Qt.darker(theme.accent, 1.1) : theme.accent
                Text {
                    id: tsig
                    anchors.centerIn: parent
                    text: ventana.paso === 0 ? "Empezar" : ventana.paso === ventana.pasos - 1 ? "Ir al escritorio" : "Siguiente"
                    color: "#ffffff"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                MouseArea { id: zs; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ventana.siguiente() }
            }
        }
    }
}
