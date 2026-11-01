import QtQuick 2.15
import QtQuick.Controls 2.15

ScrollView {
    id: wallpaperView
    contentWidth: width
    clip: true

    TitanTheme { id: theme }

    Column {
        width: parent.width - 48
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 20
        topPadding: 16
        bottomPadding: 32

        // 1. VISTA PREVIA DEL FONDO ACTUAL
        Rectangle {
            width: parent.width
            height: 160
            radius: 12
            color: "#1c1c1e"
            clip: true
            border.color: theme.contentCardBorder
            border.width: 1

            Image {
                anchors.fill: parent
                source: settingsBackend.currentWallpaper
                fillMode: Image.PreserveAspectCrop
                smooth: true
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 38
                color: Qt.rgba(0, 0, 0, 0.55)

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Fondo de pantalla actual"
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Item { width: 10; height: 1 }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: settingsBackend.currentWallpaper.split("/").pop()
                        color: Qt.rgba(1, 1, 1, 0.7)
                        font.pixelSize: 11
                    }
                }
            }
        }

        // 2. COLECCIÓN DE FONDOS DISPONIBLES
        Column {
            width: parent.width
            spacing: 12

            Text {
                text: "Fondos de pantalla de Titan Linux"
                color: theme.contentTextSecondary
                font.pixelSize: 12
                font.bold: true
            }

            Grid {
                columns: 3
                spacing: 14
                width: parent.width

                Repeater {
                    model: settingsBackend.wallpapers

                    delegate: Item {
                        width: (wallpaperView.width - 48 - 28) / 3
                        height: 130

                        property bool isSelected: settingsBackend.currentWallpaper === modelData.path
                        property bool isHovered: itemMouse.containsMouse

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: isSelected ? Qt.rgba(0, 0.44, 0.89, 0.15) :
                                   isHovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                            border.color: isSelected ? "#0071e3" :
                                          isHovered ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.1)
                            border.width: isSelected ? 3 : 1
                            scale: isHovered ? 1.03 : 1.0
                            Behavior on scale { NumberAnimation { duration: 120 } }

                            Column {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 6

                                Rectangle {
                                    width: parent.width
                                    height: 90
                                    radius: 7
                                    clip: true
                                    color: "#1c1c1e"

                                    Image {
                                        anchors.fill: parent
                                        source: modelData.thumbnail
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                    }

                                    // Badge check azul
                                    Rectangle {
                                        visible: isSelected
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 6
                                        width: 20
                                        height: 20
                                        radius: 10
                                        color: "#0071e3"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "✓"
                                            color: "#ffffff"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.name
                                    color: isSelected ? "#0071e3" : theme.contentTextPrimary
                                    font.pixelSize: 11
                                    font.bold: isSelected
                                    elide: Text.ElideRight
                                    width: parent.width - 8
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settingsBackend.setWallpaper(modelData.path)
                            }
                        }
                    }
                }
            }
        }
    }
}

