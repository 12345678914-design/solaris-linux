#include "TitanBinary.h"
#include "LauncherBackend.h"
#include <QCollator>
#include <QLocale>
#include <QHash>
#include <algorithm>
#include "TitanIconoSvg.h"
#include "TitanDesktopEntry.h"
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QHash>
#include <QRegularExpression>
#include <QSet>
#include <QProcess>
#include <QFileSystemWatcher>
#include <QUrl>
#include <QDebug>
#include <QStandardPaths>
#include <QCoreApplication>

LauncherBackend::LauncherBackend(QObject *parent)
    : QObject(parent)
    , m_watcher(new QFileSystemWatcher(this))
{
    loadApps();

    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &LauncherBackend::loadApps);
}

LauncherBackend::~LauncherBackend()
{
}

QVariantList LauncherBackend::apps() const
{
    return m_filteredApps;
}

// ---------------------------------------------------------------- categorias
// Orden en que salen en la fila de categorias del Launchpad.
static const QList<QPair<QString, QString>> &ordenCategorias()
{
    static const QList<QPair<QString, QString>> o = {
        {QStringLiteral("productividad"), QStringLiteral("Productividad")},
        {QStringLiteral("internet"), QStringLiteral("Internet")},
        {QStringLiteral("multimedia"), QStringLiteral("Multimedia")},
        {QStringLiteral("educacion"), QStringLiteral("Educación")},
        {QStringLiteral("juegos"), QStringLiteral("Juegos")},
        {QStringLiteral("desarrollo"), QStringLiteral("Desarrollo")},
        {QStringLiteral("utilidades"), QStringLiteral("Utilidades")},
        {QStringLiteral("sistema"), QStringLiteral("Sistema")}};
    return o;
}

// Entradas que no son apps para el usuario (ayudantes de KDE/GNOME, demos,
// visores sueltos, duplicados de apps de Inti OS): no salen nunca. "Abrir
// con" y los tipos de archivo siguen funcionando, solo se quitan del menu.
static bool esInterna(const QString &fichero)
{
    static const QSet<QString> internas = {
        QStringLiteral("org.gnupg.pinentry-qt.desktop"), QStringLiteral("cups.desktop"),
        QStringLiteral("kcm_updates.desktop"), QStringLiteral("kcm_kaccounts.desktop"), QStringLiteral("kcm_fcitx5.desktop"),
        QStringLiteral("org.kde.discover.appstreampreview.desktop"), QStringLiteral("org.kde.discover.flatpak.desktop"),
        QStringLiteral("org.kde.discover.notifier.desktop"), QStringLiteral("org.kde.discover.snap.desktop"),
        QStringLiteral("org.kde.discover.urlhandler.desktop"),
        QStringLiteral("org.gnome.Evolution-alarm-notify.desktop"), QStringLiteral("org.gnome.evolution-data-server.OAuth2-handler.desktop"),
        QStringLiteral("fcitx5-wayland-launcher.desktop"), QStringLiteral("org.fcitx.Fcitx5.desktop"),
        QStringLiteral("org.fcitx.fcitx5-migrator.desktop"), QStringLiteral("kbd-layout-viewer5.desktop"),
        QStringLiteral("org.fcitx.fcitx5-qt5-gui-wrapper.desktop"), QStringLiteral("org.fcitx.fcitx5-qt6-gui-wrapper.desktop"),
        QStringLiteral("gcr-prompter.desktop"), QStringLiteral("gcr-viewer.desktop"),
        QStringLiteral("geoclue-demo-agent.desktop"), QStringLiteral("geoclue-where-am-i.desktop"),
        QStringLiteral("gnome-disk-image-mounter.desktop"), QStringLiteral("gnome-disk-image-writer.desktop"),
        QStringLiteral("gnome-system-monitor-kde.desktop"), QStringLiteral("htop.desktop"), QStringLiteral("lstopo.desktop"),
        QStringLiteral("cartes-geo-handler.desktop"), QStringLiteral("google-maps-geo-handler.desktop"),
        QStringLiteral("openstreetmap-geo-handler.desktop"), QStringLiteral("wheelmap-geo-handler.desktop"),
        QStringLiteral("ktelnetservice6.desktop"), QStringLiteral("org.kde.kiod6.desktop"),
        QStringLiteral("kitty.desktop"), QStringLiteral("kitty-open.desktop"), QStringLiteral("org.kde.knewstuff-dialog6.desktop"),
        QStringLiteral("org.kde.ksecretd.desktop"), QStringLiteral("org.kde.kwalletd.desktop"),
        QStringLiteral("gkbd-keyboard-display.desktop"), QStringLiteral("mpv.desktop"), QStringLiteral("org.gnome.Totem.desktop"),
        QStringLiteral("signon-ui.desktop"), QStringLiteral("stoken-gui.desktop"), QStringLiteral("stoken-gui-small.desktop"),
        QStringLiteral("qv4l2.desktop"), QStringLiteral("qvidcap.desktop"), QStringLiteral("vim.desktop"),
        QStringLiteral("xdg-desktop-portal-gtk.desktop"), QStringLiteral("org.freedesktop.Xwayland.desktop"),
        QStringLiteral("pcmanfm-qt.desktop"), QStringLiteral("pcmanfm-qt-desktop-pref.desktop"), QStringLiteral("orca.desktop"),
        // Apps de clase: se deja la principal de cada suite
        QStringLiteral("calibre-ebook-edit.desktop"), QStringLiteral("calibre-ebook-viewer.desktop"),
        QStringLiteral("calibre-lrfviewer.desktop"), QStringLiteral("xgps.desktop"), QStringLiteral("xgpsspeed.desktop"),
        QStringLiteral("java-java-openjdk.desktop"), QStringLiteral("jconsole-java-openjdk.desktop"),
        QStringLiteral("jshell-java-openjdk.desktop"), QStringLiteral("org.kde.kalzium_cml.desktop"),
        QStringLiteral("libreoffice-startcenter.desktop"), QStringLiteral("libreoffice-xsltfilter.desktop"),
        QStringLiteral("libreoffice-base.desktop"), QStringLiteral("libreoffice-math.desktop"),
        QStringLiteral("com.github.rlancaste.stellarsolver.desktop"), QStringLiteral("xdvi.desktop"),
        // Las ventanas de hplip piden PyQt5 (no va en la ISO); las HP se
        // anaden desde Impresoras (system-config-printer) como las demas.
        QStringLiteral("hplip.desktop"), QStringLiteral("hp-uiscan.desktop")};
    return internas.contains(fichero);
}

// Herramientas de administracion: no salen en "Todas", si en "Sistema" y al
// buscar (como las carpetas Utilidades/Sistema de macOS y GNOME).
static bool esHerramienta(const QString &fichero, const QString &exec)
{
    static const QSet<QString> h = {
        QStringLiteral("org.gnome.DiskUtility.desktop"), QStringLiteral("gparted.desktop"),
        QStringLiteral("org.gnome.SystemMonitor.desktop"), QStringLiteral("btrfs-assistant.desktop"),
        QStringLiteral("timeshift-gtk.desktop"), QStringLiteral("system-config-printer.desktop"),
        QStringLiteral("nvidia-settings.desktop"), QStringLiteral("org.pulseaudio.pavucontrol.desktop"),
        QStringLiteral("org.fcitx.fcitx5-config-qt.desktop"), QStringLiteral("fcitx5-configtool.desktop"),
        QStringLiteral("titan-teclado.desktop")};
    return h.contains(fichero) || exec.startsWith(QStringLiteral("titan-teclado"));
}

static QString categoriaDe(const QString &fichero, const QString &exec, const QString &categories)
{
    // Apps de Inti OS y algunas cuyo Categories engaña
    static const QHash<QString, QString> fijas = {
        {QStringLiteral("titan-finder"), QStringLiteral("utilidades")}, {QStringLiteral("titan-terminal"), QStringLiteral("utilidades")},
        {QStringLiteral("titan-calc"), QStringLiteral("utilidades")}, {QStringLiteral("titan-clock"), QStringLiteral("utilidades")},
        {QStringLiteral("titan-grabar"), QStringLiteral("utilidades")}, {QStringLiteral("titan-calendar"), QStringLiteral("productividad")},
        {QStringLiteral("titan-fotos"), QStringLiteral("multimedia")}, {QStringLiteral("titan-musica"), QStringLiteral("multimedia")},
        {QStringLiteral("titan-video"), QStringLiteral("multimedia")}, {QStringLiteral("firefox"), QStringLiteral("internet")},
        {QStringLiteral("onlyoffice-desktopeditors"), QStringLiteral("productividad")},
        {QStringLiteral("plasma-discover"), QStringLiteral("sistema")}, {QStringLiteral("titan-settings"), QStringLiteral("sistema")},
        {QStringLiteral("titan-acerca"), QStringLiteral("sistema")}, {QStringLiteral("titan-installer"), QStringLiteral("sistema")},
        {QStringLiteral("titan-instalar"), QStringLiteral("sistema")},
        {QStringLiteral("simple-scan"), QStringLiteral("utilidades")}, {QStringLiteral("joplin-desktop"), QStringLiteral("productividad")},
        {QStringLiteral("obsidian"), QStringLiteral("productividad")}, {QStringLiteral("openboard"), QStringLiteral("educacion")},
        {QStringLiteral("xournalpp"), QStringLiteral("educacion")}, {QStringLiteral("calibre"), QStringLiteral("productividad")}};
    QString prog = exec.section(QLatin1Char(' '), 0, 0);
    prog = prog.mid(prog.lastIndexOf(QLatin1Char('/')) + 1);
    if (fijas.contains(prog))
        return fijas.value(prog);
    if (fichero.startsWith(QStringLiteral("titan-instalar")))
        return QStringLiteral("sistema");

    const QStringList c = categories.split(QLatin1Char(';'), Qt::SkipEmptyParts);
    auto tiene = [&c](std::initializer_list<const char *> l) {
        for (const char *x : l)
            if (c.contains(QLatin1String(x)))
                return true;
        return false;
    };
    if (tiene({"Education", "Science", "Math", "Astronomy", "Chemistry", "Geography", "Languages", "Geometry"}))
        return QStringLiteral("educacion");
    if (tiene({"Game"}))
        return QStringLiteral("juegos");
    if (tiene({"Settings", "System", "HardwareSettings", "PackageManager", "Monitor", "Printing", "Security"}))
        return QStringLiteral("sistema");
    if (tiene({"Development", "IDE"}))
        return QStringLiteral("desarrollo");
    if (tiene({"Office", "TextEditor", "WordProcessor", "Spreadsheet", "Presentation", "Calendar", "ContactManagement", "Publishing"}))
        return QStringLiteral("productividad");
    if (tiene({"Network", "WebBrowser", "Email", "Chat", "InstantMessaging", "FileTransfer"}))
        return QStringLiteral("internet");
    if (tiene({"AudioVideo", "Audio", "Video", "Graphics", "Photography", "Player", "Recorder"}))
        return QStringLiteral("multimedia");
    return QStringLiteral("utilidades");
}

void LauncherBackend::setCategoria(const QString &c)
{
    if (c == m_categoria)
        return;
    m_categoria = c;
    filtrar();
}

void LauncherBackend::filtrar()
{
    m_filteredApps.clear();
    const QString q = m_busqueda.trimmed();
    for (const auto &v : std::as_const(m_apps)) {
        const QVariantMap app = v.toMap();
        if (!q.isEmpty()) {
            // Al buscar se mira en todas, tambien las del sistema
            if (app.value(QStringLiteral("name")).toString().contains(q, Qt::CaseInsensitive)
                || app.value(QStringLiteral("generico")).toString().contains(q, Qt::CaseInsensitive))
                m_filteredApps.append(app);
        } else if (m_categoria == QStringLiteral("todas")) {
            if (!app.value(QStringLiteral("herramienta")).toBool())
                m_filteredApps.append(app);
        } else if (app.value(QStringLiteral("categoria")).toString() == m_categoria) {
            m_filteredApps.append(app);
        }
    }
    emit appsChanged();
}

void LauncherBackend::reload()
{
    loadApps();
}

void LauncherBackend::loadApps()
{
    m_apps.clear();
    QSet<QString> seenExecs;
    QSet<QString> seenNames;

    // Aplicaciones principales integradas de Titan Linux
    auto addApp = [this, &seenExecs, &seenNames](const QString &name, const QString &exec, const QString &icon) {
        if (seenExecs.contains(exec)) return;
        seenExecs.insert(exec);
        seenNames.insert(name.trimmed().toLower());

        QVariantMap app;
        app[QStringLiteral("name")] = name;
        app[QStringLiteral("exec")] = exec;
        app[QStringLiteral("icon")] = icon;
        app[QStringLiteral("categoria")] = categoriaDe(QString(), exec, QString());
        app[QStringLiteral("herramienta")] = false;
        m_apps.append(app);
    };

    // Devuelve "" si no encuentra nada: quien llama genera un icono SVG.
    auto resolverIcono = [](QString icono, const QString &exec) -> QString {
        if (icono.startsWith(QStringLiteral("qrc:/"))) {
            return icono;
        }
        if (icono.startsWith(QLatin1Char('/'))) {
            if (titan::iconoExiste(icono))
                return QUrl::fromLocalFile(icono).toString();
            // Ruta rota (app desinstalada a medias): se busca por el nombre.
            icono = QFileInfo(icono).completeBaseName();
        }
        // Icon=nombre.png: los temas guardan el nombre sin extension.
        icono.remove(QRegularExpression(QStringLiteral("\\.(png|svg|xpm)$"), QRegularExpression::CaseInsensitiveOption));
        if (icono.isEmpty())
            return QString();

        // Buscar en rutas comunes de iconos del sistema (Pacman y Flatpak)
        static const QStringList iconSearchPaths = {
            QStringLiteral("/usr/share/icons/hicolor/128x128/apps/"),
            QStringLiteral("/usr/share/icons/hicolor/256x256/apps/"),
            QStringLiteral("/usr/share/icons/hicolor/scalable/apps/"),
            QStringLiteral("/usr/share/icons/hicolor/64x64/apps/"),
            QStringLiteral("/usr/share/icons/hicolor/48x48/apps/"),
            QStringLiteral("/var/lib/flatpak/exports/share/icons/hicolor/128x128/apps/"),
            QStringLiteral("/var/lib/flatpak/exports/share/icons/hicolor/scalable/apps/"),
            QStringLiteral("/usr/share/pixmaps/"),
            QStringLiteral("/usr/share/titan/icons/")
        };

        for (const QString &path : iconSearchPaths) {
            QString fullPng = path + icono + QStringLiteral(".png");
            if (QFile::exists(fullPng)) return QUrl::fromLocalFile(fullPng).toString();
            QString fullSvg = path + icono + QStringLiteral(".svg");
            if (QFile::exists(fullSvg)) return QUrl::fromLocalFile(fullSvg).toString();
        }

        // Mapeo a iconos de estilo macOS
        QString lower = icono.toLower();
        QString execLower = exec.toLower();
        if (lower.contains(QStringLiteral("calc")) || execLower.contains(QStringLiteral("calc")))
            return QStringLiteral("file:///usr/share/titan/icons/calculator.png");
        if (lower.contains(QStringLiteral("calendar")) || execLower.contains(QStringLiteral("calendar")))
            return QStringLiteral("file:///usr/share/titan/icons/calendar.png");
        if (lower.contains(QStringLiteral("clock")) || execLower.contains(QStringLiteral("clock")))
            return QStringLiteral("file:///usr/share/titan/icons/clock.png");
        if (lower.contains(QStringLiteral("celluloid")) || execLower.contains(QStringLiteral("celluloid")) || lower.contains(QStringLiteral("video")))
            return QStringLiteral("file:///usr/share/titan/icons/video.png");
        if (lower.contains(QStringLiteral("software")) || execLower.contains(QStringLiteral("software")))
            return QStringLiteral("file:///usr/share/titan/icons/apps-folder.png");
        if (lower.contains(QStringLiteral("terminal")) || execLower.contains(QStringLiteral("terminal")) || execLower.contains(QStringLiteral("kitty")))
            return QStringLiteral("qrc:/icons/terminal.png");
        if (lower.contains(QStringLiteral("firefox")) || lower.contains(QStringLiteral("browser")) || execLower.contains(QStringLiteral("firefox")) || execLower.contains(QStringLiteral("chrome")))
            return QStringLiteral("qrc:/icons/firefox.png");
        if (lower.contains(QStringLiteral("vim")) || execLower.contains(QStringLiteral("vim")))
            return QStringLiteral("qrc:/icons/developer.png");
        if (lower.contains(QStringLiteral("htop")) || execLower.contains(QStringLiteral("htop")) || lower.contains(QStringLiteral("top")) || execLower.contains(QStringLiteral("top")))
            return QStringLiteral("qrc:/icons/system.png");
        if (lower.contains(QStringLiteral("code")) || execLower.contains(QStringLiteral("code")) || execLower.contains(QStringLiteral("editor")))
            return QStringLiteral("qrc:/icons/vscode.png");
        if (lower.contains(QStringLiteral("file")) || lower.contains(QStringLiteral("folder")) || execLower.contains(QStringLiteral("fm")) || execLower.contains(QStringLiteral("pcmanfm")))
            return QStringLiteral("qrc:/icons/files.png");
        if (lower.contains(QStringLiteral("about")) || lower.contains(QStringLiteral("info")))
            return QStringLiteral("qrc:/icons/about.png");
        if (lower.contains(QStringLiteral("system")) || lower.contains(QStringLiteral("setting")) || lower.contains(QStringLiteral("control")) || lower.contains(QStringLiteral("config")))
            return QStringLiteral("qrc:/icons/system.png");
        if (lower.contains(QStringLiteral("music")) || lower.contains(QStringLiteral("audio")) || lower.contains(QStringLiteral("player")) || lower.contains(QStringLiteral("spotify")))
            return QStringLiteral("qrc:/icons/music.png");
        if (lower.contains(QStringLiteral("image")) || lower.contains(QStringLiteral("photo")) || lower.contains(QStringLiteral("picture")) || lower.contains(QStringLiteral("gimp")))
            return QStringLiteral("qrc:/icons/pictures.png");
        if (lower.contains(QStringLiteral("edit")) || lower.contains(QStringLiteral("notes")) || lower.contains(QStringLiteral("text")))
            return QStringLiteral("qrc:/icons/notes.png");
        if (lower.contains(QStringLiteral("trash")))
            return QStringLiteral("qrc:/icons/trash.png");
        if (lower.contains(QStringLiteral("dev")) || lower.contains(QStringLiteral("build")) || execLower.contains(QStringLiteral("gcc")) || execLower.contains(QStringLiteral("clang")) || execLower.contains(QStringLiteral("cmake")))
            return QStringLiteral("qrc:/icons/developer.png");

        return QString();
    };

    // Las apps propias de Inti OS van primero: así ganan la deduplicación por
    // nombre frente a las de GNOME (que también vienen en la ISO como respaldo).
    addApp(QStringLiteral("Finder"), QStringLiteral("titan-finder"), QStringLiteral("qrc:/icons/finder.png"));
    addApp(QStringLiteral("Firefox"), QStringLiteral("firefox"), QStringLiteral("qrc:/icons/firefox.png"));
    addApp(QStringLiteral("Fotos"), QStringLiteral("titan-fotos"), QStringLiteral("qrc:/icons/pictures.png"));
    addApp(QStringLiteral("Música"), QStringLiteral("titan-musica"), QStringLiteral("qrc:/icons/music-app.png"));
    addApp(QStringLiteral("Terminal"), QStringLiteral("titan-terminal"), QStringLiteral("qrc:/icons/terminal.png"));
    addApp(QStringLiteral("Calculadora"), QStringLiteral("titan-calc"), QStringLiteral("file:///usr/share/titan/icons/calculator.png"));
    addApp(QStringLiteral("Calendario"), QStringLiteral("titan-calendar"), QStringLiteral("file:///usr/share/titan/icons/calendar.png"));
    addApp(QStringLiteral("Reloj"), QStringLiteral("titan-clock"), QStringLiteral("file:///usr/share/titan/icons/clock.png"));
    addApp(QStringLiteral("Reproductor de Video"), QStringLiteral("titan-video"), QStringLiteral("file:///usr/share/titan/icons/video.png"));
    addApp(QStringLiteral("App Store"), QStringLiteral("plasma-discover"), QStringLiteral("file:///usr/share/titan/icons/apps-folder.png"));
    addApp(QStringLiteral("Ajustes del Sistema"), QStringLiteral("titan-settings"), QStringLiteral("qrc:/icons/system.png"));
    addApp(QStringLiteral("ONLYOFFICE"), QStringLiteral("onlyoffice-desktopeditors"), QStringLiteral("qrc:/icons/onlyoffice.png"));
    addApp(QStringLiteral("Acerca de Inti OS"), QStringLiteral("titan-acerca"), QStringLiteral("qrc:/icons/about.png"));

    // Directorios de aplicaciones: Pacman (sistema), Local y Flatpak
    const QStringList directorios = {
        QStringLiteral("/usr/share/applications"),
        QStringLiteral("/usr/local/share/applications"),
        QStringLiteral("/var/lib/flatpak/exports/share/applications"),
        QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share/applications"),
        QDir::homePath() + QStringLiteral("/.local/share/applications")
    };

    // Registrar observadores en los directorios para auto-actualización en vivo
    for (const QString &dirRuta : directorios) {
        if (QDir(dirRuta).exists() && !m_watcher->directories().contains(dirRuta)) {
            m_watcher->addPath(dirRuta);
        }
    }

    for (const QString &dirRuta : directorios) {
        QDir dir(dirRuta);
        if (!dir.exists()) continue;

        const auto entradas = dir.entryInfoList(QStringList() << QStringLiteral("*.desktop"), QDir::Files);
        for (const auto &info : entradas) {
            const QHash<QString, QString> ini = titan::leerDesktop(info.absoluteFilePath());
            if (ini.isEmpty()) continue;

            if (titan::esVerdadero(ini.value(QStringLiteral("NoDisplay")))) continue;
            if (esInterna(info.fileName())) continue;
            if (titan::esVerdadero(ini.value(QStringLiteral("Hidden")))) continue;
            if (ini.value(QStringLiteral("Type"), QStringLiteral("Application")) != QStringLiteral("Application")) continue;
            if (ini.contains(QStringLiteral("OnlyShowIn")) && !titan::listaContieneEscritorio(ini.value(QStringLiteral("OnlyShowIn")))) continue;
            if (ini.contains(QStringLiteral("NotShowIn")) && titan::listaContieneEscritorio(ini.value(QStringLiteral("NotShowIn")))) continue;
            // TryExec: si el programa ya no está instalado, la entrada sobra
            const QString tryExec = ini.value(QStringLiteral("TryExec"));
            if (!tryExec.isEmpty()) {
                const bool existe = QDir::isAbsolutePath(tryExec)
                    ? QFileInfo(tryExec).isExecutable()
                    : (!QStandardPaths::findExecutable(tryExec).isEmpty() ||
                       QFileInfo(QStringLiteral("/usr/local/bin/") + tryExec).isExecutable());
                if (!existe) continue;
            }

            // Las versiones de GNOME de apps que Inti OS ya trae (Calculadora,
            // Calendario, Reloj) saldrían repetidas con otro nombre ("Relojes").
            static const QStringList cubiertas = {
                QStringLiteral("org.gnome.Calculator.desktop"),
                QStringLiteral("org.gnome.Calendar.desktop"),
                QStringLiteral("org.gnome.clocks.desktop")
            };
            if (cubiertas.contains(info.fileName())) continue;

            QString nombre = ini.value(QStringLiteral("Name[es]"));
            if (nombre.isEmpty()) nombre = ini.value(QStringLiteral("Name[es_ES]"));
            if (nombre.isEmpty()) nombre = ini.value(QStringLiteral("Name"));

            QString exec = ini.value(QStringLiteral("Exec"));
            QString icono = ini.value(QStringLiteral("Icon"));
            bool inTerminal = titan::esVerdadero(ini.value(QStringLiteral("Terminal")));

            // Quitar parámetros de campo (%u, %F, %k, etc.)
            exec.remove(QRegularExpression(QStringLiteral("%[a-zA-Z]")));
            exec = exec.trimmed();

            if (nombre.isEmpty() || exec.isEmpty()) continue;

            // En un sistema ya instalado no mostrar el instalador
            bool isLive = QDir(QStringLiteral("/run/archiso")).exists();
            if (!isLive) {
                if (nombre.contains(QStringLiteral("Instalar"), Qt::CaseInsensitive) ||
                    exec.contains(QStringLiteral("titan-installer")) ||
                    exec.contains(QStringLiteral("instalar")) ||
                    info.fileName().contains(QStringLiteral("instalar"), Qt::CaseInsensitive) ||
                    info.fileName().contains(QStringLiteral("calamares"), Qt::CaseInsensitive)) {
                    continue;
                }
            }

            if (exec.contains(QLatin1String("pcmanfm")) || info.fileName().contains(QLatin1String("pcmanfm"))) continue;
            if (exec.contains(QLatin1String("kitty")) || info.fileName().contains(QLatin1String("kitty"))) continue;
            if (exec.contains(QLatin1String("alacritty")) || info.fileName().contains(QLatin1String("alacritty"))) continue;
            if (nombre.trimmed().compare(QStringLiteral("Terminal"), Qt::CaseInsensitive) == 0) continue;
            if (seenNames.contains(nombre.trimmed().toLower())) continue;
            if (exec.contains(QLatin1String("noctalia"), Qt::CaseInsensitive) ||
                info.fileName().contains(QLatin1String("noctalia"), Qt::CaseInsensitive) ||
                nombre.contains(QLatin1String("noctalia"), Qt::CaseInsensitive)) continue;
            if (exec.contains(QLatin1String("brightnessctl")) || info.fileName().contains(QLatin1String("brightnessctl"))) continue;
            if (exec.contains(QLatin1String("ddcutil")) || info.fileName().contains(QLatin1String("ddcutil"))) continue;
            if (exec.contains(QLatin1String("cage")) || exec.contains(QLatin1String("labwc"))) continue;

            // Si es una aplicación que requiere terminal (como vim, htop, nano)
            if (inTerminal) {
                if (QFile::exists(QStringLiteral("/usr/bin/kitty"))) {
                    exec = QStringLiteral("kitty ") + exec;
                } else if (QFile::exists(QStringLiteral("/usr/local/bin/titan-terminal"))) {
                    exec = QStringLiteral("titan-terminal -e ") + exec;
                }
            }
            if (seenExecs.contains(exec)) continue;
            seenExecs.insert(exec);

            if (icono.isEmpty()) {
                icono = QStringLiteral("application-x-executable");
            }

            QVariantMap app;
            app[QStringLiteral("name")] = nombre;
            app[QStringLiteral("exec")] = exec;
            QString iconoFinal = resolverIcono(icono, exec);
            if (!titan::iconoExiste(iconoFinal))
                iconoFinal = titan::iconoGenerado(nombre, exec + QLatin1Char(' ') + icono + QLatin1Char(' ') +
                                                              ini.value(QStringLiteral("Categories")));
            app[QStringLiteral("icon")] = iconoFinal;
            // Lo de "Sistema" es herramienta (fuera de "Todas") salvo Ajustes,
            // App Store, Acerca de e Instalar; las de la lista van a "Sistema".
            {
                QString cat = categoriaDe(info.fileName(), exec, ini.value(QStringLiteral("Categories")));
                const bool fija = esHerramienta(info.fileName(), exec);
                static const QStringList visibles = {QStringLiteral("plasma-discover"), QStringLiteral("titan-settings"),
                                                     QStringLiteral("titan-acerca"), QStringLiteral("titan-instalar"),
                                                     QStringLiteral("titan-installer")};
                const QString prog = exec.section(QLatin1Char(' '), 0, 0).section(QLatin1Char('/'), -1);
                if (fija)
                    cat = QStringLiteral("sistema");
                app[QStringLiteral("categoria")] = cat;
                app[QStringLiteral("herramienta")] = fija || (cat == QStringLiteral("sistema") && !visibles.contains(prog)
                                                              && !info.fileName().startsWith(QStringLiteral("titan-instalar")));
            }
            // "Editor de imagenes" encuentra GIMP aunque se llame distinto
            QString generico = ini.value(QStringLiteral("GenericName[es]"));
            if (generico.isEmpty()) generico = ini.value(QStringLiteral("GenericName"));
            app[QStringLiteral("generico")] = generico + QLatin1Char(' ') + ini.value(QStringLiteral("Keywords[es]"));
            m_apps.append(app);
        }
    }

    // Orden alfabetico (sin distinguir tildes ni mayusculas)
    QCollator orden(QLocale(QStringLiteral("es_ES")));
    orden.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(m_apps.begin(), m_apps.end(), [&orden](const QVariant &a, const QVariant &b) {
        return orden.compare(a.toMap().value(QStringLiteral("name")).toString(),
                             b.toMap().value(QStringLiteral("name")).toString()) < 0;
    });

    // Solo las categorias que tienen alguna app
    QSet<QString> usadas;
    for (const auto &v : std::as_const(m_apps))
        usadas.insert(v.toMap().value(QStringLiteral("categoria")).toString());
    m_categorias = {QVariantMap{{QStringLiteral("id"), QStringLiteral("todas")}, {QStringLiteral("nombre"), QStringLiteral("Todas")}}};
    for (const auto &c : ordenCategorias())
        if (usadas.contains(c.first))
            m_categorias.append(QVariantMap{{QStringLiteral("id"), c.first}, {QStringLiteral("nombre"), c.second}});
    if (!usadas.contains(m_categoria))
        m_categoria = QStringLiteral("todas");
    filtrar();
}

void LauncherBackend::search(const QString &query)
{
    m_busqueda = query;
    filtrar();
}

static QString resolveLauncherBinary(const QString &program)
{
    return titan::resolverBinario(program);
}

void LauncherBackend::launch(const QString &exec)
{
    if (exec.isEmpty()) return;

    QString cleanExec = exec.trimmed();
    QStringList parts = QProcess::splitCommand(cleanExec);
    if (parts.isEmpty()) return;

    QString program = parts.first();

    // Detección directa por si la aplicación es vim, htop u otra herramienta interactiva de consola
    if (program == QStringLiteral("vim") || program == QStringLiteral("vi") ||
        program == QStringLiteral("htop") || program == QStringLiteral("top") ||
        program == QStringLiteral("nano") || program == QStringLiteral("btop")) {
        if (QFile::exists(QStringLiteral("/usr/bin/kitty"))) {
            QProcess::startDetached(QStringLiteral("/usr/bin/kitty"), parts);
            return;
        } else if (QFile::exists(QStringLiteral("/usr/local/bin/titan-terminal"))) {
            QProcess::startDetached(QStringLiteral("/usr/local/bin/titan-terminal"), QStringList() << QStringLiteral("-e") << parts);
            return;
        }
    }

    program = parts.takeFirst();
    QString resolved = resolveLauncherBinary(program);
    QProcess::startDetached(resolved, parts);
}
