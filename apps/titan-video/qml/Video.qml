import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Dialogs
import QtMultimedia

TitanWindow {
    id: videoWindow

    title: videoBackend.fileName + (videoBackend.playlistPosition !== "" ? "  ·  " + videoBackend.playlistPosition : "")
    width: 860
    height: 540
    minimumWidth: 480
    minimumHeight: 320
    sidebarWidth: 0

    property bool isFullscreen: visibility === Window.FullScreen
    property bool showControls: true

    function togglePlay() {
        if (mediaPlayer.playbackState === MediaPlayer.PlayingState) {
            mediaPlayer.pause();
        } else {
            mediaPlayer.play();
        }
    }

    // Velocidades de reproducción que recorre el botón "1×" y las teclas [ ]
    readonly property var speeds: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    function changeSpeed(step) {
        var i = speeds.indexOf(mediaPlayer.playbackRate)
        if (i < 0) i = 2
        i = Math.max(0, Math.min(speeds.length - 1, i + step))
        mediaPlayer.playbackRate = speeds[i]
        pingActivity()
    }
    function goNext() { if (videoBackend.playNext()) mediaPlayer.play() }
    function goPrevious() {
        // Como en cualquier reproductor: si ya llevas un rato, "anterior" vuelve al principio
        if (mediaPlayer.position > 3000 || !videoBackend.hasPrevious) mediaPlayer.position = 0
        else if (videoBackend.playPrevious()) mediaPlayer.play()
    }

    function toggleFullscreen() {
        if (isFullscreen) {
            videoWindow.showNormal();
        } else {
            videoWindow.showFullScreen();
        }
    }

    Timer {
        id: hideControlsTimer
        interval: 2500
        repeat: false
        onTriggered: {
            if (mediaPlayer.playbackState === MediaPlayer.PlayingState && !ctrlsHover.containsMouse) {
                videoWindow.showControls = false;
            }
        }
    }

    function pingActivity() {
        videoWindow.showControls = true;
        hideControlsTimer.restart();
    }

    FileDialog {
        id: openFileDialog
        title: "Seleccionar video"
        nameFilters: [
            "Archivos de video (*.mp4 *.mkv *.avi *.mov *.webm *.flv *.wmv)",
            "Todos los archivos (*)"
        ]
        onAccepted: {
            videoBackend.sourceUrl = selectedFile;
            mediaPlayer.play();
        }
    }

    headerContentData: Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 14
        spacing: 8
        visible: !videoWindow.isFullscreen

        // Botón Abrir Archivo en barra
        Rectangle {
            width: openText.implicitWidth + 18
            height: 24
            radius: 6
            color: openMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
            border.color: theme.glassBorder
            border.width: 1

            Text {
                id: openText
                anchors.centerIn: parent
                text: "Abrir..."
                color: theme.headerText
                font.pixelSize: 11
                font.weight: Font.Medium
            }

            MouseArea {
                id: openMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: openFileDialog.open()
            }
        }
    }

    Item {
        id: playerArea
        anchors.fill: parent
        focus: true

        // Multimedia
        MediaPlayer {
            id: mediaPlayer
            audioOutput: AudioOutput {
                id: audioOutput
                volume: 0.8
            }
            videoOutput: videoOutput
            source: videoBackend.sourceUrl
            // Al terminar, el siguiente vídeo de la carpeta (como una lista)
            onMediaStatusChanged: {
                if (mediaStatus === MediaPlayer.EndOfMedia && videoBackend.hasNext)
                    videoWindow.goNext()
            }

            Component.onCompleted: {
                if (videoBackend.sourceUrl.toString().length > 0) {
                    play();
                }
            }
        }

        VideoOutput {
            id: videoOutput
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectFit
        }

        // Pantalla de bienvenida si no hay video cargado
        Rectangle {
            anchors.fill: parent
            visible: videoBackend.sourceUrl.toString().length === 0
            color: theme.isDark ? "#141416" : "#f0f0f5"

            Column {
                anchors.centerIn: parent
                spacing: 16

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: "qrc:/icons/video.png"
                    width: 72
                    height: 72
                    smooth: true
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Reproductor de Video Titan"
                    color: theme.headerText
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Arrastra un archivo de video aquí o selecciona uno"
                    color: theme.isDark ? "#888888" : "#666666"
                    font.pixelSize: 12
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 130
                    height: 32
                    radius: 7
                    color: theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "Abrir archivo"
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: openFileDialog.open()
                    }
                }
            }
        }

        // DropArea para arrastrar y soltar videos
        DropArea {
            anchors.fill: parent
            onEntered: {
                dropOverlay.visible = true;
            }
            onExited: {
                dropOverlay.visible = false;
            }
            onDropped: function(drop) {
                dropOverlay.visible = false;
                if (drop.hasUrls && drop.urls.length > 0) {
                    videoBackend.sourceUrl = drop.urls[0];
                    mediaPlayer.play();
                    drop.acceptProposedAction();
                }
            }
        }

        // Indicador visual al arrastrar archivo encima
        Rectangle {
            id: dropOverlay
            anchors.fill: parent
            visible: false
            color: Qt.rgba(0.2, 0.5, 1.0, 0.25)
            border.color: theme.accent
            border.width: 3

            Text {
                anchors.centerIn: parent
                text: "Soltar video para reproducir"
                color: "#ffffff"
                font.pixelSize: 18
                font.bold: true
            }
        }

        // MouseArea sobre el video para detectar clics y movimientos
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: videoWindow.showControls ? Qt.ArrowCursor : Qt.BlankCursor
            onPositionChanged: videoWindow.pingActivity()
            onClicked: {
                videoWindow.pingActivity();
            }
            onDoubleClicked: {
                videoWindow.toggleFullscreen();
            }
        }

        // Barra de Controles Flotante Estilo QuickTime
        Rectangle {
            id: floatingControls
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - 48, 640)
            height: 52
            radius: 12
            visible: videoWindow.showControls && videoBackend.sourceUrl.toString().length > 0
            opacity: visible ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation { duration: 250 }
            }

            color: theme.isDark ? Qt.rgba(0.12, 0.12, 0.14, 0.88) : Qt.rgba(0.96, 0.96, 0.98, 0.88)
            border.color: theme.glassBorder
            border.width: 1

            MouseArea {
                id: ctrlsHover
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: videoWindow.pingActivity()
            }

            Row {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                // Botón anterior (o volver al principio)
                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: videoBackend.sourceUrl.toString().length > 0 ? 1.0 : 0.35
                    color: prevMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "⏮"
                        color: theme.headerText
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: prevMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: videoBackend.sourceUrl.toString().length > 0
                        cursorShape: Qt.PointingHandCursor
                        onClicked: videoWindow.goPrevious()
                    }
                }

                // Botón Play / Pause
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: ppMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)

                    Text {
                        anchors.centerIn: parent
                        text: mediaPlayer.playbackState === MediaPlayer.PlayingState ? "⏸" : "▶"
                        color: theme.headerText
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: ppMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: videoWindow.togglePlay()
                    }
                }

                // Botón siguiente vídeo de la carpeta
                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: videoBackend.hasNext ? 1.0 : 0.35
                    color: nextMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "⏭"
                        color: theme.headerText
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: nextMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: videoBackend.hasNext
                        cursorShape: Qt.PointingHandCursor
                        onClicked: videoWindow.goNext()
                    }
                }

                // Tiempo transcurrido
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: videoBackend.formatTime(mediaPlayer.position)
                    color: theme.isDark ? "#aaaaaa" : "#555555"
                    font.pixelSize: 11
                    font.family: "Monospace"
                }

                // Slider de posición
                Slider {
                    id: posSlider
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 470
                    from: 0
                    to: mediaPlayer.duration > 0 ? mediaPlayer.duration : 1
                    value: mediaPlayer.position
                    onMoved: {
                        mediaPlayer.position = value;
                        videoWindow.pingActivity();
                    }
                }

                // Tiempo total
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: videoBackend.formatTime(mediaPlayer.duration)
                    color: theme.isDark ? "#aaaaaa" : "#555555"
                    font.pixelSize: 11
                    font.family: "Monospace"
                }

                // Botón Silencio / Audio
                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: muteMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: audioOutput.muted ? "🔇" : (audioOutput.volume > 0.5 ? "🔊" : "🔉")
                        color: theme.headerText
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: muteMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: audioOutput.muted = !audioOutput.muted
                    }
                }

                // Slider de Volumen
                Slider {
                    id: volSlider
                    anchors.verticalCenter: parent.verticalCenter
                    width: 70
                    from: 0.0
                    to: 1.0
                    value: audioOutput.volume
                    onMoved: {
                        audioOutput.volume = value;
                        audioOutput.muted = false;
                        videoWindow.pingActivity();
                    }
                }

                // Velocidad de reproducción (clic: siguiente velocidad)
                Rectangle {
                    width: 38
                    height: 22
                    radius: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: speedMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.06)
                    Text {
                        anchors.centerIn: parent
                        text: mediaPlayer.playbackRate + "×"
                        color: theme.headerText
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: speedMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var i = videoWindow.speeds.indexOf(mediaPlayer.playbackRate)
                            mediaPlayer.playbackRate = videoWindow.speeds[(i + 1) % videoWindow.speeds.length]
                        }
                    }
                }

                // Botón Pantalla Completa
                Rectangle {
                    width: 26
                    height: 26
                    radius: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: fsMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: videoWindow.isFullscreen ? "⤓" : "⤢"
                        color: theme.headerText
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: fsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: videoWindow.toggleFullscreen()
                    }
                }
            }
        }

        // Manejador de teclas de atajo
        Keys.onSpacePressed: videoWindow.togglePlay()
        Keys.onLeftPressed: {
            mediaPlayer.position = Math.max(0, mediaPlayer.position - 5000);
            videoWindow.pingActivity();
        }
        Keys.onRightPressed: {
            mediaPlayer.position = Math.min(mediaPlayer.duration, mediaPlayer.position + 5000);
            videoWindow.pingActivity();
        }
        Keys.onUpPressed: {
            audioOutput.volume = Math.min(1.0, audioOutput.volume + 0.1);
            videoWindow.pingActivity();
        }
        Keys.onDownPressed: {
            audioOutput.volume = Math.max(0.0, audioOutput.volume - 0.1);
            videoWindow.pingActivity();
        }
        Keys.onEscapePressed: {
            if (videoWindow.isFullscreen) {
                videoWindow.showNormal();
            }
        }
        // F pantalla completa, M silencio, N/P siguiente/anterior, [ ] velocidad,
        // Inicio volver a empezar, 0-9 saltar al 0%-90%, Ctrl+O abrir
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_O && (event.modifiers & Qt.ControlModifier)) openFileDialog.open()
            else if (event.key === Qt.Key_F) videoWindow.toggleFullscreen()
            else if (event.key === Qt.Key_M) audioOutput.muted = !audioOutput.muted
            else if (event.key === Qt.Key_N) videoWindow.goNext()
            else if (event.key === Qt.Key_P) videoWindow.goPrevious()
            else if (event.key === Qt.Key_BracketLeft) videoWindow.changeSpeed(-1)
            else if (event.key === Qt.Key_BracketRight) videoWindow.changeSpeed(1)
            else if (event.key === Qt.Key_Home) mediaPlayer.position = 0
            else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9 && mediaPlayer.duration > 0)
                mediaPlayer.position = mediaPlayer.duration * (event.key - Qt.Key_0) / 10
            else return
            event.accepted = true
            videoWindow.pingActivity()
        }
    }
}

