import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: notifCenterRoot
    width: 360
    height: Math.min(520, Math.max(220, notifList.contentHeight + 70))
    radius: 18

    TitanTheme { id: theme }

    color: theme.isDark ? Qt.rgba(22/255.0, 24/255.0, 30/255.0, 0.95) : Qt.rgba(245/255.0, 245/255.0, 247/255.0, 0.95)
    border.color: theme.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
    border.width: 1

    clip: true

    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // Cabecera: Título y Botón Borrar Todo
        Item {
            width: parent.width
            height: 28

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Canvas {
                    width: 16
                    height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.strokeStyle = theme.headerText;
                        ctx.fillStyle = theme.headerText;
                        ctx.lineWidth = 1.5;
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";

                        ctx.beginPath();
                        ctx.arc(8, 6, 4, Math.PI, 0, false);
                        ctx.lineTo(13, 11);
                        ctx.lineTo(3, 11);
                        ctx.closePath();
                        ctx.stroke();

                        ctx.beginPath();
                        ctx.arc(8, 12.5, 1.5, 0, Math.PI * 2);
                        ctx.fill();
                    }
                }

                Text {
                    text: "Notificaciones"
                    color: theme.headerText
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    visible: shellBackend.notifications.length > 0
                    width: 20; height: 18; radius: 9
                    color: theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        anchors.centerIn: parent
                        text: shellBackend.notifications.length
                        color: "#ffffff"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            Rectangle {
                id: clearAllBtn
                visible: shellBackend.notifications.length > 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: clearAllText.width + 16
                height: 24
                radius: 12
                color: clearAllMouse.containsMouse
                       ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.10))
                       : (theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))

                Text {
                    id: clearAllText
                    anchors.centerIn: parent
                    text: "Borrar todo"
                    color: clearAllMouse.containsMouse ? "#ff4d4d" : theme.contentTextSecondary
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: clearAllMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.clearNotifications()
                }
            }
        }

        // Estado Vacío (Sin Notificaciones)
        Item {
            visible: shellBackend.notifications.length === 0
            width: parent.width
            height: 120

            Column {
                anchors.centerIn: parent
                spacing: 8

                Canvas {
                    width: 40
                    height: 40
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: 0.55
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.strokeStyle = theme.contentTextSecondary;
                        ctx.fillStyle = theme.contentTextSecondary;
                        ctx.lineWidth = 2.2;
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";

                        // Campana
                        ctx.beginPath();
                        ctx.arc(20, 15, 10, Math.PI, 0, false);
                        ctx.lineTo(32, 27);
                        ctx.lineTo(8, 27);
                        ctx.closePath();
                        ctx.stroke();

                        // Badajo
                        ctx.beginPath();
                        ctx.arc(20, 31, 3.5, 0, Math.PI * 2);
                        ctx.fill();

                        // Línea diagonal tachada
                        ctx.beginPath();
                        ctx.moveTo(7, 33);
                        ctx.lineTo(33, 7);
                        ctx.stroke();
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No hay notificaciones"
                    color: theme.contentTextSecondary
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }
        }

        // Lista de Notificaciones Guardadas
        ListView {
            id: notifList
            visible: shellBackend.notifications.length > 0
            width: parent.width
            height: Math.min(420, contentHeight)
            clip: true
            spacing: 8
            model: shellBackend.notifications

            delegate: Rectangle {
                id: notifDelegate
                readonly property int idNotificacion: modelData.id
                width: notifList.width
                height: notifCol.implicitHeight + 18
                radius: 12
                color: theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)
                border.color: theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                border.width: 1

                Row {
                    id: notifRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    // Icono
                    Item {
                        width: 32; height: 32
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
                        }

                        Image {
                            anchors.centerIn: parent
                            width: 22; height: 22
                            source: modelData.icon ? modelData.icon : "qrc:/icons/system.png"
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }
                    }

                    // Contenido
                    Column {
                        id: notifCol
                        width: notifRow.width - 70
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Row {
                            width: parent.width
                            spacing: 6

                            Text {
                                text: modelData.appName ? modelData.appName.toUpperCase() : "SISTEMA"
                                color: theme.accent
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }

                            Text {
                                text: "•"
                                color: theme.headerTextMuted
                                font.pixelSize: 9
                            }

                            Text {
                                text: modelData.time ? modelData.time : ""
                                color: theme.headerTextMuted
                                font.pixelSize: 9
                            }
                        }

                        Text {
                            text: modelData.title ? modelData.title : ""
                            color: theme.headerText
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: modelData.message ? modelData.message : ""
                            color: theme.isDark ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(0, 0, 0, 0.65)
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            width: parent.width
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }

                        // Botones de la app (p. ej. "Actualizar")
                        Row {
                            visible: modelData.actions && modelData.actions.length > 0
                            spacing: 6
                            topPadding: 6
                            Repeater {
                                model: modelData.actions ? modelData.actions : []
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    height: 22
                                    width: etiquetaAccion.implicitWidth + 20
                                    radius: 11
                                    color: index === 0 ? theme.accent
                                                       : (theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                                    Text {
                                        id: etiquetaAccion
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: index === 0 ? "#ffffff" : theme.headerText
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: shellBackend.invokeNotificationAction(notifDelegate.idNotificacion, modelData.key)
                                    }
                                }
                            }
                        }
                    }

                    // Botón para eliminar notificación individual
                    Item {
                        width: 18; height: 18
                        anchors.top: parent.top

                        Rectangle {
                            anchors.fill: parent
                            radius: 9
                            color: delMouse.containsMouse
                                   ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.12))
                                   : "transparent"
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: delMouse.containsMouse ? "#ff4d4d" : theme.contentTextSecondary
                            font.pixelSize: 9
                        }

                        MouseArea {
                            id: delMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shellBackend.removeNotification(modelData.id)
                        }
                    }
                }
            }
        }
    }
}

