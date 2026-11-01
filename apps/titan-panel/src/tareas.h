#ifndef TITAN_TAREAS_H
#define TITAN_TAREAS_H

#include <QHash>
#include <QObject>
#include <QString>
#include <QVector>

struct wl_display;
struct wl_registry;
struct wl_seat;
struct zwlr_foreign_toplevel_manager_v1;
struct zwlr_foreign_toplevel_handle_v1;
class QSocketNotifier;

struct Ventana
{
    quintptr id = 0;
    QString titulo;
    QString appId;
    bool activa = false;
    bool minimizada = false;
    bool maximizada = false;
    bool pantallaCompleta = false;
};

// Cliente de wlr-foreign-toplevel-management. Solo depende del protocolo
// Wayland, no de labwc: cualquier compositor que lo exponga puede usarlo.
class MonitorTareas : public QObject
{
    Q_OBJECT

public:
    struct Privado;

    explicit MonitorTareas(QObject *padre = nullptr);
    ~MonitorTareas() override;

    bool iniciar(QString *error);
    QVector<Ventana> ventanas() const;

    void activar(quintptr id);
    void minimizar(quintptr id, bool minimizada);
    void maximizar(quintptr id, bool maximizada);
    void cerrar(quintptr id);

signals:
    void cambiado();

private:
    Privado *d = nullptr;

    void procesar();
};

#endif
