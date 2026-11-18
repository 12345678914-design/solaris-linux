#include "Mpris.h"

#include "MusicaBackend.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QMetaProperty>

namespace Mpris {

bool registrar(MusicaBackend *b)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return true; // sin bus: la app funciona igual
    new MprisRaiz(b, b);
    new MprisReproductor(b, b);
    if (!bus.registerObject(ruta, b))
        return true;
    return bus.registerService(servicio);
}

} // namespace Mpris

MprisRaiz::MprisRaiz(QObject *padre, MusicaBackend *b)
    : QDBusAbstractAdaptor(padre)
    , m_b(b)
{
}

QStringList MprisRaiz::tipos() const
{
    return {QStringLiteral("audio/mpeg"), QStringLiteral("audio/flac"), QStringLiteral("audio/ogg"),
            QStringLiteral("audio/x-vorbis+ogg"), QStringLiteral("audio/x-opus+ogg"), QStringLiteral("audio/mp4"),
            QStringLiteral("audio/aac"), QStringLiteral("audio/x-wav"), QStringLiteral("audio/x-ms-wma")};
}

void MprisRaiz::Raise()
{
    m_b->levantar();
}

void MprisRaiz::Quit()
{
    QCoreApplication::quit();
}

MprisReproductor::MprisReproductor(QObject *padre, MusicaBackend *b)
    : QDBusAbstractAdaptor(padre)
    , m_b(b)
{
    connect(b, &MusicaBackend::estadoChanged, this, [this] { avisar({QStringLiteral("PlaybackStatus"), QStringLiteral("CanPlay"), QStringLiteral("CanPause"), QStringLiteral("CanSeek")}); });
    connect(b, &MusicaBackend::actualChanged, this, [this] {
        avisar({QStringLiteral("Metadata"), QStringLiteral("CanGoNext"), QStringLiteral("CanGoPrevious"), QStringLiteral("CanPlay"), QStringLiteral("CanPause"), QStringLiteral("CanSeek")});
    });
    connect(b, &MusicaBackend::duracionChanged, this, [this] { avisar({QStringLiteral("Metadata")}); });
    connect(b, &MusicaBackend::colaChanged, this, [this] { avisar({QStringLiteral("CanGoNext")}); });
    connect(b, &MusicaBackend::modoChanged, this, [this] { avisar({QStringLiteral("LoopStatus"), QStringLiteral("Shuffle"), QStringLiteral("CanGoNext")}); });
    connect(b, &MusicaBackend::volumenChanged, this, [this] { avisar({QStringLiteral("Volume")}); });
    connect(b, &MusicaBackend::saltoDePosicion, this, [this](qint64 ms) { emit Seeked(ms * 1000); });
}

void MprisReproductor::avisar(const QStringList &propiedades)
{
    QVariantMap cambios;
    for (const QString &p : propiedades) {
        const int i = metaObject()->indexOfProperty(p.toLatin1().constData());
        if (i >= 0)
            cambios.insert(p, metaObject()->property(i).read(this));
    }
    QDBusMessage m = QDBusMessage::createSignal(Mpris::ruta, QStringLiteral("org.freedesktop.DBus.Properties"),
                                                QStringLiteral("PropertiesChanged"));
    m << QStringLiteral("org.mpris.MediaPlayer2.Player") << cambios << QStringList();
    QDBusConnection::sessionBus().send(m);
}

QString MprisReproductor::estado() const
{
    if (m_b->reproduciendo())
        return QStringLiteral("Playing");
    return m_b->rutaActual().isEmpty() ? QStringLiteral("Stopped") : QStringLiteral("Paused");
}

QString MprisReproductor::bucle() const
{
    switch (m_b->repetir()) {
    case 1: return QStringLiteral("Playlist");
    case 2: return QStringLiteral("Track");
    default: return QStringLiteral("None");
    }
}

void MprisReproductor::setBucle(const QString &v)
{
    m_b->setRepetir(v == QLatin1String("Playlist") ? 1 : v == QLatin1String("Track") ? 2 : 0);
}

bool MprisReproductor::aleatorio() const
{
    return m_b->aleatorio();
}

void MprisReproductor::setAleatorio(bool a)
{
    m_b->setAleatorio(a);
}

QVariantMap MprisReproductor::metadatos() const
{
    const QVariantMap a = m_b->actual();
    if (a.isEmpty())
        return {};
    const QString id = QString::fromLatin1(QCryptographicHash::hash(m_b->rutaActual().toUtf8(), QCryptographicHash::Md5).toHex());
    QVariantMap m;
    m.insert(QStringLiteral("mpris:trackid"), QVariant::fromValue(QDBusObjectPath(QStringLiteral("/org/inti/musica/pista/") + id)));
    const qint64 dur = m_b->duracion() > 0 ? m_b->duracion() : a.value(QStringLiteral("duracion")).toLongLong();
    m.insert(QStringLiteral("mpris:length"), qlonglong(dur * 1000));
    m.insert(QStringLiteral("xesam:title"), a.value(QStringLiteral("titulo")));
    m.insert(QStringLiteral("xesam:artist"), QStringList{a.value(QStringLiteral("artista")).toString()});
    m.insert(QStringLiteral("xesam:album"), a.value(QStringLiteral("album")));
    m.insert(QStringLiteral("xesam:albumArtist"), QStringList{a.value(QStringLiteral("artistaAlbum")).toString()});
    if (!a.value(QStringLiteral("genero")).toString().isEmpty())
        m.insert(QStringLiteral("xesam:genre"), QStringList{a.value(QStringLiteral("genero")).toString()});
    if (a.value(QStringLiteral("numero")).toInt() > 0)
        m.insert(QStringLiteral("xesam:trackNumber"), a.value(QStringLiteral("numero")).toInt());
    m.insert(QStringLiteral("xesam:url"), a.value(QStringLiteral("url")));
    if (!a.value(QStringLiteral("portada")).toString().isEmpty())
        m.insert(QStringLiteral("mpris:artUrl"), a.value(QStringLiteral("portada")));
    return m;
}

double MprisReproductor::volumen() const
{
    return m_b->volumen();
}

void MprisReproductor::setVolumen(double v)
{
    m_b->setVolumen(v);
}

qlonglong MprisReproductor::posicion() const
{
    return m_b->posicion() * 1000;
}

bool MprisReproductor::puedeSiguiente() const
{
    return m_b->haySiguiente();
}

bool MprisReproductor::puedeAnterior() const
{
    return m_b->hayAnterior();
}

bool MprisReproductor::hayPista() const
{
    return !m_b->rutaActual().isEmpty() || m_b->totalCanciones() > 0;
}

void MprisReproductor::Next() { m_b->siguiente(); }
void MprisReproductor::Previous() { m_b->anterior(); }
void MprisReproductor::Pause() { m_b->pause(); }
void MprisReproductor::PlayPause() { m_b->togglePlay(); }
void MprisReproductor::Stop() { m_b->stop(); }
void MprisReproductor::Play() { m_b->play(); }

void MprisReproductor::Seek(qlonglong offset)
{
    const qint64 ms = m_b->posicion() + offset / 1000;
    if (m_b->duracion() > 0 && ms > m_b->duracion())
        m_b->siguiente();
    else
        m_b->seek(qMax<qint64>(0, ms));
}

void MprisReproductor::SetPosition(const QDBusObjectPath &, qlonglong pos)
{
    if (pos >= 0 && (m_b->duracion() <= 0 || pos / 1000 <= m_b->duracion()))
        m_b->seek(pos / 1000);
}

void MprisReproductor::OpenUri(const QString &uri)
{
    m_b->abrirArchivos({uri});
    m_b->levantar();
}
