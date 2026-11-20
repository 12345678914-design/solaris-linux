// Inti OS - Ajustes: energia, bloqueo, seguridad, accesibilidad, teclado,
// impresoras, puntos de restauracion, VPN y almacenamiento.
//
// Todo se hace con las herramientas del sistema (powerprofilesctl, nmcli,
// lpstat, fprintd, los scripts titan-*...) en procesos asincronos: la ventana
// no se congela nunca. Lo que necesita root pasa por pkexec, que pide la
// contrasena con titan-polkit.
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <functional>

class QProcess;

class Sistema : public QObject
{
    Q_OBJECT
    // Energia
    Q_PROPERTY(QString perfilEnergia READ perfilEnergia NOTIFY cambiado)
    Q_PROPERTY(QStringList perfilesEnergia READ perfilesEnergia NOTIFY cambiado)
    Q_PROPERTY(QVariantMap bateria READ bateria NOTIFY cambiado)
    Q_PROPERTY(QVariantMap inactividad READ inactividad NOTIFY cambiado)
    // Seguridad
    Q_PROPERTY(QString cortafuegos READ cortafuegos NOTIFY cambiado)
    Q_PROPERTY(QString arranqueSeguro READ arranqueSeguro NOTIFY cambiado)
    Q_PROPERTY(QString arranqueSeguroTexto READ arranqueSeguroTexto NOTIFY cambiado)
    Q_PROPERTY(QString huella READ huella NOTIFY cambiado)
    Q_PROPERTY(bool huellaActiva READ huellaActiva NOTIFY cambiado)
    Q_PROPERTY(bool registrandoHuella READ registrandoHuella NOTIFY cambiado)
    Q_PROPERTY(QString mensajeHuella READ mensajeHuella NOTIFY cambiado)
    // Accesibilidad y teclado
    Q_PROPERTY(bool lector READ lector NOTIFY cambiado)
    Q_PROPERTY(bool tecladoPantalla READ tecladoPantalla NOTIFY cambiado)
    Q_PROPERTY(bool metodosEntrada READ metodosEntrada NOTIFY cambiado)
    Q_PROPERTY(QString distribucionTeclado READ distribucionTeclado NOTIFY cambiado)
    // Ratón y panel táctil ([input] de wayfire.ini)
    Q_PROPERTY(QVariantMap raton READ raton NOTIFY cambiado)
    Q_PROPERTY(bool hayPanelTactil READ hayPanelTactil NOTIFY cambiado)
    // Compartir: escritorio remoto (VNC) — "activo" | "inactivo" | "no-instalado"
    Q_PROPERTY(QString escritorioRemoto READ escritorioRemoto NOTIFY cambiado)
    Q_PROPERTY(QStringList direccionesIp READ direccionesIp NOTIFY cambiado)
    // Impresoras, instantaneas, VPN, discos
    Q_PROPERTY(QVariantList impresoras READ impresoras NOTIFY cambiado)
    Q_PROPERTY(QString tipoInstantaneas READ tipoInstantaneas NOTIFY cambiado)
    Q_PROPERTY(QVariantList instantaneas READ instantaneas NOTIFY cambiado)
    Q_PROPERTY(QVariantList vpns READ vpns NOTIFY cambiado)
    Q_PROPERTY(QVariantList volumenes READ volumenes NOTIFY cambiado)
    Q_PROPERTY(QVariantList discos READ discos NOTIFY cambiado)
    // Estado general
    Q_PROPERTY(QString ocupado READ ocupado NOTIFY cambiado)
    Q_PROPERTY(QString aviso READ aviso NOTIFY cambiado)
    Q_PROPERTY(bool live READ live CONSTANT)

public:
    explicit Sistema(QObject *parent = nullptr);

    QString perfilEnergia() const { return m_perfil; }
    QStringList perfilesEnergia() const { return m_perfiles; }
    QVariantMap bateria() const { return m_bateria; }
    QVariantMap inactividad() const { return m_inactividad; }
    QString cortafuegos() const { return m_cortafuegos; }
    QString arranqueSeguro() const { return m_sb; }
    QString arranqueSeguroTexto() const { return m_sbTexto; }
    QString huella() const { return m_huella; }
    bool huellaActiva() const { return m_huellaActiva; }
    bool registrandoHuella() const { return m_registro != nullptr; }
    QString mensajeHuella() const { return m_mensajeHuella; }
    bool lector() const { return m_lector; }
    bool tecladoPantalla() const { return m_tecladoPantalla; }
    bool metodosEntrada() const { return m_entrada; }
    QString distribucionTeclado() const { return m_teclado; }
    QVariantMap raton() const { return m_raton; }
    bool hayPanelTactil() const { return m_panelTactil; }
    QVariantList impresoras() const { return m_impresoras; }
    QString tipoInstantaneas() const { return m_tipoInst; }
    QVariantList instantaneas() const { return m_instantaneas; }
    QVariantList vpns() const { return m_vpns; }
    QVariantList volumenes() const { return m_volumenes; }
    QVariantList discos() const { return m_discos; }
    QString ocupado() const { return m_ocupado; }
    QString aviso() const { return m_aviso; }
    bool live() const;

    // Vuelve a leer lo que ensena una seccion (al abrirla).
    Q_INVOKABLE void refrescar(const QString &seccion);

    Q_INVOKABLE void setPerfilEnergia(const QString &perfil);
    Q_INVOKABLE void setInactividad(const QString &clave, int minutos);
    Q_INVOKABLE void bloquearAhora();

    Q_INVOKABLE void setCortafuegos(bool activo);
    Q_INVOKABLE void prepararArranqueSeguro();
    Q_INVOKABLE void registrarHuella();
    Q_INVOKABLE void cancelarHuella();
    Q_INVOKABLE void setHuellaActiva(bool activa);

    Q_INVOKABLE void setLector(bool activo);
    Q_INVOKABLE void setTecladoPantalla(bool activo);
    Q_INVOKABLE void setMetodosEntrada(bool activo);
    // "es", "latam", "us"... y variante ("intl", "" ...): al momento
    Q_INVOKABLE void setDistribucion(const QString &capa, const QString &variante);
    Q_INVOKABLE void setRaton(const QString &clave, const QVariant &valor);
    Q_INVOKABLE void setEscritorioRemoto(bool activo);
    QString escritorioRemoto() const { return m_remoto; }
    QStringList direccionesIp() const { return m_ips; }

    Q_INVOKABLE void crearInstantanea(const QString &descripcion);
    Q_INVOKABLE void borrarInstantanea(int numero);

    Q_INVOKABLE void setVpn(const QString &nombre, bool activa);
    Q_INVOKABLE void importarVpn(const QString &url);

    // Abre una herramienta grafica (solo las de la lista de main: nada arbitrario).
    Q_INVOKABLE bool abrir(const QString &programa);
    Q_INVOKABLE bool instalado(const QString &programa) const;
    Q_INVOKABLE QString tamanoLegible(double bytes) const;

signals:
    void cambiado();

private:
    using Fin = std::function<void(int codigo, const QString &salida, const QString &error)>;
    void correr(const QString &programa, const QStringList &args, Fin fin, int msMax = 60000);
    void comoAdmin(const QString &operacion, const QStringList &orden, Fin fin);
    void avisar(const QString &texto);
    void ocupar(const QString &que);

    void leerEnergia();
    void leerBateria();
    void leerInactividad();
    void leerSeguridad();
    void leerAccesibilidad();
    void leerTeclado();
    void leerRaton();
    void leerImpresoras();
    void leerInstantaneas();
    void leerVpns();
    void leerAlmacenamiento();

    QString rutaConfig(const QString &fichero) const;
    QVariantMap leerConf(const QString &fichero) const;
    void escribirConf(const QString &fichero, const QString &clave, const QString &valor);

    QString m_perfil;
    QStringList m_perfiles;
    QVariantMap m_bateria;
    QVariantMap m_inactividad;
    QString m_cortafuegos = QStringLiteral("desconocido");
    QString m_remoto = QStringLiteral("inactivo");
    QStringList m_ips;
    void leerCompartir();
    QString m_sb, m_sbTexto;
    QString m_huella;
    bool m_huellaActiva = false;
    QProcess *m_registro = nullptr;
    QString m_mensajeHuella;
    bool m_lector = false;
    bool m_tecladoPantalla = false;
    bool m_entrada = false;
    QString m_teclado;
    QVariantMap m_raton;
    bool m_panelTactil = false;
    QVariantList m_impresoras;
    QString m_tipoInst;
    QVariantList m_instantaneas;
    QVariantList m_vpns;
    QVariantList m_volumenes;
    QVariantList m_discos;
    QString m_ocupado;
    QString m_aviso;
};
