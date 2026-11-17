// Ajustes > Notificaciones: generales y por app (las que han avisado alguna vez).
import QtQuick

PaginaAjustes {
    id: vista
    titulo: "Notificaciones"
    descripcion: "Las notificaciones aparecen en la Isla Dinámica y se guardan en el centro de notificaciones (la campana)."

    TitanTheme { id: tema }
    property var apps: personalizar.appsNotificadoras()
    Component.onCompleted: apps = personalizar.appsNotificadoras()

    Grupo {
        etiqueta: "General"
        Fila {
            titulo: "Mostrar previsualizaciones"
            detalle: "Sin esto, el aviso solo enseña el título"
            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                activo: { prefs.version; return prefs.b("Notificaciones/vistaPrevia") }
                onAlternado: (v) => prefs.poner("Notificaciones/vistaPrevia", v)
            }
        }
        Fila {
            titulo: "Sonido al recibir una notificación"
            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                activo: { prefs.version; return prefs.b("Notificaciones/sonido") }
                onAlternado: (v) => prefs.poner("Notificaciones/sonido", v)
            }
        }
        Fila {
            titulo: "No molestar"
            detalle: "Los avisos se guardan sin aparecer ni sonar. Horario en «Concentración»."
            separador: false
            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                activo: { prefs.version; return prefs.b("Notificaciones/noMolestar") }
                onAlternado: (v) => prefs.poner("Notificaciones/noMolestar", v)
            }
        }
    }

    Grupo {
        etiqueta: "Por aplicación"
        nota: vista.apps.length === 0 ? "Aquí aparecerán las apps cuando manden su primera notificación."
                                      : "Si se desactiva, esa app no enseña nada (los avisos urgentes del sistema sí)."
        Repeater {
            model: vista.apps
            delegate: Fila {
                required property var modelData
                required property int index
                titulo: modelData.nombre
                separador: index < vista.apps.length - 1
                Image {
                    visible: modelData.icono !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    source: modelData.icono
                    sourceSize: Qt.size(40, 40)
                    width: 20; height: 20
                }
                Interruptor {
                    anchors.verticalCenter: parent.verticalCenter
                    activo: { prefs.version; var v = prefs.v("Notificaciones/apps/" + modelData.clave); return v === undefined || v === null || String(v) !== "false" }
                    onAlternado: (v) => { if (v) prefs.quitar("Notificaciones/apps/" + modelData.clave); else prefs.poner("Notificaciones/apps/" + modelData.clave, false) }
                }
            }
        }
    }
}
