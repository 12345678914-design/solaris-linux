import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: desktopIconsRoot
    anchors.fill: parent

    TitanTheme { id: titanTheme }

    // Parámetros de la rejilla simétrica estilo macOS
    readonly property real cellWidth: 96
    readonly property real cellHeight: 102
    readonly property real gridTop: 36
    readonly property real gridRight: 16
    readonly property int maxRows: Math.max(1, Math.floor((height - gridTop - 74) / cellHeight))

    // Estado del menú contextual
    property string ctxPath: ""
    property real ctxX: 0
    property real ctxY: 0
    property bool ctxVisible: false

    // Cerrar menú al hacer clic fuera
    MouseArea {
        anchors.fill: parent
        enabled: desktopIconsRoot.ctxVisible
        z: 15
        onClicked: desktopIconsRoot.ctxVisible = false
    }

    // Función para obtener la posición por defecto simétrica en columnas desde la derecha
    function defaultPositionForIndex(idx) {
        var col = Math.floor(idx / maxRows)
        var row = idx % maxRows
        var posX = desktopIconsRoot.width - gridRight - 90 - (col * cellWidth)
        var posY = gridTop + (row * cellHeight)
        return { x: posX, y: posY }
    }

    // Función para calcular la celda de la rejilla más cercana y evitar colisiones
    function snapToGrid(reqX, reqY, currentItemPath) {
        var rawCol = Math.round((desktopIconsRoot.width - gridRight - 90 - reqX) / cellWidth)
        var rawRow = Math.round((reqY - gridTop) / cellHeight)
        var col = Math.max(0, rawCol)
        var row = Math.max(0, Math.min(maxRows - 1, rawRow))

        // Evitar que choque con otro icono ya posicionado
        var occupied = true
        var attempts = 0
        while (occupied && attempts < 50) {
            occupied = false
            for (var i = 0; i < iconRepeater.count; ++i) {
                var it = iconRepeater.itemAt(i)
                if (it && it.itemPath !== currentItemPath) {
                    var itCol = Math.round((desktopIconsRoot.width - gridRight - 90 - it.x) / cellWidth)
                    var itRow = Math.round((it.y - gridTop) / cellHeight)
                    if (itCol === col && itRow === row) {
                        occupied = true
                        row++
                        if (row >= maxRows) {
                            row = 0
                            col++
                        }
                        break
                    }
                }
            }
            attempts++
        }

        var snapX = desktopIconsRoot.width - gridRight - 90 - (col * cellWidth)
        var snapY = gridTop + (row * cellHeight)
        return { x: snapX, y: snapY }
    }

    Repeater {
        id: iconRepeater
        model: desktopBackend.items

        delegate: Item {
            id: iconWrapper

            readonly property string itemPath: modelData.path
            property var savedPos: desktopBackend.iconPosition(modelData.path)
            property var defPos: desktopIconsRoot.defaultPositionForIndex(index)

            x: (savedPos && savedPos.x >= 0) ? savedPos.x : defPos.x
            y: (savedPos && savedPos.y >= 0) ? savedPos.y : defPos.y

            width: 90
            height: 92
            z: iconMouse.drag.active ? 20 : 1

            Behavior on x {
                enabled: !iconMouse.drag.active
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                enabled: !iconMouse.drag.active
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            property bool isHovered: iconMouse.containsMouse

            // Resaltado al pasar el puntero
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: iconWrapper.isHovered ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                border.color: iconWrapper.isHovered ? Qt.rgba(1, 1, 1, 0.25) : "transparent"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 6
                spacing: 4
                width: parent.width

                // Icono de la aplicación
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 52
                    height: 52
                    scale: iconWrapper.isHovered ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    Image {
                        anchors.fill: parent
                        source: modelData.icon ? modelData.icon : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        asynchronous: true
                    }
                }

                // Etiqueta con fondo redondeado
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(84, labelText.implicitWidth + 10)
                    height: labelText.implicitHeight + 4
                    radius: 4
                    color: iconWrapper.isHovered ? Qt.rgba(0, 0.44, 0.89, 0.88) : Qt.rgba(0, 0, 0, 0.44)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        id: labelText
                        anchors.centerIn: parent
                        text: modelData.name ? modelData.name : ""
                        color: "#ffffff"
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        elide: Text.ElideMiddle
                        maximumLineCount: 2
                        wrapMode: Text.WrapAnywhere
                        horizontalAlignment: Text.AlignHCenter
                        width: 80
                    }
                }
            }

            MouseArea {
                id: iconMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: iconMouse.drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                drag.target: iconWrapper
                drag.axis: Drag.XAndYAxis
                drag.minimumX: 8
                drag.maximumX: Math.max(8, desktopIconsRoot.width - iconWrapper.width - 8)
                drag.minimumY: desktopIconsRoot.gridTop
                drag.maximumY: Math.max(desktopIconsRoot.gridTop, desktopIconsRoot.height - iconWrapper.height - 70)

                property real pressStartX: 0
                property real pressStartY: 0

                onPressed: (mouse) => {
                    pressStartX = iconWrapper.x
                    pressStartY = iconWrapper.y
                }

                onReleased: (mouse) => {
                    // Ajuste estricto a la cuadrícula de filas y columnas evitando choques
                    var snapped = desktopIconsRoot.snapToGrid(iconWrapper.x, iconWrapper.y, modelData.path)
                    iconWrapper.x = snapped.x
                    iconWrapper.y = snapped.y
                    desktopBackend.moveItem(modelData.path, snapped.x, snapped.y)
                }

                onDoubleClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        shellBackend.showSplash(modelData.name, modelData.icon, (modelData.exec ? modelData.exec : modelData.path))
                        desktopBackend.openItem(modelData.path)
                    }
                }

                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        desktopIconsRoot.ctxPath = modelData.path
                        var pt = iconWrapper.mapToItem(desktopIconsRoot, mouse.x, mouse.y)
                        desktopIconsRoot.ctxX = Math.min(pt.x, desktopIconsRoot.width - 190)
                        desktopIconsRoot.ctxY = Math.min(pt.y, desktopIconsRoot.height - 120)
                        desktopIconsRoot.ctxVisible = true
                    }
                }
            }
        }
    }

    // ── Menú Contextual Liquid Glass ──────────────────────────────────────────
    Rectangle {
        id: contextMenu
        visible: desktopIconsRoot.ctxVisible
        x: desktopIconsRoot.ctxX
        y: desktopIconsRoot.ctxY
        width: 178
        height: ctxCol.implicitHeight + 16
        radius: 13
        z: 30

        opacity: visible ? 1.0 : 0.0
        scale: visible ? 1.0 : 0.92
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

        gradient: Gradient {
            GradientStop { position: 0.0; color: titanTheme.windowBgTop }
            GradientStop { position: 1.0; color: titanTheme.windowBgBottom }
        }
        border.color: titanTheme.glassBorder
        border.width: 1

        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 20
            height: 1
            color: titanTheme.specularGlow
            radius: 1
        }

        Column {
            id: ctxCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 2

            // Opción "Abrir"
            Rectangle {
                width: parent.width
                height: 36
                radius: 8
                color: openMouse.containsMouse ? titanTheme.itemHover : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    spacing: 8
                    Text { text: "↗"; color: titanTheme.contentTextPrimary; font.pixelSize: 13 }
                    Text { text: "Abrir"; color: titanTheme.contentTextPrimary; font.pixelSize: 13 }
                }

                MouseArea {
                    id: openMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        desktopIconsRoot.ctxVisible = false
                        desktopBackend.openItem(desktopIconsRoot.ctxPath)
                    }
                }
            }

            // Separador
            Rectangle {
                width: parent.width - 16
                height: 1
                anchors.horizontalCenter: parent.horizontalCenter
                color: titanTheme.glassBorder
                opacity: 0.6
            }

            // Opción "Eliminar del Escritorio"
            Rectangle {
                width: parent.width
                height: 36
                radius: 8
                color: deleteMouse.containsMouse ? Qt.rgba(0.9, 0.12, 0.12, 0.18) : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    spacing: 8
                    Text { text: "🗑"; color: deleteMouse.containsMouse ? "#ff4444" : titanTheme.contentTextPrimary; font.pixelSize: 13 }
                    Text {
                        text: "Eliminar"
                        color: deleteMouse.containsMouse ? "#ff4444" : titanTheme.contentTextPrimary
                        font.pixelSize: 13
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }
                }

                MouseArea {
                    id: deleteMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        desktopIconsRoot.ctxVisible = false
                        desktopBackend.removeItem(desktopIconsRoot.ctxPath)
                    }
                }
            }
        }
    }
}
