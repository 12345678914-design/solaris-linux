#include "MonitorBackend.h"
#include "TitanDesktopEntry.h"
#include "TitanIconoApp.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QLocale>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QTextStream>

#include <algorithm>
#include <csignal>
#include <sys/types.h>
#include <unistd.h>

namespace {

QByteArray leer(const QString &ruta)
{
    QFile f(ruta);
    if (!f.open(QIODevice::ReadOnly))
        return QByteArray();
    return f.readAll();
}

QString sinAcentos(const QString &t)
{
    QString r;
    for (const QChar c : t.toLower().normalized(QString::NormalizationForm_D))
        if (c.category() != QChar::Mark_NonSpacing)
            r.append(c);
    return r;
}

void anadir(QVariantList &hist, double v, int max)
{
    hist.append(v);
    while (hist.size() > max)
        hist.removeFirst();
}

// Procesos sin los que el escritorio deja de funcionar: no se finalizan desde aquí
const QSet<QString> &criticos()
{
    static const QSet<QString> c = {
        QStringLiteral("titan-shell"), QStringLiteral("titan-desktop"), QStringLiteral("titan-panel"),
        QStringLiteral("titan-sesion"), QStringLiteral("wayfire"), QStringLiteral("labwc"),
        QStringLiteral("systemd"), QStringLiteral("dbus-daemon"), QStringLiteral("dbus-broker"),
        QStringLiteral("pipewire"), QStringLiteral("wireplumber"), QStringLiteral("pipewire-pulse"),
        QStringLiteral("Xwayland"), QStringLiteral("xdg-desktop-portal"), QStringLiteral("titan-monitor"),
        QStringLiteral("gtklock"), QStringLiteral("greetd"), QStringLiteral("titan-greeter"),
    };
    return c;
}

// Intérpretes: el nombre bueno es el del script (argv[1])
bool esInterprete(const QString &p)
{
    static const QRegularExpression re(QStringLiteral("^(python[0-9.]*|perl|sh|bash|dash|node|ruby|java|lua[0-9.]*)$"));
    return re.match(p).hasMatch();
}

} // namespace

MonitorBackend::MonitorBackend(QObject *parent)
    : QObject(parent)
{
    m_uid = getuid();
    m_hz = sysconf(_SC_CLK_TCK) > 0 ? sysconf(_SC_CLK_TCK) : 100;
    m_pagina4k = sysconf(_SC_PAGESIZE) > 0 ? sysconf(_SC_PAGESIZE) : 4096;

    QSettings ajustes(QStringLiteral("titan"), QStringLiteral("monitor"));
    m_intervalo = ajustes.value(QStringLiteral("intervalo"), 1000).toInt();
    if (m_intervalo != 0 && m_intervalo != 500 && m_intervalo != 1000 && m_intervalo != 2000 && m_intervalo != 5000)
        m_intervalo = 1000;
    m_todos = ajustes.value(QStringLiteral("todos"), false).toBool();

    // Modelo de la CPU (no cambia)
    const QString info = QString::fromUtf8(leer(QStringLiteral("/proc/cpuinfo")));
    for (const QString &l : info.split(QLatin1Char('\n'))) {
        if (l.startsWith(QLatin1String("model name"))) {
            m_modeloCpu = l.section(QLatin1Char(':'), 1).trimmed().simplified();
            break;
        }
    }

    connect(&m_timer, &QTimer::timeout, this, &MonitorBackend::muestrear);
    cargarInicio();
    muestrear();
    reprogramar();
}

// ---------------------------------------------------------------- ajustes

void MonitorBackend::reprogramar()
{
    if (m_activo && m_intervalo > 0)
        m_timer.start(m_intervalo);
    else
        m_timer.stop();
}

void MonitorBackend::setIntervalo(int ms)
{
    if (ms == m_intervalo)
        return;
    m_intervalo = ms;
    QSettings(QStringLiteral("titan"), QStringLiteral("monitor")).setValue(QStringLiteral("intervalo"), ms);
    reprogramar();
    emit intervaloChanged();
}

void MonitorBackend::setPagina(const QString &p)
{
    if (p == m_pagina)
        return;
    m_pagina = p;
    emit paginaChanged();
    if (p == QLatin1String("inicio"))
        cargarInicio();
    muestrear(); // la página nueva, al momento
}

void MonitorBackend::setActivo(bool a)
{
    if (a == m_activo)
        return;
    m_activo = a;
    reprogramar();
    emit activoChanged();
}

void MonitorBackend::setTodosLosUsuarios(bool t)
{
    if (t == m_todos)
        return;
    m_todos = t;
    QSettings(QStringLiteral("titan"), QStringLiteral("monitor")).setValue(QStringLiteral("todos"), t);
    m_procAnt.clear();
    muestrear();
}

void MonitorBackend::setOrden(const QString &o)
{
    if (o == m_orden)
        return;
    m_orden = o;
    m_desc = (o != QLatin1String("nombre")); // el nombre, de la A a la Z; lo demás, de más a menos
    ordenarProcesos();
}

void MonitorBackend::setOrdenDescendente(bool d)
{
    if (d == m_desc)
        return;
    m_desc = d;
    ordenarProcesos();
}

void MonitorBackend::setFiltro(const QString &f)
{
    if (f == m_filtro)
        return;
    m_filtro = f;
    ordenarProcesos();
}

void MonitorBackend::ponerAviso(const QString &t)
{
    m_aviso = t;
    emit avisoChanged();
}

void MonitorBackend::cerrarAviso()
{
    ponerAviso(QString());
}

QString MonitorBackend::bytes(double b) const
{
    return QLocale(QLocale::Spanish).formattedDataSize(qint64(b), b < 1024.0 * 1024 * 1024 ? 0 : 1, QLocale::DataSizeTraditionalFormat);
}

QString MonitorBackend::mbs(double bps) const
{
    return QLocale(QLocale::Spanish).toString(bps / (1024.0 * 1024.0), 'f', 1) + QStringLiteral(" MB/s");
}

// Red y disco: siempre en kB/s o MB/s ("0,4 kB/s", "350 kB/s", "2,5 MB/s"),
// nunca "374 bytes/s", que es largo y no cabe en las tarjetas.
QString MonitorBackend::velocidad(double bps) const
{
    const QLocale es(QLocale::Spanish);
    const double kb = qMax(0.0, bps) / 1024.0;
    if (kb < 1024.0)
        return es.toString(kb, 'f', kb < 10.0 ? 1 : 0) + QStringLiteral(" kB/s");
    const double mb = kb / 1024.0;
    return es.toString(mb, 'f', mb < 100.0 ? 1 : 0) + QStringLiteral(" MB/s");
}

// ---------------------------------------------------------------- muestras

void MonitorBackend::muestrear()
{
    const qint64 ahora = QDateTime::currentMSecsSinceEpoch();
    const double segundos = m_ultimo > 0 ? qMax(0.05, (ahora - m_ultimo) / 1000.0) : 1.0;
    m_ultimo = ahora;

    leerCpu();
    leerMemoria();
    leerDiscos(segundos);
    leerRedes(segundos);
    if (m_pagina == QLatin1String("procesos"))
        leerProcesos(segundos);
    emit muestra();
}

void MonitorBackend::leerCpu()
{
    const QList<QByteArray> lineas = leer(QStringLiteral("/proc/stat")).split('\n');
    QVector<quint64> total, ocupado;
    for (const QByteArray &l : lineas) {
        if (!l.startsWith("cpu"))
            break;
        const QList<QByteArray> c = l.simplified().split(' ');
        if (c.size() < 8)
            continue;
        quint64 t = 0;
        for (int i = 1; i <= qMin(8, int(c.size()) - 1); ++i) // user..steal (guest ya va en user)
            t += c[i].toULongLong();
        const quint64 inactivo = c[4].toULongLong() + c[5].toULongLong();
        total << t;
        ocupado << (t - inactivo);
    }
    if (total.isEmpty())
        return;

    const int nucleos = total.size() - 1;
    if (m_histNucleos.size() != nucleos)
        m_histNucleos = QList<QVariantList>(nucleos);
    QVariantList porNucleo;
    double uso = 0;
    for (int i = 0; i < total.size(); ++i) {
        double u = 0;
        if (i < m_cpuTotalAnt.size() && total[i] > m_cpuTotalAnt[i])
            u = 100.0 * double(ocupado[i] - m_cpuOcupadoAnt[i]) / double(total[i] - m_cpuTotalAnt[i]);
        u = qBound(0.0, u, 100.0);
        if (i == 0) {
            uso = u;
        } else {
            anadir(m_histNucleos[i - 1], u, kHistorial);
            porNucleo << QVariantMap{{QStringLiteral("uso"), u}, {QStringLiteral("hist"), m_histNucleos[i - 1]}};
        }
    }
    m_ticksTotalAnt = m_cpuTotalAnt.isEmpty() ? 0 : m_cpuTotalAnt[0];
    m_cpuTotalAnt = total;
    m_cpuOcupadoAnt = ocupado;
    anadir(m_histCpu, uso, kHistorial);

    // Velocidad media actual
    double khz = 0;
    int n = 0;
    for (int i = 0; i < nucleos; ++i) {
        const QByteArray f = leer(QStringLiteral("/sys/devices/system/cpu/cpu%1/cpufreq/scaling_cur_freq").arg(i)).trimmed();
        if (!f.isEmpty()) { khz += f.toDouble(); ++n; }
    }
    const QList<QByteArray> carga = leer(QStringLiteral("/proc/loadavg")).split(' ');
    const double arriba = leer(QStringLiteral("/proc/uptime")).split(' ').value(0).toDouble();
    const qint64 s = qint64(arriba);
    const QString tiempo = s >= 86400 ? QStringLiteral("%1 d %2 h").arg(s / 86400).arg((s % 86400) / 3600)
                                      : QStringLiteral("%1:%2:%3").arg(s / 3600).arg((s % 3600) / 60, 2, 10, QLatin1Char('0')).arg(s % 60, 2, 10, QLatin1Char('0'));
    int procesos = 0;
    for (const QString &d : QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot))
        if (d.at(0).isDigit()) ++procesos;

    m_cpu = {
        {QStringLiteral("uso"), uso},
        {QStringLiteral("hist"), m_histCpu},
        {QStringLiteral("nucleos"), porNucleo},
        {QStringLiteral("modelo"), m_modeloCpu.isEmpty() ? QStringLiteral("Procesador") : m_modeloCpu},
        {QStringLiteral("cantidad"), nucleos},
        {QStringLiteral("ghz"), n > 0 ? QLocale(QLocale::Spanish).toString(khz / n / 1e6, 'f', 2) + QStringLiteral(" GHz") : QString()},
        {QStringLiteral("activo"), tiempo},
        {QStringLiteral("procesos"), procesos},
        {QStringLiteral("hilos"), QString::fromLatin1(carga.value(3)).section(QLatin1Char('/'), 1, 1).toInt()},
    };
}

void MonitorBackend::leerMemoria()
{
    QHash<QByteArray, double> m;
    for (const QByteArray &l : leer(QStringLiteral("/proc/meminfo")).split('\n')) {
        const int dp = l.indexOf(':');
        if (dp > 0)
            m.insert(l.left(dp), l.mid(dp + 1).simplified().split(' ').value(0).toDouble() * 1024.0);
    }
    const double total = m.value("MemTotal");
    const double disponible = m.value("MemAvailable");
    const double usada = total - disponible;
    const double cache = m.value("Cached") + m.value("SReclaimable") - m.value("Shmem");
    const double swapT = m.value("SwapTotal"), swapL = m.value("SwapFree");
    const double pct = total > 0 ? 100.0 * usada / total : 0;
    anadir(m_histMem, pct, kHistorial);
    m_memoria = {
        {QStringLiteral("uso"), pct},
        {QStringLiteral("hist"), m_histMem},
        {QStringLiteral("total"), total},
        {QStringLiteral("usada"), usada},
        {QStringLiteral("disponible"), disponible},
        {QStringLiteral("cache"), qMax(0.0, cache)},
        {QStringLiteral("swapTotal"), swapT},
        {QStringLiteral("swapUsada"), swapT - swapL},
    };
}

void MonitorBackend::leerDiscos(double segundos)
{
    static const QRegularExpression fisico(QStringLiteral("^(sd[a-z]+|nvme\\d+n\\d+|vd[a-z]+|mmcblk\\d+|hd[a-z]+|xvd[a-z]+)$"));
    QSet<QString> vistos;
    QVariantList vista;
    int numero = 0;
    for (const QByteArray &l : leer(QStringLiteral("/proc/diskstats")).split('\n')) {
        const QList<QByteArray> c = l.simplified().split(' ');
        if (c.size() < 14)
            continue;
        const QString nombre = QString::fromLatin1(c[2]);
        if (!fisico.match(nombre).hasMatch())
            continue;
        const double tamano = leer(QStringLiteral("/sys/block/%1/size").arg(nombre)).trimmed().toDouble() * 512.0;
        if (tamano <= 0)
            continue;
        vistos.insert(nombre);
        const quint64 leido = c[5].toULongLong() * 512, escrito = c[9].toULongLong() * 512, ms = c[12].toULongLong();
        const bool nuevo = !m_discos.contains(nombre);
        Disco &d = m_discos[nombre];
        double vL = 0, vE = 0, act = 0;
        if (!nuevo) {
            vL = (leido - d.leido) / segundos;
            vE = (escrito - d.escrito) / segundos;
            act = qBound(0.0, 100.0 * (ms - d.msOcupado) / (segundos * 1000.0), 100.0);
        } else {
            d.modelo = QString::fromUtf8(leer(QStringLiteral("/sys/block/%1/device/model").arg(nombre))).trimmed();
            d.tamano = tamano;
        }
        d.leido = leido; d.escrito = escrito; d.msOcupado = ms;
        anadir(d.hist, act, kHistorial);
        anadir(d.histL, vL, kHistorial);
        anadir(d.histE, vE, kHistorial);
        const bool ssd = leer(QStringLiteral("/sys/block/%1/queue/rotational").arg(nombre)).trimmed() == "0";
        const bool extraible = leer(QStringLiteral("/sys/block/%1/removable").arg(nombre)).trimmed() == "1";
        vista << QVariantMap{
            {QStringLiteral("id"), nombre},
            {QStringLiteral("titulo"), QStringLiteral("Disco %1 (%2)").arg(numero++).arg(nombre)},
            {QStringLiteral("tipo"), extraible ? QStringLiteral("Extraíble") : nombre.startsWith(QLatin1String("nvme")) ? QStringLiteral("SSD NVMe") : ssd ? QStringLiteral("SSD") : QStringLiteral("Disco duro")},
            {QStringLiteral("modelo"), d.modelo},
            {QStringLiteral("tamano"), d.tamano},
            {QStringLiteral("uso"), act},
            {QStringLiteral("lectura"), vL},
            {QStringLiteral("escritura"), vE},
            {QStringLiteral("hist"), d.hist},
            {QStringLiteral("histL"), d.histL},
            {QStringLiteral("histE"), d.histE},
        };
    }
    for (auto it = m_discos.begin(); it != m_discos.end();)
        it = vistos.contains(it.key()) ? std::next(it) : m_discos.erase(it);
    m_discosVista = vista;
}

void MonitorBackend::leerRedes(double segundos)
{
    QSet<QString> vistas;
    QVariantList vista;
    const QList<QByteArray> lineas = leer(QStringLiteral("/proc/net/dev")).split('\n');
    for (int i = 2; i < lineas.size(); ++i) {
        const int dp = lineas[i].indexOf(':');
        if (dp < 0)
            continue;
        const QString nombre = QString::fromLatin1(lineas[i].left(dp).trimmed());
        // Solo tarjetas de verdad (Wi-Fi, cable, USB): ni lo, ni puentes ni VPN
        if (!QFileInfo::exists(QStringLiteral("/sys/class/net/%1/device").arg(nombre)))
            continue;
        const QList<QByteArray> c = lineas[i].mid(dp + 1).simplified().split(' ');
        if (c.size() < 9)
            continue;
        vistas.insert(nombre);
        const quint64 rx = c[0].toULongLong(), tx = c[8].toULongLong();
        const bool nueva = !m_redes.contains(nombre);
        Red &r = m_redes[nombre];
        double vRx = 0, vTx = 0;
        if (!nueva) {
            vRx = (rx - r.rx) / segundos;
            vTx = (tx - r.tx) / segundos;
        } else {
            r.wifi = QFileInfo::exists(QStringLiteral("/sys/class/net/%1/wireless").arg(nombre));
        }
        r.rx = rx; r.tx = tx;
        anadir(r.histRx, vRx, kHistorial);
        anadir(r.histTx, vTx, kHistorial);
        const bool conectada = leer(QStringLiteral("/sys/class/net/%1/operstate").arg(nombre)).trimmed() == "up";
        vista << QVariantMap{
            {QStringLiteral("id"), nombre},
            {QStringLiteral("titulo"), r.wifi ? QStringLiteral("Wi-Fi") : QStringLiteral("Ethernet")},
            {QStringLiteral("conectada"), conectada},
            {QStringLiteral("bajada"), vRx},
            {QStringLiteral("subida"), vTx},
            {QStringLiteral("totalBajada"), double(rx)},
            {QStringLiteral("totalSubida"), double(tx)},
            {QStringLiteral("histRx"), r.histRx},
            {QStringLiteral("histTx"), r.histTx},
        };
    }
    for (auto it = m_redes.begin(); it != m_redes.end();)
        it = vistas.contains(it.key()) ? std::next(it) : m_redes.erase(it);
    m_redesVista = vista;
}

// ---------------------------------------------------------------- procesos

void MonitorBackend::cargarApps()
{
    m_apps.clear();
    for (const QString &dir : titan::dirsAplicaciones()) {
        const auto ficheros = QDir(dir).entryInfoList({QStringLiteral("*.desktop")}, QDir::Files);
        for (const QFileInfo &f : ficheros) {
            const auto e = titan::leerDesktop(f.absoluteFilePath());
            // Solo apps que se ven en el menú (los servicios ocultos van en segundo plano)
            if (e.value(QStringLiteral("Type")) != QLatin1String("Application") || titan::esVerdadero(e.value(QStringLiteral("Hidden")))
                || titan::esVerdadero(e.value(QStringLiteral("NoDisplay"))))
                continue;
            QString nombre = e.value(QStringLiteral("Name[es]"));
            if (nombre.isEmpty()) nombre = e.value(QStringLiteral("Name"));
            const QString exec = e.value(QStringLiteral("Exec"));
            const App app{nombre, titan::iconoApp(e.value(QStringLiteral("Icon")), exec)};
            QStringList partes = QProcess::splitCommand(exec);
            // "env VAR=x programa", "sh -c ...": el programa de verdad
            while (!partes.isEmpty() && (partes.first() == QLatin1String("env") || partes.first().contains(QLatin1Char('='))))
                partes.removeFirst();
            QStringList claves;
            if (!partes.isEmpty())
                claves << QFileInfo(partes.first()).fileName();
            const QString tryExec = e.value(QStringLiteral("TryExec"));
            if (!tryExec.isEmpty())
                claves << QFileInfo(tryExec).fileName();
            const QString clase = e.value(QStringLiteral("StartupWMClass")).toLower();
            if (!clase.isEmpty())
                claves << clase;
            for (const QString &k : std::as_const(claves)) {
                // Lo primero que se encuentra gana (el usuario y Flatpak van antes que el sistema)
                if (!k.isEmpty() && !m_apps.contains(k) && !esInterprete(k))
                    m_apps.insert(k, app);
            }
        }
    }
    // Programas que no se llaman como su lanzador
    if (m_apps.contains(QStringLiteral("libreoffice"))) {
        m_apps.insert(QStringLiteral("soffice.bin"), m_apps.value(QStringLiteral("libreoffice")));
        m_apps.insert(QStringLiteral("oosplash"), m_apps.value(QStringLiteral("libreoffice")));
    }
    m_appsLeidas = QDateTime::currentMSecsSinceEpoch();
}

void MonitorBackend::leerProcesos(double segundos)
{
    if (m_apps.isEmpty() || QDateTime::currentMSecsSinceEpoch() - m_appsLeidas > 60000)
        cargarApps();

    const quint64 totalAhora = m_cpuTotalAnt.isEmpty() ? 0 : m_cpuTotalAnt[0];
    const double ticksTotales = (m_ticksTotalAnt > 0 && totalAhora > m_ticksTotalAnt) ? double(totalAhora - m_ticksTotalAnt) : 0;

    QHash<int, Proc> nuevos;
    m_procBrutos.clear();
    const QStringList dirs = QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &d : dirs) {
        if (!d.at(0).isDigit())
            continue;
        const int pid = d.toInt();
        const QString base = QStringLiteral("/proc/") + d;
        const uint uid = QFileInfo(base).ownerId();
        if (!m_todos && uid != m_uid)
            continue;
        const QByteArray stat = leer(base + QStringLiteral("/stat"));
        const int abre = stat.indexOf('('), cierra = stat.lastIndexOf(')');
        if (abre < 0 || cierra < 0)
            continue;
        const QString comm = QString::fromUtf8(stat.mid(abre + 1, cierra - abre - 1));
        const QList<QByteArray> f = stat.mid(cierra + 2).split(' ');
        if (f.size() < 22)
            continue;
        const int ppid = f[1].toInt();
        if (pid == 2 || ppid == 2) // hilos del núcleo
            continue;
        const quint64 ticks = f[11].toULongLong() + f[12].toULongLong();
        const double rss = f[21].toDouble() * m_pagina4k;

        // Disco: lo que lee y escribe de verdad (solo se puede ver en los tuyos)
        quint64 io = 0;
        for (const QByteArray &l : leer(base + QStringLiteral("/io")).split('\n'))
            if (l.startsWith("read_bytes:") || l.startsWith("write_bytes:"))
                io += l.mid(l.indexOf(':') + 1).trimmed().toULongLong();

        const Proc ant = m_procAnt.value(pid, Proc{ticks, io});
        nuevos.insert(pid, Proc{ticks, io});
        const double cpu = ticksTotales > 0 ? qBound(0.0, 100.0 * double(ticks - qMin(ticks, ant.ticks)) / ticksTotales, 100.0) : 0.0;
        const double disco = (io - qMin(io, ant.io)) / segundos;

        // Programa: el ejecutable (o el script, si es un intérprete)
        QString programa = QFileInfo(QFileInfo(base + QStringLiteral("/exe")).symLinkTarget()).fileName();
        if (programa.isEmpty())
            programa = comm;
        if (esInterprete(programa)) {
            const QList<QByteArray> args = leer(base + QStringLiteral("/cmdline")).split('\0');
            for (int i = 1; i < args.size(); ++i) {
                if (!args[i].isEmpty() && !args[i].startsWith('-')) {
                    programa = QFileInfo(QString::fromUtf8(args[i])).fileName();
                    break;
                }
            }
        }
        programa.remove(QStringLiteral(" (deleted)"));
        m_procBrutos << QVariantMap{
            {QStringLiteral("pid"), pid},
            {QStringLiteral("programa"), programa},
            {QStringLiteral("cpu"), cpu},
            {QStringLiteral("memoria"), rss},
            {QStringLiteral("disco"), disco},
            {QStringLiteral("propio"), uid == m_uid},
        };
    }
    m_procAnt = nuevos;
    ordenarProcesos();
}

void MonitorBackend::ordenarProcesos()
{
    // Las apps (con lanzador) se agrupan: Firefox con todas sus pestañas es
    // una fila. Lo demás va en "Procesos en segundo plano", uno por fila.
    QHash<QString, QVariantMap> grupos;
    QVariantList fondo;
    const QString filtro = sinAcentos(m_filtro.trimmed());
    for (const QVariant &v : std::as_const(m_procBrutos)) {
        const QVariantMap p = v.toMap();
        const QString programa = p.value(QStringLiteral("programa")).toString();
        const auto app = m_apps.constFind(programa);
        const QString nombre = app != m_apps.constEnd() ? app->nombre : programa;
        if (!filtro.isEmpty() && !sinAcentos(nombre).contains(filtro) && !sinAcentos(programa).contains(filtro))
            continue;
        if (app == m_apps.constEnd() || criticos().contains(programa)) {
            QVariantMap fila = p;
            fila[QStringLiteral("nombre")] = programa;
            fila[QStringLiteral("pids")] = QVariantList{p.value(QStringLiteral("pid"))};
            fila[QStringLiteral("cantidad")] = 1;
            fila[QStringLiteral("critico")] = criticos().contains(programa) || !p.value(QStringLiteral("propio")).toBool();
            fondo << fila;
            continue;
        }
        QVariantMap &g = grupos[app->nombre];
        if (g.isEmpty()) {
            g = {{QStringLiteral("nombre"), app->nombre}, {QStringLiteral("icono"), app->icono}, {QStringLiteral("programa"), programa},
                 {QStringLiteral("cpu"), 0.0}, {QStringLiteral("memoria"), 0.0}, {QStringLiteral("disco"), 0.0},
                 {QStringLiteral("pids"), QVariantList()}, {QStringLiteral("cantidad"), 0}, {QStringLiteral("critico"), false}};
        }
        g[QStringLiteral("cpu")] = g.value(QStringLiteral("cpu")).toDouble() + p.value(QStringLiteral("cpu")).toDouble();
        g[QStringLiteral("memoria")] = g.value(QStringLiteral("memoria")).toDouble() + p.value(QStringLiteral("memoria")).toDouble();
        g[QStringLiteral("disco")] = g.value(QStringLiteral("disco")).toDouble() + p.value(QStringLiteral("disco")).toDouble();
        QVariantList pids = g.value(QStringLiteral("pids")).toList();
        pids << p.value(QStringLiteral("pid"));
        g[QStringLiteral("pids")] = pids;
        g[QStringLiteral("cantidad")] = pids.size();
        if (!p.value(QStringLiteral("propio")).toBool())
            g[QStringLiteral("critico")] = true;
    }

    const QString orden = m_orden;
    const bool desc = m_desc;
    auto cmp = [orden, desc](const QVariant &a, const QVariant &b) {
        const QVariantMap x = a.toMap(), y = b.toMap();
        if (orden == QLatin1String("nombre")) {
            const int c = x.value(QStringLiteral("nombre")).toString().localeAwareCompare(y.value(QStringLiteral("nombre")).toString());
            return desc ? c > 0 : c < 0;
        }
        const double vx = x.value(orden).toDouble(), vy = y.value(orden).toDouble();
        if (vx == vy)
            return x.value(QStringLiteral("nombre")).toString().localeAwareCompare(y.value(QStringLiteral("nombre")).toString()) < 0;
        return desc ? vx > vy : vx < vy;
    };
    QVariantList apps;
    for (const QVariantMap &g : std::as_const(grupos))
        apps << g;
    std::sort(apps.begin(), apps.end(), cmp);
    std::sort(fondo.begin(), fondo.end(), cmp);
    m_aplicaciones = apps;
    m_segundoPlano = fondo;
    emit procesosChanged();
}

void MonitorBackend::finalizar(const QVariantList &pids, const QString &nombre, bool forzar)
{
    QList<int> hechos;
    int ajenos = 0;
    for (const QVariant &v : pids) {
        const int pid = v.toInt();
        if (pid <= 1)
            continue;
        const QString base = QStringLiteral("/proc/%1").arg(pid);
        if (!QFileInfo::exists(base))
            continue;
        const QString programa = QFileInfo(QFileInfo(base + QStringLiteral("/exe")).symLinkTarget()).fileName();
        // Sin contraseña solo lo tuyo; y nunca lo que sostiene el escritorio
        if (QFileInfo(base).ownerId() != m_uid || criticos().contains(programa)) {
            ++ajenos;
            continue;
        }
        if (::kill(pid, forzar ? SIGKILL : SIGTERM) == 0)
            hechos << pid;
    }
    if (hechos.isEmpty()) {
        ponerAviso(ajenos > 0 ? QStringLiteral("«%1» es del sistema o de otro usuario: no se puede finalizar desde aquí").arg(nombre)
                              : QStringLiteral("«%1» ya no estaba abierto").arg(nombre));
        return;
    }
    ponerAviso(QStringLiteral("«%1» finalizado").arg(nombre));
    // Si a los 3 s sigue abierto (no responde), se cierra a la fuerza
    if (!forzar) {
        QTimer::singleShot(3000, this, [hechos] {
            for (int pid : hechos)
                if (::kill(pid, 0) == 0)
                    ::kill(pid, SIGKILL);
        });
    }
    QTimer::singleShot(400, this, &MonitorBackend::muestrear);
}

// ---------------------------------------------------------------- inicio
//
// Programas que arrancan solos (XDG autostart, lo que lanza la sesión de
// Inti con systemd-xdg-autostart-generator). Desactivar = una copia en
// ~/.config/autostart con Hidden=true: no hace falta ser administrador y se
// puede volver a activar.

void MonitorBackend::cargarInicio()
{
    const QString propio = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/autostart");
    QHash<QString, QString> ficheros; // id -> el que manda (el del usuario tapa al del sistema)
    for (const QString &dir : {QStringLiteral("/etc/xdg/autostart"), propio}) {
        for (const QFileInfo &f : QDir(dir).entryInfoList({QStringLiteral("*.desktop")}, QDir::Files))
            ficheros.insert(f.fileName(), f.absoluteFilePath());
    }
    QVariantList l;
    for (auto it = ficheros.cbegin(); it != ficheros.cend(); ++it) {
        // Lo que Inti necesita para funcionar no se ofrece apagar (bandeja,
        // carpetas del usuario, permisos de ubicación, accesibilidad, llavero...)
        static const QRegularExpression esencial(QStringLiteral(
            "^(xapp-sn-watcher|xdg-user-dirs|geoclue-demo-agent|at-spi-dbus-bus|gnome-keyring-.*|polkit-.*|"
            "org\\.fcitx\\.Fcitx5|pipewire.*|wireplumber|xdg-desktop-portal.*|titan-.*)\\.desktop$"));
        if (esencial.match(it.key()).hasMatch())
            continue;
        const auto e = titan::leerDesktop(it.value());
        const QString solo = e.value(QStringLiteral("OnlyShowIn"));
        if (!solo.isEmpty() && !titan::listaContieneEscritorio(solo))
            continue;
        if (titan::listaContieneEscritorio(e.value(QStringLiteral("NotShowIn"))))
            continue;
        QString nombre = e.value(QStringLiteral("Name[es]"));
        if (nombre.isEmpty()) nombre = e.value(QStringLiteral("Name"));
        if (nombre.isEmpty()) nombre = QFileInfo(it.key()).completeBaseName();
        QString comentario = e.value(QStringLiteral("Comment[es]"));
        if (comentario.isEmpty()) comentario = e.value(QStringLiteral("Comment"));
        const bool activado = !titan::esVerdadero(e.value(QStringLiteral("Hidden")))
                              && e.value(QStringLiteral("X-GNOME-Autostart-enabled")).compare(QLatin1String("false"), Qt::CaseInsensitive) != 0;
        l << QVariantMap{
            {QStringLiteral("id"), it.key()},
            {QStringLiteral("nombre"), nombre},
            {QStringLiteral("comentario"), comentario},
            {QStringLiteral("icono"), titan::iconoApp(e.value(QStringLiteral("Icon")), e.value(QStringLiteral("Exec")))},
            {QStringLiteral("activado"), activado},
            {QStringLiteral("sistema"), !it.value().startsWith(propio)},
        };
    }
    std::sort(l.begin(), l.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("nombre")).toString().localeAwareCompare(b.toMap().value(QStringLiteral("nombre")).toString()) < 0;
    });
    m_inicio = l;
    emit inicioChanged();
}

void MonitorBackend::activarInicio(const QString &id, bool activado)
{
    if (id.contains(QLatin1Char('/')) || !id.endsWith(QLatin1String(".desktop")))
        return;
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/autostart");
    const QString propio = dir + QLatin1Char('/') + id;
    QString texto;
    if (QFile::exists(propio))
        texto = QString::fromUtf8(leer(propio));
    else
        texto = QString::fromUtf8(leer(QStringLiteral("/etc/xdg/autostart/") + id));
    if (texto.isEmpty())
        return;
    // Quitar lo que hubiera y poner Hidden al final de [Desktop Entry]
    QStringList lineas = texto.split(QLatin1Char('\n'));
    lineas.erase(std::remove_if(lineas.begin(), lineas.end(), [](const QString &l) {
        return l.startsWith(QLatin1String("Hidden=")) || l.startsWith(QLatin1String("X-GNOME-Autostart-enabled="));
    }), lineas.end());
    const int entrada = lineas.indexOf(QStringLiteral("[Desktop Entry]"));
    lineas.insert(entrada >= 0 ? entrada + 1 : 0, QStringLiteral("Hidden=%1").arg(activado ? QStringLiteral("false") : QStringLiteral("true")));
    QDir().mkpath(dir);
    QFile f(propio);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        ponerAviso(QStringLiteral("No se pudo guardar el cambio"));
        return;
    }
    f.write(lineas.join(QLatin1Char('\n')).toUtf8());
    f.close();
    cargarInicio();
    ponerAviso(activado ? QStringLiteral("Se abrirá al iniciar sesión") : QStringLiteral("Ya no se abrirá al iniciar sesión"));
}
