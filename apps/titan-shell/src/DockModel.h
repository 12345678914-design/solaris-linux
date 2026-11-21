#ifndef DOCKMODEL_H
#define DOCKMODEL_H

#include <QObject>
#include <QAbstractListModel>
#include <QString>
#include <QList>
#include <QMap>
#include <QVariantMap>

class WindowTracker;
class ShellBackend;
class QTimer;

class DockModel : public QAbstractListModel
{
    Q_OBJECT
    
public:
    enum DockRoles {
        AppIdRole = Qt::UserRole + 1,
        NameRole,
        IconRole,
        ExecRole,
        RunningRole,
        HasWindowRole,
        ActiveRole,
        LaunchingRole,
        IsPinnedRole,
        ShowSeparatorRole,
        WindowsListRole
    };
    
    explicit DockModel(WindowTracker *tracker, ShellBackend *backend, QObject *parent = nullptr);
    
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;
    
    Q_INVOKABLE void activateApp(const QString &appId);
    Q_INVOKABLE void launchApp(const QString &appId, const QString &exec = QString(), const QString &name = QString(), const QString &icon = QString());
    // Hace rebotar el icono si la app está en el Dock; devuelve si estaba.
    // Las que no están no se añaden (las abre ColaApps con su indicador).
    Q_INVOKABLE bool setAppLaunching(const QString &appId, const QString &exec = QString(), const QString &name = QString(), const QString &icon = QString());
    Q_INVOKABLE void moveItem(int fromIndex, int toIndex);

    Q_INVOKABLE void pinApp(const QString &appId);
    Q_INVOKABLE void unpinApp(const QString &appId);
    Q_INVOKABLE bool isAppPinned(const QString &appId) const;
    Q_INVOKABLE void closeApp(const QString &appId);
    Q_INVOKABLE QVariantList getWindowsForApp(const QString &appId) const;
    Q_INVOKABLE void activateWindowById(qulonglong windowId);
    // Icono de una ventana (Alt+Tab): el del Dock si la app esta, si no el que
    // se resuelva por su app_id.
    Q_INVOKABLE QString iconoVentana(const QString &appId, const QString &titulo) const;
    Q_INVOKABLE QString nombreVentana(const QString &appId, const QString &titulo) const;
    
private slots:
    void updateWindowStates();
    
private:
    void loadPinnedApps();
    void savePinnedApps();
    void initDefaultPinnedApps();
    QString resolveDynamicIcon(const QString &appId, const QString &title) const;

    WindowTracker *m_tracker = nullptr;
    ShellBackend *m_backend = nullptr;
    QList<QVariantMap> m_pinnedApps;
    QList<QVariantMap> m_apps;
    QMap<QString, QTimer*> m_launchTimers;
    QMap<QString, QVariantMap> m_launchingAppInfo;
};

#endif
