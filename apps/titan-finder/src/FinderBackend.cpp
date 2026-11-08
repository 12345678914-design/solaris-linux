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
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QTimer>
#include <QCoreApplication>
#include <QTextStream>
#include <algorithm>
#include <QDebug>
#include <QDrag>
#include <QMimeData>
#include <QPixmap>

static QString resolveFinderBinary(const QString &program)
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
        QDir::currentPath() + QStringLiteral("/iso/titan/airootfs/usr/local/bin/") + program
    };

    for (const QString &c : candidates) {
        if (QFile::exists(c) && QFileInfo(c).isExecutable()) {
            return c;
        }
    }
    return program;
}

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

    m_deviceTimer = new QTimer(this);
    m_deviceTimer->setInterval(2000);
    connect(m_deviceTimer, &QTimer::timeout, this, &FinderBackend::refreshDevices);
    m_deviceTimer->start();

    refreshDevices();
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

    QString desktop = home + QStringLiteral("/Escritorio");
    QDir().mkpath(desktop);
    addFav(QStringLiteral("Escritorio"), desktop, QStringLiteral("qrc:/icons/desktop.png"), QStringLiteral("Favoritos"));

    addFav(QStringLiteral("Aplicaciones"), QStringLiteral("/usr/share/applications"), QStringLiteral("qrc:/icons/apps-folder.png"), QStringLiteral("Favoritos"));

    QString documents = home + QStringLiteral("/Documentos");
    QDir().mkpath(documents);
    addFav(QStringLiteral("Documentos"), documents, QStringLiteral("qrc:/icons/files.png"), QStringLiteral("Favoritos"));

    QString downloads = home + QStringLiteral("/Descargas");
    QDir().mkpath(downloads);
    addFav(QStringLiteral("Descargas"), downloads, QStringLiteral("qrc:/icons/downloads.png"), QStringLiteral("Favoritos"));

    QString pictures = home + QStringLiteral("/Pictures");
    if (!QDir(pictures).exists() && QDir(home + QStringLiteral("/Imágenes")).exists()) {
        pictures = home + QStringLiteral("/Imágenes");
    } else {
        QDir().mkpath(pictures);
    }
    addFav(QStringLiteral("Pictures"), pictures, QStringLiteral("qrc:/icons/pictures.png"), QStringLiteral("Favoritos"));

    QString music = home + QStringLiteral("/Musica");
    if (!QDir(music).exists() && QDir(home + QStringLiteral("/Música")).exists()) {
        music = home + QStringLiteral("/Música");
    } else {
        QDir().mkpath(music);
    }
    addFav(QStringLiteral("Musica"), music, QStringLiteral("qrc:/icons/music-folder.png"), QStringLiteral("Favoritos"));

    QString videos = home + QStringLiteral("/Videos");
    QDir().mkpath(videos);
    addFav(QStringLiteral("Videos"), videos, QStringLiteral("qrc:/icons/file-video.png"), QStringLiteral("Favoritos"));

    QString proyectos = home + QStringLiteral("/Proyectos");
    QDir().mkpath(proyectos);
    addFav(QStringLiteral("Proyectos"), proyectos, QStringLiteral("qrc:/icons/developer.png"), QStringLiteral("Favoritos"));

    // Sección Ubicaciones
    addFav(QStringLiteral("Disco del Sistema"), QStringLiteral("/"), QStringLiteral("qrc:/icons/system.png"), QStringLiteral("Ubicaciones"));

    QString trash = home + QStringLiteral("/.local/share/Trash/files");
    QDir().mkpath(trash);
    addFav(QStringLiteral("Papelera"), trash, QStringLiteral("qrc:/icons/trash.png"), QStringLiteral("Ubicaciones"));

    // Sección Dispositivos (USBs y Discos detectados bajo demanda)
    for (const QVariant &v : m_devices) {
        m_favorites.append(v);
    }

    // Sección Etiquetas (macOS Tags con círculos de colores)
    addFav(QStringLiteral("Rojo"), QStringLiteral("tag:red"), QStringLiteral("color:#ff3b30"), QStringLiteral("Etiquetas"));
    addFav(QStringLiteral("Naranja"), QStringLiteral("tag:orange"), QStringLiteral("color:#ff9500"), QStringLiteral("Etiquetas"));
    addFav(QStringLiteral("Amarillo"), QStringLiteral("tag:yellow"), QStringLiteral("color:#ffcc00"), QStringLiteral("Etiquetas"));
    addFav(QStringLiteral("Verde"), QStringLiteral("tag:green"), QStringLiteral("color:#34c759"), QStringLiteral("Etiquetas"));
    addFav(QStringLiteral("Azul"), QStringLiteral("tag:blue"), QStringLiteral("color:#007aff"), QStringLiteral("Etiquetas"));
    addFav(QStringLiteral("Morado"), QStringLiteral("tag:purple"), QStringLiteral("color:#af52de"), QStringLiteral("Etiquetas"));
    addFav(QStringLiteral("Gris"), QStringLiteral("tag:gray"), QStringLiteral("color:#8e8e93"), QStringLiteral("Etiquetas"));

    emit favoritesChanged();
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
        if (name == QStringLiteral("applications") || name == QStringLiteral("aplicaciones") || path == QStringLiteral("/usr/share/applications"))
            return QStringLiteral("qrc:/icons/apps-folder.png");
        if (name == QStringLiteral("pictures") || name == QStringLiteral("imágenes") || name == QStringLiteral("imagenes") || name == QStringLiteral("fotos"))
            return QStringLiteral("qrc:/icons/pictures.png");
        if (name == QStringLiteral("music") || name == QStringLiteral("música") || name == QStringLiteral("musica"))
            return QStringLiteral("qrc:/icons/music-folder.png");
        if (name == QStringLiteral("videos"))
            return QStringLiteral("qrc:/icons/file-video.png");
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
        return QStringLiteral("qrc:/icons/file-audio.png");
    }

    // Video
    if (ext == QStringLiteral("mp4") || ext == QStringLiteral("mkv") || ext == QStringLiteral("avi") ||
        ext == QStringLiteral("mov") || ext == QStringLiteral("webm") || ext == QStringLiteral("flv")) {
        return QStringLiteral("qrc:/icons/file-video.png");
    }

    // PDF
    if (ext == QStringLiteral("pdf")) {
        return QStringLiteral("qrc:/icons/file-pdf.png");
    }

    // Documentos Word
    if (ext == QStringLiteral("doc") || ext == QStringLiteral("docx") || ext == QStringLiteral("odt")) {
        return QStringLiteral("qrc:/icons/file-word.png");
    }

    // Hojas de cálculo Excel
    if (ext == QStringLiteral("xls") || ext == QStringLiteral("xlsx") || ext == QStringLiteral("ods") || ext == QStringLiteral("csv")) {
        return QStringLiteral("qrc:/icons/file-excel.png");
    }

    // Presentaciones PowerPoint
    if (ext == QStringLiteral("ppt") || ext == QStringLiteral("pptx") || ext == QStringLiteral("odp")) {
        return QStringLiteral("qrc:/icons/file-powerpoint.png");
    }

    // Documentos y textos planos
    if (ext == QStringLiteral("txt") || ext == QStringLiteral("md") || ext == QStringLiteral("log") ||
        ext == QStringLiteral("conf") || ext == QStringLiteral("ini") || ext == QStringLiteral("cfg")) {
        return QStringLiteral("qrc:/icons/file-text.png");
    }

    // Código, scripts y desarrollo
    if (ext == QStringLiteral("c") || ext == QStringLiteral("cpp") || ext == QStringLiteral("h") ||
        ext == QStringLiteral("hpp") || ext == QStringLiteral("py") || ext == QStringLiteral("rs") ||
        ext == QStringLiteral("js") || ext == QStringLiteral("ts") || ext == QStringLiteral("qml") ||
        ext == QStringLiteral("html") || ext == QStringLiteral("css") || ext == QStringLiteral("json") ||
        ext == QStringLiteral("xml") || ext == QStringLiteral("sh") || ext == QStringLiteral("bash") ||
        ext == QStringLiteral("go") || ext == QStringLiteral("java") || ext == QStringLiteral("sql")) {
        return QStringLiteral("qrc:/icons/file-code.png");
    }

    // Archivos comprimidos y paquetes
    if (ext == QStringLiteral("zip") || ext == QStringLiteral("tar") || ext == QStringLiteral("gz") ||
        ext == QStringLiteral("bz2") || ext == QStringLiteral("xz") || ext == QStringLiteral("7z") ||
        ext == QStringLiteral("rar") || ext == QStringLiteral("zst") || ext == QStringLiteral("iso")) {
        return QStringLiteral("qrc:/icons/file-archive.png");
    }

    // Accesos directos y ejecutables
    if (ext == QStringLiteral("desktop")) {
        return QStringLiteral("qrc:/icons/launchpad.png");
    }
    if (info.isExecutable() || ext == QStringLiteral("bin") || ext == QStringLiteral("run")) {
        return QStringLiteral("qrc:/icons/file-exec.png");
    }

    // Archivos generales con icono de documento limpio
    return QStringLiteral("qrc:/icons/file-generic.png");
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
            QStringList parts = QProcess::splitCommand(exec);
            if (!parts.isEmpty()) {
                QString prog = resolveFinderBinary(parts.takeFirst());
                QProcess::startDetached(prog, parts);
                return;
            }
        }
    }

    // Si es ejecutable de consola/script
    if (info.isExecutable() && (info.suffix() == QStringLiteral("sh") || info.suffix() == QStringLiteral("bin") || info.suffix().isEmpty())) {
        QProcess::startDetached(info.absoluteFilePath(), QStringList());
        return;
    }

    // Documentos ofimáticos -> ONLYOFFICE DEBE SER EL PREDETERMINADO
    const QString ext = info.suffix().toLower();
    if (ext == QStringLiteral("docx") || ext == QStringLiteral("doc")  ||
        ext == QStringLiteral("xlsx") || ext == QStringLiteral("xls")  ||
        ext == QStringLiteral("pptx") || ext == QStringLiteral("ppt")  ||
        ext == QStringLiteral("odt")  || ext == QStringLiteral("ods")  || ext == QStringLiteral("odp") ||
        ext == QStringLiteral("rtf")  || ext == QStringLiteral("csv")) {
        QString oo = resolveFinderBinary(QStringLiteral("onlyoffice-desktopeditors"));
        if (!oo.isEmpty() && QFile::exists(oo)) {
            QProcess::startDetached(oo, QStringList() << info.absoluteFilePath());
            return;
        }
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

    // Crear acceso directo como enlace simbólico (mantiene tipo, extensión y apertura nativa)
    if (QFile::link(path, destPath)) {
        return true;
    }

    // Si el sistema de archivos no admite enlaces simbólicos, generar archivo .desktop
    QString desktopShortcut = desktopDir + QStringLiteral("/") + srcInfo.completeBaseName() + QStringLiteral(".desktop");
    QFile f(desktopShortcut);
    if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream out(&f);
        out << "[Desktop Entry]\n";
        out << "Version=1.0\n";
        out << "Type=Application\n";
        out << "Name=" << srcInfo.fileName() << "\n";

        QString ext = srcInfo.suffix().toLower();
        if (srcInfo.isDir()) {
            out << "Exec=titan-finder \"" << srcInfo.absoluteFilePath() << "\"\n";
            out << "Icon=/usr/share/titan/icons/folder.png\n";
        } else if (ext == QStringLiteral("docx") || ext == QStringLiteral("doc") ||
                   ext == QStringLiteral("xlsx") || ext == QStringLiteral("xls") ||
                   ext == QStringLiteral("pptx") || ext == QStringLiteral("ppt") ||
                   ext == QStringLiteral("odt")  || ext == QStringLiteral("ods") || ext == QStringLiteral("odp") ||
                   ext == QStringLiteral("rtf")  || ext == QStringLiteral("csv")) {
            out << "Exec=onlyoffice-desktopeditors \"" << srcInfo.absoluteFilePath() << "\"\n";
            out << "Icon=onlyoffice-desktopeditors\n";
        } else {
            out << "Exec=xdg-open \"" << srcInfo.absoluteFilePath() << "\"\n";
            out << "Icon=system\n";
        }
        out << "Terminal=false\n";
        f.close();
        f.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner | QFile::ReadGroup | QFile::ExeGroup | QFile::ReadOther | QFile::ExeOther);
        return true;
    }

    if (!srcInfo.isDir()) {
        return QFile::copy(path, destPath);
    }

    return false;
}

void FinderBackend::startDrag(const QString &path)
{
    if (path.isEmpty()) return;
    QString local = path;
    if (local.startsWith(QLatin1String("file://"))) {
        local = QUrl(path).toLocalFile();
    }
    if (!QFile::exists(local)) return;

    QDrag *drag = new QDrag(this);
    QMimeData *mimeData = new QMimeData();
    QList<QUrl> urls;
    urls.append(QUrl::fromLocalFile(local));
    mimeData->setUrls(urls);
    mimeData->setText(local);
    drag->setMimeData(mimeData);

    QFileInfo fi(local);
    QString iconPath = resolveIcon(fi);
    if (!iconPath.isEmpty()) {
        QString cleanIcon = iconPath;
        if (cleanIcon.startsWith(QLatin1String("qrc:"))) {
            cleanIcon = cleanIcon.mid(3);
        }
        QPixmap pm(cleanIcon);
        if (!pm.isNull()) {
            drag->setPixmap(pm.scaled(56, 56, Qt::KeepAspectRatio, Qt::SmoothTransformation));
            drag->setHotSpot(QPoint(28, 28));
        }
    }

    drag->exec(Qt::CopyAction | Qt::MoveAction);
}

static bool copyPathRecursively(const QString &srcFilePath, const QString &tgtFilePath);

bool FinderBackend::importFile(const QString &urlOrPath, const QString &targetDir)
{
    QString localPath = urlOrPath;
    if (localPath.startsWith(QLatin1String("file://"))) {
        localPath = QUrl(urlOrPath).toLocalFile();
    }
    if (localPath.isEmpty() || !QFile::exists(localPath)) return false;

    QString destDir = targetDir.isEmpty() ? m_currentPath : targetDir;
    QDir().mkpath(destDir);

    QFileInfo fi(localPath);
    if (fi.absolutePath() == destDir) return true;

    QString destPath = destDir + QStringLiteral("/") + fi.fileName();
    int counter = 1;
    while (QFile::exists(destPath)) {
        QString base = fi.completeBaseName();
        QString ext = fi.suffix().isEmpty() ? QString() : (QStringLiteral(".") + fi.suffix());
        destPath = destDir + QStringLiteral("/") + base + QStringLiteral(" (") + QString::number(++counter) + QStringLiteral(")") + ext;
    }

    bool ok = false;
    if (fi.isDir()) {
        ok = copyPathRecursively(localPath, destPath);
    } else {
        ok = QFile::copy(localPath, destPath);
    }

    if (ok) refresh();
    return ok;
}

static bool copyPathRecursively(const QString &srcFilePath, const QString &tgtFilePath)
{
    QFileInfo srcFileInfo(srcFilePath);
    if (srcFileInfo.isDir()) {
        QDir targetDir(tgtFilePath);
        targetDir.cdUp();
        if (!targetDir.mkdir(QFileInfo(tgtFilePath).fileName()))
            return false;
        QDir sourceDir(srcFilePath);
        QStringList fileNames = sourceDir.entryList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
        for (const QString &fileName : fileNames) {
            const QString newSrcFilePath = srcFilePath + QLatin1Char('/') + fileName;
            const QString newTgtFilePath = tgtFilePath + QLatin1Char('/') + fileName;
            if (!copyPathRecursively(newSrcFilePath, newTgtFilePath))
                return false;
        }
    } else {
        if (!QFile::copy(srcFilePath, tgtFilePath))
            return false;
    }
    return true;
}

void FinderBackend::copyItem(const QString &path)
{
    if (path.isEmpty() || (!QFile::exists(path) && !QDir(path).exists())) return;
    m_clipboardPath = path;
    emit clipboardChanged();
}

bool FinderBackend::paste(const QString &destinationDir)
{
    if (m_clipboardPath.isEmpty()) return false;
    QFileInfo srcInfo(m_clipboardPath);
    if (!srcInfo.exists()) return false;

    QString destDir = destinationDir.isEmpty() ? m_currentPath : destinationDir;
    QFileInfo destDirInfo(destDir);
    if (!destDirInfo.isDir()) {
        destDir = m_currentPath;
    }

    QString baseName = srcInfo.completeBaseName();
    QString suffix = srcInfo.suffix();
    QString destName = srcInfo.fileName();
    QString target = destDir + QLatin1Char('/') + destName;

    int counter = 1;
    while (QFile::exists(target) || QDir(target).exists()) {
        if (srcInfo.isDir() || suffix.isEmpty()) {
            destName = QStringLiteral("%1 (copia%2)").arg(baseName).arg(counter == 1 ? QString() : QStringLiteral(" %1").arg(counter));
        } else {
            destName = QStringLiteral("%1 (copia%2).%3").arg(baseName).arg(counter == 1 ? QString() : QStringLiteral(" %1").arg(counter)).arg(suffix);
        }
        target = destDir + QLatin1Char('/') + destName;
        counter++;
    }

    bool ok = copyPathRecursively(m_clipboardPath, target);
    if (ok) refresh();
    return ok;
}

QVariantMap FinderBackend::getFileProperties(const QString &path)
{
    QString target = path.isEmpty() ? m_currentPath : path;
    QFileInfo fi(target);
    QVariantMap map;
    if (!fi.exists()) return map;

    map[QStringLiteral("name")] = fi.fileName().isEmpty() ? fi.absoluteFilePath() : fi.fileName();
    map[QStringLiteral("path")] = fi.absoluteFilePath();
    map[QStringLiteral("dir")] = fi.absolutePath();
    map[QStringLiteral("isDir")] = fi.isDir();
    map[QStringLiteral("type")] = resolveType(fi);
    map[QStringLiteral("icon")] = resolveIcon(fi);
    map[QStringLiteral("size")] = fi.isDir() ? QStringLiteral("--") : formatBytes(fi.size());
    map[QStringLiteral("bytes")] = QString::number(fi.size()) + QStringLiteral(" bytes");
    map[QStringLiteral("modified")] = fi.lastModified().toString(QStringLiteral("dd/MM/yyyy HH:mm:ss"));
    map[QStringLiteral("created")] = fi.birthTime().isValid() ? fi.birthTime().toString(QStringLiteral("dd/MM/yyyy HH:mm:ss")) : fi.metadataChangeTime().toString(QStringLiteral("dd/MM/yyyy HH:mm:ss"));

    QFile::Permissions p = fi.permissions();
    QString permStr;
    permStr += (p & QFileDevice::ReadUser) ? 'r' : '-';
    permStr += (p & QFileDevice::WriteUser) ? 'w' : '-';
    permStr += (p & QFileDevice::ExeUser) ? 'x' : '-';
    permStr += (p & QFileDevice::ReadGroup) ? 'r' : '-';
    permStr += (p & QFileDevice::WriteGroup) ? 'w' : '-';
    permStr += (p & QFileDevice::ExeGroup) ? 'x' : '-';
    permStr += (p & QFileDevice::ReadOther) ? 'r' : '-';
    permStr += (p & QFileDevice::WriteOther) ? 'w' : '-';
    permStr += (p & QFileDevice::ExeOther) ? 'x' : '-';
    map[QStringLiteral("permissions")] = permStr;
    map[QStringLiteral("owner")] = fi.owner();
    map[QStringLiteral("group")] = fi.group();

    return map;
}

void FinderBackend::refreshDevices()
{
    QProcess proc;
    proc.start(QStringLiteral("lsblk"), {QStringLiteral("-J"), QStringLiteral("-o"), QStringLiteral("NAME,KNAME,LABEL,MOUNTPOINT,SIZE,TYPE,TRAN,RM,HOTPLUG,FSTYPE,MODEL")});
    if (!proc.waitForFinished(1200)) {
        return;
    }

    QByteArray data = proc.readAllStandardOutput();
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) return;

    QJsonObject root = doc.object();
    QJsonArray blockdevices = root[QStringLiteral("blockdevices")].toArray();

    QVariantList newDevices;

    auto processDev = [&](const QJsonObject &obj, bool parentIsUsb, const QString &parentModel) {
        QString type = obj[QStringLiteral("type")].toString();
        QString kname = obj[QStringLiteral("kname")].toString();
        QString tran = obj[QStringLiteral("tran")].toString();
        bool rm = obj[QStringLiteral("rm")].toBool();
        bool hotplug = obj[QStringLiteral("hotplug")].toBool();
        QString fstype = obj[QStringLiteral("fstype")].toString();
        QString size = obj[QStringLiteral("size")].toString();
        QString label = obj[QStringLiteral("label")].toString().trimmed();
        QString model = obj[QStringLiteral("model")].toString().trimmed();
        if (model.isEmpty()) model = parentModel;
        QJsonValue mpVal = obj[QStringLiteral("mountpoint")];
        QString mountpoint = mpVal.isNull() ? QString() : mpVal.toString();

        if (kname.startsWith(QStringLiteral("zram")) || kname.startsWith(QStringLiteral("loop")) || mountpoint == QStringLiteral("[SWAP]")) {
            return;
        }

        bool isUsb = parentIsUsb || (tran == QStringLiteral("usb") || rm || hotplug);

        if (type == QStringLiteral("part") || (!fstype.isEmpty() && type == QStringLiteral("disk"))) {
            QVariantMap dev;
            QString devNode = QStringLiteral("/dev/") + kname;
            dev[QStringLiteral("deviceNode")] = devNode;
            dev[QStringLiteral("kname")] = kname;
            dev[QStringLiteral("isUsb")] = isUsb;
            dev[QStringLiteral("size")] = size;
            dev[QStringLiteral("fsType")] = fstype;

            bool isMounted = !mountpoint.isEmpty() && QFile::exists(mountpoint);
            dev[QStringLiteral("isMounted")] = isMounted;
            dev[QStringLiteral("mountPoint")] = mountpoint;
            dev[QStringLiteral("path")] = isMounted ? mountpoint : (QStringLiteral("device:") + devNode);

            QString displayName;
            if (!label.isEmpty()) {
                displayName = label;
            } else if (isUsb) {
                displayName = QStringLiteral("USB (") + kname + QStringLiteral(" - ") + size + QStringLiteral(")");
            } else if (!model.isEmpty()) {
                displayName = model + QStringLiteral(" (") + size + QStringLiteral(")");
            } else {
                displayName = QStringLiteral("Disco (") + kname + QStringLiteral(" - ") + size + QStringLiteral(")");
            }

            dev[QStringLiteral("name")] = displayName;
            dev[QStringLiteral("icon")] = isUsb ? QStringLiteral("qrc:/icons/usb.png") : QStringLiteral("qrc:/icons/system.png");
            dev[QStringLiteral("section")] = QStringLiteral("Dispositivos");
            dev[QStringLiteral("isDevice")] = true;

            newDevices.append(dev);
        }
    };

    for (const QJsonValue &v : blockdevices) {
        QJsonObject bdev = v.toObject();
        QString tran = bdev[QStringLiteral("tran")].toString();
        bool rm = bdev[QStringLiteral("rm")].toBool();
        bool hotplug = bdev[QStringLiteral("hotplug")].toBool();
        bool isUsb = (tran == QStringLiteral("usb") || rm || hotplug);
        QString model = bdev[QStringLiteral("model")].toString().trimmed();

        if (bdev.contains(QStringLiteral("children")) && bdev[QStringLiteral("children")].isArray()) {
            QJsonArray children = bdev[QStringLiteral("children")].toArray();
            for (const QJsonValue &cv : children) {
                processDev(cv.toObject(), isUsb, model);
            }
        } else {
            processDev(bdev, isUsb, model);
        }
    }

    if (newDevices != m_devices) {
        m_devices = newDevices;
        emit devicesChanged();
        initFavorites();
    }
}

bool FinderBackend::mountDevice(const QString &deviceNode)
{
    if (deviceNode.isEmpty()) return false;

    // Regla de seguridad: montar solo bajo demanda cuando el usuario da clic una vez
    QProcess proc;
    proc.start(QStringLiteral("udisksctl"), {QStringLiteral("mount"), QStringLiteral("-b"), deviceNode, QStringLiteral("--no-user-interaction")});
    if (proc.waitForFinished(5000) && proc.exitCode() == 0) {
        refreshDevices();
        return true;
    }

    QString kname = QFileInfo(deviceNode).fileName();
    QString user = qgetenv("USER");
    if (user.isEmpty()) user = QStringLiteral("titan");
    QString userMediaDir = QStringLiteral("/run/media/") + user + QStringLiteral("/") + kname;
    QDir().mkpath(userMediaDir);

    QProcess sudoMount;
    sudoMount.start(QStringLiteral("sudo"), {QStringLiteral("-n"), QStringLiteral("mount"), QStringLiteral("-o"), QStringLiteral("nodev,nosuid"), deviceNode, userMediaDir});
    if (sudoMount.waitForFinished(3000) && sudoMount.exitCode() == 0) {
        refreshDevices();
        return true;
    }
    return false;
}

bool FinderBackend::unmountDevice(const QString &deviceNode)
{
    if (deviceNode.isEmpty()) return false;

    for (const QVariant &v : m_devices) {
        QVariantMap d = v.toMap();
        if (d[QStringLiteral("deviceNode")].toString() == deviceNode) {
            QString mp = d[QStringLiteral("mountPoint")].toString();
            if (!mp.isEmpty() && (m_currentPath == mp || m_currentPath.startsWith(mp + QStringLiteral("/")))) {
                goTo(QDir::homePath());
            }
            break;
        }
    }

    QProcess proc;
    proc.start(QStringLiteral("udisksctl"), {QStringLiteral("unmount"), QStringLiteral("-b"), deviceNode, QStringLiteral("--no-user-interaction")});
    if (!proc.waitForFinished(4000) || proc.exitCode() != 0) {
        QProcess sudoUmount;
        sudoUmount.start(QStringLiteral("sudo"), {QStringLiteral("-n"), QStringLiteral("umount"), deviceNode});
        sudoUmount.waitForFinished(3000);
    }
    refreshDevices();
    return true;
}

bool FinderBackend::mountAndOpen(const QString &deviceNode)
{
    for (const QVariant &v : m_devices) {
        QVariantMap d = v.toMap();
        if (d[QStringLiteral("deviceNode")].toString() == deviceNode && d[QStringLiteral("isMounted")].toBool()) {
            QString mp = d[QStringLiteral("mountPoint")].toString();
            if (!mp.isEmpty() && QDir(mp).exists()) {
                goTo(mp);
                return true;
            }
        }
    }

    if (mountDevice(deviceNode)) {
        for (const QVariant &v : m_devices) {
            QVariantMap d = v.toMap();
            if (d[QStringLiteral("deviceNode")].toString() == deviceNode && d[QStringLiteral("isMounted")].toBool()) {
                QString mp = d[QStringLiteral("mountPoint")].toString();
                if (!mp.isEmpty() && QDir(mp).exists()) {
                    goTo(mp);
                    return true;
                }
            }
        }

        QFile mounts(QStringLiteral("/proc/mounts"));
        if (mounts.open(QIODevice::ReadOnly | QIODevice::Text)) {
            while (!mounts.atEnd()) {
                QString line = QString::fromUtf8(mounts.readLine());
                if (line.startsWith(deviceNode + QLatin1Char(' '))) {
                    QStringList parts = line.split(QLatin1Char(' '));
                    if (parts.size() >= 2) {
                        goTo(parts.at(1));
                        return true;
                    }
                }
            }
        }
    }
    return false;
}
