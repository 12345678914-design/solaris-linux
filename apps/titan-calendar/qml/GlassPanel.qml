import QtQuick
import QtQuick.Effects   // MultiEffect (Qt 6.5+), solo para recortar esquinas

// Panel de vidrio que refleja el fondo de pantalla ACTUAL.
//
// Técnica barata: el wallpaper se decodifica a un tamaño minúsculo (48×27 px) y se amplía.
// El suavizado de la ampliación hace de desenfoque, sin blur en vivo ni archivos pre-procesados.
// La capa recortada con esquinas redondeadas es estática: solo se redibuja si cambia el fondo.
Item {
    id: gp

    // ---------- Apariencia ----------
    property real radius: 18
    property color tint: "#40ffffff"
    property bool dark: true
    property bool showBorder: true
    property bool showHighlight: true
    property color borderColor: Qt.rgba(1, 1, 1, 0.35)
    property color highlightColor: Qt.rgba(1, 1, 1, 0.5)

    // Borde "Liquid Glass": en vez de un trazo uniforme, la luz entra por arriba,
    // casi desaparece en los lados y rebota débil abajo. Necesita shaders
    // (MultiEffect): con effects=false (backend por software) se usa el borde simple.
    property bool effects: true
    property bool liquid: true
    readonly property bool _liquidRim: effects && liquid && showBorder

    // ---------- Fondo ----------
    property string wallpaper: ""          // ruta o URL del fondo actual (sin pre-desenfocar)
    property size blurSize: Qt.size(48, 27) // más grande = menos borroso (prueba 64×36 si ves bloques)

    // Alineación con la pantalla: recorta la zona del fondo que hay "detrás" del panel.
    // aligned: false = el fondo se ajusta al propio panel (útil si no conoces su posición).
    property bool aligned: true
    property real originX: 0
    property real originY: 0
    property real sceneWidth: 0
    property real sceneHeight: 0

    // Sin efectos (backend por software) no se puede recortar el fondo con
    // esquinas redondeadas: el panel se queda en el tinte plano.
    readonly property bool active: wallpaper !== "" && effects

    // ---------- Fondo con fundido al cambiar ----------
    property bool _flip: false

    function toUrl(p) {
        if (!p) return ""
        var s = p.toString()
        if (s.indexOf("://") !== -1 || s.indexOf("qrc:") === 0) return s
        if (s.charAt(0) === "/") return "file://" + s
        return s
    }

    function _swap() {
        var u = toUrl(wallpaper)
        if (_flip) imgA.source = u
        else imgB.source = u
        _flip = !_flip
    }

    onWallpaperChanged: if (wallpaper !== "") _swap()

    Component.onCompleted: {
        if (wallpaper !== "" && imgA.source.toString() === "" && imgB.source.toString() === "")
            imgA.source = toUrl(wallpaper)
    }

    // ---------- Contenido recortado ----------
    Item {
        anchors.fill: parent
        layer.enabled: gp.active
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: gpMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Image {
            id: imgA
            visible: gp.active
            x: (gp.aligned && gp.sceneWidth > 0) ? -gp.originX : 0
            y: (gp.aligned && gp.sceneHeight > 0) ? -gp.originY : 0
            width: (gp.aligned && gp.sceneWidth > 0) ? gp.sceneWidth : gp.width
            height: (gp.aligned && gp.sceneHeight > 0) ? gp.sceneHeight : gp.height
            sourceSize: gp.blurSize
            fillMode: Image.PreserveAspectCrop
            smooth: true
            cache: true
            asynchronous: true
            opacity: gp._flip ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.InOutQuad } }
        }

        Image {
            id: imgB
            visible: gp.active
            x: (gp.aligned && gp.sceneWidth > 0) ? -gp.originX : 0
            y: (gp.aligned && gp.sceneHeight > 0) ? -gp.originY : 0
            width: (gp.aligned && gp.sceneWidth > 0) ? gp.sceneWidth : gp.width
            height: (gp.aligned && gp.sceneHeight > 0) ? gp.sceneHeight : gp.height
            sourceSize: gp.blurSize
            fillMode: Image.PreserveAspectCrop
            smooth: true
            cache: true
            asynchronous: true
            opacity: gp._flip ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.InOutQuad } }
        }

        // Tinte
        Rectangle { anchors.fill: parent; radius: gp.radius; color: gp.tint }

        // Luz suave en la parte superior
        Rectangle {
            anchors.fill: parent
            radius: gp.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, gp.dark ? 0.10 : 0.30) }
                GradientStop { position: 0.3; color: Qt.rgba(1, 1, 1, gp.dark ? 0.02 : 0.06) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, gp.dark ? 0.14 : 0.04) }
            }
        }
    }

    // Máscara de esquinas redondeadas
    Rectangle {
        id: gpMask
        anchors.fill: parent
        radius: gp.radius
        visible: false
        layer.enabled: true
    }

    // Borde fino (sin efectos, o con liquid=false)
    Rectangle {
        anchors.fill: parent
        radius: gp.radius
        color: "transparent"
        visible: gp.showBorder && !gp._liquidRim
        border.color: gp.borderColor
        border.width: 1
    }

    // Borde especular Liquid Glass: un degradado recortado a un anillo de 1 px
    // (máscara invertida con el hueco interior). Es una capa estática: solo se
    // vuelve a dibujar si cambia el tamaño.
    Item {
        anchors.fill: parent
        visible: gp._liquidRim
        layer.enabled: gp._liquidRim
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: rimHole
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
        Rectangle {
            anchors.fill: parent
            radius: gp.radius
            gradient: Gradient {
                GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, gp.dark ? 0.42 : 0.85) }
                GradientStop { position: 0.18; color: Qt.rgba(1, 1, 1, gp.dark ? 0.14 : 0.40) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, gp.dark ? 0.05 : 0.18) }
                GradientStop { position: 1.0;  color: Qt.rgba(1, 1, 1, gp.dark ? 0.20 : 0.45) }
            }
        }
    }
    // Hueco del anillo: mismo tamaño que el panel (MultiEffect escala la máscara
    // al tamaño de la fuente), con el rectángulo interior 1 px más pequeño.
    Item {
        id: rimHole
        anchors.fill: parent
        visible: false
        layer.enabled: gp._liquidRim
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, gp.radius - 1)
        }
    }

    // Reflejo especular superior (solo sin el borde Liquid Glass, que ya lo lleva)
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(0, parent.width - gp.radius * 1.6)
        height: 1
        radius: 1
        visible: gp.showHighlight && !gp._liquidRim
        color: gp.highlightColor
    }
}
