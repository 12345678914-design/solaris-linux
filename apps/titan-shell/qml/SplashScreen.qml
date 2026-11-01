import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: splashCard
    width: parent ? parent.width : 800
    height: parent ? parent.height : 520
    radius: 18

    TitanTheme { id: titanTheme }

    // Fondo Liquid Glass que emula la ventana nativa que se está abriendo
    color: titanTheme.isDark ? Qt.rgba(0.11, 0.12, 0.16, 0.88) : Qt.rgba(0.97, 0.97, 0.99, 0.88)
    border.color: titanTheme.glassBorder
    border.width: 1
    clip: true

    // Brillo especular superior del cristal
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 24
        height: 1
        color: titanTheme.specularGlow
    }

    // Cabecera decorativa simulada estilo ventana macOS (Traffic Lights)
    Item {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 38

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Rectangle { width: 11; height: 11; radius: 5.5; color: "#ff5f57"; opacity: 0.7 }
            Rectangle { width: 11; height: 11; radius: 5.5; color: "#febc2e"; opacity: 0.7 }
            Rectangle { width: 11; height: 11; radius: 5.5; color: "#28c840"; opacity: 0.7 }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: titanTheme.glassBorder
            opacity: 0.5
        }
    }

    scale: shellBackend.splashVisible ? 1.0 : 0.94
    opacity: shellBackend.splashVisible ? 1.0 : 0.0

    Behavior on scale {
        NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.05 }
    }
    Behavior on opacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 12
        spacing: 16

        // Icono de la aplicación en el centro con animación de pulso suave
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 70
            height: 70

            scale: pulseAnim.scaleVal

            QtObject {
                id: pulseAnim
                property real scaleVal: 1.0
                SequentialAnimation on scaleVal {
                    running: splashCard.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.07; duration: 650; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                }
            }

            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                source: {
                    var ic = shellBackend.splashIcon;
                    if (ic.indexOf("/") !== -1) return ic;
                    if (ic === "folder" || ic === "titan-finder") return "qrc:/icons/finder.png";
                    if (ic === "view-app-grid" || ic === "launchpad") return "qrc:/icons/launchpad.png";
                    if (ic === "utilities-terminal" || ic === "terminal" || ic === "titan-terminal") return "qrc:/icons/terminal.png";
                    if (ic === "system-file-manager" || ic === "pcmanfm-qt" || ic === "files") return "qrc:/icons/files.png";
                    if (ic === "help-about" || ic === "titan-acerca") return "qrc:/icons/about.png";
                    if (ic === "firefox" || ic === "safari") return "qrc:/icons/safari.png";
                    if (ic === "vscode" || ic === "code") return "qrc:/icons/vscode.png";
                    if (ic === "system" || ic === "titan-settings") return "qrc:/icons/system.png";
                    if (ic === "onlyoffice" || ic === "onlyoffice-desktopeditors") return "qrc:/icons/onlyoffice.png";
                    return "qrc:/icons/developer.png";
                }
            }
        }

        // Nombre de la app
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: shellBackend.splashName
            color: titanTheme.contentTextPrimary
            font.pixelSize: 15
            font.bold: true
        }

        // Indicador de espera suave
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6

            Repeater {
                model: 3
                delegate: Rectangle {
                    width: 6; height: 6; radius: 3
                    color: titanTheme.accent
                    opacity: dotAnim.dotOpacity

                    QtObject {
                        id: dotAnim
                        property real dotOpacity: 0.3
                        SequentialAnimation on dotOpacity {
                            running: splashCard.visible
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 180 }
                            NumberAnimation { to: 1.0; duration: 320; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0.3; duration: 320; easing.type: Easing.InOutSine }
                            PauseAnimation { duration: (2 - index) * 180 }
                        }
                    }
                }
            }
        }
    }
}
