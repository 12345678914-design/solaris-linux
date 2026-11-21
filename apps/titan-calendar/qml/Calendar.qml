import QtQuick 2.15
import QtQuick.Controls 2.15

TitanWindow {
    id: calWindow

    // Índice del evento que se está editando en el formulario (-1 = evento nuevo)
    property int editingIndex: -1

    function guardarEvento() {
        if (eventTitleInput.text.trim().length === 0) return
        if (calendarBackend.timeError(eventTimeInput.text) !== "") return
        if (calWindow.editingIndex >= 0)
            calendarBackend.updateEvent(calWindow.editingIndex, eventTitleInput.text, eventTimeInput.text, "")
        else
            calendarBackend.addEvent(eventTitleInput.text, eventTimeInput.text, "")
        calWindow.cancelarEdicion()
    }
    function cancelarEdicion() {
        calWindow.editingIndex = -1
        eventTitleInput.text = ""
        eventTimeInput.text = ""
    }

    // Al cambiar de día no se puede seguir editando un evento de otro día
    Connections {
        target: calendarBackend
        function onSelectedDateChanged() { calWindow.cancelarEdicion() }
    }

    title: "Calendario"
    width: 780
    height: 520
    minimumWidth: 680
    minimumHeight: 460
    sidebarWidth: 0

    headerContentData: Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 14
        spacing: 8

        // Botón Hoy
        Rectangle {
            width: hoyText.implicitWidth + 16
            height: 24
            radius: 6
            color: hoyMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
            border.color: theme.glassBorder
            border.width: 1

            Text {
                id: hoyText
                anchors.centerIn: parent
                text: "Hoy"
                color: theme.headerText
                font.pixelSize: 11
                font.weight: Font.Medium
            }

            MouseArea {
                id: hoyMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: calendarBackend.goToToday()
            }
        }

        // Flecha Anterior Mes
        Rectangle {
            width: 24
            height: 24
            radius: 6
            color: prevMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
            border.color: theme.glassBorder
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "‹"
                color: theme.headerText
                font.pixelSize: 16
                font.bold: true
            }

            MouseArea {
                id: prevMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: calendarBackend.prevMonth()
            }
        }

        // Flecha Siguiente Mes
        Rectangle {
            width: 24
            height: 24
            radius: 6
            color: nextMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
            border.color: theme.glassBorder
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "›"
                color: theme.headerText
                font.pixelSize: 16
                font.bold: true
            }

            MouseArea {
                id: nextMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: calendarBackend.nextMonth()
            }
        }
    }

    Row {
        anchors.fill: parent

        // Panel Izquierdo: Rejilla del Calendario
        Item {
            width: parent.width - 270
            height: parent.height

            // Encabezado del mes
            Text {
                id: monthLabel
                anchors.top: parent.top
                anchors.topMargin: 16
                anchors.left: parent.left
                anchors.leftMargin: 24
                text: calendarBackend.monthName
                color: theme.headerText
                font.pixelSize: 20
                font.bold: true
            }

            // Días de la semana
            Row {
                id: daysHeader
                anchors.top: monthLabel.bottom
                anchors.topMargin: 16
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.right: parent.right
                anchors.rightMargin: 20
                height: 24

                property var dayNames: ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]
                Repeater {
                    model: parent.dayNames
                    Item {
                        width: daysHeader.width / 7
                        height: 24
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: theme.isDark ? "#888888" : "#777777"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }

            // Separador horizontal
            Rectangle {
                anchors.top: daysHeader.bottom
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.right: parent.right
                anchors.rightMargin: 20
                height: 1
                color: theme.glassBorder
            }

            // Grid de días
            Grid {
                id: monthGrid
                anchors.top: daysHeader.bottom
                anchors.topMargin: 8
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                columns: 7
                spacing: 0

                property real cellWidth: width / 7
                property real cellHeight: height / (calendarBackend.daysInMonth.length / 7)

                Repeater {
                    model: calendarBackend.daysInMonth

                    Item {
                        width: monthGrid.cellWidth
                        height: monthGrid.cellHeight

                        property bool isSelected: {
                            var d = modelData.date;
                            var s = calendarBackend.selectedDate;
                            return d.getFullYear() === s.getFullYear() &&
                                   d.getMonth() === s.getMonth() &&
                                   d.getDate() === s.getDate();
                        }

                        // Círculo o fondo de selección
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) - 10
                            height: width
                            radius: width / 2
                            color: isSelected
                                   ? theme.accent
                                   : (modelData.isToday ? (theme.isDark ? "#333333" : "#e0e0e0") : (cellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"))
                            border.color: modelData.isToday && !isSelected ? theme.accent : "transparent"
                            border.width: 1.5
                        }

                        // Número del día
                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: modelData.hasEvents ? -3 : 0
                            text: modelData.day
                            color: isSelected
                                   ? "#ffffff"
                                   : (modelData.isCurrentMonth
                                      ? (modelData.isToday ? theme.accent : theme.headerText)
                                      : (theme.isDark ? "#555555" : "#aaaaaa"))
                            font.pixelSize: 13
                            font.weight: (modelData.isToday || isSelected) ? Font.Bold : Font.Normal
                        }

                        // Indicador de evento (punto)
                        Rectangle {
                            visible: modelData.hasEvents
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 5
                            height: 5
                            radius: 2.5
                            color: isSelected ? "#ffffff" : theme.accent
                        }

                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: calendarBackend.selectedDate = modelData.date
                        }
                    }
                }
            }
        }

        // Separador vertical
        Rectangle {
            width: 1
            height: parent.height
            color: theme.glassBorder
        }

        // Panel Derecho: Eventos del día seleccionado
        Rectangle {
            width: 269
            height: parent.height
            color: theme.isDark ? Qt.rgba(0, 0, 0, 0.15) : Qt.rgba(255, 255, 255, 0.25)

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // Título fecha seleccionada
                Text {
                    text: calendarBackend.selectedDate.toLocaleDateString(Qt.locale("es_ES"), "dddd, d 'de' MMMM")
                    color: theme.headerText
                    font.pixelSize: 14
                    font.bold: true
                    width: parent.width
                    wrapMode: Text.Wrap
                }

                // Lista de eventos
                Item {
                    width: parent.width
                    height: parent.height - 180

                    ListView {
                        id: eventsList
                        anchors.fill: parent
                        clip: true
                        spacing: 8
                        model: calendarBackend.selectedDateEvents

                        Text {
                            visible: eventsList.count === 0
                            anchors.centerIn: parent
                            text: "Sin eventos para este día"
                            color: theme.isDark ? "#777777" : "#999999"
                            font.pixelSize: 12
                        }

                        delegate: Rectangle {
                            width: eventsList.width
                            height: 48
                            radius: 8
                            color: calWindow.editingIndex === index
                                   ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18)
                                   : (theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04))
                            border.color: calWindow.editingIndex === index ? theme.accent : theme.glassBorder
                            border.width: 1

                            // Clic en el evento: cargarlo en el formulario para editarlo
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    calWindow.editingIndex = index
                                    eventTitleInput.text = modelData.title
                                    eventTimeInput.text = modelData.time === "Todo el día" ? "" : modelData.time
                                    eventTitleInput.forceActiveFocus()
                                }
                            }

                            Row {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                Rectangle {
                                    width: 3
                                    height: parent.height
                                    radius: 1.5
                                    color: theme.accent
                                }

                                Column {
                                    width: parent.width - 40
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        text: modelData.title
                                        color: theme.headerText
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                    Text {
                                        text: modelData.time
                                        color: theme.isDark ? "#888888" : "#666666"
                                        font.pixelSize: 10
                                    }
                                }

                                // Botón eliminar evento
                                Rectangle {
                                    width: 20
                                    height: 20
                                    radius: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: delMouse.containsMouse ? Qt.rgba(1, 0, 0, 0.2) : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: delMouse.containsMouse ? "#ff4444" : (theme.isDark ? "#777777" : "#aaaaaa")
                                        font.pixelSize: 11
                                    }

                                    MouseArea {
                                        id: delMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (calWindow.editingIndex === index) calWindow.cancelarEdicion()
                                            calendarBackend.deleteEvent(index)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Sección para agregar evento
                Rectangle {
                    width: parent.width
                    height: 100
                    radius: 8
                    color: theme.isDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.02)
                    border.color: theme.glassBorder
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        TextField {
                            id: eventTitleInput
                            width: parent.width
                            height: 26
                            placeholderText: "Título del evento..."
                            onAccepted: calWindow.guardarEvento()
                            Keys.onEscapePressed: calWindow.cancelarEdicion()
                            font.pixelSize: 11
                            color: theme.headerText
                            background: Rectangle {
                                radius: 4
                                color: theme.isDark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.6)
                                border.color: theme.glassBorder
                                border.width: 1
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 6

                            TextField {
                                id: eventTimeInput
                                width: parent.width - 76
                                height: 26
                                placeholderText: "Hora (ej. 14:00, vacía = todo el día)"
                                onAccepted: calWindow.guardarEvento()
                                Keys.onEscapePressed: calWindow.cancelarEdicion()
                                font.pixelSize: 11
                                color: theme.headerText
                                background: Rectangle {
                                    radius: 4
                                    color: theme.isDark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.6)
                                    border.color: theme.glassBorder
                                    border.width: 1
                                }
                            }

                            Rectangle {
                                width: 70
                                height: 26
                                radius: 4
                                color: addMouse.containsMouse ? Qt.lighter(theme.accent, 1.1) : theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: calWindow.editingIndex >= 0 ? "Guardar" : "Agregar"
                                    color: "#ffffff"
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }

                                MouseArea {
                                    id: addMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: calWindow.guardarEvento()
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 10
                            Text {
                                readonly property string err: calendarBackend.timeError(eventTimeInput.text)
                                visible: err !== ""
                                text: err
                                color: "#ff453a"
                                font.pixelSize: 10
                            }
                            Text {
                                visible: calWindow.editingIndex >= 0
                                text: "Cancelar edición"
                                color: theme.accent
                                font.pixelSize: 10
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: calWindow.cancelarEdicion()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

