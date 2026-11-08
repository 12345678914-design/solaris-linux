#include "VideoBackend.h"
#include <QFileInfo>

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
    return QFileInfo(m_sourceUrl.toLocalFile()).fileName();
}

void VideoBackend::openFile(const QString &filePath) {
    if (!filePath.isEmpty()) {
        setSourceUrl(QUrl::fromLocalFile(filePath));
    }
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

