#include "MusicaBackend.h"

#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QProcess>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <QUrl>

MusicaBackend::MusicaBackend(QObject *parent)
    : QObject(parent)
    , m_player(new QMediaPlayer(this))
    , m_audioOutput(new QAudioOutput(this))
    , m_watcher(new QFileSystemWatcher(this))
    , m_currentCategory(QStringLiteral("todas"))
    , m_currentTrackIndex(-1)
    , m_position(0)
    , m_duration(0)
    , m_isShuffle(false)
    , m_isRepeat(false)
{
    m_player->setAudioOutput(m_audioOutput);
    m_audioOutput->setVolume(0.8);

    connect(m_player, &QMediaPlayer::positionChanged, this, &MusicaBackend::onPlayerPositionChanged);
    connect(m_player, &QMediaPlayer::durationChanged, this, &MusicaBackend::onPlayerDurationChanged);
    connect(m_player, &QMediaPlayer::playbackStateChanged, this, &MusicaBackend::onPlaybackStateChanged);
    connect(m_player, &QMediaPlayer::mediaStatusChanged, this, &MusicaBackend::onMediaStatusChanged);

    initCategories();
    scanDirectories();

    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &MusicaBackend::refresh);
}

void MusicaBackend::initCategories()
{
    m_categories.clear();

    QVariantMap catTodas;
    catTodas[QStringLiteral("id")] = QStringLiteral("todas");
    catTodas[QStringLiteral("name")] = QStringLiteral("Canciones");
    catTodas[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/music.png");
    m_categories.append(catTodas);

    QVariantMap catArtistas;
    catArtistas[QStringLiteral("id")] = QStringLiteral("artistas");
    catArtistas[QStringLiteral("name")] = QStringLiteral("Artistas");
    catArtistas[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/folder.png");
    m_categories.append(catArtistas);

    QVariantMap catAlbumes;
    catAlbumes[QStringLiteral("id")] = QStringLiteral("albumes");
    catAlbumes[QStringLiteral("name")] = QStringLiteral("Álbumes");
    catAlbumes[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/folder.png");
    m_categories.append(catAlbumes);
}

void MusicaBackend::scanDirectories()
{
    m_allTracks.clear();

    QStringList searchDirs;
    const QString musicDir = QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
    if (!musicDir.isEmpty() && QDir(musicDir).exists()) {
        searchDirs << musicDir;
    }
    const QString homeMusic = QDir::homePath() + QStringLiteral("/Música");
    if (QDir(homeMusic).exists() && !searchDirs.contains(homeMusic)) {
        searchDirs << homeMusic;
    }
    const QString downloadsDir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (!downloadsDir.isEmpty() && QDir(downloadsDir).exists()) {
        searchDirs << downloadsDir;
    }
    const QString systemSounds = QStringLiteral("/usr/share/sounds");
    if (QDir(systemSounds).exists()) {
        searchDirs << systemSounds;
    }

    const QStringList nameFilters = {
        QStringLiteral("*.mp3"), QStringLiteral("*.wav"), QStringLiteral("*.ogg"),
        QStringLiteral("*.flac"), QStringLiteral("*.m4a"), QStringLiteral("*.aac"),
        QStringLiteral("*.opus")
    };

    QStringList addedPaths;
    int trackId = 1;

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

            QVariantMap track;
            track[QStringLiteral("id")] = trackId++;
            
            // Nombre de la pista y metadatos limpios
            QString baseName = fi.completeBaseName();
            QString artist = QStringLiteral("Artista desconocido");
            QString album = fi.dir().dirName();
            QString title = baseName;

            if (baseName.contains(QStringLiteral(" - "))) {
                const QStringList parts = baseName.split(QStringLiteral(" - "));
                if (parts.size() >= 2) {
                    artist = parts.at(0).trimmed();
                    title = parts.at(1).trimmed();
                }
            }

            track[QStringLiteral("title")] = title;
            track[QStringLiteral("artist")] = artist;
            track[QStringLiteral("album")] = album;
            track[QStringLiteral("path")] = absPath;
            track[QStringLiteral("url")] = QUrl::fromLocalFile(absPath).toString();
            track[QStringLiteral("format")] = fi.suffix().toUpper();
            track[QStringLiteral("size")] = formatBytes(fi.size());

            m_allTracks.append(track);
        }
    }

    filterTracks();
}

void MusicaBackend::filterTracks()
{
    m_filteredTracks.clear();

    for (const QVariant &var : m_allTracks) {
        const QVariantMap track = var.toMap();
        const QString title = track.value(QStringLiteral("title")).toString();
        const QString artist = track.value(QStringLiteral("artist")).toString();
        const QString album = track.value(QStringLiteral("album")).toString();

        if (!m_searchQuery.isEmpty()) {
            bool matches = title.contains(m_searchQuery, Qt::CaseInsensitive)
                        || artist.contains(m_searchQuery, Qt::CaseInsensitive)
                        || album.contains(m_searchQuery, Qt::CaseInsensitive);
            if (!matches) {
                continue;
            }
        }

        m_filteredTracks.append(track);
    }

    emit tracksChanged();
}

QVariantMap MusicaBackend::currentTrack() const
{
    if (m_currentTrackIndex >= 0 && m_currentTrackIndex < m_filteredTracks.size()) {
        return m_filteredTracks.at(m_currentTrackIndex).toMap();
    }
    return QVariantMap();
}

bool MusicaBackend::isPlaying() const
{
    return m_player->playbackState() == QMediaPlayer::PlayingState;
}

qreal MusicaBackend::volume() const
{
    return m_audioOutput->volume();
}

bool MusicaBackend::isMuted() const
{
    return m_audioOutput->isMuted();
}

QString MusicaBackend::statusText() const
{
    const int total = m_filteredTracks.size();
    if (total == 0) return QStringLiteral("Sin canciones");
    if (total == 1) return QStringLiteral("1 canción");
    return QStringLiteral("%1 canciones").arg(total);
}

void MusicaBackend::setSearchQuery(const QString &query)
{
    if (m_searchQuery != query) {
        m_searchQuery = query;
        emit searchQueryChanged();
        filterTracks();
    }
}

void MusicaBackend::playTrack(int index)
{
    if (index < 0 || index >= m_filteredTracks.size()) return;

    m_currentTrackIndex = index;
    const QVariantMap tr = m_filteredTracks.at(index).toMap();
    const QString filePath = tr.value(QStringLiteral("path")).toString();

    m_player->setSource(QUrl::fromLocalFile(filePath));
    m_player->play();

    emit currentTrackChanged();
    emit playbackStateChanged();
}

void MusicaBackend::play()
{
    if (m_currentTrackIndex < 0 && !m_filteredTracks.isEmpty()) {
        playTrack(0);
    } else {
        m_player->play();
        emit playbackStateChanged();
    }
}

void MusicaBackend::pause()
{
    m_player->pause();
    emit playbackStateChanged();
}

void MusicaBackend::togglePlay()
{
    if (isPlaying()) {
        pause();
    } else {
        play();
    }
}

void MusicaBackend::stop()
{
    m_player->stop();
    m_position = 0;
    emit positionChanged();
    emit playbackStateChanged();
}

void MusicaBackend::nextTrack()
{
    if (m_filteredTracks.isEmpty()) return;

    int next = 0;
    if (m_isShuffle) {
        next = QRandomGenerator::global()->bounded(m_filteredTracks.size());
    } else {
        next = (m_currentTrackIndex + 1) % m_filteredTracks.size();
    }

    playTrack(next);
}

void MusicaBackend::previousTrack()
{
    if (m_filteredTracks.isEmpty()) return;

    if (m_position > 3000) {
        // Si lleva más de 3 segundos, reiniciar la pista actual
        seek(0);
        return;
    }

    int prev = (m_currentTrackIndex - 1 + m_filteredTracks.size()) % m_filteredTracks.size();
    playTrack(prev);
}

void MusicaBackend::seek(qint64 positionMs)
{
    m_player->setPosition(positionMs);
}

void MusicaBackend::setVolume(qreal vol)
{
    qreal clamped = qBound(0.0, vol, 1.0);
    m_audioOutput->setVolume(clamped);
    if (m_audioOutput->isMuted() && clamped > 0.0) {
        m_audioOutput->setMuted(false);
    }
    emit volumeChanged();
}

void MusicaBackend::toggleMute()
{
    m_audioOutput->setMuted(!m_audioOutput->isMuted());
    emit volumeChanged();
}

void MusicaBackend::toggleShuffle()
{
    m_isShuffle = !m_isShuffle;
    emit shuffleChanged();
}

void MusicaBackend::toggleRepeat()
{
    m_isRepeat = !m_isRepeat;
    emit repeatChanged();
}

void MusicaBackend::selectCategory(const QString &cat)
{
    if (m_currentCategory != cat) {
        m_currentCategory = cat;
        emit categoryChanged();
        filterTracks();
    }
}

void MusicaBackend::openInFinder(const QString &filePath)
{
    QString target = filePath.isEmpty() ? currentTrack().value(QStringLiteral("path")).toString() : filePath;
    if (target.isEmpty()) return;
    QFileInfo fi(target);
    QString dir = fi.isDir() ? fi.absoluteFilePath() : fi.absolutePath();
    QProcess::startDetached(QStringLiteral("titan-finder"), {dir});
}

void MusicaBackend::refresh()
{
    scanDirectories();
}

void MusicaBackend::onPlayerPositionChanged(qint64 pos)
{
    m_position = pos;
    emit positionChanged();
}

void MusicaBackend::onPlayerDurationChanged(qint64 dur)
{
    m_duration = dur;
    emit durationChanged();
}

void MusicaBackend::onPlaybackStateChanged(QMediaPlayer::PlaybackState state)
{
    Q_UNUSED(state);
    emit playbackStateChanged();
}

void MusicaBackend::onMediaStatusChanged(QMediaPlayer::MediaStatus status)
{
    if (status == QMediaPlayer::EndOfMedia) {
        if (m_isRepeat) {
            seek(0);
            m_player->play();
        } else {
            nextTrack();
        }
    }
}

QString MusicaBackend::formatTime(qint64 ms) const
{
    if (ms <= 0) return QStringLiteral("0:00");
    qint64 totalSeconds = ms / 1000;
    qint64 minutes = totalSeconds / 60;
    qint64 seconds = totalSeconds % 60;
    return QStringLiteral("%1:%2").arg(minutes).arg(seconds, 2, 10, QLatin1Char('0'));
}

QString MusicaBackend::formatBytes(qint64 bytes) const
{
    if (bytes <= 0) return QStringLiteral("0 B");
    const double kb = 1024.0;
    const double mb = kb * 1024.0;
    if (bytes >= mb) return QStringLiteral("%1 MB").arg(bytes / mb, 0, 'f', 1);
    return QStringLiteral("%1 KB").arg(bytes / kb, 0, 'f', 0);
}

