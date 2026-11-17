#include "TitanPrefs.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QHash>
#include <QSettings>
#include <QStandardPaths>
#include <QTime>
#include <QTimer>

namespace {

const QHash<QString, QVariant> &tabla()
{
    static const QHash<QString, QVariant> t = {
        {QStringLiteral("Dock/visible"), true},
        {QStringLiteral("Dock/posicion"), QStringLiteral("abajo")},
        {QStringLiteral("Dock/tamano"), 36},
        {QStringLiteral("Dock/ampliacion"), true},
        {QStringLiteral("Dock/ocultarAuto"), false},
        {QStringLiteral("Barra/visible"), true},
        {QStringLiteral("Barra/estilo"), QStringLiteral("transparente")},
        {QStringLiteral("Barra/reloj24h"), true},
        {QStringLiteral("Barra/segundos"), false},
        {QStringLiteral("Barra/fecha"), true},
        {QStringLiteral("Barra/diaSemana"), true},
        {QStringLiteral("Barra/bateriaPorcentaje"), true},
        {QStringLiteral("Barra/iconoWifi"), true},
        {QStringLiteral("Barra/iconoBluetooth"), true},
        {QStringLiteral("Barra/iconoFondo"), true},
        {QStringLiteral("Centro/conectividad"), true},
        {QStringLiteral("Centro/energia"), true},
        {QStringLiteral("Centro/brillo"), true},
        {QStringLiteral("Centro/sonido"), true},
        {QStringLiteral("Centro/noMolestar"), true},
        {QStringLiteral("Notificaciones/vistaPrevia"), true},
        {QStringLiteral("Notificaciones/sonido"), true},
        {QStringLiteral("Notificaciones/noMolestar"), false},
        {QStringLiteral("Concentracion/programado"), false},
        {QStringLiteral("Concentracion/desde"), QStringLiteral("22:00")},
        {QStringLiteral("Concentracion/hasta"), QStringLiteral("07:00")},
        {QStringLiteral("Escritorio/iconos"), true},
    };
    return t;
}

// QSettings devuelve "true"/"false" como texto: se convierte al tipo del
// valor por defecto para que QML reciba bool/int de verdad.
QVariant conTipo(const QVariant &valor, const QVariant &defecto)
{
    if (!defecto.isValid())
        return valor;
    switch (defecto.typeId()) {
    case QMetaType::Bool: {
        const QString t = valor.toString().toLower();
        if (valor.typeId() == QMetaType::Bool)
            return valor;
        return t == QStringLiteral("true") || t == QStringLiteral("1");
    }
    case QMetaType::Int:
        return valor.toInt();
    default:
        return valor.toString();
    }
}

} // namespace

TitanPrefs::TitanPrefs(QObject *parent)
    : QObject(parent)
    , m_vigia(new QFileSystemWatcher(this))
    , m_retraso(new QTimer(this))
{
    // QSettings guarda escribiendo un fichero nuevo y renombrandolo: se vigila
    // tambien la carpeta, y se agrupan los avisos (varios en pocos ms).
    m_retraso->setSingleShot(true);
    m_retraso->setInterval(80);
    connect(m_retraso, &QTimer::timeout, this, [this]() {
        const QVariantMap antes = m_valores;
        recargar();
        vigilar();
        if (antes != m_valores) {
            ++m_version;
            emit cambiado();
        }
    });
    connect(m_vigia, &QFileSystemWatcher::fileChanged, m_retraso, qOverload<>(&QTimer::start));
    connect(m_vigia, &QFileSystemWatcher::directoryChanged, m_retraso, qOverload<>(&QTimer::start));

    // El horario de Concentracion cambia con la hora, sin tocar el fichero.
    auto *minuto = new QTimer(this);
    minuto->setInterval(60 * 1000);
    connect(minuto, &QTimer::timeout, this, [this]() {
        if (b(QStringLiteral("Concentracion/programado"))) {
            ++m_version;
            emit cambiado();
        }
    });
    minuto->start();

    recargar();
    vigilar();
}

QString TitanPrefs::ruta()
{
    return QDir::homePath() + QStringLiteral("/.config/titan/shell.conf");
}

QVariant TitanPrefs::porDefecto(const QString &clave)
{
    return tabla().value(clave);
}

void TitanPrefs::recargar()
{
    m_valores.clear();
    QSettings s(ruta(), QSettings::IniFormat);
    for (const QString &k : s.allKeys())
        m_valores.insert(k, s.value(k));
    // Claves antiguas de Ajustes (antes de existir los grupos).
    if (!m_valores.contains(QStringLiteral("Dock/visible")) && m_valores.contains(QStringLiteral("Shell/dockEnabled")))
        m_valores.insert(QStringLiteral("Dock/visible"), m_valores.value(QStringLiteral("Shell/dockEnabled")));
    if (!m_valores.contains(QStringLiteral("Barra/visible")) && m_valores.contains(QStringLiteral("Shell/topBarEnabled")))
        m_valores.insert(QStringLiteral("Barra/visible"), m_valores.value(QStringLiteral("Shell/topBarEnabled")));
}

void TitanPrefs::vigilar()
{
    const QString dir = QFileInfo(ruta()).absolutePath();
    QDir().mkpath(dir);
    if (!m_vigia->directories().contains(dir))
        m_vigia->addPath(dir);
    if (QFile::exists(ruta()) && !m_vigia->files().contains(ruta()))
        m_vigia->addPath(ruta());
}

QVariant TitanPrefs::v(const QString &clave) const
{
    const QVariant d = porDefecto(clave);
    auto it = m_valores.constFind(clave);
    if (it == m_valores.constEnd())
        return d;
    return conTipo(it.value(), d);
}

void TitanPrefs::poner(const QString &clave, const QVariant &valor)
{
    if (clave.isEmpty())
        return;
    if (m_valores.contains(clave) && v(clave) == conTipo(valor, porDefecto(clave)))
        return;
    {
        QSettings s(ruta(), QSettings::IniFormat);
        s.setValue(clave, valor);
        s.sync();
    }
    m_valores.insert(clave, valor);
    ++m_version;
    emit cambiado();
}

void TitanPrefs::quitar(const QString &clave)
{
    {
        QSettings s(ruta(), QSettings::IniFormat);
        s.remove(clave);
        s.sync();
    }
    m_valores.remove(clave);
    ++m_version;
    emit cambiado();
}

QVariantMap TitanPrefs::grupo(const QString &prefijo) const
{
    QVariantMap r;
    const QString p = prefijo.endsWith(QLatin1Char('/')) ? prefijo : prefijo + QLatin1Char('/');
    for (auto it = m_valores.constBegin(); it != m_valores.constEnd(); ++it) {
        if (it.key().startsWith(p))
            r.insert(it.key().mid(p.size()), it.value());
    }
    return r;
}

bool TitanPrefs::noMolestarActivo() const
{
    if (b(QStringLiteral("Notificaciones/noMolestar")))
        return true;
    if (!b(QStringLiteral("Concentracion/programado")))
        return false;
    const QTime desde = QTime::fromString(s(QStringLiteral("Concentracion/desde")), QStringLiteral("HH:mm"));
    const QTime hasta = QTime::fromString(s(QStringLiteral("Concentracion/hasta")), QStringLiteral("HH:mm"));
    if (!desde.isValid() || !hasta.isValid() || desde == hasta)
        return false;
    const QTime ahora = QTime::currentTime();
    // 22:00 -> 07:00 cruza la medianoche.
    return desde < hasta ? (ahora >= desde && ahora < hasta) : (ahora >= desde || ahora < hasta);
}
