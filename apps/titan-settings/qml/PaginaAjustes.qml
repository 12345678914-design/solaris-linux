// Pagina de una seccion de Ajustes: titulo, descripcion, aviso y contenido.
import QtQuick
import QtQuick.Controls

ScrollView {
    id: pagina
    property string titulo: ""
    property string descripcion: ""
    // Aviso de la ultima operacion; cada seccion puede usar el de su backend.
    property string mensaje: sistema.aviso
    signal mensajeCerrado()
    default property alias contenido: columna.data
    contentWidth: width
    clip: true

    TitanTheme { id: tema }

    Column {
        id: columna
        x: 24
        width: pagina.width - 48
        spacing: 18
        topPadding: 18
        bottomPadding: 32

        Column {
            width: parent.width
            spacing: 4
            Text {
                text: pagina.titulo
                color: tema.contentTextPrimary
                font.pixelSize: 20
                font.bold: true
            }
            Text {
                visible: text.length > 0
                width: parent.width
                text: pagina.descripcion
                color: tema.contentTextSecondary
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        // Aviso de la ultima operacion (error o confirmacion)
        Rectangle {
            visible: pagina.mensaje.length > 0
            width: parent.width
            height: textoAviso.implicitHeight + 20
            radius: 8
            color: tema.isDark ? Qt.rgba(0.04, 0.45, 0.95, 0.16) : Qt.rgba(0.04, 0.45, 0.95, 0.08)
            border.color: Qt.rgba(0.04, 0.45, 0.95, 0.45)
            border.width: 1
            Text {
                id: textoAviso
                anchors.left: parent.left
                anchors.right: cerrarAviso.left
                anchors.margins: 12
                anchors.verticalCenter: parent.verticalCenter
                text: pagina.mensaje
                color: tema.contentTextPrimary
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
            Text {
                id: cerrarAviso
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"
                color: tema.contentTextSecondary
                font.pixelSize: 11
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { sistema.refrescar(""); pagina.mensajeCerrado() }
                }
            }
        }
    }
}
