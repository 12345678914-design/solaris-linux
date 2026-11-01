#ifndef DOCKMODEL_H
#define DOCKMODEL_H

#include <QObject>
#include <QAbstractListModel>
#include <QString>
#include <QList>
#include <QVariantMap>

class WindowTracker;
class ShellBackend;

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
        ActiveRole
    };
    
    explicit DockModel(WindowTracker *tracker, ShellBackend *backend, QObject *parent = nullptr);
    
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;
    
    Q_INVOKABLE void activateApp(const QString &appId);
    Q_INVOKABLE void moveItem(int fromIndex, int toIndex);
    
private slots:
    void updateWindowStates();
    
private:
    WindowTracker *m_tracker = nullptr;
    ShellBackend *m_backend = nullptr;
    QList<QVariantMap> m_pinnedApps;
    QList<QVariantMap> m_apps;
};

#endif
