#include "FinderBackend.h"
#include "TitanPredeterminadas.h"
#include "TitanDesktopEntry.h"

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
#include <QGuiApplication>
#include <QClipboard>
#include <QLocale>
#include <QMimeDatabase>
#include <QMimeType>
#include <QSet>
#include <QImageReader>

// "Música" y "musica" son lo mismo al buscar
QString sinAcentos(const QString &t)
{
    QString r;
    const QString n = t.toLower().normalized(QString::NormalizationForm_D);
    r.reserve(n.size());
    for (const QChar c : n)
        if (c.category() != QChar::Mark_NonSpacing)
            r.append(c);
    return r;
}

namespace {
bool esFoto(const QString &ext)
{
    static const QSet<QString> fotos = {QStringLiteral("png"), QStringLiteral("jpg"), QStringLiteral("jpeg"),
                                        QStringLiteral("webp"), QStringLiteral("gif"), QStringLiteral("bmp"),
                                        QStringLiteral("svg")};
    return fotos.contains(ext);
}
}

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
    , m_viewMode(QStringLiteral("grid"))
    , m_sortBy(QStringLiteral("name"))
    , m_sortAscending(true)
    , m_watcher(new QFileSystemWatcher(this))
{
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &FinderBackend::onDirectoryChanged);

    m_temporizadorBusqueda = new QTimer(this);
    m_temporizadorBusqueda->setSingleShot(true);
    m_temporizadorBusqueda->setInterval(350);
    connect(m_temporizadorBusqueda, &QTimer::timeout, this, &FinderBackend::buscarEnSubcarpetas);

    // Explorador de archivos: iconos grandes y panel de detalles por defecto;
    // lo que el usuario elige se recuerda.
    {
        QSettings ajustes(QStringLiteral("titan"), QStringLiteral("explorador"));
        const QString vista = ajustes.value(QStringLiteral("vista"), QStringLiteral("grid")).toString();
        m_viewMode = (vista == QLatin1String("list")) ? vista : QStringLiteral("grid");
        m_panelDetalles = ajustes.value(QStringLiteral("detalles"), true).toBool();
    }

    m_deviceTimer = new QTimer(this);
    m_deviceTimer->setInterval(2000);
    connect(m_deviceTimer, &QTimer::timeout, this, &FinderBackend::refreshDevices);
    m_deviceTimer->start();

    // Lo que copian otras apps también cuenta para "Pegar".
    connect(QGuiApplication::clipboard(), &QClipboard::dataChanged, this, &FinderBackend::clipboardChanged);

    refreshDevices();
    initFavorites();

    // Iniciar en el directorio personal del usuario
    goTo(QDir::homePath());
}

void FinderBackend::initFavorites()
{
    m_favorites.clear();

    auto addFav = [this](const QString &name, const QString &path, const QString &icon, const QString &section) {
        if (QDir(path).exists() || path == QStringLiteral("/") || path.startsWith(QStringLiteral("tag:")) || path == rutaRecientes()) {
            QVariantMap item;
            item[QStringLiteral("name")] = name;
            item[QStringLiteral("path")] = path;
            item[QStringLiteral("icon")] = icon;
            item[QStringLiteral("section")] = section;
            m_favorites.append(item);
        }
    };

    const QString home = QDir::homePath();

    // Acceso rápido (como el Explorador de Windows). Las carpetas del usuario
    // salen de xdg-user-dirs (Imágenes, Música, Vídeos...); no se crean
    // carpetas en inglés.
    const QString rapido = QStringLiteral("Acceso rápido");
    auto carpetaUsuario = [&home](QStandardPaths::StandardLocation donde, const QStringList &nombres) {
        const QString p = QStandardPaths::writableLocation(donde);
        if (!p.isEmpty() && p != home && QDir(p).exists())
            return p;
        for (const QString &n : nombres) {
            if (QDir(home + QLatin1Char('/') + n).exists())
                return home + QLatin1Char('/') + n;
        }
        return QString();
    };
    addFav(QStringLiteral("Carpeta personal"), home, QStringLiteral("qrc:/icons/folder.png"), rapido);
    addFav(QStringLiteral("Recientes"), rutaRecientes(), QStringLiteral("qrc:/icons/notes.png"), rapido);

    QString desktop = carpetaUsuario(QStandardPaths::DesktopLocation, {QStringLiteral("Escritorio")});
    if (desktop.isEmpty()) { desktop = home + QStringLiteral("/Escritorio"); QDir().mkpath(desktop); }
    addFav(QStringLiteral("Escritorio"), desktop, QStringLiteral("qrc:/icons/desktop.png"), rapido);

    QString downloads = carpetaUsuario(QStandardPaths::DownloadLocation, {QStringLiteral("Descargas")});
    if (downloads.isEmpty()) { downloads = home + QStringLiteral("/Descargas"); QDir().mkpath(downloads); }
    addFav(QStringLiteral("Descargas"), downloads, QStringLiteral("qrc:/icons/downloads.png"), rapido);

    QString documents = carpetaUsuario(QStandardPaths::DocumentsLocation, {QStringLiteral("Documentos")});
    if (documents.isEmpty()) { documents = home + QStringLiteral("/Documentos"); QDir().mkpath(documents); }
    addFav(QStringLiteral("Documentos"), documents, QStringLiteral("qrc:/icons/files.png"), rapido);

    const QString pictures = carpetaUsuario(QStandardPaths::PicturesLocation, {QStringLiteral("Imágenes"), QStringLiteral("Pictures")});
    if (!pictures.isEmpty())
        addFav(QStringLiteral("Imágenes"), pictures, QStringLiteral("qrc:/icons/pictures.png"), rapido);
    const QString music = carpetaUsuario(QStandardPaths::MusicLocation, {QStringLiteral("Música"), QStringLiteral("Musica"), QStringLiteral("Music")});
    if (!music.isEmpty())
        addFav(QStringLiteral("Música"), music, QStringLiteral("qrc:/icons/music-folder.png"), rapido);
    const QString videos = carpetaUsuario(QStandardPaths::MoviesLocation, {QStringLiteral("Vídeos"), QStringLiteral("Videos")});
    if (!videos.isEmpty())
        addFav(QStringLiteral("Vídeos"), videos, QStringLiteral("qrc:/icons/file-video.png"), rapido);
    if (QDir(home + QStringLiteral("/Proyectos")).exists())
        addFav(QStringLiteral("Proyectos"), home + QStringLiteral("/Proyectos"), QStringLiteral("qrc:/icons/developer.png"), rapido);

    // Las que ancla el usuario (clic derecho > Anclar a Acceso rápido)
    QStringList yaEstan;
    for (const QVariant &f : std::as_const(m_favorites))
        yaEstan << f.toMap().value(QStringLiteral("path")).toString();
    const QStringList ancladas = QSettings(QStringLiteral("titan"), QStringLiteral("explorador")).value(QStringLiteral("ancladas")).toStringList();
    for (const QString &a : ancladas) {
        if (yaEstan.contains(a) || !QFileInfo(a).isDir())
            continue;
        addFav(QFileInfo(a).fileName(), a, QStringLiteral("qrc:/icons/folder.png"), rapido);
        QVariantMap ultimo = m_favorites.takeLast().toMap();
        ultimo[QStringLiteral("anclada")] = true;
        m_favorites.append(ultimo);
    }

    // Este equipo
    addFav(QStringLiteral("Disco del sistema"), QStringLiteral("/"), QStringLiteral("qrc:/icons/system.png"), QStringLiteral("Este equipo"));

    QString trash = home + QStringLiteral("/.local/share/Trash/files");
    QDir().mkpath(trash);
    addFav(QStringLiteral("Papelera"), trash, QStringLiteral("qrc:/icons/trash.png"), QStringLiteral("Este equipo"));

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
    if (m_currentPath == QDir::homePath()) return QStringLiteral("Carpeta personal");
    if (m_currentPath == rutaRecientes()) return QStringLiteral("Recientes");
    if (m_currentPath == QStringLiteral("/")) return QStringLiteral("Sistema");

    QDir dir(m_currentPath);
    QString name = dir.dirName();
    if (name.isEmpty()) return m_currentPath;
    return name;
}

bool FinderBackend::canGoUp() const
{
    return m_currentPath != QStringLiteral("/") && !m_currentPath.isEmpty() && m_currentPath != rutaRecientes();
}

QVariantList FinderBackend::pathSegments() const
{
    QVariantList segments;
    if (m_currentPath.isEmpty()) return segments;
    if (m_currentPath == rutaRecientes())
        return {QVariantMap{{QStringLiteral("name"), QStringLiteral("Recientes")}, {QStringLiteral("path"), rutaRecientes()}}};

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
            displayName = QStringLiteral("Carpeta personal");
        }
        seg[QStringLiteral("name")] = displayName;
        seg[QStringLiteral("path")] = accumulated;
        segments.append(seg);
    }

    return segments;
}

void FinderBackend::goTo(const QString &path)
{
    QString canonical = path;
    if (path != rutaRecientes()) {
        canonical = QDir(path).canonicalPath();
        if (canonical.isEmpty()) canonical = path;
        if (!QDir(canonical).exists()) return;
    }

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
    m_extraBusqueda.clear();

    if (path == rutaRecientes()) {
        cargarRecientes();
        updateFreeSpace();
        filterAndSortEntries();
        emit currentPathChanged();
        return;
    }

    QDir dir(path);
    QDir::Filters filters = QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot;
    if (m_showHiddenFiles) {
        filters |= QDir::Hidden;
    }

    const QFileInfoList list = dir.entryInfoList(filters, QDir::DirsFirst | QDir::Name);

    for (const QFileInfo &info : list)
        m_rawEntries.append(entradaDe(info));

    updateFreeSpace();
    filterAndSortEntries();

    emit currentPathChanged();
}

void FinderBackend::filterAndSortEntries()
{
    m_filteredEntries.clear();

    const QString query = sinAcentos(m_searchQuery.trimmed());

    for (const QVariant &var : m_rawEntries) {
        const QVariantMap item = var.toMap();
        if (!query.isEmpty() && !sinAcentos(item.value(QStringLiteral("name")).toString()).contains(query))
            continue;
        m_filteredEntries.append(item);
    }
    if (enRecientes()) { // lo último abierto, primero
        std::sort(m_filteredEntries.begin(), m_filteredEntries.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap().value(QStringLiteral("reciente")).toLongLong() > b.toMap().value(QStringLiteral("reciente")).toLongLong();
        });
        emit entriesChanged();
        return;
    }
    const int locales = m_filteredEntries.size();

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

    // Lo encontrado dentro de las subcarpetas va después de lo de aquí
    Q_UNUSED(locales)
    if (!query.isEmpty())
        m_filteredEntries.append(m_extraBusqueda);

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
    if (ext == QStringLiteral("appimage")) return QStringLiteral("Aplicación (AppImage)");
    if (ext == QStringLiteral("png")) return QStringLiteral("Imagen PNG");
    if (ext == QStringLiteral("jpg") || ext == QStringLiteral("jpeg")) return QStringLiteral("Imagen JPEG");
    if (ext == QStringLiteral("svg")) return QStringLiteral("Gráfico vectorial SVG");
    if (ext == QStringLiteral("mp3")) return QStringLiteral("Audio MP3");
    if (ext == QStringLiteral("flac")) return QStringLiteral("Audio FLAC");
    if (ext == QStringLiteral("txt")) return QStringLiteral("Documento de texto");
    if (ext == QStringLiteral("md")) return QStringLiteral("Documento Markdown");
    if (ext == QStringLiteral("pdf")) return QStringLiteral("Documento PDF");
    if (ext == QStringLiteral("docx") || ext == QStringLiteral("doc") || ext == QStringLiteral("odt")) return QStringLiteral("Documento");
    if (ext == QStringLiteral("xlsx") || ext == QStringLiteral("xls") || ext == QStringLiteral("ods")) return QStringLiteral("Hoja de cálculo");
    if (ext == QStringLiteral("pptx") || ext == QStringLiteral("ppt") || ext == QStringLiteral("odp")) return QStringLiteral("Presentación");
    if (ext == QStringLiteral("zip") || ext == QStringLiteral("rar") || ext == QStringLiteral("7z") || ext == QStringLiteral("gz")) return QStringLiteral("Archivo comprimido");
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
        ++m_generacionBusqueda;          // lo que se estaba buscando ya no vale
        m_extraBusqueda.clear();
        if (m_buscando) { m_buscando = false; emit busquedaChanged(); }
        filterAndSortEntries();
        m_temporizadorBusqueda->start(); // y en un momento, en las subcarpetas
    }
}

void FinderBackend::setViewMode(const QString &mode)
{
    if (m_viewMode != mode && (mode == QLatin1String("grid") || mode == QLatin1String("list"))) {
        m_viewMode = mode;
        QSettings(QStringLiteral("titan"), QStringLiteral("explorador")).setValue(QStringLiteral("vista"), mode);
        emit viewModeChanged();
    }
}

void FinderBackend::setPanelDetalles(bool v)
{
    if (m_panelDetalles == v)
        return;
    m_panelDetalles = v;
    QSettings(QStringLiteral("titan"), QStringLiteral("explorador")).setValue(QStringLiteral("detalles"), v);
    emit panelDetallesChanged();
}


QVariantMap FinderBackend::detalles(const QString &path) const
{
    QVariantMap m;
    const QFileInfo fi(path.isEmpty() ? m_currentPath : path);
    if (!fi.exists())
        return m;
    const QLocale es(QLocale::Spanish);
    const QString ext = fi.suffix().toLower();
    m[QStringLiteral("nombre")] = fi.fileName().isEmpty() ? fi.absoluteFilePath() : fi.fileName();
    m[QStringLiteral("ruta")] = fi.absoluteFilePath();
    m[QStringLiteral("carpeta")] = QFileInfo(fi.absolutePath()).fileName();
    m[QStringLiteral("esCarpeta")] = fi.isDir();
    m[QStringLiteral("tipo")] = resolveType(fi);
    m[QStringLiteral("icono")] = resolveIcon(fi);
    if (fi.isDir()) {
        const int n = QDir(fi.absoluteFilePath()).entryList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot).size();
        m[QStringLiteral("tamano")] = n == 1 ? QStringLiteral("1 elemento") : QStringLiteral("%1 elementos").arg(n);
    } else {
        m[QStringLiteral("tamano")] = formatBytes(fi.size());
    }
    m[QStringLiteral("modificado")] = es.toString(fi.lastModified(), QStringLiteral("d MMM yyyy, HH:mm"));
    const QDateTime creado = fi.birthTime().isValid() ? fi.birthTime() : fi.metadataChangeTime();
    m[QStringLiteral("creado")] = es.toString(creado, QStringLiteral("d MMM yyyy, HH:mm"));
    const bool foto = !fi.isDir() && esFoto(ext);
    m[QStringLiteral("esFoto")] = foto;
    if (foto && ext != QLatin1String("svg")) {
        // Solo lee la cabecera: no carga la foto entera
        const QSize t = QImageReader(fi.absoluteFilePath()).size();
        if (t.isValid())
            m[QStringLiteral("dimensiones")] = QStringLiteral("%1 × %2").arg(t.width()).arg(t.height());
    }
    return m;
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

    // A Recientes (no los programas ni los lanzadores)
    if (info.suffix() != QLatin1String("desktop") && info.suffix().compare(QLatin1String("appimage"), Qt::CaseInsensitive) != 0)
        apuntarReciente(info.absoluteFilePath());

    // Si es un lanzador .desktop
    if (info.suffix() == QStringLiteral("desktop")) {
        // QSettings no sirve para .desktop: con una coma el valor sale vacío.
        QString exec = titan::leerDesktop(info.absoluteFilePath()).value(QStringLiteral("Exec"));
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

    // Instaladores de Ubuntu/Debian (.deb) y Fedora (.rpm): titan-paquete
    // ofrece la App Store o instalarlo solo en la cuenta.
    if (info.suffix().compare(QStringLiteral("deb"), Qt::CaseInsensitive) == 0
        || info.suffix().compare(QStringLiteral("rpm"), Qt::CaseInsensitive) == 0) {
        const QString paquete = resolveFinderBinary(QStringLiteral("titan-paquete"));
        if (QFile::exists(paquete)) {
            QProcess::startDetached(paquete, {info.absoluteFilePath()});
            return;
        }
    }

    // Programas de Windows (.exe/.msi): titan-exe los abre con Wine y, si no
    // está, ofrece instalarlo (con la ventana de contraseña de Inti).
    if (info.suffix().compare(QStringLiteral("exe"), Qt::CaseInsensitive) == 0
        || info.suffix().compare(QStringLiteral("msi"), Qt::CaseInsensitive) == 0) {
        const QString exe = resolveFinderBinary(QStringLiteral("titan-exe"));
        if (QFile::exists(exe)) {
            QProcess::startDetached(exe, {info.absoluteFilePath()});
            return;
        }
    }

    // AppImage: preguntar e instalar como en Windows (titan-appimage). Por
    // tipo no se puede: xdg-mime lo ve como un ejecutable cualquiera.
    if (info.suffix().compare(QStringLiteral("appimage"), Qt::CaseInsensitive) == 0) {
        const QString instalador = resolveFinderBinary(QStringLiteral("titan-appimage"));
        if (QFile::exists(instalador)) {
            QProcess::startDetached(instalador, {info.absoluteFilePath()});
            return;
        }
    }

    // Si es ejecutable de consola/script
    if (info.isExecutable() && (info.suffix() == QStringLiteral("sh") || info.suffix() == QStringLiteral("bin") || info.suffix().isEmpty())) {
        QProcess::startDetached(info.absoluteFilePath(), QStringList());
        return;
    }

    // Lo elegido en Ajustes > Aplicaciones predeterminadas va primero
    if (titan::abrirConElegida(info.absoluteFilePath()))
        return;

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
    if (!puedeEscribir()) {
        ponerAviso(enPapelera() ? QStringLiteral("En la Papelera no se crean carpetas")
                                : QStringLiteral("No tienes permiso para crear carpetas aquí"));
        return false;
    }
    QString base = name.trimmed().isEmpty() ? QStringLiteral("Nueva carpeta") : name.trimmed();
    QDir dir(m_currentPath);
    QString candidate = base;
    int index = 2;
    while (dir.exists(candidate)) {
        candidate = QStringLiteral("%1 %2").arg(base).arg(index++);
    }
    bool ok = dir.mkdir(candidate);
    if (ok) {
        apuntarDeshacer(QStringLiteral("crear"), {QVariantMap{{QStringLiteral("b"), dir.filePath(candidate)}}}, QStringLiteral("Deshacer: nueva carpeta"));
        refresh();
    }
    return ok;
}

bool FinderBackend::deleteItem(const QString &path)
{
    return deleteItems(QStringList{path});
}

bool FinderBackend::renameItem(const QString &oldPath, const QString &newName)
{
    if (newName.trimmed().isEmpty()) return false;
    QFileInfo info(oldPath);
    if (!info.exists()) return false;
    QString target = info.absolutePath() + QStringLiteral("/") + newName.trimmed();
    if (target == info.absoluteFilePath()) return true;
    if (QFileInfo::exists(target)) {
        ponerAviso(QStringLiteral("Ya hay algo llamado «%1» aquí").arg(newName.trimmed()));
        return false;
    }
    bool ok = QFile::rename(oldPath, target);
    if (ok) {
        apuntarDeshacer(QStringLiteral("renombrar"), {QVariantMap{{QStringLiteral("a"), info.absoluteFilePath()}, {QStringLiteral("b"), target}}},
                        QStringLiteral("Deshacer: renombrar"));
        refresh();
    }
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
    arrastrar(QStringList{path});
    return;
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
    copyItems(QStringList() << path);
}

void FinderBackend::copyItems(const QStringList &paths)
{
    if (paths.isEmpty()) return;
    m_clipboardPath = paths.first();
    QMimeData *mime = new QMimeData();
    QList<QUrl> urls;
    for (const QString &p : paths) {
        if (QFile::exists(p) || QDir(p).exists()) {
            urls.append(QUrl::fromLocalFile(p));
        }
    }
    mime->setUrls(urls);
    mime->setText(paths.join(QLatin1Char('\n')));
    QByteArray gnome("copy");
    for (const QUrl &u : std::as_const(urls))
        gnome += '\n' + u.toEncoded();
    mime->setData(QStringLiteral("x-special/gnome-copied-files"), gnome);
    QGuiApplication::clipboard()->setMimeData(mime);
    emit clipboardChanged();
    ponerAviso(urls.size() == 1 ? QStringLiteral("Copiado") : QStringLiteral("%1 elementos copiados").arg(urls.size()));
}

bool FinderBackend::deleteItems(const QStringList &paths)
{
    // A la Papelera de verdad (con su .trashinfo, para poder recuperar).
    // Si no se puede, NO se borra para siempre: se avisa.
    int n = 0, protegidas = 0;
    QString fallo;
    QVariantList deshacer;
    for (const QString &p0 : paths) {
        const QString p = p0.startsWith(QStringLiteral("file:")) ? QUrl(p0).toLocalFile() : p0;
        if (!QFileInfo::exists(p) && !QFileInfo(p).isSymLink())
            continue;
        if (esProtegida(p)) {
            ++protegidas;
            continue;
        }
        QString enLaPapelera;
        if (QFile::moveToTrash(p, &enLaPapelera)) {
            ++n;
            deshacer << QVariantMap{{QStringLiteral("a"), p}, {QStringLiteral("b"), enLaPapelera}};
        }
        else if (fallo.isEmpty())
            fallo = QFileInfo(p).fileName();
    }
    apuntarDeshacer(QStringLiteral("papelera"), deshacer, QStringLiteral("Deshacer: enviar a la Papelera"));
    refresh();
    if (!fallo.isEmpty())
        ponerAviso(QStringLiteral("«%1» no se pudo mover a la Papelera (¿sin permiso?)").arg(fallo));
    else if (protegidas > 0 && n == 0)
        ponerAviso(QStringLiteral("Las carpetas principales de tu carpeta personal no se tiran"));
    else if (n > 0)
        ponerAviso(n == 1 ? QStringLiteral("Movido a la Papelera") : QStringLiteral("%1 elementos movidos a la Papelera").arg(n));
    return fallo.isEmpty() && n > 0;
}

bool FinderBackend::moveItems(const QStringList &paths, const QString &targetDir)
{
    QVariantList urls;
    for (const QString &p : paths)
        urls << p;
    soltar(urls, targetDir.isEmpty() ? m_currentPath : targetDir, false);
    return true;
}

bool FinderBackend::paste(const QString &destinationDir)
{
    QString destDir = destinationDir.isEmpty() ? m_currentPath : destinationDir;
    if (!QFileInfo(destDir).isDir())
        destDir = m_currentPath;
    if (enPapelera() && destinationDir.isEmpty()) {
        ponerAviso(QStringLiteral("No se puede pegar en la Papelera"));
        return false;
    }
    const QMimeData *mime = QGuiApplication::clipboard()->mimeData();
    QVariantList urls;
    if (mime && mime->hasUrls()) {
        for (const QUrl &u : mime->urls())
            if (u.isLocalFile())
                urls << u.toLocalFile();
    } else if (!m_clipboardPath.isEmpty()) {
        urls << m_clipboardPath;
    }
    if (urls.isEmpty())
        return false;
    const bool cortado = portapapelesCortado();
    soltar(urls, destDir, !cortado);
    if (cortado) {
        // Lo cortado se pega una vez: luego el portapapeles queda vacío.
        QGuiApplication::clipboard()->clear();
        m_clipboardPath.clear();
        emit clipboardChanged();
    }
    return true;
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

// ---------------------------------------------------------------- menú contextual

namespace {
// Documentos vacíos de ONLYOFFICE (los usa él mismo para "Nuevo"): en el
// idioma del sistema si los hay, si no en inglés.
QString plantillaOffice(const QString &ext)
{
    const QString base = QStringLiteral("/opt/onlyoffice/desktopeditors/converter/empty/");
    const QString idioma = QLocale().name().replace(QLatin1Char('_'), QLatin1Char('-'));
    for (const QString &d : {idioma, QStringLiteral("es-ES"), QStringLiteral("en-US"), QStringLiteral("default")}) {
        const QString f = base + d + QStringLiteral("/new.") + ext;
        if (QFile::exists(f))
            return f;
    }
    return QString();
}

QStringList carpetasAplicaciones()
{
    QStringList d = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
    d << QStringLiteral("/var/lib/flatpak/exports/share/applications")
      << QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share/applications");
    d.removeDuplicates();
    return d;
}
}

QVariantList FinderBackend::tiposNuevos() const
{
    QVariantList l;
    auto poner = [&l](const QString &tipo, const QString &texto, const QString &icono) {
        l.append(QVariantMap{{QStringLiteral("tipo"), tipo}, {QStringLiteral("t"), texto}, {QStringLiteral("i"), icono}});
    };
    poner(QStringLiteral("txt"), QStringLiteral("Documento de texto"), QStringLiteral("📝"));
    if (!plantillaOffice(QStringLiteral("docx")).isEmpty())
        poner(QStringLiteral("docx"), QStringLiteral("Documento"), QStringLiteral("📄"));
    if (!plantillaOffice(QStringLiteral("xlsx")).isEmpty())
        poner(QStringLiteral("xlsx"), QStringLiteral("Hoja de cálculo"), QStringLiteral("📊"));
    if (!plantillaOffice(QStringLiteral("pptx")).isEmpty())
        poner(QStringLiteral("pptx"), QStringLiteral("Presentación"), QStringLiteral("📽"));
    return l;
}

QString FinderBackend::nuevoArchivo(const QString &tipo)
{
    if (!puedeEscribir()) {
        ponerAviso(QStringLiteral("No tienes permiso para crear archivos aquí"));
        return QString();
    }
    QString base, plantilla;
    if (tipo == QLatin1String("txt")) base = QStringLiteral("Documento de texto");
    else if (tipo == QLatin1String("docx")) base = QStringLiteral("Documento");
    else if (tipo == QLatin1String("xlsx")) base = QStringLiteral("Hoja de cálculo");
    else if (tipo == QLatin1String("pptx")) base = QStringLiteral("Presentación");
    else return QString();
    if (tipo != QLatin1String("txt")) {
        plantilla = plantillaOffice(tipo);
        if (plantilla.isEmpty())
            return QString();
    }
    QDir dir(m_currentPath);
    QString nombre = base + QLatin1Char('.') + tipo;
    for (int i = 2; dir.exists(nombre); ++i)
        nombre = QStringLiteral("%1 %2.%3").arg(base).arg(i).arg(tipo);
    const QString ruta = dir.filePath(nombre);
    bool ok;
    if (plantilla.isEmpty()) {
        QFile f(ruta);
        ok = f.open(QIODevice::WriteOnly | QIODevice::NewOnly);
    } else {
        ok = QFile::copy(plantilla, ruta);
        if (ok)
            QFile::setPermissions(ruta, QFile::ReadOwner | QFile::WriteOwner | QFile::ReadGroup | QFile::ReadOther);
    }
    if (!ok) {
        ponerAviso(QStringLiteral("No se pudo crear el archivo"));
        return QString();
    }
    apuntarDeshacer(QStringLiteral("crear"), {QVariantMap{{QStringLiteral("b"), ruta}}}, QStringLiteral("Deshacer: nuevo documento"));
    refresh();
    return ruta;
}

// Apps que dicen abrir ese tipo de archivo (MimeType= de su .desktop), la
// predeterminada primero. Como "Abrir con" de Windows.
QVariantList FinderBackend::aplicacionesPara(const QString &path) const
{
    const QMimeType mime = QMimeDatabase().mimeTypeForFile(path);
    QSet<QString> tipos{mime.name()};
    for (const QString &t : mime.allAncestors()) tipos.insert(t);
    for (const QString &t : mime.aliases()) tipos.insert(t);
    tipos.remove(QStringLiteral("application/octet-stream"));

    QProcess xdg;
    xdg.start(QStringLiteral("xdg-mime"), {QStringLiteral("query"), QStringLiteral("default"), mime.name()});
    const QString predeterminada = xdg.waitForFinished(1500) ? QString::fromUtf8(xdg.readAllStandardOutput()).trimmed() : QString();

    QVariantList lista;
    QSet<QString> vistos, nombres;
    const QString idioma = QLocale().name().left(2);
    for (const QString &carpeta : carpetasAplicaciones()) {
        const QFileInfoList ficheros = QDir(carpeta).entryInfoList({QStringLiteral("*.desktop")}, QDir::Files);
        for (const QFileInfo &fi : ficheros) {
            if (vistos.contains(fi.fileName()))
                continue;   // el de más prioridad (el de la persona) gana
            vistos.insert(fi.fileName());
            const auto d = titan::leerDesktop(fi.absoluteFilePath());
            if (titan::esVerdadero(d.value(QStringLiteral("NoDisplay"))) || titan::esVerdadero(d.value(QStringLiteral("Hidden")))
                || d.value(QStringLiteral("Type")) != QLatin1String("Application"))
                continue;
            bool sirve = false;
            for (const QString &m : d.value(QStringLiteral("MimeType")).split(QLatin1Char(';'), Qt::SkipEmptyParts))
                if (tipos.contains(m)) { sirve = true; break; }
            if (!sirve)
                continue;
            QString nombre = d.value(QStringLiteral("Name[") + idioma + QLatin1Char(']'));
            if (nombre.isEmpty()) nombre = d.value(QStringLiteral("Name"));
            if (nombres.contains(nombre))
                continue;   // dos .desktop con el mismo nombre: uno basta
            nombres.insert(nombre);
            QVariantMap app{{QStringLiteral("t"), nombre}, {QStringLiteral("desktop"), fi.absoluteFilePath()}};
            if (fi.fileName() == predeterminada) lista.prepend(app); else lista.append(app);
        }
    }
    // Las demás por nombre (la predeterminada se queda la primera)
    const bool hayPred = !lista.isEmpty() && lista.first().toMap().value(QStringLiteral("desktop")).toString().endsWith(QLatin1Char('/') + predeterminada);
    std::sort(lista.begin() + (hayPred ? 1 : 0), lista.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("t")).toString().localeAwareCompare(b.toMap().value(QStringLiteral("t")).toString()) < 0;
    });
    while (lista.size() > 10) lista.removeLast();
    return lista;
}

void FinderBackend::abrirCon(const QString &path, const QString &desktop)
{
    if (path.isEmpty() || !desktop.endsWith(QStringLiteral(".desktop")) || !QFile::exists(desktop))
        return;
    QProcess::startDetached(QStringLiteral("gio"), {QStringLiteral("launch"), desktop, path});
}

void FinderBackend::copiarRuta(const QStringList &paths)
{
    if (paths.isEmpty())
        return;
    QGuiApplication::clipboard()->setText(paths.join(QLatin1Char('\n')));
    ponerAviso(paths.size() == 1 ? QStringLiteral("Ruta copiada") : QStringLiteral("Rutas copiadas"));
}

QVariantMap FinderBackend::entradaDe(const QFileInfo &info) const
{
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
        entry[QStringLiteral("size")] = count == 1 ? QStringLiteral("1 elemento") : QStringLiteral("%1 elementos").arg(count);
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
    // Las fotos se ven en miniatura en la vista de iconos
    entry[QStringLiteral("foto")] = !info.isDir() && esFoto(info.suffix().toLower());

    return entry;
}
