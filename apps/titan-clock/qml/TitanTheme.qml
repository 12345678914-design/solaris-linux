import QtQuick 2.15

QtObject {
    id: theme

    // Modo de vidrio translúcido (Frosted Glass / Vidrio acrílico sin color sólido)
    // Se enlaza dinámicamente al gestor central de temas si está disponible
    property bool isDark: (typeof titanThemeManager !== "undefined") ? titanThemeManager.isDark : false

    // Ventanas de las apps OPACAS (como Windows 11 y el Finder de macOS Tahoe):
    // se leen mejor y la gráfica no tiene que mezclar lo de detrás. El vidrio
    // queda para el Dock, la barra superior y el Launchpad (GlassPanel).
    readonly property bool opaco: true

    // Fondo general de la ventana
    readonly property color windowBgTop: isDark ? "#1f2025" : "#f2f2f5"
    readonly property color windowBgMid: isDark ? "#1f2025" : "#f2f2f5"
    readonly property color windowBgBottom: isDark ? "#1f2025" : "#f2f2f5"

    // Borde fino de cristal reflectante y brillo especular
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.24)
    readonly property color specularGlow: Qt.rgba(1, 1, 1, 0.40)

    // Barra superior / Toolbar (a juego con la barra lateral)
    readonly property color headerTop: isDark ? "#26272c" : "#ebebef"
    readonly property color headerBottom: isDark ? "#26272c" : "#ebebef"
    readonly property color headerBorder: isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.12)
    readonly property color headerText: isDark ? "#ffffff" : "#1d1d1f"
    readonly property color headerTextMuted: isDark ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(0, 0, 0, 0.50)

    // Barra lateral (gris sólido, un poco distinto del contenido)
    readonly property color sidebarTop: isDark ? "#26272c" : "#ebebef"
    readonly property color sidebarBottom: isDark ? "#26272c" : "#ebebef"
    readonly property color sidebarBorder: isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color sidebarText: isDark ? "#f0f2f8" : "#2c2c2e"
    readonly property color sidebarTextMuted: isDark ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(0, 0, 0, 0.50)

    // Contenido central (blanco / gris oscuro) y tarjetas sobre él
    readonly property color contentBackground: isDark ? "#1c1d21" : "#ffffff"
    readonly property color contentCardBg: isDark ? "#2a2b30" : "#ffffff"
    readonly property color contentCardBorder: isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color contentTextPrimary: isDark ? "#ffffff" : "#1d1d1f"
    readonly property color contentTextSecondary: isDark ? "#a2aab8" : "#6e6e73"

    // Acentos y estados de selección estilo macOS
    // El acento lo elige el usuario en Ajustes (ThemeManager); si no hay gestor, azul.
    readonly property color accent: (typeof titanThemeManager !== "undefined" && titanThemeManager.accent) ? titanThemeManager.accent : "#0071e3"
    readonly property color accentHover: Qt.lighter(accent, 1.08)

    // Carpetas e icono del Finder con el color de acento (proveedor
    // "image://tinte", TitanTinte.h; lo registran el Finder y el shell).
    // Con el azul de serie se deja el PNG original.
    function tinte(src) {
        var s = String(src)
        if (!/\/icons\/(folder|desktop|downloads|apps-folder|music-folder|finder)\.png$/.test(s))
            return s
        var a = String(accent).toLowerCase()
        if (a === "#0071e3")
            return s
        // qrc:/icons/x.png -> /icons/x.png ; file:///usr/... -> /usr/... (TitanTinte
        // prueba primero el recurso interno y luego el fichero del disco)
        return "image://tinte/" + a.substring(1) + s.replace(/^qrc:/, "").replace(/^file:\/\//, "")
    }
    readonly property color selectionBg: Qt.rgba(accent.r, accent.g, accent.b, isDark ? 0.45 : 0.20)
    readonly property color itemHover: isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

    // Radios de esquina, concéntricos (estilo Tahoe): un elemento dentro de otro
    // lleva radio = radio_exterior - margen, para que las curvas sean paralelas.
    // windowRadius coincide con <cornerRadius> de labwc (rc.xml).
    readonly property int windowRadius: 16
    readonly property int cardRadius: 12
    readonly property int controlRadius: 8
    readonly property int innerMargin: windowRadius - cardRadius   // 4
    function concentric(outerRadius, margin) { return Math.max(0, outerRadius - margin) }

    // Tipografía. Inter es la fuente del sistema (fontconfig: sans-serif = Inter).
    readonly property string fontFamily: "Inter"
    readonly property string monoFamily: "JetBrains Mono"
    readonly property int fontCaption: 11
    readonly property int fontBody: 13
    readonly property int fontHeadline: 15
    readonly property int fontTitle: 20
    readonly property int fontLargeTitle: 26

    // Efectos (vidrio, sombras, muelles). Con el backend por software (VMs,
    // modo compatibilidad) se apagan: se dibuja plano, que es mucho más barato.
    // Lo fija quien crea el tema desde un Item (GraphicsInfo solo funciona en Items):
    //   TitanTheme { effects: algunItem.GraphicsInfo.api !== GraphicsInfo.Software }
    property bool effects: true
}
