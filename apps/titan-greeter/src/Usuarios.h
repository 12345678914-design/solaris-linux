#ifndef TITAN_USUARIOS_H
#define TITAN_USUARIOS_H

// Usuarios y grupos del sistema para la pantalla de inicio (titan-greeter) y
// la de bloqueo (titan-shell).
//
// Leer cuentas y grupos no necesita privilegios (/etc/passwd y /etc/group).
// Crear o cambiar algo pasa por titan-usuarios-helper (root, activado por
// socket), que exige usuario y contrasena de un administrador (grupo wheel)
// en cada peticion.

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QString>

class QLocalSocket;

class Usuarios : public QObject
{
    Q_OBJECT
    // Personas que pueden entrar: [{usuario, nombre, uid, esAdmin, grupos[]}]
    Q_PROPERTY(QVariantList usuarios READ usuarios NOTIFY cambiado)
    // Grupos de personas (gid 1000-59999) y wheel: [{grupo, gid, miembros[]}]
    Q_PROPERTY(QVariantList grupos READ grupos NOTIFY cambiado)
    // Administradores (para elegir con cual autorizar cambios)
    Q_PROPERTY(QStringList administradores READ administradores NOTIFY cambiado)
    Q_PROPERTY(bool gestionDisponible READ gestionDisponible CONSTANT)
    Q_PROPERTY(QString adminActivo READ adminActivo NOTIFY adminActivoCambiado)
    Q_PROPERTY(bool ocupado READ ocupado NOTIFY ocupadoCambiado)

public:
    explicit Usuarios(QObject *parent = nullptr);

    QVariantList usuarios() const { return m_usuarios; }
    QVariantList grupos() const { return m_grupos; }
    QStringList administradores() const { return m_admins; }
    bool gestionDisponible() const;
    QString adminActivo() const { return m_adminActivo; }
    bool ocupado() const { return m_ocupado; }

    Q_INVOKABLE void recargar();
    // Comprueba la contrasena del administrador; si vale, queda activo hasta
    // cerrarAdmin() y las acciones siguientes se autorizan con ella.
    Q_INVOKABLE void iniciarAdmin(const QString &admin, const QString &clave);
    Q_INVOKABLE void cerrarAdmin();
    Q_INVOKABLE void crearUsuario(const QString &usuario, const QString &nombre,
                                  const QString &clave, bool esAdmin,
                                  const QStringList &grupos = {});
    Q_INVOKABLE void crearGrupo(const QString &grupo);
    Q_INVOKABLE void agregarAGrupo(const QString &usuario, const QString &grupo);
    Q_INVOKABLE void quitarDeGrupo(const QString &usuario, const QString &grupo);
    Q_INVOKABLE void cambiarClave(const QString &usuario, const QString &clave);
    Q_INVOKABLE void cambiarNombre(const QString &usuario, const QString &nombre);
    Q_INVOKABLE void borrarUsuario(const QString &usuario, bool borrarCarpeta);
    // Sin administrador: la cuenta con la que se ha entrado, con su contrasena.
    Q_INVOKABLE void cambiarMiClave(const QString &actual, const QString &nueva);
    Q_INVOKABLE QString usuarioActual() const;

signals:
    void cambiado();
    void adminActivoCambiado();
    void ocupadoCambiado();
    // Resultado de cada accion ('verificar' para iniciarAdmin).
    void terminado(const QString &accion, bool ok, const QString &error);

private:
    void enviar(QVariantMap peticion, const QString &admin, const QString &clave);
    void setOcupado(bool o);

    QVariantList m_usuarios;
    QVariantList m_grupos;
    QStringList m_admins;
    QString m_adminActivo;
    QString m_claveAdmin;
    QString m_adminPendiente;
    QString m_clavePendiente;
    bool m_ocupado = false;
};

#endif
