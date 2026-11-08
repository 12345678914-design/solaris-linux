#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QFileInfo>
#include <QDir>
#include <QFile>
#include <QFileSystemWatcher>
#include <QTimer>

class FinderBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY currentPathChanged)
    Q_PROPERTY(QString currentPathName READ currentPathName NOTIFY currentPathChanged)
    Q_PROPERTY(bool canGoBack READ canGoBack NOTIFY historyChanged)
    Q_PROPERTY(bool canGoForward READ canGoForward NOTIFY historyChanged)
    Q_PROPERTY(bool canGoUp READ canGoUp NOTIFY currentPathChanged)
    Q_PROPERTY(QVariantList pathSegments READ pathSegments NOTIFY currentPathChanged)
    Q_PROPERTY(QVariantList entries READ entries NOTIFY entriesChanged)
    Q_PROPERTY(QVariantList favorites READ favorites NOTIFY favoritesChanged)
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    Q_PROPERTY(bool showHiddenFiles READ showHiddenFiles WRITE setShowHiddenFiles NOTIFY showHiddenFilesChanged)
    Q_PROPERTY(QString searchQuery READ searchQuery WRITE setSearchQuery NOTIFY searchQueryChanged)
    Q_PROPERTY(QString viewMode READ viewMode WRITE setViewMode NOTIFY viewModeChanged)
    Q_PROPERTY(QString sortBy READ sortBy WRITE setSortBy NOTIFY sortChanged)
    Q_PROPERTY(bool sortAscending READ sortAscending WRITE setSortAscending NOTIFY sortChanged)
    Q_PROPERTY(QString totalItemsText READ totalItemsText NOTIFY entriesChanged)
    Q_PROPERTY(QString freeSpaceText READ freeSpaceText NOTIFY freeSpaceTextChanged)
    Q_PROPERTY(bool hasClipboard READ hasClipboard NOTIFY clipboardChanged)
    Q_PROPERTY(QString clipboardPath READ clipboardPath NOTIFY clipboardChanged)

public:
    explicit FinderBackend(QObject *parent = nullptr);
    ~FinderBackend() override = default;

    QString currentPath() const { return m_currentPath; }
    QString currentPathName() const;
    bool canGoBack() const { return m_historyIndex > 0; }
    bool canGoForward() const { return m_historyIndex + 1 < m_history.size(); }
    bool canGoUp() const;
    QVariantList pathSegments() const;
    QVariantList entries() const { return m_filteredEntries; }
    QVariantList favorites() const { return m_favorites; }
    QVariantList devices() const { return m_devices; }

    bool showHiddenFiles() const { return m_showHiddenFiles; }
    void setShowHiddenFiles(bool show);

    QString searchQuery() const { return m_searchQuery; }
    void setSearchQuery(const QString &query);

    QString viewMode() const { return m_viewMode; }
    void setViewMode(const QString &mode);

    QString sortBy() const { return m_sortBy; }
    void setSortBy(const QString &by);

    bool sortAscending() const { return m_sortAscending; }
    void setSortAscending(bool asc);

    QString totalItemsText() const;
    QString freeSpaceText() const { return m_freeSpaceText; }
    bool hasClipboard() const { return !m_clipboardPath.isEmpty() && (QFile::exists(m_clipboardPath) || QDir(m_clipboardPath).exists()); }
    QString clipboardPath() const { return m_clipboardPath; }

    Q_INVOKABLE void goTo(const QString &path);
    Q_INVOKABLE void goBack();
    Q_INVOKABLE void goForward();
    Q_INVOKABLE void goUp();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void openItem(const QString &path);
    Q_INVOKABLE void openTerminal(const QString &path = QString());
    Q_INVOKABLE bool createFolder(const QString &name = QString());
    Q_INVOKABLE bool deleteItem(const QString &path);
    Q_INVOKABLE bool renameItem(const QString &oldPath, const QString &newName);
    Q_INVOKABLE bool sendToDesktop(const QString &path);
    Q_INVOKABLE void startDrag(const QString &path);
    Q_INVOKABLE bool importFile(const QString &urlOrPath, const QString &targetDir = QString());
    Q_INVOKABLE void copyItem(const QString &path);
    Q_INVOKABLE bool paste(const QString &destinationDir = QString());
    Q_INVOKABLE QVariantMap getFileProperties(const QString &path);
    Q_INVOKABLE void sort(const QString &criteria);
    Q_INVOKABLE void refreshDevices();
    Q_INVOKABLE bool mountDevice(const QString &deviceNode);
    Q_INVOKABLE bool unmountDevice(const QString &deviceNode);
    Q_INVOKABLE bool mountAndOpen(const QString &deviceNode);

signals:
    void currentPathChanged();
    void historyChanged();
    void entriesChanged();
    void favoritesChanged();
    void devicesChanged();
    void showHiddenFilesChanged();
    void searchQueryChanged();
    void viewModeChanged();
    void sortChanged();
    void freeSpaceTextChanged();
    void clipboardChanged();

private slots:
    void onDirectoryChanged(const QString &path);

private:
    void loadDirectory(const QString &path);
    void filterAndSortEntries();
    void initFavorites();
    void updateFreeSpace();
    QString resolveIcon(const QFileInfo &info) const;
    QString resolveType(const QFileInfo &info) const;
    QString formatBytes(qint64 bytes) const;

    QString m_currentPath;
    QStringList m_history;
    int m_historyIndex;
    bool m_showHiddenFiles;
    QString m_searchQuery;
    QString m_viewMode; // "grid" or "list"
    QString m_sortBy;   // "name", "date", "size", "kind"
    bool m_sortAscending;
    QString m_freeSpaceText;

    QVariantList m_rawEntries;
    QVariantList m_filteredEntries;
    QVariantList m_favorites;
    QVariantList m_devices;
    QFileSystemWatcher *m_watcher;
    QTimer *m_deviceTimer;
    QString m_clipboardPath;
};

