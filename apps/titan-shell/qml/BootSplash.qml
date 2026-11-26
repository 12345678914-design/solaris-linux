import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: bootSplashRoot
    anchors.fill: parent

    // Fondo negro azabache puro
    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    Item {
        id: centerContainer
        anchors.centerIn: parent
        width: 600
        height: 170

        // 1. LOGO INTI OS
        Image {
            id: splashLogo
            width: 150
            height: 150
            anchors.verticalCenter: parent.verticalCenter
            source: "qrc:/icons/solaris-logo.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true

            property real offsetX: 0
            x: (parent.width - width) / 2 + offsetX
            opacity: 0.0
            scale: 0.85
        }

        // 2. TEXTO DEL SISTEMA (INTI OS)
        Column {
            id: systemTextCol
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: splashLogo.right
            anchors.leftMargin: 24
            spacing: 2
            opacity: 0.0

            Text {
                text: "Inti OS"
                color: "#ffffff"
                font.pixelSize: 54
                font.bold: true
                font.letterSpacing: 1.0
            }

            Text {
                text: "1.8 · Fácil, rápido y privado"
                color: "#8e95a5"
                font.pixelSize: 17
                font.weight: Font.Normal
                font.letterSpacing: 0.5
            }
        }
    }

    // SECUENCIA CINEMATOGRÁFICA DE ARRANQUE
    SequentialAnimation {
        id: bootSequence
        running: true

        PauseAnimation { duration: 150 }

        // 1. Logo aparece en el centro exacto con fade in y escala
        ParallelAnimation {
            NumberAnimation { target: splashLogo; property: "opacity"; to: 1.0; duration: 650; easing.type: Easing.OutQuad }
            NumberAnimation { target: splashLogo; property: "scale"; to: 1.0; duration: 750; easing.type: Easing.OutBack; easing.overshoot: 1.05 }
        }

        // Pausa breve con el logo en el centro
        PauseAnimation { duration: 400 }

        // 2. Apartar el logo a la izquierda mientras muestra el nombre del sistema
        ParallelAnimation {
            NumberAnimation { target: splashLogo; property: "offsetX"; to: -140; duration: 700; easing.type: Easing.OutCubic }
            NumberAnimation { target: systemTextCol; property: "opacity"; to: 1.0; duration: 700; easing.type: Easing.OutCubic }
        }

        // 3. Momento para contemplar el logo y nombre de Inti OS
        PauseAnimation { duration: 1000 }

        // 4. Desvanecimiento suave para ingresar al escritorio
        ParallelAnimation {
            NumberAnimation { target: bootSplashRoot; property: "opacity"; to: 0.0; duration: 550; easing.type: Easing.InOutCubic }
            NumberAnimation { target: centerContainer; property: "scale"; to: 1.04; duration: 550; easing.type: Easing.OutQuad }
        }

        ScriptAction {
            script: {
                shellBackend.finishBootSplash();
            }
        }
    }
}
