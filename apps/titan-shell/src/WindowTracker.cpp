#include "WindowTracker.h"
#include "tareas.h"
#include <QDebug>

WindowTracker::WindowTracker(QObject *parent)
    : QObject(parent)
    , m_monitor(new MonitorTareas(this))
{
    QString err;
    if (m_monitor->iniciar(&err)) {
        connect(m_monitor, &MonitorTareas::cambiado, this, &WindowTracker::onTareasCambiadas);
    } else {
        qWarning() << "WindowTracker: no se pudo iniciar MonitorTareas:" << err;
    }
}

WindowTracker::~WindowTracker() = default;

QVariantList WindowTracker::windows() const
{
    return m_windows;
}

QString WindowTracker::activeTitle() const
{
    return m_activeTitle.isEmpty() ? QStringLiteral("Titan Linux") : m_activeTitle;
}

QString WindowTracker::activeAppId() const
{
    return m_activeAppId.isEmpty() ? QStringLiteral("Titan") : m_activeAppId;
}

static bool matchesAppId(const QString &target, const QString &winAppId)
{
    QString t = target.toLower();
    QString w = winAppId.toLower();
    if (t.contains("firefox") || t.contains("browser") || t.contains("navigator") || t.contains("safari")) {
        if (w.contains("firefox") || w.contains("browser") || w.contains("navigator") || w.contains("safari")) {
            return true;
        }
    }
    return w.contains(t) || t.contains(w);
}

void WindowTracker::onTareasCambiadas()
{
    if (!m_monitor) return;
    
    m_windows.clear();
    QString newActiveTitle;
    QString newActiveAppId;
    
    bool hasFs = false;
    bool hasMax = false;
    for (const auto &v : m_monitor->ventanas()) {
        QVariantMap map;
        map[QStringLiteral("id")] = static_cast<qulonglong>(v.id);
        map[QStringLiteral("title")] = v.titulo;
        map[QStringLiteral("appId")] = v.appId;
        map[QStringLiteral("active")] = v.activa;
        map[QStringLiteral("minimized")] = v.minimizada;
        map[QStringLiteral("maximized")] = v.maximizada;
        map[QStringLiteral("fullscreen")] = v.pantallaCompleta;
        m_windows.append(map);
        
        if (v.pantallaCompleta && !v.minimizada) {
            hasFs = true;
        }
        if ((v.maximizada || v.pantallaCompleta) && !v.minimizada) {
            hasMax = true;
        }

        if (v.activa) {
            newActiveTitle = v.titulo;
            newActiveAppId = v.appId;
        }
    }
    
    emit windowsChanged();
    
    if (m_hasFullscreen != hasFs) {
        m_hasFullscreen = hasFs;
        emit fullscreenChanged();
    }
    if (m_hasMaximized != hasMax) {
        m_hasMaximized = hasMax;
        emit maximizedChanged();
    }
    
    if (m_activeTitle != newActiveTitle) {
        m_activeTitle = newActiveTitle;
        emit activeTitleChanged();
    }
    if (m_activeAppId != newActiveAppId) {
        m_activeAppId = newActiveAppId;
        emit activeAppIdChanged();
    }
}

void WindowTracker::activateWindow(const QString &appId)
{
    if (!m_monitor) return;
    for (const auto &v : m_monitor->ventanas()) {
        if (matchesAppId(appId, v.appId)) {
            if (v.activa) {
                m_monitor->minimizar(v.id, true);
            } else {
                m_monitor->activar(v.id);
            }
            return;
        }
    }
}

void WindowTracker::focusWindow(const QString &appId)
{
    if (!m_monitor) return;
    for (const auto &v : m_monitor->ventanas()) {
        if (matchesAppId(appId, v.appId)) {
            m_monitor->activar(v.id);
            return;
        }
    }
}

void WindowTracker::closeWindow(const QString &appId)
{
    if (!m_monitor) return;
    for (const auto &v : m_monitor->ventanas()) {
        if (matchesAppId(appId, v.appId)) {
            m_monitor->cerrar(v.id);
            return;
        }
    }
}
