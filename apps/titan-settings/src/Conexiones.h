// Inti OS - Ajustes: Wi-Fi (NetworkManager) y Bluetooth (BlueZ) con lo que
// queda guardado: redes conocidas con su contrasena y dispositivos emparejados.
//
// Wi-Fi: cada red a la que se entra queda como perfil de NetworkManager con
// su contrasena; al volver a elegirla se usa el perfil (no se pide otra vez).
// Bluetooth: emparejar + confiar, asi el dispositivo vuelve a conectarse solo.
#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <functional>

class Conexiones : public QObject
{
    Q_OBJECT
    // Wi-Fi
    Q_PROPERTY(bool wifiActivo READ wifiActivo NOTIFY wifiCambiado)
    Q_PROPERTY(bool hayWifi READ hayWifi NOTIFY wifiCambiado)
    Q_PROPERTY(QString redActual READ redActual NOTIFY wifiCambiado)
    // [{ssid, senal, seguridad, conectada, conocida, uuid}]
    Q_PROPERTY(QVariantList redes READ redes NOTIFY wifiCambiado)
    // [{nombre, uuid, ssid, autoconectar, ultima, activa}]
    Q_PROPERTY(QVariantList conocidas READ conocidas NOTIFY wifiCambiado)
    Q_PROPERTY(bool escaneando READ escaneando NOTIFY wifiCambiado)
    Q_PROPERTY(QString conectando READ conectando NOTIFY wifiCambiado)
    // Bluetooth
    Q_PROPERTY(bool btActivo READ btActivo NOTIFY btCambiado)
    Q_PROPERTY(bool hayBt READ hayBt NOTIFY btCambiado)
    // [{mac, nombre, emparejado, conectado, confiable, icono, tipo, bateria}]
    Q_PROPERTY(QVariantList dispositivos READ dispositivos NOTIFY btCambiado)
    Q_PROPERTY(bool buscando READ buscando NOTIFY btCambiado)
    Q_PROPERTY(QString btOcupado READ btOcupado NOTIFY btCambiado)
    Q_PROPERTY(QString mensaje READ mensaje NOTIFY mensajeCambiado)

public:
    explicit Conexiones(QObject *parent = nullptr);

    bool wifiActivo() const { return m_wifiActivo; }
    bool hayWifi() const { return m_hayWifi; }
    QString redActual() const { return m_redActual; }
    QVariantList redes() const { return m_redes; }
    QVariantList conocidas() const { return m_conocidas; }
    bool escaneando() const { return m_escaneando; }
    QString conectando() const { return m_conectando; }
    bool btActivo() const { return m_btActivo; }
    bool hayBt() const { return m_hayBt; }
    QVariantList dispositivos() const { return m_dispositivos; }
    bool buscando() const { return m_buscando; }
    QString btOcupado() const { return m_btOcupado; }
    QString mensaje() const { return m_mensaje; }

    Q_INVOKABLE void leerWifi();
    Q_INVOKABLE void escanear();
    Q_INVOKABLE void setWifi(bool activo);
    // Red conocida: se usa su perfil guardado. Nueva: hace falta la contrasena
    // si tiene seguridad (la UI la pide antes).
    Q_INVOKABLE void conectar(const QString &ssid, const QString &clave = QString());
    Q_INVOKABLE void unirseOculta(const QString &ssid, const QString &clave);
    Q_INVOKABLE void desconectar();
    Q_INVOKABLE void olvidar(const QString &uuid);
    Q_INVOKABLE void setAutoconectar(const QString &uuid, bool si);
    // Lee la contrasena guardada (NetworkManager puede pedir la de administrador).
    Q_INVOKABLE void verClave(const QString &uuid);
    Q_INVOKABLE bool esConocida(const QString &ssid) const;

    Q_INVOKABLE void leerBt();
    Q_INVOKABLE void buscarBt();
    Q_INVOKABLE void setBt(bool activo);
    // Empareja y confia si hace falta, y conecta.
    Q_INVOKABLE void conectarBt(const QString &mac);
    Q_INVOKABLE void desconectarBt(const QString &mac);
    Q_INVOKABLE void olvidarBt(const QString &mac);

    Q_INVOKABLE void limpiarMensaje();

signals:
    void wifiCambiado();
    void btCambiado();
    void mensajeCambiado();
    void claveLeida(const QString &uuid, const QString &clave);

private:
    using Fin = std::function<void(int codigo, const QString &salida, const QString &error)>;
    void correr(const QString &programa, const QStringList &args, Fin fin, int msMax = 30000);
    void avisar(const QString &t);
    void leerPerfiles(QVariantList perfiles, int i, QVariantList listos);
    void unirListas();
    void leerInfoBt(QStringList macs, int i, QVariantList listos);

    bool m_wifiActivo = false;
    bool m_hayWifi = false;
    QString m_redActual;
    QVariantList m_escaneadas;
    QVariantList m_redes;
    QVariantList m_conocidas;
    bool m_escaneando = false;
    QString m_conectando;
    bool m_btActivo = false;
    bool m_hayBt = false;
    QVariantList m_dispositivos;
    bool m_buscando = false;
    QString m_btOcupado;
    QString m_mensaje;
};
