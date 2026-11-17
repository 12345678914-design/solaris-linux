#ifndef WINDOWTRACKER_H
#define WINDOWTRACKER_H

#include <QObject>
#include <QString>
#include <QList>
#include <QVariantMap>
#include <QHash>
#include <QSet>
#include <QRect>
#include <QPointer>

class MonitorTareas;
class QWindow;

class WindowTracker : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList windows READ windows NOTIFY windowsChanged)
    Q_PROPERTY(QString activeTitle READ activeTitle NOTIFY activeTitleChanged)
    Q_PROPERTY(QString activeAppId READ activeAppId NOTIFY activeAppIdChanged)
    Q_PROPERTY(bool hasFullscreenWindow READ hasFullscreenWindow NOTIFY fullscreenChanged)
    Q_PROPERTY(bool hasMaximizedWindow READ hasMaximizedWindow NOTIFY maximizedChanged)
    Q_PROPERTY(int currentWorkspace READ currentWorkspace WRITE setCurrentWorkspace NOTIFY currentWorkspaceChanged)
    Q_PROPERTY(QVariantList currentWorkspaceWindows READ currentWorkspaceWindows NOTIFY currentWorkspaceWindowsChanged)
    
public:
    explicit WindowTracker(QObject *parent = nullptr);
    ~WindowTracker() override;
    
    QVariantList windows() const;
    QString activeTitle() const;
    QString activeAppId() const;
    bool hasFullscreenWindow() const { return m_hasFullscreen; }
    bool hasMaximizedWindow() const { return m_hasMaximized; }
    int currentWorkspace() const { return m_currentWorkspace; }
    void setCurrentWorkspace(int ws);
    QVariantList currentWorkspaceWindows() const;
    
    Q_INVOKABLE QVariantList windowsForWorkspace(int workspaceIndex) const;
    Q_INVOKABLE int windowWorkspace(qulonglong windowId) const;
    Q_INVOKABLE void moveWindowToWorkspace(qulonglong windowId, int workspaceIndex);
    Q_INVOKABLE void focusWindow(const QString &appId);
    Q_INVOKABLE void activateWindow(const QString &appId);
    Q_INVOKABLE void closeWindow(const QString &appId);
    Q_INVOKABLE QVariantList windowsForApp(const QString &appId) const;
    Q_INVOKABLE void activateWindowById(qulonglong windowId);
    Q_INVOKABLE void closeWindowById(qulonglong windowId);
    // Icono del Dock hacia el que se anima la ventana al minimizar
    // (wlr-foreign-toplevel set_rectangle). Coordenadas relativas a 'ventana'.
    Q_INVOKABLE void setMinimizeTarget(const QString &appId, QObject *ventana,
                                       qreal x, qreal y, qreal ancho, qreal alto);
    // true si el compositor es Wayfire con IPC: los escritorios son reales.
    Q_INVOKABLE bool nativeWorkspaces() const;
    
signals:
    void windowsChanged();
    void activeTitleChanged();
    void activeAppIdChanged();
    void fullscreenChanged();
    void maximizedChanged();
    void currentWorkspaceChanged();
    void currentWorkspaceWindowsChanged();
    void requestWorkspaceSwitch(int targetWorkspace);
    
private slots:
    void onTareasCambiadas();

private:
    MonitorTareas *m_monitor = nullptr;
    QVariantList m_windows;
    QString m_activeTitle;
    QString m_activeAppId;
    bool m_hasFullscreen = false;
    bool m_hasMaximized = false;
    int m_currentWorkspace = 0;
    QHash<quintptr, int> m_windowWorkspaces;

    struct DestinoMinimizado {
        QPointer<QWindow> ventana;
        QRect rect;
    };
    QHash<QString, DestinoMinimizado> m_destinos;
    QSet<quintptr> m_conDestino;
    void aplicarDestino(quintptr id, const QString &appId);
};

#endif
