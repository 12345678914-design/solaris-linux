import QtQuick 2.15
import QtQuick.Controls 2.15

TitanWindow {
    id: clockWindow

    title: "Reloj"
    width: 680
    height: 480
    minimumWidth: 420
    minimumHeight: 440
    sidebarWidth: 0

    property int currentTab: 0 // 0: Reloj Mundial, 1: Alarma, 2: Cronómetro, 3: Temporizador

    headerContentData: Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4

        // Pestañas Segmented Control estilo macOS
        Rectangle {
            height: 28
            width: segRow.width + 8
            radius: 7
            color: theme.isDark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(0, 0, 0, 0.08)
            border.color: theme.glassBorder
            border.width: 1

            Row {
                id: segRow
                anchors.centerIn: parent
                spacing: 2

                property var tabTitles: ["Mundial", "Alarmas", "Cronómetro", "Temporizador"]

                Repeater {
                    model: segRow.tabTitles

                    Rectangle {
                        width: tabText.implicitWidth + 16
                        height: 22
                        radius: 5
                        color: clockWindow.currentTab === index
                               ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.18) : "#ffffff")
                               : (tabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            text: modelData
                            color: clockWindow.currentTab === index
                                   ? theme.headerText
                                   : (theme.isDark ? "#888888" : "#666666")
                            font.pixelSize: 11
                            font.weight: clockWindow.currentTab === index ? Font.DemiBold : Font.Normal
                        }

                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: clockWindow.currentTab = index
                        }
                    }
                }
            }
        }
    }

    content: Item {
        anchors.fill: parent

        // TAB 0: RELOJ MUNDIAL
        Item {
            visible: clockWindow.currentTab === 0
            anchors.fill: parent

            // Lado izquierdo: Reloj Local (Esfera analógica + digital)
            Item {
                id: localClockPane
                width: 280
                height: parent.height

                Column {
                    anchors.centerIn: parent
                    spacing: 16

                    // Reloj analógico Canvas
                    Canvas {
                        id: clockCanvas
                        width: 160
                        height: 160
                        anchors.horizontalCenter: parent.horizontalCenter

                        Connections {
                            target: clockBackend
                            function onTimeChanged() { clockCanvas.requestPaint(); }
                        }

                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            var cx = width / 2;
                            var cy = height / 2;
                            var r = width / 2 - 6;

                            // Esfera
                            ctx.beginPath();
                            ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                            ctx.fillStyle = theme.isDark ? "#1c1c1e" : "#f2f2f7";
                            ctx.fill();
                            ctx.lineWidth = 2;
                            ctx.strokeStyle = theme.isDark ? "#38383a" : "#d1d1d6";
                            ctx.stroke();

                            // Marcas de horas
                            for (var i = 0; i < 12; i++) {
                                var angle = i * Math.PI / 6;
                                var x1 = cx + (r - 8) * Math.sin(angle);
                                var y1 = cy - (r - 8) * Math.cos(angle);
                                var x2 = cx + (r - 2) * Math.sin(angle);
                                var y2 = cy - (r - 2) * Math.cos(angle);
                                ctx.beginPath();
                                ctx.moveTo(x1, y1);
                                ctx.lineTo(x2, y2);
                                ctx.lineWidth = (i % 3 === 0) ? 2.5 : 1;
                                ctx.strokeStyle = theme.isDark ? "#8e8e93" : "#636366";
                                ctx.stroke();
                            }

                            var h = clockBackend.hours % 12;
                            var m = clockBackend.minutes;
                            var s = clockBackend.seconds;

                            // Manecilla Horas
                            var hAngle = (h + m / 60.0) * Math.PI / 6;
                            ctx.beginPath();
                            ctx.moveTo(cx, cy);
                            ctx.lineTo(cx + (r * 0.5) * Math.sin(hAngle), cy - (r * 0.5) * Math.cos(hAngle));
                            ctx.lineWidth = 4;
                            ctx.lineCap = "round";
                            ctx.strokeStyle = theme.headerText;
                            ctx.stroke();

                            // Manecilla Minutos
                            var mAngle = (m + s / 60.0) * Math.PI / 30;
                            ctx.beginPath();
                            ctx.moveTo(cx, cy);
                            ctx.lineTo(cx + (r * 0.72) * Math.sin(mAngle), cy - (r * 0.72) * Math.cos(mAngle));
                            ctx.lineWidth = 2.5;
                            ctx.lineCap = "round";
                            ctx.strokeStyle = theme.headerText;
                            ctx.stroke();

                            // Manecilla Segundos (Naranja / Acento)
                            var sAngle = s * Math.PI / 30;
                            ctx.beginPath();
                            ctx.moveTo(cx - 10 * Math.sin(sAngle), cy + 10 * Math.cos(sAngle));
                            ctx.lineTo(cx + (r * 0.82) * Math.sin(sAngle), cy - (r * 0.82) * Math.cos(sAngle));
                            ctx.lineWidth = 1.5;
                            ctx.strokeStyle = "#ff9500";
                            ctx.stroke();

                            // Centro
                            ctx.beginPath();
                            ctx.arc(cx, cy, 3.5, 0, 2 * Math.PI);
                            ctx.fillStyle = "#ff9500";
                            ctx.fill();
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: clockBackend.currentTime
                        color: theme.headerText
                        font.pixelSize: 26
                        font.bold: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Hora local"
                        color: theme.isDark ? "#888888" : "#666666"
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: clockBackend.currentDate
                        color: theme.isDark ? "#aaaaaa" : "#444444"
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                x: 280
                width: 1
                height: parent.height
                color: theme.glassBorder
            }

            // Lado derecho: Ciudades del Mundo
            Item {
                anchors.left: localClockPane.right
                anchors.leftMargin: 1
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                ListView {
                    id: worldList
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10
                    clip: true
                    model: clockBackend.worldClocks

                    delegate: Rectangle {
                        width: worldList.width
                        height: 64
                        radius: 10
                        color: theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.03)
                        border.color: theme.glassBorder
                        border.width: 1

                        Row {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 120
                                Text {
                                    text: modelData.offset + " | " + modelData.date
                                    color: theme.isDark ? "#888888" : "#777777"
                                    font.pixelSize: 10
                                }
                                Text {
                                    text: modelData.city
                                    color: theme.headerText
                                    font.pixelSize: 18
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.time
                                color: theme.headerText
                                font.pixelSize: 26
                                font.weight: Font.Light
                            }
                        }
                    }
                }
            }
        }

        // TAB 1: ALARMAS
        Item {
            visible: clockWindow.currentTab === 1
            anchors.fill: parent

            ListView {
                id: alarmList
                anchors.fill: parent
                anchors.margins: 20
                anchors.bottomMargin: 70
                spacing: 10
                clip: true
                model: clockBackend.alarms

                Text {
                    visible: alarmList.count === 0
                    anchors.centerIn: parent
                    text: "No hay alarmas configuradas"
                    color: theme.isDark ? "#777777" : "#999999"
                    font.pixelSize: 13
                }

                delegate: Rectangle {
                    width: alarmList.width
                    height: 64
                    radius: 10
                    color: theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.03)
                    border.color: theme.glassBorder
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 130
                            Text {
                                text: modelData.time
                                color: modelData.enabled ? theme.headerText : (theme.isDark ? "#666666" : "#aaaaaa")
                                font.pixelSize: 24
                                font.weight: Font.Light
                            }
                            Text {
                                text: modelData.label + " • " + modelData.days
                                color: theme.isDark ? "#888888" : "#777777"
                                font.pixelSize: 11
                            }
                        }

                        // Switch de activación
                        Switch {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: modelData.enabled
                            onToggled: clockBackend.toggleAlarm(index, checked)
                        }

                        // Eliminar
                        Rectangle {
                            width: 24
                            height: 24
                            radius: 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: delAlm.containsMouse ? Qt.rgba(1, 0, 0, 0.2) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: delAlm.containsMouse ? "#ff4444" : (theme.isDark ? "#666666" : "#aaaaaa")
                                font.pixelSize: 11
                            }

                            MouseArea {
                                id: delAlm
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: clockBackend.removeAlarm(index)
                            }
                        }
                    }
                }
            }

            // Barra inferior para agregar alarma
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 60
                color: theme.isDark ? Qt.rgba(0, 0, 0, 0.2) : Qt.rgba(255, 255, 255, 0.3)
                border.color: theme.glassBorder
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 10

                    TextField {
                        id: alarmTimeInput
                        width: 90
                        height: 32
                        placeholderText: "07:00"
                        font.pixelSize: 12
                        color: theme.headerText
                        background: Rectangle {
                            radius: 6
                            color: theme.isDark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(255, 255, 255, 0.6)
                            border.color: theme.glassBorder
                            border.width: 1
                        }
                    }

                    TextField {
                        id: alarmLabelInput
                        width: 180
                        height: 32
                        placeholderText: "Etiqueta (ej. Despertador)"
                        font.pixelSize: 12
                        color: theme.headerText
                        background: Rectangle {
                            radius: 6
                            color: theme.isDark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(255, 255, 255, 0.6)
                            border.color: theme.glassBorder
                            border.width: 1
                        }
                    }

                    Rectangle {
                        width: 100
                        height: 32
                        radius: 6
                        color: addAlmBtn.containsMouse ? Qt.lighter(theme.accent, 1.1) : theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: "+ Nueva Alarma"
                            color: "#ffffff"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: addAlmBtn
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (alarmTimeInput.text.trim().length > 0) {
                                    clockBackend.addAlarm(alarmTimeInput.text, alarmLabelInput.text, "Todos los días");
                                    alarmTimeInput.text = "";
                                    alarmLabelInput.text = "";
                                }
                            }
                        }
                    }
                }
            }
        }

        // TAB 2: CRONÓMETRO
        Item {
            visible: clockWindow.currentTab === 2
            anchors.fill: parent

            Column {
                anchors.top: parent.top
                anchors.topMargin: 24
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20

                // Gran indicador digital
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: clockBackend.stopwatchTime
                    color: theme.headerText
                    font.pixelSize: 56
                    font.weight: Font.Light
                    font.family: "Monospace"
                }

                // Botones de acción
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 40

                    // Botón Vuelta / Reiniciar
                    Rectangle {
                        width: 76
                        height: 76
                        radius: 38
                        color: theme.isDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.08)
                        border.color: theme.glassBorder
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: clockBackend.stopwatchRunning ? "Vuelta" : "Reiniciar"
                            color: theme.headerText
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (clockBackend.stopwatchRunning) {
                                    clockBackend.lapStopwatch();
                                } else {
                                    clockBackend.resetStopwatch();
                                }
                            }
                        }
                    }

                    // Botón Iniciar / Detener
                    Rectangle {
                        width: 76
                        height: 76
                        radius: 38
                        color: clockBackend.stopwatchRunning ? Qt.rgba(1, 0.2, 0.2, 0.25) : Qt.rgba(0.2, 0.8, 0.2, 0.25)
                        border.color: clockBackend.stopwatchRunning ? "#ff3b30" : "#34c759"
                        border.width: 1.5

                        Text {
                            anchors.centerIn: parent
                            text: clockBackend.stopwatchRunning ? "Detener" : "Iniciar"
                            color: clockBackend.stopwatchRunning ? "#ff3b30" : "#34c759"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (clockBackend.stopwatchRunning) {
                                    clockBackend.pauseStopwatch();
                                } else {
                                    clockBackend.startStopwatch();
                                }
                            }
                        }
                    }
                }
            }

            // Lista de vueltas (Laps)
            ListView {
                anchors.top: parent.top
                anchors.topMargin: 200
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.right: parent.right
                anchors.rightMargin: 30
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                clip: true
                spacing: 6
                model: clockBackend.stopwatchLaps

                delegate: Rectangle {
                    width: parent.width
                    height: 36
                    radius: 6
                    color: theme.isDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.02)

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Vuelta " + (modelData ? modelData.lapNum : "")
                            color: theme.isDark ? "#aaaaaa" : "#555555"
                            font.pixelSize: 12
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData ? modelData.time : ""
                            color: theme.headerText
                            font.pixelSize: 12
                            font.family: "Monospace"
                        }
                    }
                }
            }
        }

        // TAB 3: TEMPORIZADOR
        Item {
            visible: clockWindow.currentTab === 3
            anchors.fill: parent

            Column {
                anchors.centerIn: parent
                spacing: 24

                // Anillo de progreso y tiempo
                Item {
                    width: 220
                    height: 220
                    anchors.horizontalCenter: parent.horizontalCenter

                    Canvas {
                        id: timerCanvas
                        anchors.fill: parent

                        Connections {
                            target: clockBackend
                            function onTimerChanged() { timerCanvas.requestPaint(); }
                        }

                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            var cx = width / 2;
                            var cy = height / 2;
                            var r = width / 2 - 12;

                            // Fondo del anillo
                            ctx.beginPath();
                            ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                            ctx.lineWidth = 8;
                            ctx.strokeStyle = theme.isDark ? "#2c2c2e" : "#e5e5ea";
                            ctx.stroke();

                            // Progreso
                            var fraction = clockBackend.timerTotalSeconds > 0
                                           ? (clockBackend.timerRemainingSeconds / clockBackend.timerTotalSeconds)
                                           : 0;
                            var startAngle = -Math.PI / 2;
                            var endAngle = startAngle + (2 * Math.PI * fraction);

                            ctx.beginPath();
                            ctx.arc(cx, cy, r, startAngle, endAngle);
                            ctx.lineWidth = 8;
                            ctx.lineCap = "round";
                            ctx.strokeStyle = "#ff9500";
                            ctx.stroke();
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: clockBackend.timerDisplay
                        color: theme.headerText
                        font.pixelSize: 38
                        font.weight: Font.Light
                        font.family: "Monospace"
                    }
                }

                // Ajuste rápido o botones de preset
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    visible: !clockBackend.timerRunning

                    Repeater {
                        model: [
                            { label: "1 min", secs: 60 },
                            { label: "5 min", secs: 300 },
                            { label: "10 min", secs: 600 },
                            { label: "15 min", secs: 900 },
                            { label: "30 min", secs: 1800 }
                        ]

                        Rectangle {
                            width: 60
                            height: 28
                            radius: 6
                            color: quickMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                            border.color: theme.glassBorder
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: theme.headerText
                                font.pixelSize: 11
                            }

                            MouseArea {
                                id: quickMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: clockBackend.startTimer(modelData.secs)
                            }
                        }
                    }
                }

                // Controles del Temporizador
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 40

                    // Cancelar
                    Rectangle {
                        width: 72
                        height: 72
                        radius: 36
                        color: theme.isDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.08)
                        border.color: theme.glassBorder
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "Cancelar"
                            color: theme.headerText
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: clockBackend.resetTimer()
                        }
                    }

                    // Iniciar / Pausar
                    Rectangle {
                        width: 72
                        height: 72
                        radius: 36
                        color: clockBackend.timerRunning ? Qt.rgba(1, 0.6, 0, 0.25) : Qt.rgba(0.2, 0.8, 0.2, 0.25)
                        border.color: clockBackend.timerRunning ? "#ff9500" : "#34c759"
                        border.width: 1.5

                        Text {
                            anchors.centerIn: parent
                            text: clockBackend.timerRunning ? "Pausar" : "Iniciar"
                            color: clockBackend.timerRunning ? "#ff9500" : "#34c759"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (clockBackend.timerRunning) {
                                    clockBackend.pauseTimer();
                                } else {
                                    clockBackend.resumeTimer();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

