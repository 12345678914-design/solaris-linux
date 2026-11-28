// Calendario rápido del mes, como el de la fecha de la barra de Windows.
// Se abre al pulsar la fecha; flechas para otros meses y «Hoy» para volver.
// La semana empieza en lunes. Solo lee el reloj del equipo: nada sale fuera.
import QtQuick 2.15

Rectangle {
    id: cal
    property bool abierto: false
    // Mes que se enseña (día 1)
    property date mes: new Date()
    property date hoy: new Date()

    width: 292
    height: columna.height + 28
    radius: 18
    color: tema.isDark ? Qt.rgba(22/255, 24/255, 30/255, 0.96) : Qt.rgba(245/255, 245/255, 247/255, 0.96)
    border.color: tema.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
    border.width: 1
    visible: opacity > 0
    opacity: abierto ? 1 : 0
    scale: abierto ? 1 : 0.94
    transformOrigin: Item.TopRight
    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack; easing.overshoot: 1.05 } }

    TitanTheme { id: tema }

    readonly property var nombresMes: ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
                                       "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
    readonly property var nombresDia: ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]

    // Cada vez que se abre: el mes de hoy
    onAbiertoChanged: if (abierto) irAHoy()
    function irAHoy() {
        hoy = new Date()
        mes = new Date(hoy.getFullYear(), hoy.getMonth(), 1)
    }
    function mover(n) { mes = new Date(mes.getFullYear(), mes.getMonth() + n, 1) }

    // 42 casillas (6 semanas) empezando en el lunes de la semana del día 1
    readonly property var casillas: {
        var primero = new Date(mes.getFullYear(), mes.getMonth(), 1)
        var hueco = (primero.getDay() + 6) % 7        // lunes = 0
        var r = []
        for (var i = 0; i < 42; ++i) {
            var d = new Date(mes.getFullYear(), mes.getMonth(), 1 - hueco + i)
            r.push({ dia: d.getDate(), delMes: d.getMonth() === mes.getMonth(),
                     esHoy: d.getFullYear() === hoy.getFullYear() && d.getMonth() === hoy.getMonth()
                            && d.getDate() === hoy.getDate(),
                     finde: d.getDay() === 0 || d.getDay() === 6 })
        }
        return r
    }

    // Que los clics dentro no cierren el calendario
    MouseArea { anchors.fill: parent }

    Column {
        id: columna
        x: 14; y: 14
        width: parent.width - 28
        spacing: 10

        // Hoy, en grande
        Column {
            spacing: 1
            Text {
                text: cal.nombresDia[(cal.hoy.getDay() + 6) % 7].charAt(0).toUpperCase()
                      + cal.nombresDia[(cal.hoy.getDay() + 6) % 7].slice(1)
                      + ", " + cal.hoy.getDate() + " de " + cal.nombresMes[cal.hoy.getMonth()]
                color: tema.accent
                font.pixelSize: 13; font.weight: Font.DemiBold
            }
            Text {
                text: Qt.formatTime(cal.hoy, "HH:mm")
                color: tema.contentTextPrimary
                font.pixelSize: 26; font.weight: Font.Light
            }
        }

        Rectangle { width: parent.width; height: 1; color: tema.contentCardBorder }

        // Mes y flechas
        Item {
            width: parent.width; height: 26
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: cal.nombresMes[cal.mes.getMonth()].charAt(0).toUpperCase()
                      + cal.nombresMes[cal.mes.getMonth()].slice(1) + " de " + cal.mes.getFullYear()
                color: tema.contentTextPrimary
                font.pixelSize: 14; font.weight: Font.DemiBold
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    model: [{ t: "Hoy", n: 0 }, { t: "‹", n: -1 }, { t: "›", n: 1 }]
                    delegate: Rectangle {
                        required property var modelData
                        width: modelData.n === 0 ? 40 : 26; height: 24; radius: 6
                        visible: modelData.n !== 0 || cal.mes.getMonth() !== cal.hoy.getMonth()
                                 || cal.mes.getFullYear() !== cal.hoy.getFullYear()
                        color: zonaFlecha.containsMouse ? tema.itemHover : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.t
                            color: parent.modelData.n === 0 ? tema.accent : tema.contentTextPrimary
                            font.pixelSize: parent.modelData.n === 0 ? 12 : 18
                        }
                        MouseArea {
                            id: zonaFlecha
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: parent.modelData.n === 0 ? cal.irAHoy() : cal.mover(parent.modelData.n)
                        }
                    }
                }
            }
        }

        // Días de la semana
        Row {
            Repeater {
                model: ["L", "M", "X", "J", "V", "S", "D"]
                delegate: Text {
                    required property string modelData
                    width: columna.width / 7
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: tema.contentTextSecondary
                    font.pixelSize: 11; font.weight: Font.DemiBold
                }
            }
        }

        // Días
        Grid {
            columns: 7
            Repeater {
                model: cal.casillas
                delegate: Item {
                    required property var modelData
                    width: columna.width / 7
                    height: 32
                    Rectangle {
                        anchors.centerIn: parent
                        width: 28; height: 28; radius: 14
                        color: parent.modelData.esHoy ? tema.accent : "transparent"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.dia
                        color: parent.modelData.esHoy ? "white"
                               : !parent.modelData.delMes ? Qt.rgba(tema.contentTextSecondary.r, tema.contentTextSecondary.g, tema.contentTextSecondary.b, 0.45)
                               : parent.modelData.finde ? tema.contentTextSecondary : tema.contentTextPrimary
                        font.pixelSize: 12
                        font.weight: parent.modelData.esHoy ? Font.Bold : Font.Normal
                    }
                }
            }
        }
    }

    // La hora de arriba sigue al reloj mientras está abierto
    Timer {
        interval: 10000; repeat: true; running: cal.abierto
        onTriggered: cal.hoy = new Date()
    }
    // Rueda del ratón: otros meses
    WheelHandler {
        onWheel: (e) => cal.mover(e.angleDelta.y > 0 ? -1 : 1)
    }
}
