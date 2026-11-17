#pragma once

#include <QObject>
#include <QUrl>
#include <QString>
#include <QStringList>

class VideoBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl sourceUrl READ sourceUrl WRITE setSourceUrl NOTIFY sourceUrlChanged)
    Q_PROPERTY(QString fileName READ fileName NOTIFY sourceUrlChanged)
    // Vídeos de la misma carpeta, en orden alfabético: anterior / siguiente.
    Q_PROPERTY(bool hasNext READ hasNext NOTIFY sourceUrlChanged)
    Q_PROPERTY(bool hasPrevious READ hasPrevious NOTIFY sourceUrlChanged)
    Q_PROPERTY(QString playlistPosition READ playlistPosition NOTIFY sourceUrlChanged)

public:
    explicit VideoBackend(QObject *parent = nullptr);

    QUrl sourceUrl() const { return m_sourceUrl; }
    void setSourceUrl(const QUrl &url);

    QString fileName() const;

    Q_INVOKABLE void openFile(const QString &filePath);
    Q_INVOKABLE QString formatTime(qint64 milliseconds) const;
    bool hasNext() const;
    bool hasPrevious() const;
    QString playlistPosition() const;   // "3 / 12", o "" si no hay carpeta
    // Cambian al vídeo siguiente/anterior de la carpeta; false si no hay.
    Q_INVOKABLE bool playNext();
    Q_INVOKABLE bool playPrevious();

signals:
    void sourceUrlChanged();

private:
    QStringList siblings() const;   // vídeos de la carpeta del actual
    int currentIndex(const QStringList &list) const;
    QUrl m_sourceUrl;
};

