#include "Agente.h"

#include <QDebug>
#include <QFileInfo>
#include <pwd.h>
#include <unistd.h>

namespace {

// Nombre que se ensena para una identidad de polkit (unix-user:1000).
QVariantMap describir(const PolkitQt1::Identity &id)
{
    QVariantMap m;
    const QString s = id.toString();
    m[QStringLiteral("id")] = s;
    if (s.startsWith(QStringLiteral("unix-user:"))) {
        bool ok = false;
        const uid_t uid = s.mid(10).toUInt(&ok);
        struct passwd *pw = ok ? getpwuid(uid) : nullptr;
        const QString login = pw ? QString::fromLocal8Bit(pw->pw_name) : s.mid(10);
        QString nombre = pw ? QString::fromLocal8Bit(pw->pw_gecos).section(QLatin1Char(','), 0, 0).trimmed() : QString();
        if (uid == 0)
            nombre = QStringLiteral("Administrador del sistema");
        if (nombre.isEmpty())
            nombre = login;
        m[QStringLiteral("login")] = login;
        m[QStringLiteral("nombre")] = nombre;
        m[QStringLiteral("uid")] = static_cast<int>(uid);
        m[QStringLiteral("inicial")] = nombre.left(1).toUpper();
    } else {
        m[QStringLiteral("login")] = s;
        m[QStringLiteral("nombre")] = s;
        m[QStringLiteral("uid")] = -1;
        m[QStringLiteral("inicial")] = QStringLiteral("?");
    }
    return m;
}

// PAM pregunta "Password: " o "Contraseña: "; en la ventana basta "Contraseña".
QString peticionLegible(QString p)
{
    p = p.trimmed();
    if (p.endsWith(QLatin1Char(':')))
        p.chop(1);
    if (p.compare(QStringLiteral("Password"), Qt::CaseInsensitive) == 0)
        p = QStringLiteral("Contraseña");
    return p;
}

} // namespace

Agente::Agente(QObject *parent)
    : PolkitQt1::Agent::Listener(parent)
{
}

void Agente::initiateAuthentication(const QString &actionId,
                                    const QString &message,
                                    const QString &iconName,
                                    const PolkitQt1::Details &details,
                                    const QString &cookie,
                                    const PolkitQt1::Identity::List &identities,
                                    PolkitQt1::Agent::AsyncResult *result)
{
    Q_UNUSED(iconName)
    if (m_activo) {
        // Una peticion a la vez, como los agentes de GNOME y KDE.
        result->setError(QStringLiteral("Ya hay otra petición de contraseña abierta"));
        result->setCompleted();
        return;
    }

    m_accion = actionId;
    m_mensaje = message.isEmpty()
        ? QStringLiteral("Una aplicación quiere hacer cambios que necesitan permisos de administrador.")
        : message;
    // pkexec dice que programa va a ejecutar: se ensena debajo, pequeno.
    m_programa = details.lookup(QStringLiteral("command_line"));
    if (m_programa.isEmpty())
        m_programa = details.lookup(QStringLiteral("program"));
    m_cookie = cookie;
    m_identidades = identities;
    m_resultado = result;
    m_fallos = 0;
    m_cancelado = false;
    m_error.clear();
    m_aviso.clear();

    m_usuarios.clear();
    m_usuarioActual = 0;
    const uid_t yo = getuid();
    for (int i = 0; i < identities.size(); ++i) {
        const QVariantMap u = describir(identities.at(i));
        if (u.value(QStringLiteral("uid")).toInt() == static_cast<int>(yo))
            m_usuarioActual = i;
        m_usuarios.append(u);
    }

    m_activo = true;
    emit cambiado();
    empezarSesion();
}

void Agente::empezarSesion()
{
    if (m_sesion) {
        m_sesion->disconnect(this);
        m_sesion->cancel();
        m_sesion->deleteLater();
    }
    if (m_identidades.isEmpty()) {
        m_error = QStringLiteral("No hay ninguna cuenta de administrador en este equipo.");
        emit cambiado();
        return;
    }
    m_peticion = QStringLiteral("Contraseña");
    m_eco = false;
    m_esperandoRespuesta = false;
    emit cambiado();

    auto *s = new PolkitQt1::Agent::Session(m_identidades.at(m_usuarioActual), m_cookie, m_resultado, this);
    m_sesion = s;
    connect(s, &PolkitQt1::Agent::Session::request, this, [this](const QString &texto, bool eco) {
        m_peticion = peticionLegible(texto);
        m_eco = eco;
        m_esperandoRespuesta = true;
        emit cambiado();
    });
    connect(s, &PolkitQt1::Agent::Session::showError, this, [this](const QString &texto) {
        m_error = texto;
        emit cambiado();
    });
    connect(s, &PolkitQt1::Agent::Session::showInfo, this, [this](const QString &texto) {
        // pam_fprintd: "Pon el dedo en el lector..."
        m_aviso = texto;
        emit cambiado();
    });
    connect(s, &PolkitQt1::Agent::Session::completed, this, &Agente::alCompletar);
    s->initiate();
}

void Agente::alCompletar(bool autorizado)
{
    m_esperandoRespuesta = false;
    if (autorizado || m_cancelado) {
        terminar();
        return;
    }
    // Contrasena mal: se queda la ventana y se vuelve a preguntar.
    ++m_fallos;
    m_error = QStringLiteral("La contraseña no es correcta. Inténtalo de nuevo.");
    m_aviso.clear();
    emit cambiado();
    empezarSesion();
}

void Agente::terminar()
{
    // Se completa siempre: polkitd sabe por su lado si la identidad quedo
    // autenticada (igual que hacen polkit-gnome y polkit-kde-agent).
    if (m_resultado) {
        m_resultado->setCompleted();
        m_resultado = nullptr;
    }
    if (m_sesion) {
        m_sesion->disconnect(this);
        m_sesion->deleteLater();
    }
    m_activo = false;
    m_esperandoRespuesta = false;
    m_peticion.clear();
    m_error.clear();
    m_aviso.clear();
    emit cambiado();
}

void Agente::responder(const QString &texto)
{
    if (!m_sesion || !m_esperandoRespuesta)
        return;
    m_esperandoRespuesta = false;
    m_error.clear();
    emit cambiado();
    m_sesion->setResponse(texto);
}

void Agente::cancelar()
{
    if (!m_activo)
        return;
    m_cancelado = true;
    if (m_sesion)
        m_sesion->cancel();
    terminar();
}

void Agente::elegirUsuario(int indice)
{
    if (indice < 0 || indice >= m_identidades.size() || indice == m_usuarioActual)
        return;
    m_usuarioActual = indice;
    m_error.clear();
    emit cambiado();
    empezarSesion();
}

bool Agente::initiateAuthenticationFinish()
{
    return true;
}

void Agente::cancelAuthentication()
{
    // polkitd lo cancela (el programa que pidio permiso se ha cerrado).
    m_cancelado = true;
    if (m_sesion)
        m_sesion->cancel();
    terminar();
}

void Agente::demostracion()
{
    m_accion = QStringLiteral("org.freedesktop.packagekit.package-install");
    m_mensaje = QStringLiteral("Para instalar o quitar programas hace falta autenticarse.");
    m_programa = QStringLiteral("/usr/bin/pacman -S firefox");
    m_usuarios.clear();
    QVariantMap u;
    u[QStringLiteral("login")] = QStringLiteral("ana");
    u[QStringLiteral("nombre")] = QStringLiteral("Ana Quispe");
    u[QStringLiteral("inicial")] = QStringLiteral("A");
    u[QStringLiteral("uid")] = 1000;
    m_usuarios.append(u);
    m_usuarioActual = 0;
    m_peticion = QStringLiteral("Contraseña");
    m_esperandoRespuesta = true;
    m_error = qEnvironmentVariableIsSet("TITAN_POLKIT_DEMO_ERROR")
        ? QStringLiteral("La contraseña no es correcta. Inténtalo de nuevo.") : QString();
    m_activo = true;
    emit cambiado();
}
