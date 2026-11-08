import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: dynamicIslandRoot
    width: islandCard.width
    height: islandCard.height

    TitanTheme { id: theme }

    readonly property bool active: shellBackend.islandActive
    readonly property var notif: shellBackend.currentIslandNotification

    Rectangle {
        id: islandCard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top

        width: active ? Math.min(420, Math.max(300, notifContent.implicitWidth + 36)) : 140
        height: active ? Math.max(64, notifContent.implicitHeight + 20) : 26
        radius: active ? 22 : 13

        color: "#0a0b0e"
        border.color: active ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12)
        border.width: 1

        opacity: active ? 1.0 : 0.0
        scale: active ? 1.0 : 0.7

        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on radius { NumberAnimation { duration: 250 } }
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

        // Resplandor sutil estilo iOS / macOS
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.color: theme.accent
            border.width: 1
            opacity: active ? 0.35 : 0.0
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }

        Row {
            id: notifContent
            anchors.centerIn: parent
            spacing: 12
            visible: islandCard.height > 40
            opacity: islandCard.height > 40 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 180 } }

            // Icono de la aplicación o sistema
            Item {
                width: 36
                height: 36
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 9
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                Image {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    source: notif && notif.icon ? notif.icon : "qrc:/icons/system.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }

            // Textos: App / Título / Mensaje
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                width: 280

                Row {
                    spacing: 6
                    width: parent.width

                    Text {
                        text: notif && notif.appName ? notif.appName.toUpperCase() : "SISTEMA"
                        color: theme.accent
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 0.5
                    }

                    Text {
                        text: "•"
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.pixelSize: 10
                    }

                    Text {
                        text: notif && notif.time ? notif.time : "Ahora"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 10
                    }
                }

                Text {
                    text: notif && notif.title ? notif.title : ""
                    color: "#ffffff"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    width: parent.width
                }

                Text {
                    text: notif && notif.message ? notif.message : ""
                    color: Qt.rgba(1, 1, 1, 0.78)
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    width: parent.width
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
            }

            // Botón de cierre rápido
            Item {
                width: 22
                height: 22
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.12)
                }

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "#ffffff"
                    font.pixelSize: 10
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.dismissIsland()
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                shellBackend.dismissIsland()
                shellBackend.toggleNotificationCenter()
            }
        }
    }
}

