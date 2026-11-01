#include "FinderBackend.h"

#include <QDir>
#include <QFile>
#include <QFileInfoList>
#include <QProcess>
#include <QDesktopServices>
#include <QUrl>
#include <QSettings>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QDateTime>
#include <QStorageInfo>
#include <algorithm>
#include <QDebug>

FinderBackend::FinderBackend(QObject *parent)
    : QObject(parent)
    , m_historyIndex(-1)
    , m_showHiddenFiles(false)
    , m_searchQuery(QString())
    , m_viewMode(QStringLiteral("list"))
    , m_sortBy(QStringLiteral("name"))
    , m_sortAscending(true)
    , m_watcher(new QFileSystemWatcher(this))
{
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &FinderBackend::onDirectoryChanged);

    initFavorites();

    // Iniciar en el directorio personal del usuario
    goTo(QDir::homePath());
}

void FinderBackend::initFavorites()
{
    m_favorites.clear();

    auto addFav = [this](const QString &name, const QString &path, const QString &icon, const QString &section) {
        if (QDir(path).exists() || path == QStringLiteral("/") || path.startsWith(QStringLiteral("tag:"))) {
            QVariantMap item;
            item[QStringLiteral("name")] = name;
            item[QStringLiteral("path")] = path;
            item[QStringLiteral("icon")] = icon;
            item[QStringLiteral("section")] = section;
            m_favorites.append(item);
        }
    };

    const QString home = QDir::homePath();

    // Sección Favoritos estilo macOS
    addFav(QStringLiteral("Recientes"), home, QStringLiteral("qrc:/icons/notes.png"), QStringLiteral("Favoritos"));

    QString desktop = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    if (!QDir(desktop).exists()) desktop = home + QStringLiteral("/Escritorio");
    addFav(QStringLiteral("Escritorio"), desktop, QStringLiteral("qrc:/icons/desktop.png"), QStringLiteral("Favoritos"));

    addFav(QStringLiteral("Aplicaciones"), QStringLiteral("/usr/share/applications"), QStringLiteral("qrc:/icons/launchpad.png"), QStringLiteral("Favoritos"));

    QString documents = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (!QDir(documents).exists()) documents = home + QStringLiteral("/Documentos");
    addFav(QStringLiteral("Documentos"), documents, QStringLiteral("qrc:/icons/files.png"), QStringLiteral("Favoritos"));

    QString downloads = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (!QDir(downloads).exists()) downloads = home + QStringLiteral("/Descargas");
    addFav(QStringLiteral("Descargas"), downloads, QStringLiteral("qrc:/icons/downloads.png"), QStringLiteral("Favoritos"));

    QString pictures = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    if (!QDir(pictures).exists()) pictures = home + QStringLiteral("/Imágenes");
    addFav(QStringLiteral("Imágenes"), pictures, QStringLiteral("qrc:/icons/pictures.png"), QStringLiteral("Favoritos"));

    QString music = QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
    if (!QDir(music).exists()) music = home + QStringLiteral("/Música");
    addFav(QStringLiteral("Música"), music, QStringLiteral("qrc:/icons/music.png"), QStringLiteral("Favoritos"));

    // Sección iCloud / Ubicaciones
    addFav(QStringLiteral("iCloud Drive"), home, QStringLiteral("qrc:/icons/finder.png"), QStringLiteral("iCloud"));
    addFav(QStringLiteral("Disco TITAN"), QStringLiteral("/"), QStringLiteral("qrc:/icons/system.png"), QStringLiteral("iCloud"));

    QString trash = home + QStringLiteral("/.local/share/Trash/files");
    QDir().mkpath(trash);
    addFav(QStringLiteral("Papelera"), trash, QStringLiteral("qrc:/icons/trash.png"), QStringLiteral("iCloud"));

    // Sección Etiquetas (macOS Tags con círculos de colores)
    addFav(QStringLiteral("Rojo"), QStringLiteral("tag:red"), QStringLiteral("color:#ff3b30"), QStringLiteral("Etiquetas"));
    addFav(QStringLiteral("Naranja"), QStringLiteral("tag:orange"), QStringLiteral("color:#ff9500"), QStringLiteral("Etiquetas"));
    addFav(QStringLiteral("Amarillo"), QStringLiteral("tag:yellow"), QStringLiteral("color:#ffcc00"), QStringLiteral("Etiquetas"));
    addFav(QStringLiteral("Verde"), QStringLiteral("tag:green"), QStringLiteral("color:#34c759"), QStringLiteral("Etiquetas"));
    addFav(QStringLiteral("Azul"), QStringLiteral("tag:blue"), QStringLiteral("color:#007aff"), QStringLiteral("Etiquetas"));
    addFav(QStringLiteral("Morado"), QStringLiteral("tag:purple"), QStringLiteral("color:#af52de"), QStringLiteral("Etiquetas"));
    addFav(QStringLiteral("Gris"), QStringLiteral("tag:gray"), QStringLiteral("color:#8e8e93"), QStringLiteral("Etiquetas"));
}

QString FinderBackend::currentPathName() const
{
    if (m_currentPath == QDir::homePath()) return QStringLiteral("Inicio");
    if (m_currentPath == QStringLiteral("/")) return QStringLiteral("Sistema");

    QDir dir(m_currentPath);
    QString name = dir.dirName();
    if (name.isEmpty()) return m_currentPath;
    return name;
}

bool FinderBackend::canGoUp() const
{
    return m_currentPath != QStringLiteral("/") && !m_currentPath.isEmpty();
}

QVariantList FinderBackend::pathSegments() const
{
    QVariantList segments;
    if (m_currentPath.isEmpty()) return segments;

    QVariantMap rootSeg;
    rootSeg[QStringLiteral("name")] = QStringLiteral("Sistema");
    rootSeg[QStringLiteral("path")] = QStringLiteral("/");
    segments.append(rootSeg);

    QStringList parts = m_currentPath.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    QString accumulated = QStringLiteral("");

    for (int i = 0; i < parts.size(); ++i) {
        accumulated += QStringLiteral("/") + parts.at(i);
        QVariantMap seg;
        QString displayName = parts.at(i);
        if (accumulated == QDir::homePath()) {
            displayName = QStringLiteral("Inicio");
        }
        seg[QStringLiteral("name")] = displayName;
        seg[QStringLiteral("path")] = accumulated;
        segments.append(seg);
    }

    return segments;
}

void FinderBackend::goTo(const QString &path)
{
    QDir target(path);
    QString canonical = target.canonicalPath();
    if (canonical.isEmpty()) canonical = path;
    if (!QDir(canonical).exists()) return;

    // Actualizar historial
    if (m_historyIndex >= 0 && m_historyIndex < m_history.size() - 1) {
        while (m_history.size() > m_historyIndex + 1) {
            m_history.removeLast();
        }
    }
    m_history.append(canonical);
    m_historyIndex = m_history.size() - 1;
    emit historyChanged();

    loadDirectory(canonical);
}

void FinderBackend::goBack()
{
    if (canGoBack()) {
        m_historyIndex--;
        emit historyChanged();
        loadDirectory(m_history.at(m_historyIndex));
    }
}

void FinderBackend::goForward()
{
    if (canGoForward()) {
        m_historyIndex++;
        emit historyChanged();
        loadDirectory(m_history.at(m_historyIndex));
    }
}

void FinderBackend::goUp()
{
    if (canGoUp()) {
        QDir dir(m_currentPath);
        if (dir.cdUp()) {
            goTo(dir.absolutePath());
        }
    }
}

void FinderBackend::refresh()
{
    loadDirectory(m_currentPath);
}

void FinderBackend::onDirectoryChanged(const QString &path)
{
    if (path == m_currentPath) {
        loadDirectory(m_currentPath);
    }
}

void FinderBackend::loadDirectory(const QString &path)
{
    m_currentPath = path;

    // Actualizar observador de cambios en disco
    const auto watched = m_watcher->directories();
    if (!watched.isEmpty()) {
        m_watcher->removePaths(watched);
    }
    if (QDir(path).exists()) {
        m_watcher->addPath(path);
    }

    m_rawEntries.clear();

    QDir dir(path);
    QDir::Filters filters = QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot;
    if (m_showHiddenFiles) {
        filters |= QDir::Hidden;
    }

    const QFileInfoList list = dir.entryInfoList(filters, QDir::DirsFirst | QDir::Name);

    for (const QFileInfo &info : list) {
        QVariantMap entry;
        entry[QStringLiteral("name")] = info.fileName();
        entry[QStringLiteral("path")] = info.absoluteFilePath();
        entry[QStringLiteral("isDir")] = info.isDir();
        entry[QStringLiteral("isSymLink")] = info.isSymLink();
        entry[QStringLiteral("isHidden")] = info.isHidden();
        entry[QStringLiteral("isExecutable")] = info.isExecutable();

        if (info.isDir()) {
            QDir sub(info.absoluteFilePath());
            const uint count = sub.entryList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot).size();
            entry[QStringLiteral("size")] = QStringLiteral("%1 elementos").arg(count);
            entry[QStringLiteral("sizeBytes")] = static_cast<qint64>(count);
        } else {
            entry[QStringLiteral("size")] = formatBytes(info.size());
            entry[QStringLiteral("sizeBytes")] = info.size();
        }

        const QDateTime modified = info.lastModified();
        entry[QStringLiteral("modified")] = modified.toString(QStringLiteral("d MMM yyyy, hh:mm"));
        entry[QStringLiteral("modifiedTimestamp")] = modified.toMSecsSinceEpoch();

        entry[QStringLiteral("type")] = resolveType(info);
        entry[QStringLiteral("icon")] = resolveIcon(info);

        m_rawEntries.append(entry);
    }

    updateFreeSpace();
    filterAndSortEntries();

    emit currentPathChanged();
}

void FinderBackend::filterAndSortEntries()
{
    m_filteredEntries.clear();

    const QString query = m_searchQuery.trimmed().toLower();

    for (const QVariant &var : m_rawEntries) {
        const QVariantMap item = var.toMap();
        if (!query.isEmpty()) {
            const QString name = item.value(QStringLiteral("name")).toString().toLower();
            if (!name.contains(query)) continue;
        }
        m_filteredEntries.append(item);
    }

    // Ordenamiento natural estilo macOS: carpetas primero, luego archivos
    std::sort(m_filteredEntries.begin(), m_filteredEntries.end(), [this](const QVariant &a, const QVariant &b) {
        const QVariantMap ma = a.toMap();
        const QVariantMap mb = b.toMap();

        const bool dirA = ma.value(QStringLiteral("isDir")).toBool();
        const bool dirB = mb.value(QStringLiteral("isDir")).toBool();

        if (dirA != dirB) {
            return dirA; // Carpetas siempre primero
        }

        if (m_sortBy == QStringLiteral("size")) {
            const qint64 sA = ma.value(QStringLiteral("sizeBytes")).toLongLong();
            const qint64 sB = mb.value(QStringLiteral("sizeBytes")).toLongLong();
            return m_sortAscending ? (sA < sB) : (sA > sB);
        }

        if (m_sortBy == QStringLiteral("date")) {
            const qint64 tA = ma.value(QStringLiteral("modifiedTimestamp")).toLongLong();
            const qint64 tB = mb.value(QStringLiteral("modifiedTimestamp")).toLongLong();
            return m_sortAscending ? (tA < tB) : (tA > tB);
        }

        if (m_sortBy == QStringLiteral("kind")) {
            const QString kA = ma.value(QStringLiteral("type")).toString();
            const QString kB = mb.value(QStringLiteral("type")).toString();
            if (kA != kB) {
                return m_sortAscending ? (kA.localeAwareCompare(kB) < 0) : (kA.localeAwareCompare(kB) > 0);
            }
        }

        const QString nA = ma.value(QStringLiteral("name")).toString();
        const QString nB = mb.value(QStringLiteral("name")).toString();
        return m_sortAscending ? (nA.localeAwareCompare(nB) < 0) : (nA.localeAwareCompare(nB) > 0);
    });

    emit entriesChanged();
}

QString FinderBackend::resolveIcon(const QFileInfo &info) const
{
    if (info.isDir()) {
        const QString name = info.fileName().toLower();
        const QString path = info.absoluteFilePath();
        const QString home = QDir::homePath();

        if (name == QStringLiteral("desktop") || name == QStringLiteral("escritorio"))
            return QStringLiteral("qrc:/icons/desktop.png");
        if (name == QStringLiteral("downloads") || name == QStringLiteral("descargas"))
            return QStringLiteral("qrc:/icons/downloads.png");
        if (name == QStringLiteral("documents") || name == QStringLiteral("documentos"))
            return QStringLiteral("qrc:/icons/notes.png");
        if (name == QStringLiteral("pictures") || name == QStringLiteral("imágenes") || name == QStringLiteral("imagenes") || name == QStringLiteral("fotos"))
            return QStringLiteral("qrc:/icons/pictures.png");
        if (name == QStringLiteral("music") || name == QStringLiteral("música") || name == QStringLiteral("musica"))
            return QStringLiteral("qrc:/icons/music.png");
        if (name == QStringLiteral("developer") || name == QStringLiteral("proyectos") || name == QStringLiteral("codigo") || name == QStringLiteral("código") || name == QStringLiteral("src"))
            return QStringLiteral("qrc:/icons/developer.png");
        if (path.contains(QStringLiteral("Trash")))
            return QStringLiteral("qrc:/icons/trash.png");
        if (path == QStringLiteral("/") || path == QStringLiteral("/etc") || path == QStringLiteral("/usr") || path == QStringLiteral("/var") || path == QStringLiteral("/boot"))
            return QStringLiteral("qrc:/icons/system.png");

        return QStringLiteral("qrc:/icons/folder.png");
    }

    const QString ext = info.suffix().toLower();

    // Imágenes: usar vista previa directa si es posible
    if (ext == QStringLiteral("png") || ext == QStringLiteral("jpg") || ext == QStringLiteral("jpeg") ||
        ext == QStringLiteral("svg") || ext == QStringLiteral("webp") || ext == QStringLiteral("gif")) {
        return QUrl::fromLocalFile(info.absoluteFilePath()).toString();
    }

    // Audio
    if (ext == QStringLiteral("mp3") || ext == QStringLiteral("wav") || ext == QStringLiteral("ogg") ||
        ext == QStringLiteral("flac") || ext == QStringLiteral("m4a") || ext == QStringLiteral("aac")) {
        return QStringLiteral("qrc:/icons/music.png");
    }

    // Documentos y textos
    if (ext == QStringLiteral("txt") || ext == QStringLiteral("md") || ext == QStringLiteral("pdf") ||
        ext == QStringLiteral("doc") || ext == QStringLiteral("docx") || ext == QStringLiteral("odt") ||
        ext == QStringLiteral("log") || ext == QStringLiteral("conf") || ext == QStringLiteral("ini")) {
        return QStringLiteral("qrc:/icons/notes.png");
    }

    // Código, scripts y desarrollo
    if (ext == QStringLiteral("c") || ext == QStringLiteral("cpp") || ext == QStringLiteral("h") ||
        ext == QStringLiteral("hpp") || ext == QStringLiteral("py") || ext == QStringLiteral("rs") ||
        ext == QStringLiteral("js") || ext == QStringLiteral("ts") || ext == QStringLiteral("qml") ||
        ext == QStringLiteral("html") || ext == QStringLiteral("css") || ext == QStringLiteral("json") ||
        ext == QStringLiteral("xml") || ext == QStringLiteral("sh") || ext == QStringLiteral("bash")) {
        return QStringLiteral("qrc:/icons/developer.png");
    }

    // Ejecutables y aplicaciones
    if (ext == QStringLiteral("desktop")) {
        return QStringLiteral("qrc:/icons/launchpad.png");
    }
    if (info.isExecutable() || ext == QStringLiteral("bin") || ext == QStringLiteral("run")) {
        return QStringLiteral("qrc:/icons/terminal.png");
    }

    // Archivos comprimidos y generales
    return QStringLiteral("qrc:/icons/files.png");
}

QString FinderBackend::resolveType(const QFileInfo &info) const
{
    if (info.isDir()) return QStringLiteral("Carpeta");

    const QString ext = info.suffix().toLower();
    if (ext == QStringLiteral("png")) return QStringLiteral("Imagen PNG");
    if (ext == QStringLiteral("jpg") || ext == QStringLiteral("jpeg")) return QStringLiteral("Imagen JPEG");
    if (ext == QStringLiteral("svg")) return QStringLiteral("Gráfico vectorial SVG");
    if (ext == QStringLiteral("mp3")) return QStringLiteral("Audio MP3");
    if (ext == QStringLiteral("flac")) return QStringLiteral("Audio FLAC");
    if (ext == QStringLiteral("txt")) return QStringLiteral("Documento de texto");
    if (ext == QStringLiteral("md")) return QStringLiteral("Documento Markdown");
    if (ext == QStringLiteral("pdf")) return QStringLiteral("Documento PDF");
    if (ext == QStringLiteral("cpp") || ext == QStringLiteral("c") || ext == QStringLiteral("h")) return QStringLiteral("Código C/C++");
    if (ext == QStringLiteral("py")) return QStringLiteral("Script Python");
    if (ext == QStringLiteral("rs")) return QStringLiteral("Código Rust");
    if (ext == QStringLiteral("sh")) return QStringLiteral("Script Shell");
    if (ext == QStringLiteral("qml")) return QStringLiteral("Interfaz QML");
    if (ext == QStringLiteral("json")) return QStringLiteral("Archivo JSON");
    if (ext == QStringLiteral("tar") || ext == QStringLiteral("gz") || ext == QStringLiteral("zip") || ext == QStringLiteral("zst")) return QStringLiteral("Archivo comprimido");
    if (info.isExecutable()) return QStringLiteral("Archivo ejecutable");

    return QStringLiteral("Archivo");
}

QString FinderBackend::formatBytes(qint64 bytes) const
{
    if (bytes <= 0) return QStringLiteral("0 B");
    const double gib = 1024.0 * 1024.0 * 1024.0;
    const double mib = 1024.0 * 1024.0;
    const double kib = 1024.0;
    if (bytes >= gib) return QStringLiteral("%1 GiB").arg(bytes / gib, 0, 'f', 1);
    if (bytes >= mib) return QStringLiteral("%1 MiB").arg(bytes / mib, 0, 'f', 1);
    if (bytes >= kib) return QStringLiteral("%1 KiB").arg(bytes / kib, 0, 'f', 0);
    return QStringLiteral("%1 B").arg(bytes);
}

void FinderBackend::updateFreeSpace()
{
    QStorageInfo storage(m_currentPath);
    if (storage.isValid() && storage.isReady()) {
        m_freeSpaceText = QStringLiteral("%1 disponibles").arg(formatBytes(storage.bytesAvailable()));
    } else {
        m_freeSpaceText = QStringLiteral("Espacio disponible desconocido");
    }
    emit freeSpaceTextChanged();
}

QString FinderBackend::totalItemsText() const
{
    const int count = m_filteredEntries.size();
    if (count == 1) return QStringLiteral("1 elemento");
    return QStringLiteral("%1 elementos").arg(count);
}

void FinderBackend::setShowHiddenFiles(bool show)
{
    if (m_showHiddenFiles != show) {
        m_showHiddenFiles = show;
        emit showHiddenFilesChanged();
        refresh();
    }
}

void FinderBackend::setSearchQuery(const QString &query)
{
    if (m_searchQuery != query) {
        m_searchQuery = query;
        emit searchQueryChanged();
        filterAndSortEntries();
    }
}

void FinderBackend::setViewMode(const QString &mode)
{
    if (m_viewMode != mode) {
        m_viewMode = mode;
        emit viewModeChanged();
    }
}

void FinderBackend::setSortBy(const QString &by)
{
    if (m_sortBy != by) {
        m_sortBy = by;
        emit sortChanged();
        filterAndSortEntries();
    }
}

void FinderBackend::setSortAscending(bool asc)
{
    if (m_sortAscending != asc) {
        m_sortAscending = asc;
        emit sortChanged();
        filterAndSortEntries();
    }
}

void FinderBackend::sort(const QString &criteria)
{
    if (m_sortBy == criteria) {
        setSortAscending(!m_sortAscending);
    } else {
        m_sortBy = criteria;
        m_sortAscending = true;
        emit sortChanged();
        filterAndSortEntries();
    }
}

void FinderBackend::openItem(const QString &path)
{
    QFileInfo info(path);
    if (!info.exists()) return;

    if (info.isDir()) {
        goTo(info.absoluteFilePath());
        return;
    }

    // Si es un lanzador .desktop
    if (info.suffix() == QStringLiteral("desktop")) {
        QSettings desktop(info.absoluteFilePath(), QSettings::IniFormat);
        desktop.beginGroup(QStringLiteral("Desktop Entry"));
        QString exec = desktop.value(QStringLiteral("Exec")).toString();
        exec.remove(QRegularExpression(QStringLiteral("%[a-zA-Z]")));
        exec = exec.trimmed();
        if (!exec.isEmpty()) {
            QProcess::startDetached(exec, QStringList());
            return;
        }
    }

    // Si es ejecutable de consola/script
    if (info.isExecutable() && (info.suffix() == QStringLiteral("sh") || info.suffix() == QStringLiteral("bin") || info.suffix().isEmpty())) {
        QProcess::startDetached(info.absoluteFilePath(), QStringList());
        return;
    }

    // Abrir con aplicación asociada del sistema
    if (!QDesktopServices::openUrl(QUrl::fromLocalFile(info.absoluteFilePath()))) {
        QProcess::startDetached(QStringLiteral("xdg-open"), QStringList() << info.absoluteFilePath());
    }
}

void FinderBackend::openTerminal(const QString &path)
{
    QString dir = path.isEmpty() ? m_currentPath : path;
    QFileInfo info(dir);
    if (!info.isDir()) {
        dir = info.absolutePath();
    }

    if (QFile::exists(QStringLiteral("/usr/local/bin/titan-terminal"))) {
        QProcess::startDetached(QStringLiteral("/usr/local/bin/titan-terminal"), QStringList(), dir);
    } else if (QFile::exists(QStringLiteral("/usr/bin/kitty"))) {
        QProcess::startDetached(QStringLiteral("/usr/bin/kitty"), QStringList() << QStringLiteral("--directory") << dir);
    } else {
        QProcess::startDetached(QStringLiteral("xdg-open"), QStringList() << dir);
    }
}

bool FinderBackend::createFolder(const QString &name)
{
    QString base = name.trimmed().isEmpty() ? QStringLiteral("Nueva carpeta") : name.trimmed();
    QDir dir(m_currentPath);
    QString candidate = base;
    int index = 2;
    while (dir.exists(candidate)) {
        candidate = QStringLiteral("%1 %2").arg(base).arg(index++);
    }
    bool ok = dir.mkdir(candidate);
    if (ok) refresh();
    return ok;
}

bool FinderBackend::deleteItem(const QString &path)
{
    QFileInfo info(path);
    if (!info.exists()) return false;

    QString trashFiles = QDir::homePath() + QStringLiteral("/.local/share/Trash/files");
    QDir().mkpath(trashFiles);

    QString dest = trashFiles + QStringLiteral("/") + info.fileName();
    if (QFile::exists(dest)) {
        dest = trashFiles + QStringLiteral("/") + QString::number(QDateTime::currentMSecsSinceEpoch()) + QStringLiteral("_") + info.fileName();
    }

    bool ok = QFile::rename(path, dest);
    if (!ok) {
        if (info.isDir()) {
            ok = QDir(path).removeRecursively();
        } else {
            ok = QFile::remove(path);
        }
    }
    if (ok) refresh();
    return ok;
}

bool FinderBackend::renameItem(const QString &oldPath, const QString &newName)
{
    if (newName.trimmed().isEmpty()) return false;
    QFileInfo info(oldPath);
    if (!info.exists()) return false;
    QString target = info.absolutePath() + QStringLiteral("/") + newName.trimmed();
    bool ok = QFile::rename(oldPath, target);
    if (ok) refresh();
    return ok;
}

bool FinderBackend::sendToDesktop(const QString &path)
{
    if (path.isEmpty() || !QFile::exists(path)) return false;

    QString desktopDir = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    if (desktopDir.isEmpty() || !QDir(desktopDir).exists()) {
        desktopDir = QDir::homePath() + QStringLiteral("/Escritorio");
    }
    QDir().mkpath(desktopDir);

    QFileInfo srcInfo(path);
    QString destName = srcInfo.fileName();
    QString destPath = desktopDir + QStringLiteral("/") + destName;

    int counter = 1;
    while (QFile::exists(destPath)) {
        if (srcInfo.isDir()) {
            destPath = desktopDir + QStringLiteral("/") + destName + QStringLiteral(" (") + QString::number(++counter) + QStringLiteral(")");
        } else {
            QString base = srcInfo.completeBaseName();
            QString ext = srcInfo.suffix().isEmpty() ? QString() : (QStringLiteral(".") + srcInfo.suffix());
            destPath = desktopDir + QStringLiteral("/") + base + QStringLiteral(" (") + QString::number(++counter) + QStringLiteral(")") + ext;
        }
    }

    if (srcInfo.suffix().toLower() == QStringLiteral("desktop")) {
        return QFile::copy(path, destPath);
    }

    if (QFile::link(path, destPath)) {
        return true;
    }

    if (!srcInfo.isDir()) {
        return QFile::copy(path, destPath);
    }

    return false;
}
