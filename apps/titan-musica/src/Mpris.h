// Inti OS - Música: MPRIS2 (org.mpris.MediaPlayer2.titan_musica). Con esto la
// Isla del shell, las teclas multimedia y playerctl controlan la música.
#pragma once

#include <QDBusAbstractAdaptor>
#include <QDBusObjectPath>
#include <QStringList>
#include <QVariantMap>

class MusicaBackend;

namespace Mpris {
inline const QString servicio = QStringLiteral("org.mpris.MediaPlayer2.titan_musica");
inline const QString ruta = QStringLiteral("/org/mpris/MediaPlayer2");
// Registra el servicio; false si otra instancia ya lo tiene.
bool registrar(MusicaBackend *backend);
}

class MprisRaiz : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(bool CanQuit READ siempre)
    Q_PROPERTY(bool CanRaise READ siempre)
    Q_PROPERTY(bool HasTrackList READ nunca)
    Q_PROPERTY(QString Identity READ identidad)
    Q_PROPERTY(QString DesktopEntry READ escritorio)
    Q_PROPERTY(QStringList SupportedUriSchemes READ esquemas)
    Q_PROPERTY(QStringList SupportedMimeTypes READ tipos)

public:
    MprisRaiz(QObject *padre, MusicaBackend *b);
    bool siempre() const { return true; }
    bool nunca() const { return false; }
    QString identidad() const { return QStringLiteral("Música"); }
    QString escritorio() const { return QStringLiteral("titan-musica"); }
    QStringList esquemas() const { return {QStringLiteral("file")}; }
    QStringList tipos() const;

public slots:
    void Raise();
    void Quit();

private:
    MusicaBackend *m_b;
};

class MprisReproductor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus READ estado)
    Q_PROPERTY(QString LoopStatus READ bucle WRITE setBucle)
    Q_PROPERTY(double Rate READ uno WRITE setRate)
    Q_PROPERTY(bool Shuffle READ aleatorio WRITE setAleatorio)
    Q_PROPERTY(QVariantMap Metadata READ metadatos)
    Q_PROPERTY(double Volume READ volumen WRITE setVolumen)
    Q_PROPERTY(qlonglong Position READ posicion)
    Q_PROPERTY(double MinimumRate READ uno)
    Q_PROPERTY(double MaximumRate READ uno)
    Q_PROPERTY(bool CanGoNext READ puedeSiguiente)
    Q_PROPERTY(bool CanGoPrevious READ puedeAnterior)
    Q_PROPERTY(bool CanPlay READ hayPista)
    Q_PROPERTY(bool CanPause READ hayPista)
    Q_PROPERTY(bool CanSeek READ hayPista)
    Q_PROPERTY(bool CanControl READ siempre)

public:
    MprisReproductor(QObject *padre, MusicaBackend *b);
    QString estado() const;
    QString bucle() const;
    void setBucle(const QString &v);
    double uno() const { return 1.0; }
    void setRate(double) {}
    bool aleatorio() const;
    void setAleatorio(bool a);
    QVariantMap metadatos() const;
    double volumen() const;
    void setVolumen(double v);
    qlonglong posicion() const;
    bool puedeSiguiente() const;
    bool puedeAnterior() const;
    bool hayPista() const;
    bool siempre() const { return true; }

public slots:
    void Next();
    void Previous();
    void Pause();
    void PlayPause();
    void Stop();
    void Play();
    void Seek(qlonglong offset);
    void SetPosition(const QDBusObjectPath &pista, qlonglong pos);
    void OpenUri(const QString &uri);

signals:
    void Seeked(qlonglong posicion);

private:
    void avisar(const QStringList &propiedades);
    MusicaBackend *m_b;
};
