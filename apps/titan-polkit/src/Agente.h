// Inti OS - agente de autenticacion de polkit.
//
// polkitd llama a initiateAuthentication cuando un programa sin privilegios
// pide algo que necesita administrador (pkexec, udisks, cups, PackageKit...).
// El agente ensena la ventana, pasa la contrasena a una sesion PAM de polkit
// (PolkitQt1::Agent::Session) y al terminar avisa con AsyncResult.
#pragma once

#include <QObject>
#include <QPointer>
#include <QStringList>
#include <QVariantList>

#include <PolkitQt1/Agent/Listener>
#include <PolkitQt1/Agent/Session>
#include <PolkitQt1/Details>
#include <PolkitQt1/Identity>

class Agente : public PolkitQt1::Agent::Listener
{
    Q_OBJECT
    // Lo que ve la ventana (qml/Dialogo.qml)
    Q_PROPERTY(bool activo READ activo NOTIFY cambiado)
    Q_PROPERTY(QString mensaje READ mensaje NOTIFY cambiado)
    Q_PROPERTY(QString accion READ accion NOTIFY cambiado)
    Q_PROPERTY(QString programa READ programa NOTIFY cambiado)
    Q_PROPERTY(QVariantList usuarios READ usuarios NOTIFY cambiado)
    Q_PROPERTY(int usuarioActual READ usuarioActual NOTIFY cambiado)
    Q_PROPERTY(QString peticion READ peticion NOTIFY cambiado)
    Q_PROPERTY(bool eco READ eco NOTIFY cambiado)
    Q_PROPERTY(bool esperandoRespuesta READ esperandoRespuesta NOTIFY cambiado)
    Q_PROPERTY(QString error READ error NOTIFY cambiado)
    Q_PROPERTY(QString aviso READ aviso NOTIFY cambiado)
    Q_PROPERTY(int intentosFallidos READ intentosFallidos NOTIFY cambiado)

public:
    explicit Agente(QObject *parent = nullptr);

    bool activo() const { return m_activo; }
    QString mensaje() const { return m_mensaje; }
    QString accion() const { return m_accion; }
    QString programa() const { return m_programa; }
    QVariantList usuarios() const { return m_usuarios; }
    int usuarioActual() const { return m_usuarioActual; }
    QString peticion() const { return m_peticion; }
    bool eco() const { return m_eco; }
    bool esperandoRespuesta() const { return m_esperandoRespuesta; }
    QString error() const { return m_error; }
    QString aviso() const { return m_aviso; }
    int intentosFallidos() const { return m_fallos; }

    Q_INVOKABLE void responder(const QString &texto);
    Q_INVOKABLE void cancelar();
    Q_INVOKABLE void elegirUsuario(int indice);

    // Modo de prueba (TITAN_POLKIT_DEMO=1): ensena la ventana sin polkitd.
    void demostracion();

public Q_SLOTS:
    void initiateAuthentication(const QString &actionId,
                                const QString &message,
                                const QString &iconName,
                                const PolkitQt1::Details &details,
                                const QString &cookie,
                                const PolkitQt1::Identity::List &identities,
                                PolkitQt1::Agent::AsyncResult *result) override;
    bool initiateAuthenticationFinish() override;
    void cancelAuthentication() override;

Q_SIGNALS:
    void cambiado();

private:
    void empezarSesion();
    void terminar();
    void alCompletar(bool autorizado);

    bool m_activo{false};
    QString m_mensaje;
    QString m_accion;
    QString m_programa;
    QVariantList m_usuarios;
    int m_usuarioActual{0};
    QString m_peticion;
    bool m_eco{false};
    bool m_esperandoRespuesta{false};
    QString m_error;
    QString m_aviso;
    int m_fallos{0};
    bool m_cancelado{false};

    QString m_cookie;
    PolkitQt1::Identity::List m_identidades;
    PolkitQt1::Agent::AsyncResult *m_resultado{nullptr};
    QPointer<PolkitQt1::Agent::Session> m_sesion;
};
