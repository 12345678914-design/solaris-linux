#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QFileSystemWatcher>

class DesktopBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    Q_PROPERTY(QVariantMap positions READ positions NOTIFY positionsChanged)

public:
    explicit DesktopBackend(QObject *parent = nullptr);
    ~DesktopBackend() override = default;

    QVariantList items() const { return m_items; }
    QVariantMap positions() const { return m_positions; }

public slots:
    Q_INVOKABLE void openItem(const QString &path);
    Q_INVOKABLE void openInFinder();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void removeItem(const QString &path);
    Q_INVOKABLE void moveItem(const QString &path, qreal x, qreal y);
    Q_INVOKABLE QVariantMap iconPosition(const QString &path);
    Q_INVOKABLE bool importFile(const QString &urlOrPath, qreal x = -1, qreal y = -1, bool isMove = false);

signals:
    void itemsChanged();
    void positionsChanged();

private:
    void loadItems();
    void ensureSampleDesktop();
    void loadPositions();
    void savePositions();
    QString resolveIcon(const QString &fileName, bool isDir) const;
    QString resolveAppIcon(const QString &iconName, const QString &exec) const;

    QVariantList m_items;
    QFileSystemWatcher *m_watcher;
    QString m_desktopPath;
    QVariantMap m_positions;
};
