#include "config.h"

#include <QCoreApplication>
#include <QFile>
#include <QStringList>
#include <QTextStream>

namespace {

QString sinComillas(const QString &texto)
{
    QString valor = texto.trimmed();
    if (valor.size() >= 2) {
        const QChar primero = valor.front();
        const QChar ultimo = valor.back();
        if ((primero == '"' && ultimo == '"') ||
            (primero == '\'' && ultimo == '\'')) {
            valor = valor.mid(1, valor.size() - 2);
        }
    }
    return valor;
}

} // namespace

Config::Config()
{
    cargar();
}

const Config &Config::instancia()
{
    static const Config configuracion;
    return configuracion;
}

void Config::cargar()
{
    QStringList candidatos;
    const QString porEntorno = QString::fromLocal8Bit(qgetenv("TITAN_CONFIG"));
    if (!porEntorno.isEmpty()) {
        candidatos << porEntorno;
    }
    candidatos << QStringLiteral("/etc/titan/base.conf");

    const QString aplicacion = QCoreApplication::applicationDirPath();
    const QStringList relativas = {
        QStringLiteral("/config/titan-base.conf"),
        QStringLiteral("/../config/titan-base.conf"),
        QStringLiteral("/../../config/titan-base.conf"),
        QStringLiteral("/../../../config/titan-base.conf"),
    };
    for (const QString &relativa : relativas) {
        candidatos << aplicacion + relativa;
    }

    for (const QString &ruta : candidatos) {
        QFile fichero(ruta);
        if (!fichero.open(QIODevice::ReadOnly | QIODevice::Text)) {
            continue;
        }
        QTextStream entrada(&fichero);
        while (!entrada.atEnd()) {
            const QString linea = entrada.readLine().trimmed();
            if (linea.isEmpty() || linea.startsWith('#')) {
                continue;
            }
            const int igual = linea.indexOf('=');
            if (igual <= 0) {
                continue;
            }
            QString clave = linea.left(igual).trimmed();
            if (clave.startsWith(QStringLiteral("export "))) {
                clave = clave.mid(7).trimmed();
            }
            m_valores.insert(clave, sinComillas(linea.mid(igual + 1)));
        }
        m_ruta = ruta;
        break;
    }
}

QString Config::valor(const QString &clave, const QString &defecto) const
{
    const QString leido = m_valores.value(clave);
    return leido.isEmpty() ? defecto : leido;
}

QString Config::soNombre() const
{
    return valor(QStringLiteral("TITAN_SO_NOMBRE"),
                 QStringLiteral("Titan Linux"));
}

QString Config::soVersion() const
{
    return valor(QStringLiteral("TITAN_SO_VERSION"), QStringLiteral("0.2.0"));
}

QString Config::soId() const
{
    return valor(QStringLiteral("TITAN_SO_ID"), QStringLiteral("titan"));
}

QString Config::usuario() const
{
    return valor(QStringLiteral("TITAN_USUARIO"), QStringLiteral("titan"));
}

QString Config::hostname() const
{
    return valor(QStringLiteral("TITAN_HOSTNAME"), QStringLiteral("titan"));
}

QString Config::terminal() const
{
    return valor(QStringLiteral("TITAN_TERMINAL"), QStringLiteral("kitty"));
}

QString Config::explorador() const
{
    return valor(QStringLiteral("TITAN_EXPLORADOR"),
                 QStringLiteral("pcmanfm-qt"));
}

QString Config::escritorio() const
{
    return valor(QStringLiteral("TITAN_ESCRITORIO"), QStringLiteral("labwc"));
}

QString Config::apagar() const
{
    return valor(QStringLiteral("TITAN_APAGAR"),
                 QStringLiteral("systemctl poweroff"));
}

QString Config::reiniciar() const
{
    return valor(QStringLiteral("TITAN_REINICIAR"),
                 QStringLiteral("systemctl reboot"));
}

QString Config::fondoColor1() const
{
    return valor(QStringLiteral("TITAN_FONDO_COLOR1"),
                 QStringLiteral("#101a33"));
}

QString Config::fondoColor2() const
{
    return valor(QStringLiteral("TITAN_FONDO_COLOR2"),
                 QStringLiteral("#2a1a4a"));
}

int Config::barraAlto() const
{
    bool bien = false;
    const int alto = valor(QStringLiteral("TITAN_BARRA_ALTO"),
                           QStringLiteral("56")).toInt(&bien);
    return bien && alto >= 32 && alto <= 200 ? alto : 56;
}

QString Config::barraFondo() const
{
    return valor(QStringLiteral("TITAN_BARRA_FONDO"),
                 QStringLiteral("#0b1020"));
}

double Config::barraAlfa() const
{
    bool bien = false;
    const double alfa = valor(QStringLiteral("TITAN_BARRA_ALFA"),
                              QStringLiteral("0.92")).toDouble(&bien);
    return bien && alfa >= 0.0 && alfa <= 1.0 ? alfa : 0.92;
}

QString Config::barraAcento() const
{
    return valor(QStringLiteral("TITAN_BARRA_ACENTO"),
                 QStringLiteral("#4fc4ff"));
}

QString Config::inicioTexto() const
{
    return valor(QStringLiteral("TITAN_INICIO_TEXTO"),
                 QStringLiteral("Inicio"));
}

int Config::centroAncho() const
{
    bool bien = false;
    const int ancho = valor(QStringLiteral("TITAN_CENTRO_ANCHO"),
                            QStringLiteral("900")).toInt(&bien);
    return bien && ancho >= 320 && ancho <= 2400 ? ancho : 900;
}

int Config::centroAlto() const
{
    bool bien = false;
    const int alto = valor(QStringLiteral("TITAN_CENTRO_ALTO"),
                           QStringLiteral("620")).toInt(&bien);
    return bien && alto >= 240 && alto <= 1600 ? alto : 620;
}

int Config::centroColumnas() const
{
    bool bien = false;
    const int columnas = valor(QStringLiteral("TITAN_CENTRO_COLUMNAS"),
                               QStringLiteral("5")).toInt(&bien);
    return bien && columnas >= 2 && columnas <= 10 ? columnas : 5;
}

double Config::centroOscuridad() const
{
    bool bien = false;
    const double oscuridad = valor(QStringLiteral("TITAN_CENTRO_OSCURIDAD"),
                                   QStringLiteral("0.55")).toDouble(&bien);
    return bien && oscuridad >= 0.0 && oscuridad <= 0.9 ? oscuridad : 0.55;
}

QString Config::rutaCargada() const
{
    return m_ruta;
}
