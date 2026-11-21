import QtQuick 2.15
import QtQuick.Controls 2.15

TitanWindow {
    id: settingsWindow

    title: "Ajustes del Sistema - " + settingsBackend.currentSection
    sidebarWidth: 230
    showStatusBar: false

    TitanTheme { id: theme }

    // 1. TOOLBAR SUPERIOR DEL CONTENIDO (BOTONES < > Y TÍTULO DE LA SECCIÓN)
    headerContentData: Row {
        anchors.fill: parent
        spacing: 14

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Rectangle {
                width: 26
                height: 24
                radius: 5
                color: navBackMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.08) : "transparent"
                border.color: Qt.rgba(0, 0, 0, 0.1)

                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    color: theme.headerText
                    font.pixelSize: 16
                    font.bold: true
                }

                MouseArea {
                    id: navBackMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingsBackend.currentSection = "General"
                }
            }

            Rectangle {
                width: 26
                height: 24
                radius: 5
                color: "transparent"
                opacity: 0.35

                Text {
                    anchors.centerIn: parent
                    text: "›"
                    color: theme.headerText
                    font.pixelSize: 16
                    font.bold: true
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: settingsBackend.currentSection
            color: theme.headerText
            font.pixelSize: 14
            font.bold: true
        }
    }

    // 2. BARRA LATERAL TRANSLÚCIDA ESTILO macOS VENTURA / SONOMA
    sidebarContentData: Item {
        anchors.fill: parent

        // A. BUSCADOR ESTILO macOS
        Rectangle {
            id: searchBox
            anchors.top: parent.top
            anchors.topMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 24
            height: 28
            radius: 6
            color: theme.isDark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.6)
            border.color: searchInput.activeFocus ? theme.accent : Qt.rgba(0, 0, 0, 0.12)
            border.width: searchInput.activeFocus ? 1.5 : 1

            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "🔍"
                    font.pixelSize: 10
                    opacity: 0.6
                }

                TextField {
                    id: searchInput
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 36
                    placeholderText: "Buscar"
                    font.pixelSize: 11
                    color: theme.contentTextPrimary
                    background: null
                    placeholderTextColor: theme.contentTextSecondary
                    text: settingsBackend.searchQuery
                    onTextChanged: settingsBackend.searchQuery = text
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text.length > 0
                    text: "✕"
                    color: theme.contentTextSecondary
                    font.pixelSize: 10
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: searchInput.text = ""
                    }
                }
            }
        }

        // B. TARJETA DE PERFIL DE USUARIO
        Item {
            id: userCard
            anchors.top: searchBox.bottom
            anchors.topMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 20
            height: 48

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: userMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                spacing: 10

                // Avatar circular con monograma
                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    color: theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: (settingsBackend.systemInfo.user && settingsBackend.systemInfo.user.length > 0) ?
                              settingsBackend.systemInfo.user.charAt(0).toUpperCase() : "I"
                        color: "#ffffff"
                        font.pixelSize: 15
                        font.bold: true
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: settingsBackend.systemInfo.user || ""
                        color: theme.contentTextPrimary
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Text {
                        text: "Cuenta local"
                        color: theme.contentTextSecondary
                        font.pixelSize: 10
                    }
                }
            }

            MouseArea {
                id: userMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: settingsBackend.currentSection = "Usuarios y grupos"
            }
        }

        // Separador sutil
        Rectangle {
            id: sidebarSep
            anchors.top: userCard.bottom
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 24
            height: 1
            color: theme.sidebarBorder
        }

        // C. LISTA DE CATEGORÍAS DETERMINISTA
        ListView {
            id: sidebarListView
            anchors.top: sidebarSep.bottom
            anchors.topMargin: 6
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: 2

            model: settingsBackend.sections

            delegate: Item {
                width: sidebarListView.width - 16
                height: 32
                anchors.horizontalCenter: parent.horizontalCenter

                property bool isSelected: settingsBackend.currentSection === modelData.name ||
                                          settingsBackend.currentSection === modelData.id
                property bool isHovered: rowMouse.containsMouse

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: isSelected ? theme.accent :
                           isHovered ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)) : "transparent"

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        spacing: 10

                        // Icono redondeado estilo macOS
                        Rectangle {
                            width: 20
                            height: 20
                            radius: 5
                            color: modelData.badgeColor || "#007aff"
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                font.pixelSize: 11
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            color: isSelected ? "#ffffff" : theme.contentTextPrimary
                            font.pixelSize: 11
                            font.weight: isSelected ? Font.Medium : Font.Normal
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            settingsBackend.currentSection = modelData.name
                        }
                    }
                }
            }
        }
    }

    // 3. CONTENIDO PRINCIPAL DE LA DERECHA
    Loader {
        id: viewLoader
        anchors.fill: parent

        sourceComponent: {
            var sec = settingsBackend.currentSection;
            if (sec === "Apariencia") {
                return appearanceComponent
            } else if (sec === "Fondo de pantalla") {
                return wallpaperComponent
            } else if (sec === "General" || sec === "Acerca de") {
                return generalComponent
            } else if (sec === "Wi-Fi" || sec === "wifi" || sec === "Red" || sec === "red") {
                return wifiComponent
            } else if (sec === "Bluetooth" || sec === "bluetooth") {
                return bluetoothComponent
            } else if (vistasSistema[sec] !== undefined) {
                return vistasSistema[sec]
            } else {
                return dynamicSectionComponent
            }
        }
    }

    Component { id: appearanceComponent; AppearanceView {} }
    Component { id: wallpaperComponent; WallpaperView {} }
    Component { id: generalComponent; GeneralView {} }
    Component { id: wifiComponent; WifiView {} }
    Component { id: bluetoothComponent; BluetoothView {} }

    // Secciones con datos reales del sistema (backend Sistema)
    readonly property var vistasSistema: ({
        "Batería": energiaComponent,
        "Bloquear pantalla": bloqueoComponent,
        "Privacidad y seguridad": seguridadComponent,
        "Accesibilidad": accesibilidadComponent,
        "Teclado": tecladoComponent,
        "Ratón y panel táctil": ratonComponent,
        "Compartir": compartirComponent,
        "Impresoras y escáneres": impresorasComponent,
        "Restaurar sistema": restaurarComponent,
        "VPN": vpnComponent,
        "Almacenamiento": almacenamientoComponent,
        "Pantallas": pantallasComponent,
        "Sonido": sonidoComponent,
        "Escritorio y Dock": escritorioDockComponent,
        "Barra de menús": barraMenusComponent,
        "Centro de control": centroControlComponent,
        "Notificaciones": notificacionesComponent,
        "Concentración": concentracionComponent,
        "Usuarios y grupos": usuariosComponent
    })
    Component { id: pantallasComponent; PantallasView {} }
    Component { id: sonidoComponent; SonidoView {} }
    Component { id: escritorioDockComponent; EscritorioDockView {} }
    Component { id: barraMenusComponent; BarraMenusView {} }
    Component { id: centroControlComponent; CentroControlView {} }
    Component { id: notificacionesComponent; NotificacionesView {} }
    Component { id: concentracionComponent; ConcentracionView {} }
    Component { id: usuariosComponent; UsuariosView {} }
    Component { id: energiaComponent; EnergiaView {} }
    Component { id: bloqueoComponent; BloqueoView {} }
    Component { id: seguridadComponent; SeguridadView {} }
    Component { id: accesibilidadComponent; AccesibilidadView {} }
    Component { id: tecladoComponent; TecladoView {} }
    Component { id: ratonComponent; RatonView {} }
    Component { id: compartirComponent; CompartirView {} }
    Component { id: impresorasComponent; ImpresorasView {} }
    Component { id: restaurarComponent; RestaurarView {} }
    Component { id: vpnComponent; VpnView {} }
    Component { id: almacenamientoComponent; AlmacenamientoView {} }

    // Componente dinámico y completo para todas las demás secciones
    Component {
        id: dynamicSectionComponent

        ScrollView {
            contentWidth: width
            clip: true

            Column {
                width: parent.width - 48
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20
                topPadding: 20
                bottomPadding: 32

                // Encabezado de la sección activa
                Row {
                    width: parent.width
                    spacing: 12

                    Text {
                        text: settingsBackend.currentSection
                        color: theme.contentTextPrimary
                        font.pixelSize: 18
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // TARJETA 1: ESTADO PRINCIPAL E INTERRUPTOR
                Rectangle {
                    width: parent.width
                    height: 64
                    radius: 10
                    color: theme.contentCardBg
                    border.color: theme.contentCardBorder
                    border.width: 1

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Column {
                            spacing: 3
                            Text {
                                text: settingsBackend.currentSection === "Wi-Fi" ? "Conexión Wi-Fi" :
                                      settingsBackend.currentSection === "Bluetooth" ? "Bluetooth" :
                                      settingsBackend.currentSection === "Sonido" ? "Sonido del Sistema" :
                                      settingsBackend.currentSection === "Pantallas" ? "Pantalla Principal (1920×1080)" :
                                      settingsBackend.currentSection === "Batería" ? "Alimentación y Batería" :
                                      settingsBackend.currentSection === "Teclado" ? "Distribución del Teclado" :
                                      "Opciones de " + settingsBackend.currentSection
                                color: theme.contentTextPrimary
                                font.pixelSize: 13
                                font.bold: true
                            }
                            Text {
                                text: settingsBackend.currentSection === "Wi-Fi" ? "Conectado a red local de alta velocidad" :
                                      settingsBackend.currentSection === "Bluetooth" ? "Visible para otros dispositivos cercanos" :
                                      settingsBackend.currentSection === "Sonido" ? "Salida: Altavoces integrados / Entrada: Micrófono" :
                                      settingsBackend.currentSection === "Pantallas" ? "Tasa de refresco: 60.00 Hz • Perfil de color estándar" :
                                      settingsBackend.currentSection === "Batería" ? "Nivel: 95% • Modo de consumo equilibrado" :
                                      settingsBackend.currentSection === "Teclado" ? "Español (Latinoamérica) / Arch Linux keymap" :
                                      "Configuración activa administrada por Inti OS"
                                color: theme.contentTextSecondary
                                font.pixelSize: 11
                            }
                        }
                    }

                    // Toggle verde estilo iOS
                    Rectangle {
                        id: mainSectionToggle
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 24
                        radius: 12
                        property bool active: true
                        color: active ? "#34c759" : (theme.isDark ? "#39393d" : "#e5e5ea")
                        Behavior on color { ColorAnimation { duration: 160 } }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: mainSectionToggle.active ? 22 : 2
                            width: 20
                            height: 20
                            radius: 10
                            color: "#ffffff"
                            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mainSectionToggle.active = !mainSectionToggle.active
                        }
                    }
                }

                // TARJETA 2: AJUSTES DETALLADOS SEGÚN LA SECCIÓN
                Rectangle {
                    width: parent.width
                    height: settingsBackend.currentSection === "Sonido" || settingsBackend.currentSection === "Pantallas" ? 140 : 110
                    radius: 10
                    color: theme.contentCardBg
                    border.color: theme.contentCardBorder
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        Text {
                            text: settingsBackend.currentSection === "Sonido" ? "Volumen de salida" :
                                  settingsBackend.currentSection === "Pantallas" ? "Nivel de brillo" :
                                  settingsBackend.currentSection === "Batería" ? "Condición de la batería" :
                                  settingsBackend.currentSection === "Usuarios y grupos" ? "Detalles de la cuenta" :
                                  "Preferencias avanzadas"
                            color: theme.contentTextPrimary
                            font.pixelSize: 12
                            font.bold: true
                        }

                        // Slider interactivo para sonido o pantalla
                        Row {
                            visible: settingsBackend.currentSection === "Sonido" || settingsBackend.currentSection === "Pantallas"
                            width: parent.width
                            spacing: 14

                            Text {
                                text: settingsBackend.currentSection === "Sonido" ? "🔈" : "🔅"
                                font.pixelSize: 14
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Slider {
                                id: levelSlider
                                width: parent.width - 80
                                anchors.verticalCenter: parent.verticalCenter
                                from: 0.0
                                to: 1.0
                                value: 0.8
                            }

                            Text {
                                text: Math.round(levelSlider.value * 100) + "%"
                                color: theme.contentTextSecondary
                                font.pixelSize: 11
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Información secundaria
                        Text {
                            text: settingsBackend.currentSection === "Batería" ? "Salud de batería: 98% (Normal) • Temperatura óptima: 31°C" :
                                  settingsBackend.currentSection === "Usuarios y grupos" ? "Usuario: " + (settingsBackend.systemInfo.user || "") + " • Grupo: wheel (Administrador)" :
                                  settingsBackend.currentSection === "Teclado" ? "Velocidad de repetición: Rápida • Retardo: Corto" :
                                  settingsBackend.currentSection === "Wi-Fi" ? "Dirección IPv4: 192.168.1.105 • Puerta de enlace: 192.168.1.1" :
                                  settingsBackend.currentSection === "Bluetooth" ? "Controlador Intel AX200 • Perfiles soportados: A2DP, AVRCP, HFP" :
                                  "Compatibilidad nativa con Wayland y compositor labwc en Inti OS"
                            color: theme.contentTextSecondary
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}
