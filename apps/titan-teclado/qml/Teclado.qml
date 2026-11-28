// Inti OS - teclado en pantalla (distribución española).
//
// Cada tecla es {t: lo que se ve, s: texto que escribe, k: tecla XKB que
// pulsa, w: ancho en unidades, f: función especial}. Mayúsculas de una vez
// (dos toques = bloqueo), Ctrl y Alt de una vez, página de números y
// símbolos con las vocales acentuadas y ¿ ¡.
import QtQuick
import QtQuick.Window

Window {
    id: ventana
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
    width: Screen.width > 0 ? Screen.width : 1280
    height: 280
    title: "Teclado en pantalla"

    TitanTheme { id: tema }

    property bool simbolos: false
    property bool mayus: false
    property bool bloqueoMayus: false
    property bool ctrl: false
    property bool alt: false
    property real ultimoMayus: 0

    function modificadores() {
        var m = []
        if (ctrl) m.push("ctrl")
        if (alt) m.push("alt")
        return m
    }
    function soltarModificadores() {
        ctrl = false
        alt = false
        if (!bloqueoMayus) mayus = false
    }

    function pulsar(d) {
        if (d.f === "mayus") {
            var ahora = Date.now()
            if (mayus && ahora - ultimoMayus < 400) { bloqueoMayus = true }
            else if (bloqueoMayus) { bloqueoMayus = false; mayus = false }
            else mayus = !mayus
            ultimoMayus = ahora
            return
        }
        if (d.f === "pagina") { simbolos = !simbolos; return }
        if (d.f === "ctrl") { ctrl = !ctrl; return }
        if (d.f === "alt") { alt = !alt; return }
        if (d.f === "ocultar") { teclado.salir(); return }
        if (d.k) {
            teclado.tecla(d.k, modificadores())
        } else {
            var s = d.s !== undefined ? d.s : d.t
            if (mayus && !simbolos) s = s.toUpperCase()
            // Con Ctrl/Alt va la letra en minúscula (Ctrl+C, no Ctrl+Mayús+C)
            if (ctrl || alt) s = s.toLowerCase()
            teclado.texto(s, modificadores())
        }
        // Las flechas y el borrado no gastan las mayúsculas de una vez
        if (!d.k || ctrl || alt) soltarModificadores()
    }

    readonly property var letras: [
        [{t:"q"},{t:"w"},{t:"e"},{t:"r"},{t:"t"},{t:"y"},{t:"u"},{t:"i"},{t:"o"},{t:"p"},{t:"⌫",k:"BackSpace",w:1.5,esp:true}],
        [{t:"a",w:1},{t:"s"},{t:"d"},{t:"f"},{t:"g"},{t:"h"},{t:"j"},{t:"k"},{t:"l"},{t:"ñ"},{t:"⏎",k:"Return",w:1.5,esp:true}],
        [{t:"⇧",f:"mayus",w:1.5,esp:true},{t:"z"},{t:"x"},{t:"c"},{t:"v"},{t:"b"},{t:"n"},{t:"m"},{t:","},{t:"."},{t:"-"}],
        [{t:"?123",f:"pagina",w:1.5,esp:true},{t:"Ctrl",f:"ctrl",w:1.2,esp:true},{t:"Alt",f:"alt",w:1.2,esp:true},
         {t:"",s:" ",w:3.6,espacio:true},{t:"←",k:"Left",esp:true},{t:"↓",k:"Down",esp:true},{t:"↑",k:"Up",esp:true},{t:"→",k:"Right",esp:true}]
    ]
    readonly property var numeros: [
        [{t:"1"},{t:"2"},{t:"3"},{t:"4"},{t:"5"},{t:"6"},{t:"7"},{t:"8"},{t:"9"},{t:"0"},{t:"⌫",k:"BackSpace",w:1.5,esp:true}],
        [{t:"@"},{t:"#"},{t:"€"},{t:"%"},{t:"&"},{t:"*"},{t:"+"},{t:"="},{t:"("},{t:")"},{t:"⏎",k:"Return",w:1.5,esp:true}],
        [{t:"Tab",k:"Tab",w:1.5,esp:true},{t:"á"},{t:"é"},{t:"í"},{t:"ó"},{t:"ú"},{t:"ü"},{t:"¿"},{t:"?"},{t:"¡"},{t:"!"}],
        [{t:"ABC",f:"pagina",w:1.5,esp:true},{t:"Esc",k:"Escape",w:1.2,esp:true},{t:"/"},{t:"\""},{t:"'"},{t:":"},{t:"_"},
         {t:"",s:" ",w:1.8,espacio:true},{t:"←",k:"Left",esp:true},{t:"→",k:"Right",esp:true}]
    ]
    readonly property var filas: simbolos ? numeros : letras

    Rectangle {
        anchors.fill: parent
        color: tema.isDark ? Qt.rgba(0.10, 0.11, 0.15, 0.97) : Qt.rgba(0.86, 0.87, 0.90, 0.97)
        Rectangle { width: parent.width; height: 1; color: tema.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.12) }

        // Asa para cerrar
        Rectangle {
            id: cerrar
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            width: 30; height: 22; radius: 6
            color: zonaCerrar.containsMouse ? tema.itemHover : "transparent"
            Text { anchors.centerIn: parent; text: "⌄"; font.pixelSize: 16; color: tema.contentTextSecondary }
            MouseArea { id: zonaCerrar; anchors.fill: parent; hoverEnabled: true; onClicked: teclado.salir() }
        }

        Column {
            id: rejilla
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 30
            anchors.bottomMargin: 8
            spacing: 6
            readonly property real altoFila: (height - spacing * 3) / 4

            Repeater {
                model: ventana.filas
                delegate: Row {
                    id: fila
                    required property var modelData
                    readonly property real unidades: {
                        var u = 0
                        for (var i = 0; i < modelData.length; ++i) u += modelData[i].w || 1
                        return u
                    }
                    spacing: 6
                    readonly property real unidad: (rejilla.width - spacing * (modelData.length - 1)) / 11.5
                    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
                    Repeater {
                        model: fila.modelData
                        delegate: Rectangle {
                            id: boton
                            required property var modelData
                            readonly property bool activa: (modelData.f === "mayus" && ventana.mayus)
                                                           || (modelData.f === "ctrl" && ventana.ctrl)
                                                           || (modelData.f === "alt" && ventana.alt)
                            width: fila.unidad * (modelData.w || 1)
                            height: rejilla.altoFila
                            radius: 7
                            color: zona.pressed ? tema.accent
                                 : activa ? Qt.rgba(tema.accent.r, tema.accent.g, tema.accent.b, 0.55)
                                 : modelData.esp ? (tema.isDark ? "#2a2c33" : "#c3c6cf")
                                 : (tema.isDark ? "#3a3c45" : "#ffffff")
                            border.color: tema.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.08)
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    var t = boton.modelData.t
                                    if (boton.modelData.f === "mayus" && ventana.bloqueoMayus) return "⇪"
                                    return (ventana.mayus && !ventana.simbolos && !boton.modelData.esp) ? t.toUpperCase() : t
                                }
                                color: zona.pressed || boton.activa ? "#ffffff" : tema.contentTextPrimary
                                font.pixelSize: boton.modelData.esp ? Math.min(15, boton.height * 0.32) : Math.min(22, boton.height * 0.42)
                            }
                            MouseArea {
                                id: zona
                                anchors.fill: parent
                                onClicked: ventana.pulsar(boton.modelData)
                                // Borrar y flechas se repiten al mantener
                                onPressAndHold: if (boton.modelData.k && boton.modelData.k !== "Return") repetir.start()
                                onReleased: repetir.stop()
                                onCanceled: repetir.stop()
                                Timer {
                                    id: repetir
                                    interval: 70
                                    repeat: true
                                    onTriggered: teclado.tecla(boton.modelData.k, ventana.modificadores())
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
