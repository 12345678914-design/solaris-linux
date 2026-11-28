import QtQuick
import QtQuick.Controls

// Una canción en la lista. `columnas` trae los anchos que calcula la vista.
Rectangle {
    id: fila
    property var cancion: ({})
    property int numero: 0
    property var columnas: ({})
    property bool enAlbum: false
    property var tema
    readonly property bool esActual: musicaBackend.actual.ruta === cancion.ruta
    readonly property bool favorita: { musicaBackend.datosVersion; return musicaBackend.esFavorita(cancion.ruta) }
    signal reproducir()
    signal menu(real x, real y)

    height: 44
    radius: 8
    color: zona.containsMouse ? tema.itemHover : "transparent"

    Row {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        // Número, carátula o ecualizador
        Item {
            width: fila.columnas.num
            height: parent.height

            Text {
                anchors.centerIn: parent
                visible: fila.enAlbum && !fila.esActual
                text: fila.cancion.numero > 0 ? fila.cancion.numero : fila.numero
                color: fila.tema.contentTextSecondary
                font.pixelSize: 12
            }
            Portada {
                anchors.centerIn: parent
                width: 34; height: 34; radio: 5
                visible: !fila.enAlbum
                fuente: fila.cancion.portada || ""
                semilla: fila.cancion.album || ""
            }
            // Ecualizador animado sobre la actual
            Row {
                anchors.centerIn: parent
                spacing: 2
                visible: fila.esActual
                Repeater {
                    model: 3
                    Rectangle {
                        width: 3
                        radius: 1.5
                        anchors.bottom: parent.bottom
                        color: fila.enAlbum ? fila.tema.accent : "#ffffff"
                        height: 4
                        SequentialAnimation on height {
                            running: fila.esActual && musicaBackend.reproduciendo
                            loops: Animation.Infinite
                            NumberAnimation { to: 6 + index * 3; duration: 260 + index * 70 }
                            NumberAnimation { to: 4 + (2 - index) * 2; duration: 220 + index * 60 }
                        }
                    }
                }
                height: 14
            }
            Rectangle {
                anchors.centerIn: parent
                width: 34; height: 34; radius: 5
                color: Qt.rgba(0, 0, 0, 0.45)
                visible: fila.esActual && !fila.enAlbum
                z: -1
            }
        }

        Column {
            width: fila.columnas.titulo
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: fila.cancion.titulo || ""
                color: fila.esActual ? fila.tema.accent : fila.tema.contentTextPrimary
                font.pixelSize: 13
                font.weight: fila.esActual ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: fila.columnas.artista === 0
                text: fila.cancion.artista || ""
                color: fila.tema.contentTextSecondary
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
        Text {
            width: fila.columnas.artista
            visible: width > 0
            anchors.verticalCenter: parent.verticalCenter
            text: fila.cancion.artista || ""
            color: fila.tema.contentTextSecondary
            font.pixelSize: 12
            elide: Text.ElideRight
        }
        Text {
            width: fila.columnas.album
            visible: width > 0
            anchors.verticalCenter: parent.verticalCenter
            text: fila.cancion.album || ""
            color: fila.tema.contentTextSecondary
            font.pixelSize: 12
            elide: Text.ElideRight
        }
        Text {
            width: fila.columnas.fav
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: fila.favorita ? "♥" : "♡"
            color: fila.favorita ? "#ff2d55" : fila.tema.contentTextSecondary
            font.pixelSize: 15
            opacity: fila.favorita || zona.containsMouse ? 1 : 0
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: musicaBackend.alternarFavorita(fila.cancion.ruta)
            }
        }
        Text {
            width: fila.columnas.dur
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: fila.cancion.duracionTexto || ""
            color: fila.tema.contentTextSecondary
            font.pixelSize: 12
            font.features: { "tnum": 1 }
        }
        Text {
            width: fila.columnas.mas
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: "•••"
            color: fila.tema.contentTextSecondary
            font.pixelSize: 11
            opacity: zona.containsMouse ? 1 : 0
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: (e) => { var p = mapToItem(fila, e.x, e.y); fila.menu(p.x, p.y) }
            }
        }
    }

    // Arrastrar a una lista de la barra lateral
    Drag.active: zona.drag.active
    Drag.keys: ["text/x-titan-ruta"]
    Drag.mimeData: { "text/x-titan-ruta": cancion.ruta || "" }
    Drag.dragType: Drag.Automatic
    Item { id: fantasma }

    MouseArea {
        id: zona
        anchors.fill: parent
        hoverEnabled: true
        drag.target: fantasma
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        z: -1
        onDoubleClicked: (e) => { if (e.button === Qt.LeftButton) fila.reproducir() }
        onClicked: (e) => { if (e.button === Qt.RightButton) fila.menu(e.x, e.y) }
    }
}
