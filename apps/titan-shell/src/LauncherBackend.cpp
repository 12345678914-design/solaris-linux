#include "LauncherBackend.h"
#include <QDir>
#include <QFileInfo>
#include <QSettings>
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

void LauncherBackend::reload()
{
    loadApps();
}

void LauncherBackend::loadApps()
{
    m_apps.clear();
    QSet<QString> seenExecs;

    // Aplicaciones principales integradas de Titan Linux
    auto addApp = [this, &seenExecs](const QString &name, const QString &exec, const QString &icon) {
        QVariantMap app;
        app[QStringLiteral("name")] = name;
        app[QStringLiteral("exec")] = exec;
        app[QStringLiteral("icon")] = icon;
        m_apps.append(app);
        seenExecs.insert(exec);
    };

    auto resolverIcono = [](const QString &icono, const QString &exec) -> QString {
        if (icono.startsWith(QStringLiteral("qrc:/")) || icono.startsWith(QLatin1Char('/'))) {
            return icono;
        }

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
        if (lower.contains(QStringLiteral("terminal")) || execLower.contains(QStringLiteral("terminal")) || execLower.contains(QStringLiteral("kitty")))
            return QStringLiteral("qrc:/icons/terminal.png");
        if (lower.contains(QStringLiteral("firefox")) || lower.contains(QStringLiteral("browser")) || execLower.contains(QStringLiteral("firefox")) || execLower.contains(QStringLiteral("chrome")))
            return QStringLiteral("qrc:/icons/safari.png");
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

        return QStringLiteral("qrc:/icons/developer.png");
    };

    addApp(QStringLiteral("Finder"), QStringLiteral("titan-finder"), QStringLiteral("qrc:/icons/finder.png"));
    addApp(QStringLiteral("Firefox"), QStringLiteral("firefox"), QStringLiteral("qrc:/icons/safari.png"));
    addApp(QStringLiteral("Fotos"), QStringLiteral("titan-fotos"), QStringLiteral("qrc:/icons/pictures.png"));
    addApp(QStringLiteral("Música"), QStringLiteral("titan-musica"), QStringLiteral("qrc:/icons/music.png"));
    addApp(QStringLiteral("Terminal"), QStringLiteral("titan-terminal"), QStringLiteral("qrc:/icons/terminal.png"));
    addApp(QStringLiteral("Ajustes del Sistema"), QStringLiteral("titan-settings"), QStringLiteral("qrc:/icons/system.png"));
    addApp(QStringLiteral("ONLYOFFICE"), QStringLiteral("onlyoffice-desktopeditors"), QStringLiteral("qrc:/icons/onlyoffice.png"));
    addApp(QStringLiteral("Acerca de Titan"), QStringLiteral("titan-acerca"), QStringLiteral("qrc:/icons/about.png"));

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
            QSettings ini(info.absoluteFilePath(), QSettings::IniFormat);
            ini.beginGroup(QStringLiteral("Desktop Entry"));

            if (ini.value(QStringLiteral("NoDisplay"), false).toBool()) continue;
            if (ini.value(QStringLiteral("Type"), QStringLiteral("Application")).toString() != QStringLiteral("Application")) continue;

            QString nombre = ini.value(QStringLiteral("Name[es]")).toString();
            if (nombre.isEmpty()) {
                nombre = ini.value(QStringLiteral("Name")).toString();
            }

            QString exec = ini.value(QStringLiteral("Exec")).toString();
            QString icono = ini.value(QStringLiteral("Icon")).toString();
            bool inTerminal = ini.value(QStringLiteral("Terminal"), false).toBool();

            // Quitar parámetros de campo (%u, %F, %k, etc.)
            exec.remove(QRegularExpression(QStringLiteral("%[a-zA-Z]")));
            exec = exec.trimmed();

            if (nombre.isEmpty() || exec.isEmpty()) continue;
            if (exec.contains(QLatin1String("pcmanfm")) || info.fileName().contains(QLatin1String("pcmanfm"))) continue;

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
            app[QStringLiteral("icon")] = resolverIcono(icono, exec);
            m_apps.append(app);
        }
    }

    m_filteredApps = m_apps;
    emit appsChanged();
}

void LauncherBackend::search(const QString &query)
{
    if (query.trimmed().isEmpty()) {
        m_filteredApps = m_apps;
    } else {
        m_filteredApps.clear();
        for (const auto &appVal : m_apps) {
            QVariantMap app = appVal.toMap();
            QString name = app[QStringLiteral("name")].toString();
            if (name.contains(query, Qt::CaseInsensitive)) {
                m_filteredApps.append(app);
            }
        }
    }
    emit appsChanged();
}

static QString resolveLauncherBinary(const QString &program)
{
    if (QFile::exists(program)) return program;
    QString inPath = QStandardPaths::findExecutable(program);
    if (!inPath.isEmpty()) return inPath;

    const QStringList candidates = {
        QStringLiteral("/usr/local/bin/") + program,
        QStringLiteral("/usr/bin/") + program,
        QCoreApplication::applicationDirPath() + QStringLiteral("/../") + program + QStringLiteral("/") + program,
        QCoreApplication::applicationDirPath() + QStringLiteral("/../") + program + QStringLiteral("/build/") + program,
        QDir::currentPath() + QStringLiteral("/apps/") + program + QStringLiteral("/") + program,
        QDir::currentPath() + QStringLiteral("/apps/") + program + QStringLiteral("/build/") + program,
        QDir::currentPath() + QStringLiteral("/iso/titan/airootfs/usr/local/bin/") + program,
        QStringLiteral("/home/isai/Proyectos/titan-linux/apps/") + program + QStringLiteral("/") + program,
        QStringLiteral("/home/isai/Proyectos/titan-linux/iso/titan/airootfs/usr/local/bin/") + program
    };

    for (const QString &c : candidates) {
        if (QFile::exists(c) && QFileInfo(c).isExecutable()) {
            return c;
        }
    }
    return program;
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
