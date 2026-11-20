import QtQuick 2.15
import QtQuick.Controls 2.15

ScrollView {
    id: generalView
    contentWidth: width
    clip: true

    TitanTheme { id: theme }

    Column {
        width: parent.width - 48
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 20
        topPadding: 16
        bottomPadding: 32

        // 1. IDIOMA
        Column {
            width: parent.width
            spacing: 8

            Text {
                text: "Idioma"
                color: theme.contentTextPrimary
                font.pixelSize: 13
                font.bold: true
            }

            Row {
                width: parent.width
                spacing: 12

                Text {
                    text: "Automático sigue el idioma del sistema"
                    color: theme.contentTextSecondary
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 340
                    wrapMode: Text.WordWrap
                }

                // Control segmentado de idioma estilo macOS
                Rectangle {
                    width: 320
                    height: 28
                    radius: 7
                    color: theme.isDark ? Qt.rgba(0.18, 0.20, 0.26, 0.8) : Qt.rgba(0.0, 0.0, 0.0, 0.08)
                    border.color: theme.contentCardBorder
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: 2
                        spacing: 2

                        Repeater {
                            model: [
                                { id: "auto", name: "Automático" },
                                { id: "es", name: "Español" },
                                { id: "en", name: "English" },
                                { id: "quz", name: "Quechua" }
                            ]

                            delegate: Rectangle {
                                width: (parent.width - 6) / 4
                                height: parent.height
                                radius: 5
                                color: settingsBackend.language === modelData.id ?
                                       (theme.isDark ? "#323644" : "#ffffff") : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    color: theme.contentTextPrimary
                                    font.pixelSize: 10
                                    font.bold: settingsBackend.language === modelData.id
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: settingsBackend.language = modelData.id
                                }
                            }
                        }
                    }
                }
            }

            // Qué ha pasado al cambiarlo (se aplica al volver a entrar)
            Text {
                visible: settingsBackend.languageStatus !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: settingsBackend.languageStatus
                color: settingsBackend.languageStatus.indexOf("Listo") === 0 ? theme.accent : theme.contentTextSecondary
                font.pixelSize: 11
            }
        }

        // 2. SHELL
        Column {
            width: parent.width
            spacing: 8

            Text {
                text: "Shell"
                color: theme.contentTextSecondary
                font.pixelSize: 12
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: 128
                radius: 10
                color: theme.contentCardBg
                border.color: theme.contentCardBorder
                border.width: 1

                Column {
                    anchors.fill: parent

                    // Fila 1: Dock
                    Item {
                        width: parent.width
                        height: 63

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Text {
                                text: "Dock"
                                color: theme.contentTextPrimary
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text {
                                text: "Mostrar el Dock en la parte inferior de la pantalla"
                                color: theme.contentTextSecondary
                                font.pixelSize: 11
                            }
                        }

                        // Toggle verde estilo iOS
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44
                            height: 24
                            radius: 12
                            color: settingsBackend.dockEnabled ? "#34c759" : (theme.isDark ? "#39393d" : "#e5e5ea")
                            Behavior on color { ColorAnimation { duration: 160 } }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: settingsBackend.dockEnabled ? 22 : 2
                                width: 20
                                height: 20
                                radius: 10
                                color: "#ffffff"
                                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settingsBackend.dockEnabled = !settingsBackend.dockEnabled
                            }
                        }
                    }

                    // Separador 1px
                    Rectangle {
                        width: parent.width - 32
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 1
                        color: theme.contentCardBorder
                    }

                    // Fila 2: Barra de menús
                    Item {
                        width: parent.width
                        height: 64

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            width: parent.width - 80

                            Text {
                                text: "Barra de menús"
                                color: theme.contentTextPrimary
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text {
                                text: "Mostrar el panel en la parte superior de la pantalla. Spotlight, el Centro de control y el calendario están en él."
                                color: theme.contentTextSecondary
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        // Toggle verde estilo iOS
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44
                            height: 24
                            radius: 12
                            color: settingsBackend.topBarEnabled ? "#34c759" : (theme.isDark ? "#39393d" : "#e5e5ea")
                            Behavior on color { ColorAnimation { duration: 160 } }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: settingsBackend.topBarEnabled ? 22 : 2
                                width: 20
                                height: 20
                                radius: 10
                                color: "#ffffff"
                                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settingsBackend.topBarEnabled = !settingsBackend.topBarEnabled
                            }
                        }
                    }
                }
            }

            Text {
                text: "Si desactivas ambos, reabre esta ventana con: titan-settings"
                color: theme.contentTextSecondary
                font.pixelSize: 11
                leftPadding: 4
            }
        }

        // 3. ACTUALIZACIÓN DE SOFTWARE
        Column {
            width: parent.width
            spacing: 12

            Text {
                text: "Actualización de software (Arch Linux)"
                color: theme.contentTextSecondary
                font.pixelSize: 12
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: 56
                radius: 10
                color: theme.contentCardBg
                border.color: theme.contentCardBorder
                border.width: 1

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: updateBtnRect.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    Text {
                        text: settingsBackend.updateChecking ? "⏳" : "🔄"
                        font.pixelSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: settingsBackend.updateRunning ? "Hay una actualización en marcha" : settingsBackend.updateStatus
                        color: theme.contentTextPrimary
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        width: parent.width - 32
                    }
                }

                Rectangle {
                    id: updateBtnRect
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: updateBtnText.implicitWidth + 24
                    height: 28
                    radius: 6
                    color: settingsBackend.updateChecking ? (theme.isDark ? "#22242b" : "#e0e0e0") :
                           updateMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.08) : (theme.isDark ? "#2c303c" : "#f0f0f4")
                    border.color: Qt.rgba(0, 0, 0, 0.15)
                    border.width: 1
                    opacity: settingsBackend.updateChecking || settingsBackend.updateRunning ? 0.6 : 1.0

                    Text {
                        id: updateBtnText
                        anchors.centerIn: parent
                        text: settingsBackend.updateChecking ? "Buscando..." : "Buscar actualizaciones"
                        color: theme.contentTextPrimary
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        id: updateMouse
                        anchors.fill: parent
                        enabled: !settingsBackend.updateChecking && !settingsBackend.updateRunning
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: settingsBackend.checkUpdates()
                    }
                }
            }

            // TARJETA DE CONFIRMACIÓN MODAL CUANDO HAY ACTUALIZACIONES ENCONTRADAS
            Rectangle {
                visible: settingsBackend.updatePromptVisible
                width: parent.width
                height: 120
                radius: 10
                color: theme.isDark ? Qt.rgba(0.08, 0.35, 0.70, 0.18) : Qt.rgba(0.04, 0.45, 0.95, 0.08)
                border.color: theme.accent
                border.width: 1.5

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    Row {
                        width: parent.width
                        spacing: 10

                        Text {
                            text: "📦"
                            font.pixelSize: 20
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            width: parent.width - 36

                            Text {
                                text: "Actualización disponible: " + settingsBackend.updateCount + " paquetes (" + settingsBackend.updateSize + ")"
                                color: theme.contentTextPrimary
                                font.pixelSize: 13
                                font.bold: true
                            }

                            Text {
                                text: "Se instala sola, sin preguntas: pones la contraseña una vez y puedes seguir usando el equipo."
                                color: theme.contentTextSecondary
                                font.pixelSize: 11
                            }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 12

                        // Botón Rechazar / Cancelar
                        Rectangle {
                            width: 90
                            height: 28
                            radius: 6
                            color: cancelMouse.containsMouse ? (theme.isDark ? "#383c48" : "#d8d8de") : (theme.isDark ? "#282b34" : "#e8e8ed")
                            border.color: theme.contentCardBorder
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "Ahora no"
                                color: theme.contentTextPrimary
                                font.pixelSize: 11
                                font.bold: true
                            }

                            MouseArea {
                                id: cancelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settingsBackend.cancelUpdates()
                            }
                        }

                        // Botón Instalar
                        Rectangle {
                            width: 140
                            height: 28
                            radius: 6
                            color: installMouse.containsMouse ? Qt.darker(theme.accent, 1.15) : theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: "Actualizar"
                                color: "#ffffff"
                                font.pixelSize: 11
                                font.bold: true
                            }

                            MouseArea {
                                id: installMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settingsBackend.installUpdates()
                            }
                        }
                    }
                }
            }

            // ACTUALIZANDO: mensaje, barra y, dentro, el registro (como Garuda,
            // pero sin terminal ni preguntas)
            Rectangle {
                id: tarjetaActualizando
                visible: settingsBackend.updateRunning || settingsBackend.updateResult !== ""
                property bool detalles: false
                width: parent.width
                height: cuerpoAct.implicitHeight + 32
                radius: 10
                color: theme.contentCardBg
                border.color: settingsBackend.updateResult === "error" ? "#ff453a" : theme.contentCardBorder
                border.width: 1

                Column {
                    id: cuerpoAct
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 10

                    Text {
                        width: parent.width
                        text: settingsBackend.updateRunning ? "Actualizando el sistema"
                              : settingsBackend.updateResult === "ok" ? "✓ Actualización terminada"
                              : "No se pudo terminar la actualización"
                        color: settingsBackend.updateResult === "error" ? "#ff453a" : theme.contentTextPrimary
                        font.pixelSize: 13
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        text: settingsBackend.updateStatus
                        color: theme.contentTextSecondary
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    // Barra de progreso
                    Rectangle {
                        width: parent.width
                        height: 6
                        radius: 3
                        color: theme.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                        visible: settingsBackend.updateResult !== "error"
                        Rectangle {
                            width: Math.max(6, parent.width * settingsBackend.updateProgress)
                            height: parent.height
                            radius: 3
                            color: theme.accent
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        }
                    }
                    Text {
                        visible: settingsBackend.updateRunning
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Puedes seguir usando el equipo y cerrar esta ventana: la actualización sigue. No apagues el equipo hasta que termine."
                        color: theme.contentTextSecondary
                        font.pixelSize: 10
                    }

                    Row {
                        spacing: 12
                        // Mostrar / ocultar el registro
                        Text {
                            text: (tarjetaActualizando.detalles ? "▾ Ocultar detalles" : "▸ Mostrar detalles")
                            color: theme.accent
                            font.pixelSize: 11
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: tarjetaActualizando.detalles = !tarjetaActualizando.detalles
                            }
                        }
                    }

                    Rectangle {
                        visible: tarjetaActualizando.detalles
                        width: parent.width
                        height: 220
                        radius: 8
                        color: theme.isDark ? "#101114" : "#f4f4f6"
                        border.color: theme.contentCardBorder
                        clip: true
                        Flickable {
                            id: desplazaRegistro
                            anchors.fill: parent
                            anchors.margins: 8
                            contentWidth: width
                            contentHeight: textoRegistro.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            // Siempre en la última línea, salvo que se haya subido a leer
                            property bool alFinal: true
                            onMovementEnded: alFinal = contentY >= contentHeight - height - 4
                            onContentHeightChanged: if (alFinal) contentY = Math.max(0, contentHeight - height)
                            TextEdit {
                                id: textoRegistro
                                width: desplazaRegistro.width
                                text: settingsBackend.updateLog
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                color: theme.contentTextSecondary
                                font.family: "monospace"
                                font.pixelSize: 10
                            }
                        }
                    }

                    // Botones al terminar
                    Row {
                        visible: !settingsBackend.updateRunning
                        anchors.right: parent.right
                        spacing: 12
                        Rectangle {
                            visible: settingsBackend.updateResult === "error"
                            width: 110; height: 28; radius: 6
                            color: reintentarMouse.containsMouse ? Qt.darker(theme.accent, 1.15) : theme.accent
                            Text { anchors.centerIn: parent; text: "Reintentar"; color: "#ffffff"; font.pixelSize: 11; font.bold: true }
                            MouseArea { id: reintentarMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: settingsBackend.installUpdates() }
                        }
                        Rectangle {
                            visible: settingsBackend.updateNeedsReboot && settingsBackend.updateResult === "ok"
                            width: 130; height: 28; radius: 6
                            color: reiniciarMouse.containsMouse ? Qt.darker(theme.accent, 1.15) : theme.accent
                            Text { anchors.centerIn: parent; text: "Reiniciar ahora"; color: "#ffffff"; font.pixelSize: 11; font.bold: true }
                            MouseArea { id: reiniciarMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: settingsBackend.rebootNow() }
                        }
                    }
                }
            }
        }
    }
}

