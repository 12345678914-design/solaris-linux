import QtQuick 2.15
import QtQuick.Window 2.15

Item {
    id: root
    width: Screen.width
    height: Screen.height

    // Etapas enviadas por ksplashqml durante el inicio de KDE:
    // 0 = Inicial / kernel
    // 1 = Servicios esenciales de sistema
    // 2 = Gestor de ventanas KWin
    // 3 = Espacio de trabajo Plasma y paneles
    // 4 = Completado / entrada al escritorio
    property int stage: 0

    onStageChanged: {
        if (stage >= 1 && stage <= 4) {
            progressAnim.to = Math.min(1.0, stage / 4.0)
            progressAnim.restart()
        }
    }

    Rectangle {
        id: background
        anchors.fill: parent
        color: "#0b0d13"

        // Brillo radial muy sutil detrás del logo
        Rectangle {
            anchors.centerIn: parent
            width: 320
            height: 320
            radius: 160
            color: Qt.rgba(0.2, 0.4, 0.8, 0.04)
        }

        Column {
            anchors.centerIn: parent
            spacing: 28
            horizontalAlignment: Text.AlignHCenter

            // Logo de Inti OS
            Image {
                id: logo
                source: "images/logo.png"
                width: 136
                height: 136
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0.0

                NumberAnimation on opacity {
                    from: 0.0
                    to: 1.0
                    duration: 500
                    easing.type: Easing.OutCubic
                }
            }

            // Barra de progreso minimalista estilo macOS
            Rectangle {
                id: progressTrack
                width: 170
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.16)
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    id: progressBar
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    radius: 2
                    color: "#FFFFFF"
                    width: Math.max(8, progressTrack.width * progressRatio)

                    property real progressRatio: 0.12

                    NumberAnimation on progressRatio {
                        id: progressAnim
                        duration: 350
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // Texto sutil de estado
            Text {
                id: statusText
                text: {
                    if (root.stage <= 1) return "Iniciando sistema..."
                    if (root.stage === 2) return "Cargando entorno gráfico..."
                    if (root.stage === 3) return "Preparando escritorio..."
                    return "Bienvenido a Inti OS"
                }
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 11
                font.weight: Font.Normal
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}

