// Pantalla de bloqueo: música y notificaciones, como Android.
//
// Arriba la tarjeta de lo que suena (con anterior / pausa / siguiente) y
// debajo las notificaciones. Si no caben hasta la foto del perfil, se
// acoplan en una fila de iconos de las apps. Solo son de quien bloqueó:
// LockScreen las oculta al cambiar de usuario, y titan-shell solo pasa lo que
// permite Ajustes > Notificaciones > En la pantalla de bloqueo.
import QtQuick

Item {
    id: avisos
    // Alto libre entre el reloj y el perfil (lo da LockScreen)
    property real alturaDisponible: 300
    property bool oculto: false

    width: 380
    height: columna.implicitHeight
    opacity: oculto ? 0 : 1
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 180 } }

    readonly property bool hayMpris: typeof mpris !== "undefined" && mpris !== null
    readonly property bool musica: hayMpris && mpris.disponible
    readonly property var lista: shellBackend.avisosBloqueo
    readonly property int altoTarjeta: 66
    readonly property int hueco: 8
    readonly property real altoMusica: musica ? 104 + hueco : 0
    readonly property real altoLista: lista.length * (altoTarjeta + hueco)
    readonly property int altoFila: 44 + hueco
    // Si llegan hasta el perfil, las que no caben se acoplan en una fila de
    // iconos (como la repisa de Android): se ven enteras las más recientes.
    readonly property int tarjetasQueCaben: {
        if (altoMusica + altoLista <= alturaDisponible) return lista.length
        var n = Math.floor((alturaDisponible - altoMusica - altoFila + hueco) / (altoTarjeta + hueco))
        return Math.max(0, Math.min(lista.length, n))
    }
    readonly property var tarjetas: lista.slice(0, tarjetasQueCaben)
    readonly property bool enIconos: tarjetasQueCaben < lista.length

    // Las acopladas: una entrada por app (la más reciente primero)
    readonly property var apps: {
        var vistas = {}, r = []
        for (var i = tarjetasQueCaben; i < lista.length; ++i) {
            var a = lista[i].appName
            if (vistas[a]) { vistas[a].n++; continue }
            vistas[a] = { app: a, icono: lista[i].icon, n: 1 }
            r.push(vistas[a])
        }
        return r
    }

    component Cristal: Rectangle {
        radius: 18
        color: Qt.rgba(0.07, 0.08, 0.11, 0.48)
        border.color: Qt.rgba(1, 1, 1, 0.16)
        border.width: 1
    }

    Column {
        id: columna
        width: parent.width
        spacing: avisos.hueco

        // ── Música ───────────────────────────────────────────────────────
        Cristal {
            width: parent.width
            height: 104
            visible: avisos.musica

            Caratula {
                id: caratula
                width: 76; height: 76; radio: 12
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                fuente: avisos.hayMpris ? mpris.caratula : ""
            }
            Column {
                anchors.left: caratula.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.top: caratula.top
                spacing: 1
                Text {
                    text: avisos.hayMpris ? mpris.reproductor : ""
                    color: Qt.rgba(1, 1, 1, 0.65)
                    font.pixelSize: 10
                    font.weight: Font.Medium
                }
                Text {
                    width: parent.width
                    text: avisos.hayMpris ? mpris.titulo : ""
                    color: "#ffffff"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: avisos.hayMpris ? mpris.artista : ""
                    color: Qt.rgba(1, 1, 1, 0.70)
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
            Row {
                anchors.left: caratula.right
                anchors.leftMargin: 6
                anchors.bottom: caratula.bottom
                spacing: 4
                BotonMedio {
                    tipo: "anterior"
                    activo: avisos.hayMpris && mpris.puedeAnterior
                    onPulsado: mpris.anterior()
                }
                BotonMedio {
                    tipo: avisos.hayMpris && mpris.reproduciendo ? "pausa" : "play"
                    grande: true
                    onPulsado: mpris.alternar()
                }
                BotonMedio {
                    tipo: "siguiente"
                    activo: avisos.hayMpris && mpris.puedeSiguiente
                    onPulsado: mpris.siguiente()
                }
            }
        }

        // ── Notificaciones completas ─────────────────────────────────────
        Repeater {
            model: avisos.tarjetas
            delegate: Cristal {
                id: tarjeta
                required property var modelData
                width: columna.width
                height: avisos.altoTarjeta

                Image {
                    id: icono
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32; height: 32
                    source: tarjeta.modelData.icon ? tarjeta.modelData.icon : "qrc:/icons/system.png"
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                Column {
                    anchors.left: icono.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Item {
                        width: parent.width
                        height: appTexto.implicitHeight
                        Text {
                            id: appTexto
                            anchors.left: parent.left
                            anchors.right: horaTexto.left
                            anchors.rightMargin: 8
                            text: tarjeta.modelData.appName
                            color: Qt.rgba(1, 1, 1, 0.65)
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            id: horaTexto
                            anchors.right: parent.right
                            text: tarjeta.modelData.time
                            color: Qt.rgba(1, 1, 1, 0.55)
                            font.pixelSize: 11
                        }
                    }
                    Text {
                        width: parent.width
                        text: tarjeta.modelData.title
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: text.length > 0
                        text: tarjeta.modelData.message
                        color: Qt.rgba(1, 1, 1, 0.80)
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        textFormat: Text.PlainText
                    }
                }
            }
        }

        // ── Acopladas en iconos ──────────────────────────────────────────
        Cristal {
            visible: avisos.enIconos
            anchors.horizontalCenter: parent.horizontalCenter
            height: 44
            radius: 22
            width: filaIconos.implicitWidth + 28
            Row {
                id: filaIconos
                anchors.centerIn: parent
                spacing: 10
                Repeater {
                    model: avisos.apps.slice(0, 8)
                    delegate: Item {
                        required property var modelData
                        width: 26; height: 26
                        Image {
                            anchors.fill: parent
                            source: parent.modelData.icono ? parent.modelData.icono : "qrc:/icons/system.png"
                            sourceSize: Qt.size(52, 52)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        // Varias de la misma app: un número pequeño
                        Rectangle {
                            visible: parent.modelData.n > 1
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: -4
                            width: Math.max(15, cuenta.implicitWidth + 6); height: 15; radius: 7.5
                            color: "#ffffff"
                            Text {
                                id: cuenta
                                anchors.centerIn: parent
                                text: parent.parent.modelData.n
                                color: "#111111"
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: avisos.apps.length > 8
                    text: "+" + (avisos.apps.length - 8)
                    color: "#ffffff"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
