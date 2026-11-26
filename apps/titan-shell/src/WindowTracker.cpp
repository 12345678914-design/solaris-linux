#include <algorithm>
#include "WindowTracker.h"
#include "WayfireIpc.h"
#include "tareas.h"
#include <QDebug>
#include <QGuiApplication>
#include <QWindow>
#include <qpa/qplatformnativeinterface.h>

static wl_display *displayDeQt()
{
    if (auto *wl = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>()) {
        return wl->display();
    }
    return nullptr;
}

static wl_surface *superficieDe(QWindow *ventana)
{
    if (!ventana || !ventana->handle()) {
        return nullptr;
    }
    auto *nativa = QGuiApplication::platformNativeInterface();
    if (!nativa) {
        return nullptr;
    }
    return static_cast<wl_surface *>(
        nativa->nativeResourceForWindow(QByteArrayLiteral("surface"), ventana));
}

WindowTracker::WindowTracker(QObject *parent)
    : QObject(parent)
    , m_monitor(new MonitorTareas(this))
{
    connect(WayfireIpc::instancia(), &WayfireIpc::acopladaCambiada, this, &WindowTracker::tiledChanged);
    QString err;
    // Con la conexion de Qt se puede pasar la superficie del Dock en
    // set_rectangle; sin Wayland (p. ej. pruebas) se abre una propia.
    if (m_monitor->iniciar(&err, displayDeQt())) {
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
    return m_activeTitle.isEmpty() ? QStringLiteral("Inti OS") : m_activeTitle;
}

QString WindowTracker::activeAppId() const
{
    return m_activeAppId.isEmpty() ? QStringLiteral("Inti OS") : m_activeAppId;
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

    // En Wayfire los escritorios son reales (vswitch): no se simulan
    // minimizando, que dispararia la animacion de minimizar en cada cambio.
    if (m_monitor && !nativeWorkspaces()) {
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
        if (m_monitor && nativeWorkspaces()) {
            for (const auto &v : m_monitor->ventanas()) {
                if (v.id == id) {
                    WayfireIpc::instancia()->enviarVentana(v.appId, v.titulo, workspaceIndex);
                    break;
                }
            }
        } else if (m_monitor) {
            if (workspaceIndex != m_currentWorkspace) {
                m_monitor->minimizar(id, true);
            } else {
                m_monitor->minimizar(id, false);
            }
        }
        // Rehace la lista para que el campo "workspace" (miniaturas) se actualice.
        onTareasCambiadas();
    }
}

bool WindowTracker::hasTiledWindow() const
{
    return WayfireIpc::instancia()->disponible() && WayfireIpc::instancia()->hayAcoplada();
}

void WindowTracker::moverActivaAEscritorio(int workspaceIndex)
{
    if (!m_monitor) return;
    for (const auto &v : m_monitor->ventanas()) {
        if (v.activa) {
            if (m_windowWorkspaces.value(v.id, m_currentWorkspace) != workspaceIndex)
                moveWindowToWorkspace(v.id, workspaceIndex);
            return;
        }
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
        if (!m_conDestino.contains(v.id) && !v.appId.isEmpty()) {
            aplicarDestino(v.id, v.appId);
        }

        int winWs = m_windowWorkspaces.value(v.id, 0);
        if (v.activa && m_recientes.value(0) != v.id) {
            m_recientes.removeAll(v.id);
            m_recientes.prepend(v.id);
        } else if (!m_recientes.contains(v.id)) {
            m_recientes.append(v.id);
        }

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
    m_conDestino.intersect(currentIds);
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

QVariantList WindowTracker::ventanasRecientes() const
{
    QVariantList r;
    if (!m_monitor) return r;
    const auto ventanas = m_monitor->ventanas();
    QHash<quintptr, int> pos;
    for (int i = 0; i < m_recientes.size(); ++i)
        pos.insert(m_recientes.at(i), i);
    QList<Ventana> lista;
    for (const auto &v : ventanas)
        if (m_windowWorkspaces.value(v.id, 0) == m_currentWorkspace)
            lista.append(v);
    std::stable_sort(lista.begin(), lista.end(), [&pos](const Ventana &a, const Ventana &b) {
        // La activa siempre primero; las minimizadas al final
        if (a.activa != b.activa) return a.activa;
        if (a.minimizada != b.minimizada) return !a.minimizada;
        return pos.value(a.id, 1 << 20) < pos.value(b.id, 1 << 20);
    });
    for (const auto &v : std::as_const(lista)) {
        QVariantMap m;
        m[QStringLiteral("id")] = static_cast<qulonglong>(v.id);
        m[QStringLiteral("title")] = v.titulo;
        m[QStringLiteral("appId")] = v.appId;
        m[QStringLiteral("minimized")] = v.minimizada;
        r.append(m);
    }
    return r;
}

void WindowTracker::traerVentana(qulonglong windowId)
{
    if (!m_monitor) return;
    const quintptr id = static_cast<quintptr>(windowId);
    for (const auto &v : m_monitor->ventanas())
        if (v.id == id && v.minimizada)
            m_monitor->minimizar(id, false);
    m_monitor->activar(id);
    m_ocultasEscritorio.removeAll(id);
}

void WindowTracker::mostrarEscritorio()
{
    if (!m_monitor) return;
    const auto ventanas = m_monitor->ventanas();
    QList<quintptr> visibles;
    for (const auto &v : ventanas)
        if (!v.minimizada && m_windowWorkspaces.value(v.id, 0) == m_currentWorkspace)
            visibles.append(v.id);

    if (!visibles.isEmpty()) {
        // Ocultar: tambien las abiertas despues de la ultima vez
        for (quintptr id : std::as_const(visibles)) {
            m_monitor->minimizar(id, true);
            if (!m_ocultasEscritorio.contains(id))
                m_ocultasEscritorio.append(id);
        }
        return;
    }
    // Ya estaba el escritorio a la vista: devolver las que se ocultaron aqui
    // (las que el usuario minimizo a mano se quedan donde estan).
    QSet<quintptr> existen;
    for (const auto &v : ventanas)
        if (v.minimizada)
            existen.insert(v.id);
    quintptr ultima = 0;
    for (quintptr id : std::as_const(m_ocultasEscritorio)) {
        if (!existen.contains(id)) continue;
        m_monitor->minimizar(id, false);
        ultima = id;
    }
    if (ultima)
        m_monitor->activar(ultima);
    m_ocultasEscritorio.clear();
}

bool WindowTracker::nativeWorkspaces() const
{
    return WayfireIpc::instancia()->disponible();
}

void WindowTracker::aplicarDestino(quintptr id, const QString &appId)
{
    if (!m_monitor) return;
    for (auto it = m_destinos.constBegin(); it != m_destinos.constEnd(); ++it) {
        if (!matchesAppId(it.key(), appId)) continue;
        wl_surface *sup = superficieDe(it->ventana);
        if (!sup) return;
        m_monitor->ponerRectangulo(id, sup, it->rect.x(), it->rect.y(),
                                   it->rect.width(), it->rect.height());
        m_conDestino.insert(id);
        return;
    }
}

void WindowTracker::setMinimizeTarget(const QString &appId, QObject *ventana,
                                      qreal x, qreal y, qreal ancho, qreal alto)
{
    auto *win = qobject_cast<QWindow *>(ventana);
    if (!win || appId.isEmpty()) return;
    const QRect r(qRound(x), qRound(y), qRound(ancho), qRound(alto));
    auto actual = m_destinos.constFind(appId);
    if (actual != m_destinos.constEnd() && actual->ventana == win && actual->rect == r) {
        return;
    }
    m_destinos.insert(appId, DestinoMinimizado{win, r});

    if (!m_monitor) return;
    wl_surface *sup = superficieDe(win);
    if (!sup) return;
    for (const auto &v : m_monitor->ventanas()) {
        if (matchesAppId(appId, v.appId)) {
            m_monitor->ponerRectangulo(v.id, sup, r.x(), r.y(), r.width(), r.height());
            m_conDestino.insert(v.id);
        }
    }
}
