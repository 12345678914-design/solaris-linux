#include "Mpris.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusArgument>
#include <QDBusVariant>
#include <QTimer>
#include <QUrl>

namespace {
const QString kPrefijo = QStringLiteral("org.mpris.MediaPlayer2.");
const QString kRuta = QStringLiteral("/org/mpris/MediaPlayer2");
const QString kRaiz = QStringLiteral("org.mpris.MediaPlayer2");
const QString kPlayer = QStringLiteral("org.mpris.MediaPlayer2.Player");
const QString kProps = QStringLiteral("org.freedesktop.DBus.Properties");

QVariantMap aMapa(const QVariant &v)
{
    if (v.canConvert<QDBusArgument>()) {
        QVariantMap m;
        v.value<QDBusArgument>() >> m;
        return m;
    }
    return v.toMap();
}

QString aTexto(const QVariant &v)
{
    if (v.canConvert<QDBusArgument>()) {
        QStringList l;
        v.value<QDBusArgument>() >> l;
        return l.join(QStringLiteral(", "));
    }
    if (v.typeId() == QMetaType::QStringList)
        return v.toStringList().join(QStringLiteral(", "));
    return v.toString();
}
} // namespace

Mpris::Mpris(QObject *parent)
    : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return;

    // Varias PropertiesChanged seguidas (cancion nueva = titulo + caratula +
    // estado...) se juntan en un solo repaso.
    m_repaso = new QTimer(this);
    m_repaso->setSingleShot(true);
    m_repaso->setInterval(120);
    connect(m_repaso, &QTimer::timeout, this, &Mpris::elegir);

    bus.connect(QStringLiteral("org.freedesktop.DBus"), QStringLiteral("/org/freedesktop/DBus"),
                QStringLiteral("org.freedesktop.DBus"), QStringLiteral("NameOwnerChanged"),
                this, SLOT(nombreCambiado(QString,QString,QString)));
    bus.connect(QString(), kRuta, kProps, QStringLiteral("PropertiesChanged"),
                this, SLOT(propiedadesCambiadas(QDBusMessage)));

    // Reproductores que ya estaban abiertos al arrancar el escritorio.
    QDBusPendingCall pc = bus.interface()->asyncCall(QStringLiteral("ListNames"));
    auto *w = new QDBusPendingCallWatcher(pc, this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<QStringList> r = *w;
        w->deleteLater();
        if (r.isError())
            return;
        for (const QString &n : r.value())
            if (n.startsWith(kPrefijo))
                anadir(n);
    });
}

void Mpris::anadir(const QString &nombre)
{
    if (!m_reproductores.contains(nombre))
        m_reproductores.insert(nombre, Estado());
    // Las senales llegan con el nombre unico del emisor: hay que saber de quien es.
    QDBusPendingCall pc = QDBusConnection::sessionBus().interface()->asyncCall(QStringLiteral("GetNameOwner"), nombre);
    auto *w = new QDBusPendingCallWatcher(pc, this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, nombre](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<QString> r = *w;
        w->deleteLater();
        if (!r.isError())
            m_duenos.insert(r.value(), nombre);
    });
    consultar(nombre);
}

void Mpris::consultar(const QString &nombre)
{
    QDBusConnection bus = QDBusConnection::sessionBus();

    QDBusMessage m = QDBusMessage::createMethodCall(nombre, kRuta, kProps, QStringLiteral("GetAll"));
    m << kPlayer;
    auto *w = new QDBusPendingCallWatcher(bus.asyncCall(m, 2000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, nombre](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<QVariantMap> r = *w;
        w->deleteLater();
        if (r.isError() || !m_reproductores.contains(nombre))
            return;
        const QVariantMap p = r.value();
        Estado &e = m_reproductores[nombre];
        e.estado = p.value(QStringLiteral("PlaybackStatus")).toString();
        e.puedeAnterior = p.value(QStringLiteral("CanGoPrevious"), false).toBool();
        e.puedeSiguiente = p.value(QStringLiteral("CanGoNext"), false).toBool();
        const QVariantMap md = aMapa(p.value(QStringLiteral("Metadata")));
        e.titulo = md.value(QStringLiteral("xesam:title")).toString();
        e.artista = aTexto(md.value(QStringLiteral("xesam:artist")));
        e.album = md.value(QStringLiteral("xesam:album")).toString();
        e.caratula = md.value(QStringLiteral("mpris:artUrl")).toString();
        if (e.titulo.isEmpty()) {
            // Algunos reproductores solo dan la URL (un fichero sin etiquetas).
            const QString url = md.value(QStringLiteral("xesam:url")).toString();
            if (!url.isEmpty())
                e.titulo = QUrl(url).fileName();
        }
        if (e.estado == QStringLiteral("Playing"))
            e.ultimaVezSonando = QDateTime::currentDateTimeUtc();
        if (m_repaso)
            m_repaso->start();
    });

    if (m_reproductores.value(nombre).identidad.isEmpty()) {
        QDBusMessage mi = QDBusMessage::createMethodCall(nombre, kRuta, kProps, QStringLiteral("Get"));
        mi << kRaiz << QStringLiteral("Identity");
        auto *wi = new QDBusPendingCallWatcher(bus.asyncCall(mi, 2000), this);
        connect(wi, &QDBusPendingCallWatcher::finished, this, [this, nombre](QDBusPendingCallWatcher *w) {
            QDBusPendingReply<QDBusVariant> r = *w;
            w->deleteLater();
            if (!r.isError() && m_reproductores.contains(nombre)) {
                m_reproductores[nombre].identidad = r.value().variant().toString();
                if (nombre == m_actual)
                    emit cambiado();
            }
        });
    }
}

void Mpris::nombreCambiado(const QString &nombre, const QString &antes, const QString &ahora)
{
    if (!nombre.startsWith(kPrefijo))
        return;
    if (!antes.isEmpty())
        m_duenos.remove(antes);
    if (ahora.isEmpty()) {
        m_reproductores.remove(nombre);
        elegir();
    } else {
        m_duenos.insert(ahora, nombre);
        anadir(nombre);
    }
}

void Mpris::propiedadesCambiadas(const QDBusMessage &msg)
{
    const QString nombre = m_duenos.value(msg.service());
    if (!nombre.isEmpty()) {
        consultar(nombre);
        return;
    }
    // Emisor aun sin identificar: se repasan todos (son pocos).
    for (auto it = m_reproductores.cbegin(); it != m_reproductores.cend(); ++it)
        consultar(it.key());
}

void Mpris::elegir()
{
    QString elegido;
    // 1) el actual, si sigue sonando (no saltar entre dos que suenan a la vez)
    if (m_reproductores.value(m_actual).estado == QStringLiteral("Playing"))
        elegido = m_actual;
    // 2) cualquiera que suene; 3) el que sono mas recientemente y esta en pausa
    if (elegido.isEmpty()) {
        QDateTime mejor;
        for (auto it = m_reproductores.cbegin(); it != m_reproductores.cend(); ++it) {
            const Estado &e = it.value();
            if (e.titulo.isEmpty() && e.estado != QStringLiteral("Playing"))
                continue;
            if (e.estado == QStringLiteral("Playing")) {
                elegido = it.key();
                break;
            }
            if (e.estado == QStringLiteral("Paused") && (mejor.isNull() || e.ultimaVezSonando > mejor)) {
                mejor = e.ultimaVezSonando;
                elegido = it.key();
            }
        }
        // Una pausa de hace mas de 30 min ya no se ensena.
        if (!elegido.isEmpty() && m_reproductores.value(elegido).estado != QStringLiteral("Playing")) {
            const QDateTime t = m_reproductores.value(elegido).ultimaVezSonando;
            if (t.isNull() || t.secsTo(QDateTime::currentDateTimeUtc()) > 30 * 60)
                elegido.clear();
        }
    }
    m_actual = elegido;

    const Estado &e = estado();
    const QString cancion = e.titulo + QLatin1Char('\n') + e.artista;
    if (!m_actual.isEmpty() && reproduciendo() && cancion != m_cancionAnterior && !e.titulo.isEmpty()) {
        m_cancionAnterior = cancion;
        emit cambiado();
        emit cancionNueva();
        return;
    }
    emit cambiado();
}

const Mpris::Estado &Mpris::estado() const
{
    static const Estado vacio;
    auto it = m_reproductores.constFind(m_actual);
    return it == m_reproductores.cend() ? vacio : it.value();
}

bool Mpris::reproduciendo() const
{
    return estado().estado == QStringLiteral("Playing");
}

QString Mpris::reproductor() const
{
    const Estado &e = estado();
    if (!e.identidad.isEmpty())
        return e.identidad;
    QString n = m_actual.mid(kPrefijo.size()).section(QLatin1Char('.'), 0, 0);
    if (!n.isEmpty())
        n[0] = n.at(0).toUpper();
    return n;
}

void Mpris::llamar(const QString &metodo, const QString &interfaz)
{
    if (m_actual.isEmpty())
        return;
    QDBusMessage m = QDBusMessage::createMethodCall(m_actual, kRuta, interfaz.isEmpty() ? kPlayer : interfaz, metodo);
    QDBusConnection::sessionBus().asyncCall(m, 2000);
}

void Mpris::alternar() { llamar(QStringLiteral("PlayPause")); }
void Mpris::siguiente() { llamar(QStringLiteral("Next")); }
void Mpris::anterior() { llamar(QStringLiteral("Previous")); }
void Mpris::mostrarReproductor() { llamar(QStringLiteral("Raise"), kRaiz); }
