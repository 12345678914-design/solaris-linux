// Inti OS - lo que suena ahora (MPRIS) para la Isla Dinamica.
//
// Sigue todos los reproductores org.mpris.MediaPlayer2.* del bus de sesion
// (Firefox, Chromium, Spotify, mpv, VLC, titan-musica...) y elige uno: el que
// esta sonando; si ninguno suena, el ultimo que sono y esta en pausa. Todas
// las llamadas por D-Bus son asincronas: un reproductor colgado no congela
// el escritorio.
#pragma once

#include <QObject>
#include <QHash>
#include <QString>
#include <QStringList>
#include <QDateTime>

class QDBusMessage;
class QTimer;

class Mpris : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool disponible READ disponible NOTIFY cambiado)
    Q_PROPERTY(bool reproduciendo READ reproduciendo NOTIFY cambiado)
    Q_PROPERTY(QString titulo READ titulo NOTIFY cambiado)
    Q_PROPERTY(QString artista READ artista NOTIFY cambiado)
    Q_PROPERTY(QString album READ album NOTIFY cambiado)
    Q_PROPERTY(QString caratula READ caratula NOTIFY cambiado)
    Q_PROPERTY(QString reproductor READ reproductor NOTIFY cambiado)
    Q_PROPERTY(bool puedeAnterior READ puedeAnterior NOTIFY cambiado)
    Q_PROPERTY(bool puedeSiguiente READ puedeSiguiente NOTIFY cambiado)
public:
    explicit Mpris(QObject *parent = nullptr);

    bool disponible() const { return !m_actual.isEmpty(); }
    bool reproduciendo() const;
    QString titulo() const { return estado().titulo; }
    QString artista() const { return estado().artista; }
    QString album() const { return estado().album; }
    QString caratula() const { return estado().caratula; }
    QString reproductor() const;
    bool puedeAnterior() const { return estado().puedeAnterior; }
    bool puedeSiguiente() const { return estado().puedeSiguiente; }

    Q_INVOKABLE void alternar();
    Q_INVOKABLE void siguiente();
    Q_INVOKABLE void anterior();
    Q_INVOKABLE void mostrarReproductor();

signals:
    void cambiado();
    // Empieza a sonar otra cancion (la isla se abre un momento para ensenarla).
    void cancionNueva();

private slots:
    void nombreCambiado(const QString &nombre, const QString &antes, const QString &ahora);
    void propiedadesCambiadas(const QDBusMessage &msg);

private:
    struct Estado {
        QString estado;          // Playing / Paused / Stopped
        QString titulo, artista, album, caratula, identidad;
        bool puedeAnterior = false, puedeSiguiente = false;
        QDateTime ultimaVezSonando;
    };
    const Estado &estado() const;
    void anadir(const QString &nombre);
    void consultar(const QString &nombre);
    void elegir();
    void llamar(const QString &metodo, const QString &interfaz = QString());

    QHash<QString, Estado> m_reproductores;   // nombre de bus -> estado
    QHash<QString, QString> m_duenos;         // nombre unico (:1.42) -> nombre de bus
    QString m_actual;
    QString m_cancionAnterior;
    QTimer *m_repaso = nullptr;
};
