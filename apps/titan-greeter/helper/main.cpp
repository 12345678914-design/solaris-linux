// titan-usuarios-helper: gestion de usuarios y grupos para Inti OS.
//
// Lo arranca systemd como root por cada conexion a /run/titan-usuarios.sock
// (titan-usuarios.socket, Accept=yes): la peticion llega por stdin y la
// respuesta sale por stdout, una linea JSON cada una.
//
// Peticion:  {"admin":"ana","clave":"...","accion":"crear-usuario", ...}
// Respuesta: {"ok":true} o {"ok":false,"error":"texto para el usuario"}
//
// Cada peticion se autentica entera: la contrasena del administrador se
// comprueba con PAM (servicio titan-usuarios -> system-auth, con faillock) y
// el administrador tiene que estar en el grupo wheel. Los nombres se validan
// con la misma regla que useradd por defecto y los programas se lanzan sin
// shell, con la lista de argumentos.
//
// Acciones:
//   verificar                                   solo comprueba al administrador
//   crear-usuario  usuario nombre claveNueva esAdmin grupos[]
//   crear-grupo    grupo
//   agregar-a-grupo / quitar-de-grupo  usuario grupo
//   cambiar-clave  usuario claveNueva
//   cambiar-nombre usuario nombre
//   borrar-usuario usuario borrarCarpeta       no la propia ni con sesion abierta
//
// Sin administrador (cada persona con su propia contrasena):
//   cambiar-mi-clave usuario claveActual claveNueva
//     'usuario' tiene que ser quien esta al otro lado del socket (SO_PEERCRED):
//     nadie puede cambiar la contrasena de otra cuenta por aqui.

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QProcess>
#include <QRegularExpression>
#include <QThread>

#include <security/pam_appl.h>
#include <sys/socket.h>
#include <grp.h>
#include <pwd.h>
#include <unistd.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>

namespace {

// Grupos con los que se crea cualquier cuenta (si existen en el sistema),
// los mismos que pone el instalador. 'wheel' solo para administradores.
const char *const kGruposBase[] = {"audio", "video", "storage", "input", "render", "network", "power"};

struct DatosPam {
    std::string clave;
};

int conversacion(int n, const struct pam_message **msgs, struct pam_response **resp, void *datos)
{
    auto *d = static_cast<DatosPam *>(datos);
    auto *r = static_cast<pam_response *>(calloc(n, sizeof(pam_response)));
    if (!r)
        return PAM_BUF_ERR;
    for (int i = 0; i < n; ++i) {
        if (msgs[i]->msg_style == PAM_PROMPT_ECHO_OFF || msgs[i]->msg_style == PAM_PROMPT_ECHO_ON)
            r[i].resp = strdup(d->clave.c_str());
    }
    *resp = r;
    return PAM_SUCCESS;
}

bool autenticar(const QString &usuario, const QString &clave, bool aceptarCaducada = false)
{
    DatosPam datos{clave.toStdString()};
    pam_conv conv{conversacion, &datos};
    pam_handle_t *pamh = nullptr;
    const std::string u = usuario.toStdString();
    if (pam_start("titan-usuarios", u.c_str(), &conv, &pamh) != PAM_SUCCESS)
        return false;
    int r = pam_authenticate(pamh, PAM_DISALLOW_NULL_AUTHTOK);
    if (r == PAM_SUCCESS) {
        r = pam_acct_mgmt(pamh, 0);
        // Contrasena caducada: justo lo que se quiere arreglar al cambiarla.
        if (aceptarCaducada && r == PAM_NEW_AUTHTOK_REQD)
            r = PAM_SUCCESS;
    }
    pam_end(pamh, r);
    datos.clave.assign(datos.clave.size(), '\0');
    return r == PAM_SUCCESS;
}

bool existeGrupo(const QString &g)
{
    return getgrnam(g.toLocal8Bit().constData()) != nullptr;
}

bool existeUsuario(const QString &u)
{
    return getpwnam(u.toLocal8Bit().constData()) != nullptr;
}

bool esDeWheel(const QString &usuario)
{
    struct passwd *pw = getpwnam(usuario.toLocal8Bit().constData());
    struct group *gr = getgrnam("wheel");
    if (!pw || !gr)
        return false;
    if (pw->pw_gid == gr->gr_gid)
        return true;
    for (char **m = gr->gr_mem; m && *m; ++m) {
        if (usuario == QString::fromLocal8Bit(*m))
            return true;
    }
    return false;
}

bool nombreValido(const QString &n)
{
    static const QRegularExpression re(QStringLiteral("^[a-z_][a-z0-9_-]{0,31}$"));
    return re.match(n).hasMatch();
}

bool claveValida(const QString &c)
{
    return !c.isEmpty() && c.size() <= 512 && !c.contains(QLatin1Char('\n')) && !c.contains(QLatin1Char('\r'));
}

QJsonObject error(const QString &texto)
{
    return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), texto}};
}

QJsonObject exito()
{
    return {{QStringLiteral("ok"), true}};
}

// Lanza un programa sin shell; devuelve la salida de error si falla.
bool ejecutar(const QString &programa, const QStringList &args, QString *fallo, const QByteArray &entrada = {})
{
    QProcess p;
    p.start(programa, args);
    if (!p.waitForStarted(5000)) {
        *fallo = QStringLiteral("No se pudo ejecutar ") + programa;
        return false;
    }
    if (!entrada.isEmpty())
        p.write(entrada);
    p.closeWriteChannel();
    p.waitForFinished(60000);
    if (p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) {
        QString err = QString::fromLocal8Bit(p.readAllStandardError()).trimmed();
        *fallo = err.isEmpty() ? programa + QStringLiteral(" fallo (codigo ") + QString::number(p.exitCode()) + QLatin1Char(')') : err;
        return false;
    }
    return true;
}

QJsonObject crearUsuario(const QJsonObject &pet)
{
    const QString usuario = pet.value(QStringLiteral("usuario")).toString().trimmed();
    const QString nombre = pet.value(QStringLiteral("nombre")).toString().trimmed();
    const QString clave = pet.value(QStringLiteral("claveNueva")).toString();
    const bool esAdmin = pet.value(QStringLiteral("esAdmin")).toBool();

    if (!nombreValido(usuario))
        return error(QStringLiteral("Nombre de usuario no valido: minusculas, numeros, '-' o '_', empezando por letra"));
    if (existeUsuario(usuario))
        return error(QStringLiteral("Ya existe el usuario ") + usuario);
    if (nombre.contains(QLatin1Char(':')) || nombre.contains(QLatin1Char('\n')) || nombre.size() > 120)
        return error(QStringLiteral("El nombre completo no puede tener ':' ni saltos de linea"));
    if (!claveValida(clave))
        return error(QStringLiteral("La contrasena no puede estar vacia"));

    QStringList grupos;
    for (const char *g : kGruposBase) {
        if (existeGrupo(QString::fromLatin1(g)))
            grupos << QString::fromLatin1(g);
    }
    if (esAdmin)
        grupos << QStringLiteral("wheel");
    for (const QJsonValue &v : pet.value(QStringLiteral("grupos")).toArray()) {
        const QString g = v.toString();
        if (!nombreValido(g) || !existeGrupo(g))
            return error(QStringLiteral("No existe el grupo ") + g);
        if (g == QStringLiteral("wheel") && !esAdmin)
            continue;
        if (!grupos.contains(g))
            grupos << g;
    }

    QStringList args = {QStringLiteral("-m"), QStringLiteral("-s"), QStringLiteral("/bin/bash"),
                        QStringLiteral("-G"), grupos.join(QLatin1Char(','))};
    if (!nombre.isEmpty())
        args << QStringLiteral("-c") << nombre;
    args << QStringLiteral("--") << usuario;

    QString fallo;
    if (!ejecutar(QStringLiteral("/usr/bin/useradd"), args, &fallo))
        return error(QStringLiteral("No se pudo crear el usuario: ") + fallo);
    if (!ejecutar(QStringLiteral("/usr/bin/chpasswd"), {}, &fallo, (usuario + QLatin1Char(':') + clave + QLatin1Char('\n')).toUtf8())) {
        // Sin contrasena la cuenta no serviria para entrar: se deshace.
        QString ignorar;
        ejecutar(QStringLiteral("/usr/bin/userdel"), {QStringLiteral("-r"), QStringLiteral("--"), usuario}, &ignorar);
        return error(QStringLiteral("No se pudo poner la contrasena: ") + fallo);
    }
    return exito();
}

QJsonObject crearGrupo(const QJsonObject &pet)
{
    const QString grupo = pet.value(QStringLiteral("grupo")).toString().trimmed();
    if (!nombreValido(grupo))
        return error(QStringLiteral("Nombre de grupo no valido: minusculas, numeros, '-' o '_', empezando por letra"));
    if (existeGrupo(grupo))
        return error(QStringLiteral("Ya existe el grupo ") + grupo);
    QString fallo;
    if (!ejecutar(QStringLiteral("/usr/bin/groupadd"), {QStringLiteral("--"), grupo}, &fallo))
        return error(QStringLiteral("No se pudo crear el grupo: ") + fallo);
    return exito();
}

QJsonObject cambiarMiembro(const QJsonObject &pet, bool agregar, const QString &admin)
{
    const QString usuario = pet.value(QStringLiteral("usuario")).toString();
    const QString grupo = pet.value(QStringLiteral("grupo")).toString();
    if (!nombreValido(usuario) || !existeUsuario(usuario))
        return error(QStringLiteral("No existe el usuario ") + usuario);
    if (!nombreValido(grupo) || !existeGrupo(grupo))
        return error(QStringLiteral("No existe el grupo ") + grupo);
    if (!agregar && grupo == QStringLiteral("wheel") && usuario == admin)
        return error(QStringLiteral("No puedes quitarte a ti mismo de administradores"));
    QString fallo;
    if (!ejecutar(QStringLiteral("/usr/bin/gpasswd"),
                  {agregar ? QStringLiteral("-a") : QStringLiteral("-d"), usuario, grupo}, &fallo))
        return error(fallo);
    return exito();
}

QJsonObject cambiarClave(const QJsonObject &pet)
{
    const QString usuario = pet.value(QStringLiteral("usuario")).toString();
    const QString clave = pet.value(QStringLiteral("claveNueva")).toString();
    if (!nombreValido(usuario) || !existeUsuario(usuario))
        return error(QStringLiteral("No existe el usuario ") + usuario);
    struct passwd *pw = getpwnam(usuario.toLocal8Bit().constData());
    if (!pw || pw->pw_uid < 1000)
        return error(QStringLiteral("Solo se puede cambiar la contrasena de cuentas de personas"));
    if (!claveValida(clave))
        return error(QStringLiteral("La contrasena no puede estar vacia"));
    QString fallo;
    if (!ejecutar(QStringLiteral("/usr/bin/chpasswd"), {}, &fallo, (usuario + QLatin1Char(':') + clave + QLatin1Char('\n')).toUtf8()))
        return error(fallo);
    return exito();
}

// Quien esta al otro lado del socket (stdin, por Accept=yes).
bool uidQuePregunta(uid_t *uid)
{
    struct ucred cred{};
    socklen_t largo = sizeof(cred);
    if (getsockopt(STDIN_FILENO, SOL_SOCKET, SO_PEERCRED, &cred, &largo) != 0 || largo != sizeof(cred))
        return false;
    *uid = cred.uid;
    return true;
}

QJsonObject cambiarMiClave(const QJsonObject &pet)
{
    const QString usuario = pet.value(QStringLiteral("usuario")).toString();
    const QString actual = pet.value(QStringLiteral("claveActual")).toString();
    const QString nueva = pet.value(QStringLiteral("claveNueva")).toString();
    uid_t uid = 0;
    if (!uidQuePregunta(&uid))
        return error(QStringLiteral("No se pudo saber quien hace la peticion"));
    struct passwd *pw = getpwuid(uid);
    if (!pw || uid < 1000 || !nombreValido(usuario) || usuario != QString::fromLocal8Bit(pw->pw_name))
        return error(QStringLiteral("Solo puedes cambiar la contrasena de tu propia cuenta"));
    if (!claveValida(nueva))
        return error(QStringLiteral("La contrasena nueva no puede estar vacia"));
    if (!autenticar(usuario, actual, true)) {
        QThread::sleep(2);
        return error(QStringLiteral("La contrasena actual no es correcta"));
    }
    if (actual == nueva)
        return error(QStringLiteral("La contrasena nueva es igual a la actual"));
    QString fallo;
    if (!ejecutar(QStringLiteral("/usr/bin/chpasswd"), {}, &fallo, (usuario + QLatin1Char(':') + nueva + QLatin1Char('\n')).toUtf8()))
        return error(fallo);
    return exito();
}

QJsonObject cambiarNombre(const QJsonObject &pet)
{
    const QString usuario = pet.value(QStringLiteral("usuario")).toString();
    const QString nombre = pet.value(QStringLiteral("nombre")).toString().trimmed();
    if (!nombreValido(usuario) || !existeUsuario(usuario))
        return error(QStringLiteral("No existe el usuario ") + usuario);
    if (nombre.contains(QLatin1Char(':')) || nombre.contains(QLatin1Char(',')) || nombre.contains(QLatin1Char('\n')) || nombre.size() > 120)
        return error(QStringLiteral("El nombre no puede tener ':', ',' ni saltos de linea"));
    QString fallo;
    if (!ejecutar(QStringLiteral("/usr/bin/usermod"), {QStringLiteral("-c"), nombre, QStringLiteral("--"), usuario}, &fallo))
        return error(fallo);
    return exito();
}

QJsonObject borrarUsuario(const QJsonObject &pet, const QString &admin)
{
    const QString usuario = pet.value(QStringLiteral("usuario")).toString();
    const bool carpeta = pet.value(QStringLiteral("borrarCarpeta")).toBool();
    if (!nombreValido(usuario) || !existeUsuario(usuario))
        return error(QStringLiteral("No existe el usuario ") + usuario);
    struct passwd *pw = getpwnam(usuario.toLocal8Bit().constData());
    if (!pw || pw->pw_uid < 1000 || pw->pw_uid >= 60000)
        return error(QStringLiteral("Solo se pueden borrar cuentas de personas"));
    if (usuario == admin)
        return error(QStringLiteral("No puedes borrar tu propia cuenta"));

    // Con la sesion abierta, userdel fallaria a medias: se pide cerrarla antes.
    QProcess estado;
    estado.start(QStringLiteral("/usr/bin/loginctl"),
                 {QStringLiteral("show-user"), QStringLiteral("-p"), QStringLiteral("State"), QStringLiteral("--value"), usuario});
    estado.waitForFinished(5000);
    const QString st = QString::fromLocal8Bit(estado.readAllStandardOutput()).trimmed();
    if (st == QStringLiteral("active") || st == QStringLiteral("online"))
        return error(usuario + QStringLiteral(" tiene la sesion abierta: que la cierre antes de borrar la cuenta"));
    if (!st.isEmpty()) {
        // 'lingering' o 'closing': restos de una sesion ya cerrada.
        QString ignorar;
        ejecutar(QStringLiteral("/usr/bin/loginctl"), {QStringLiteral("terminate-user"), usuario}, &ignorar);
        QThread::sleep(1);
    }

    QStringList args;
    if (carpeta)
        args << QStringLiteral("-r");
    args << QStringLiteral("--") << usuario;
    QString fallo;
    if (!ejecutar(QStringLiteral("/usr/bin/userdel"), args, &fallo))
        return error(QStringLiteral("No se pudo borrar la cuenta: ") + fallo);
    return exito();
}

QJsonObject atender(const QJsonObject &pet)
{
    const QString admin = pet.value(QStringLiteral("admin")).toString();
    const QString clave = pet.value(QStringLiteral("clave")).toString();
    const QString accion = pet.value(QStringLiteral("accion")).toString();

    if (accion == QStringLiteral("cambiar-mi-clave"))
        return cambiarMiClave(pet);

    if (!nombreValido(admin) || !existeUsuario(admin) || !esDeWheel(admin))
        return error(QStringLiteral("Esa cuenta no es de administrador"));
    if (!autenticar(admin, clave)) {
        // Frena los intentos a ciegas (pam_faillock bloquea tras varios).
        QThread::sleep(2);
        return error(QStringLiteral("Contrasena de administrador incorrecta"));
    }

    if (accion == QStringLiteral("verificar"))
        return exito();
    if (accion == QStringLiteral("crear-usuario"))
        return crearUsuario(pet);
    if (accion == QStringLiteral("crear-grupo"))
        return crearGrupo(pet);
    if (accion == QStringLiteral("agregar-a-grupo"))
        return cambiarMiembro(pet, true, admin);
    if (accion == QStringLiteral("quitar-de-grupo"))
        return cambiarMiembro(pet, false, admin);
    if (accion == QStringLiteral("cambiar-clave"))
        return cambiarClave(pet);
    if (accion == QStringLiteral("cambiar-nombre"))
        return cambiarNombre(pet);
    if (accion == QStringLiteral("borrar-usuario"))
        return borrarUsuario(pet, admin);
    return error(QStringLiteral("Accion desconocida"));
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);

    if (geteuid() != 0) {
        std::cout << QJsonDocument(error(QStringLiteral("titan-usuarios-helper tiene que ejecutarse como root")))
                         .toJson(QJsonDocument::Compact).toStdString()
                  << std::endl;
        return 1;
    }

    std::string linea;
    if (!std::getline(std::cin, linea) || linea.size() > 65536) {
        std::cout << QJsonDocument(error(QStringLiteral("Peticion vacia o demasiado larga")))
                         .toJson(QJsonDocument::Compact).toStdString()
                  << std::endl;
        return 1;
    }

    QJsonParseError err{};
    const QJsonDocument doc = QJsonDocument::fromJson(QByteArray::fromStdString(linea), &err);
    linea.assign(linea.size(), '\0');
    QJsonObject respuesta;
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        respuesta = error(QStringLiteral("Peticion mal formada"));
    else
        respuesta = atender(doc.object());

    std::cout << QJsonDocument(respuesta).toJson(QJsonDocument::Compact).toStdString() << std::endl;
    return respuesta.value(QStringLiteral("ok")).toBool() ? 0 : 1;
}
