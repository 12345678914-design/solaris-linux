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

            // Teclado
            Row {
                width: parent.width
                height: parent.height - 92
                spacing: 10

                // Panel Científico (opcional)
                Grid {
                    visible: calcWindow.isSci
                    columns: 3
                    spacing: 8
                    width: 200
                    height: parent.height

                    readonly property real bW: Math.floor((width - 16) / 3)
                    readonly property real bH: Math.floor((height - 32) / 5)

                    CalcButton { text: "sin"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.trigSin() }
                    CalcButton { text: "cos"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.trigCos() }
                    CalcButton { text: "tan"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.trigTan() }

                    CalcButton { text: "x²"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.sqrOp() }
                    CalcButton { text: "√x"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.sqrtOp() }
                    CalcButton { text: "xʸ"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.inputOperator("^") }

                    CalcButton { text: "1/x"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.invOp() }
                    CalcButton { text: "ln"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.lnOp() }
                    CalcButton { text: "log"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.log10Op() }

                    CalcButton { text: "π"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.constPi() }
                    CalcButton { text: "e"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.constE() }
                    CalcButton { text: "MC"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.memoryClear() }

                    CalcButton { text: "MR"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.memoryRecall() }
                    CalcButton { text: "M+"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.memoryAdd() }
                    CalcButton { text: "M−"; width: parent.bW; height: parent.bH; type: "sci"; onClicked: if (calcBackend) calcBackend.memorySubtract() }
                }

                // Panel Estándar
                Grid {
                    id: stdGrid
                    columns: 4
                    spacing: 8
                    width: parent.width - (calcWindow.isSci ? 210 : 0)
                    height: parent.height

                    readonly property real bW: Math.floor((width - 24) / 4)
                    readonly property real bH: Math.floor((height - 32) / 5)

                    // Fila 1
                    CalcButton { text: calcWindow.dispText !== "0" ? "C" : "AC"; width: stdGrid.bW; height: stdGrid.bH; type: "fn"; onClicked: if (calcBackend) calcBackend.clear() }
                    CalcButton { text: "±"; width: stdGrid.bW; height: stdGrid.bH; type: "fn"; onClicked: if (calcBackend) calcBackend.toggleSign() }
                    CalcButton { text: "%"; width: stdGrid.bW; height: stdGrid.bH; type: "fn"; onClicked: if (calcBackend) calcBackend.percent() }
                    CalcButton { text: "÷"; width: stdGrid.bW; height: stdGrid.bH; type: "op"; onClicked: if (calcBackend) calcBackend.inputOperator("÷") }

                    // Fila 2
                    CalcButton { text: "7"; width: stdGrid.bW; height: stdGrid.bH; type: "num"; onClicked: if (calcBackend) calcBackend.inputDigit("7") }
                    CalcButton { text: "8"; width: stdGrid.bW; height: stdGrid.bH; type: "num"; onClicked: if (calcBackend) calcBackend.inputDigit("8") }
                    CalcButton { text: "9"; width: stdGrid.bW; height: stdGrid.bH; type: "num"; onClicked: if (calcBackend) calcBackend.inputDigit("9") }
                    CalcButton { text: "×"; width: stdGrid.bW; height: stdGrid.bH; type: "op"; onClicked: if (calcBackend) calcBackend.inputOperator("×") }

                    // Fila 3
                    CalcButton { text: "4"; width: stdGrid.bW; height: stdGrid.bH; type: "num"; onClicked: calcBackend.inputDigit("4") }
                    CalcButton { text: "5"; width: stdGrid.bW; height: stdGrid.bH; type: "num"; onClicked: calcBackend.inputDigit("5") }
                    CalcButton { text: "6"; width: stdGrid.bW; height: stdGrid.bH; type: "num"; onClicked: calcBackend.inputDigit("6") }
                    CalcButton { text: "−"; width: stdGrid.bW; height: stdGrid.bH; type: "op"; onClicked: calcBackend.inputOperator("−") }

                    // Fila 4
                    CalcButton { text: "1"; width: stdGrid.bW; height: stdGrid.bH; type: "num"; onClicked: calcBackend.inputDigit("1") }
                    CalcButton { text: "2"; width: stdGrid.bW; height: stdGrid.bH; type: "num"; onClicked: calcBackend.inputDigit("2") }
                    CalcButton { text: "3"; width: stdGrid.bW; height: stdGrid.bH; type: "num"; onClicked: calcBackend.inputDigit("3") }
                    CalcButton { text: "+"; width: stdGrid.bW; height: stdGrid.bH; type: "op"; onClicked: calcBackend.inputOperator("+") }

                    // Fila 5
                    CalcButton { text: "0"; width: stdGrid.bW * 2 + 8; height: stdGrid.bH; type: "num"; isWide: true; onClicked: calcBackend.inputDigit("0") }
                    CalcButton { text: "."; width: stdGrid.bW; height: stdGrid.bH; type: "num"; onClicked: calcBackend.inputDot() }
                    CalcButton { text: "="; width: stdGrid.bW; height: stdGrid.bH; type: "op"; onClicked: calcBackend.calculate() }
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
        color: {
            if (type === "op") {
                return btnMouse.pressed ? "#d67e00" : (btnMouse.containsMouse ? "#ffaa2b" : "#ff9f0a")
            } else if (type === "fn") {
                return btnMouse.pressed ? Qt.rgba(1, 1, 1, 0.45) : (btnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.22))
            } else if (type === "sci") {
                return btnMouse.pressed ? Qt.rgba(1, 1, 1, 0.25) : (btnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.10))
            } else {
                return btnMouse.pressed ? Qt.rgba(1, 1, 1, 0.28) : (btnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.12))
            }
        }
        border.color: theme.glassBorder
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

