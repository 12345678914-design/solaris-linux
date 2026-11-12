import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Effects   // MultiEffect (Qt 6.5+), solo para recortar esquinas

Item {
    id: dynamicIslandRoot
    width: islandCard.width
    height: islandCard.height

    TitanTheme { id: theme }

    // ---------- Datos del backend ----------
    readonly property bool active: shellBackend.islandActive
    readonly property var notif: shellBackend.currentIslandNotification
    readonly property var actions: notif && notif.actions ? notif.actions : []
    readonly property int queued: (typeof shellBackend !== "undefined" && typeof shellBackend.islandQueueCount !== "undefined" && shellBackend.islandQueueCount) ? shellBackend.islandQueueCount : 0

    // ---------- Opciones ----------
    property bool showIdlePill: false        // true = pastilla visible incluso sin notificación
    property real expandedWidth: 380
    property int  compactWidth: 140
    property int  compactHeight: 26

    // Wallpaper ya desenfocado y reducido (se genera una sola vez fuera de QML).
    // Ej.: magick wall.jpg -resize 25% -blur 0x10 -modulate 100,140 wall-blur.jpg
    readonly property url blurredWallpaper: (typeof shellBackend !== "undefined" && typeof shellBackend.blurredWallpaper !== "undefined" && shellBackend.blurredWallpaper) ? shellBackend.blurredWallpaper : ""
    readonly property bool hasGlass: blurredWallpaper.toString() !== ""

    // Dibujar la isla (visible solo si hay algo que mostrar)
    readonly property bool shown: active || showIdlePill

    signal actionTriggered(var action)       // conecta esto a tu backend

    // Posición de la isla en pantalla (para alinear el wallpaper borroso)
    property real glassOriginX: 0
    property real glassOriginY: 0
    function updateOrigin() {
        if (!islandCard) return
        var p = islandCard.mapToGlobal(0, 0)
        var vx = (typeof Screen !== "undefined" && typeof Screen.virtualX !== "undefined") ? Screen.virtualX : 0
        var vy = (typeof Screen !== "undefined" && typeof Screen.virtualY !== "undefined") ? Screen.virtualY : 0
        glassOriginX = p.x - vx
        glassOriginY = p.y - vy
    }
    Component.onCompleted: Qt.callLater(updateOrigin)

    onNotifChanged: if (active && ringAnim) ringAnim.restart()
    onActiveChanged: if (active && ringAnim) ringAnim.restart()

    Item {
        id: islandCard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top

        readonly property real contentH: Math.max(40, textCol.implicitHeight)
                                         + (actionsRow.visible ? actionsRow.height + 10 : 0)

        width: dynamicIslandRoot.active
               ? Math.min(dynamicIslandRoot.expandedWidth, (typeof Screen !== "undefined" && Screen.width > 0 ? Screen.width : 1920) - 32)
               : dynamicIslandRoot.compactWidth
        height: dynamicIslandRoot.active
                ? Math.max(64, contentH + 28)
                : dynamicIslandRoot.compactHeight
        readonly property real cornerRadius: Math.min(height / 2, 24)

        onWidthChanged: Qt.callLater(dynamicIslandRoot.updateOrigin)
        onHeightChanged: Qt.callLater(dynamicIslandRoot.updateOrigin)

        // Mismo muelle en ancho y alto: la isla crece sin deformarse
        Behavior on width  { SpringAnimation { spring: 3.4; damping: 0.34; epsilon: 0.25 } }
        Behavior on height { SpringAnimation { spring: 3.4; damping: 0.34; epsilon: 0.25 } }

        // Si no se muestra, no se dibuja ni recibe clics
        opacity: dynamicIslandRoot.shown ? 1.0 : 0.0
        visible: opacity > 0.01
        scale: dynamicIslandRoot.shown ? 1.0 : 0.7
        transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        // Arrastrar hacia arriba para descartar
        transform: Translate { y: Math.min(0, swipe.translation.y) * 0.6 }
        DragHandler {
            id: swipe
            xAxis.enabled: false
            yAxis.enabled: true
            target: null
            enabled: dynamicIslandRoot.active
            onActiveChanged: {
                if (!active && translation.y < -24) shellBackend.dismissIsland()
            }
        }

        // ---------- VIDRIO: wallpaper borroso recortado + tinte oscuro ----------
        Item {
            anchors.fill: parent
            layer.enabled: dynamicIslandRoot.hasGlass
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: glassMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Image {
                visible: dynamicIslandRoot.hasGlass
                source: dynamicIslandRoot.blurredWallpaper
                x: -dynamicIslandRoot.glassOriginX
                y: -dynamicIslandRoot.glassOriginY
                width: (typeof Screen !== "undefined" && Screen.width > 0) ? Screen.width : 1920
                height: (typeof Screen !== "undefined" && Screen.height > 0) ? Screen.height : 1080
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
            }

            // Tinte: oscuro y casi opaco para un blur "pequeño" y legible
            Rectangle {
                anchors.fill: parent
                radius: islandCard.cornerRadius
                color: dynamicIslandRoot.hasGlass ? Qt.rgba(0.04, 0.045, 0.055, 0.80) : "#0a0b0e"
            }
        }

        Rectangle {
            id: glassMask
            anchors.fill: parent
            radius: islandCard.cornerRadius
            visible: false
            layer.enabled: true
        }

        // Borde fino y brillo superior
        Rectangle {
            anchors.fill: parent
            radius: islandCard.cornerRadius
            color: "transparent"
            border.color: dynamicIslandRoot.active ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.12)
            border.width: 1
        }
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - islandCard.cornerRadius * 1.6
            height: 1
            radius: 1
            color: Qt.rgba(1, 1, 1, 0.10)
        }

        // Anillo de acento tenue solo cuando llega una notificación nueva
        Rectangle {
            id: arrivalRing
            anchors.fill: parent
            radius: islandCard.cornerRadius
            color: "transparent"
            border.color: theme.accent
            border.width: 1
            opacity: 0.0

            SequentialAnimation {
                id: ringAnim
                NumberAnimation { target: arrivalRing; property: "opacity"; to: 0.45; duration: 160 }
                NumberAnimation { target: arrivalRing; property: "opacity"; to: 0.0; duration: 500; easing.type: Easing.OutCubic }
            }
        }

        // Clic en la tarjeta: abre el centro de notificaciones
        MouseArea {
            anchors.fill: parent
            z: -1
            enabled: dynamicIslandRoot.active
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                shellBackend.dismissIsland()
                shellBackend.toggleNotificationCenter()
            }
        }

        // ---------- CONTENIDO (aparece un poco después de crecer) ----------
        Item {
            id: body
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            anchors.topMargin: 14
            anchors.bottomMargin: 14

            opacity: dynamicIslandRoot.active && islandCard.height > 48 ? 1.0 : 0.0
            visible: opacity > 0.01
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: dynamicIslandRoot.active ? 110 : 0 }
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }

            // Icono
            Item {
                id: iconTile
                width: 40
                height: 40
                anchors.left: parent.left
                anchors.top: parent.top

                Rectangle { anchors.fill: parent; radius: 10; color: Qt.rgba(1, 1, 1, 0.09) }

                Image {
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    source: dynamicIslandRoot.notif && dynamicIslandRoot.notif.icon
                            ? dynamicIslandRoot.notif.icon : "qrc:/icons/system.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }

            // Cierre (cruz dibujada, sin depender de la fuente)
            Item {
                id: closeBtn
                width: 22
                height: 22
                anchors.right: parent.right
                anchors.top: parent.top

                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.12)
                }
                Rectangle { anchors.centerIn: parent; width: 10; height: 1.5; radius: 1; rotation: 45;  color: "#ffffff" }
                Rectangle { anchors.centerIn: parent; width: 10; height: 1.5; radius: 1; rotation: -45; color: "#ffffff" }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellBackend.dismissIsland()
                }
            }

            // Contador de cola "+N"
            Rectangle {
                id: queueBadge
                visible: dynamicIslandRoot.queued > 0
                height: 18
                width: queueText.implicitWidth + 14
                radius: 9
                color: theme.accent
                anchors.right: closeBtn.left
                anchors.rightMargin: 8
                anchors.top: parent.top
                anchors.topMargin: 2

                Text {
                    id: queueText
                    anchors.centerIn: parent
                    text: "+" + dynamicIslandRoot.queued
                    color: "#ffffff"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }

            // Textos
            Column {
                id: textCol
                anchors.left: iconTile.right
                anchors.leftMargin: 12
                anchors.right: queueBadge.visible ? queueBadge.left : closeBtn.left
                anchors.rightMargin: 8
                anchors.top: parent.top
                spacing: 2

                Row {
                    spacing: 6
                    Text {
                        text: dynamicIslandRoot.notif && dynamicIslandRoot.notif.appName
                              ? dynamicIslandRoot.notif.appName : qsTr("Sistema")
                        color: theme.accent
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                    Text { text: "•"; color: Qt.rgba(1, 1, 1, 0.4); font.pixelSize: 10 }
                    Text {
                        text: dynamicIslandRoot.notif && dynamicIslandRoot.notif.time
                              ? dynamicIslandRoot.notif.time : qsTr("Ahora")
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 11
                    }
                }

                Text {
                    width: parent.width
                    text: dynamicIslandRoot.notif && dynamicIslandRoot.notif.title ? dynamicIslandRoot.notif.title : ""
                    color: "#ffffff"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: dynamicIslandRoot.notif && dynamicIslandRoot.notif.message ? dynamicIslandRoot.notif.message : ""
                    color: Qt.rgba(1, 1, 1, 0.78)
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            // Botones de acción (si la notificación trae `actions`)
            Row {
                id: actionsRow
                visible: dynamicIslandRoot.actions && dynamicIslandRoot.actions.length > 0
                anchors.left: textCol.left
                anchors.top: textCol.bottom
                anchors.topMargin: 10
                spacing: 8

                Repeater {
                    model: dynamicIslandRoot.actions
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        height: 26
                        width: actionLabel.implicitWidth + 28
                        radius: 13
                        color: index === 0
                               ? (actionMouse.containsMouse ? Qt.lighter(theme.accent, 1.15) : theme.accent)
                               : (actionMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12))

                        Text {
                            id: actionLabel
                            anchors.centerIn: parent
                            text: modelData.label ? modelData.label : modelData
                            color: "#ffffff"
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dynamicIslandRoot.actionTriggered(modelData)
                        }
                    }
                }
            }
        }
    }
}
