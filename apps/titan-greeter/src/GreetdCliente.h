#ifndef TITAN_GREETD_CLIENTE_H
#define TITAN_GREETD_CLIENTE_H

// Cliente del IPC de greetd (man 7 greetd-ipc): cada mensaje es una longitud
// de 4 bytes en orden nativo seguida de JSON.
//
//   create_session -> auth_message (contrasena) -> post_auth_message_response
//   -> success -> start_session -> success: el greeter termina y greetd
//   arranca la sesion del usuario.

#include <QObject>
#include <QByteArray>
#include <QString>
#include <QStringList>

class QLocalSocket;
class QJsonObject;

class GreetdCliente : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool disponible READ disponible CONSTANT)
    Q_PROPERTY(bool ocupado READ ocupado NOTIFY ocupadoCambiado)

public:
    explicit GreetdCliente(QObject *parent = nullptr);

    bool disponible() const;
    bool ocupado() const { return m_estado != Estado::Libre; }

    // Orden con la que greetd arranca la sesion del usuario.
    void setOrdenSesion(const QStringList &orden) { m_orden = orden; }

    Q_INVOKABLE void entrar(const QString &usuario, const QString &clave);

signals:
    void ocupadoCambiado();
    void fallo(const QString &mensaje);
    // La sesion esta lista: el greeter tiene que salir para que greetd la arranque.
    void sesionLista();

private:
    enum class Estado { Libre, Creando, Autenticando, Arrancando, Cancelando };

    void enviar(const QJsonObject &msg);
    void procesar(const QJsonObject &msg);
    void terminarConFallo(const QString &mensaje);
    void setEstado(Estado e);

    QLocalSocket *m_socket = nullptr;
    QByteArray m_buffer;
    Estado m_estado = Estado::Libre;
    QString m_clave;
    bool m_claveEnviada = false;
    QString m_falloPendiente;
    QStringList m_orden;
};

#endif
