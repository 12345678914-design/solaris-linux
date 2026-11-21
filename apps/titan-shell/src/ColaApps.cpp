#include "ColaApps.h"
#include "WindowTracker.h"
#include "WayfireIpc.h"

#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonObject>
#include <QProcess>
#include <QQuickWindow>
#include <QScreen>
#include <QTimer>

#include <LayerShellQt/window.h>

namespace {
// Tiempo máximo que se espera a la ventana de una app antes de abrir la
// siguiente de la cola (las hay que tardan, como LibreOffice en un Celeron).
constexpr int kEsperaVentanaMs = 8000;
// El indicador junto al puntero se quita como mucho a los 15 s
constexpr int kMaxIndicadorMs = 15000;
// Separación entre el puntero y el indicador
constexpr int kDesplazamiento = 18;
}

ColaApps *ColaApps::instancia()
{
    static ColaApps *cola = new ColaApps(qApp);
    return cola;
}

ColaApps::ColaApps(QObject *padre)
    : QObject(padre)
{
    m_espera = new QTimer(this);
    m_espera->setSingleShot(true);
    m_espera->setInterval(kEsperaVentanaMs);
    connect(m_espera, &QTimer::timeout, this, &ColaApps::terminarActual);

    m_puntero = new QTimer(this);
    m_puntero->setInterval(40);
    connect(m_puntero, &QTimer::timeout, this, &ColaApps::moverIndicador);

    m_finIndicador = new QTimer(this);
    m_finIndicador->setSingleShot(true);
    m_finIndicador->setInterval(kMaxIndicadorMs);
    connect(m_finIndicador, &QTimer::timeout, this, [this]() { ponerIndicador(false); });
}

void ColaApps::setTracker(WindowTracker *tracker)
{
    m_tracker = tracker;
    if (!m_tracker)
        return;
    // Ventana nueva = la app que se estaba abriendo ya está (o como mínimo
    // ya hay algo en pantalla): fuera indicador y paso a la siguiente.
    connect(m_tracker, &WindowTracker::windowsChanged, this, [this]() {
        const int n = m_tracker->windows().size();
        const bool nueva = n > m_ventanasAntes;
        m_ventanasAntes = n;
        if (!nueva)
            return;
        if (m_indicador)
            ponerIndicador(false);
        if (!m_actual.isEmpty())
            terminarActual();
    });
}

void ColaApps::setVentanaIndicador(QQuickWindow *ventana)
{
    m_ventana = ventana;
}

QString ColaApps::claveDe(const QString &programa, const QStringList &args)
{
    // La orden completa: "python3 app-a.py" y "python3 app-b.py" (o dos
    // "flatpak run ...") son apps distintas; la misma orden, la misma app.
    return (QStringList{QFileInfo(programa).fileName()} + args).join(QLatin1Char(' '));
}

void ColaApps::lanzar(const QString &programa, const QStringList &args, bool enDock, const QString &icono)
{
    if (programa.isEmpty())
        return;
    const QString clave = claveDe(programa, args);

    // Pulsar otra vez la misma app mientras se abre no la abre dos veces
    if (clave == m_actual)
        return;
    for (const Pedido &p : std::as_const(m_cola))
        if (p.clave == clave)
            return;

    m_cola.append({programa, args, enDock, icono, clave});
    if (m_actual.isEmpty())
        siguiente();
}

void ColaApps::siguiente()
{
    if (m_cola.isEmpty())
        return;
    const Pedido p = m_cola.takeFirst();
    m_actual = p.clave;
    m_ventanasAntes = m_tracker ? m_tracker->windows().size() : 0;

    if (!QProcess::startDetached(p.programa, p.args)) {
        // No se pudo ni empezar: no hay ventana que esperar
        m_actual.clear();
        QTimer::singleShot(0, this, &ColaApps::siguiente);
        return;
    }

    if (!p.enDock)
        ponerIndicador(true, p.icono);
    m_espera->start();
}

void ColaApps::terminarActual()
{
    // Por ventana nueva o por tiempo agotado. Si fue por tiempo, el
    // indicador sigue (la app puede ser lenta) hasta su ventana o kMaxIndicadorMs.
    m_espera->stop();
    m_actual.clear();
    if (!m_cola.isEmpty())
        QTimer::singleShot(150, this, &ColaApps::siguiente);   // respiro para colocar la anterior
}

void ColaApps::ponerIndicador(bool visible, const QString &icono)
{
    if (visible) {
        m_icono = icono;
        m_finIndicador->start();
        if (m_ventana) {
            moverIndicador();
            m_ventana->setVisible(true);
        }
        m_puntero->start();
    } else {
        m_finIndicador->stop();
        m_puntero->stop();
        if (m_ventana)
            m_ventana->setVisible(false);
    }
    m_indicador = visible;
    emit indicadorCambiado();
}

void ColaApps::moverIndicador()
{
    if (!m_ventana)
        return;
    auto *ipc = WayfireIpc::instancia();
    if (!ipc->disponible())
        return;
    const QJsonObject pos = ipc->llamar(QStringLiteral("window-rules/get_cursor_position"), {}, 100)
                                .value(QStringLiteral("pos")).toObject();
    if (pos.isEmpty())
        return;
    const QPoint p(int(pos.value(QStringLiteral("x")).toDouble()), int(pos.value(QStringLiteral("y")).toDouble()));

    // Coordenadas del conjunto de pantallas -> de la pantalla donde está
    QScreen *pantalla = QGuiApplication::screenAt(p);
    if (!pantalla)
        pantalla = m_ventana->screen();
    const QRect g = pantalla ? pantalla->geometry() : QRect();
    if (pantalla && m_ventana->screen() != pantalla && !m_ventana->isVisible())
        m_ventana->setScreen(pantalla);

    int x = p.x() - g.x() + kDesplazamiento;
    int y = p.y() - g.y() + kDesplazamiento;
    // Que no se salga por la derecha ni por abajo
    if (g.isValid()) {
        x = qMin(x, g.width() - m_ventana->width());
        y = qMin(y, g.height() - m_ventana->height());
    }
    if (auto *ls = LayerShellQt::Window::get(m_ventana))
        ls->setMargins(QMargins(qMax(0, x), qMax(0, y), 0, 0));
}
