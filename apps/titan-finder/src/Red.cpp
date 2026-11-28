#include "Red.h"

#include <QDir>
#include <QPointer>
#include <QRegularExpression>
#include <QUrl>

// glib usa "signals" como nombre de campo
#pragma push_macro("signals")
#undef signals
#include <gio/gio.h>
#pragma pop_macro("signals")

namespace {

struct Peticion {
    QPointer<Red> red;
    QString uri;
    bool reintentado = false;
    bool despuesListar = false;
    GMountOperation *op = nullptr;
};

QString textoError(GError *e)
{
    if (!e) return QString();
    if (g_error_matches(e, G_IO_ERROR, G_IO_ERROR_PERMISSION_DENIED))
        return QStringLiteral("No tienes permiso para entrar aquí.");
    if (g_error_matches(e, G_IO_ERROR, G_IO_ERROR_FAILED_HANDLED))
        return QStringLiteral("Cancelado.");
    if (g_error_matches(e, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED))
        return QStringLiteral("No se puede abrir: falta el componente de red de Inti (gvfs-smb).");
    if (g_error_matches(e, G_IO_ERROR, G_IO_ERROR_NOT_MOUNTABLE_FILE))
        return QStringLiteral("No se puede conectar con esa dirección (¿falta gvfs-smb o está mal escrita?).");
    if (g_error_matches(e, G_IO_ERROR, G_IO_ERROR_TIMED_OUT) || g_error_matches(e, G_IO_ERROR, G_IO_ERROR_HOST_UNREACHABLE)
        || g_error_matches(e, G_IO_ERROR, G_IO_ERROR_NETWORK_UNREACHABLE) || g_error_matches(e, G_IO_ERROR, G_IO_ERROR_CONNECTION_REFUSED))
        return QStringLiteral("Ese equipo no responde. Comprueba que está encendido y en la misma red.");
    if (g_error_matches(e, G_IO_ERROR, G_IO_ERROR_HOST_NOT_FOUND) || g_error_matches(e, G_IO_ERROR, G_IO_ERROR_NOT_FOUND))
        return QStringLiteral("No se encuentra ese equipo o carpeta en la red.");
    return QString::fromUtf8(e->message);
}

void alPedirClave(GMountOperation *op, const char *mensaje, const char *usuario, const char *dominio,
                  GAskPasswordFlags flags, gpointer datos)
{
    auto *red = static_cast<Red *>(datos);
    red->pedirCredenciales(op, QString::fromUtf8(mensaje ? mensaje : ""), QString::fromUtf8(usuario ? usuario : ""),
                           QString::fromUtf8(dominio ? dominio : ""), flags & G_ASK_PASSWORD_ANONYMOUS_SUPPORTED);
}

// Preguntas (p. ej. un certificado): la primera opción, que suele ser "Continuar"
void alPreguntar(GMountOperation *op, const char *, const char **, gpointer)
{
    g_mount_operation_set_choice(op, 0);
    g_mount_operation_reply(op, G_MOUNT_OPERATION_HANDLED);
}

void alListarHijos(GObject *origen, GAsyncResult *res, gpointer datos);

void alEnumerar(GObject *origen, GAsyncResult *res, gpointer datos)
{
    auto *p = static_cast<Peticion *>(datos);
    GError *e = nullptr;
    GFileEnumerator *en = g_file_enumerate_children_finish(G_FILE(origen), res, &e);
    if (!en) {
        if (g_error_matches(e, G_IO_ERROR, G_IO_ERROR_NOT_MOUNTED) && !p->reintentado && p->red) {
            g_error_free(e);
            p->red->montar(p->uri, true);
            delete p;
            return;
        }
        if (p->red) emit p->red->listado(p->uri, {}, textoError(e));
        g_error_free(e);
        delete p;
        return;
    }
    g_file_enumerator_next_files_async(en, 500, G_PRIORITY_DEFAULT, nullptr, alListarHijos, p);
}

void alListarHijos(GObject *origen, GAsyncResult *res, gpointer datos)
{
    auto *p = static_cast<Peticion *>(datos);
    GFileEnumerator *en = G_FILE_ENUMERATOR(origen);
    GError *e = nullptr;
    GList *lista = g_file_enumerator_next_files_finish(en, res, &e);
    QVariantList r;
    GFile *padre = g_file_enumerator_get_container(en);
    for (GList *l = lista; l; l = l->next) {
        GFileInfo *info = G_FILE_INFO(l->data);
        const char *destino = g_file_info_get_attribute_string(info, G_FILE_ATTRIBUTE_STANDARD_TARGET_URI);
        QString ruta;
        if (destino && *destino) {
            ruta = QString::fromUtf8(destino);
        } else {
            GFile *hijo = g_file_get_child(padre, g_file_info_get_name(info));
            char *u = g_file_get_uri(hijo);
            ruta = QString::fromUtf8(u);
            g_free(u);
            g_object_unref(hijo);
        }
        const char *nombre = g_file_info_get_display_name(info);
        const GFileType tipo = g_file_info_get_file_type(info);
        // Un equipo (smb://PC/) o un grupo de trabajo, frente a una carpeta compartida
        const bool equipo = !Red::esCarpetaCompartida(ruta);
        r << QVariantMap{{QStringLiteral("name"), QString::fromUtf8(nombre ? nombre : g_file_info_get_name(info))},
                         {QStringLiteral("path"), ruta},
                         {QStringLiteral("isDir"), tipo != G_FILE_TYPE_REGULAR},
                         {QStringLiteral("equipo"), equipo}};
    }
    g_list_free_full(lista, g_object_unref);
    if (p->red) emit p->red->listado(p->uri, r, textoError(e));
    if (e) g_error_free(e);
    g_object_unref(en);
    delete p;
}

void alMontar(GObject *origen, GAsyncResult *res, gpointer datos)
{
    auto *p = static_cast<Peticion *>(datos);
    GError *e = nullptr;
    const bool ok = g_file_mount_enclosing_volume_finish(G_FILE(origen), res, &e)
                    || g_error_matches(e, G_IO_ERROR, G_IO_ERROR_ALREADY_MOUNTED);
    if (p->red) p->red->soltarOperacion(p->op);
    if (!p->red) { if (e) g_error_free(e); delete p; return; }
    if (!ok) {
        const QString t = textoError(e);
        if (p->despuesListar) emit p->red->listado(p->uri, {}, t);
        else emit p->red->abierto(p->uri, QString(), t);
    } else if (p->despuesListar) {
        auto *otra = new Peticion{p->red, p->uri, true, true};
        GFile *f = g_file_new_for_uri(p->uri.toUtf8().constData());
        g_file_enumerate_children_async(f, "standard::*", G_FILE_QUERY_INFO_NONE, G_PRIORITY_DEFAULT, nullptr, alEnumerar, otra);
        g_object_unref(f);
    } else {
        // La ruta local del montaje (gvfsd-fuse en /run/user/UID/gvfs)
        char *local = g_file_get_path(G_FILE(origen));
        if (local) emit p->red->abierto(p->uri, QString::fromUtf8(local), QString());
        else emit p->red->abierto(p->uri, QString(), QStringLiteral("Conectado, pero no se puede abrir como carpeta (falta gvfsd-fuse)."));
        g_free(local);
    }
    if (e) g_error_free(e);
    delete p;
}

} // namespace

Red::Red(QObject *parent) : QObject(parent) {}

Red::~Red()
{
    soltarOperacion();
}

bool Red::esRed(const QString &ruta)
{
    static const QRegularExpression esquema(QStringLiteral("^(network|smb|wsdd|dnssd|ftp|sftp|afp|nfs|dav|davs)://"),
                                            QRegularExpression::CaseInsensitiveOption);
    return esquema.match(ruta).hasMatch();
}

QString Red::normalizar(const QString &texto)
{
    QString t = texto.trimmed();
    if (t.startsWith(QLatin1String("\\\\"))) {
        // \\PC\Carpeta\sub -> smb://PC/Carpeta/sub (con espacios codificados)
        const QStringList trozos = t.mid(2).split(QLatin1Char('\\'), Qt::SkipEmptyParts);
        if (trozos.isEmpty()) return QString();
        QString u = QStringLiteral("smb://") + trozos.first() + QLatin1Char('/');
        for (int i = 1; i < trozos.size(); ++i)
            u += QString::fromUtf8(QUrl::toPercentEncoding(trozos.at(i))) + QLatin1Char('/');
        return u;
    }
    return esRed(t) ? t : QString();
}

bool Red::esCarpetaCompartida(const QString &uri)
{
    // smb://PC/Carpeta[/...]  (no smb://PC/ ni smb://GRUPO/)
    const QUrl u(uri);
    return u.scheme().compare(QLatin1String("smb"), Qt::CaseInsensitive) == 0 && !u.host().isEmpty()
           && !u.path().split(QLatin1Char('/'), Qt::SkipEmptyParts).isEmpty();
}

QStringList Red::partes(const QString &uri)
{
    const QUrl u(uri);
    if (u.scheme() == QLatin1String("network")) return {};
    QStringList r;
    if (!u.host().isEmpty()) r << u.host();
    r << u.path().split(QLatin1Char('/'), Qt::SkipEmptyParts);
    return r;
}

void Red::listar(const QString &uri)
{
    auto *p = new Peticion{this, uri};
    GFile *f = g_file_new_for_uri(uri.toUtf8().constData());
    g_file_enumerate_children_async(f, "standard::*", G_FILE_QUERY_INFO_NONE, G_PRIORITY_DEFAULT, nullptr, alEnumerar, p);
    g_object_unref(f);
}

void Red::abrir(const QString &uri)
{
    montar(uri, false);
}

void Red::montar(const QString &uri, bool despuesListar)
{
    soltarOperacion();
    GMountOperation *op = g_mount_operation_new();
    g_signal_connect(op, "ask-password", G_CALLBACK(alPedirClave), this);
    g_signal_connect(op, "ask-question", G_CALLBACK(alPreguntar), this);
    m_op = op;
    auto *p = new Peticion{this, uri, false, despuesListar, op};
    GFile *f = g_file_new_for_uri(uri.toUtf8().constData());
    g_file_mount_enclosing_volume(f, G_MOUNT_MOUNT_NONE, op, nullptr, alMontar, p);
    g_object_unref(f);
}

void Red::pedirCredenciales(GMountOperation *op, const QString &mensaje, const QString &usuario,
                            const QString &dominio, bool anonimo)
{
    if (op != m_op) {
        g_mount_operation_reply(op, G_MOUNT_OPERATION_ABORTED);
        return;
    }
    emit credencialesPedidas(mensaje, usuario, dominio, anonimo);
}

void Red::responder(bool aceptar, const QString &usuario, const QString &dominio, const QString &clave, bool anonimo)
{
    if (!m_op) return;
    if (!aceptar) {
        g_mount_operation_reply(m_op, G_MOUNT_OPERATION_ABORTED);
        return;
    }
    if (anonimo) {
        g_mount_operation_set_anonymous(m_op, TRUE);
    } else {
        g_mount_operation_set_username(m_op, usuario.toUtf8().constData());
        g_mount_operation_set_domain(m_op, dominio.toUtf8().constData());
        g_mount_operation_set_password(m_op, clave.toUtf8().constData());
    }
    // Solo mientras dure la sesión: la contraseña no se guarda en disco
    g_mount_operation_set_password_save(m_op, G_PASSWORD_SAVE_FOR_SESSION);
    g_mount_operation_reply(m_op, G_MOUNT_OPERATION_HANDLED);
}

void Red::soltarOperacion(GMountOperation *solo)
{
    if (solo && solo != m_op)
        return;
    if (m_op) {
        g_signal_handlers_disconnect_by_data(m_op, this);
        g_object_unref(m_op);
        m_op = nullptr;
    }
}
