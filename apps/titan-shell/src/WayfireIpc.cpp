#include "WayfireIpc.h"
#include <QTimer>
#include <QSizeF>
#include <QHash>

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocalSocket>
#include <QtEndian>

#include <cstring>

namespace {

// Extrae un mensaje completo del buffer (si lo hay) y lo quita de el.
bool sacarMensaje(QByteArray &buffer, QJsonDocument *salida)
{
    if (buffer.size() < 4) {
        return false;
    }
    quint32 largo = 0;
    std::memcpy(&largo, buffer.constData(), 4);
    if (buffer.size() < int(4 + largo)) {
        return false;
    }
    const QByteArray cuerpo = buffer.mid(4, int(largo));
    buffer.remove(0, int(4 + largo));
    *salida = QJsonDocument::fromJson(cuerpo);
    return true;
}

} // namespace

WayfireIpc *WayfireIpc::instancia()
{
    static WayfireIpc *unica = new WayfireIpc;
    return unica;
}

WayfireIpc::WayfireIpc(QObject *padre)
    : QObject(padre)
    , m_ruta(QString::fromLocal8Bit(qgetenv("WAYFIRE_SOCKET")))
{
    if (m_ruta.isEmpty()) {
        return;
    }

    m_sincrono = new QLocalSocket(this);
    if (!conectar(m_sincrono)) {
        qWarning() << "WayfireIpc: no se pudo conectar a" << m_ruta;
        return;
    }
    m_disponible = true;

    // Segundo socket solo para eventos: el plugin no permite mezclar
    // respuestas y eventos sin confundirlos, y asi las llamadas sincronas
    // nunca se encuentran un evento a medio leer.
    m_eventos = new QLocalSocket(this);
    if (conectar(m_eventos)) {
        QJsonObject datos;
        datos.insert(QStringLiteral("events"),
                     QJsonArray{QStringLiteral("wset-workspace-changed"), QStringLiteral("view-tiled"),
                                QStringLiteral("view-mapped"), QStringLiteral("view-unmapped"),
                                QStringLiteral("view-minimized"), QStringLiteral("view-geometry-changed"),
                                QStringLiteral("view-workspace-changed"), QStringLiteral("view-set-output")});
        QJsonObject msg;
        msg.insert(QStringLiteral("method"), QStringLiteral("window-rules/events/watch"));
        msg.insert(QStringLiteral("data"), datos);
        m_eventos->write(marco(msg));
        m_eventos->flush();
        connect(m_eventos, &QLocalSocket::readyRead, this, &WayfireIpc::leerEventos);
    }
    // Muchos eventos seguidos (mover, animaciones): se revisa una vez al final
    m_revisar = new QTimer(this);
    m_revisar->setSingleShot(true);
    m_revisar->setInterval(120);
    connect(m_revisar, &QTimer::timeout, this, &WayfireIpc::revisarAcopladas);
    m_revisar->start();
}

bool WayfireIpc::conectar(QLocalSocket *socket)
{
    socket->connectToServer(m_ruta);
    return socket->waitForConnected(500);
}

QByteArray WayfireIpc::marco(const QJsonObject &mensaje)
{
    const QByteArray cuerpo = QJsonDocument(mensaje).toJson(QJsonDocument::Compact);
    const quint32 largo = quint32(cuerpo.size());
    QByteArray salida(4, Qt::Uninitialized);
    std::memcpy(salida.data(), &largo, 4);
    return salida + cuerpo;
}

QJsonObject WayfireIpc::llamar(const QString &metodo, const QJsonObject &datos, int esperaMs)
{
    return llamarDoc(metodo, datos, esperaMs).object();
}

QJsonDocument WayfireIpc::llamarDoc(const QString &metodo, const QJsonObject &datos, int esperaMs)
{
    if (!m_disponible || !m_sincrono) {
        return {};
    }
    if (m_sincrono->state() != QLocalSocket::ConnectedState && !conectar(m_sincrono)) {
        return {};
    }

    QJsonObject msg;
    msg.insert(QStringLiteral("method"), metodo);
    msg.insert(QStringLiteral("data"), datos);
    m_sincrono->write(marco(msg));
    m_sincrono->flush();

    QByteArray buffer;
    QJsonDocument respuesta;
    while (!sacarMensaje(buffer, &respuesta)) {
        if (!m_sincrono->waitForReadyRead(esperaMs)) {
            qWarning() << "WayfireIpc: sin respuesta a" << metodo;
            return {};
        }
        buffer += m_sincrono->readAll();
    }
    if (respuesta.isObject()
        && respuesta.object().value(QStringLiteral("result")).toString() == QLatin1String("error")) {
        qWarning() << "WayfireIpc:" << metodo
                   << respuesta.object().value(QStringLiteral("error")).toString();
    }
    return respuesta;
}

int WayfireIpc::idSalida()
{
    // La salida con el foco: en un solo monitor es siempre la misma, pero
    // con varios el cambio de escritorio debe ir a la que usa el usuario.
    const QJsonObject r = llamar(QStringLiteral("window-rules/get-focused-output"));
    const QJsonObject info = r.value(QStringLiteral("info")).toObject();
    if (info.contains(QStringLiteral("id"))) {
        m_idSalida = info.value(QStringLiteral("id")).toInt();
    }
    return m_idSalida;
}

int WayfireIpc::escritorioActual()
{
    const QJsonObject r = llamar(QStringLiteral("window-rules/get-focused-output"));
    const QJsonObject ws = r.value(QStringLiteral("info")).toObject()
                               .value(QStringLiteral("workspace")).toObject();
    if (ws.isEmpty()) {
        return -1;
    }
    return ws.value(QStringLiteral("x")).toInt();
}

bool WayfireIpc::irAEscritorio(int indice)
{
    const int salida = idSalida();
    if (salida < 0 || indice < 0) {
        return false;
    }
    QJsonObject datos;
    datos.insert(QStringLiteral("x"), indice);
    datos.insert(QStringLiteral("y"), 0);
    datos.insert(QStringLiteral("output-id"), salida);
    const QJsonObject r = llamar(QStringLiteral("vswitch/set-workspace"), datos);
    return r.value(QStringLiteral("result")).toString() == QLatin1String("ok");
}

bool WayfireIpc::enviarVentana(const QString &appId, const QString &titulo, int indice)
{
    // foreign-toplevel no da el id de Wayfire; se busca la vista por app-id
    // y titulo entre las ventanas normales.
    // La respuesta es un array JSON en el nivel superior.
    const QJsonArray vistas = llamarDoc(QStringLiteral("window-rules/list-views")).array();

    int idVista = -1;
    for (const QJsonValue &v : vistas) {
        const QJsonObject o = v.toObject();
        if (o.value(QStringLiteral("type")).toString() != QLatin1String("toplevel")) {
            continue;
        }
        if (o.value(QStringLiteral("app-id")).toString() == appId
            && (titulo.isEmpty() || o.value(QStringLiteral("title")).toString() == titulo)) {
            idVista = o.value(QStringLiteral("id")).toInt();
            break;
        }
    }
    if (idVista < 0) {
        return false;
    }

    QJsonObject datos;
    datos.insert(QStringLiteral("x"), indice);
    datos.insert(QStringLiteral("y"), 0);
    datos.insert(QStringLiteral("view-id"), idVista);
    const QJsonObject res = llamar(QStringLiteral("vswitch/send-view"), datos);
    return res.value(QStringLiteral("result")).toString() == QLatin1String("ok");
}

void WayfireIpc::leerEventos()
{
    m_bufferEventos += m_eventos->readAll();
    QJsonDocument doc;
    while (sacarMensaje(m_bufferEventos, &doc)) {
        const QJsonObject msg = doc.object();
        const QString evento = msg.value(QStringLiteral("event")).toString();
        if (evento.isEmpty()) continue;
        if (m_revisar) m_revisar->start();
        if (evento != QLatin1String("wset-workspace-changed")) {
            continue;
        }
        const QJsonObject nuevo = msg.value(QStringLiteral("new-workspace")).toObject();
        if (!nuevo.isEmpty()) {
            emit escritorioCambiado(nuevo.value(QStringLiteral("x")).toInt());
        }
    }
}

void WayfireIpc::revisarAcopladas()
{
    // Tamaño de cada pantalla (las ventanas dan su posición respecto a ella)
    QHash<int, QSizeF> salidas;
    for (const QJsonValue &v : llamarDoc(QStringLiteral("window-rules/list-outputs")).array()) {
        const QJsonObject o = v.toObject();
        const QJsonObject g = o.value(QStringLiteral("geometry")).toObject();
        salidas.insert(o.value(QStringLiteral("id")).toInt(),
                       QSizeF(g.value(QStringLiteral("width")).toDouble(), g.value(QStringLiteral("height")).toDouble()));
    }
    bool hay = false;
    for (const QJsonValue &v : llamarDoc(QStringLiteral("window-rules/list-views")).array()) {
        const QJsonObject o = v.toObject();
        if (o.value(QStringLiteral("role")).toString() != QLatin1String("toplevel")
            || !o.value(QStringLiteral("mapped")).toBool() || o.value(QStringLiteral("minimized")).toBool()
            || o.value(QStringLiteral("layer")).toString() != QLatin1String("workspace"))
            continue;
        // Bordes acoplados: 1 arriba, 2 abajo, 4 izquierda, 8 derecha
        if (!(o.value(QStringLiteral("tiled-edges")).toInt() & 2))
            continue;
        // Solo las que se ven (las de otros escritorios caen fuera de la pantalla)
        const QSizeF pantalla = salidas.value(o.value(QStringLiteral("output-id")).toInt());
        const QJsonObject g = o.value(QStringLiteral("geometry")).toObject();
        const double x = g.value(QStringLiteral("x")).toDouble(), y = g.value(QStringLiteral("y")).toDouble();
        const double w = g.value(QStringLiteral("width")).toDouble(), h = g.value(QStringLiteral("height")).toDouble();
        if (pantalla.isEmpty() || x + w <= 0 || y + h <= 0 || x >= pantalla.width() || y >= pantalla.height())
            continue;
        hay = true;
        break;
    }
    if (hay != m_hayAcoplada) {
        m_hayAcoplada = hay;
        emit acopladaCambiada();
    }
}

bool WayfireIpc::pluginActivo(const QString &nombre)
{
    QJsonObject datos;
    datos.insert(QStringLiteral("option"), QStringLiteral("core/plugins"));
    const QString lista = llamar(QStringLiteral("wayfire/get-config-option"), datos)
                              .value(QStringLiteral("value")).toString();
    return lista.split(QLatin1Char(' '), Qt::SkipEmptyParts).contains(nombre);
}
