#include "VideoBackend.h"
#include <QFileInfo>
#include <QDir>
#include <QCollator>

VideoBackend::VideoBackend(QObject *parent)
    : QObject(parent)
{
}

void VideoBackend::setSourceUrl(const QUrl &url) {
    if (m_sourceUrl != url) {
        m_sourceUrl = url;
        emit sourceUrlChanged();
    }
}

QString VideoBackend::fileName() const {
    if (m_sourceUrl.isEmpty()) {
        return "Reproductor de Video";
    }
    // Las URLs de red no tienen fichero local: se usa el último tramo de la URL
    return m_sourceUrl.isLocalFile() ? QFileInfo(m_sourceUrl.toLocalFile()).fileName()
                                     : m_sourceUrl.fileName();
}

void VideoBackend::openFile(const QString &filePath) {
    if (filePath.isEmpty()) return;
    // Desde QML puede llegar una URL (file:///...) en vez de una ruta
    const QUrl u(filePath);
    setSourceUrl(u.isLocalFile() ? u : QUrl::fromLocalFile(filePath));
}

QStringList VideoBackend::siblings() const {
    if (!m_sourceUrl.isLocalFile()) return {};
    const QFileInfo fi(m_sourceUrl.toLocalFile());
    static const QStringList filtros = {
        QStringLiteral("*.mp4"), QStringLiteral("*.mkv"), QStringLiteral("*.webm"), QStringLiteral("*.avi"),
        QStringLiteral("*.mov"), QStringLiteral("*.flv"), QStringLiteral("*.wmv"), QStringLiteral("*.m4v"),
        QStringLiteral("*.mpg"), QStringLiteral("*.mpeg"), QStringLiteral("*.ogv")
    };
    QDir dir = fi.dir();
    dir.setNameFilters(filtros);
    QStringList nombres = dir.entryList(QDir::Files | QDir::Readable | QDir::CaseSensitive);
    // Orden "natural": capitulo2 antes que capitulo10
    QCollator col;
    col.setNumericMode(true);
    col.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(nombres.begin(), nombres.end(), col);
    QStringList rutas;
    for (const QString &n : std::as_const(nombres))
        rutas << dir.absoluteFilePath(n);
    return rutas;
}

int VideoBackend::currentIndex(const QStringList &list) const {
    if (!m_sourceUrl.isLocalFile()) return -1;
    return list.indexOf(QFileInfo(m_sourceUrl.toLocalFile()).absoluteFilePath());
}

bool VideoBackend::hasNext() const {
    const QStringList l = siblings();
    const int i = currentIndex(l);
    return i >= 0 && i + 1 < l.size();
}

bool VideoBackend::hasPrevious() const {
    const QStringList l = siblings();
    return currentIndex(l) > 0;
}

QString VideoBackend::playlistPosition() const {
    const QStringList l = siblings();
    const int i = currentIndex(l);
    if (i < 0 || l.size() < 2) return QString();
    return QStringLiteral("%1 / %2").arg(i + 1).arg(l.size());
}

bool VideoBackend::playNext() {
    const QStringList l = siblings();
    const int i = currentIndex(l);
    if (i < 0 || i + 1 >= l.size()) return false;
    setSourceUrl(QUrl::fromLocalFile(l.at(i + 1)));
    return true;
}

bool VideoBackend::playPrevious() {
    const QStringList l = siblings();
    const int i = currentIndex(l);
    if (i <= 0) return false;
    setSourceUrl(QUrl::fromLocalFile(l.at(i - 1)));
    return true;
}

QString VideoBackend::formatTime(qint64 milliseconds) const {
    if (milliseconds < 0) milliseconds = 0;
    qint64 totalSeconds = milliseconds / 1000;
    qint64 hours = totalSeconds / 3600;
    qint64 minutes = (totalSeconds % 3600) / 60;
    qint64 seconds = totalSeconds % 60;

    if (hours > 0) {
        return QString("%1:%2:%3")
            .arg(hours, 2, 10, QChar('0'))
            .arg(minutes, 2, 10, QChar('0'))
            .arg(seconds, 2, 10, QChar('0'));
    }
    return QString("%1:%2")
        .arg(minutes, 2, 10, QChar('0'))
        .arg(seconds, 2, 10, QChar('0'));
}

