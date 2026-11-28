import QtQuick 2.15
import QtQuick.Controls 2.15

TitanWindow {
    id: calcWindow

    readonly property bool isSci: typeof calcBackend !== "undefined" && calcBackend && calcBackend.isScientific
    readonly property string dispText: (typeof calcBackend !== "undefined" && calcBackend) ? calcBackend.display : "0"
    readonly property string exprText: (typeof calcBackend !== "undefined" && calcBackend) ? calcBackend.expression : ""

    title: "Calculadora"
    width: isSci ? 540 : 330
    height: 480
    minimumWidth: isSci ? 540 : 330
    maximumWidth: isSci ? 540 : 330
    minimumHeight: 480
    maximumHeight: 480
    sidebarWidth: 0
    showSidebar: false
    showStatusBar: false

    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    headerContentData: Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 14
        spacing: 6

        // Botón conmutador Científica / Básica
        Rectangle {
            width: sciText.implicitWidth + 14
            height: 24
            radius: 6
            color: sciMouse.containsMouse ? (isSci ? theme.accent : Qt.rgba(1, 1, 1, 0.18))
                                          : (isSci ? theme.accent : Qt.rgba(1, 1, 1, 0.08))
            border.color: theme.glassBorder
            border.width: 1

            Text {
                id: sciText
                anchors.centerIn: parent
                text: isSci ? "Básica" : "Científica"
                color: isSci ? "#ffffff" : theme.headerText
                font.pixelSize: 11
                font.weight: Font.Medium
            }

            MouseArea {
                id: sciMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (calcBackend) calcBackend.isScientific = !calcBackend.isScientific
            }
        }
    }

    // Atajos de teclado
    Shortcut { sequence: "0"; onActivated: calcBackend.inputDigit("0") }
    Shortcut { sequence: "1"; onActivated: calcBackend.inputDigit("1") }
    Shortcut { sequence: "2"; onActivated: calcBackend.inputDigit("2") }
    Shortcut { sequence: "3"; onActivated: calcBackend.inputDigit("3") }
    Shortcut { sequence: "4"; onActivated: calcBackend.inputDigit("4") }
    Shortcut { sequence: "5"; onActivated: calcBackend.inputDigit("5") }
    Shortcut { sequence: "6"; onActivated: calcBackend.inputDigit("6") }
    Shortcut { sequence: "7"; onActivated: calcBackend.inputDigit("7") }
    Shortcut { sequence: "8"; onActivated: calcBackend.inputDigit("8") }
    Shortcut { sequence: "9"; onActivated: calcBackend.inputDigit("9") }
    Shortcut { sequence: "."; onActivated: calcBackend.inputDot() }
    Shortcut { sequence: ","; onActivated: calcBackend.inputDot() }
    Shortcut { sequence: "+"; onActivated: calcBackend.inputOperator("+") }
    Shortcut { sequence: "-"; onActivated: calcBackend.inputOperator("−") }
    Shortcut { sequence: "*"; onActivated: calcBackend.inputOperator("×") }
    Shortcut { sequence: "/"; onActivated: calcBackend.inputOperator("÷") }
    Shortcut { sequence: "Return"; onActivated: calcBackend.calculate() }
    Shortcut { sequence: "Enter"; onActivated: calcBackend.calculate() }
    Shortcut { sequence: "="; onActivated: calcBackend.calculate() }
    Shortcut { sequence: "Escape"; onActivated: calcBackend.clear() }
    Shortcut { sequence: "Backspace"; onActivated: calcBackend.deleteLast() }
    Shortcut { sequence: "%"; onActivated: calcBackend.percent() }

    Rectangle {
        anchors.fill: parent
        color: theme.contentBackground

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            // Pantalla de la calculadora
            Rectangle {
                width: parent.width
                height: 80
                radius: 12
                color: theme.contentCardBg
                border.color: theme.contentCardBorder
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 4

                    Text {
                        width: parent.width
                        text: calcWindow.exprText
                        color: theme.contentTextSecondary
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                    }

                    Text {
                        width: parent.width
                        text: calcWindow.dispText
                        color: theme.contentTextPrimary
                        font.pixelSize: text.length > 10 ? 24 : (text.length > 8 ? 28 : 34)
                        font.bold: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                    }
                }
            }

            // Teclado: filas explícitas (un Grid daba al "0" doble ancho a toda
            // su columna y empujaba la de operadores fuera de la ventana)
            Row {
                id: teclado
                width: parent.width
                height: parent.height - 92
                spacing: 10

                readonly property int sep: 8
                readonly property real bH: Math.floor((height - sep * 4) / 5)

                // Panel científico (3 columnas)
                Column {
                    id: sciPanel
                    visible: calcWindow.isSci
                    width: visible ? 200 : 0
                    spacing: teclado.sep
                    readonly property real bW: Math.floor((width - teclado.sep * 2) / 3)

                    Repeater {
                        model: [
                            [["sin", "trigSin"], ["cos", "trigCos"], ["tan", "trigTan"]],
                            [["x²", "sqrOp"], ["√x", "sqrtOp"], ["xʸ", "^"]],
                            [["1/x", "invOp"], ["ln", "lnOp"], ["log", "log10Op"]],
                            [["π", "constPi"], ["e", "constE"], ["MC", "memoryClear"]],
                            [["MR", "memoryRecall"], ["M+", "memoryAdd"], ["M−", "memorySubtract"]]
                        ]
                        delegate: Row {
                            required property var modelData
                            spacing: teclado.sep
                            Repeater {
                                model: parent.modelData
                                delegate: CalcButton {
                                    required property var modelData
                                    text: modelData[0]
                                    type: "sci"
                                    width: sciPanel.bW
                                    height: teclado.bH
                                    onClicked: {
                                        if (!calcBackend) return
                                        if (modelData[1] === "^") calcBackend.inputOperator("^")
                                        else calcBackend[modelData[1]]()
                                    }
                                }
                            }
                        }
                    }
                }

                // Panel estándar (4 columnas)
                Column {
                    id: stdPanel
                    width: parent.width - (calcWindow.isSci ? sciPanel.width + teclado.spacing : 0)
                    spacing: teclado.sep
                    readonly property real bW: Math.floor((width - teclado.sep * 3) / 4)

                    Row {
                        spacing: teclado.sep
                        CalcButton { text: calcWindow.dispText !== "0" ? "C" : "AC"; width: stdPanel.bW; height: teclado.bH; type: "fn"; onClicked: if (calcBackend) calcBackend.clear() }
                        CalcButton { text: "±"; width: stdPanel.bW; height: teclado.bH; type: "fn"; onClicked: if (calcBackend) calcBackend.toggleSign() }
                        CalcButton { text: "%"; width: stdPanel.bW; height: teclado.bH; type: "fn"; onClicked: if (calcBackend) calcBackend.percent() }
                        CalcButton { text: "÷"; width: stdPanel.bW; height: teclado.bH; type: "op"; onClicked: if (calcBackend) calcBackend.inputOperator("÷") }
                    }
                    Repeater {
                        model: [["7", "8", "9", "×"], ["4", "5", "6", "−"], ["1", "2", "3", "+"]]
                        delegate: Row {
                            required property var modelData
                            spacing: teclado.sep
                            Repeater {
                                model: parent.modelData
                                delegate: CalcButton {
                                    required property var modelData
                                    required property int index
                                    text: modelData
                                    type: index === 3 ? "op" : "num"
                                    width: stdPanel.bW
                                    height: teclado.bH
                                    onClicked: {
                                        if (!calcBackend) return
                                        if (index === 3) calcBackend.inputOperator(modelData)
                                        else calcBackend.inputDigit(modelData)
                                    }
                                }
                            }
                        }
                    }
                    Row {
                        spacing: teclado.sep
                        CalcButton { text: "0"; width: stdPanel.bW * 2 + teclado.sep; height: teclado.bH; type: "num"; isWide: true; onClicked: if (calcBackend) calcBackend.inputDigit("0") }
                        CalcButton { text: "."; width: stdPanel.bW; height: teclado.bH; type: "num"; onClicked: if (calcBackend) calcBackend.inputDot() }
                        CalcButton { text: "="; width: stdPanel.bW; height: teclado.bH; type: "op"; onClicked: if (calcBackend) calcBackend.calculate() }
                    }
                }
            }
        }
    }

    // Componente botón de calculadora estilo macOS Sonoma
    component CalcButton: Rectangle {
        id: btn
        property string text: ""
        property string type: "num" // "num", "fn", "op", "sci"
        property bool isWide: false
        signal clicked()

        radius: 10
        // Base: blanco translúcido en oscuro, gris sobre blanco en claro
        readonly property color base: theme.isDark ? Qt.rgba(1, 1, 1, 1) : Qt.rgba(0, 0, 0, 1)
        readonly property real nivel: type === "fn" ? (theme.isDark ? 0.22 : 0.11)
                                    : type === "sci" ? (theme.isDark ? 0.10 : 0.05)
                                    : (theme.isDark ? 0.13 : 0.06)
        color: {
            if (type === "op")
                return btnMouse.pressed ? "#d67e00" : (btnMouse.containsMouse ? "#ffaa2b" : "#ff9f0a")
            var n = nivel + (btnMouse.pressed ? 0.12 : (btnMouse.containsMouse ? 0.06 : 0))
            return Qt.rgba(base.r, base.g, base.b, n)
        }
        border.color: theme.isDark ? theme.glassBorder : Qt.rgba(0, 0, 0, 0.06)
        border.width: 1

        scale: btnMouse.pressed ? 0.96 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }

        Text {
            anchors.centerIn: parent
            text: btn.text
            color: (btn.type === "op") ? "#ffffff" : theme.contentTextPrimary
            font.pixelSize: (btn.type === "sci") ? 13 : 18
            font.weight: Font.Medium
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}

