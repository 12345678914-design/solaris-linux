#ifndef TITAN_WAYFIRE_IPC_H
#define TITAN_WAYFIRE_IPC_H

#include <QByteArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QString>

class QLocalSocket;

// Cliente del IPC de Wayfire (plugin "ipc", socket en $WAYFIRE_SOCKET).
// Formato del protocolo: 4 bytes con la longitud (orden nativo) + JSON
// {"method": ..., "data": {...}}. Las respuestas y los eventos usan el mismo
// marco.
//
// Se usa para que los escritorios del Dock y de WorkspacesView sean los
// escritorios reales de Wayfire (vswitch) en vez de simularlos minimizando
// ventanas, que en Wayfire dispararia la animacion de minimizar en cada
// cambio. Fuera de Wayfire disponible() es false y no hace nada.
class WayfireIpc : public QObject
{
    Q_OBJECT

public:
    static WayfireIpc *instancia();

    bool disponible() const { return m_disponible; }

    // Llamada sincrona (el socket es local; tarda microsegundos). Devuelve
    // un objeto vacio si falla.
    QJsonObject llamar(const QString &metodo, const QJsonObject &datos = {},
                       int esperaMs = 400);
    QJsonDocument llamarDoc(const QString &metodo, const QJsonObject &datos = {},
                            int esperaMs = 400);

    bool irAEscritorio(int indice);
    bool enviarVentana(const QString &appId, const QString &titulo, int indice);
    int escritorioActual();
    // true si el plugin esta en core/plugins (p. ej. "blur").
    bool pluginActivo(const QString &nombre);
    // ¿Hay una ventana acoplada (media pantalla, cuarto o mosaico) pegada al
    // borde de abajo en el escritorio que se ve? Entonces el Dock se esconde.
    bool hayAcoplada() const { return m_hayAcoplada; }

signals:
    void escritorioCambiado(int indice);
    void acopladaCambiada();

private:
    explicit WayfireIpc(QObject *padre = nullptr);

    bool conectar(QLocalSocket *socket);
    static QByteArray marco(const QJsonObject &mensaje);
    void leerEventos();
    int idSalida();
    void revisarAcopladas();

    QString m_ruta;
    bool m_disponible = false;
    QLocalSocket *m_sincrono = nullptr;
    QLocalSocket *m_eventos = nullptr;
    QByteArray m_bufferEventos;
    int m_idSalida = -1;
    bool m_hayAcoplada = false;
    class QTimer *m_revisar = nullptr;
};

#endif
