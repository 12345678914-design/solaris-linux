#ifndef WINDOWTRACKER_H
#define WINDOWTRACKER_H

#include <QObject>
#include <QString>
#include <QList>
#include <QVariantMap>

class MonitorTareas;

class WindowTracker : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList windows READ windows NOTIFY windowsChanged)
    Q_PROPERTY(QString activeTitle READ activeTitle NOTIFY activeTitleChanged)
    Q_PROPERTY(QString activeAppId READ activeAppId NOTIFY activeAppIdChanged)
    Q_PROPERTY(bool hasFullscreenWindow READ hasFullscreenWindow NOTIFY fullscreenChanged)
    Q_PROPERTY(bool hasMaximizedWindow READ hasMaximizedWindow NOTIFY maximizedChanged)
    
public:
    explicit WindowTracker(QObject *parent = nullptr);
    ~WindowTracker() override;
    
    QVariantList windows() const;
    QString activeTitle() const;
    QString activeAppId() const;
    bool hasFullscreenWindow() const { return m_hasFullscreen; }
    bool hasMaximizedWindow() const { return m_hasMaximized; }
    
    Q_INVOKABLE void focusWindow(const QString &appId);
    Q_INVOKABLE void activateWindow(const QString &appId);
    Q_INVOKABLE void closeWindow(const QString &appId);
    
signals:
    void windowsChanged();
    void activeTitleChanged();
    void activeAppIdChanged();
    void fullscreenChanged();
    void maximizedChanged();
    
private slots:
    void onTareasCambiadas();

private:
    MonitorTareas *m_monitor = nullptr;
    QVariantList m_windows;
    QString m_activeTitle;
    QString m_activeAppId;
    bool m_hasFullscreen = false;
    bool m_hasMaximized = false;
};

#endif
