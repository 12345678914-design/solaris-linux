#include "FotosBackend.h"
#include "ThemeManager.h"

#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QImageReader>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>
#include <QDateTime>
#include <QFile>

FotosBackend::FotosBackend(QObject *parent)
    : QObject(parent)
    , m_currentCategory(QStringLiteral("todas"))
    , m_currentIndex(-1)
    , m_zoomFactor(1.0)
    , m_rotationAngle(0)
    , m_watcher(new QFileSystemWatcher(this))
{
    initCategories();
    scanDirectories();

    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &FotosBackend::refresh);
}

void FotosBackend::initCategories()
{
    m_categories.clear();

    QVariantMap catTodas;
    catTodas[QStringLiteral("id")] = QStringLiteral("todas");
    catTodas[QStringLiteral("name")] = QStringLiteral("Fototeca");
    catTodas[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/pictures.png");
    m_categories.append(catTodas);

    QVariantMap catFondos;
    catFondos[QStringLiteral("id")] = QStringLiteral("fondos");
    catFondos[QStringLiteral("name")] = QStringLiteral("Fondos de Pantalla");
    catFondos[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/desktop.png");
    m_categories.append(catFondos);

    QVariantMap catDescargas;
    catDescargas[QStringLiteral("id")] = QStringLiteral("descargas");
    catDescargas[QStringLiteral("name")] = QStringLiteral("Descargas");
    catDescargas[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/downloads.png");
    m_categories.append(catDescargas);
}

void FotosBackend::scanDirectories()
{
    m_allPhotos.clear();

    QStringList searchDirs;
    const QString picturesDir = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    if (!picturesDir.isEmpty() && QDir(picturesDir).exists()) {
        searchDirs << picturesDir;
    }
    const QString homePictures = QDir::homePath() + QStringLiteral("/Imágenes");
    if (QDir(homePictures).exists() && !searchDirs.contains(homePictures)) {
        searchDirs << homePictures;
    }

    // Fondos de pantalla del sistema
    const QString sysWallpapers = QStringLiteral("/usr/share/backgrounds");
    if (QDir(sysWallpapers).exists()) {
        searchDirs << sysWallpapers;
    }
    const QString titanWallpapers = QStringLiteral("/usr/share/titan/wallpapers");
    if (QDir(titanWallpapers).exists()) {
        searchDirs << titanWallpapers;
    }

    // Descargas
    const QString downloadsDir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (!downloadsDir.isEmpty() && QDir(downloadsDir).exists()) {
        searchDirs << downloadsDir;
    }

    const QStringList nameFilters = {
        QStringLiteral("*.png"), QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"),
        QStringLiteral("*.webp"), QStringLiteral("*.bmp"), QStringLiteral("*.svg"),
        QStringLiteral("*.gif")
    };

    QStringList addedPaths;

    for (const QString &dirPath : searchDirs) {
        if (!m_watcher->directories().contains(dirPath)) {
            m_watcher->addPath(dirPath);
        }

        QDirIterator it(dirPath, nameFilters, QDir::Files | QDir::Readable, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            it.next();
            const QFileInfo fi = it.fileInfo();
            const QString absPath = fi.canonicalFilePath();
            if (absPath.isEmpty() || addedPaths.contains(absPath)) {
                continue;
            }
            addedPaths << absPath;

            QVariantMap item;
            item[QStringLiteral("name")] = fi.fileName();
            item[QStringLiteral("path")] = absPath;
            item[QStringLiteral("url")] = QUrl::fromLocalFile(absPath).toString();
            item[QStringLiteral("size")] = formatBytes(fi.size());
            item[QStringLiteral("date")] = fi.lastModified().toString(QStringLiteral("dd/MM/yyyy hh:mm"));

            // Categorización
            if (absPath.contains(QStringLiteral("backgrounds")) || absPath.contains(QStringLiteral("wallpaper"))) {
                item[QStringLiteral("category")] = QStringLiteral("fondos");
            } else if (absPath.contains(QStringLiteral("Descargas")) || absPath.contains(QStringLiteral("Downloads"))) {
                item[QStringLiteral("category")] = QStringLiteral("descargas");
            } else {
                item[QStringLiteral("category")] = QStringLiteral("todas");
            }

            // Dimensiones rápidas con QImageReader
            QImageReader reader(absPath);
            const QSize sz = reader.size();
            if (sz.isValid()) {
                item[QStringLiteral("dimensions")] = QStringLiteral("%1 × %2").arg(sz.width()).arg(sz.height());
            } else {
                item[QStringLiteral("dimensions")] = QStringLiteral("");
            }

            m_allPhotos.append(item);
        }
    }

    filterPhotos();
}

void FotosBackend::filterPhotos()
{
    m_filteredPhotos.clear();

    for (const QVariant &var : m_allPhotos) {
        const QVariantMap item = var.toMap();
        const QString cat = item.value(QStringLiteral("category")).toString();
        const QString name = item.value(QStringLiteral("name")).toString();

        if (m_currentCategory != QStringLiteral("todas") && cat != m_currentCategory) {
            continue;
        }

        if (!m_searchQuery.isEmpty() && !name.contains(m_searchQuery, Qt::CaseInsensitive)) {
            continue;
        }

        m_filteredPhotos.append(item);
    }

    if (m_currentIndex >= m_filteredPhotos.size()) {
        m_currentIndex = m_filteredPhotos.isEmpty() ? -1 : 0;
        emit currentPhotoChanged();
    }

    emit photosChanged();
}

QVariantMap FotosBackend::currentPhoto() const
{
    if (m_currentIndex >= 0 && m_currentIndex < m_filteredPhotos.size()) {
        return m_filteredPhotos.at(m_currentIndex).toMap();
    }
    return QVariantMap();
}

QString FotosBackend::statusText() const
{
    const int total = m_filteredPhotos.size();
    if (total == 0) return QStringLiteral("Sin fotos");
    if (total == 1) return QStringLiteral("1 foto");
    return QStringLiteral("%1 fotos").arg(total);
}

void FotosBackend::setSearchQuery(const QString &query)
{
    if (m_searchQuery != query) {
        m_searchQuery = query;
        emit searchQueryChanged();
        filterPhotos();
    }
}

void FotosBackend::setZoomFactor(qreal factor)
{
    qreal clamped = qBound(0.2, factor, 5.0);
    if (!qFuzzyCompare(m_zoomFactor, clamped)) {
        m_zoomFactor = clamped;
        emit zoomFactorChanged();
    }
}

void FotosBackend::selectCategory(const QString &category)
{
    if (m_currentCategory != category) {
        m_currentCategory = category;
        emit categoryChanged();
        filterPhotos();
    }
}

void FotosBackend::selectPhoto(int index)
{
    if (index >= 0 && index < m_filteredPhotos.size()) {
        m_currentIndex = index;
    } else {
        m_currentIndex = -1;
    }
    m_zoomFactor = 1.0;
    m_rotationAngle = 0;
    emit currentPhotoChanged();
    emit zoomFactorChanged();
    emit rotationAngleChanged();
}

void FotosBackend::nextPhoto()
{
    if (m_filteredPhotos.isEmpty()) return;
    int next = (m_currentIndex + 1) % m_filteredPhotos.size();
    selectPhoto(next);
}

void FotosBackend::previousPhoto()
{
    if (m_filteredPhotos.isEmpty()) return;
    int prev = (m_currentIndex - 1 + m_filteredPhotos.size()) % m_filteredPhotos.size();
    selectPhoto(prev);
}

void FotosBackend::rotateClockwise()
{
    m_rotationAngle = (m_rotationAngle + 90) % 360;
    emit rotationAngleChanged();
}

void FotosBackend::rotateCounterClockwise()
{
    m_rotationAngle = (m_rotationAngle + 270) % 360;
    emit rotationAngleChanged();
}

void FotosBackend::zoomIn()
{
    setZoomFactor(m_zoomFactor * 1.25);
}

void FotosBackend::zoomOut()
{
    setZoomFactor(m_zoomFactor / 1.25);
}

void FotosBackend::resetZoom()
{
    setZoomFactor(1.0);
    m_rotationAngle = 0;
    emit rotationAngleChanged();
}

bool FotosBackend::setAsWallpaper(const QString &filePath)
{
    QString target = filePath.isEmpty() ? currentPhoto().value(QStringLiteral("path")).toString() : filePath;
    if (target.isEmpty() || !QFile::exists(target)) {
        // Si no hay foto seleccionada, abrir el selector de fondo de pantalla (Ctrl+W del sistema)
        QProcess::startDetached(QStringLiteral("titan-shell"), {QStringLiteral("--toggle-wallpaper")});
        return true;
    }

    ThemeManager::instance()->setWallpaper(target);
    QProcess::startDetached(QStringLiteral("titan-desktop"), {QStringLiteral("--wallpaper"), target});
    return true;
}

void FotosBackend::openInFinder(const QString &filePath)
{
    QString target = filePath.isEmpty() ? currentPhoto().value(QStringLiteral("path")).toString() : filePath;
    if (target.isEmpty()) return;
    QFileInfo fi(target);
    QString dir = fi.isDir() ? fi.absoluteFilePath() : fi.absolutePath();
    QProcess::startDetached(QStringLiteral("titan-finder"), {dir});
}

void FotosBackend::refresh()
{
    scanDirectories();
}

QString FotosBackend::formatBytes(qint64 bytes) const
{
    if (bytes <= 0) return QStringLiteral("0 B");
    const double kb = 1024.0;
    const double mb = kb * 1024.0;
    const double gb = mb * 1024.0;
    if (bytes >= gb) return QStringLiteral("%1 GB").arg(bytes / gb, 0, 'f', 1);
    if (bytes >= mb) return QStringLiteral("%1 MB").arg(bytes / mb, 0, 'f', 1);
    return QStringLiteral("%1 KB").arg(bytes / kb, 0, 'f', 0);
}

