#ifndef TITAN_COLA_APPS_H
#define TITAN_COLA_APPS_H

#include <QObject>
#include <QList>
#include <QStringList>

class QTimer;
class QQuickWindow;
class WindowTracker;

// Cola para abrir apps de una en una (Dock, Launchpad, búsqueda, escritorio).
//
// Abrir varias a la vez en un equipo lento hacía que se pisaran: dobles
// ventanas, el Dock rebotando con iconos de más... Ahora cada app espera a que
// la anterior abra su ventana (o a que pasen unos segundos) y pulsar dos veces
// la misma mientras se abre no la abre dos veces.
//
// Mientras se abre: si la app está en el Dock, rebota su icono (lo hace
// DockModel); si no, aparece un pequeño indicador junto al puntero.
class ColaApps : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool indicador READ indicador NOTIFY indicadorCambiado)
    Q_PROPERTY(QString icono READ icono NOTIFY indicadorCambiado)

public:
    static ColaApps *instancia();

    void setTracker(WindowTracker *tracker);
    void setVentanaIndicador(QQuickWindow *ventana);

    // enDock: la app tiene icono en el Dock (rebota allí, sin indicador)
    Q_INVOKABLE void lanzar(const QString &programa, const QStringList &args,
                            bool enDock = false, const QString &icono = QString());

    bool indicador() const { return m_indicador; }
    QString icono() const { return m_icono; }

signals:
    void indicadorCambiado();

private:
    explicit ColaApps(QObject *padre = nullptr);
    struct Pedido {
        QString programa;
        QStringList args;
        bool enDock = false;
        QString icono;
        QString clave;
    };
    void siguiente();
    void terminarActual();
    void ponerIndicador(bool visible, const QString &icono = QString());
    void moverIndicador();
    static QString claveDe(const QString &programa, const QStringList &args);

    QList<Pedido> m_cola;
    QString m_actual;          // clave de la app que se está abriendo
    int m_ventanasAntes = 0;
    WindowTracker *m_tracker = nullptr;
    QQuickWindow *m_ventana = nullptr;
    QTimer *m_espera = nullptr;     // máximo que se espera a la ventana
    QTimer *m_puntero = nullptr;    // sigue al puntero mientras se ve
    QTimer *m_finIndicador = nullptr;
    bool m_indicador = false;
    QString m_icono;
};

#endif
