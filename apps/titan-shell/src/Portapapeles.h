#pragma once
// Historial del portapapeles (Win+V, como Windows).
//
// Privacidad: viene APAGADO; la primera vez que se pulsa Win+V se ofrece
// activarlo. Lo copiado se guarda solo en memoria (nunca en el disco) y se
// pierde al cerrar la sesión. No se apunta lo que los gestores de
// contraseñas marcan como secreto (x-kde-passwordManagerHint).
// Lo vigila "wl-paste --watch" (protocolo wlr-data-control de Wayfire).
#include <QObject>
#include <QProcess>
#include <QStringList>

class Portapapeles : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool activo READ activo WRITE setActivo NOTIFY activoChanged)
    Q_PROPERTY(QStringList elementos READ elementos NOTIFY elementosChanged)

public:
    explicit Portapapeles(QObject *parent = nullptr);
    ~Portapapeles() override;

    bool activo() const { return m_activo; }
    void setActivo(bool a);
    QStringList elementos() const { return m_elementos; }

    // Lo pone en el portapapeles y lo pega en la ventana de antes (Ctrl+V)
    Q_INVOKABLE void pegar(int indice);
    Q_INVOKABLE void quitar(int indice);
    Q_INVOKABLE void borrarTodo();
    // Escribe texto en la ventana de antes (emojis)
    Q_INVOKABLE void escribir(const QString &texto);

signals:
    void activoChanged();
    void elementosChanged();

private:
    void vigilar();
    void leer();
    QProcess m_vigia;
    QByteArray m_resto;
    QStringList m_elementos;
    bool m_activo = false;
    static constexpr int kMaximo = 25;
};
