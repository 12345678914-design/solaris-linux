#include "tareas.h"

#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

#include <QDebug>
#include <QSocketNotifier>

#include <algorithm>
#include <cstring>
#include <wayland-client.h>

struct Toplevel;

struct MonitorTareas::Privado
{
    MonitorTareas *q = nullptr;
    wl_display *display = nullptr;
    wl_registry *registry = nullptr;
    wl_seat *seat = nullptr;
    zwlr_foreign_toplevel_manager_v1 *manager = nullptr;
    quint32 managerVersion = 0;
    QSocketNotifier *notificador = nullptr;
    QHash<quintptr, Toplevel *> manejadores;
    QHash<quintptr, Ventana> ventanas;
    QVector<quintptr> orden;
};

struct Toplevel
{
    MonitorTareas::Privado *d = nullptr;
    zwlr_foreign_toplevel_handle_v1 *handle = nullptr;
    quintptr id = 0;
};

namespace {

void cbTitulo(void *datos, zwlr_foreign_toplevel_handle_v1 *,
              const char *titulo)
{
    auto *t = static_cast<Toplevel *>(datos);
    auto it = t->d->ventanas.find(t->id);
    if (it == t->d->ventanas.end()) {
        return;
    }
    it->titulo = QString::fromUtf8(titulo ? titulo : "");
    Q_EMIT t->d->q->cambiado();
}

void cbAppId(void *datos, zwlr_foreign_toplevel_handle_v1 *,
             const char *appId)
{
    auto *t = static_cast<Toplevel *>(datos);
    auto it = t->d->ventanas.find(t->id);
    if (it == t->d->ventanas.end()) {
        return;
    }
    it->appId = QString::fromUtf8(appId ? appId : "");
    Q_EMIT t->d->q->cambiado();
}

void cbOutputEnter(void *, zwlr_foreign_toplevel_handle_v1 *, wl_output *)
{
}

void cbOutputLeave(void *, zwlr_foreign_toplevel_handle_v1 *, wl_output *)
{
}

void cbEstado(void *datos, zwlr_foreign_toplevel_handle_v1 *,
              wl_array *estado)
{
    auto *t = static_cast<Toplevel *>(datos);
    auto it = t->d->ventanas.find(t->id);
    if (it == t->d->ventanas.end()) {
        return;
    }
    it->maximizada = false;
    it->minimizada = false;
    it->activa = false;
    it->pantallaCompleta = false;
    const auto *valores = static_cast<const quint32 *>(estado->data);
    const int cuantos = int(estado->size / sizeof(quint32));
    for (int i = 0; i < cuantos; ++i) {
        switch (valores[i]) {
        case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MAXIMIZED:
            it->maximizada = true;
            break;
        case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MINIMIZED:
            it->minimizada = true;
            break;
        case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED:
            it->activa = true;
            break;
        case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_FULLSCREEN:
            it->pantallaCompleta = true;
            break;
        default:
            break;
        }
    }
    Q_EMIT t->d->q->cambiado();
}

void cbHecho(void *datos, zwlr_foreign_toplevel_handle_v1 *)
{
    auto *t = static_cast<Toplevel *>(datos);
    Q_EMIT t->d->q->cambiado();
}

void cbPadre(void *, zwlr_foreign_toplevel_handle_v1 *,
             zwlr_foreign_toplevel_handle_v1 *)
{
}

void cbCerrado(void *datos, zwlr_foreign_toplevel_handle_v1 *handle)
{
    auto *t = static_cast<Toplevel *>(datos);
    MonitorTareas::Privado *d = t->d;
    d->manejadores.remove(t->id);
    d->ventanas.remove(t->id);
    d->orden.removeAll(t->id);
    zwlr_foreign_toplevel_handle_v1_destroy(handle);
    delete t;
    Q_EMIT d->q->cambiado();
}

const zwlr_foreign_toplevel_handle_v1_listener kListenerToplevel = {
    cbTitulo,
    cbAppId,
    cbOutputEnter,
    cbOutputLeave,
    cbEstado,
    cbHecho,
    cbCerrado,
    cbPadre,
};

void cbNuevoToplevel(void *datos, zwlr_foreign_toplevel_manager_v1 *,
                     zwlr_foreign_toplevel_handle_v1 *handle)
{
    auto *d = static_cast<MonitorTareas::Privado *>(datos);
    auto *t = new Toplevel;
    t->d = d;
    t->handle = handle;
    t->id = reinterpret_cast<quintptr>(handle);
    Ventana v;
    v.id = t->id;
    d->manejadores.insert(t->id, t);
    d->ventanas.insert(t->id, v);
    d->orden.append(t->id);
    zwlr_foreign_toplevel_handle_v1_add_listener(handle,
                                                 &kListenerToplevel, t);
    Q_EMIT d->q->cambiado();
}

void cbManagerFin(void *datos, zwlr_foreign_toplevel_manager_v1 *)
{
    auto *d = static_cast<MonitorTareas::Privado *>(datos);
    d->manager = nullptr;
    d->managerVersion = 0;
    Q_EMIT d->q->cambiado();
}

const zwlr_foreign_toplevel_manager_v1_listener kListenerManager = {
    cbNuevoToplevel,
    cbManagerFin,
};

void cbGlobal(void *datos, wl_registry *registry, quint32 nombre,
              const char *interfaz, quint32 version)
{
    auto *d = static_cast<MonitorTareas::Privado *>(datos);
    if (std::strcmp(interfaz,
                    zwlr_foreign_toplevel_manager_v1_interface.name) == 0) {
        d->managerVersion = std::min<quint32>(version, 3);
        d->manager = static_cast<zwlr_foreign_toplevel_manager_v1 *>(
            wl_registry_bind(registry, nombre,
                             &zwlr_foreign_toplevel_manager_v1_interface,
                             d->managerVersion));
        zwlr_foreign_toplevel_manager_v1_add_listener(
            d->manager, &kListenerManager, d);
    } else if (std::strcmp(interfaz, wl_seat_interface.name) == 0 &&
               !d->seat) {
        d->seat = static_cast<wl_seat *>(
            wl_registry_bind(registry, nombre, &wl_seat_interface, 1));
    }
}

void cbGlobalQuitado(void *, wl_registry *, quint32)
{
}

const wl_registry_listener kListenerRegistry = {
    cbGlobal,
    cbGlobalQuitado,
};

} // namespace

MonitorTareas::MonitorTareas(QObject *padre)
    : QObject(padre)
    , d(new Privado)
{
    d->q = this;
}

MonitorTareas::~MonitorTareas()
{
    if (!d) {
        return;
    }
    delete d->notificador;
    d->notificador = nullptr;

    const auto manejadores = d->manejadores;
    for (Toplevel *t : manejadores) {
        zwlr_foreign_toplevel_handle_v1_destroy(t->handle);
        delete t;
    }
    d->manejadores.clear();
    if (d->manager) {
        zwlr_foreign_toplevel_manager_v1_destroy(d->manager);
    }
    if (d->seat) {
        wl_seat_destroy(d->seat);
    }
    if (d->registry) {
        wl_registry_destroy(d->registry);
    }
    if (d->display) {
        wl_display_flush(d->display);
        wl_display_disconnect(d->display);
    }
    delete d;
    d = nullptr;
}

bool MonitorTareas::iniciar(QString *error)
{
    d->display = wl_display_connect(nullptr);
    if (!d->display) {
        if (error) {
            *error = QStringLiteral(
                "No hay conexion Wayland (WAYLAND_DISPLAY).");
        }
        return false;
    }

    d->registry = wl_display_get_registry(d->display);
    wl_registry_add_listener(d->registry, &kListenerRegistry, d);
    if (wl_display_roundtrip(d->display) < 0) {
        if (error) {
            *error = QStringLiteral("Fallo al leer el registro Wayland.");
        }
        return false;
    }
    if (!d->manager) {
        if (error) {
            *error = QStringLiteral(
                "El compositor no ofrece wlr-foreign-toplevel-management.");
        }
        return false;
    }

    if (wl_display_roundtrip(d->display) < 0) {
        if (error) {
            *error = QStringLiteral("Fallo al recibir las ventanas.");
        }
        return false;
    }

    const int fd = wl_display_get_fd(d->display);
    d->notificador = new QSocketNotifier(fd, QSocketNotifier::Read, this);
    connect(d->notificador, &QSocketNotifier::activated, this,
            [this](QSocketDescriptor, QSocketNotifier::Type) {
                procesar();
            });
    return true;
}

void MonitorTareas::procesar()
{
    if (!d->display) {
        return;
    }
    if (wl_display_dispatch(d->display) < 0) {
        qWarning("titan-panel: se perdio la conexion Wayland");
        d->notificador->setEnabled(false);
    }
}

QVector<Ventana> MonitorTareas::ventanas() const
{
    QVector<Ventana> salida;
    salida.reserve(d->orden.size());
    for (quintptr id : d->orden) {
        const auto it = d->ventanas.constFind(id);
        if (it != d->ventanas.constEnd()) {
            salida << it.value();
        }
    }
    return salida;
}

void MonitorTareas::activar(quintptr id)
{
    auto it = d->manejadores.constFind(id);
    if (it == d->manejadores.constEnd()) {
        return;
    }
    zwlr_foreign_toplevel_handle_v1_unset_minimized((*it)->handle);
    if (d->seat && d->managerVersion >= 3) {
        zwlr_foreign_toplevel_handle_v1_activate((*it)->handle, d->seat);
    }
    wl_display_flush(d->display);
}

void MonitorTareas::minimizar(quintptr id, bool minimizada)
{
    auto it = d->manejadores.constFind(id);
    if (it == d->manejadores.constEnd()) {
        return;
    }
    if (minimizada) {
        zwlr_foreign_toplevel_handle_v1_set_minimized((*it)->handle);
    } else {
        zwlr_foreign_toplevel_handle_v1_unset_minimized((*it)->handle);
    }
    wl_display_flush(d->display);
}

void MonitorTareas::maximizar(quintptr id, bool maximizada)
{
    auto it = d->manejadores.constFind(id);
    if (it == d->manejadores.constEnd()) {
        return;
    }
    if (maximizada) {
        zwlr_foreign_toplevel_handle_v1_set_maximized((*it)->handle);
    } else {
        zwlr_foreign_toplevel_handle_v1_unset_maximized((*it)->handle);
    }
    wl_display_flush(d->display);
}

void MonitorTareas::cerrar(quintptr id)
{
    auto it = d->manejadores.constFind(id);
    if (it == d->manejadores.constEnd()) {
        return;
    }
    zwlr_foreign_toplevel_handle_v1_close((*it)->handle);
    wl_display_flush(d->display);
}
