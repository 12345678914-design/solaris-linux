import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import QMLTermWidget 2.0

Window {
    id: terminalWindow

    width: 800
    height: 500
    minimumWidth: 500
    minimumHeight: 300
    visible: true
    title: "TITAN Terminal"
    flags: Qt.FramelessWindowHint | Qt.Window
    color: "transparent"

    property bool isDragging: false

    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on x { enabled: !terminalWindow.isDragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !terminalWindow.isDragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Action {
        shortcut: "Ctrl+Shift+C"
        onTriggered: terminal.copyClipboard()
    }

    Action {
        shortcut: "Ctrl+Shift+V"
        onTriggered: terminal.pasteClipboard()
    }

    Action {
        shortcut: "Ctrl+F"
        onTriggered: {
            searchBar.visible = !searchBar.visible
            if (searchBar.visible)
                searchInput.forceActiveFocus()
            else
                terminal.forceActiveFocus()
        }
    }

    Rectangle {
        id: terminalRoot
        anchors.fill: parent
        radius: (terminalWindow.visibility === Window.Maximized) ? 0 : 10
        color: "#111318"
        border.color: "#303644"
        clip: true

        opacity: 0.0
        scale: 0.95

        Component.onCompleted: openAnim.start()

        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: terminalRoot; property: "opacity"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: terminalRoot; property: "scale"; from: 0.95; to: 1.0; duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.05 }
        }

        SequentialAnimation {
            id: closeAnim
            ParallelAnimation {
                NumberAnimation { target: terminalRoot; property: "opacity"; to: 0.0; duration: 160; easing.type: Easing.InCubic }
                NumberAnimation { target: terminalRoot; property: "scale"; to: 0.95; duration: 160; easing.type: Easing.InCubic }
            }
            ScriptAction { script: terminalWindow.close() }
        }

        Rectangle {
            id: titleBar

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 42
            color: "#1A1D24"

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                property point pressPos
                property bool systemMoveStarted: false

                onPressed: {
                    pressPos = Qt.point(mouse.x, mouse.y)
                    systemMoveStarted = false
                }
                onPositionChanged: {
                    if (!systemMoveStarted) {
                        var dx = mouse.x - pressPos.x
                        var dy = mouse.y - pressPos.y
                        if (Math.abs(dx) > 3 || Math.abs(dy) > 3) {
                            terminalWindow.isDragging = true
                            if (terminalWindow.startSystemMove()) {
                                systemMoveStarted = true
                            } else {
                                terminalWindow.x += dx
                                terminalWindow.y += dy
                            }
                        }
                    }
                }
                onReleased: {
                    terminalWindow.isDragging = false
                    systemMoveStarted = false
                }
                onCanceled: {
                    terminalWindow.isDragging = false
                    systemMoveStarted = false
                }
                onDoubleClicked: {
                    if (terminalWindow.visibility === Window.Maximized) {
                        terminalWindow.showNormal()
                    } else {
                        terminalWindow.showMaximized()
                    }
                }
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                z: 10

                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: "#ff5f57"
                    scale: closeBtnArea.containsMouse ? 1.15 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    MouseArea {
                        id: closeBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: closeAnim.start()
                    }
                }

                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: "#febc2e"
                    scale: minBtnArea.containsMouse ? 1.15 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    MouseArea {
                        id: minBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: terminalWindow.showMinimized()
                    }
                }

                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: "#28c840"
                    scale: maxBtnArea.containsMouse ? 1.15 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    MouseArea {
                        id: maxBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (terminalWindow.visibility === Window.Maximized) {
                                terminalWindow.showNormal()
                            } else {
                                terminalWindow.showMaximized()
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                text: "TITAN Terminal"
                color: "#F2F4F8"
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        QMLTermWidget {
            id: terminal

            anchors.top: titleBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: searchBar.visible
                               ? searchBar.top : parent.bottom

            anchors.margins: 10

            font.family: "Monospace"
            font.pointSize: 12
            colorScheme: "cool-retro-term"

            session: QMLTermSession {
                id: mainSession

                initialWorkingDirectory: "$HOME"

                onMatchFound: function(startColumn, startLine,
                                        endColumn, endLine) {
                    console.log("Coincidencia:",
                                startColumn, startLine,
                                endColumn, endLine)
                }

                onNoMatchFound: {
                    console.log("No se encontraron coincidencias")
                }
            }

            QMLTermScrollbar {
                terminal: terminal
                width: 14
            }

            Component.onCompleted: {
                mainSession.startShellProgram()
                terminal.forceActiveFocus()
            }
        }

        Rectangle {
            id: searchBar

            visible: false
            height: 44
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 10
            color: "#1A1D24"
            radius: 6
            border.color: "#303644"

            Row {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 8

                TextField {
                    id: searchInput

                    width: parent.width - searchButton.width - 8
                    height: parent.height
                    placeholderText: "Buscar en el terminal..."
                    color: "#F2F4F8"
                    placeholderTextColor: "#777F91"
                    font.family: "monospace"
                    background: null

                    onAccepted: mainSession.search(text)
                }

                Button {
                    id: searchButton
                    height: parent.height
                    text: "Buscar"

                    onClicked: mainSession.search(searchInput.text)
                }
            }
        }
    }
}
