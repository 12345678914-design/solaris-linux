#include "Usuarios.h"

#include <QFile>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QTimer>

#include <algorithm>
#include <memory>

namespace {
// TITAN_USUARIOS_SOCK solo sirve para pruebas (servicio falso sin root): el
// cliente no gana nada con cambiarlo, la autorizacion la hace el servicio.
QString rutaSocket()
{
    return qEnvironmentVariable("TITAN_USUARIOS_SOCK", QStringLiteral("/run/titan-usuarios.sock"));
}

bool shellDeEntrada(const QString &shell)
{
    return !shell.endsWith(QStringLiteral("nologin")) && !shell.endsWith(QStringLiteral("/false"));
}
}

Usuarios::Usuarios(QObject *parent) : QObject(parent)
{
    recargar();
}

bool Usuarios::gestionDisponible() const
{
    return QFile::exists(rutaSocket());
}

void Usuarios::recargar()
{
    // Grupos: nombre -> (gid, miembros)
    QHash<QString, QStringList> miembros;
    QHash<QString, int> gids;
    QHash<int, QString> nombrePorGid;
    QFile fg(QStringLiteral("/etc/group"));
    if (fg.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const auto lineas = QString::fromUtf8(fg.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString &l : lineas) {
            const QStringList c = l.split(QLatin1Char(':'));
            if (c.size() < 4)
                continue;
            const int gid = c[2].toInt();
            gids.insert(c[0], gid);
            nombrePorGid.insert(gid, c[0]);
            miembros.insert(c[0], c[3].split(QLatin1Char(','), Qt::SkipEmptyParts));
        }
    }

    QVariantList usuarios;
    QStringList admins;
    QHash<QString, QStringList> gruposDe;
    QFile fp(QStringLiteral("/etc/passwd"));
    if (fp.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const auto lineas = QString::fromUtf8(fp.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString &l : lineas) {
            const QStringList c = l.split(QLatin1Char(':'));
            if (c.size() < 7)
                continue;
            const int uid = c[2].toInt();
            if (uid < 1000 || uid >= 60000 || !shellDeEntrada(c[6]))
                continue;
            const QString usuario = c[0];
            QStringList suyos;
            const QString primario = nombrePorGid.value(c[3].toInt());
            if (!primario.isEmpty())
                suyos << primario;
            for (auto it = miembros.cbegin(); it != miembros.cend(); ++it) {
                if (it.value().contains(usuario) && !suyos.contains(it.key()))
                    suyos << it.key();
            }
            std::sort(suyos.begin(), suyos.end());
            gruposDe.insert(usuario, suyos);
            const bool esAdmin = suyos.contains(QStringLiteral("wheel"));
            if (esAdmin)
                admins << usuario;
            QString nombre = c[4].section(QLatin1Char(','), 0, 0).trimmed();
            usuarios << QVariantMap{
                {QStringLiteral("usuario"), usuario},
                {QStringLiteral("nombre"), nombre.isEmpty() ? usuario : nombre},
                {QStringLiteral("uid"), uid},
                {QStringLiteral("esAdmin"), esAdmin},
                {QStringLiteral("grupos"), suyos},
            };
        }
    }
    std::sort(usuarios.begin(), usuarios.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("uid")).toInt() < b.toMap().value(QStringLiteral("uid")).toInt();
    });

    // Grupos que interesan a una persona: los creados (gid 1000-59999) y
    // wheel (administradores). Los miembros incluyen a quien lo tiene como
    // grupo primario.
    QVariantList grupos;
    QStringList nombres = gids.keys();
    std::sort(nombres.begin(), nombres.end());
    for (const QString &g : nombres) {
        const int gid = gids.value(g);
        if (g != QStringLiteral("wheel") && (gid < 1000 || gid >= 60000))
            continue;
        QStringList m;
        for (auto it = gruposDe.cbegin(); it != gruposDe.cend(); ++it) {
            if (it.value().contains(g))
                m << it.key();
        }
        std::sort(m.begin(), m.end());
        grupos << QVariantMap{
            {QStringLiteral("grupo"), g},
            {QStringLiteral("gid"), gid},
            {QStringLiteral("miembros"), m},
        };
    }

    m_usuarios = usuarios;
    m_grupos = grupos;
    m_admins = admins;
    emit cambiado();
}

void Usuarios::setOcupado(bool o)
{
    if (m_ocupado == o)
        return;
    m_ocupado = o;
    emit ocupadoCambiado();
}

void Usuarios::enviar(QVariantMap peticion, const QString &admin, const QString &clave)
{
    const QString accion = peticion.value(QStringLiteral("accion")).toString();
    if (m_ocupado) {
        emit terminado(accion, false, QStringLiteral("Espera a que termine la operacion anterior"));
        return;
    }
    if (!gestionDisponible()) {
        emit terminado(accion, false, QStringLiteral("El servicio de usuarios no esta disponible en este sistema"));
        return;
    }
    peticion.insert(QStringLiteral("admin"), admin);
    peticion.insert(QStringLiteral("clave"), clave);

    setOcupado(true);
    auto *s = new QLocalSocket(this);
    auto *buffer = new QByteArray;
    auto acabado = std::make_shared<bool>(false);
    auto terminar = [this, s, buffer, accion, acabado](bool ok, const QString &error) {
        if (*acabado)
            return;
        *acabado = true;
        s->disconnect(this);
        s->abort();
        s->deleteLater();
        delete buffer;
        setOcupado(false);
        if (ok)
            recargar();
        emit terminado(accion, ok, error);
    };

    connect(s, &QLocalSocket::connected, this, [s, peticion]() {
        QByteArray linea = QJsonDocument(QJsonObject::fromVariantMap(peticion)).toJson(QJsonDocument::Compact);
        linea.append('\n');
        s->write(linea);
        linea.fill('\0');
    });
    connect(s, &QLocalSocket::readyRead, this, [s, buffer, terminar]() {
        buffer->append(s->readAll());
        const int fin = buffer->indexOf('\n');
        if (fin < 0)
            return;
        const QJsonObject r = QJsonDocument::fromJson(buffer->left(fin)).object();
        terminar(r.value(QStringLiteral("ok")).toBool(),
                 r.value(QStringLiteral("error")).toString(QStringLiteral("Respuesta no valida del servicio")));
    });
    connect(s, &QLocalSocket::errorOccurred, this, [terminar](QLocalSocket::LocalSocketError e) {
        if (e != QLocalSocket::PeerClosedError)
            terminar(false, QStringLiteral("No se pudo hablar con el servicio de usuarios"));
    });
    connect(s, &QLocalSocket::disconnected, this, [terminar]() {
        terminar(false, QStringLiteral("El servicio de usuarios cerro la conexion"));
    });
    QTimer::singleShot(90000, s, [terminar]() {
        terminar(false, QStringLiteral("El servicio de usuarios no responde"));
    });
    s->connectToServer(rutaSocket());
}

void Usuarios::iniciarAdmin(const QString &admin, const QString &clave)
{
    m_adminPendiente = admin;
    m_clavePendiente = clave;
    // Al verificar, si sale bien, el administrador queda activo.
    auto *conexion = new QMetaObject::Connection;
    *conexion = connect(this, &Usuarios::terminado, this,
                        [this, conexion](const QString &accion, bool ok, const QString &) {
        if (accion != QStringLiteral("verificar"))
            return;
        disconnect(*conexion);
        delete conexion;
        if (ok) {
            m_adminActivo = m_adminPendiente;
            m_claveAdmin = m_clavePendiente;
            emit adminActivoCambiado();
        }
        m_clavePendiente.fill(QLatin1Char('\0'));
        m_clavePendiente.clear();
        m_adminPendiente.clear();
    });
    enviar({{QStringLiteral("accion"), QStringLiteral("verificar")}}, admin, clave);
}

void Usuarios::cerrarAdmin()
{
    m_claveAdmin.fill(QLatin1Char('\0'));
    m_claveAdmin.clear();
    if (!m_adminActivo.isEmpty()) {
        m_adminActivo.clear();
        emit adminActivoCambiado();
    }
}

void Usuarios::crearUsuario(const QString &usuario, const QString &nombre, const QString &clave,
                            bool esAdmin, const QStringList &grupos)
{
    enviar({{QStringLiteral("accion"), QStringLiteral("crear-usuario")},
            {QStringLiteral("usuario"), usuario.trimmed()},
            {QStringLiteral("nombre"), nombre.trimmed()},
            {QStringLiteral("claveNueva"), clave},
            {QStringLiteral("esAdmin"), esAdmin},
            {QStringLiteral("grupos"), grupos}},
           m_adminActivo, m_claveAdmin);
}

void Usuarios::crearGrupo(const QString &grupo)
{
    enviar({{QStringLiteral("accion"), QStringLiteral("crear-grupo")},
            {QStringLiteral("grupo"), grupo.trimmed()}},
           m_adminActivo, m_claveAdmin);
}

void Usuarios::agregarAGrupo(const QString &usuario, const QString &grupo)
{
    enviar({{QStringLiteral("accion"), QStringLiteral("agregar-a-grupo")},
            {QStringLiteral("usuario"), usuario}, {QStringLiteral("grupo"), grupo}},
           m_adminActivo, m_claveAdmin);
}

void Usuarios::quitarDeGrupo(const QString &usuario, const QString &grupo)
{
    enviar({{QStringLiteral("accion"), QStringLiteral("quitar-de-grupo")},
            {QStringLiteral("usuario"), usuario}, {QStringLiteral("grupo"), grupo}},
           m_adminActivo, m_claveAdmin);
}

void Usuarios::cambiarClave(const QString &usuario, const QString &clave)
{
    enviar({{QStringLiteral("accion"), QStringLiteral("cambiar-clave")},
            {QStringLiteral("usuario"), usuario}, {QStringLiteral("claveNueva"), clave}},
           m_adminActivo, m_claveAdmin);
}
