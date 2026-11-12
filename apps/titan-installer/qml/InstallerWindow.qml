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
    title: "Instalador de Solaris Linux"
    showSidebar: false
    showStatusBar: false

    TitanTheme { id: theme }

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

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ==============================================================================
        // BARRA LATERAL IZQUIERDA (PASOS DE INSTALACIÓN)
        // ==============================================================================
        Rectangle {
            Layout.fillHeight: parent
            Layout.preferredWidth: 230
            color: Qt.rgba(0.08, 0.08, 0.12, 0.85)
            border.color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16

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
                            text: "Solaris Linux"
                            color: "#ffffff"
                            font.pixelSize: 15
                            font.bold: true
                        }
                        Text {
                            text: "Instalador del Sistema"
                            color: "#8e8e93"
                            font.pixelSize: 11
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.1)
                }

                // Lista de Pasos
                Repeater {
                    model: steps
                    delegate: Row {
                        spacing: 12
                        opacity: installerBackend.currentStep === index ? 1.0 : (index < installerBackend.currentStep ? 0.8 : 0.4)

                        Rectangle {
                            width: 24
                            height: 24
                            radius: 12
                            color: index < installerBackend.currentStep ? "#34c759" : (installerBackend.currentStep === index ? "#007aff" : Qt.rgba(1, 1, 1, 0.1))
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: index < installerBackend.currentStep ? "✓" : (index + 1)
                                color: "#ffffff"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData
                            color: "#ffffff"
                            font.pixelSize: 13
                            font.bold: installerBackend.currentStep === index
                        }
                    }
                }
            }
        }

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
                                text: "Bienvenido a Solaris Linux"
                                color: "#ffffff"
                                font.pixelSize: 22
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                text: "Este instalador configurará Solaris Linux en tu equipo con la interfaz inspirada en macOS, compatibilidad universal de hardware y alto rendimiento."
                                color: "#a1a1aa"
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
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.color: Qt.rgba(1, 1, 1, 0.1)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 10

                                    Row {
                                        spacing: 10
                                        Text { text: installerBackend.reqRamOk ? "✓" : "✗"; color: installerBackend.reqRamOk ? "#34c759" : "#ff3b30"; font.bold: true }
                                        Text { text: "Memoria RAM: " + Math.round(installerBackend.ramMb / 1024) + " GB detectados (mínimo 2 GB)"; color: "#ffffff"; font.pixelSize: 12 }
                                    }
                                    Row {
                                        spacing: 10
                                        Text { text: installerBackend.reqDiskOk ? "✓" : "✗"; color: installerBackend.reqDiskOk ? "#34c759" : "#ff3b30"; font.bold: true }
                                        Text { text: installerBackend.reqDiskOk ? ("Discos disponibles: " + installerBackend.disks.length + " unidad(es) de almacenamiento") : "No se ha detectado ningún disco duro o SSD"; color: "#ffffff"; font.pixelSize: 12 }
                                    }
                                    Row {
                                        spacing: 10
                                        Text { text: installerBackend.reqPowerOk ? "✓" : "!"; color: installerBackend.reqPowerOk ? "#34c759" : "#ff9500"; font.bold: true }
                                        Text { text: installerBackend.reqPowerOk ? "Alimentación eléctrica: Conectado a la corriente" : "Aviso: batería baja en el portátil"; color: "#ffffff"; font.pixelSize: 12 }
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
                                color: "#ffffff"
                                font.pixelSize: 18
                                font.bold: true
                            }

                            Text {
                                text: "Selecciona tu zona horaria y la distribución de teclado que prefieras."
                                color: "#a1a1aa"
                                font.pixelSize: 12
                            }

                            // Zona horaria
                            Text { text: "Zona Horaria:"; color: "#ffffff"; font.pixelSize: 13; font.bold: true }
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
                            Text { text: "Distribución de Teclado:"; color: "#ffffff"; font.pixelSize: 13; font.bold: true }
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

                            Text { text: "Prueba tu teclado aquí:"; color: "#a1a1aa"; font.pixelSize: 12 }
                            TextField {
                                width: parent.width
                                placeholderText: "Escribe aquí para verificar caracteres: ñ, á, @, #, €..."
                                color: "#ffffff"
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
                                    color: "#ffffff"
                                    font.pixelSize: 18
                                    font.bold: true
                                }

                                Text {
                                    text: "Elige la unidad donde se instalará Solaris Linux y el esquema de particionado."
                                    color: "#a1a1aa"
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
                                        color: installerBackend.selectedDiskIndex === index ? Qt.rgba(0, 0.48, 1, 0.25) : Qt.rgba(1, 1, 1, 0.05)
                                        border.color: installerBackend.selectedDiskIndex === index ? "#007aff" : Qt.rgba(1, 1, 1, 0.12)
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
                                                    text: modelData.path + " — " + modelData.size + " (" + modelData.tran + ")"
                                                    color: "#ffffff"
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                }
                                                Text {
                                                    text: modelData.model
                                                    color: "#8e8e93"
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
                                    color: "#ffffff"
                                    font.pixelSize: 13
                                    font.bold: true
                                }

                                // Opción 1: Borrar disco completo
                                Rectangle {
                                    width: parent.width
                                    height: 50
                                    radius: 8
                                    color: !installerBackend.manualPartitioning ? Qt.rgba(0, 0.48, 1, 0.2) : Qt.rgba(1, 1, 1, 0.05)
                                    border.color: !installerBackend.manualPartitioning ? "#007aff" : Qt.rgba(1, 1, 1, 0.12)

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
                                                color: "#ffffff"
                                                font.pixelSize: 12
                                                font.bold: true
                                            }
                                            Text {
                                                text: "Crea automáticamente la partición EFI (/boot/efi de 512M) y la partición Raíz (/)."
                                                color: "#a1a1aa"
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
                                    Text { text: "Sistema de archivos:"; color: "#ffffff"; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12 }
                                    ComboBox {
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
                                    color: installerBackend.manualPartitioning ? Qt.rgba(0, 0.48, 1, 0.2) : Qt.rgba(1, 1, 1, 0.05)
                                    border.color: installerBackend.manualPartitioning ? "#007aff" : Qt.rgba(1, 1, 1, 0.12)

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
                                                color: "#ffffff"
                                                font.pixelSize: 12
                                                font.bold: true
                                            }
                                            Text {
                                                text: "Configura tus propias particiones, puntos de montaje (/boot/efi, /, /home) y tamaños."
                                                color: "#a1a1aa"
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
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                        radius: 4
                                        Row {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            Text { width: 140; text: "Punto de Montaje"; color: "#a1a1aa"; font.pixelSize: 11; font.bold: true }
                                            Text { width: 120; text: "Tamaño (MiB)"; color: "#a1a1aa"; font.pixelSize: 11; font.bold: true }
                                            Text { width: 110; text: "Formato"; color: "#a1a1aa"; font.pixelSize: 11; font.bold: true }
                                            Text { text: "Acción"; color: "#a1a1aa"; font.pixelSize: 11; font.bold: true }
                                        }
                                    }

                                    // Lista de particiones manuales
                                    Repeater {
                                        model: installerBackend.manualPartitions
                                        delegate: Rectangle {
                                            width: parent.width
                                            height: 40
                                            radius: 6
                                            color: Qt.rgba(1, 1, 1, 0.04)
                                            border.color: Qt.rgba(1, 1, 1, 0.08)

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
                                                TextField {
                                                    width: 112
                                                    text: modelData.size === 0 ? "Restante" : modelData.size.toString()
                                                    color: "#ffffff"
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
                                                Button {
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
                                        Button {
                                            text: "+ Añadir Partición"
                                            onClicked: installerBackend.addManualPartition("/home", 10240, "ext4")
                                        }
                                        Button {
                                            text: "Restablecer esquema recomendado"
                                            onClicked: installerBackend.resetDefaultPartitions()
                                        }
                                        Button {
                                            text: "Particionador Externo (GParted)"
                                            onClicked: installerBackend.openExternalPartitioner()
                                        }
                                    }

                                    // Validación del esquema
                                    Text {
                                        text: installerBackend.validatePartitionPlan()
                                        color: "#ff3b30"
                                        font.pixelSize: 11
                                        font.bold: true
                                        visible: text !== ""
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 34
                                    radius: 6
                                    color: Qt.rgba(1, 0.23, 0.19, 0.15)
                                    border.color: "#ff3b30"
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Text { text: "⚠"; color: "#ff3b30"; font.bold: true }
                                        Text { text: "Se borrarán los datos contenidos en el disco seleccionado."; color: "#ffffff"; font.pixelSize: 11 }
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
                                color: "#ffffff"
                                font.pixelSize: 18
                                font.bold: true
                            }

                            Text { text: "¿Cuál es tu nombre?"; color: "#ffffff"; font.pixelSize: 12 }
                            TextField {
                                id: fullNameField
                                width: parent.width
                                text: "Usuario Solaris"
                                color: "#ffffff"
                            }

                            Text { text: "Nombre de usuario (para inicio de sesión):"; color: "#ffffff"; font.pixelSize: 12 }
                            TextField {
                                id: userField
                                width: parent.width
                                text: "solaris"
                                color: "#ffffff"
                            }

                            Text { text: "Nombre del equipo (Hostname):"; color: "#ffffff"; font.pixelSize: 12 }
                            TextField {
                                id: hostnameField
                                width: parent.width
                                text: "solaris-pc"
                                color: "#ffffff"
                            }

                            Row {
                                spacing: 16
                                width: parent.width
                                Column {
                                    width: parent.width / 2 - 8
                                    spacing: 4
                                    Text { text: "Contraseña:"; color: "#ffffff"; font.pixelSize: 12 }
                                    TextField {
                                        id: passField
                                        width: parent.width
                                        text: "1234"
                                        echoMode: TextInput.Password
                                        color: "#ffffff"
                                    }
                                }
                                Column {
                                    width: parent.width / 2 - 8
                                    spacing: 4
                                    Text { text: "Confirmar contraseña:"; color: "#ffffff"; font.pixelSize: 12 }
                                    TextField {
                                        id: confirmPassField
                                        width: parent.width
                                        text: "1234"
                                        echoMode: TextInput.Password
                                        color: "#ffffff"
                                    }
                                }
                            }

                            CheckBox {
                                text: "Iniciar sesión automáticamente sin solicitar contraseña"
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
                                color: "#ffffff"
                                font.pixelSize: 18
                                font.bold: true
                            }

                            Text {
                                text: "Por favor revisa la configuración antes de proceder con el formateo e instalación."
                                color: "#a1a1aa"
                                font.pixelSize: 12
                            }

                            Rectangle {
                                width: parent.width
                                height: 160
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.color: Qt.rgba(1, 1, 1, 0.12)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 10

                                    Text { text: "• Disco de destino: " + installerBackend.selectedDiskName; color: "#ffffff"; font.bold: true }
                                    Text { text: "• Particionamiento: " + (installerBackend.manualPartitioning ? ("Manual (" + installerBackend.manualPartitions.length + " particiones configuradas)") : ("Automático (" + window.selectedFs + ")")); color: "#ffffff" }
                                    Text { text: "• Modo de arranque: " + (installerBackend.isUefi ? "UEFI (GPT)" : "BIOS Legacy (MBR)"); color: "#ffffff" }
                                    Text { text: "• Usuario: " + userField.text + " (" + hostnameField.text + ")"; color: "#ffffff" }
                                    Text { text: "• Región y Teclado: " + window.selectedTimezone + " / " + window.selectedKeymap; color: "#ffffff" }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 42
                                radius: 6
                                color: Qt.rgba(1, 0.23, 0.19, 0.2)
                                border.color: "#ff3b30"
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text { text: "⚠"; color: "#ff3b30"; font.bold: true; font.pixelSize: 16 }
                                    Text { text: "Al pulsar 'Instalar Ahora' se aplicarán los cambios permanentemente en el disco."; color: "#ffffff"; font.pixelSize: 12 }
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
                                text: "Instalando Solaris Linux..."
                                color: "#ffffff"
                                font.pixelSize: 20
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            // Barra de progreso
                            Rectangle {
                                width: parent.width
                                height: 12
                                radius: 6
                                color: Qt.rgba(1, 1, 1, 0.1)

                                Rectangle {
                                    width: parent.width * (installerBackend.progressPercent / 100.0)
                                    height: parent.height
                                    radius: 6
                                    color: "#007aff"
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
                                    color: "#a1a1aa"
                                    font.pixelSize: 12
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: installerBackend.progressPercent + "%"
                                    color: "#ffffff"
                                    font.bold: true
                                    font.pixelSize: 12
                                }
                            }

                            Text {
                                visible: installerBackend.errorMessage !== ""
                                text: "Error: " + installerBackend.errorMessage
                                color: "#ff3b30"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                width: parent.width
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
                                color: "#34c759"
                                anchors.horizontalCenter: parent.horizontalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: "#ffffff"
                                    font.pixelSize: 32
                                    font.bold: true
                                }
                            }

                            Text {
                                text: "¡Instalación Completada!"
                                color: "#ffffff"
                                font.pixelSize: 22
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                text: "Inti OS se ha instalado con éxito en tu ordenador. Se ha configurado el arranque UEFI de tu disco como prioridad 1. Puedes retirar el medio USB y reiniciar el equipo para comenzar a utilizar tu nuevo sistema operativo."
                                color: "#a1a1aa"
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                width: parent.width
                            }

                            Row {
                                spacing: 14
                                anchors.horizontalCenter: parent.horizontalCenter

                                Button {
                                    text: "Continuar Probando"
                                    onClicked: installerBackend.closeInstaller()
                                }

                                Button {
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

                    Button {
                        text: "Cancelar"
                        onClicked: installerBackend.closeInstaller()
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "Atrás"
                        visible: installerBackend.currentStep > 0
                        onClicked: installerBackend.currentStep--
                    }

                    Button {
                        text: installerBackend.currentStep === 4 ? "Instalar Ahora" : "Siguiente"
                        highlighted: true
                        enabled: {
                            if (installerBackend.currentStep === 0) return installerBackend.reqRamOk && installerBackend.reqDiskOk;
                            if (installerBackend.currentStep === 2) return installerBackend.disks.length > 0;
                            if (installerBackend.currentStep === 3) return userField.text.length > 0 && passField.text.length > 0 && passField.text === confirmPassField.text;
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
