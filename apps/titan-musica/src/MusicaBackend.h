#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QFileSystemWatcher>

class MusicaBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList tracks READ tracks NOTIFY tracksChanged)
    Q_PROPERTY(QVariantList categories READ categories CONSTANT)
    Q_PROPERTY(QString currentCategory READ currentCategory WRITE selectCategory NOTIFY categoryChanged)
    Q_PROPERTY(int currentTrackIndex READ currentTrackIndex NOTIFY currentTrackChanged)
    Q_PROPERTY(QVariantMap currentTrack READ currentTrack NOTIFY currentTrackChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY playbackStateChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(QString positionText READ positionText NOTIFY positionChanged)
    Q_PROPERTY(QString durationText READ durationText NOTIFY durationChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool isMuted READ isMuted NOTIFY volumeChanged)
    Q_PROPERTY(bool isShuffle READ isShuffle NOTIFY shuffleChanged)
    Q_PROPERTY(bool isRepeat READ isRepeat NOTIFY repeatChanged)
    Q_PROPERTY(QString searchQuery READ searchQuery WRITE setSearchQuery NOTIFY searchQueryChanged)
    Q_PROPERTY(int count READ count NOTIFY tracksChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY tracksChanged)

public:
    explicit MusicaBackend(QObject *parent = nullptr);
    ~MusicaBackend() override = default;

    QVariantList tracks() const { return m_filteredTracks; }
    QVariantList categories() const { return m_categories; }
    QString currentCategory() const { return m_currentCategory; }
    int currentTrackIndex() const { return m_currentTrackIndex; }
    QVariantMap currentTrack() const;
    bool isPlaying() const;
    qint64 position() const { return m_position; }
    qint64 duration() const { return m_duration; }
    QString positionText() const { return formatTime(m_position); }
    QString durationText() const { return formatTime(m_duration); }
    qreal volume() const;
    bool isMuted() const;
    bool isShuffle() const { return m_isShuffle; }
    bool isRepeat() const { return m_isRepeat; }
    QString searchQuery() const { return m_searchQuery; }
    int count() const { return m_filteredTracks.size(); }
    QString statusText() const;

    void setSearchQuery(const QString &query);

public slots:
    Q_INVOKABLE void playTrack(int index);
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void togglePlay();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void nextTrack();
    Q_INVOKABLE void previousTrack();
    Q_INVOKABLE void seek(qint64 positionMs);
    Q_INVOKABLE void setVolume(qreal vol);
    Q_INVOKABLE void toggleMute();
    Q_INVOKABLE void toggleShuffle();
    Q_INVOKABLE void toggleRepeat();
    Q_INVOKABLE void selectCategory(const QString &cat);
    Q_INVOKABLE void openInFinder(const QString &filePath = QString());
    Q_INVOKABLE void refresh();

signals:
    void tracksChanged();
    void categoryChanged();
    void currentTrackChanged();
    void playbackStateChanged();
    void positionChanged();
    void durationChanged();
    void volumeChanged();
    void shuffleChanged();
    void repeatChanged();
    void searchQueryChanged();

private slots:
    void onPlayerPositionChanged(qint64 pos);
    void onPlayerDurationChanged(qint64 dur);
    void onPlaybackStateChanged(QMediaPlayer::PlaybackState state);
    void onMediaStatusChanged(QMediaPlayer::MediaStatus status);

private:
    void initCategories();
    void scanDirectories();
    void filterTracks();
    QString formatTime(qint64 ms) const;
    QString formatBytes(qint64 bytes) const;

    QMediaPlayer *m_player;
    QAudioOutput *m_audioOutput;
    QFileSystemWatcher *m_watcher;

    QVariantList m_allTracks;
    QVariantList m_filteredTracks;
    QVariantList m_categories;
    QString m_currentCategory;
    int m_currentTrackIndex;
    qint64 m_position;
    qint64 m_duration;
    bool m_isShuffle;
    bool m_isRepeat;
    QString m_searchQuery;
};

