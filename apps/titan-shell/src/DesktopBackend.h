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
    Q_INVOKABLE void moveItemToSlot(const QString &path, int col, int row);
    Q_INVOKABLE QVariantMap iconPosition(const QString &path);
    Q_INVOKABLE bool importFile(const QString &urlOrPath, qreal x = -1, qreal y = -1, bool isMove = false);
    Q_INVOKABLE void copyItems(const QStringList &paths);
    Q_INVOKABLE void deleteItems(const QStringList &paths);
    Q_INVOKABLE void pasteItems(qreal x = -1, qreal y = -1);
    Q_INVOKABLE bool hasClipboard() const;
    Q_INVOKABLE void moveItems(const QStringList &paths, const QString &targetDir);

signals:
    void itemsChanged();
    void positionsChanged();

private:
    static int anchoEscritorio();
    static int filasEscritorio();
    static QPair<int, int> casillaDe(const QVariantMap &pos);
    void loadItems();
    void ensureSampleDesktop();
    void syncStoreAppsToDesktop();
    void vigilarTienda();
    void loadPositions();
    void savePositions();
    QString resolveIcon(const QString &fileName, bool isDir) const;
    QString resolveAppIcon(const QString &iconName, const QString &exec) const;

    QVariantList m_items;
    QFileSystemWatcher *m_watcher;
    QString m_desktopPath;
    QVariantMap m_positions;
};
