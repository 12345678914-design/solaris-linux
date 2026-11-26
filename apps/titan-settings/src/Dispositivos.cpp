#include "Dispositivos.h"
#include <QSize>
#include <QRegularExpression>

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

// Resoluciones habituales. Muchas pantallas de portátil anuncian solo la
// suya (nativa); otras llegan con datos (EDID) incompletos y el sistema
// arranca en una menor de la que admiten. Estas se ofrecen además de las
// anunciadas, como modo personalizado (wlr-randr --custom-mode): por debajo
// de la máxima la tarjeta gráfica escala la imagen; por encima, solo si se
// pide, y el aviso de 15 s deshace el cambio si la pantalla no lo acepta.
const QList<QSize> &resolucionesHabituales()
{
    static const QList<QSize> r = {
        {3840, 2160}, {2560, 1600}, {2560, 1440}, {1920, 1200}, {1920, 1080}, {1680, 1050},
        {1600, 900}, {1440, 900}, {1366, 768}, {1360, 768}, {1280, 1024}, {1280, 800},
        {1280, 720}, {1024, 768}, {1024, 600}, {800, 600},
    };
    return r;
}

QString idModo(int w, int h, double hz)
{
    return QStringLiteral("%1x%2@%3Hz").arg(w).arg(h).arg(QString::number(hz, 'f', 3));
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
            QSet<QString> tamanos;          // "1366x768" de los anunciados
            QStringList reales;             // ids que anuncia la pantalla
            int maxW = 0, maxH = 0;
            double hzBase = 60.0;
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
                reales << id;
                tamanos.insert(QStringLiteral("%1x%2").arg(w).arg(h));
                if (qint64(w) * h > qint64(maxW) * maxH) { maxW = w; maxH = h; }
                if (m.value(QStringLiteral("preferred")).toBool() && hz > 1) hzBase = hz;
                QVariantMap mm{{QStringLiteral("id"), id}, {QStringLiteral("ancho"), w}, {QStringLiteral("alto"), h},
                               {QStringLiteral("hz"), hz}, {QStringLiteral("texto"), textoModo(w, h, hz)},
                               {QStringLiteral("actual"), actual},
                               {QStringLiteral("preferido"), m.value(QStringLiteral("preferred")).toBool()}};
                if (actual)
                    p[QStringLiteral("modo")] = id;
                modos << mm;
            }
            // Modo en uso que no está en la lista (uno personalizado ya aplicado):
            // se toma de lo guardado
            const QString nombreSalida = p.value(QStringLiteral("nombre")).toString();
            if (!p.contains(QStringLiteral("modo")) && o.value(QStringLiteral("enabled")).toBool()) {
                const QString guardado = m_modoAplicado.value(nombreSalida, modoGuardado(nombreSalida));
                if (!guardado.isEmpty()) p[QStringLiteral("modo")] = guardado;
            }
            // Las habituales que no anuncia: menores que la máxima (seguras) y,
            // aparte, mayores (solo con «Mostrar más resoluciones»)
            const double hzPers = std::round(hzBase) >= 59 && std::round(hzBase) <= 61 ? 60.0 : std::round(hzBase);
            for (const QSize &r : resolucionesHabituales()) {
                if (tamanos.contains(QStringLiteral("%1x%2").arg(r.width()).arg(r.height())))
                    continue;
                const bool menor = maxW == 0 || (r.width() <= maxW && r.height() <= maxH);
                const QString id = idModo(r.width(), r.height(), hzPers);
                modos << QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("ancho"), r.width()},
                                     {QStringLiteral("alto"), r.height()}, {QStringLiteral("hz"), hzPers},
                                     {QStringLiteral("texto"), textoModo(r.width(), r.height(), hzPers)},
                                     {QStringLiteral("actual"), p.value(QStringLiteral("modo")).toString() == id},
                                     {QStringLiteral("preferido"), false},
                                     {QStringLiteral("personalizado"), true},
                                     {QStringLiteral("mayor"), !menor}};
            }
            // El personalizado en uso, si no es de la lista de habituales
            const QString enUso = p.value(QStringLiteral("modo")).toString();
            bool esta = false;
            for (const QVariant &mv : std::as_const(modos))
                esta = esta || mv.toMap().value(QStringLiteral("id")).toString() == enUso;
            static const QRegularExpression reModo(QStringLiteral("^(\\d+)x(\\d+)@([0-9.]+)Hz$"));
            const auto mt = reModo.match(enUso);
            if (!esta && mt.hasMatch()) {
                const int w = mt.captured(1).toInt(), h = mt.captured(2).toInt();
                const double hz = mt.captured(3).toDouble();
                modos << QVariantMap{{QStringLiteral("id"), enUso}, {QStringLiteral("ancho"), w}, {QStringLiteral("alto"), h},
                                     {QStringLiteral("hz"), hz}, {QStringLiteral("texto"), textoModo(w, h, hz)},
                                     {QStringLiteral("actual"), true}, {QStringLiteral("preferido"), false},
                                     {QStringLiteral("personalizado"), true},
                                     {QStringLiteral("mayor"), qint64(w) * h > qint64(maxW) * maxH}};
            }
            p[QStringLiteral("modosReales")] = reales;
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
    if (!modo.isEmpty()) {
        if (p.value(QStringLiteral("modosReales")).toStringList().contains(modo)) {
            a << QStringLiteral("--mode") << modo;
        } else {
            // No la anuncia la pantalla: modo personalizado (p. ej. 1280x720@60Hz)
            QString m = modo;
            m.replace(QStringLiteral(".000Hz"), QStringLiteral("Hz"));
            a << QStringLiteral("--custom-mode") << m;
        }
    }
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
        m_modoAplicado.insert(nombre, modo);
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
        m_modoAplicado.insert(v.toMap().value(QStringLiteral("nombre")).toString(), v.toMap().value(QStringLiteral("modo")).toString());
    for (const QVariant &v : antes)
        correr(QStringLiteral("wlr-randr"), argumentosDe(v.toMap()), [](int, const QByteArray &, const QString &) {});
    QTimer::singleShot(400, this, &Dispositivos::leerPantallas);
}

// El modo guardado para una pantalla en pantallas.conf ("1280x720@60.000Hz"),
// para saber cuál está en uso cuando es personalizado.
QString Dispositivos::modoGuardado(const QString &nombre) const
{
    QFile f(rutaTitan(QStringLiteral("pantallas.conf")));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();
    static const QRegularExpression re(QStringLiteral("^(\\d+)x(\\d+)(?:@([0-9.]+)Hz)?$"));
    while (!f.atEnd()) {
        const QStringList a = QString::fromUtf8(f.readLine()).simplified().split(QLatin1Char(' '));
        const int i = a.indexOf(QStringLiteral("--output"));
        if (i < 0 || a.value(i + 1) != nombre)
            continue;
        for (const QString &op : {QStringLiteral("--custom-mode"), QStringLiteral("--mode")}) {
            const int k = a.indexOf(op);
            const auto m = re.match(a.value(k + 1));
            if (k >= 0 && m.hasMatch())
                return idModo(m.captured(1).toInt(), m.captured(2).toInt(),
                              m.captured(3).isEmpty() ? 60.0 : m.captured(3).toDouble());
        }
    }
    return QString();
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

void Dispositivos::leerAppsSonido()
{
    correr(QStringLiteral("pactl"), {QStringLiteral("-f"), QStringLiteral("json"), QStringLiteral("list"), QStringLiteral("sink-inputs")},
           [this](int codigo, const QByteArray &salida, const QString &) {
        QVariantList r;
        if (codigo == 0) {
            for (const QJsonValue &v : QJsonDocument::fromJson(salida).array()) {
                const QJsonObject o = v.toObject();
                const QJsonObject pr = o.value(QStringLiteral("properties")).toObject();
                // Los sonidos de aviso del sistema no se listan
                if (pr.value(QStringLiteral("media.role")).toString() == QLatin1String("event"))
                    continue;
                QString nombre = pr.value(QStringLiteral("application.name")).toString();
                if (nombre.isEmpty()) nombre = pr.value(QStringLiteral("application.process.binary")).toString();
                if (nombre.isEmpty()) nombre = QStringLiteral("Aplicación");
                r << QVariantMap{
                    {QStringLiteral("id"), o.value(QStringLiteral("index")).toInt()},
                    {QStringLiteral("nombre"), nombre},
                    {QStringLiteral("detalle"), pr.value(QStringLiteral("media.name")).toString()},
                    {QStringLiteral("icono"), pr.value(QStringLiteral("application.icon_name")).toString()},
                    {QStringLiteral("volumen"), porcentaje(o.value(QStringLiteral("volume")).toObject())},
                    {QStringLiteral("silencio"), o.value(QStringLiteral("mute")).toBool()},
                };
            }
        }
        if (r != m_appsSonido) {
            m_appsSonido = r;
            emit appsSonidoCambiado();
        }
    });
}

void Dispositivos::setVolumenApp(int id, int porcentaje)
{
    if (id < 0) return;
    correr(QStringLiteral("pactl"), {QStringLiteral("set-sink-input-volume"), QString::number(id),
                                     QString::number(qBound(0, porcentaje, 150)) + QLatin1Char('%')},
           [](int, const QByteArray &, const QString &) {});
}

void Dispositivos::setSilencioApp(int id, bool silencio)
{
    if (id < 0) return;
    correr(QStringLiteral("pactl"), {QStringLiteral("set-sink-input-mute"), QString::number(id), silencio ? QStringLiteral("1") : QStringLiteral("0")},
           [this](int, const QByteArray &, const QString &) { leerAppsSonido(); });
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
