import QtQuick 2.15

QtObject {
    id: theme

    // Modo de vidrio translúcido (Frosted Glass / Vidrio acrílico sin color sólido)
    // Se enlaza dinámicamente al gestor central de temas si está disponible
    property bool isDark: (typeof titanThemeManager !== "undefined") ? titanThemeManager.isDark : false

    // Fondo general de la ventana de cristal (translúcido con degradado acrílico)
    readonly property color windowBgTop: isDark ? Qt.rgba(0.16, 0.18, 0.25, 0.76) : Qt.rgba(0.96, 0.97, 1.0, 0.78)
    readonly property color windowBgMid: isDark ? Qt.rgba(0.11, 0.13, 0.18, 0.72) : Qt.rgba(0.92, 0.94, 0.98, 0.72)
    readonly property color windowBgBottom: isDark ? Qt.rgba(0.08, 0.10, 0.15, 0.78) : Qt.rgba(0.88, 0.90, 0.95, 0.76)

    // Borde fino de cristal reflectante y brillo especular
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.24)
    readonly property color specularGlow: Qt.rgba(1, 1, 1, 0.40)

    // Barra superior / Toolbar (panel normal con degradado blur translúcido)
    readonly property color headerTop: isDark ? Qt.rgba(0.20, 0.23, 0.32, 0.78) : Qt.rgba(0.98, 0.98, 1.0, 0.82)
    readonly property color headerBottom: isDark ? Qt.rgba(0.14, 0.16, 0.24, 0.72) : Qt.rgba(0.92, 0.93, 0.97, 0.76)
    readonly property color headerBorder: isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.12)
    readonly property color headerText: isDark ? "#ffffff" : "#1d1d1f"

    // Barra lateral / Sidebar (translúcido acrílico)
    readonly property color sidebarTop: isDark ? Qt.rgba(0.12, 0.14, 0.20, 0.65) : Qt.rgba(0.95, 0.96, 0.98, 0.65)
    readonly property color sidebarBottom: isDark ? Qt.rgba(0.08, 0.10, 0.16, 0.60) : Qt.rgba(0.90, 0.92, 0.95, 0.60)
    readonly property color sidebarBorder: isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color sidebarText: isDark ? "#f0f2f8" : "#2c2c2e"
    readonly property color sidebarTextMuted: isDark ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(0, 0, 0, 0.50)

    // Contenido central de cristal translúcido (SIN COLOR SÓLIDO OPACO)
    readonly property color contentBackground: isDark ? Qt.rgba(0.09, 0.11, 0.16, 0.65) : Qt.rgba(1.0, 1.0, 1.0, 0.65)
    readonly property color contentCardBg: isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.45)
    readonly property color contentCardBorder: isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color contentTextPrimary: isDark ? "#ffffff" : "#1d1d1f"
    readonly property color contentTextSecondary: isDark ? "#a2aab8" : "#6e6e73"

    // Acentos y estados de selección estilo macOS
    readonly property color accent: "#0071e3"
    readonly property color accentHover: "#0077ed"
    readonly property color selectionBg: isDark ? Qt.rgba(0.0, 0.44, 0.89, 0.45) : Qt.rgba(0.0, 0.44, 0.89, 0.20)
    readonly property color itemHover: isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

    // Radios de esquina
    readonly property int windowRadius: 14
    readonly property int controlRadius: 8
}
