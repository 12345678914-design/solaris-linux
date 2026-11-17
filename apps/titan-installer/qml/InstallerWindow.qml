import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

TitanWindow {
    id: window
    width: 900
    height: 600
    minimumWidth: 800
    minimumHeight: 520
    title: "Instalador de Inti OS"
    showSidebar: true
    expandedSidebarWidth: 236
    showStatusBar: false

    TitanTheme { id: theme }

    // ---------- Colores del tema (claro y oscuro) ----------
    // Antes todo el texto era blanco fijo: con el tema claro no se leía.
    readonly property bool dark: window.theme.isDark
    readonly property color txt: window.theme.contentTextPrimary
    readonly property color txt2: window.theme.contentTextSecondary
    readonly property color accent: window.theme.accent
    readonly property color okColor: "#34c759"
    readonly property color warnColor: dark ? "#ff9f0a" : "#c66b00"
    readonly property color errColor: dark ? "#ff453a" : "#d70015"
    // Velo: blanco translúcido en oscuro, negro translúcido en claro.
    function veil(a) { return dark ? Qt.rgba(1, 1, 1, a) : Qt.rgba(0, 0, 0, a * 0.7) }
    function tintOf(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // ---------- Controles con estilo propio ----------
    component Boton: Button {
        id: btn
        font.pixelSize: 13
        font.weight: btn.highlighted ? Font.DemiBold : Font.Normal
        implicitHeight: 32
        leftPadding: 18
        rightPadding: 18
        contentItem: Text {
            text: btn.text
            font: btn.font
            color: btn.highlighted ? "#ffffff" : window.txt
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: 8
            opacity: btn.enabled ? 1.0 : 0.45
            color: btn.highlighted
                   ? (btn.down ? Qt.darker(window.accent, 1.15) : (btn.hovered ? Qt.lighter(window.accent, 1.08) : window.accent))
                   : (btn.down ? window.veil(0.16) : (btn.hovered ? window.veil(0.11) : window.veil(0.06)))
            border.width: btn.highlighted ? 0 : 1
            border.color: window.veil(0.12)
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }

    component Campo: TextField {
        id: campo
        font.pixelSize: 13
        implicitHeight: 34
        leftPadding: 10
        rightPadding: 10
        color: window.txt
        placeholderTextColor: window.txt2
        selectionColor: window.accent
        selectedTextColor: "#ffffff"
        background: Rectangle {
            radius: 8
            color: window.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.9)
            border.width: campo.activeFocus ? 2 : 1
            border.color: campo.activeFocus ? window.accent : window.veil(0.16)
        }
    }

    // Título y subtítulo de cada paso, iguales en todos.
    component Titulo: Text {
        color: window.txt
        font.pixelSize: window.theme.fontTitle
        font.weight: Font.Bold
    }
    component Subtitulo: Text {
        color: window.txt2
        font.pixelSize: window.theme.fontBody
        wrapMode: Text.WordWrap
    }

    property var steps: [
        "Bienvenida",
        "Ubicación y Teclado",
        "Disco de Destino",
        "Usuario",
        "Resumen",
        "Instalación",
        "Finalizado"
    ]

    property string selectedLang: "es_ES.UTF-8"
    property string selectedTimezone: "Europe/Madrid"
    property string selectedKeymap: "es"
    property string selectedFs: "ext4"
    property bool autoLogin: false

    // Lo que impide crear la cuenta, o "" si se puede. Las mismas reglas que
    // useradd: si el nombre no las cumple, la cuenta no se crea y el sistema
    // instalado se queda sin usuario.
    function accountError() {
        var u = userField.text
        if (u.length === 0) return "Escribe un nombre de usuario."
        if (!/^[a-z_][a-z0-9_-]{0,31}$/.test(u))
            return "El usuario solo puede llevar minúsculas, números, '-' y '_', y empezar por letra."
        if (["root", "bin", "daemon", "mail", "ftp", "http", "nobody", "dbus"].indexOf(u) !== -1)
            return "El nombre '" + u + "' está reservado por el sistema."
        if (!/^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(hostnameField.text))
            return "El nombre del equipo solo puede llevar letras, números y '-'."
        if (passField.text.length < 4) return "La contraseña debe tener al menos 4 caracteres."
        if (passField.text !== confirmPassField.text) return "Las contraseñas no coinciden."
        return ""
    }


    // ==============================================================================
    // BARRA LATERAL (PASOS DE INSTALACIÓN): la tarjeta flotante de TitanWindow
    // ==============================================================================
    sidebarContentData: [
        Column {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 6
            spacing: 14

            // Logo y Título
            Row {
                spacing: 12
                Image {
                    source: "qrc:/icons/solaris-logo.png"
                    width: 38
                    height: 38
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "Inti OS"
                        color: window.txt
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Text {
                        text: "Instalador del Sistema"
                        color: window.txt2
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: window.veil(0.1)
            }

            // Lista de Pasos: el actual va en una fila resaltada (como una
            // barra lateral de macOS); los hechos llevan ✓ en verde.
            Column {
                width: parent.width
                spacing: 2
                Repeater {
                    model: steps
                    delegate: Rectangle {
                        id: stepRow
                        required property int index
                        required property string modelData
                        readonly property bool current: installerBackend.currentStep === index
                        readonly property bool done: index < installerBackend.currentStep
                        width: parent.width
                        height: 32
                        radius: 8
                        color: current ? window.tintOf(window.accent, window.dark ? 0.30 : 0.16) : "transparent"
                        Behavior on color { ColorAnimation { duration: 160 } }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 8
                            spacing: 10

                            Rectangle {
                                width: 20
                                height: 20
                                radius: 10
                                anchors.verticalCenter: parent.verticalCenter
                                color: stepRow.done ? window.okColor : (stepRow.current ? window.accent : "transparent")
                                border.width: (stepRow.done || stepRow.current) ? 0 : 1.5
                                border.color: window.veil(0.3)

                                Text {
                                    anchors.centerIn: parent
                                    text: stepRow.done ? "✓" : (stepRow.index + 1)
                                    color: (stepRow.done || stepRow.current) ? "#ffffff" : window.txt2
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: stepRow.modelData
                                color: stepRow.current || stepRow.done ? window.txt : window.txt2
                                font.pixelSize: 13
                                font.weight: stepRow.current ? Font.DemiBold : Font.Normal
                            }
                        }
                    }
                }
            }
        }
    ]

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ==============================================================================
        // ÁREA DE CONTENIDO PRINCIPAL
        // ==============================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 16

                // CONTENEDOR DINÁMICO DE PANTALLAS
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: installerBackend.currentStep

                    // -------------------------------------------------------------
                    // PASO 0: BIENVENIDA
                    // -------------------------------------------------------------
                    Item {
                        Column {
                            anchors.centerIn: parent
                            spacing: 18
                            width: Math.min(parent.width - 40, 520)

                            Image {
                                source: "qrc:/icons/solaris-logo.png"
                                width: 80
                                height: 80
                                anchors.horizontalCenter: parent.horizontalCenter
                                fillMode: Image.PreserveAspectFit
                            }

                            Text {
                                text: "Bienvenido a Inti OS"
                                color: window.txt
                                font.pixelSize: 22
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                text: "Este instalador configurará Inti OS en tu equipo con la interfaz inspirada en macOS, compatibilidad universal de hardware y alto rendimiento."
                                color: window.txt2
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                width: parent.width
                            }

                            // Requisitos del sistema
                            Rectangle {
                                width: parent.width
                                height: 120
                                radius: 10
                                color: window.veil(0.05)
                                border.color: window.veil(0.1)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 10

                                    Row {
                                        spacing: 10
                                        Text { text: installerBackend.reqRamOk ? "✓" : "✗"; color: installerBackend.reqRamOk ? window.okColor : window.errColor; font.bold: true }
                                        Text { text: "Memoria RAM: " + Math.round(installerBackend.ramMb / 1024) + " GB detectados (mínimo 2 GB)"; color: window.txt; font.pixelSize: 12 }
                                    }
                                    Row {
                                        spacing: 10
                                        Text { text: installerBackend.reqDiskOk ? "✓" : "✗"; color: installerBackend.reqDiskOk ? window.okColor : window.errColor; font.bold: true }
                                        Text { text: installerBackend.reqDiskOk ? ("Discos disponibles: " + installerBackend.disks.length + " unidad(es) de almacenamiento") : "No se ha detectado ningún disco duro o SSD"; color: window.txt; font.pixelSize: 12 }
                                    }
                                    Row {
                                        spacing: 10
                                        Text { text: installerBackend.reqPowerOk ? "✓" : "!"; color: installerBackend.reqPowerOk ? window.okColor : window.warnColor; font.bold: true }
                                        Text { text: installerBackend.reqPowerOk ? "Alimentación eléctrica: Conectado a la corriente" : "Aviso: batería baja en el portátil"; color: window.txt; font.pixelSize: 12 }
                                    }
                                }
                            }
                        }
                    }

                    // -------------------------------------------------------------
                    // PASO 1: UBICACIÓN Y TECLADO
                    // -------------------------------------------------------------
                    Item {
                        Column {
                            anchors.fill: parent
                            spacing: 16

                            Text {
                                text: "Ubicación, Región y Teclado"
                                color: window.txt
                                font.pixelSize: 18
                                font.bold: true
                            }

                            Text {
                                text: "Selecciona tu zona horaria y la distribución de teclado que prefieras."
                                color: window.txt2
                                font.pixelSize: 12
                            }

                            // Zona horaria
                            Text { text: "Zona Horaria:"; color: window.txt; font.pixelSize: 13; font.bold: true }
                            ComboBox {
                                width: parent.width
                                model: [
                                    "Europe/Madrid",
                                    "America/Mexico_City",
                                    "America/Bogota",
                                    "America/Argentina/Buenos_Aires",
                                    "America/Santiago",
                                    "America/Lima",
                                    "America/New_York",
                                    "UTC"
                                ]
                                currentIndex: 0
                                onActivated: window.selectedTimezone = currentText
                            }

                            // Distribución de teclado
                            Text { text: "Distribución de Teclado:"; color: window.txt; font.pixelSize: 13; font.bold: true }
                            ComboBox {
                                width: parent.width
                                model: ["es (Español)", "latam (Latinoamericano)", "us (Inglés EE. UU.)"]
                                currentIndex: 0
                                onActivated: {
                                    if (index === 0) window.selectedKeymap = "es"
                                    else if (index === 1) window.selectedKeymap = "latam"
                                    else window.selectedKeymap = "us"
                                }
                            }

                            Text { text: "Prueba tu teclado aquí:"; color: window.txt2; font.pixelSize: 12 }
                            Campo {
                                width: parent.width
                                placeholderText: "Escribe aquí para verificar caracteres: ñ, á, @, #, €..."
                                color: window.txt
                            }
                        }
                    }

                    // -------------------------------------------------------------
                    // PASO 2: DISCO DE DESTINO Y PARTICIONAMIENTO
                    // -------------------------------------------------------------
                    Item {
                        ScrollView {
                            anchors.fill: parent
                            clip: true
                            contentWidth: width

                            Column {
                                width: parent.width
                                spacing: 12

                                Text {
                                    text: "Seleccionar Disco y Particionamiento"
                                    color: window.txt
                                    font.pixelSize: 18
                                    font.bold: true
                                }

                                Text {
                                    text: "Elige la unidad donde se instalará Inti OS y el esquema de particionado."
                                    color: window.txt2
                                    font.pixelSize: 12
                                }

                                Text {
                                    visible: installerBackend.disks.length === 0
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: "No se ha encontrado ningún disco donde instalar (de al menos 8 GB). El USB desde el que arranca Inti OS no se muestra, para no borrarlo por error."
                                    color: window.warnColor
                                    font.pixelSize: 12
                                }

                                // Lista de Discos
                                ListView {
                                    width: parent.width
                                    height: Math.min(Math.max(installerBackend.disks.length * 56, 56), 115)
                                    spacing: 6
                                    clip: true
                                    model: installerBackend.disks
                                    delegate: Rectangle {
                                        width: parent.width
                                        height: 52
                                        radius: 8
                                        color: installerBackend.selectedDiskIndex === index ? window.tintOf(window.accent, 0.25) : window.veil(0.05)
                                        border.color: installerBackend.selectedDiskIndex === index ? window.accent : window.veil(0.12)
                                        border.width: installerBackend.selectedDiskIndex === index ? 2 : 1

                                        Row {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 12

                                            Image {
                                                source: "qrc:/icons/system.png"
                                                width: 28
                                                height: 28
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                Text {
                                                    text: modelData.path + " — " + modelData.size + (modelData.tran ? " (" + modelData.tran + ")" : "")
                                                    color: window.txt
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                }
                                                Text {
                                                    text: modelData.model
                                                    color: window.txt2
                                                    font.pixelSize: 11
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: installerBackend.selectedDiskIndex = index
                                        }
                                    }
                                }

                                Text {
                                    text: "Esquema de Instalación:"
                                    color: window.txt
                                    font.pixelSize: 13
                                    font.bold: true
                                }

                                // Opción 1: Borrar disco completo
                                Rectangle {
                                    width: parent.width
                                    height: 50
                                    radius: 8
                                    color: !installerBackend.manualPartitioning ? window.tintOf(window.accent, 0.2) : window.veil(0.05)
                                    border.color: !installerBackend.manualPartitioning ? window.accent : window.veil(0.12)

                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 10

                                        RadioButton {
                                            checked: !installerBackend.manualPartitioning
                                            anchors.verticalCenter: parent.verticalCenter
                                            onClicked: installerBackend.manualPartitioning = false
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            Text {
                                                text: "Borrar disco e instalar automáticamente"
                                                color: window.txt
                                                font.pixelSize: 12
                                                font.bold: true
                                            }
                                            Text {
                                                text: "Crea automáticamente la partición EFI (/boot/efi de 512M) y la partición Raíz (/)."
                                                color: window.txt2
                                                font.pixelSize: 10
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: installerBackend.manualPartitioning = false
                                    }
                                }

                                // Selector de FS para modo automático
                                Row {
                                    visible: !installerBackend.manualPartitioning
                                    spacing: 12
                                    Text { text: "Sistema de archivos:"; color: window.txt; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12 }
                                    ComboBox {
                                        implicitWidth: 210
                                        model: ["ext4 (Recomendado)", "btrfs"]
                                        currentIndex: 0
                                        onActivated: window.selectedFs = (index === 0) ? "ext4" : "btrfs"
                                    }
                                }

                                // Opción 2: Particionamiento manual
                                Rectangle {
                                    width: parent.width
                                    height: 50
                                    radius: 8
                                    color: installerBackend.manualPartitioning ? window.tintOf(window.accent, 0.2) : window.veil(0.05)
                                    border.color: installerBackend.manualPartitioning ? window.accent : window.veil(0.12)

                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 10

                                        RadioButton {
                                            checked: installerBackend.manualPartitioning
                                            anchors.verticalCenter: parent.verticalCenter
                                            onClicked: installerBackend.manualPartitioning = true
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            Text {
                                                text: "Particionamiento manual (Puntos de montaje, tamaños y formatos)"
                                                color: window.txt
                                                font.pixelSize: 12
                                                font.bold: true
                                            }
                                            Text {
                                                text: "Configura tus propias particiones, puntos de montaje (/boot/efi, /, /home) y tamaños."
                                                color: window.txt2
                                                font.pixelSize: 10
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: installerBackend.manualPartitioning = true
                                    }
                                }

                                // Panel de Particionamiento manual
                                Column {
                                    visible: installerBackend.manualPartitioning
                                    width: parent.width
                                    spacing: 8

                                    // Cabecera de la tabla
                                    Rectangle {
                                        width: parent.width
                                        height: 26
                                        color: window.veil(0.08)
                                        radius: 4
                                        Row {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            Text { width: 140; text: "Punto de Montaje"; color: window.txt2; font.pixelSize: 11; font.bold: true }
                                            Text { width: 120; text: "Tamaño (MiB)"; color: window.txt2; font.pixelSize: 11; font.bold: true }
                                            Text { width: 110; text: "Formato"; color: window.txt2; font.pixelSize: 11; font.bold: true }
                                            Text { text: "Acción"; color: window.txt2; font.pixelSize: 11; font.bold: true }
                                        }
                                    }

                                    // Lista de particiones manuales
                                    Repeater {
                                        model: installerBackend.manualPartitions
                                        delegate: Rectangle {
                                            width: parent.width
                                            height: 40
                                            radius: 6
                                            color: window.veil(0.04)
                                            border.color: window.veil(0.08)

                                            Row {
                                                anchors.fill: parent
                                                anchors.margins: 4
                                                spacing: 8

                                                // Selector de punto de montaje
                                                ComboBox {
                                                    width: 132
                                                    model: ["/", "/boot/efi", "/home", "swap", "/boot", "/var", "/tmp"]
                                                    currentIndex: Math.max(0, model.indexOf(modelData.mount))
                                                    onActivated: {
                                                        installerBackend.updateManualPartition(index, currentText, modelData.size, modelData.fs)
                                                    }
                                                }

                                                // Campo de tamaño
                                                Campo {
                                                    width: 112
                                                    text: modelData.size === 0 ? "Restante" : modelData.size.toString()
                                                    color: window.txt
                                                    placeholderText: "0 = Todo"
                                                    onEditingFinished: {
                                                        var val = parseInt(text) || 0
                                                        installerBackend.updateManualPartition(index, modelData.mount, val, modelData.fs)
                                                    }
                                                }

                                                // Selector de formato
                                                ComboBox {
                                                    width: 102
                                                    model: ["ext4", "btrfs", "fat32", "swap"]
                                                    currentIndex: Math.max(0, model.indexOf(modelData.fs))
                                                    onActivated: {
                                                        installerBackend.updateManualPartition(index, modelData.mount, modelData.size, currentText)
                                                    }
                                                }

                                                // Botón eliminar
                                                Boton {
                                                    text: "✕"
                                                    width: 32
                                                    height: 32
                                                    onClicked: installerBackend.removeManualPartition(index)
                                                }
                                            }
                                        }
                                    }

                                    // Botones de acción manual
                                    Row {
                                        spacing: 8
                                        Boton {
                                            text: "+ Añadir Partición"
                                            onClicked: installerBackend.addManualPartition("/home", 10240, "ext4")
                                        }
                                        Boton {
                                            text: "Restablecer esquema recomendado"
                                            onClicked: installerBackend.resetDefaultPartitions()
                                        }
                                        Boton {
                                            text: "Particionador Externo (GParted)"
                                            onClicked: installerBackend.openExternalPartitioner()
                                        }
                                    }

                                    // Validación del esquema
                                    Text {
                                        text: installerBackend.validatePartitionPlan()
                                        color: window.errColor
                                        font.pixelSize: 11
                                        font.bold: true
                                        visible: text !== ""
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 34
                                    radius: 6
                                    color: window.tintOf(window.errColor, 0.15)
                                    border.color: window.errColor
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Text { text: "⚠"; color: window.errColor; font.bold: true }
                                        Text { text: "Se borrarán los datos contenidos en el disco seleccionado."; color: window.txt; font.pixelSize: 11 }
                                    }
                                }
                            }
                        }
                    }

                    // -------------------------------------------------------------
                    // PASO 3: CUENTA DE USUARIO
                    // -------------------------------------------------------------
                    Item {
                        Column {
                            anchors.fill: parent
                            spacing: 12

                            Text {
                                text: "Crear Cuenta de Usuario"
                                color: window.txt
                                font.pixelSize: 18
                                font.bold: true
                            }

                            Text { text: "¿Cuál es tu nombre?"; color: window.txt; font.pixelSize: 12 }
                            Campo {
                                id: fullNameField
                                width: parent.width
                                text: "Usuario Inti"
                                color: window.txt
                            }

                            Text { text: "Nombre de usuario (para inicio de sesión):"; color: window.txt; font.pixelSize: 12 }
                            Campo {
                                id: userField
                                width: parent.width
                                text: "inti"
                                color: window.txt
                            }

                            Text { text: "Nombre del equipo (Hostname):"; color: window.txt; font.pixelSize: 12 }
                            Campo {
                                id: hostnameField
                                width: parent.width
                                text: "inti-pc"
                                color: window.txt
                            }

                            Row {
                                spacing: 16
                                width: parent.width
                                Column {
                                    width: parent.width / 2 - 8
                                    spacing: 4
                                    Text { text: "Contraseña:"; color: window.txt; font.pixelSize: 12 }
                                    Campo {
                                        id: passField
                                        width: parent.width
                                        text: ""
                                        echoMode: TextInput.Password
                                        color: window.txt
                                    }
                                }
                                Column {
                                    width: parent.width / 2 - 8
                                    spacing: 4
                                    Text { text: "Confirmar contraseña:"; color: window.txt; font.pixelSize: 12 }
                                    Campo {
                                        id: confirmPassField
                                        width: parent.width
                                        text: ""
                                        echoMode: TextInput.Password
                                        color: window.txt
                                    }
                                }
                            }

                            Text {
                                visible: window.accountError() !== ""
                                text: window.accountError()
                                color: window.warnColor
                                font.pixelSize: 12
                                width: parent.width
                                wrapMode: Text.WordWrap
                            }

                            CheckBox {
                                text: "Entrar automáticamente la primera vez (después pedirá la contraseña)"
                                checked: window.autoLogin
                                onToggled: window.autoLogin = checked
                            }
                        }
                    }

                    // -------------------------------------------------------------
                    // PASO 4: RESUMEN
                    // -------------------------------------------------------------
                    Item {
                        Column {
                            anchors.fill: parent
                            spacing: 16

                            Text {
                                text: "Resumen de Instalación"
                                color: window.txt
                                font.pixelSize: 18
                                font.bold: true
                            }

                            Text {
                                text: "Por favor revisa la configuración antes de proceder con el formateo e instalación."
                                color: window.txt2
                                font.pixelSize: 12
                            }

                            Rectangle {
                                width: parent.width
                                height: 160
                                radius: 8
                                color: window.veil(0.05)
                                border.color: window.veil(0.12)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 10

                                    Text { text: "• Disco de destino: " + installerBackend.selectedDiskName; color: window.txt; font.bold: true }
                                    Text { text: "• Particionamiento: " + (installerBackend.manualPartitioning ? ("Manual (" + installerBackend.manualPartitions.length + " particiones configuradas)") : ("Automático (" + window.selectedFs + ")")); color: window.txt }
                                    Text { text: "• Modo de arranque: " + (installerBackend.isUefi ? "UEFI (GPT)" : "BIOS Legacy (MBR)"); color: window.txt }
                                    Text { text: "• Usuario: " + userField.text + " (" + hostnameField.text + ")"; color: window.txt }
                                    Text { text: "• Región y Teclado: " + window.selectedTimezone + " / " + window.selectedKeymap; color: window.txt }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 42
                                radius: 6
                                color: window.tintOf(window.errColor, 0.2)
                                border.color: window.errColor
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text { text: "⚠"; color: window.errColor; font.bold: true; font.pixelSize: 16 }
                                    Text { text: "Al pulsar 'Instalar Ahora' se aplicarán los cambios permanentemente en el disco."; color: window.txt; font.pixelSize: 12 }
                                }
                            }
                        }
                    }

                    // -------------------------------------------------------------
                    // PASO 5: INSTALANDO (PROGRESO)
                    // -------------------------------------------------------------
                    Item {
                        Column {
                            anchors.centerIn: parent
                            spacing: 20
                            width: parent.width - 40

                            Image {
                                source: "qrc:/icons/solaris-logo.png"
                                width: 70
                                height: 70
                                anchors.horizontalCenter: parent.horizontalCenter
                                fillMode: Image.PreserveAspectFit
                            }

                            Text {
                                text: "Instalando Inti OS..."
                                color: window.txt
                                font.pixelSize: 20
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            // Barra de progreso
                            Rectangle {
                                width: parent.width
                                height: 12
                                radius: 6
                                color: window.veil(0.1)

                                Rectangle {
                                    width: parent.width * (installerBackend.progressPercent / 100.0)
                                    height: parent.height
                                    radius: 6
                                    color: window.accent
                                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                            }

                            Item {
                                width: parent.width
                                height: 20
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: installerBackend.progressMessage
                                    color: window.txt2
                                    font.pixelSize: 12
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: installerBackend.progressPercent + "%"
                                    color: window.txt
                                    font.bold: true
                                    font.pixelSize: 12
                                }
                            }

                            Text {
                                visible: installerBackend.errorMessage !== ""
                                text: "La instalación no se ha completado.\n" + installerBackend.errorMessage
                                color: window.errColor
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                width: parent.width
                            }

                            // Si falla, que haya salida: antes la pantalla se
                            // quedaba sin ningún botón.
                            Row {
                                visible: !installerBackend.installing && installerBackend.errorMessage !== ""
                                spacing: 14
                                anchors.horizontalCenter: parent.horizontalCenter
                                Boton {
                                    text: "Cerrar instalador"
                                    onClicked: installerBackend.closeInstaller()
                                }
                                Boton {
                                    text: "Volver al resumen"
                                    highlighted: true
                                    onClicked: installerBackend.currentStep = 4
                                }
                            }
                        }
                    }

                    // -------------------------------------------------------------
                    // PASO 6: COMPLETADO
                    // -------------------------------------------------------------
                    Item {
                        Column {
                            anchors.centerIn: parent
                            spacing: 18
                            width: Math.min(parent.width - 40, 520)

                            Rectangle {
                                width: 64
                                height: 64
                                radius: 32
                                color: window.okColor
                                anchors.horizontalCenter: parent.horizontalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: window.txt
                                    font.pixelSize: 32
                                    font.bold: true
                                }
                            }

                            Text {
                                text: "¡Instalación Completada!"
                                color: window.txt
                                font.pixelSize: 22
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                text: "Inti OS se ha instalado con éxito en tu ordenador. "
                                      + (installerBackend.isUefi ? "Se ha configurado el arranque UEFI de tu disco como prioridad 1. "
                                                                 : "Se ha instalado GRUB en el disco. ")
                                      + "Puedes retirar el medio USB y reiniciar el equipo para comenzar a utilizar tu nuevo sistema operativo."
                                color: window.txt2
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                width: parent.width
                            }

                            Row {
                                spacing: 14
                                anchors.horizontalCenter: parent.horizontalCenter

                                Boton {
                                    text: "Continuar Probando"
                                    onClicked: installerBackend.closeInstaller()
                                }

                                Boton {
                                    text: "Reiniciar Ahora"
                                    highlighted: true
                                    onClicked: installerBackend.rebootSystem()
                                }
                            }
                        }
                    }
                }

                // ==============================================================================
                // BARRA INFERIOR DE NAVEGACIÓN
                // ==============================================================================
                RowLayout {
                    Layout.fillWidth: true
                    visible: installerBackend.currentStep < 5

                    Boton {
                        text: "Cancelar"
                        onClicked: installerBackend.closeInstaller()
                    }

                    Item { Layout.fillWidth: true }

                    Boton {
                        text: "Atrás"
                        visible: installerBackend.currentStep > 0
                        onClicked: installerBackend.currentStep--
                    }

                    Boton {
                        text: installerBackend.currentStep === 4 ? "Instalar Ahora" : "Siguiente"
                        highlighted: true
                        enabled: {
                            if (installerBackend.currentStep === 0) return installerBackend.reqRamOk && installerBackend.reqDiskOk;
                            if (installerBackend.currentStep === 2) return installerBackend.disks.length > 0;
                            if (installerBackend.currentStep === 3) return window.accountError() === "";
                            return true;
                        }
                        onClicked: {
                            if (installerBackend.currentStep === 4) {
                                installerBackend.startInstallation(
                                    window.selectedFs,
                                    fullNameField.text,
                                    userField.text,
                                    passField.text,
                                    hostnameField.text,
                                    window.autoLogin,
                                    window.selectedTimezone,
                                    window.selectedKeymap
                                );
                            } else {
                                installerBackend.currentStep++;
                            }
                        }
                    }
                }
            }
        }
    }
}
