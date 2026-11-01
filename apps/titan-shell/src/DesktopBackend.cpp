#include "DesktopBackend.h"

#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QFile>
#include <QSettings>
#include <QUrl>
#include <QRegularExpression>
#include <QJsonDocument>
#include <QJsonObject>

static QString resolveDesktopBinary(const QString &program)
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

DesktopBackend::DesktopBackend(QObject *parent)
    : QObject(parent)
    , m_watcher(new QFileSystemWatcher(this))
{
    m_desktopPath = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    if (m_desktopPath.isEmpty() || !QDir(m_desktopPath).exists()) {
        m_desktopPath = QDir::homePath() + QStringLiteral("/Escritorio");
    }

    QDir().mkpath(m_desktopPath);
    ensureSampleDesktop();
    loadPositions();
    loadItems();

    m_watcher->addPath(m_desktopPath);
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &DesktopBackend::refresh);
}

void DesktopBackend::ensureSampleDesktop()
{
    QDir desk(m_desktopPath);

    // 1. Carpeta Planning como en la referencia de macOS
    if (!desk.exists(QStringLiteral("Planning"))) {
        desk.mkdir(QStringLiteral("Planning"));
        QFile sampleNotes(m_desktopPath + QStringLiteral("/Planning/Proyectos 2026.txt"));
        if (sampleNotes.open(QIODevice::WriteOnly | QIODevice::Text)) {
            sampleNotes.write("Plan de desarrollo y diseño TITAN Linux estilo macOS\n");
            sampleNotes.close();
        }
    }

    // 2. Acceso directo a Firefox en el Escritorio
    QString ffShortcut = m_desktopPath + QStringLiteral("/firefox.desktop");
    if (!QFile::exists(ffShortcut)) {
        QFile f(ffShortcut);
        if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
            f.write(
                "[Desktop Entry]\n"
                "Version=1.0\n"
                "Name=Firefox\n"
                "GenericName=Navegador Web\n"
                "Comment=Navega por la red\n"
                "Exec=firefox %u\n"
                "Icon=firefox\n"
                "Terminal=false\n"
                "Type=Application\n"
                "Categories=Network;WebBrowser;\n"
            );
            f.close();
            f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                             QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                             QFileDevice::ReadOther | QFileDevice::ExeOther);
        }
    }

    // 3. Acceso directo a ONLYOFFICE en el Escritorio
    QString ooShortcut = m_desktopPath + QStringLiteral("/onlyoffice-desktopeditors.desktop");
    if (!QFile::exists(ooShortcut)) {
        QFile f(ooShortcut);
        if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
            f.write(
                "[Desktop Entry]\n"
                "Version=1.0\n"
                "Name=ONLYOFFICE\n"
                "GenericName=Suite Ofimática\n"
                "Comment=Editor de documentos, hojas de cálculo y presentaciones\n"
                "Exec=onlyoffice-desktopeditors %U\n"
                "Icon=onlyoffice-desktopeditors\n"
                "Terminal=false\n"
                "Type=Application\n"
                "Categories=Office;WordProcessor;Spreadsheet;Presentation;\n"
            );
            f.close();
            f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                             QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                             QFileDevice::ReadOther | QFileDevice::ExeOther);
        }
    }
}

void DesktopBackend::loadItems()
{
    m_items.clear();
    QDir desk(m_desktopPath);
    const QFileInfoList list = desk.entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries, QDir::DirsFirst | QDir::Name);

    for (const QFileInfo &fi : list) {
        if (fi.fileName().startsWith(QLatin1Char('.'))) continue;

        QVariantMap item;
        item[QStringLiteral("path")] = fi.absoluteFilePath();
        item[QStringLiteral("isDir")] = fi.isDir();

        if (fi.suffix().toLower() == QStringLiteral("desktop")) {
            QSettings ini(fi.absoluteFilePath(), QSettings::IniFormat);
            ini.beginGroup(QStringLiteral("Desktop Entry"));

            QString name = ini.value(QStringLiteral("Name[es]")).toString();
            if (name.isEmpty()) {
                name = ini.value(QStringLiteral("Name")).toString();
            }
            if (name.isEmpty()) {
                name = fi.completeBaseName();
            }

            QString icon = ini.value(QStringLiteral("Icon")).toString();
            QString exec = ini.value(QStringLiteral("Exec")).toString();

            item[QStringLiteral("name")] = name;
            item[QStringLiteral("icon")] = resolveAppIcon(icon, exec);
            item[QStringLiteral("isApp")] = true;
            item[QStringLiteral("exec")] = exec;
        } else {
            item[QStringLiteral("name")] = fi.fileName();
            item[QStringLiteral("icon")] = resolveIcon(fi.fileName(), fi.isDir());
            item[QStringLiteral("isApp")] = false;
        }

        m_items.append(item);
    }

    emit itemsChanged();
}

QString DesktopBackend::resolveAppIcon(const QString &iconName, const QString &exec) const
{
    QString lower = iconName.toLower();
    QString execLower = exec.toLower();

    if (lower.contains(QStringLiteral("onlyoffice")) || execLower.contains(QStringLiteral("onlyoffice"))) {
        return QStringLiteral("qrc:/icons/onlyoffice.png");
    }
    if (lower.contains(QStringLiteral("firefox")) || lower.contains(QStringLiteral("browser")) || execLower.contains(QStringLiteral("firefox"))) {
        return QStringLiteral("qrc:/icons/safari.png");
    }
    if (lower.contains(QStringLiteral("terminal")) || execLower.contains(QStringLiteral("terminal")) || execLower.contains(QStringLiteral("kitty"))) {
        return QStringLiteral("qrc:/icons/terminal.png");
    }
    if (lower.contains(QStringLiteral("finder")) || lower.contains(QStringLiteral("pcmanfm")) || execLower.contains(QStringLiteral("finder"))) {
        return QStringLiteral("qrc:/icons/finder.png");
    }
    if (lower.contains(QStringLiteral("photo")) || lower.contains(QStringLiteral("picture")) || execLower.contains(QStringLiteral("foto"))) {
        return QStringLiteral("qrc:/icons/pictures.png");
    }
    if (lower.contains(QStringLiteral("music")) || execLower.contains(QStringLiteral("musica"))) {
        return QStringLiteral("qrc:/icons/music.png");
    }
    if (lower.contains(QStringLiteral("code")) || lower.contains(QStringLiteral("develop")) || execLower.contains(QStringLiteral("code"))) {
        return QStringLiteral("qrc:/icons/vscode.png");
    }

    if (QFile::exists(iconName)) {
        return QUrl::fromLocalFile(iconName).toString();
    }
    static const QStringList iconSearchPaths = {
        QStringLiteral("/usr/share/icons/hicolor/128x128/apps/"),
        QStringLiteral("/usr/share/icons/hicolor/256x256/apps/"),
        QStringLiteral("/usr/share/icons/hicolor/64x64/apps/"),
        QStringLiteral("/usr/share/pixmaps/")
    };
    for (const QString &p : iconSearchPaths) {
        if (QFile::exists(p + iconName + QStringLiteral(".png"))) {
            return QUrl::fromLocalFile(p + iconName + QStringLiteral(".png")).toString();
        }
        if (QFile::exists(p + iconName + QStringLiteral(".svg"))) {
            return QUrl::fromLocalFile(p + iconName + QStringLiteral(".svg")).toString();
        }
    }

    return QStringLiteral("qrc:/icons/system.png");
}

QString DesktopBackend::resolveIcon(const QString &fileName, bool isDir) const
{
    if (isDir) {
        return QStringLiteral("qrc:/icons/folder.png");
    }

    const QString lower = fileName.toLower();
    if (lower.endsWith(QStringLiteral(".png")) || lower.endsWith(QStringLiteral(".jpg")) || lower.endsWith(QStringLiteral(".jpeg")) || lower.endsWith(QStringLiteral(".webp"))) {
        return QStringLiteral("qrc:/icons/pictures.png");
    }
    if (lower.endsWith(QStringLiteral(".mp3")) || lower.endsWith(QStringLiteral(".wav")) || lower.endsWith(QStringLiteral(".ogg")) || lower.endsWith(QStringLiteral(".flac"))) {
        return QStringLiteral("qrc:/icons/music.png");
    }
    if (lower.endsWith(QStringLiteral(".sh")) || lower.endsWith(QStringLiteral(".py")) || lower.endsWith(QStringLiteral(".cpp")) || lower.endsWith(QStringLiteral(".rs"))) {
        return QStringLiteral("qrc:/icons/developer.png");
    }

    return QStringLiteral("qrc:/icons/notes.png");
}

void DesktopBackend::openItem(const QString &path)
{
    QFileInfo fi(path);
    if (!fi.exists()) return;

    if (fi.suffix().toLower() == QStringLiteral("desktop")) {
        QSettings ini(path, QSettings::IniFormat);
        ini.beginGroup(QStringLiteral("Desktop Entry"));
        QString exec = ini.value(QStringLiteral("Exec")).toString();
        exec.remove(QRegularExpression(QStringLiteral("%[a-zA-Z]")));
        exec = exec.trimmed();

        bool inTerminal = ini.value(QStringLiteral("Terminal"), false).toBool();
        if (inTerminal) {
            QString term = resolveDesktopBinary(QStringLiteral("titan-terminal"));
            if (QFile::exists(term)) {
                QProcess::startDetached(term, {QStringLiteral("-e"), exec});
                return;
            } else if (QFile::exists(QStringLiteral("/usr/bin/kitty"))) {
                QProcess::startDetached(QStringLiteral("/usr/bin/kitty"), {exec});
                return;
            }
        }

        if (!exec.isEmpty()) {
            QStringList parts = QProcess::splitCommand(exec);
            if (!parts.isEmpty()) {
                QString prog = resolveDesktopBinary(parts.takeFirst());
                QProcess::startDetached(prog, parts);
                return;
            }
        }
        return;
    }

    if (fi.isDir()) {
        QProcess::startDetached(resolveDesktopBinary(QStringLiteral("titan-finder")), {path});
        return;
    }

    const QString ext = fi.suffix().toLower();
    if (ext == QStringLiteral("png") || ext == QStringLiteral("jpg") || ext == QStringLiteral("jpeg") || ext == QStringLiteral("webp")) {
        QProcess::startDetached(resolveDesktopBinary(QStringLiteral("titan-fotos")), {path});
        return;
    }

    if (ext == QStringLiteral("mp3") || ext == QStringLiteral("wav") || ext == QStringLiteral("ogg") || ext == QStringLiteral("flac")) {
        QProcess::startDetached(resolveDesktopBinary(QStringLiteral("titan-musica")), {path});
        return;
    }

    // Default opener
    QProcess::startDetached(QStringLiteral("xdg-open"), {path});
}

void DesktopBackend::openInFinder()
{
    QProcess::startDetached(resolveDesktopBinary(QStringLiteral("titan-finder")), {m_desktopPath});
}

void DesktopBackend::refresh()
{
    loadItems();
}

void DesktopBackend::removeItem(const QString &path)
{
    QFileInfo fi(path);
    if (!fi.exists()) return;

    if (fi.isDir()) {
        QDir dir(path);
        dir.removeRecursively();
    } else {
        QFile::remove(path);
    }

    refresh();
}

void DesktopBackend::moveItem(const QString &path, qreal x, qreal y)
{
    QVariantMap pos;
    pos[QStringLiteral("x")] = x;
    pos[QStringLiteral("y")] = y;
    m_positions[path] = pos;
    savePositions();
}

QVariantMap DesktopBackend::iconPosition(const QString &path)
{
    if (m_positions.contains(path)) {
        return m_positions.value(path).toMap();
    }
    QVariantMap def;
    def[QStringLiteral("x")] = -1.0;
    def[QStringLiteral("y")] = -1.0;
    return def;
}

void DesktopBackend::loadPositions()
{
    QString configPath = QDir::homePath() + QStringLiteral("/.config/titan/desktop_positions.json");
    QFile file(configPath);
    if (!file.open(QIODevice::ReadOnly)) return;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    if (!doc.isObject()) return;

    QJsonObject root = doc.object();
    for (auto it = root.begin(); it != root.end(); ++it) {
        QJsonObject posObj = it.value().toObject();
        QVariantMap pos;
        pos[QStringLiteral("x")] = posObj.value(QStringLiteral("x")).toDouble(-1.0);
        pos[QStringLiteral("y")] = posObj.value(QStringLiteral("y")).toDouble(-1.0);
        m_positions[it.key()] = pos;
    }
}

void DesktopBackend::savePositions()
{
    QString configDir = QDir::homePath() + QStringLiteral("/.config/titan");
    QDir().mkpath(configDir);

    QString configPath = configDir + QStringLiteral("/desktop_positions.json");

    QJsonObject root;
    for (auto it = m_positions.begin(); it != m_positions.end(); ++it) {
        QVariantMap posMap = it.value().toMap();
        QJsonObject posObj;
        posObj[QStringLiteral("x")] = posMap.value(QStringLiteral("x")).toDouble();
        posObj[QStringLiteral("y")] = posMap.value(QStringLiteral("y")).toDouble();
        root[it.key()] = posObj;
    }

    QFile file(configPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) return;
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    file.close();
}

