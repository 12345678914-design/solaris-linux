import QtQuick
import QtQuick.Controls
import QtQuick.Effects   // MultiEffect (Qt 6.5+), solo para recortar esquinas

Item {
    id: pickerRoot
    width: Math.min(840, parent ? parent.width - 40 : 840)
    height: Math.min(580, parent ? parent.height - 60 : 580)

    TitanTheme { id: theme }   // una sola instancia

    // ---------- Opciones y señales ----------
    property bool showAddTile: true          // tarjeta "Añadir imagen…"
    signal addImageRequested()               // conéctala a tu diálogo de archivos / backend

    // ---------- Estado ----------
    property int tabIndex: 0                 // 0 todos, 1 claros, 2 oscuros, 3 mis imágenes
    property string originalWallpaper: ""    // para poder restaurar
    readonly property int columns: width >= 760 ? 4 : 3
    readonly property real cardRadius: 20

    // Datos opcionales por fondo: isDark (bool), isCustom (bool), width/height (int)
    readonly property bool hasDarkInfo: anyHas(shellBackend.wallpapers, "isDark")
    readonly property bool hasCustomInfo: anyHas(shellBackend.wallpapers, "isCustom")
    readonly property var items: buildItems(tabIndex, shellBackend.wallpapers)
    readonly property bool emptyCategory: items.length === 0 || (items.length === 1 && items[0].isAdd === true)

    function anyHas(list, key) {
        if (!list) return false
        for (var i = 0; i < list.length; i++)
            if (list[i][key] !== undefined) return true
        return false
    }

    function buildItems(tab, list) {
        var out = []
        if (list) {
            for (var i = 0; i < list.length; i++) {
                var w = list[i]
                if (tab === 1 && w.isDark !== false) continue
                if (tab === 2 && w.isDark !== true) continue
                if (tab === 3 && w.isCustom !== true) continue
                out.push(w)
            }
        }
        if (showAddTile && (tab === 0 || tab === 3)) out.push({ isAdd: true })
        return out
    }

    function toUrl(p) {
        if (!p) return ""
        var s = p.toString()
        if (s.indexOf("://") !== -1 || s.indexOf("qrc:") === 0) return s
        if (s.charAt(0) === "/") return "file://" + s
        return s
    }

    function positionAtSelected() {
        for (var i = 0; i < items.length; i++) {
            if (items[i].path === shellBackend.currentWallpaper) {
                appGrid.currentIndex = i
                appGrid.positionViewAtIndex(i, GridView.Contain)
                return
            }
        }
        appGrid.currentIndex = items.length > 0 ? 0 : -1
    }

    function applyItem(w) {
        if (!w) return
        if (w.isAdd) {
            addImageRequested()
            shellBackend.openSettings("wallpaper")
            return
        }
        shellBackend.setWallpaper(w.path)
    }

    onItemsChanged: Qt.callLater(positionAtSelected)

    onVisibleChanged: {
        if (visible) {
            originalWallpaper = shellBackend.currentWallpaper
            tabIndex = 0
            enterAnim.restart()
            appGrid.forceActiveFocus()
            Qt.callLater(positionAtSelected)
        }
    }

    Component.onCompleted: {
        originalWallpaper = shellBackend.currentWallpaper
        bg.start(shellBackend.currentWallpaper)
        appGrid.forceActiveFocus()
        Qt.callLater(positionAtSelected)
    }

    // Escape cierra (llega desde la rejilla si ésta no lo consume)
    Keys.onEscapePressed: shellBackend.closeWallpaperPicker()

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: pickerRoot; property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: pickerRoot; property: "scale"; from: 0.96; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    // ---------- Componentes reutilizables ----------

    // Pestaña tipo píldora
    component TabPill: Rectangle {
        id: pill
        property string label: ""
        property bool active: false
        property color textColor: "white"
        signal clicked()
        height: 26
        width: pillText.implicitWidth + 26
        radius: 13
        color: active ? Qt.rgba(1, 1, 1, 0.20) : (pillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.textColor
            font.pixelSize: 12
            font.weight: pill.active ? Font.Medium : Font.Normal
        }
        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }

    // Miniatura de fondo (o tarjeta "añadir")
    component WallpaperCell: Item {
        id: cell
        property string name: ""
        property url thumb: ""
        property string info: ""
        property bool selected: false
        property bool highlighted: false
        property bool isAdd: false
        property color accent: "#0a84ff"
        property color textColor: "white"
        property color mutedColor: "#bbbbbb"
        signal activated()

        readonly property real thumbW: width - 16
        readonly property real thumbH: Math.round(thumbW * 9 / 16)
        readonly property bool hot: cellMouse.containsMouse || highlighted
        z: hot ? 10 : 0

        Item {
            id: thumbBox
            x: 8
            y: 6
            width: cell.thumbW
            height: cell.thumbH
            scale: cell.hot ? 1.04 : 1.0
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            // Contenido recortado con esquinas redondeadas
            Item {
                anchors.fill: parent
                visible: !cell.isAdd
                layer.enabled: !cell.isAdd
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: thumbMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.08) }   // marcador de carga

                Image {
                    id: thumbImage
                    anchors.fill: parent
                    source: cell.thumb
                    sourceSize: Qt.size(360, 203)       // no decodifica a resolución completa
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                    opacity: status === Image.Ready ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }

                // Franja con nombre y resolución al pasar el cursor
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 24
                    color: Qt.rgba(0.04, 0.045, 0.055, 0.62)
                    opacity: cell.hot ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: cell.info !== "" ? cell.name + "  ·  " + cell.info : cell.name
                        color: "#ffffff"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }

            Rectangle {
                id: thumbMask
                anchors.fill: parent
                radius: 10
                visible: false
                layer.enabled: true
            }

            // Borde fino
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "transparent"
                visible: !cell.isAdd
                border.color: Qt.rgba(1, 1, 1, 0.22)
                border.width: 1
            }

            // Anillo de selección (separado de la imagen)
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: 13
                color: "transparent"
                border.color: cell.accent
                border.width: 2
                opacity: cell.selected ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            // Check de seleccionado (dibujado)
            Rectangle {
                visible: cell.selected && !cell.isAdd
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 6
                width: 20
                height: 20
                radius: 10
                color: cell.accent

                Canvas {
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    onPaint: {
                        var c = getContext("2d")
                        c.reset()
                        c.strokeStyle = "#ffffff"
                        c.lineWidth = 1.8
                        c.lineCap = "round"
                        c.lineJoin = "round"
                        c.beginPath()
                        c.moveTo(2.5, 6.2)
                        c.lineTo(5, 8.6)
                        c.lineTo(9.5, 3.6)
                        c.stroke()
                    }
                }
            }

            // Tarjeta "Añadir imagen…"
            Item {
                anchors.fill: parent
                visible: cell.isAdd

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: cell.hot ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.05)
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                Canvas {
                    id: dashCanvas
                    anchors.fill: parent
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d")
                        c.reset()
                        c.strokeStyle = Qt.rgba(1, 1, 1, 0.5)
                        c.lineWidth = 1
                        c.setLineDash([5, 4])
                        var r = 10, x = 1, y = 1, w = width - 2, h = height - 2
                        c.beginPath()
                        c.moveTo(x + r, y)
                        c.lineTo(x + w - r, y)
                        c.arcTo(x + w, y, x + w, y + r, r)
                        c.lineTo(x + w, y + h - r)
                        c.arcTo(x + w, y + h, x + w - r, y + h, r)
                        c.lineTo(x + r, y + h)
                        c.arcTo(x, y + h, x, y + h - r, r)
                        c.lineTo(x, y + r)
                        c.arcTo(x, y, x + r, y, r)
                        c.closePath()
                        c.stroke()
                    }
                }

                Rectangle { anchors.centerIn: parent; width: 18; height: 2; radius: 1; color: cell.textColor }
                Rectangle { anchors.centerIn: parent; width: 2; height: 18; radius: 1; color: cell.textColor }
            }
        }

        // Nombre debajo
        Text {
            anchors.top: thumbBox.bottom
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            width: cell.thumbW
            text: cell.isAdd ? qsTr("Añadir imagen…") : cell.name
            color: cell.selected ? cell.accent : cell.textColor
            font.pixelSize: 11
            font.weight: cell.selected ? Font.Medium : Font.Normal
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        MouseArea {
            id: cellMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cell.activated()
        }
    }

    // ---------- TARJETA ----------
    Item {
        id: card
        anchors.fill: parent

        // Fondo de vidrio: el fondo actual, decodificado en minúscula y ampliado
        // (el suavizado de la ampliación hace de desenfoque, sin coste de GPU extra)
        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: cardMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Item {
                id: bg
                anchors.fill: parent
                property bool flip: false

                function start(path) {
                    imgA.source = pickerRoot.toUrl(path)
                    flip = false
                }

                Connections {
                    target: shellBackend
                    function onCurrentWallpaperChanged() {
                        var u = pickerRoot.toUrl(shellBackend.currentWallpaper)
                        if (bg.flip) imgA.source = u
                        else imgB.source = u
                        bg.flip = !bg.flip
                    }
                }

                Rectangle { anchors.fill: parent; color: theme.isDark ? "#14151c" : "#e8e9ef" }

                Image {
                    id: imgA
                    anchors.fill: parent
                    sourceSize: Qt.size(48, 27)
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    asynchronous: true
                    opacity: bg.flip ? 0.0 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.InOutQuad } }
                }
                Image {
                    id: imgB
                    anchors.fill: parent
                    sourceSize: Qt.size(48, 27)
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    asynchronous: true
                    opacity: bg.flip ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.InOutQuad } }
                }
            }

            // Tinte para legibilidad
            Rectangle {
                anchors.fill: parent
                radius: pickerRoot.cardRadius
                color: theme.isDark ? Qt.rgba(0.08, 0.09, 0.13, 0.58) : Qt.rgba(0.97, 0.97, 0.99, 0.60)
            }

            Rectangle {
                anchors.fill: parent
                radius: pickerRoot.cardRadius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, theme.isDark ? 0.08 : 0.25) }
                    GradientStop { position: 0.3; color: Qt.rgba(1, 1, 1, 0.0) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, theme.isDark ? 0.14 : 0.04) }
                }
            }
        }

        Rectangle {
            id: cardMask
            anchors.fill: parent
            radius: pickerRoot.cardRadius
            visible: false
            layer.enabled: true
        }

        Rectangle {
            anchors.fill: parent
            radius: pickerRoot.cardRadius
            color: "transparent"
            border.color: theme.glassBorder
            border.width: 1
        }

        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 40
            height: 1
            radius: 1
            color: theme.specularGlow
        }

        // ---------- 1. ENCABEZADO ----------
        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 64

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Rectangle {
                    width: 36
                    height: 36
                    radius: 10
                    color: theme.accent
                    anchors.verticalCenter: parent.verticalCenter

                    // Icono "imagen" dibujado
                    Canvas {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        onPaint: {
                            var c = getContext("2d")
                            c.reset()
                            c.strokeStyle = "#ffffff"
                            c.fillStyle = "#ffffff"
                            c.lineWidth = 1.6
                            c.lineCap = "round"
                            c.lineJoin = "round"
                            c.beginPath()
                            c.moveTo(5, 3.5); c.lineTo(15, 3.5)
                            c.arcTo(17, 3.5, 17, 5.5, 2)
                            c.lineTo(17, 14.5)
                            c.arcTo(17, 16.5, 15, 16.5, 2)
                            c.lineTo(5, 16.5)
                            c.arcTo(3, 16.5, 3, 14.5, 2)
                            c.lineTo(3, 5.5)
                            c.arcTo(3, 3.5, 5, 3.5, 2)
                            c.closePath()
                            c.stroke()
                            c.beginPath(); c.arc(7.2, 8, 1.5, 0, Math.PI * 2); c.fill()
                            c.beginPath()
                            c.moveTo(3.5, 14.5); c.lineTo(8, 10.5); c.lineTo(11, 13.5); c.lineTo(13.5, 11.5); c.lineTo(16.5, 14.5)
                            c.stroke()
                        }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: qsTr("Fondos de pantalla")
                        color: theme.headerText
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: qsTr("Elige un fondo para tu escritorio")
                        color: theme.contentTextSecondary
                        font.pixelSize: 11
                    }
                }
            }

            // Cierre (cruz dibujada)
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                radius: 14
                color: closeMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.18) : Qt.rgba(0, 0, 0, 0.08)
                Behavior on color { ColorAnimation { duration: 100 } }

                Rectangle { anchors.centerIn: parent; width: 11; height: 1.6; radius: 1; rotation: 45;  color: theme.headerText }
                Rectangle { anchors.centerIn: parent; width: 11; height: 1.6; radius: 1; rotation: -45; color: theme.headerText }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.closeWallpaperPicker()
                }
            }
        }

        // ---------- 2. PESTAÑAS ----------
        Row {
            id: tabsRow
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.leftMargin: 20
            spacing: 4
            height: 28

            TabPill {
                label: qsTr("Todos")
                active: pickerRoot.tabIndex === 0
                textColor: theme.contentTextPrimary
                onClicked: pickerRoot.tabIndex = 0
            }
            TabPill {
                visible: pickerRoot.hasDarkInfo
                label: qsTr("Claros")
                active: pickerRoot.tabIndex === 1
                textColor: theme.contentTextPrimary
                onClicked: pickerRoot.tabIndex = 1
            }
            TabPill {
                visible: pickerRoot.hasDarkInfo
                label: qsTr("Oscuros")
                active: pickerRoot.tabIndex === 2
                textColor: theme.contentTextPrimary
                onClicked: pickerRoot.tabIndex = 2
            }
            TabPill {
                visible: pickerRoot.hasCustomInfo
                label: qsTr("Mis imágenes")
                active: pickerRoot.tabIndex === 3
                textColor: theme.contentTextPrimary
                onClicked: pickerRoot.tabIndex = 3
            }
        }

        // ---------- 3. REJILLA (virtualizada) ----------
        GridView {
            id: appGrid
            anchors.top: tabsRow.bottom
            anchors.topMargin: 8
            anchors.bottom: footer.top
            anchors.bottomMargin: 4
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            clip: true

            cellWidth: Math.floor(width / pickerRoot.columns)
            cellHeight: Math.round((cellWidth - 16) * 9 / 16) + 44
            model: pickerRoot.items
            cacheBuffer: 400
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            focus: true

            Keys.onReturnPressed: pickerRoot.applyItem(pickerRoot.items[currentIndex])
            Keys.onEnterPressed: pickerRoot.applyItem(pickerRoot.items[currentIndex])

            ScrollBar.vertical: ScrollBar {
                id: vBar
                policy: ScrollBar.AsNeeded
                width: 6
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: 3
                    color: vBar.pressed ? theme.accent : (vBar.hovered ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(1, 1, 1, 0.28))
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
            }

            delegate: WallpaperCell {
                width: appGrid.cellWidth
                height: appGrid.cellHeight
                isAdd: modelData.isAdd === true
                name: modelData.name ? modelData.name : ""
                thumb: modelData.thumbnail ? modelData.thumbnail : ""
                info: modelData.width && modelData.height ? (modelData.width + "×" + modelData.height) : ""
                selected: !isAdd && shellBackend.currentWallpaper === modelData.path
                highlighted: GridView.isCurrentItem && appGrid.activeFocus
                accent: theme.accent
                textColor: theme.contentTextPrimary
                mutedColor: theme.contentTextSecondary
                onActivated: {
                    appGrid.currentIndex = index
                    pickerRoot.applyItem(modelData)
                }
            }
        }

        // Estado vacío de la categoría
        Text {
            anchors.centerIn: appGrid
            visible: pickerRoot.emptyCategory && !pickerRoot.showAddTile
            text: qsTr("No hay fondos en esta categoría.")
            color: theme.contentTextSecondary
            font.pixelSize: 13
        }

        // ---------- 4. PIE ----------
        Item {
            id: footer
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 54

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                height: 1
                color: theme.headerBorder
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 18

                // Ajustes de pantalla
                Item {
                    width: settingsRow.width
                    height: 28

                    Row {
                        id: settingsRow
                        spacing: 7
                        anchors.verticalCenter: parent.verticalCenter

                        Canvas {
                            id: slidersIcon
                            width: 14
                            height: 14
                            anchors.verticalCenter: parent.verticalCenter
                            onPaint: {
                                var c = getContext("2d")
                                c.reset()
                                c.strokeStyle = theme.contentTextPrimary
                                c.fillStyle = theme.contentTextPrimary
                                c.lineWidth = 1.4
                                c.lineCap = "round"
                                c.beginPath(); c.moveTo(1.5, 4); c.lineTo(12.5, 4); c.stroke()
                                c.beginPath(); c.moveTo(1.5, 10); c.lineTo(12.5, 10); c.stroke()
                                c.beginPath(); c.arc(9, 4, 2, 0, Math.PI * 2); c.fill()
                                c.beginPath(); c.arc(5, 10, 2, 0, Math.PI * 2); c.fill()
                            }
                            Connections {
                                target: theme
                                function onIsDarkChanged() { slidersIcon.requestPaint() }
                            }
                        }

                        Text {
                            text: qsTr("Ajustes de pantalla…")
                            color: theme.contentTextPrimary
                            font.pixelSize: 12
                            opacity: settingsMouse.containsMouse ? 1.0 : 0.85
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: settingsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shellBackend.openSettings("wallpaper")
                    }
                }

                // Restaurar el fondo con el que se abrió el selector
                Item {
                    width: restoreText.implicitWidth
                    height: 28
                    visible: shellBackend.currentWallpaper !== pickerRoot.originalWallpaper

                    Text {
                        id: restoreText
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Restaurar fondo anterior")
                        color: theme.accent
                        font.pixelSize: 12
                        opacity: restoreMouse.containsMouse ? 1.0 : 0.85
                    }
                    MouseArea {
                        id: restoreMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shellBackend.setWallpaper(pickerRoot.originalWallpaper)
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 88
                height: 32
                radius: 8
                color: okMouse.pressed ? Qt.darker(theme.accent, 1.2)
                       : (okMouse.containsMouse ? Qt.lighter(theme.accent, 1.12) : theme.accent)
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Listo")
                    color: "#ffffff"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: okMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.closeWallpaperPicker()
                }
            }
        }
    }
}
