import QtQuick 2.15

Rectangle {
    id: windowDecorations
    height: 28
    color: Qt.rgba(0.2, 0.2, 0.2, 0.9)
    radius: 10
    
    TrafficLights {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
    }
    
    Text {
        anchors.centerIn: parent
        text: "Ventana"
        color: "white"
        font.pixelSize: 12
    }
}
