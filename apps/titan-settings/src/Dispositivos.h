// Inti OS - Ajustes: pantallas (wlr-randr, brillo, luz nocturna) y sonido
// (PipeWire con pactl). Todo en procesos asincronos.
#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <functional>

class QTimer;

class Dispositivos : public QObject
{
    Q_OBJECT
    // Pantallas: [{nombre, descripcion, activa, modos[{ancho,alto,hz,texto,actual,preferido}],
    //              modo, escala, giro, x, y}]
    Q_PROPERTY(QVariantList pantallas READ pantallas NOTIFY pantallasCambiadas)
    Q_PROPERTY(bool pantallasDisponibles READ pantallasDisponibles NOTIFY pantallasCambiadas)
    Q_PROPERTY(bool pendienteConfirmar READ pendienteConfirmar NOTIFY pendienteCambiado)
    Q_PROPERTY(int brillo READ brillo NOTIFY brilloCambiado)          // -1 = sin control
    Q_PROPERTY(QVariantMap luzNocturna READ luzNocturna NOTIFY luzCambiada)
    // Sonido: [{nombre, descripcion, volumen, silencio, predeterminado}]
    Q_PROPERTY(QVariantList salidas READ salidas NOTIFY sonidoCambiado)
    Q_PROPERTY(QVariantList entradas READ entradas NOTIFY sonidoCambiado)
    Q_PROPERTY(bool sonidoDisponible READ sonidoDisponible NOTIFY sonidoCambiado)
    Q_PROPERTY(QString aviso READ aviso NOTIFY avisoCambiado)

public:
    explicit Dispositivos(QObject *parent = nullptr);

    QVariantList pantallas() const { return m_pantallas; }
    bool pantallasDisponibles() const { return m_pantallasOk; }
    bool pendienteConfirmar() const { return !m_anterior.isEmpty(); }
    int brillo() const { return m_brillo; }
    QVariantMap luzNocturna() const { return m_luz; }
    QVariantList salidas() const { return m_salidas; }
    QVariantList entradas() const { return m_entradas; }
    bool sonidoDisponible() const { return m_sonidoOk; }
    QString aviso() const { return m_aviso; }

    Q_INVOKABLE void leerPantallas();
    // Cambia una pantalla: modo "1920x1080@60.000", escala, giro ("normal", "90"...),
    // activa. Hay que confirmarlo en 15 s o se deshace solo.
    Q_INVOKABLE void aplicarPantalla(const QString &nombre, const QString &modo, double escala,
                                     const QString &giro, bool activa);
    Q_INVOKABLE void confirmarPantallas();
    Q_INVOKABLE void deshacerPantallas();
    Q_INVOKABLE void identificar();

    Q_INVOKABLE void leerBrillo();
    Q_INVOKABLE void setBrillo(int porcentaje);

    Q_INVOKABLE void setLuzNocturna(const QString &clave, const QVariant &valor);

    Q_INVOKABLE void leerSonido();
    Q_INVOKABLE void setPredeterminado(bool salida, const QString &nombre);
    Q_INVOKABLE void setVolumen(bool salida, const QString &nombre, int porcentaje);
    Q_INVOKABLE void setSilencio(bool salida, const QString &nombre, bool silencio);
    Q_INVOKABLE void probarSonido();

signals:
    void pantallasCambiadas();
    void pendienteCambiado();
    void brilloCambiado();
    void luzCambiada();
    void sonidoCambiado();
    void avisoCambiado();

private:
    using Fin = std::function<void(int codigo, const QByteArray &salida, const QString &error)>;
    void correr(const QString &programa, const QStringList &args, Fin fin);
    void avisar(const QString &t);
    QStringList argumentosDe(const QVariantMap &p) const;
    void guardarPantallas();
    void leerLuz();

    QVariantList m_pantallas;
    bool m_pantallasOk = false;
    QVariantList m_anterior;     // para deshacer
    QTimer *m_cuentaAtras = nullptr;
    int m_brillo = -1;
    QVariantMap m_luz;
    QVariantList m_salidas;
    QVariantList m_entradas;
    bool m_sonidoOk = false;
    QString m_aviso;
    QTimer *m_volumenTimer = nullptr;
    QVariantMap m_volumenPendiente;
};
