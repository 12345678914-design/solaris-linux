import QtQuick
import QtQuick.Controls

// Visor de una foto: zoom con la rueda o pellizco, arrastrar para moverse,
// doble clic para ampliar/ajustar, flechas a los lados, tira de miniaturas
// y panel de información.
Item {
    id: visor

    required property var theme
    property bool panelInfo: false
    property bool tira: true
    property bool soloImagen: false           // presentación: sin controles
    property real escala: 1                    // 1 = ajustada a la ventana
    property int giro: 0                       // giro solo para ver (no guarda)
    readonly property var foto: fotosBackend.currentPhoto
    // Tamaño real cargado (sourceSize devuelve el límite pedido, no el real)
    readonly property real zoomReal: imagen.status === Image.Ready && anchoGirado > 0 && visor.foto.ancho > 0
                                     ? ajusteW * escala / ((giro % 180 === 0) ? visor.foto.ancho : visor.foto.alto) : 1
    readonly property real anchoGirado: (giro % 180 === 0) ? imagen.implicitWidth : imagen.implicitHeight
    readonly property real altoGirado: (giro % 180 === 0) ? imagen.implicitHeight : imagen.implicitWidth
    // Tamaño ajustado (sin ampliar fotos pequeñas por encima de su tamaño)
    readonly property real ajusteW: {
        if (anchoGirado <= 0) return 0
        var k = Math.min(zona.width / anchoGirado, zona.height / altoGirado, 1)
        return anchoGirado * k
    }
    readonly property real ajusteH: anchoGirado > 0 ? ajusteW * altoGirado / anchoGirado : 0

    function ampliar(f, px, py) {
        var nueva = Math.max(1, Math.min(escala * f, 12))
        if (px === undefined) { px = zona.width / 2; py = zona.height / 2 }
        // Mantener bajo el cursor el mismo punto de la foto
        var cx = (flick.contentX + px) / Math.max(1, flick.contentWidth)
        var cy = (flick.contentY + py) / Math.max(1, flick.contentHeight)
        escala = nueva
        flick.contentX = Math.max(0, cx * flick.contentWidth - px)
        flick.contentY = Math.max(0, cy * flick.contentHeight - py)
        flick.returnToBounds()
    }
    function tamanoReal() {
        var real = (giro % 180 === 0) ? visor.foto.ancho : visor.foto.alto
        if (anchoGirado <= 0 || !(real > 0)) return
        ampliar((real / ajusteW) / escala)
    }
    function ajustar() { escala = 1 }

    onFotoChanged: { escala = 1; giro = 0 }

    Rectangle {
        anchors.fill: parent
        color: visor.soloImagen ? "#000000" : (visor.theme.isDark ? "#141416" : "#ececee")
    }

    Item {
        id: zona
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.right: info.left
        anchors.bottom: tiraFotos.top
        clip: true

        Flickable {
            id: flick
            anchors.fill: parent
            contentWidth: Math.max(width, visor.ajusteW * visor.escala)
            contentHeight: Math.max(height, visor.ajusteH * visor.escala)
            interactive: visor.escala > 1.001
            boundsBehavior: Flickable.StopAtBounds

            Image {
                id: imagen
                // Girada: el rectángulo de la imagen intercambia ancho y alto
                width: (visor.giro % 180 === 0 ? visor.ajusteW : visor.ajusteH) * visor.escala
                height: (visor.giro % 180 === 0 ? visor.ajusteH : visor.ajusteW) * visor.escala
                x: (flick.contentWidth - width) / 2
                y: (flick.contentHeight - height) / 2
                rotation: visor.giro
                Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                source: visor.foto.url || ""
                sourceSize.width: 4096
                sourceSize.height: 4096
                asynchronous: true
                autoTransform: true
                cache: false
                retainWhileLoading: true
                smooth: true
                mipmap: true
                fillMode: Image.Stretch
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            // Mientras carga se ve la miniatura (ya está en caché)
            Image {
                anchors.centerIn: parent
                width: visor.ajusteW > 0 ? imagen.width : Math.min(zona.width, zona.height) * 0.6
                height: visor.ajusteW > 0 ? imagen.height : width
                visible: imagen.status !== Image.Ready
                source: visor.foto.miniatura || ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
        }

        // Rueda: zoom en el punto del cursor
        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (e) => {
                if (!(e.modifiers & Qt.ControlModifier) && e.pixelDelta.y !== 0 && visor.escala > 1.001)
                    return // touchpad sin Ctrl con zoom: desplazar
                visor.ampliar(Math.pow(1.0015, e.angleDelta.y), e.x, e.y)
            }
        }
        PinchHandler {
            target: null
            property real inicio: 1
            onActiveChanged: if (active) inicio = visor.escala
            onActiveScaleChanged: visor.escala = Math.max(1, Math.min(12, inicio * activeScale))
        }
        TapHandler {
            onDoubleTapped: (p) => {
                if (visor.escala > 1.01) visor.ajustar()
                else visor.ampliar(2.5, p.position.x, p.position.y)
            }
        }

        // Flechas a los lados (al pasar el ratón)
        HoverHandler { id: sobreZona }
        Repeater {
            model: [-1, 1]
            Rectangle {
                required property int modelData
                visible: !visor.soloImagen && fotosBackend.count > 1
                opacity: sobreZona.hovered ? (flecha.containsMouse ? 1 : 0.75) : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                anchors.verticalCenter: parent.verticalCenter
                x: modelData < 0 ? 14 : zona.width - width - 14
                width: 38; height: 38; radius: 19
                color: Qt.rgba(0, 0, 0, 0.45)
                border.color: Qt.rgba(1, 1, 1, 0.18)
                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: modelData < 0 ? -1 : 1
                    anchors.verticalCenterOffset: -2
                    text: modelData < 0 ? "‹" : "›"
                    color: "#ffffff"
                    font.pixelSize: 26
                }
                MouseArea {
                    id: flecha
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData < 0 ? fotosBackend.previousPhoto() : fotosBackend.nextPhoto()
                }
            }
        }

        // Indicador de zoom
        Rectangle {
            id: indicador
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            width: indTexto.implicitWidth + 22
            height: 26
            radius: 13
            color: Qt.rgba(0, 0, 0, 0.55)
            opacity: 0
            Text { id: indTexto; anchors.centerIn: parent; text: Math.round(visor.zoomReal * 100) + " %"; color: "#ffffff"; font.pixelSize: 12 }
            SequentialAnimation {
                id: animIndicador
                NumberAnimation { target: indicador; property: "opacity"; to: 1; duration: 100 }
                PauseAnimation { duration: 900 }
                NumberAnimation { target: indicador; property: "opacity"; to: 0; duration: 300 }
            }
        }
    }
    onEscalaChanged: if (!soloImagen) animIndicador.restart()

    // ---------------------------------------------------------------- tira
    Rectangle {
        id: tiraFotos
        anchors.left: parent.left
        anchors.right: info.left
        anchors.bottom: parent.bottom
        height: visor.tira && !visor.soloImagen && fotosBackend.count > 1 ? 66 : 0
        visible: height > 0
        color: visor.theme.isDark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(1, 1, 1, 0.6)

        ListView {
            id: listaTira
            anchors.fill: parent
            anchors.margins: 7
            orientation: ListView.Horizontal
            spacing: 4
            clip: true
            model: fotosBackend.photos
            currentIndex: fotosBackend.currentIndex
            highlightFollowsCurrentItem: false
            preferredHighlightBegin: width / 2 - 26
            preferredHighlightEnd: width / 2 + 26
            highlightRangeMode: ListView.ApplyRange
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                required property var modelData
                required property int index
                readonly property bool actual: index === fotosBackend.currentIndex
                width: actual ? 72 : 44
                height: 52
                Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Image {
                    anchors.fill: parent
                    source: modelData.miniatura
                    sourceSize.width: 128
                    sourceSize.height: 128
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: parent.actual ? 1 : 0.72
                }
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: 3
                    border.width: parent.actual ? 2 : 0
                    border.color: visor.theme.accent
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: fotosBackend.selectPhoto(index) }
            }
        }
    }

    // ---------------------------------------------------------------- información
    Rectangle {
        id: info
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: visor.panelInfo && !visor.soloImagen ? 290 : 0
        visible: width > 0
        clip: true
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        color: visor.theme.contentBackground
        Rectangle { width: 1; height: parent.height; color: visor.theme.contentCardBorder }

        property var d: ({})
        function recargar() { d = visor.foto.path ? fotosBackend.detalles(visor.foto.path) : ({}) }
        Connections {
            target: fotosBackend
            function onCurrentPhotoChanged() { if (visor.panelInfo) info.recargar() }
            function onAlbumesChanged() { if (visor.panelInfo) info.recargar() }
        }
        Connections {
            target: visor
            function onPanelInfoChanged() { if (visor.panelInfo) info.recargar() }
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: 18
            contentHeight: colInfo.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: colInfo
                width: parent.width
                spacing: 14

                Text {
                    width: parent.width
                    text: info.d.nombre || ""
                    color: visor.theme.contentTextPrimary
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    wrapMode: Text.WrapAnywhere
                }
                Text {
                    width: parent.width
                    text: (info.d.fechaEtiqueta || "") + "\n" + (info.d.fechaTexto || "")
                    color: visor.theme.contentTextSecondary
                    font.pixelSize: 12
                    lineHeight: 1.2
                    wrapMode: Text.Wrap
                }

                // Cámara y exposición (si la foto trae EXIF)
                Rectangle {
                    visible: !!info.d.camara || !!info.d.exposicion
                    width: parent.width
                    height: camCol.height + 20
                    radius: 10
                    color: visor.theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04)
                    Column {
                        id: camCol
                        x: 12; y: 10
                        width: parent.width - 24
                        spacing: 6
                        Text { text: "📷  " + (info.d.camara || "Cámara desconocida"); color: visor.theme.contentTextPrimary; font.pixelSize: 13; font.weight: Font.DemiBold; width: parent.width; elide: Text.ElideRight }
                        Text { visible: !!info.d.objetivo; text: info.d.objetivo || ""; color: visor.theme.contentTextSecondary; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
                        Row {
                            spacing: 12
                            Repeater {
                                model: [info.d.iso, info.d.focal, info.d.apertura, info.d.exposicion].filter(function (v) { return !!v })
                                Text { required property var modelData; text: modelData; color: visor.theme.contentTextPrimary; font.pixelSize: 12 }
                            }
                        }
                        Text { visible: !!info.d.flash; text: info.d.flash || ""; color: visor.theme.contentTextSecondary; font.pixelSize: 11 }
                    }
                }

                Repeater {
                    model: [
                        ["Dimensiones", (info.d.dimensiones || "") + (info.d.megapixeles ? "  ·  " + info.d.megapixeles : "")],
                        ["Tamaño", info.d.tamano || ""],
                        ["Formato", info.d.formato || ""],
                        ["Carpeta", info.d.carpeta || ""],
                        ["Álbumes", info.d.albumes || ""]
                    ]
                    Column {
                        required property var modelData
                        visible: modelData[1] !== ""
                        width: colInfo.width
                        spacing: 2
                        Text { text: modelData[0]; color: visor.theme.contentTextSecondary; font.pixelSize: 11; font.weight: Font.DemiBold }
                        Text { width: parent.width; text: modelData[1]; color: visor.theme.contentTextPrimary; font.pixelSize: 12; wrapMode: Text.WrapAnywhere }
                    }
                }

                Column {
                    visible: info.d.lat !== undefined
                    width: parent.width
                    spacing: 2
                    Text { text: "Ubicación"; color: visor.theme.contentTextSecondary; font.pixelSize: 11; font.weight: Font.DemiBold }
                    Text {
                        text: info.d.lat !== undefined ? info.d.lat.toFixed(5) + ", " + info.d.lon.toFixed(5) : ""
                        color: visor.theme.contentTextPrimary
                        font.pixelSize: 12
                    }
                    Text {
                        text: "Ver en el mapa ↗"
                        color: visor.theme.accent
                        font.pixelSize: 12
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally("https://www.openstreetmap.org/?mlat=" + info.d.lat + "&mlon=" + info.d.lon + "#map=15/" + info.d.lat + "/" + info.d.lon)
                        }
                    }
                }
            }
        }
    }
}
