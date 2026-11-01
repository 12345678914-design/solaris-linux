#ifndef LAUNCHERBACKEND_H
#define LAUNCHERBACKEND_H

#include <QObject>
#include <QString>
#include <QVariantList>

class QFileSystemWatcher;

class LauncherBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)
    
public:
    explicit LauncherBackend(QObject *parent = nullptr);
    ~LauncherBackend() override;
    
    QVariantList apps() const;
    
    Q_INVOKABLE void search(const QString &query);
    Q_INVOKABLE void launch(const QString &exec);
    Q_INVOKABLE void reload();
    
signals:
    void appsChanged();
    
private:
    void loadApps();
    
    QVariantList m_apps;
    QVariantList m_filteredApps;
    QFileSystemWatcher *m_watcher;
};

#endif
