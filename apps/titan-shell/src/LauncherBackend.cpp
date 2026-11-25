#include "TitanBinary.h"
#include "LauncherBackend.h"
#include "ColaApps.h"
#include <QCollator>
#include <QLocale>
#include <QHash>
#include <algorithm>
#include "TitanIconoSvg.h"
#include "TitanIconoApp.h"
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
        {QStringLiteral("titan-monitor"), QStringLiteral("sistema")},
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

namespace {
// Programas de Inti (en pruebas, TITAN_BIN apunta a otros)
QString binTitan(const QString &nombre)
{
    return qEnvironmentVariable("TITAN_BIN", QStringLiteral("/usr/local/bin/")) + nombre;
}

const QStringList &carpetasApps()
{
    static const QStringList d = {
        QDir::homePath() + QStringLiteral("/.local/share/applications"),
        QStringLiteral("/usr/local/share/applications"),
        QStringLiteral("/usr/share/applications"),
        QStringLiteral("/var/lib/flatpak/exports/share/applications"),
        QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share/applications")};
    return d;
}

// .desktop de una app integrada (Finder, Firefox...) por su orden
QString buscarDesktop(const QString &exec)
{
    const QString prog = exec.section(QLatin1Char(' '), 0, 0).section(QLatin1Char('/'), -1);
    QStringList nombres{prog + QStringLiteral(".desktop")};
    if (prog == QLatin1String("plasma-discover"))
        nombres.prepend(QStringLiteral("org.kde.discover.desktop"));
    for (const QString &d : carpetasApps())
        for (const QString &n : nombres)
            if (QFile::exists(d + QLatin1Char('/') + n))
                return d + QLatin1Char('/') + n;
    return QString();
}

bool desktopValido(const QString &ruta)
{
    if (!ruta.endsWith(QStringLiteral(".desktop")) || !QFile::exists(ruta))
        return false;
    const QString canon = QFileInfo(ruta).canonicalFilePath();
    for (const QString &d : carpetasApps()) {
        const QString c = QFileInfo(d).canonicalFilePath();
        if (!c.isEmpty() && (canon.startsWith(c + QLatin1Char('/')) || QFileInfo(ruta).absolutePath() == d))
            return true;
    }
    return false;
}

// Grupos de un .desktop: {"Desktop Entry": {...}, "Desktop Action new-window": {...}}
QHash<QString, QHash<QString, QString>> gruposDesktop(const QString &ruta)
{
    QHash<QString, QHash<QString, QString>> g;
    QFile f(ruta);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return g;
    QString actual;
    while (!f.atEnd()) {
        const QString l = QString::fromUtf8(f.readLine()).trimmed();
        if (l.isEmpty() || l.startsWith(QLatin1Char('#')))
            continue;
        if (l.startsWith(QLatin1Char('[')) && l.endsWith(QLatin1Char(']'))) {
            actual = l.mid(1, l.size() - 2);
            continue;
        }
        const int i = l.indexOf(QLatin1Char('='));
        if (i > 0 && !actual.isEmpty() && !g[actual].contains(l.left(i).trimmed()))
            g[actual].insert(l.left(i).trimmed(), l.mid(i + 1).trimmed());
    }
    return g;
}

QString traducido(const QHash<QString, QString> &h, const QString &clave)
{
    for (const QString &k : {clave + QStringLiteral("[es_ES]"), clave + QStringLiteral("[es]"), clave})
        if (!h.value(k).isEmpty())
            return h.value(k);
    return QString();
}

QString paqueteDe(const QString &ruta)
{
    QProcess p;
    p.start(QStringLiteral("pacman"), {QStringLiteral("-Qqo"), QFileInfo(ruta).canonicalFilePath()});
    if (!p.waitForFinished(3000) || p.exitCode() != 0)
        return QString();
    return QString::fromUtf8(p.readAllStandardOutput()).trimmed().section(QLatin1Char('\n'), 0, 0);
}

bool esFlatpak(const QString &ruta) { return ruta.contains(QStringLiteral("/flatpak/exports/")); }

// AppImage instalado con doble clic (titan-appimage): vive en la cuenta.
bool esAppImage(const QString &ruta)
{
    return QFileInfo(ruta).fileName().startsWith(QStringLiteral("inti-appimage-"))
           && ruta.startsWith(QDir::homePath() + QStringLiteral("/.local/share/applications/"));
}
}

QVariantMap LauncherBackend::opcionesApp(const QString &desktop) const
{
    QVariantMap r;
    QVariantList acciones;
    r[QStringLiteral("desinstalable")] = false;
    if (!desktopValido(desktop)) {
        r[QStringLiteral("acciones")] = acciones;
        r[QStringLiteral("motivo")] = QStringLiteral("Parte del sistema");
        return r;
    }
    const auto g = gruposDesktop(desktop);
    for (const QString &id : g.value(QStringLiteral("Desktop Entry")).value(QStringLiteral("Actions")).split(QLatin1Char(';'), Qt::SkipEmptyParts)) {
        const auto a = g.value(QStringLiteral("Desktop Action ") + id);
        const QString t = traducido(a, QStringLiteral("Name"));
        if (!t.isEmpty() && !a.value(QStringLiteral("Exec")).isEmpty())
            acciones.append(QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("t"), t}});
    }
    r[QStringLiteral("acciones")] = acciones;

    if (esAppImage(desktop)) {
        r[QStringLiteral("desinstalable")] = true;
    } else if (QDir(QStringLiteral("/run/archiso")).exists()) {
        r[QStringLiteral("motivo")] = QStringLiteral("No disponible en la sesión de prueba");
    } else if (esFlatpak(desktop)) {
        r[QStringLiteral("desinstalable")] = true;
    } else {
        const QString paquete = paqueteDe(desktop);
        QProcess puede;
        if (!paquete.isEmpty())
            puede.start(binTitan(QStringLiteral("titan-desinstalar")), {QStringLiteral("--puede"), paquete});
        const bool si = !paquete.isEmpty() && puede.waitForFinished(3000)
                        && QString::fromUtf8(puede.readAllStandardOutput()).trimmed() == QLatin1String("si");
        r[QStringLiteral("desinstalable")] = si;
        if (!si)
            r[QStringLiteral("motivo")] = QStringLiteral("Parte del sistema");
    }
    return r;
}

void LauncherBackend::lanzarAccion(const QString &desktop, const QString &accion, const QString &icono)
{
    if (!desktopValido(desktop))
        return;
    QString exec = gruposDesktop(desktop).value(QStringLiteral("Desktop Action ") + accion).value(QStringLiteral("Exec"));
    exec.remove(QRegularExpression(QStringLiteral("%[a-zA-Z]")));
    exec = exec.trimmed();
    if (!exec.isEmpty())
        launch(exec, false, icono);
}

QString LauncherBackend::enviarAlEscritorio(const QString &desktop) const
{
    if (!desktopValido(desktop))
        return QStringLiteral("No se pudo crear el acceso directo");
    QString escritorio = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    if (escritorio.isEmpty())
        escritorio = QDir::homePath() + QStringLiteral("/Escritorio");
    QDir().mkpath(escritorio);
    const QString destino = escritorio + QLatin1Char('/') + QFileInfo(desktop).fileName();
    if (QFile::exists(destino))
        return QStringLiteral("Ya está en el escritorio");
    if (!QFile::copy(desktop, destino))
        return QStringLiteral("No se pudo crear el acceso directo");
    QFile::setPermissions(destino, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner | QFile::ReadGroup | QFile::ReadOther);
    return QStringLiteral("Acceso directo creado en el escritorio");
}

QVariantList LauncherBackend::propiedadesApp(const QString &desktop) const
{
    QVariantList l;
    auto poner = [&l](const QString &k, const QString &v) {
        if (!v.trimmed().isEmpty())
            l.append(QVariantMap{{QStringLiteral("k"), k}, {QStringLiteral("v"), v.trimmed()}});
    };
    if (!desktopValido(desktop))
        return l;
    const auto e = gruposDesktop(desktop).value(QStringLiteral("Desktop Entry"));
    poner(QStringLiteral("Nombre"), traducido(e, QStringLiteral("Name")));
    poner(QStringLiteral("Descripción"), traducido(e, QStringLiteral("Comment")));
    poner(QStringLiteral("Tipo"), traducido(e, QStringLiteral("GenericName")));
    if (esAppImage(desktop)) {
        const QFileInfo prog(e.value(QStringLiteral("X-Inti-AppImage")));
        poner(QStringLiteral("Origen"), QStringLiteral("AppImage (instalada en tu cuenta)"));
        if (prog.exists()) {
            poner(QStringLiteral("Tamaño"), QLocale().formattedDataSize(prog.size()));
            poner(QStringLiteral("Instalado"), QLocale().toString(prog.lastModified(), QLocale::ShortFormat));
        }
    } else if (esFlatpak(desktop)) {
        poner(QStringLiteral("Origen"), QStringLiteral("Flatpak (%1)").arg(QFileInfo(desktop).completeBaseName()));
    } else {
        const QString paquete = paqueteDe(desktop);
        if (!paquete.isEmpty()) {
            QProcess qi;
            qi.setProcessEnvironment([] { auto e = QProcessEnvironment::systemEnvironment(); e.insert(QStringLiteral("LC_ALL"), QStringLiteral("C")); return e; }());
            qi.start(QStringLiteral("pacman"), {QStringLiteral("-Qi"), paquete});
            QString version, tam, fecha;
            if (qi.waitForFinished(3000)) {
                for (const QString &lin : QString::fromUtf8(qi.readAllStandardOutput()).split(QLatin1Char('\n'))) {
                    const QString k = lin.section(QLatin1Char(':'), 0, 0).trimmed();
                    const QString v = lin.section(QLatin1Char(':'), 1).trimmed();
                    if (k == QLatin1String("Version")) version = v;
                    else if (k == QLatin1String("Installed Size")) tam = v;
                    else if (k == QLatin1String("Install Date")) fecha = v;
                }
            }
            poner(QStringLiteral("Paquete"), paquete);
            poner(QStringLiteral("Versión"), version);
            poner(QStringLiteral("Tamaño"), tam);
            poner(QStringLiteral("Instalado"), fecha);
        }
    }
    poner(QStringLiteral("Orden"), e.value(QStringLiteral("Exec")).remove(QRegularExpression(QStringLiteral("%[a-zA-Z]"))));
    poner(QStringLiteral("Archivo"), desktop);
    return l;
}

void LauncherBackend::desinstalar(const QString &desktop, const QString &nombre)
{
    if (!desktopValido(desktop) || (QDir(QStringLiteral("/run/archiso")).exists() && !esAppImage(desktop))) {
        emit desinstalacionTerminada(nombre, false, QStringLiteral("No se puede desinstalar"));
        return;
    }
    auto *p = new QProcess(this);
    if (esAppImage(desktop)) {
        // Solo borra el AppImage, su icono y su lanzador: sin contraseña.
        p->setProgram(binTitan(QStringLiteral("titan-appimage")));
        p->setArguments({QStringLiteral("quitar"), desktop});
    } else if (esFlatpak(desktop)) {
        const bool usuario = desktop.startsWith(QDir::homePath());
        p->setProgram(QStringLiteral("flatpak"));
        p->setArguments({QStringLiteral("uninstall"), usuario ? QStringLiteral("--user") : QStringLiteral("--system"),
                         QStringLiteral("--noninteractive"), QFileInfo(desktop).completeBaseName()});
    } else {
        const QString paquete = paqueteDe(desktop);
        if (paquete.isEmpty()) {
            p->deleteLater();
            emit desinstalacionTerminada(nombre, false, QStringLiteral("No se encontró el paquete"));
            return;
        }
        p->setProgram(QStringLiteral("pkexec"));
        p->setArguments({binTitan(QStringLiteral("titan-desinstalar")), paquete});
    }
    connect(p, &QProcess::finished, this, [this, p, nombre](int codigo, QProcess::ExitStatus) {
        const QString error = QString::fromUtf8(p->readAllStandardError()).trimmed().section(QLatin1Char('\n'), -1);
        p->deleteLater();
        if (codigo == 0) {
            loadApps();
            emit desinstalacionTerminada(nombre, true, nombre + QStringLiteral(" se ha desinstalado"));
        } else {
            emit desinstalacionTerminada(nombre, false, codigo == 126 ? QStringLiteral("Cancelado")
                                                          : (error.isEmpty() ? QStringLiteral("No se pudo desinstalar") : error));
        }
    });
    p->start();
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
        app[QStringLiteral("desktop")] = buscarDesktop(exec);
        m_apps.append(app);
    };

    // El mismo icono que el Dock y el escritorio (ver TitanIconoApp.h).
    // Devuelve "" si no encuentra nada: quien llama genera un icono SVG.
    auto resolverIcono = [](const QString &icono, const QString &exec) -> QString {
        return titan::iconoApp(icono, exec);
    };

    // Las apps propias de Inti OS van primero: así ganan la deduplicación por
    // nombre frente a las de GNOME (que también vienen en la ISO como respaldo).
    addApp(QStringLiteral("Explorador de archivos"), QStringLiteral("titan-finder"), QStringLiteral("qrc:/icons/finder.png"));
    addApp(QStringLiteral("Firefox"), QStringLiteral("firefox"), QStringLiteral("qrc:/icons/firefox.png"));
    addApp(QStringLiteral("Fotos"), QStringLiteral("titan-fotos"), QStringLiteral("qrc:/icons/pictures.png"));
    addApp(QStringLiteral("Música"), QStringLiteral("titan-musica"), QStringLiteral("qrc:/icons/music-app.png"));
    addApp(QStringLiteral("Terminal"), QStringLiteral("titan-terminal"), QStringLiteral("qrc:/icons/terminal.png"));
    addApp(QStringLiteral("Calculadora"), QStringLiteral("titan-calc"), QStringLiteral("qrc:/icons/calculator.png"));
    addApp(QStringLiteral("Monitor de recursos"), QStringLiteral("titan-monitor"), QStringLiteral("qrc:/icons/monitor.png"));
    addApp(QStringLiteral("Calendario"), QStringLiteral("titan-calendar"), QStringLiteral("qrc:/icons/calendar.png"));
    addApp(QStringLiteral("Reloj"), QStringLiteral("titan-clock"), QStringLiteral("qrc:/icons/clock.png"));
    addApp(QStringLiteral("Reproductor de Video"), QStringLiteral("titan-video"), QStringLiteral("qrc:/icons/video.png"));
    addApp(QStringLiteral("App Store"), QStringLiteral("plasma-discover"), QStringLiteral("qrc:/icons/apps-folder.png"));
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
            app[QStringLiteral("desktop")] = info.absoluteFilePath();
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

void LauncherBackend::launch(const QString &exec, bool enDock, const QString &icono)
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
            ColaApps::instancia()->lanzar(QStringLiteral("/usr/bin/kitty"), parts, enDock, icono);
            return;
        } else if (QFile::exists(QStringLiteral("/usr/local/bin/titan-terminal"))) {
            ColaApps::instancia()->lanzar(QStringLiteral("/usr/local/bin/titan-terminal"), QStringList() << QStringLiteral("-e") << parts, enDock, icono);
            return;
        }
    }

    program = parts.takeFirst();
    // De una en una, en orden (ColaApps)
    ColaApps::instancia()->lanzar(resolveLauncherBinary(program), parts, enDock, icono);
}
