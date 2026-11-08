#pragma once

#include <QObject>
#include <QUrl>
#include <QString>

class VideoBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl sourceUrl READ sourceUrl WRITE setSourceUrl NOTIFY sourceUrlChanged)
    Q_PROPERTY(QString fileName READ fileName NOTIFY sourceUrlChanged)

public:
    explicit VideoBackend(QObject *parent = nullptr);

    QUrl sourceUrl() const { return m_sourceUrl; }
    void setSourceUrl(const QUrl &url);

    QString fileName() const;

    Q_INVOKABLE void openFile(const QString &filePath);
    Q_INVOKABLE QString formatTime(qint64 milliseconds) const;

signals:
    void sourceUrlChanged();

private:
    QUrl m_sourceUrl;
};

