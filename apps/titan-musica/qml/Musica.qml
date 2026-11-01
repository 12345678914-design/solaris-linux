import QtQuick 2.15
import QtQuick.Controls 2.15

TitanWindow {
    id: musicaWindow

    title: musicaBackend.isPlaying
           ? (musicaBackend.currentTrack.title + " — " + musicaBackend.currentTrack.artist + " • Música")
           : "Música"
    sidebarWidth: 195

    Shortcut {
        sequence: "Space"
        onActivated: musicaBackend.togglePlay()
    }
    Shortcut {
        sequence: "Ctrl+Left"
        onActivated: musicaBackend.previousTrack()
    }
    Shortcut {
        sequence: "Ctrl+Right"
        onActivated: musicaBackend.nextTrack()
    }
    Shortcut {
        sequence: "Ctrl+M"
        onActivated: musicaBackend.toggleMute()
    }
    Shortcut {
        sequence: "Ctrl+R"
        onActivated: musicaBackend.toggleRepeat()
    }
    Shortcut {
        sequence: "Ctrl+S"
        onActivated: musicaBackend.toggleShuffle()
    }

    // 1. TOOLBAR / PANEL SUPERIOR CON CONTROLES DE REPRODUCCIÓN (BLUR ACRÍLICO)
    headerContentData: Row {
        anchors.fill: parent
        spacing: 12

        // Botones de transporte (Anterior, Reproducir/Pausa, Siguiente)
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            // Pista anterior
            Rectangle {
                width: 28; height: 26; radius: 5
                color: prevTrackMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.12)
                Text { anchors.centerIn: parent; text: "⏮"; color: theme.headerText; font.pixelSize: 11 }
                MouseArea {
                    id: prevTrackMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: musicaBackend.previousTrack()
                }
            }

            // Reproducir / Pausa principal
            Rectangle {
                width: 34; height: 28; radius: 14
                color: playMouse.containsMouse ? theme.accentHover : theme.accent

                Text {
                    anchors.centerIn: parent
                    text: musicaBackend.isPlaying ? "❚❚" : "▶"
                    color: "#ffffff"
                    font.pixelSize: musicaBackend.isPlaying ? 10 : 12
                }

                MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: musicaBackend.togglePlay()
                }
            }

            // Pista siguiente
            Rectangle {
                width: 28; height: 26; radius: 5
                color: nextTrackMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.12)
                Text { anchors.centerIn: parent; text: "⏭"; color: theme.headerText; font.pixelSize: 11 }
                MouseArea {
                    id: nextTrackMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: musicaBackend.nextTrack()
                }
            }
        }

        // Barra central de reproducción (Now Playing + Scrubber)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(220, parent.width - 480)
            height: 38
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.22)
            border.color: Qt.rgba(1, 1, 1, 0.12)
            clip: true

            Column {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 4
                spacing: 2

                // Info de pista actual
                Item {
                    width: parent.width
                    height: 16

                    Row {
                        anchors.left: parent.left
                        anchors.right: durText.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Text {
                            text: musicaBackend.currentTrack.title ? musicaBackend.currentTrack.title : "TITAN Música"
                            color: theme.headerText
                            font.pixelSize: 11
                            font.bold: true
                            elide: Text.ElideRight
                            width: Math.min(parent.width - 90, 200)
                        }

                        Text {
                            text: "—"
                            color: Qt.rgba(1, 1, 1, 0.4)
                            font.pixelSize: 11
                            visible: musicaBackend.currentTrack.artist ? true : false
                        }

                        Text {
                            text: musicaBackend.currentTrack.artist ? musicaBackend.currentTrack.artist : ""
                            color: theme.contentTextSecondary
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            width: Math.min(parent.width - 160, 160)
                        }
                    }

                    Text {
                        id: durText
                        text: musicaBackend.duration > 0
                              ? (musicaBackend.positionText + " / " + musicaBackend.durationText)
                              : "--:--"
                        color: theme.contentTextSecondary
                        font.pixelSize: 9
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Scrubber interactivo
                Item {
                    width: parent.width
                    height: 14

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 3
                        radius: 1.5
                        color: Qt.rgba(1, 1, 1, 0.2)

                        Rectangle {
                            height: parent.height
                            radius: 1.5
                            color: theme.accent
                            width: (musicaBackend.duration > 0)
                                   ? Math.min(parent.width, parent.width * (musicaBackend.position / musicaBackend.duration))
                                   : 0
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (musicaBackend.duration > 0) {
                                var ratio = Math.max(0.0, Math.min(1.0, mouse.x / width))
                                musicaBackend.seek(ratio * musicaBackend.duration)
                            }
                        }
                    }
                }
            }
        }

        // Shuffle y Repeat
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Rectangle {
                width: 26; height: 26; radius: 5
                color: musicaBackend.isShuffle ? Qt.rgba(0, 0.44, 0.89, 0.35) : (shufMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent")
                border.color: musicaBackend.isShuffle ? theme.accent : "transparent"
                Text { anchors.centerIn: parent; text: "🔀"; font.pixelSize: 10; opacity: musicaBackend.isShuffle ? 1.0 : 0.6 }
                MouseArea {
                    id: shufMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: musicaBackend.toggleShuffle()
                }
            }

            Rectangle {
                width: 26; height: 26; radius: 5
                color: musicaBackend.isRepeat ? Qt.rgba(0, 0.44, 0.89, 0.35) : (repMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent")
                border.color: musicaBackend.isRepeat ? theme.accent : "transparent"
                Text { anchors.centerIn: parent; text: "🔁"; font.pixelSize: 10; opacity: musicaBackend.isRepeat ? 1.0 : 0.6 }
                MouseArea {
                    id: repMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: musicaBackend.toggleRepeat()
                }
            }
        }

        // Control de volumen
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: musicaBackend.isMuted || musicaBackend.volume === 0 ? "🔇" : (musicaBackend.volume > 0.5 ? "🔊" : "🔉")
                font.pixelSize: 12
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: musicaBackend.toggleMute()
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 60
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.2)

                Rectangle {
                    height: parent.height
                    radius: 2
                    color: theme.accent
                    width: musicaBackend.isMuted ? 0 : (parent.width * musicaBackend.volume)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var v = Math.max(0.0, Math.min(1.0, mouse.x / width))
                        musicaBackend.setVolume(v)
                    }
                }
            }
        }

        Item { width: 4; height: 1 }

        // Barra de búsqueda Spotlight
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 130; height: 28; radius: 6
            color: Qt.rgba(1, 1, 1, 0.12)
            border.color: searchMusicaInput.activeFocus ? theme.accent : Qt.rgba(1, 1, 1, 0.18)

            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "🔍"
                    font.pixelSize: 10
                    opacity: 0.7
                }

                TextField {
                    id: searchMusicaInput
                    width: parent.width - 32
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "Buscar..."
                    font.pixelSize: 11
                    color: theme.headerText
                    background: null
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)
                    text: musicaBackend.searchQuery
                    onTextChanged: musicaBackend.searchQuery = text
                }
            }
        }
    }

    // 2. SIDEBAR TRANSLÚCIDO
    sidebarContentData: Column {
        anchors.fill: parent
        anchors.topMargin: 12
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 4

        Text {
            text: "BIBLIOTECA"
            color: theme.sidebarTextMuted
            font.pixelSize: 10
            font.bold: true
            anchors.left: parent.left
            anchors.leftMargin: 8
        }

        Repeater {
            model: musicaBackend.categories
            delegate: Rectangle {
                width: parent.width
                height: 32
                radius: 6
                color: isSelected ? theme.selectionBg : (catMouse.containsMouse ? theme.itemHover : "transparent")

                readonly property bool isSelected: musicaBackend.currentCategory === modelData.id

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16; height: 16
                        source: modelData.icon
                        sourceSize.width: 16
                        sourceSize.height: 16
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: isSelected ? "#ffffff" : theme.sidebarText
                        font.pixelSize: 12
                        font.weight: isSelected ? Font.DemiBold : Font.Normal
                    }
                }

                MouseArea {
                    id: catMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: musicaBackend.selectCategory(modelData.id)
                }
            }
        }
    }

    // 3. CONTENIDO CENTRAL TRANSLÚCIDO (VIDRIO FROSTED)
    Rectangle {
        anchors.fill: parent
        color: theme.contentBackground

        // Cabecera de columnas de la lista de canciones
        Rectangle {
            id: listHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28
            color: Qt.rgba(0, 0, 0, 0.15)
            border.color: theme.contentCardBorder
            border.width: 1

            Row {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                Text { text: "#"; width: 28; color: theme.contentTextSecondary; font.pixelSize: 10; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "TÍTULO"; width: Math.max(160, parent.width - 480); color: theme.contentTextSecondary; font.pixelSize: 10; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "ARTISTA"; width: 140; color: theme.contentTextSecondary; font.pixelSize: 10; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "ÁLBUM"; width: 130; color: theme.contentTextSecondary; font.pixelSize: 10; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "FORMATO"; width: 60; color: theme.contentTextSecondary; font.pixelSize: 10; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            }
        }

        // Lista de canciones
        ListView {
            id: trackListView
            anchors.top: listHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            model: musicaBackend.tracks

            delegate: Rectangle {
                width: trackListView.width
                height: 36
                color: isCurrentTrack
                       ? theme.selectionBg
                       : (rowMouse.containsMouse ? theme.itemHover : (index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.02)))

                readonly property bool isCurrentTrack: musicaBackend.currentTrackIndex === index

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    // Número / Ecualizador animado
                    Item {
                        width: 28
                        height: parent.height
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            visible: !(isCurrentTrack && musicaBackend.isPlaying)
                            text: String(index + 1)
                            color: isCurrentTrack ? theme.accent : theme.contentTextSecondary
                            font.pixelSize: 11
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: isCurrentTrack && musicaBackend.isPlaying
                            text: "♫"
                            color: theme.accent
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }

                    // Título
                    Text {
                        width: Math.max(160, parent.width - 480)
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.title
                        color: isCurrentTrack ? theme.accent : theme.contentTextPrimary
                        font.pixelSize: 12
                        font.bold: isCurrentTrack
                        elide: Text.ElideRight
                    }

                    // Artista
                    Text {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.artist
                        color: theme.contentTextSecondary
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    // Álbum
                    Text {
                        width: 130
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.album
                        color: theme.contentTextSecondary
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    // Formato
                    Text {
                        width: 60
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.format
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.pixelSize: 10
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onDoubleClicked: musicaBackend.playTrack(index)
                    onClicked: {
                        if (mouse.button === Qt.RightButton) {
                            trackMenu.trackPath = modelData.path
                            trackMenu.trackIndex = index
                            trackMenu.popup()
                        } else {
                            musicaBackend.playTrack(index)
                        }
                    }
                }
            }
        }

        // Menú contextual para canciones
        Menu {
            id: trackMenu
            property string trackPath: ""
            property int trackIndex: -1

            Action {
                text: "Reproducir"
                onTriggered: musicaBackend.playTrack(trackMenu.trackIndex)
            }
            Action {
                text: "Mostrar en Finder"
                onTriggered: musicaBackend.openInFinder(trackMenu.trackPath)
            }
        }

        // Estado vacío
        Column {
            anchors.centerIn: parent
            spacing: 12
            visible: musicaBackend.tracks.length === 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "🎵"
                font.pixelSize: 48
                opacity: 0.6
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No se encontraron canciones en tu biblioteca"
                color: theme.contentTextSecondary
                font.pixelSize: 14
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Coloca archivos MP3, WAV, FLAC u OGG en la carpeta ~/Música"
                color: theme.contentTextSecondary
                font.pixelSize: 11
                opacity: 0.7
            }
        }
    }

    // 4. BARRA DE ESTADO INFERIOR
    statusBarContentData: Row {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: musicaBackend.statusText
            color: theme.contentTextSecondary
            font.pixelSize: 10
        }

        Item { width: 12; height: 1 }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: musicaBackend.currentTrack.format ? true : false
            text: "•  " + (musicaBackend.currentTrack.format ? musicaBackend.currentTrack.format : "") + "  •  " + (musicaBackend.currentTrack.size ? musicaBackend.currentTrack.size : "")
            color: theme.contentTextSecondary
            font.pixelSize: 10
        }

        Item { width: 10; height: 1 }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            visible: musicaBackend.currentTrack.path ? true : false
            spacing: 4

            Text {
                text: "Mostrar archivo en Finder"
                color: finderMusicaLink.containsMouse ? theme.accent : theme.contentTextSecondary
                font.pixelSize: 10
                font.underline: finderMusicaLink.containsMouse

                MouseArea {
                    id: finderMusicaLink
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: musicaBackend.openInFinder()
                }
            }
        }
    }
}

