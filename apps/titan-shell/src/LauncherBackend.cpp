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
#include <QDateTime>
#include <QElapsedTimer>
#include <QFutureWatcher>
#include <QTimer>
#include <QtConcurrent/QtConcurrentRun>

LauncherBackend::LauncherBackend(QObject *parent)
    : QObject(parent)
    , m_watcher(new QFileSystemWatcher(this))
{
    loadApps();

    // Se espera a que deje de escribir un momento antes de recorrer carpetas
    m_esperaArchivos = new QTimer(this);
    m_esperaArchivos->setSingleShot(true);
    m_esperaArchivos->setInterval(220);
    connect(m_esperaArchivos, &QTimer::timeout, this, &LauncherBackend::lanzarBusquedaArchivos);

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

// .deb/.rpm instalado en la cuenta con doble clic (titan-paquete).
bool esPaqueteCuenta(const QString &ruta)
{
    return QFileInfo(ruta).fileName().startsWith(QStringLiteral("inti-paquete-"))
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

    if (esAppImage(desktop) || esPaqueteCuenta(desktop)) {
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
    } else if (esPaqueteCuenta(desktop)) {
        const QFileInfo dir(e.value(QStringLiteral("X-Inti-Paquete")));
        poner(QStringLiteral("Origen"), QStringLiteral("Paquete .deb/.rpm (instalado en tu cuenta)"));
        if (dir.exists())
            poner(QStringLiteral("Instalado"), QLocale().toString(dir.lastModified(), QLocale::ShortFormat));
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
    if (!desktopValido(desktop) || (QDir(QStringLiteral("/run/archiso")).exists() && !esAppImage(desktop) && !esPaqueteCuenta(desktop))) {
        emit desinstalacionTerminada(nombre, false, QStringLiteral("No se puede desinstalar"));
        return;
    }
    auto *p = new QProcess(this);
    if (esAppImage(desktop)) {
        // Solo borra el AppImage, su icono y su lanzador: sin contraseña.
        p->setProgram(binTitan(QStringLiteral("titan-appimage")));
        p->setArguments({QStringLiteral("quitar"), desktop});
    } else if (esPaqueteCuenta(desktop)) {
        // Solo borra su carpeta en la cuenta y sus lanzadores: sin contraseña.
        p->setProgram(binTitan(QStringLiteral("titan-paquete")));
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

// ---------------------------------------------------------------- búsqueda
namespace {

// Minúsculas y sin tildes: "configuracion" encuentra "Configuración"
QString normal(const QString &s)
{
    const QString d = s.normalized(QString::NormalizationForm_D).toLower();
    QString r;
    r.reserve(d.size());
    for (const QChar c : d)
        if (c.category() != QChar::Mark_NonSpacing)
            r.append(c);
    return r;
}

// 0 = empieza igual, 1 = empieza una palabra, 2 = está dentro, -1 = no está
int encaje(const QString &texto, const QString &q)
{
    const int i = texto.indexOf(q);
    if (i < 0) return -1;
    if (i == 0) return 0;
    for (int j = texto.indexOf(q); j >= 0; j = texto.indexOf(q, j + 1))
        if (j == 0 || !texto.at(j - 1).isLetterOrNumber()) return 1;
    return 2;
}

struct PaginaAjustes { const char *seccion; const char *detalle; const char *claves; };

// Páginas de Ajustes y palabras con las que la gente las busca
const PaginaAjustes kAjustes[] = {
    {"Wi-Fi", "Conectarse a internet", "wifi,wi-fi,internet,red,inalambrica,conexion,contraseña del wifi,router"},
    {"Bluetooth", "Auriculares, ratones y altavoces", "bluetooth,auriculares,cascos,altavoz,emparejar,mando"},
    {"VPN", "Red privada", "vpn,wireguard,openvpn,red privada"},
    {"General", "Acerca de este equipo", "acerca de,informacion del sistema,version,nombre del equipo,procesador,memoria ram,sistema"},
    {"Apariencia", "Tema claro u oscuro y color", "tema,modo oscuro,oscuro,claro,color,acento,colores,estilo,windows,iconos,personalizar"},
    {"Fondo de pantalla", "Imagen del escritorio", "fondo,fondo de pantalla,wallpaper,imagen del escritorio,personalizar"},
    {"Pantallas", "Resolución, escala y monitores", "pantalla,resolucion,monitor,escala,tamaño del texto,frecuencia,hz,segunda pantalla,proyector,girar"},
    {"Sonido", "Volumen, altavoces y micrófono", "sonido,volumen,audio,altavoces,microfono,auriculares,salida,entrada"},
    {"Notificaciones", "Avisos de las aplicaciones", "notificaciones,avisos,alertas,no molestar"},
    {"Concentración", "No molestar", "concentracion,no molestar,silencio,foco"},
    {"Batería", "Energía y suspensión", "bateria,energia,suspender,ahorro de energia,apagar pantalla,portatil,cargador,hibernar"},
    {"Bloquear pantalla", "Contraseña al volver", "bloquear,bloqueo,pantalla de bloqueo,salvapantallas,contraseña al volver"},
    {"Privacidad y seguridad", "Permisos y cortafuegos", "privacidad,seguridad,cortafuegos,firewall,permisos,camara,ubicacion,antivirus"},
    {"Accesibilidad", "Letra grande, zoom y contraste", "accesibilidad,letra grande,zoom,lupa,contraste,lector de pantalla,daltonismo"},
    {"Teclado", "Idioma del teclado y escritura", "teclado,idioma del teclado,distribucion,ñ,acentos,corrector,metodo de entrada,chino,japones"},
    {"Ratón y panel táctil", "Velocidad del puntero y clics", "raton,mouse,panel tactil,touchpad,cursor,puntero,velocidad,clic,desplazamiento,scroll"},
    {"Compartir", "Compartir archivos en la red", "compartir,carpeta compartida,red local,samba,nombre del equipo"},
    {"Impresoras y escáneres", "Añadir una impresora", "impresora,imprimir,escaner,escanear,cola de impresion"},
    {"Restaurar sistema", "Volver a un punto anterior", "restaurar,punto de restauracion,copia de seguridad,volver atras,recuperar,deshacer cambios"},
    {"Almacenamiento", "Espacio en disco", "almacenamiento,disco,espacio,liberar espacio,limpiar,disco duro,ssd"},
    {"Escritorio y Dock", "Dock e iconos del escritorio", "dock,barra de tareas,escritorio,iconos del escritorio,taskbar"},
    {"Barra de menús", "Barra superior y reloj", "barra de menus,barra superior,reloj,hora,fecha"},
    {"Centro de control", "Accesos rápidos", "centro de control,accesos rapidos,botones rapidos"},
    {"Usuarios y grupos", "Cuentas y contraseñas", "usuario,usuarios,cuenta,contraseña,cambiar contraseña,foto de perfil,añadir usuario,administrador"},
    {"Ventanas", "Comportamiento de las ventanas", "ventanas,ajustar ventanas,animaciones,barra de titulo,botones de ventana"},
    {"Aplicaciones predeterminadas", "Navegador, correo, PDF...", "aplicaciones predeterminadas,predeterminado,por defecto,navegador,correo,pdf,abrir con,reproductor,programa predeterminado"},
};

} // namespace

void LauncherBackend::search(const QString &query)
{
    m_busqueda = query;
    filtrar();
    buscarAjustes(query);
    const QString q = query.trimmed();
    ++m_generacion;   // la búsqueda anterior, si sigue, se abandona
    if (q.size() < 2) {
        m_esperaArchivos->stop();
        if (!m_archivos.isEmpty() || m_buscandoArchivos) {
            m_archivos.clear();
            m_buscandoArchivos = false;
            emit resultadosChanged();
        }
        return;
    }
    m_esperaArchivos->start();
}

void LauncherBackend::buscarAjustes(const QString &consulta)
{
    m_ajustes.clear();
    const QString q = normal(consulta.trimmed());
    if (q.size() >= 2) {
        QList<QPair<int, QVariantMap>> hallados;
        for (const PaginaAjustes &p : kAjustes) {
            const QString titulo = QString::fromUtf8(p.seccion);
            int puntos = encaje(normal(titulo), q);
            QString porQue = QString::fromUtf8(p.detalle);
            if (puntos < 0) {
                // Por sus palabras clave (puntúan detrás del título)
                for (const QString &c : QString::fromUtf8(p.claves).split(QLatin1Char(','))) {
                    const int e = encaje(normal(c), q);
                    if (e >= 0 && (puntos < 0 || e + 3 < puntos)) puntos = e + 3;
                }
            }
            if (puntos >= 0)
                hallados.append({puntos, QVariantMap{{QStringLiteral("seccion"), titulo},
                                                     {QStringLiteral("titulo"), titulo},
                                                     {QStringLiteral("detalle"), porQue}}});
        }
        std::stable_sort(hallados.begin(), hallados.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
        for (int i = 0; i < hallados.size() && i < 4; ++i)
            m_ajustes.append(hallados.at(i).second);
    }
    emit resultadosChanged();
}

// Recorre la carpeta personal (sin ocultas, sin seguir enlaces) por niveles,
// con un tope de tiempo y de entradas para no cargar el equipo.
static QVariantList buscarEnCasa(const QString &q, const std::atomic<int> &generacion, int mia)
{
    struct Hallado { int puntos; int nivel; qint64 cambio; QString ruta; bool carpeta; };
    const QString casa = QDir::homePath();
    static const QSet<QString> saltar = {QStringLiteral("node_modules"), QStringLiteral("__pycache__"),
                                         QStringLiteral("snap"), QStringLiteral("build"), QStringLiteral("target"),
                                         QStringLiteral("venv"), QStringLiteral("site-packages")};
    QList<Hallado> hallados;
    QList<QPair<QString, int>> cola{{casa, 0}};
    QElapsedTimer reloj;
    reloj.start();
    int vistos = 0;
    while (!cola.isEmpty() && reloj.elapsed() < 800 && vistos < 80000) {
        if (generacion.load() != mia)
            return {};
        const auto [dir, nivel] = cola.takeFirst();
        const QFileInfoList hijos = QDir(dir).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System, QDir::NoSort);
        for (const QFileInfo &fi : hijos) {
            ++vistos;
            const bool carpeta = fi.isDir() && !fi.isSymLink();
            const int e = encaje(normal(fi.fileName()), q);
            if (e >= 0 && hallados.size() < 400)
                hallados.append({e, nivel, fi.lastModified().toSecsSinceEpoch(), fi.absoluteFilePath(), fi.isDir()});
            if (carpeta && nivel < 7 && !saltar.contains(fi.fileName()))
                cola.append({fi.absoluteFilePath(), nivel + 1});
        }
    }
    std::sort(hallados.begin(), hallados.end(), [](const Hallado &a, const Hallado &b) {
        if (a.puntos != b.puntos) return a.puntos < b.puntos;
        if (a.nivel != b.nivel) return a.nivel < b.nivel;
        return a.cambio > b.cambio;
    });
    QVariantList r;
    for (int i = 0; i < hallados.size() && i < 8; ++i) {
        const Hallado &h = hallados.at(i);
        const QFileInfo fi(h.ruta);
        QString carpeta = fi.absolutePath();
        carpeta = carpeta == casa ? QStringLiteral("Carpeta personal")
                                  : carpeta.mid(casa.size() + 1).replace(QLatin1Char('/'), QStringLiteral(" › "));
        r.append(QVariantMap{{QStringLiteral("ruta"), h.ruta}, {QStringLiteral("nombre"), fi.fileName()},
                             {QStringLiteral("carpeta"), carpeta}, {QStringLiteral("esCarpeta"), h.carpeta}});
    }
    return r;
}

void LauncherBackend::lanzarBusquedaArchivos()
{
    const QString q = normal(m_busqueda.trimmed());
    if (q.size() < 2) return;
    const int mia = m_generacion.load();
    m_buscandoArchivos = true;
    emit resultadosChanged();
    auto *vigia = new QFutureWatcher<QVariantList>(this);
    connect(vigia, &QFutureWatcher<QVariantList>::finished, this, [this, vigia, mia]() {
        vigia->deleteLater();
        if (m_generacion.load() != mia) return;   // ya escribió otra cosa
        m_archivos = vigia->result();
        m_buscandoArchivos = false;
        emit resultadosChanged();
    });
    vigia->setFuture(QtConcurrent::run([q, mia, this]() { return buscarEnCasa(q, m_generacion, mia); }));
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
