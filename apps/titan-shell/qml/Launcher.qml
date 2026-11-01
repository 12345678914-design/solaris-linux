import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: launcher
    width: 740
    height: 530
    radius: 24

    TitanTheme { id: titanTheme }

    // Fondo Liquid Glass translúcido neutro (sin tinte de color)
    color: titanTheme.isDark ? Qt.rgba(0.12, 0.12, 0.14, 0.75) : Qt.rgba(0.96, 0.96, 0.97, 0.75)
    border.color: titanTheme.isDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.45)
    border.width: 1
    clip: true

    // Capa de desenfoque difuso estilo frosted glass
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 23
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, titanTheme.isDark ? 0.12 : 0.35) }
            GradientStop { position: 0.3; color: Qt.rgba(1, 1, 1, titanTheme.isDark ? 0.03 : 0.08) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, titanTheme.isDark ? 0.15 : 0.04) }
        }
    }

    // Brillo especular superior estilo cristal Sonoma
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 40
        height: 1
        color: titanTheme.specularGlow
    }

    // Animación de entrada suave
    property bool isVisible: visible
    scale: isVisible ? 1.0 : 0.92
    opacity: isVisible ? 1.0 : 0.0

    Behavior on scale {
        NumberAnimation { duration: 250; easing.type: Easing.OutBack; easing.overshoot: 1.08 }
    }
    Behavior on opacity {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    property int selectedIndex: -1

    // 1. Campo de búsqueda Spotlight estilo macOS
    Rectangle {
        id: searchContainer
        anchors.top: parent.top
        anchors.topMargin: 20
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        height: 46
        radius: 15
        color: titanTheme.contentCardBg
        border.color: searchField.activeFocus ? titanTheme.accent : titanTheme.contentCardBorder
        border.width: searchField.activeFocus ? 1.5 : 1

        Behavior on border.color { ColorAnimation { duration: 160 } }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            spacing: 10

            Item {
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter

                Canvas {
                    id: searchIconCanvas
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.strokeStyle = searchField.activeFocus ? titanTheme.accent : titanTheme.contentTextSecondary;
                        ctx.lineWidth = 2.0;
                        ctx.lineCap = "round";
                        ctx.beginPath();
                        ctx.arc(8, 8, 5.5, 0, Math.PI * 2);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(12.5, 12.5);
                        ctx.lineTo(17, 17);
                        ctx.stroke();
                    }
                    Connections {
                        target: searchField
                        function onActiveFocusChanged() { searchIconCanvas.requestPaint(); }
                    }
                }
            }

            TextField {
                id: searchField
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 64
                placeholderText: "Buscar aplicaciones..."
                font.pixelSize: 13
                focus: true
                background: null
                color: titanTheme.contentTextPrimary
                placeholderTextColor: titanTheme.contentTextSecondary

                onTextChanged: launcherBackend.search(text)
                Keys.onEscapePressed: shellBackend.closeLauncher()
                Keys.onUpPressed: {
                    if (launcher.selectedIndex > 0) launcher.selectedIndex--
                }
                Keys.onDownPressed: {
                    if (launcher.selectedIndex < appGrid.count - 1) launcher.selectedIndex++
                }
                Keys.onReturnPressed: {
                    if (launcher.selectedIndex >= 0 && launcher.selectedIndex < appGrid.count) {
                        var item = launcherBackend.apps[launcher.selectedIndex]
                        if (item) {
                            launcherBackend.launch(item.exec)
                            shellBackend.closeLauncher()
                        }
                    }
                }
            }

            Item {
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                visible: searchField.text.length > 0

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: clearMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.18) : Qt.rgba(0, 0, 0, 0.10)
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: titanTheme.contentTextPrimary
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { searchField.text = ""; searchField.forceActiveFocus() }
                }
            }
        }
    }

    // 2. Encabezado de sección
    Text {
        id: sectionLabel
        anchors.top: searchContainer.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.leftMargin: 28
        text: searchField.text.length > 0 ? "Resultados de búsqueda" : "Todas las aplicaciones"
        color: titanTheme.contentTextSecondary
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 0.6
    }

    // 3. Rejilla simétrica de aplicaciones en filas y columnas
    GridView {
        id: appGrid
        anchors.top: sectionLabel.bottom
        anchors.topMargin: 10
        anchors.bottom: pageDotsRow.top
        anchors.bottomMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        clip: true

        cellWidth: Math.floor(width / 5)
        cellHeight: 106
        model: launcherBackend.apps
        cacheBuffer: 300

        ScrollBar.vertical: ScrollBar {
            active: appGrid.moving || appGrid.flicking
            width: 5
            policy: ScrollBar.AsNeeded
        }

        delegate: Item {
            id: gridDelegate
            width: appGrid.cellWidth
            height: appGrid.cellHeight

            property int itemIndex: index
            property bool isSelected: launcher.selectedIndex === index

            // Animación de entrada fluida escalonada
            opacity: 0
            y: 8

            Component.onCompleted: {
                entranceAnim.delay = Math.min(index * 16, 180)
                entranceAnim.start()
            }

            SequentialAnimation {
                id: entranceAnim
                property int delay: 0
                PauseAnimation { duration: entranceAnim.delay }
                ParallelAnimation {
                    NumberAnimation { target: gridDelegate; property: "opacity"; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                    NumberAnimation { target: gridDelegate; property: "y"; to: 0; duration: 200; easing.type: Easing.OutCubic }
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: 14
                color: gridItemMouse.containsMouse || isSelected ? titanTheme.itemHover : "transparent"
                border.color: (gridItemMouse.containsMouse || isSelected) ? titanTheme.glassBorder : "transparent"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Column {
                anchors.centerIn: parent
                spacing: 7

                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 54
                    height: 54
                    scale: gridItemMouse.containsMouse ? 1.10 : 1.0
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        source: {
                            var ic = (modelData && modelData.icon) ? modelData.icon : "";
                            if (ic.indexOf("/") !== -1) return ic;
                            if (ic === "folder" || ic === "titan-finder") return "qrc:/icons/finder.png";
                            if (ic === "utilities-terminal" || ic === "terminal" || ic === "titan-terminal") return "qrc:/icons/terminal.png";
                            if (ic === "system-file-manager" || ic === "pcmanfm-qt" || ic === "files") return "qrc:/icons/files.png";
                            if (ic === "help-about" || ic === "titan-acerca") return "qrc:/icons/about.png";
                            if (ic === "firefox" || ic === "safari") return "qrc:/icons/safari.png";
                            if (ic === "vscode" || ic === "code") return "qrc:/icons/vscode.png";
                            if (ic === "system" || ic === "titan-settings") return "qrc:/icons/system.png";
                            if (ic === "onlyoffice" || ic === "onlyoffice-desktopeditors") return "qrc:/icons/onlyoffice.png";
                            return "qrc:/icons/developer.png";
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData ? modelData.name : ""
                    color: titanTheme.contentTextPrimary
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    width: appGrid.cellWidth - 16
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
            }

            MouseArea {
                id: gridItemMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: launcher.selectedIndex = index
                onExited: if (launcher.selectedIndex === index) launcher.selectedIndex = -1
                onClicked: {
                    shellBackend.showSplash(modelData.name, modelData.icon, modelData.exec)
                    launcherBackend.launch(modelData.exec)
                    shellBackend.closeLauncher()
                }
            }
        }
    }

    // 4. Indicador de páginas inferior
    Row {
        id: pageDotsRow
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6

        Repeater {
            model: Math.max(1, Math.ceil(appGrid.count / 15))
            delegate: Rectangle {
                width: index === 0 ? 14 : 6
                height: 6
                radius: 3
                color: index === 0 ? titanTheme.accent : Qt.rgba(0.5, 0.5, 0.5, 0.4)
                Behavior on width { NumberAnimation { duration: 180 } }
            }
        }
    }
}
