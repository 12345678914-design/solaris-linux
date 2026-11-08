import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: sidebar

    TitanTheme { id: theme }

    ListView {
        id: favList
        anchors.fill: parent
        anchors.margins: 8
        spacing: 2
        clip: true

        model: finderBackend.favorites

        // Separadores de sección (Favoritos vs Ubicaciones)
        section.property: "section"
        section.criteria: ViewSection.FullString
        section.delegate: Item {
            width: favList.width
            height: sidebar.width > 60 ? 28 : 8

            Text {
                visible: sidebar.width > 60
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                text: section
                color: theme.sidebarTextMuted
                font.pixelSize: 11
                font.bold: true
                font.capitalization: Font.AllUppercase
            }
        }

        delegate: Item {
            id: favItem
            width: favList.width
            height: 32

            property bool isSelected: (modelData.isDevice && modelData.isMounted)
                ? (finderBackend.currentPath === modelData.mountPoint)
                : (finderBackend.currentPath === modelData.path)

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: isSelected ? theme.accent :
                       itemMouse.containsMouse ? theme.itemHover : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }

                Item {
                    id: iconHolder
                    width: 20
                    height: 20
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: sidebar.width > 60 ? parent.left : undefined
                    anchors.leftMargin: sidebar.width > 60 ? 8 : 0
                    anchors.horizontalCenter: sidebar.width <= 60 ? parent.horizontalCenter : undefined

                    Rectangle {
                        visible: modelData.icon.indexOf("color:") === 0
                        width: 10
                        height: 10
                        radius: 5
                        anchors.centerIn: parent
                        color: modelData.icon.indexOf("color:") === 0 ? modelData.icon.substring(6) : "transparent"
                    }

                    Image {
                        visible: modelData.icon.indexOf("color:") !== 0
                        source: modelData.icon.indexOf("color:") !== 0 ? modelData.icon : ""
                        width: 17
                        height: 17
                        anchors.centerIn: parent
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }

                Item {
                    id: ejectBtn
                    visible: !!modelData.isDevice && !!modelData.isMounted && sidebar.width > 60
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    z: 5

                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: ejectMouse.containsMouse ? (isSelected ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "⏏"
                        font.pixelSize: 13
                        color: ejectMouse.containsMouse ? "#ff4d4d" : (isSelected ? "#ffffff" : theme.sidebarTextMuted)
                    }

                    MouseArea {
                        id: ejectMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            finderBackend.unmountDevice(modelData.deviceNode)
                        }
                    }
                }

                Text {
                    visible: sidebar.width > 60
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: iconHolder.right
                    anchors.leftMargin: 8
                    anchors.right: (modelData.isDevice && modelData.isMounted) ? ejectBtn.left : parent.right
                    anchors.rightMargin: (modelData.isDevice && modelData.isMounted) ? 4 : 8
                    text: modelData.name
                    color: isSelected ? "#ffffff" : theme.sidebarText
                    font.pixelSize: 12
                    font.weight: isSelected ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.isDevice) {
                            if (!modelData.isMounted) {
                                finderBackend.mountAndOpen(modelData.deviceNode)
                            } else {
                                finderBackend.goTo(modelData.mountPoint ? modelData.mountPoint : modelData.path)
                            }
                        } else {
                            finderBackend.goTo(modelData.path)
                        }
                    }
                }
            }
        }
    }
}
