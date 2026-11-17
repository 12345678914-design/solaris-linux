#include "Dispositivos.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSet>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <cmath>

namespace {

QString rutaTitan(const QString &f)
{
    return QDir::homePath() + QStringLiteral("/.config/titan/") + f;
}

int porcentaje(const QJsonObject &volumen)
{
    // {"front-left":{"value_percent":"65%"}, ...}: la media de los canales.
    int suma = 0, n = 0;
    for (auto it = volumen.begin(); it != volumen.end(); ++it) {
        QString p = it.value().toObject().value(QStringLiteral("value_percent")).toString();
        p.chop(1);
        suma += p.toInt();
        ++n;
    }
    return n ? qRound(double(suma) / n) : 0;
}

QString textoModo(int w, int h, double hz)
{
    return QStringLiteral("%1 × %2 · %3 Hz").arg(w).arg(h).arg(QString::number(hz, 'f', hz == std::floor(hz) ? 0 : 2));
}

} // namespace

Dispositivos::Dispositivos(QObject *parent)
    : QObject(parent)
    , m_cuentaAtras(new QTimer(this))
    , m_volumenTimer(new QTimer(this))
{
    m_cuentaAtras->setSingleShot(true);
    m_cuentaAtras->setInterval(15000);
    connect(m_cuentaAtras, &QTimer::timeout, this, &Dispositivos::deshacerPantallas);

    // Al arrastrar el deslizador llegan muchos valores: se aplica el ultimo.
    m_volumenTimer->setSingleShot(true);
    m_volumenTimer->setInterval(60);
    connect(m_volumenTimer, &QTimer::timeout, this, [this]() {
        const QVariantMap p = m_volumenPendiente;
        const bool salida = p.value(QStringLiteral("salida")).toBool();
        correr(QStringLiteral("pactl"),
               {salida ? QStringLiteral("set-sink-volume") : QStringLiteral("set-source-volume"),
                p.value(QStringLiteral("nombre")).toString(),
                QString::number(p.value(QStringLiteral("valor")).toInt()) + QLatin1Char('%')},
               [this](int, const QByteArray &, const QString &) { leerSonido(); });
    });
    leerLuz();
}

void Dispositivos::correr(const QString &programa, const QStringList &args, Fin fin)
{
    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [p, fin](int codigo, QProcess::ExitStatus estado) {
        const QByteArray salida = p->readAllStandardOutput();
        const QString error = QString::fromLocal8Bit(p->readAllStandardError()).trimmed();
        p->deleteLater();
        fin(estado == QProcess::NormalExit ? codigo : -1, salida, error);
    });
    connect(p, &QProcess::errorOccurred, this, [p, fin](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            p->deleteLater();
            fin(-2, QByteArray(), QStringLiteral("no instalado"));
        }
    });
    QTimer::singleShot(20000, p, [p]() { p->kill(); });
    p->start(programa, args);
}

void Dispositivos::avisar(const QString &t)
{
    m_aviso = t;
    emit avisoCambiado();
}

// ------------------------------------------------------------------ pantallas

void Dispositivos::leerPantallas()
{
    correr(QStringLiteral("wlr-randr"), {QStringLiteral("--json")},
           [this](int codigo, const QByteArray &salida, const QString &) {
        QVariantList lista;
        const QJsonArray arr = QJsonDocument::fromJson(salida).array();
        for (const QJsonValue &v : arr) {
            const QJsonObject o = v.toObject();
            QVariantMap p;
            p[QStringLiteral("nombre")] = o.value(QStringLiteral("name")).toString();
            QString desc = (o.value(QStringLiteral("make")).toString() + QLatin1Char(' ')
                            + o.value(QStringLiteral("model")).toString()).trimmed();
            if (desc.isEmpty() || desc == QStringLiteral("Unknown Unknown"))
                desc = o.value(QStringLiteral("description")).toString();
            p[QStringLiteral("descripcion")] = desc;
            p[QStringLiteral("activa")] = o.value(QStringLiteral("enabled")).toBool();
            p[QStringLiteral("escala")] = o.value(QStringLiteral("scale")).toDouble(1.0);
            p[QStringLiteral("giro")] = o.value(QStringLiteral("transform")).toString(QStringLiteral("normal"));
            const QJsonObject pos = o.value(QStringLiteral("position")).toObject();
            p[QStringLiteral("x")] = pos.value(QStringLiteral("x")).toInt();
            p[QStringLiteral("y")] = pos.value(QStringLiteral("y")).toInt();
            const QJsonObject fis = o.value(QStringLiteral("physical_size")).toObject();
            const double mmW = fis.value(QStringLiteral("width")).toDouble();
            const double mmH = fis.value(QStringLiteral("height")).toDouble();
            if (mmW > 0 && mmH > 0)
                p[QStringLiteral("pulgadas")] = qRound(std::sqrt(mmW * mmW + mmH * mmH) / 25.4);

            QVariantList modos;
            QSet<QString> vistos;
            for (const QJsonValue &mv : o.value(QStringLiteral("modes")).toArray()) {
                const QJsonObject m = mv.toObject();
                const int w = m.value(QStringLiteral("width")).toInt();
                const int h = m.value(QStringLiteral("height")).toInt();
                const double hz = m.value(QStringLiteral("refresh")).toDouble();
                const QString id = QStringLiteral("%1x%2@%3Hz").arg(w).arg(h).arg(QString::number(hz, 'f', 3));
                if (vistos.contains(id))
                    continue;
                vistos.insert(id);
                const bool actual = m.value(QStringLiteral("current")).toBool();
                QVariantMap mm{{QStringLiteral("id"), id}, {QStringLiteral("ancho"), w}, {QStringLiteral("alto"), h},
                               {QStringLiteral("hz"), hz}, {QStringLiteral("texto"), textoModo(w, h, hz)},
                               {QStringLiteral("actual"), actual},
                               {QStringLiteral("preferido"), m.value(QStringLiteral("preferred")).toBool()}};
                if (actual)
                    p[QStringLiteral("modo")] = id;
                modos << mm;
            }
            // De mayor a menor resolucion y frecuencia.
            std::sort(modos.begin(), modos.end(), [](const QVariant &a, const QVariant &b) {
                const QVariantMap x = a.toMap(), y = b.toMap();
                const qint64 ax = qint64(x[QStringLiteral("ancho")].toInt()) * x[QStringLiteral("alto")].toInt();
                const qint64 bx = qint64(y[QStringLiteral("ancho")].toInt()) * y[QStringLiteral("alto")].toInt();
                if (ax != bx)
                    return ax > bx;
                return x[QStringLiteral("hz")].toDouble() > y[QStringLiteral("hz")].toDouble();
            });
            p[QStringLiteral("modos")] = modos;
            lista << p;
        }
        m_pantallas = lista;
        m_pantallasOk = codigo == 0 && !lista.isEmpty();
        emit pantallasCambiadas();
    });
}

QStringList Dispositivos::argumentosDe(const QVariantMap &p) const
{
    QStringList a{QStringLiteral("--output"), p.value(QStringLiteral("nombre")).toString()};
    if (!p.value(QStringLiteral("activa")).toBool())
        return a << QStringLiteral("--off");
    a << QStringLiteral("--on");
    const QString modo = p.value(QStringLiteral("modo")).toString();
    if (!modo.isEmpty())
        a << QStringLiteral("--mode") << modo;
    a << QStringLiteral("--scale") << QString::number(p.value(QStringLiteral("escala")).toDouble(), 'f', 2);
    a << QStringLiteral("--transform") << p.value(QStringLiteral("giro")).toString();
    a << QStringLiteral("--pos") << QStringLiteral("%1,%2").arg(p.value(QStringLiteral("x")).toInt()).arg(p.value(QStringLiteral("y")).toInt());
    return a;
}

void Dispositivos::aplicarPantalla(const QString &nombre, const QString &modo, double escala,
                                   const QString &giro, bool activa)
{
    // No se deja apagar la unica pantalla encendida.
    int encendidas = 0;
    for (const QVariant &v : std::as_const(m_pantallas))
        encendidas += v.toMap().value(QStringLiteral("activa")).toBool() ? 1 : 0;

    QVariantList nuevas = m_pantallas;
    for (int i = 0; i < nuevas.size(); ++i) {
        QVariantMap p = nuevas[i].toMap();
        if (p.value(QStringLiteral("nombre")).toString() != nombre)
            continue;
        if (!activa && p.value(QStringLiteral("activa")).toBool() && encendidas <= 1) {
            avisar(QStringLiteral("No se puede apagar la única pantalla encendida"));
            return;
        }
        p[QStringLiteral("modo")] = modo;
        p[QStringLiteral("escala")] = qBound(0.5, escala, 4.0);
        p[QStringLiteral("giro")] = giro;
        p[QStringLiteral("activa")] = activa;
        nuevas[i] = p;
        if (m_anterior.isEmpty())
            m_anterior = m_pantallas;
        correr(QStringLiteral("wlr-randr"), argumentosDe(p),
               [this](int codigo, const QByteArray &, const QString &error) {
            if (codigo != 0) {
                avisar(QStringLiteral("No se pudo cambiar la pantalla: ") + error);
                m_anterior.clear();
                m_cuentaAtras->stop();
                emit pendienteCambiado();
            }
            leerPantallas();
        });
        m_cuentaAtras->start();
        emit pendienteCambiado();
        return;
    }
}

void Dispositivos::confirmarPantallas()
{
    m_cuentaAtras->stop();
    m_anterior.clear();
    emit pendienteCambiado();
    guardarPantallas();
}

void Dispositivos::deshacerPantallas()
{
    m_cuentaAtras->stop();
    const QVariantList antes = m_anterior;
    m_anterior.clear();
    emit pendienteCambiado();
    for (const QVariant &v : antes)
        correr(QStringLiteral("wlr-randr"), argumentosDe(v.toMap()), [](int, const QByteArray &, const QString &) {});
    QTimer::singleShot(400, this, &Dispositivos::leerPantallas);
}

void Dispositivos::guardarPantallas()
{
    // titan-pantallas (al entrar en la sesion) vuelve a aplicar esto.
    QDir().mkpath(rutaTitan(QString()));
    QFile f(rutaTitan(QStringLiteral("pantallas.conf")));
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        return;
    f.write("# Inti OS: pantallas (lo escribe Ajustes; lo aplica titan-pantallas al entrar)\n");
    for (const QVariant &v : std::as_const(m_pantallas))
        f.write(argumentosDe(v.toMap()).join(QLatin1Char(' ')).toUtf8() + '\n');
}

void Dispositivos::identificar()
{
    // Una notificacion por pantalla con su nombre.
    for (const QVariant &v : std::as_const(m_pantallas)) {
        const QVariantMap p = v.toMap();
        QProcess::startDetached(QStringLiteral("notify-send"),
                                {QStringLiteral("-a"), QStringLiteral("Ajustes"), QStringLiteral("-i"), QStringLiteral("video-display"),
                                 p.value(QStringLiteral("nombre")).toString(), p.value(QStringLiteral("descripcion")).toString()});
    }
}

void Dispositivos::leerBrillo()
{
    correr(QStringLiteral("brightnessctl"), {QStringLiteral("-m"), QStringLiteral("-c"), QStringLiteral("backlight"), QStringLiteral("info")},
           [this](int codigo, const QByteArray &salida, const QString &) {
        // intel_backlight,backlight,500,52%,960
        int b = -1;
        if (codigo == 0) {
            const QStringList c = QString::fromUtf8(salida).trimmed().split(QLatin1Char(','));
            if (c.size() >= 4) {
                QString pc = c[3];
                pc.remove(QLatin1Char('%'));
                b = pc.toInt();
            }
        }
        if (b != m_brillo) {
            m_brillo = b;
            emit brilloCambiado();
        }
    });
}

void Dispositivos::setBrillo(int porcentaje)
{
    porcentaje = qBound(5, porcentaje, 100);
    m_brillo = porcentaje;
    emit brilloCambiado();
    correr(QStringLiteral("brightnessctl"), {QStringLiteral("-c"), QStringLiteral("backlight"), QStringLiteral("set"),
                                            QString::number(porcentaje) + QLatin1Char('%')},
           [](int, const QByteArray &, const QString &) {});
}

// ------------------------------------------------------------------ luz nocturna

void Dispositivos::leerLuz()
{
    QSettings s(rutaTitan(QStringLiteral("luz-nocturna.conf")), QSettings::IniFormat);
    m_luz = {
        {QStringLiteral("activa"), s.value(QStringLiteral("activa"), false).toBool()},
        {QStringLiteral("temperatura"), s.value(QStringLiteral("temperatura"), 4000).toInt()},
        {QStringLiteral("desde"), s.value(QStringLiteral("desde"), QStringLiteral("20:00")).toString()},
        {QStringLiteral("hasta"), s.value(QStringLiteral("hasta"), QStringLiteral("07:00")).toString()},
        {QStringLiteral("instalada"), !QStandardPaths::findExecutable(QStringLiteral("wlsunset")).isEmpty()},
    };
    emit luzCambiada();
}

void Dispositivos::setLuzNocturna(const QString &clave, const QVariant &valor)
{
    static const QStringList validas{QStringLiteral("activa"), QStringLiteral("temperatura"),
                                     QStringLiteral("desde"), QStringLiteral("hasta")};
    if (!validas.contains(clave))
        return;
    {
        QDir().mkpath(rutaTitan(QString()));
        QSettings s(rutaTitan(QStringLiteral("luz-nocturna.conf")), QSettings::IniFormat);
        s.setValue(clave, valor);
        s.sync();
    }
    leerLuz();
    // titan-luz-nocturna mata el wlsunset anterior y arranca uno nuevo (o ninguno).
    QProcess::startDetached(QStringLiteral("/usr/local/bin/titan-luz-nocturna"), {});
}

// ------------------------------------------------------------------ sonido

void Dispositivos::leerSonido()
{
    correr(QStringLiteral("pactl"), {QStringLiteral("get-default-sink")},
           [this](int, const QByteArray &defSink, const QString &) {
        correr(QStringLiteral("pactl"), {QStringLiteral("get-default-source")},
               [this, defSink](int, const QByteArray &defSource, const QString &) {
            const QString sinkPred = QString::fromUtf8(defSink).trimmed();
            const QString sourcePred = QString::fromUtf8(defSource).trimmed();
            correr(QStringLiteral("pactl"), {QStringLiteral("-f"), QStringLiteral("json"), QStringLiteral("list"), QStringLiteral("sinks")},
                   [this, sinkPred, sourcePred](int c1, const QByteArray &sinks, const QString &) {
                correr(QStringLiteral("pactl"), {QStringLiteral("-f"), QStringLiteral("json"), QStringLiteral("list"), QStringLiteral("sources")},
                       [this, sinkPred, sourcePred, c1, sinks](int c2, const QByteArray &sources, const QString &) {
                    auto convertir = [](const QByteArray &json, const QString &pred, bool fuentes) {
                        QVariantList r;
                        for (const QJsonValue &v : QJsonDocument::fromJson(json).array()) {
                            const QJsonObject o = v.toObject();
                            const QString nombre = o.value(QStringLiteral("name")).toString();
                            // Los "monitor" de las salidas no son microfonos.
                            const QString de = o.value(QStringLiteral("monitor_of_sink")).toString();
                            if (fuentes && (nombre.endsWith(QStringLiteral(".monitor"))
                                            || (!de.isEmpty() && de != QStringLiteral("n/a"))))
                                continue;
                            r << QVariantMap{
                                {QStringLiteral("nombre"), nombre},
                                {QStringLiteral("descripcion"), o.value(QStringLiteral("description")).toString()},
                                {QStringLiteral("volumen"), porcentaje(o.value(QStringLiteral("volume")).toObject())},
                                {QStringLiteral("silencio"), o.value(QStringLiteral("mute")).toBool()},
                                {QStringLiteral("predeterminado"), nombre == pred},
                            };
                        }
                        return r;
                    };
                    m_salidas = convertir(sinks, sinkPred, false);
                    m_entradas = convertir(sources, sourcePred, true);
                    m_sonidoOk = c1 == 0 || c2 == 0;
                    emit sonidoCambiado();
                });
            });
        });
    });
}

void Dispositivos::setPredeterminado(bool salida, const QString &nombre)
{
    correr(QStringLiteral("pactl"), {salida ? QStringLiteral("set-default-sink") : QStringLiteral("set-default-source"), nombre},
           [this](int, const QByteArray &, const QString &) { leerSonido(); });
}

void Dispositivos::setVolumen(bool salida, const QString &nombre, int porcentaje)
{
    porcentaje = qBound(0, porcentaje, 150);
    m_volumenPendiente = {{QStringLiteral("salida"), salida}, {QStringLiteral("nombre"), nombre},
                          {QStringLiteral("valor"), porcentaje}};
    m_volumenTimer->start();
}

void Dispositivos::setSilencio(bool salida, const QString &nombre, bool silencio)
{
    correr(QStringLiteral("pactl"), {salida ? QStringLiteral("set-sink-mute") : QStringLiteral("set-source-mute"),
                                     nombre, silencio ? QStringLiteral("1") : QStringLiteral("0")},
           [this](int, const QByteArray &, const QString &) { leerSonido(); });
}

void Dispositivos::probarSonido()
{
    static const QStringList candidatos{
        QStringLiteral("/usr/share/sounds/freedesktop/stereo/audio-volume-change.oga"),
        QStringLiteral("/usr/share/sounds/freedesktop/stereo/bell.oga"),
        QStringLiteral("/usr/share/sounds/freedesktop/stereo/message.oga"),
    };
    for (const QString &c : candidatos) {
        if (QFile::exists(c)) {
            QProcess::startDetached(QStringLiteral("pw-play"), {c});
            return;
        }
    }
    avisar(QStringLiteral("No hay sonidos de prueba instalados (sound-theme-freedesktop)"));
}
