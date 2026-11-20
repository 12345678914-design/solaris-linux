#include "Sistema.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QProcess>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QTextStream>
#include <QTimer>
#include <QUrl>

#include <unistd.h>

namespace {
// TITAN_BIN: solo para pruebas (programas de Inti fuera de /usr/local/bin)
const QString kBin = qEnvironmentVariable("TITAN_BIN", QStringLiteral("/usr/local/bin/"));

QString leerFichero(const QString &ruta)
{
    QFile f(ruta);
    if (!f.open(QIODevice::ReadOnly))
        return QString();
    return QString::fromUtf8(f.readAll()).trimmed();
}

// nmcli -t separa con ':' y escapa los ':' de los nombres como '\:'.
QStringList camposNmcli(const QString &linea)
{
    QStringList campos;
    QString actual;
    for (int i = 0; i < linea.size(); ++i) {
        const QChar c = linea.at(i);
        if (c == QLatin1Char('\\') && i + 1 < linea.size()) {
            actual += linea.at(++i);
        } else if (c == QLatin1Char(':')) {
            campos << actual;
            actual.clear();
        } else {
            actual += c;
        }
    }
    campos << actual;
    return campos;
}
} // namespace

Sistema::Sistema(QObject *parent)
    : QObject(parent)
{
    leerInactividad();
}

bool Sistema::live() const
{
    return QFile::exists(QStringLiteral("/run/archiso"));
}

// ---------------------------------------------------------------- procesos

void Sistema::correr(const QString &programa, const QStringList &args, Fin fin, int msMax)
{
    auto *p = new QProcess(this);
    // Salida en ingles: se interpreta texto de lpstat, localectl, fprintd...
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C.UTF-8"));
    p->setProcessEnvironment(env);

    auto *limite = new QTimer(p);
    limite->setSingleShot(true);
    connect(limite, &QTimer::timeout, p, [p]() { p->kill(); });

    connect(p, &QProcess::finished, this, [p, fin](int codigo, QProcess::ExitStatus estado) {
        const QString salida = QString::fromUtf8(p->readAllStandardOutput());
        const QString error = QString::fromUtf8(p->readAllStandardError());
        p->deleteLater();
        if (fin)
            fin(estado == QProcess::NormalExit ? codigo : -1, salida, error);
    });
    connect(p, &QProcess::errorOccurred, this, [p, fin](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart)
            return;
        p->deleteLater();
        if (fin)
            fin(-1, QString(), QStringLiteral("no está instalado"));
    });
    p->start(programa, args);
    limite->start(msMax);
}

void Sistema::comoAdmin(const QString &operacion, const QStringList &orden, Fin fin)
{
    ocupar(operacion);
    correr(QStringLiteral("pkexec"), orden, [this, fin](int codigo, const QString &salida, const QString &error) {
        ocupar(QString());
        // pkexec: 126 = la persona cerro la ventana, 127 = no autorizado
        if (codigo == 126) {
            avisar(QStringLiteral("Cancelado: no se ha cambiado nada."));
            return;
        }
        if (codigo == 127) {
            avisar(QStringLiteral("Tu cuenta no puede hacer cambios de administrador."));
            return;
        }
        if (fin)
            fin(codigo, salida, error);
    }, 15 * 60 * 1000);
}

void Sistema::avisar(const QString &texto)
{
    m_aviso = texto;
    emit cambiado();
}

void Sistema::ocupar(const QString &que)
{
    m_ocupado = que;
    emit cambiado();
}

// ---------------------------------------------------------------- ficheros de configuracion

QString Sistema::rutaConfig(const QString &fichero) const
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
           + QStringLiteral("/titan/") + fichero;
}

QVariantMap Sistema::leerConf(const QString &fichero) const
{
    QVariantMap m;
    QFile f(rutaConfig(fichero));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return m;
    QTextStream in(&f);
    while (!in.atEnd()) {
        const QString l = in.readLine().trimmed();
        if (l.isEmpty() || l.startsWith(QLatin1Char('#')) || !l.contains(QLatin1Char('=')))
            continue;
        QString valor = l.section(QLatin1Char('='), 1).trimmed();
        if (valor.size() >= 2 && valor.startsWith(QLatin1Char('"')) && valor.endsWith(QLatin1Char('"')))
            valor = valor.mid(1, valor.size() - 2);
        m.insert(l.section(QLatin1Char('='), 0, 0).trimmed(), valor);
    }
    return m;
}

void Sistema::escribirConf(const QString &fichero, const QString &clave, const QString &valor)
{
    const QString ruta = rutaConfig(fichero);
    QDir().mkpath(QFileInfo(ruta).absolutePath());
    QStringList lineas;
    {
        QFile f(ruta);
        if (f.open(QIODevice::ReadOnly | QIODevice::Text))
            lineas = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
    }
    while (!lineas.isEmpty() && lineas.last().isEmpty())
        lineas.removeLast();
    bool puesto = false;
    for (QString &l : lineas) {
        if (l.trimmed().startsWith(clave + QLatin1Char('='))) {
            l = clave + QLatin1Char('=') + valor;
            puesto = true;
        }
    }
    if (!puesto)
        lineas << clave + QLatin1Char('=') + valor;
    QFile f(ruta);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        f.write((lineas.join(QLatin1Char('\n')) + QLatin1Char('\n')).toUtf8());
}

// ---------------------------------------------------------------- refrescar

void Sistema::refrescar(const QString &seccion)
{
    m_aviso.clear();
    if (seccion == QStringLiteral("Batería")) {
        leerEnergia();
        leerBateria();
        leerInactividad();
    } else if (seccion == QStringLiteral("Bloquear pantalla")) {
        leerInactividad();
        leerSeguridad();
    } else if (seccion == QStringLiteral("Privacidad y seguridad")) {
        leerSeguridad();
    } else if (seccion == QStringLiteral("Accesibilidad")) {
        leerAccesibilidad();
    } else if (seccion == QStringLiteral("Teclado")) {
        leerTeclado();
    } else if (seccion == QStringLiteral("Ratón y panel táctil")) {
        leerRaton();
    } else if (seccion == QStringLiteral("Impresoras y escáneres")) {
        leerImpresoras();
    } else if (seccion == QStringLiteral("Restaurar sistema")) {
        leerInstantaneas();
    } else if (seccion == QStringLiteral("VPN")) {
        leerVpns();
    } else if (seccion == QStringLiteral("Almacenamiento")) {
        leerAlmacenamiento();
    } else if (seccion == QStringLiteral("bateria")) {
        leerBateria();
    }
    emit cambiado();
}

// ---------------------------------------------------------------- energia

void Sistema::leerEnergia()
{
    correr(QStringLiteral("powerprofilesctl"), {QStringLiteral("get")}, [this](int c, const QString &o, const QString &) {
        m_perfil = c == 0 ? o.trimmed() : QString();
        emit cambiado();
    }, 5000);
    correr(QStringLiteral("powerprofilesctl"), {QStringLiteral("list")}, [this](int c, const QString &o, const QString &) {
        m_perfiles.clear();
        if (c == 0) {
            static const QRegularExpression re(QStringLiteral("^\\*?\\s*([a-z-]+):\\s*$"));
            for (const QString &l : o.split(QLatin1Char('\n'))) {
                const auto m = re.match(l);
                if (m.hasMatch())
                    m_perfiles << m.captured(1);
            }
        }
        emit cambiado();
    }, 5000);
}

void Sistema::setPerfilEnergia(const QString &perfil)
{
    if (!m_perfiles.contains(perfil))
        return;
    correr(QStringLiteral("powerprofilesctl"), {QStringLiteral("set"), perfil}, [this, perfil](int c, const QString &, const QString &e) {
        if (c == 0)
            m_perfil = perfil;
        else
            avisar(QStringLiteral("No se pudo cambiar el modo de energía: ") + e.trimmed());
        emit cambiado();
    }, 10000);
}

void Sistema::leerBateria()
{
    QVariantMap b;
    const QDir dir(QStringLiteral("/sys/class/power_supply"));
    bool enchufado = false;
    for (const QString &n : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        const QString base = dir.filePath(n) + QLatin1Char('/');
        const QString tipo = leerFichero(base + QStringLiteral("type"));
        if (tipo == QStringLiteral("Mains") && leerFichero(base + QStringLiteral("online")) == QStringLiteral("1"))
            enchufado = true;
        if (tipo != QStringLiteral("Battery") || b.contains(QStringLiteral("porcentaje")))
            continue;
        if (leerFichero(base + QStringLiteral("scope")) == QStringLiteral("Device"))
            continue;   // raton o auriculares, no la bateria del equipo
        b[QStringLiteral("porcentaje")] = leerFichero(base + QStringLiteral("capacity")).toInt();
        b[QStringLiteral("estado")] = leerFichero(base + QStringLiteral("status"));
        const QString pre = QFile::exists(base + QStringLiteral("energy_full")) ? QStringLiteral("energy") : QStringLiteral("charge");
        const double lleno = leerFichero(base + pre + QStringLiteral("_full")).toDouble();
        const double diseno = leerFichero(base + pre + QStringLiteral("_full_design")).toDouble();
        const double ahora = leerFichero(base + pre + QStringLiteral("_now")).toDouble();
        const double ritmo = leerFichero(base + (pre == QStringLiteral("energy") ? QStringLiteral("power_now") : QStringLiteral("current_now"))).toDouble();
        if (lleno > 0 && diseno > 0)
            b[QStringLiteral("salud")] = qRound(qMin(100.0, lleno * 100.0 / diseno));
        const int ciclos = leerFichero(base + QStringLiteral("cycle_count")).toInt();
        if (ciclos > 0)
            b[QStringLiteral("ciclos")] = ciclos;
        if (ritmo > 0 && b.value(QStringLiteral("estado")) == QStringLiteral("Discharging"))
            b[QStringLiteral("minutosRestantes")] = qRound(ahora / ritmo * 60.0);
        else if (ritmo > 0 && b.value(QStringLiteral("estado")) == QStringLiteral("Charging") && lleno > ahora)
            b[QStringLiteral("minutosHastaLlena")] = qRound((lleno - ahora) / ritmo * 60.0);
    }
    b[QStringLiteral("hay")] = b.contains(QStringLiteral("porcentaje"));
    b[QStringLiteral("enchufado")] = enchufado;
    m_bateria = b;
    emit cambiado();
}

void Sistema::leerInactividad()
{
    QVariantMap m{{QStringLiteral("BLOQUEAR"), 5},
                  {QStringLiteral("APAGAR_PANTALLA"), 10},
                  {QStringLiteral("SUSPENDER_BATERIA"), 15},
                  {QStringLiteral("SUSPENDER_CORRIENTE"), 30}};
    const QVariantMap c = leerConf(QStringLiteral("inactividad.conf"));
    for (auto it = c.cbegin(); it != c.cend(); ++it) {
        bool ok = false;
        const int v = it.value().toString().toInt(&ok);
        if (ok && m.contains(it.key()))
            m[it.key()] = v;
    }
    m_inactividad = m;
}

void Sistema::setInactividad(const QString &clave, int minutos)
{
    if (!m_inactividad.contains(clave) || minutos < 0 || minutos > 600)
        return;
    escribirConf(QStringLiteral("inactividad.conf"), clave, QString::number(minutos));
    m_inactividad[clave] = minutos;
    emit cambiado();
    // titan-inactividad se reinicia solo (mata su swayidle y arranca otro).
    QProcess::startDetached(kBin + QStringLiteral("titan-inactividad"), {});
}

void Sistema::bloquearAhora()
{
    if (!QProcess::startDetached(kBin + QStringLiteral("titan-bloquear"), {}))
        QProcess::startDetached(QStringLiteral("loginctl"), {QStringLiteral("lock-session")});
}

// ---------------------------------------------------------------- seguridad

void Sistema::leerSeguridad()
{
    correr(kBin + QStringLiteral("titan-cortafuegos"), {QStringLiteral("estado")}, [this](int c, const QString &o, const QString &) {
        m_cortafuegos = c == -1 ? QStringLiteral("desconocido") : o.trimmed();
        emit cambiado();
    }, 10000);
    correr(kBin + QStringLiteral("titan-arranque-seguro"), {QStringLiteral("estado")}, [this](int, const QString &o, const QString &) {
        const QString l = o.trimmed();
        m_sb = l.section(QLatin1Char('|'), 0, 0);
        m_sbTexto = l.section(QLatin1Char('|'), 1);
        emit cambiado();
    }, 10000);
    correr(kBin + QStringLiteral("titan-huella"), {QStringLiteral("estado")}, [this](int, const QString &o, const QString &) {
        m_huella = o.trimmed().isEmpty() ? QStringLiteral("sin-lector") : o.trimmed();
        emit cambiado();
    }, 10000);
    correr(kBin + QStringLiteral("titan-huella"), {QStringLiteral("pam")}, [this](int, const QString &o, const QString &) {
        m_huellaActiva = o.trimmed() == QStringLiteral("si");
        emit cambiado();
    }, 5000);
}

void Sistema::setCortafuegos(bool activo)
{
    comoAdmin(QStringLiteral("cortafuegos"),
              {kBin + QStringLiteral("titan-cortafuegos"), activo ? QStringLiteral("activar") : QStringLiteral("desactivar")},
              [this](int c, const QString &, const QString &e) {
                  if (c != 0)
                      avisar(QStringLiteral("No se pudo cambiar el cortafuegos: ") + e.trimmed());
                  leerSeguridad();
              });
}

void Sistema::prepararArranqueSeguro()
{
    comoAdmin(QStringLiteral("arranque-seguro"), {kBin + QStringLiteral("titan-arranque-seguro"), QStringLiteral("preparar")},
              [this](int c, const QString &, const QString &e) {
                  if (c == 0) {
                      avisar(QStringLiteral("Listo. Reinicia, entra en la BIOS/UEFI y activa Secure Boot."));
                  } else {
                      const QStringList l = e.trimmed().split(QLatin1Char('\n'));
                      avisar(l.isEmpty() || l.last().isEmpty() ? QStringLiteral("No se pudo preparar el arranque seguro.") : l.last());
                  }
                  leerSeguridad();
              });
}

void Sistema::registrarHuella()
{
    if (m_registro)
        return;
    m_registro = new QProcess(this);
    m_registro->setProcessChannelMode(QProcess::MergedChannels);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C.UTF-8"));
    m_registro->setProcessEnvironment(env);
    m_mensajeHuella = QStringLiteral("Pon el dedo índice derecho en el lector.");
    int pasadas = 0;
    connect(m_registro, &QProcess::readyRead, this, [this, pasadas]() mutable {
        while (m_registro && m_registro->canReadLine()) {
            const QString l = QString::fromUtf8(m_registro->readLine()).trimmed();
            if (!l.startsWith(QStringLiteral("Enroll result: ")))
                continue;
            const QString r = l.mid(15);
            if (r == QStringLiteral("enroll-stage-passed"))
                m_mensajeHuella = QStringLiteral("Bien (%1). Levanta el dedo y vuelve a ponerlo.").arg(++pasadas);
            else if (r == QStringLiteral("enroll-retry-scan") || r == QStringLiteral("enroll-remove-and-retry"))
                m_mensajeHuella = QStringLiteral("No se ha leído bien. Inténtalo otra vez.");
            else if (r == QStringLiteral("enroll-finger-not-centered"))
                m_mensajeHuella = QStringLiteral("Pon el dedo en el centro del lector.");
            else if (r == QStringLiteral("enroll-swipe-too-short"))
                m_mensajeHuella = QStringLiteral("Desliza el dedo más despacio.");
            else if (r == QStringLiteral("enroll-completed"))
                m_mensajeHuella = QStringLiteral("Huella registrada.");
            else if (r == QStringLiteral("enroll-data-full"))
                m_mensajeHuella = QStringLiteral("El lector no tiene espacio para más huellas.");
            else if (r == QStringLiteral("enroll-duplicate"))
                m_mensajeHuella = QStringLiteral("Esa huella ya está registrada.");
            else
                m_mensajeHuella = QStringLiteral("No se pudo registrar la huella (%1).").arg(r);
            emit cambiado();
        }
    });
    connect(m_registro, &QProcess::finished, this, [this]() {
        m_registro->deleteLater();
        m_registro = nullptr;
        emit cambiado();
        leerSeguridad();
    });
    m_registro->start(QStringLiteral("fprintd-enroll"), {});
    emit cambiado();
}

void Sistema::cancelarHuella()
{
    if (m_registro) {
        m_registro->terminate();
        m_mensajeHuella.clear();
    }
}

void Sistema::setHuellaActiva(bool activa)
{
    comoAdmin(QStringLiteral("huella"),
              {kBin + QStringLiteral("titan-huella"), activa ? QStringLiteral("activar") : QStringLiteral("desactivar")},
              [this](int, const QString &, const QString &) { leerSeguridad(); });
}

// ---------------------------------------------------------------- accesibilidad y teclado

void Sistema::leerAccesibilidad()
{
    correr(kBin + QStringLiteral("titan-lector"), {QStringLiteral("estado")}, [this](int, const QString &o, const QString &) {
        m_lector = o.trimmed() == QStringLiteral("on");
        emit cambiado();
    }, 5000);
    correr(QStringLiteral("pgrep"), {QStringLiteral("-u"), QString::number(getuid()), QStringLiteral("-x"), QStringLiteral("titan-teclado")},
           [this](int codigo, const QString &, const QString &) {
        m_tecladoPantalla = codigo == 0;
        emit cambiado();
    }, 3000);
}

// Teclado en pantalla (titan-teclado): abrirlo lo cierra si ya estaba
// abierto, así que solo se lanza cuando hace falta cambiar. Se recuerda en
// accesibilidad.conf (TECLADO=1) y titan-sesion lo abre al entrar.
void Sistema::setTecladoPantalla(bool activo)
{
    const QString conf = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                         + QStringLiteral("/titan/accesibilidad.conf");
    QStringList lineas;
    QFile f(conf);
    if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        for (const QString &l : QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts))
            if (!l.startsWith(QStringLiteral("TECLADO=")))
                lineas << l;
        f.close();
    }
    lineas << (activo ? QStringLiteral("TECLADO=1") : QStringLiteral("TECLADO=0"));
    QDir().mkpath(QFileInfo(conf).absolutePath());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        f.write((lineas.join(QLatin1Char('\n')) + QLatin1Char('\n')).toUtf8());

    const bool antes = m_tecladoPantalla;
    m_tecladoPantalla = activo;
    emit cambiado();
    if (antes != activo)
        QProcess::startDetached(kBin + QStringLiteral("titan-teclado"), {});
    QTimer::singleShot(800, this, [this] { leerAccesibilidad(); });
}

void Sistema::setLector(bool activo)
{
    m_lector = activo;
    emit cambiado();
    correr(kBin + QStringLiteral("titan-lector"), {activo ? QStringLiteral("on") : QStringLiteral("off")},
           [this](int, const QString &, const QString &) { leerAccesibilidad(); }, 15000);
}

void Sistema::leerTeclado()
{
    m_entrada = leerConf(QStringLiteral("entrada.conf")).value(QStringLiteral("ACTIVO")).toString() == QStringLiteral("1");
    // "es", "latam", "us intl"...: la de esta persona o, si no eligió, la del sistema
    correr(kBin + QStringLiteral("titan-distribucion"), {}, [this](int, const QString &o, const QString &) {
        m_teclado = o.trimmed().isEmpty() ? QStringLiteral("us") : o.trimmed();
        emit cambiado();
    }, 5000);
}

void Sistema::setDistribucion(const QString &capa, const QString &variante)
{
    m_teclado = (capa + QLatin1Char(' ') + variante).trimmed();
    emit cambiado();
    correr(kBin + QStringLiteral("titan-distribucion"), {capa, variante},
           [this](int codigo, const QString &, const QString &err) {
        if (codigo != 0)
            avisar(QStringLiteral("No se pudo cambiar la distribución: ") + err.trimmed());
        leerTeclado();
    }, 5000);
}

// ---------------------------------------------------------------- ratón y panel táctil

static QString rutaWayfireIni()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/wayfire.ini");
}

// Cambia (o añade) "clave = valor" en la sección [seccion] de wayfire.ini;
// Wayfire vigila el fichero y lo aplica al momento.
static void ponerClaveWayfire(const QString &seccion, const QString &clave, const QString &texto)
{
    QStringList lineas;
    QFile f(rutaWayfireIni());
    if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        lineas = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
        f.close();
    }
    if (!lineas.isEmpty() && lineas.last().isEmpty())
        lineas.removeLast();
    const QString cabecera = QLatin1Char('[') + seccion + QLatin1Char(']');
    int inicio = -1, fin = lineas.size();
    for (int i = 0; i < lineas.size(); ++i) {
        const QString l = lineas.at(i).trimmed();
        if (!l.startsWith(QLatin1Char('[')))
            continue;
        if (inicio >= 0) { fin = i; break; }
        if (l == cabecera)
            inicio = i;
    }
    const QString nueva = clave + QStringLiteral(" = ") + texto;
    if (inicio < 0) {
        lineas << QString() << cabecera << nueva;
    } else {
        bool hecho = false;
        for (int i = inicio + 1; i < fin; ++i) {
            const QString l = lineas.at(i).trimmed();
            const int igual = l.indexOf(QLatin1Char('='));
            if (igual > 0 && l.left(igual).trimmed() == clave) {
                lineas[i] = nueva;
                hecho = true;
                break;
            }
        }
        if (!hecho)
            lineas.insert(fin, nueva);
    }
    QDir().mkpath(QFileInfo(rutaWayfireIni()).absolutePath());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        f.write((lineas.join(QLatin1Char('\n')) + QLatin1Char('\n')).toUtf8());
}

// Claves de [input] de Wayfire que se ven en Ajustes, con su valor por defecto
static const QList<QPair<QString, QString>> &clavesRaton()
{
    static const QList<QPair<QString, QString>> c = {
        {QStringLiteral("mouse_cursor_speed"), QStringLiteral("0")},
        {QStringLiteral("mouse_natural_scroll"), QStringLiteral("false")},
        {QStringLiteral("left_handed_mode"), QStringLiteral("false")},
        {QStringLiteral("touchpad_cursor_speed"), QStringLiteral("0")},
        {QStringLiteral("natural_scroll"), QStringLiteral("false")},
        {QStringLiteral("tap_to_click"), QStringLiteral("true")},
        {QStringLiteral("disable_touchpad_while_typing"), QStringLiteral("false")},
    };
    return c;
}

void Sistema::leerRaton()
{
    QVariantMap m;
    for (const auto &c : clavesRaton())
        m.insert(c.first, c.second);
    QFile wf(rutaWayfireIni());
    if (wf.open(QIODevice::ReadOnly | QIODevice::Text)) {
        bool enInput = false;
        QTextStream in(&wf);
        while (!in.atEnd()) {
            const QString l = in.readLine().trimmed();
            if (l.startsWith(QLatin1Char('['))) {
                enInput = l == QStringLiteral("[input]");
                continue;
            }
            const int igual = l.indexOf(QLatin1Char('='));
            if (!enInput || igual <= 0)
                continue;
            const QString k = l.left(igual).trimmed();
            if (m.contains(k))
                m.insert(k, l.mid(igual + 1).trimmed());
        }
        wf.close();
    }
    // Interruptores como bool y velocidades como número (-1 lento .. 1 rápido)
    for (auto it = m.begin(); it != m.end(); ++it) {
        const QString v = it.value().toString();
        if (it.key().endsWith(QStringLiteral("_speed")))
            it.value() = v.toDouble();
        else
            it.value() = (v == QStringLiteral("true") || v == QStringLiteral("1"));
    }
    // Gestos del panel táctil ([titan-gestos] activado; por defecto sí)
    bool gestos = true;
    if (wf.open(QIODevice::ReadOnly | QIODevice::Text)) {
        bool enGestos = false;
        QTextStream in(&wf);
        while (!in.atEnd()) {
            const QString l = in.readLine().trimmed();
            if (l.startsWith(QLatin1Char('['))) { enGestos = l == QStringLiteral("[titan-gestos]"); continue; }
            if (enGestos && l.startsWith(QStringLiteral("activado")))
                gestos = l.section(QLatin1Char('='), 1).trimmed() != QStringLiteral("false");
        }
        wf.close();
    }
    m.insert(QStringLiteral("gestos"), gestos);
    m_raton = m;

    // ¿Hay panel táctil? (como Ubuntu: si no, no se enseña su grupo)
    m_panelTactil = false;
    QFile disp(QStringLiteral("/proc/bus/input/devices"));
    if (disp.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString t = QString::fromUtf8(disp.readAll()).toLower();
        m_panelTactil = t.contains(QStringLiteral("touchpad")) || t.contains(QStringLiteral("trackpad"))
                        || t.contains(QStringLiteral("synaptics")) || t.contains(QStringLiteral("glidepoint"));
    }
    emit cambiado();
}

// Cambia una clave de [input] en wayfire.ini; Wayfire la aplica al momento.
void Sistema::setRaton(const QString &clave, const QVariant &valor)
{
    if (clave == QStringLiteral("gestos")) {
        ponerClaveWayfire(QStringLiteral("titan-gestos"), QStringLiteral("activado"),
                          valor.toBool() ? QStringLiteral("true") : QStringLiteral("false"));
        // Y el de tres dedos a los lados (cambiar de escritorio, plugin vswipe)
        ponerClaveWayfire(QStringLiteral("vswipe"), QStringLiteral("enable_horizontal"),
                          valor.toBool() ? QStringLiteral("true") : QStringLiteral("false"));
        m_raton.insert(clave, valor.toBool());
        emit cambiado();
        return;
    }
    bool conocida = false;
    for (const auto &c : clavesRaton())
        conocida = conocida || c.first == clave;
    if (!conocida)
        return;
    QString texto;
    if (clave.endsWith(QStringLiteral("_speed")))
        texto = QString::number(qBound(-1.0, valor.toDouble(), 1.0), 'f', 2);
    else
        texto = valor.toBool() ? QStringLiteral("true") : QStringLiteral("false");

    ponerClaveWayfire(QStringLiteral("input"), clave, texto);
    m_raton.insert(clave, clave.endsWith(QStringLiteral("_speed")) ? QVariant(texto.toDouble()) : QVariant(valor.toBool()));
    emit cambiado();
}

void Sistema::setMetodosEntrada(bool activo)
{
    escribirConf(QStringLiteral("entrada.conf"), QStringLiteral("ACTIVO"), activo ? QStringLiteral("1") : QStringLiteral("0"));
    m_entrada = activo;
    if (activo) {
        QProcess::startDetached(QStringLiteral("fcitx5"), {QStringLiteral("-d"), QStringLiteral("--replace")});
        avisar(QStringLiteral("Activado. Algunas apps lo usarán al volver a abrirlas; todas, al volver a entrar en la sesión."));
    } else {
        QProcess::startDetached(QStringLiteral("pkill"), {QStringLiteral("-x"), QStringLiteral("fcitx5")});
        avisar(QStringLiteral("Desactivado."));
    }
    emit cambiado();
}

// ---------------------------------------------------------------- impresoras

void Sistema::leerImpresoras()
{
    correr(QStringLiteral("lpstat"), {QStringLiteral("-p"), QStringLiteral("-d")}, [this](int, const QString &o, const QString &) {
        QString predeterminada;
        static const QRegularExpression reDef(QStringLiteral("system default destination: (\\S+)"));
        const auto md = reDef.match(o);
        if (md.hasMatch())
            predeterminada = md.captured(1);
        static const QRegularExpression reImp(QStringLiteral("^printer (\\S+) (.*)$"));
        QVariantList lista;
        for (const QString &l : o.split(QLatin1Char('\n'))) {
            const auto m = reImp.match(l);
            if (!m.hasMatch())
                continue;
            const QString resto = m.captured(2);
            QString estado = QStringLiteral("Lista");
            if (resto.contains(QStringLiteral("disabled")))
                estado = QStringLiteral("Desactivada");
            else if (resto.contains(QStringLiteral("printing")))
                estado = QStringLiteral("Imprimiendo");
            lista << QVariantMap{{QStringLiteral("nombre"), m.captured(1)},
                                 {QStringLiteral("estado"), estado},
                                 {QStringLiteral("predeterminada"), m.captured(1) == predeterminada}};
        }
        m_impresoras = lista;
        emit cambiado();
    }, 10000);
}

// ---------------------------------------------------------------- instantaneas

void Sistema::leerInstantaneas()
{
    correr(kBin + QStringLiteral("titan-instantaneas"), {QStringLiteral("tipo")}, [this](int, const QString &o, const QString &) {
        m_tipoInst = o.trimmed().isEmpty() ? QStringLiteral("ninguno") : o.trimmed();
        emit cambiado();
    }, 5000);
    correr(kBin + QStringLiteral("titan-instantaneas"), {QStringLiteral("lista")}, [this](int, const QString &o, const QString &) {
        QVariantList lista;
        for (const QString &l : o.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            const QStringList c = l.split(QLatin1Char('|'));
            if (c.size() < 3)
                continue;
            lista.prepend(QVariantMap{{QStringLiteral("numero"), c.at(0).toInt()},
                                      {QStringLiteral("fecha"), c.at(1)},
                                      {QStringLiteral("descripcion"), c.mid(2).join(QLatin1Char('|'))}});
        }
        m_instantaneas = lista;   // la mas reciente primero
        emit cambiado();
    }, 15000);
}

void Sistema::crearInstantanea(const QString &descripcion)
{
    const QString d = descripcion.trimmed().isEmpty() ? QStringLiteral("Punto de restauración manual") : descripcion.trimmed().left(120);
    comoAdmin(QStringLiteral("instantanea"), {kBin + QStringLiteral("titan-instantaneas"), QStringLiteral("crear"), d},
              [this](int c, const QString &, const QString &e) {
                  avisar(c == 0 ? QStringLiteral("Punto de restauración creado.")
                                : QStringLiteral("No se pudo crear: ") + e.trimmed());
                  leerInstantaneas();
              });
}

void Sistema::borrarInstantanea(int numero)
{
    if (numero <= 0)
        return;
    comoAdmin(QStringLiteral("instantanea"), {kBin + QStringLiteral("titan-instantaneas"), QStringLiteral("borrar"), QString::number(numero)},
              [this](int c, const QString &, const QString &e) {
                  if (c != 0)
                      avisar(QStringLiteral("No se pudo borrar: ") + e.trimmed());
                  leerInstantaneas();
              });
}

// ---------------------------------------------------------------- VPN

void Sistema::leerVpns()
{
    correr(QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("NAME,TYPE,ACTIVE"),
                                     QStringLiteral("connection"), QStringLiteral("show")},
           [this](int, const QString &o, const QString &) {
               QVariantList lista;
               for (const QString &l : o.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                   const QStringList c = camposNmcli(l);
                   if (c.size() < 3)
                       continue;
                   const QString tipo = c.at(1);
                   if (tipo != QStringLiteral("vpn") && tipo != QStringLiteral("wireguard"))
                       continue;
                   lista << QVariantMap{{QStringLiteral("nombre"), c.at(0)},
                                        {QStringLiteral("tipo"), tipo == QStringLiteral("wireguard") ? QStringLiteral("WireGuard") : QStringLiteral("VPN")},
                                        {QStringLiteral("activa"), c.at(2) == QStringLiteral("yes")}};
               }
               m_vpns = lista;
               emit cambiado();
           }, 10000);
}

void Sistema::setVpn(const QString &nombre, bool activa)
{
    ocupar(QStringLiteral("vpn"));
    correr(QStringLiteral("nmcli"), {QStringLiteral("connection"), activa ? QStringLiteral("up") : QStringLiteral("down"),
                                     QStringLiteral("id"), nombre},
           [this](int c, const QString &, const QString &e) {
               ocupar(QString());
               if (c != 0)
                   avisar(QStringLiteral("No se pudo conectar: ") + e.trimmed().section(QLatin1Char('\n'), -1));
               leerVpns();
           }, 90000);
}

void Sistema::importarVpn(const QString &url)
{
    const QString fichero = QUrl(url).isLocalFile() ? QUrl(url).toLocalFile() : url;
    QFile f(fichero);
    if (!f.open(QIODevice::ReadOnly)) {
        avisar(QStringLiteral("No se puede leer el fichero."));
        return;
    }
    const bool wireguard = fichero.endsWith(QStringLiteral(".conf")) && f.read(64 * 1024).contains("[Interface]");
    ocupar(QStringLiteral("vpn"));
    correr(QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("import"), QStringLiteral("type"),
                                     wireguard ? QStringLiteral("wireguard") : QStringLiteral("openvpn"),
                                     QStringLiteral("file"), fichero},
           [this](int c, const QString &, const QString &e) {
               ocupar(QString());
               avisar(c == 0 ? QStringLiteral("VPN añadida.")
                             : QStringLiteral("No se pudo importar: ") + e.trimmed().section(QLatin1Char('\n'), -1));
               leerVpns();
           }, 30000);
}

// ---------------------------------------------------------------- almacenamiento

void Sistema::leerAlmacenamiento()
{
    // Volumenes montados (uno por dispositivo: btrfs monta el mismo varias veces)
    QVariantList vols;
    QSet<QByteArray> vistos;
    QList<QStorageInfo> lista = QStorageInfo::mountedVolumes();
    std::sort(lista.begin(), lista.end(), [](const QStorageInfo &a, const QStorageInfo &b) {
        return a.rootPath().size() < b.rootPath().size();
    });
    for (const QStorageInfo &s : std::as_const(lista)) {
        if (!s.isValid() || !s.isReady() || !s.device().startsWith("/dev/") || s.bytesTotal() <= 0)
            continue;
        if (s.device().startsWith("/dev/loop") || s.rootPath().startsWith(QStringLiteral("/boot"))
            || s.rootPath().startsWith(QStringLiteral("/run/archiso")))
            continue;
        if (vistos.contains(s.device()))
            continue;
        vistos.insert(s.device());
        QString nombre = s.rootPath() == QStringLiteral("/") ? QStringLiteral("Inti OS") : s.displayName();
        vols << QVariantMap{{QStringLiteral("nombre"), nombre},
                            {QStringLiteral("ruta"), s.rootPath()},
                            {QStringLiteral("dispositivo"), QString::fromUtf8(s.device())},
                            {QStringLiteral("sistema"), QString::fromUtf8(s.fileSystemType())},
                            {QStringLiteral("total"), double(s.bytesTotal())},
                            {QStringLiteral("libre"), double(s.bytesAvailable())}};
    }
    m_volumenes = vols;

    correr(QStringLiteral("lsblk"), {QStringLiteral("-d"), QStringLiteral("-n"), QStringLiteral("-b"), QStringLiteral("-P"),
                                     QStringLiteral("-o"), QStringLiteral("NAME,SIZE,ROTA,TRAN,TYPE,MODEL")},
           [this](int, const QString &o, const QString &) {
               static const QRegularExpression re(QStringLiteral("(\\w+)=\"([^\"]*)\""));
               QVariantList lista;
               for (const QString &l : o.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                   QVariantMap d;
                   auto it = re.globalMatch(l);
                   while (it.hasNext()) {
                       const auto m = it.next();
                       d.insert(m.captured(1), m.captured(2).trimmed());
                   }
                   if (d.value(QStringLiteral("TYPE")) != QStringLiteral("disk"))
                       continue;
                   const QString nombre = d.value(QStringLiteral("NAME")).toString();
                   if (nombre.startsWith(QStringLiteral("zram")) || nombre.startsWith(QStringLiteral("loop")))
                       continue;
                   QString clase = QStringLiteral("Disco");
                   const QString tran = d.value(QStringLiteral("TRAN")).toString();
                   if (tran == QStringLiteral("usb"))
                       clase = QStringLiteral("USB");
                   else if (tran == QStringLiteral("nvme") || nombre.startsWith(QStringLiteral("nvme")))
                       clase = QStringLiteral("NVMe");
                   else if (d.value(QStringLiteral("ROTA")).toString() == QStringLiteral("0"))
                       clase = QStringLiteral("SSD");
                   else
                       clase = QStringLiteral("Disco duro");
                   const QString modelo = d.value(QStringLiteral("MODEL")).toString();
                   lista << QVariantMap{{QStringLiteral("nombre"), modelo.isEmpty() ? QStringLiteral("/dev/") + nombre : modelo},
                                        {QStringLiteral("dispositivo"), QStringLiteral("/dev/") + nombre},
                                        {QStringLiteral("clase"), clase},
                                        {QStringLiteral("tamano"), d.value(QStringLiteral("SIZE")).toDouble()}};
               }
               m_discos = lista;
               emit cambiado();
           }, 10000);
}

// ---------------------------------------------------------------- utilidades

bool Sistema::instalado(const QString &programa) const
{
    return !QStandardPaths::findExecutable(programa).isEmpty();
}

bool Sistema::abrir(const QString &programa)
{
    static const QStringList permitidos{
        QStringLiteral("system-config-printer"), QStringLiteral("simple-scan"), QStringLiteral("gnome-disks"),
        QStringLiteral("btrfs-assistant"), QStringLiteral("timeshift-launcher"), QStringLiteral("fcitx5-configtool"),
        QStringLiteral("nm-connection-editor"), QStringLiteral("orca")};
    if (!permitidos.contains(programa))
        return false;
    if (!instalado(programa)) {
        avisar(QStringLiteral("«%1» no está instalado.").arg(programa));
        return false;
    }
    QStringList args;
    if (programa == QStringLiteral("orca"))
        args << QStringLiteral("--setup");
    return QProcess::startDetached(programa, args);
}

QString Sistema::tamanoLegible(double bytes) const
{
    return QLocale(QLocale::Spanish).formattedDataSize(qint64(bytes), 1, QLocale::DataSizeSIFormat);
}
