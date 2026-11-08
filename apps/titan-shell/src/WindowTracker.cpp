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
    return m_activeTitle.isEmpty() ? QStringLiteral("Solaris Linux") : m_activeTitle;
}

QString WindowTracker::activeAppId() const
{
    return m_activeAppId.isEmpty() ? QStringLiteral("Solaris") : m_activeAppId;
}

static QString cleanWinId(const QString &raw)
{
    if (raw.isEmpty()) return QString();
    QString s = raw.trimmed();
    if (s.contains(QLatin1Char('/'))) {
        int idx = s.lastIndexOf(QLatin1Char('/'));
        s = s.mid(idx + 1);
    }
    int spaceIdx = s.indexOf(QLatin1Char(' '));
    if (spaceIdx > 0) {
        s = s.left(spaceIdx);
    }
    if (s.endsWith(QStringLiteral(".desktop"), Qt::CaseInsensitive)) {
        s.chop(8);
    }
    return s.trimmed().toLower();
}

static bool matchesAppId(const QString &target, const QString &winAppId)
{
    QString t = cleanWinId(target);
    QString w = cleanWinId(winAppId);

    // ONLYOFFICE
    bool tIsOnlyOffice = t.contains(QStringLiteral("onlyoffice")) || t.contains(QStringLiteral("desktopeditors"));
    bool wIsOnlyOffice = w.contains(QStringLiteral("onlyoffice")) || w.contains(QStringLiteral("desktopeditors"));
    if (tIsOnlyOffice && wIsOnlyOffice) return true;

    // Firefox / Browser
    bool tIsBrowser = t.contains(QStringLiteral("firefox")) || t.contains(QStringLiteral("browser")) || t.contains(QStringLiteral("navigator")) || t.contains(QStringLiteral("safari"));
    bool wIsBrowser = w.contains(QStringLiteral("firefox")) || w.contains(QStringLiteral("browser")) || w.contains(QStringLiteral("navigator")) || w.contains(QStringLiteral("safari"));
    if (tIsBrowser && wIsBrowser) return true;

    // Terminal
    bool tIsTerm = t.contains(QStringLiteral("terminal")) || t.contains(QStringLiteral("kitty"));
    bool wIsTerm = w.contains(QStringLiteral("terminal")) || w.contains(QStringLiteral("kitty")) || w.contains(QStringLiteral("foot")) || w.contains(QStringLiteral("alacritty"));
    if (tIsTerm && wIsTerm) return true;

    // Finder
    bool tIsFinder = t.contains(QStringLiteral("finder")) || t.contains(QStringLiteral("files")) || t.contains(QStringLiteral("pcmanfm"));
    bool wIsFinder = w.contains(QStringLiteral("finder")) || w.contains(QStringLiteral("files")) || w.contains(QStringLiteral("pcmanfm")) || w.contains(QStringLiteral("dolphin"));
    if (tIsFinder && wIsFinder) return true;

    return w == t || w.contains(t) || t.contains(w);
}

void WindowTracker::setCurrentWorkspace(int ws)
{
    if (m_currentWorkspace == ws) return;
    int oldWs = m_currentWorkspace;
    m_currentWorkspace = ws;
    emit currentWorkspaceChanged();

    if (m_monitor) {
        for (const auto &v : m_monitor->ventanas()) {
            int winWs = m_windowWorkspaces.value(v.id, 0);
            if (winWs == oldWs && oldWs != ws) {
                m_monitor->minimizar(v.id, true);
            } else if (winWs == ws) {
                m_monitor->minimizar(v.id, false);
            }
        }
    }
    emit currentWorkspaceWindowsChanged();
}

QVariantList WindowTracker::currentWorkspaceWindows() const
{
    return windowsForWorkspace(m_currentWorkspace);
}

QVariantList WindowTracker::windowsForWorkspace(int workspaceIndex) const
{
    QVariantList list;
    if (!m_monitor) return list;
    for (const auto &v : m_monitor->ventanas()) {
        if (m_windowWorkspaces.value(v.id, 0) == workspaceIndex) {
            QVariantMap map;
            map[QStringLiteral("id")] = static_cast<qulonglong>(v.id);
            map[QStringLiteral("title")] = v.titulo;
            map[QStringLiteral("appId")] = v.appId;
            map[QStringLiteral("active")] = v.activa;
            map[QStringLiteral("minimized")] = v.minimizada;
            map[QStringLiteral("maximized")] = v.maximizada;
            map[QStringLiteral("fullscreen")] = v.pantallaCompleta;
            map[QStringLiteral("workspace")] = workspaceIndex;
            list.append(map);
        }
    }
    return list;
}

int WindowTracker::windowWorkspace(qulonglong windowId) const
{
    return m_windowWorkspaces.value(static_cast<quintptr>(windowId), 0);
}

void WindowTracker::moveWindowToWorkspace(qulonglong windowId, int workspaceIndex)
{
    quintptr id = static_cast<quintptr>(windowId);
    if (m_windowWorkspaces.contains(id)) {
        m_windowWorkspaces[id] = workspaceIndex;
        if (m_monitor) {
            if (workspaceIndex != m_currentWorkspace) {
                m_monitor->minimizar(id, true);
            } else {
                m_monitor->minimizar(id, false);
            }
        }
        emit currentWorkspaceWindowsChanged();
    }
}

void WindowTracker::onTareasCambiadas()
{
    if (!m_monitor) return;
    
    m_windows.clear();
    QString newActiveTitle;
    QString newActiveAppId;
    
    QSet<quintptr> currentIds;
    bool hasFs = false;
    bool hasMax = false;
    for (const auto &v : m_monitor->ventanas()) {
        currentIds.insert(v.id);
        if (!m_windowWorkspaces.contains(v.id)) {
            // Asigna la nueva ventana al espacio de trabajo activo actual
            m_windowWorkspaces.insert(v.id, m_currentWorkspace);
        }

        int winWs = m_windowWorkspaces.value(v.id, 0);

        QVariantMap map;
        map[QStringLiteral("id")] = static_cast<qulonglong>(v.id);
        map[QStringLiteral("title")] = v.titulo;
        map[QStringLiteral("appId")] = v.appId;
        map[QStringLiteral("active")] = v.activa;
        map[QStringLiteral("minimized")] = v.minimizada;
        map[QStringLiteral("maximized")] = v.maximizada;
        map[QStringLiteral("fullscreen")] = v.pantallaCompleta;
        map[QStringLiteral("workspace")] = winWs;
        m_windows.append(map);
        
        if (winWs == m_currentWorkspace) {
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
    }

    // Limpia ventanas cerradas
    auto it = m_windowWorkspaces.begin();
    while (it != m_windowWorkspaces.end()) {
        if (!currentIds.contains(it.key())) {
            it = m_windowWorkspaces.erase(it);
        } else {
            ++it;
        }
    }
    
    emit windowsChanged();
    emit currentWorkspaceWindowsChanged();
    
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
            int targetWs = m_windowWorkspaces.value(v.id, 0);
            if (targetWs != m_currentWorkspace) {
                emit requestWorkspaceSwitch(targetWs);
            }
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
        if (matchesAppId(appId, v.appId) || matchesAppId(appId, v.titulo)) {
            m_monitor->cerrar(v.id);
        }
    }
}

QVariantList WindowTracker::windowsForApp(const QString &appId) const
{
    QVariantList list;
    if (!m_monitor) return list;
    for (const auto &v : m_monitor->ventanas()) {
        if (matchesAppId(appId, v.appId) || matchesAppId(appId, v.titulo)) {
            QVariantMap map;
            map[QStringLiteral("id")] = static_cast<qulonglong>(v.id);
            map[QStringLiteral("title")] = v.titulo.isEmpty() ? v.appId : v.titulo;
            map[QStringLiteral("appId")] = v.appId;
            map[QStringLiteral("active")] = v.activa;
            map[QStringLiteral("minimized")] = v.minimizada;
            list.append(map);
        }
    }
    return list;
}

void WindowTracker::activateWindowById(qulonglong windowId)
{
    if (!m_monitor) return;
    quintptr id = static_cast<quintptr>(windowId);
    m_monitor->activar(id);
}

void WindowTracker::closeWindowById(qulonglong windowId)
{
    if (!m_monitor) return;
    quintptr id = static_cast<quintptr>(windowId);
    m_monitor->cerrar(id);
}
