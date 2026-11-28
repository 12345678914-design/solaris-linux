#pragma once
// Monitor de recursos de Inti OS: lee /proc y /sys directamente (sin
// procesos auxiliares). Solo trabaja lo que se ve: la lista de procesos se
// calcula si la página Procesos está abierta, y nada si la ventana está
// minimizada (pausa la vista).
#include <QHash>
#include <QObject>
#include <QSet>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class MonitorBackend : public QObject
{
    Q_OBJECT
    // Ajustes
    Q_PROPERTY(int intervalo READ intervalo WRITE setIntervalo NOTIFY intervaloChanged)          // ms; 0 = en pausa
    Q_PROPERTY(QString pagina READ pagina WRITE setPagina NOTIFY paginaChanged)                  // procesos | rendimiento | inicio
    Q_PROPERTY(bool activo READ activo WRITE setActivo NOTIFY activoChanged)                     // ventana visible
    Q_PROPERTY(bool todosLosUsuarios READ todosLosUsuarios WRITE setTodosLosUsuarios NOTIFY procesosChanged)
    Q_PROPERTY(QString orden READ orden WRITE setOrden NOTIFY procesosChanged)                   // nombre | cpu | memoria | disco
    Q_PROPERTY(bool ordenDescendente READ ordenDescendente WRITE setOrdenDescendente NOTIFY procesosChanged)
    Q_PROPERTY(QString filtro READ filtro WRITE setFiltro NOTIFY procesosChanged)

    // Rendimiento (se actualiza junto, con la señal muestra())
    Q_PROPERTY(QVariantMap cpu READ cpu NOTIFY muestra)
    Q_PROPERTY(QVariantMap memoria READ memoria NOTIFY muestra)
    Q_PROPERTY(QVariantList discos READ discos NOTIFY muestra)
    Q_PROPERTY(QVariantList redes READ redes NOTIFY muestra)

    // Procesos e inicio
    Q_PROPERTY(QVariantList aplicaciones READ aplicaciones NOTIFY procesosChanged)
    Q_PROPERTY(QVariantList segundoPlano READ segundoPlano NOTIFY procesosChanged)
    Q_PROPERTY(QVariantList inicio READ inicio NOTIFY inicioChanged)
    Q_PROPERTY(QString aviso READ aviso NOTIFY avisoChanged)

public:
    explicit MonitorBackend(QObject *parent = nullptr);

    int intervalo() const { return m_intervalo; }
    void setIntervalo(int ms);
    QString pagina() const { return m_pagina; }
    void setPagina(const QString &p);
    bool activo() const { return m_activo; }
    void setActivo(bool a);
    bool todosLosUsuarios() const { return m_todos; }
    void setTodosLosUsuarios(bool t);
    QString orden() const { return m_orden; }
    void setOrden(const QString &o);
    bool ordenDescendente() const { return m_desc; }
    void setOrdenDescendente(bool d);
    QString filtro() const { return m_filtro; }
    void setFiltro(const QString &f);

    QVariantMap cpu() const { return m_cpu; }
    QVariantMap memoria() const { return m_memoria; }
    QVariantList discos() const { return m_discosVista; }
    QVariantList redes() const { return m_redesVista; }
    QVariantList aplicaciones() const { return m_aplicaciones; }
    QVariantList segundoPlano() const { return m_segundoPlano; }
    QVariantList inicio() const { return m_inicio; }
    QString aviso() const { return m_aviso; }

    // Finaliza los procesos (solo los tuyos). forzar = SIGKILL sin esperar.
    Q_INVOKABLE void finalizar(const QVariantList &pids, const QString &nombre, bool forzar = false);
    Q_INVOKABLE void activarInicio(const QString &id, bool activado);
    Q_INVOKABLE void cerrarAviso();
    Q_INVOKABLE void actualizarAhora() { muestrear(); }
    Q_INVOKABLE QString bytes(double b) const;          // "1,2 GB"
    Q_INVOKABLE QString velocidad(double bps) const;    // "350 KB/s"
    Q_INVOKABLE QString mbs(double bps) const;          // "0,4 MB/s" (columna Disco)

signals:
    void intervaloChanged();
    void paginaChanged();
    void activoChanged();
    void muestra();
    void procesosChanged();
    void inicioChanged();
    void avisoChanged();

private:
    void muestrear();
    void leerCpu();
    void leerMemoria();
    void leerDiscos(double segundos);
    void leerRedes(double segundos);
    void leerProcesos(double segundos);
    void ordenarProcesos();
    void cargarInicio();
    void cargarApps();
    void ponerAviso(const QString &t);
    void reprogramar();

    QTimer m_timer;
    int m_intervalo = 1000;
    QString m_pagina = QStringLiteral("procesos");
    bool m_activo = true;
    bool m_todos = false;
    QString m_orden = QStringLiteral("cpu");
    bool m_desc = true;
    QString m_filtro;
    QString m_aviso;
    qint64 m_ultimo = 0;            // ms de la muestra anterior
    static constexpr int kHistorial = 60;

    // CPU
    QVector<quint64> m_cpuTotalAnt, m_cpuOcupadoAnt;   // [0] = total, [1..] = núcleos
    QVariantList m_histCpu;
    QList<QVariantList> m_histNucleos;
    QVariantMap m_cpu;
    QString m_modeloCpu;

    // Memoria
    QVariantList m_histMem;
    QVariantMap m_memoria;

    // Discos y redes: por nombre
    struct Disco { quint64 leido = 0, escrito = 0, msOcupado = 0; QVariantList hist, histL, histE; QString modelo; double tamano = 0; };
    struct Red { quint64 rx = 0, tx = 0; QVariantList histRx, histTx; bool wifi = false; };
    QHash<QString, Disco> m_discos;
    QHash<QString, Red> m_redes;
    QVariantList m_discosVista, m_redesVista;

    // Procesos
    struct Proc { quint64 ticks = 0; quint64 io = 0; };
    QHash<int, Proc> m_procAnt;
    quint64 m_ticksTotalAnt = 0;
    QVariantList m_aplicaciones, m_segundoPlano;
    QVariantList m_procBrutos;                 // la última lectura, para reordenar sin leer
    struct App { QString nombre; QString icono; };
    QHash<QString, App> m_apps;                // programa (basename del Exec) -> app
    qint64 m_appsLeidas = 0;
    uint m_uid = 0;
    long m_hz = 100;
    long m_pagina4k = 4096;

    QVariantList m_inicio;
};
