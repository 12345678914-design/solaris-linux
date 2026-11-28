#include "GreetdCliente.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QtEndian>

#include <cstring>

GreetdCliente::GreetdCliente(QObject *parent) : QObject(parent) {}

bool GreetdCliente::disponible() const
{
    return !qEnvironmentVariableIsEmpty("GREETD_SOCK");
}

void GreetdCliente::setEstado(Estado e)
{
    const bool antes = ocupado();
    m_estado = e;
    if (antes != ocupado())
        emit ocupadoCambiado();
}

void GreetdCliente::entrar(const QString &usuario, const QString &clave)
{
    if (ocupado())
        return;
    if (!disponible()) {
        emit fallo(QStringLiteral("No se puede iniciar sesion: greetd no esta activo"));
        return;
    }

    m_clave = clave;
    m_claveEnviada = false;
    m_falloPendiente.clear();
    m_buffer.clear();

    if (!m_socket) {
        m_socket = new QLocalSocket(this);
        connect(m_socket, &QLocalSocket::readyRead, this, [this]() {
            m_buffer.append(m_socket->readAll());
            while (m_buffer.size() >= 4) {
                quint32 largo;
                std::memcpy(&largo, m_buffer.constData(), 4);
                if (largo > 1 << 20) {
                    terminarConFallo(QStringLiteral("Respuesta de greetd demasiado larga"));
                    return;
                }
                if (m_buffer.size() < 4 + static_cast<int>(largo))
                    return;
                const QJsonObject msg = QJsonDocument::fromJson(m_buffer.mid(4, largo)).object();
                m_buffer.remove(0, 4 + largo);
                procesar(msg);
            }
        });
        connect(m_socket, &QLocalSocket::errorOccurred, this, [this](QLocalSocket::LocalSocketError) {
            if (ocupado())
                terminarConFallo(QStringLiteral("Se perdio la conexion con greetd"));
        });
    }
    if (m_socket->state() != QLocalSocket::ConnectedState) {
        m_socket->connectToServer(qEnvironmentVariable("GREETD_SOCK"));
        if (!m_socket->waitForConnected(3000)) {
            emit fallo(QStringLiteral("No se pudo conectar con greetd"));
            return;
        }
    }

    setEstado(Estado::Creando);
    enviar({{QStringLiteral("type"), QStringLiteral("create_session")},
            {QStringLiteral("username"), usuario}});
}

void GreetdCliente::enviar(const QJsonObject &msg)
{
    QByteArray json = QJsonDocument(msg).toJson(QJsonDocument::Compact);
    const quint32 largo = static_cast<quint32>(json.size());
    QByteArray paquete(4, '\0');
    std::memcpy(paquete.data(), &largo, 4);
    paquete.append(json);
    m_socket->write(paquete);
    m_socket->flush();
    json.fill('\0');
    paquete.fill('\0');
}

void GreetdCliente::terminarConFallo(const QString &mensaje)
{
    // Una sesion a medio configurar hay que cancelarla antes de reintentar.
    if (m_estado == Estado::Creando || m_estado == Estado::Autenticando || m_estado == Estado::Arrancando) {
        m_falloPendiente = mensaje;
        setEstado(Estado::Cancelando);
        if (m_socket && m_socket->state() == QLocalSocket::ConnectedState) {
            enviar({{QStringLiteral("type"), QStringLiteral("cancel_session")}});
            return;
        }
    }
    m_clave.fill(QLatin1Char('\0'));
    m_clave.clear();
    setEstado(Estado::Libre);
    emit fallo(mensaje.isEmpty() ? m_falloPendiente : mensaje);
}

void GreetdCliente::procesar(const QJsonObject &msg)
{
    const QString tipo = msg.value(QStringLiteral("type")).toString();

    if (m_estado == Estado::Cancelando) {
        // Respuesta al cancel_session: ya se puede avisar del fallo.
        const QString mensaje = m_falloPendiente;
        m_clave.fill(QLatin1Char('\0'));
        m_clave.clear();
        setEstado(Estado::Libre);
        emit fallo(mensaje);
        return;
    }

    if (tipo == QStringLiteral("error")) {
        const bool deClave = msg.value(QStringLiteral("error_type")).toString() == QStringLiteral("auth_error");
        terminarConFallo(deClave ? QStringLiteral("Contraseña incorrecta")
                                 : msg.value(QStringLiteral("description")).toString());
        return;
    }

    if (tipo == QStringLiteral("auth_message")) {
        setEstado(Estado::Autenticando);
        const QString clase = msg.value(QStringLiteral("auth_message_type")).toString();
        if (clase == QStringLiteral("secret") || clase == QStringLiteral("visible")) {
            if (m_claveEnviada) {
                // Segunda pregunta (p. ej. contrasena caducada): no se puede
                // contestar desde aqui.
                const QString texto = msg.value(QStringLiteral("auth_message")).toString().trimmed();
                terminarConFallo(texto.isEmpty() ? QStringLiteral("La cuenta pide otro dato para entrar")
                                                 : texto);
                return;
            }
            m_claveEnviada = true;
            enviar({{QStringLiteral("type"), QStringLiteral("post_auth_message_response")},
                    {QStringLiteral("response"), m_clave}});
            m_clave.fill(QLatin1Char('\0'));
            m_clave.clear();
        } else {
            // info / error informativos: se reconocen sin respuesta.
            enviar({{QStringLiteral("type"), QStringLiteral("post_auth_message_response")}});
        }
        return;
    }

    if (tipo == QStringLiteral("success")) {
        if (m_estado == Estado::Arrancando) {
            setEstado(Estado::Libre);
            emit sesionLista();
            return;
        }
        setEstado(Estado::Arrancando);
        QJsonArray cmd;
        for (const QString &parte : m_orden)
            cmd.append(parte);
        enviar({{QStringLiteral("type"), QStringLiteral("start_session")},
                {QStringLiteral("cmd"), cmd},
                {QStringLiteral("env"), QJsonArray{QStringLiteral("TITAN_DESDE_GREETD=1")}}});
        return;
    }

    terminarConFallo(QStringLiteral("Respuesta inesperada de greetd"));
}
