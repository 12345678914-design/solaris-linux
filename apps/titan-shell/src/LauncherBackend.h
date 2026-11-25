#ifndef LAUNCHERBACKEND_H
#define LAUNCHERBACKEND_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <atomic>

class QFileSystemWatcher;

class LauncherBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)
    Q_PROPERTY(QVariantList recentApps READ recentApps NOTIFY recentAppsChanged)
    // Categorias con apps: [{id, nombre}], "todas" primero
    Q_PROPERTY(QVariantList categorias READ categorias NOTIFY appsChanged)
    Q_PROPERTY(QString categoria READ categoria WRITE setCategoria NOTIFY appsChanged)
    // Al escribir en el buscador, además de apps: páginas de Ajustes y
    // archivos de la carpeta personal. Todo local: no se envía nada ni hay
    // un indexador funcionando de fondo; se busca solo al escribir.
    //   ajustes:  [{seccion, titulo, detalle}]
    //   archivos: [{ruta, nombre, carpeta, esCarpeta}]
    Q_PROPERTY(QVariantList ajustes READ ajustes NOTIFY resultadosChanged)
    Q_PROPERTY(QVariantList archivos READ archivos NOTIFY resultadosChanged)
    Q_PROPERTY(bool buscandoArchivos READ buscandoArchivos NOTIFY resultadosChanged)
    
public:
    explicit LauncherBackend(QObject *parent = nullptr);
    ~LauncherBackend() override;
    
    QVariantList apps() const;
    QVariantList recentApps() const { return QVariantList(); }
    
    Q_INVOKABLE void search(const QString &query);
    // enDock: rebota en el Dock (sin indicador junto al puntero)
    Q_INVOKABLE void launch(const QString &exec, bool enDock = false, const QString &icono = QString());
    Q_INVOKABLE void reload();

    // Menú del clic derecho de cada app (desktop = su fichero .desktop)
    //   {acciones: [{id, t}], desinstalable, motivo}
    Q_INVOKABLE QVariantMap opcionesApp(const QString &desktop) const;
    Q_INVOKABLE void lanzarAccion(const QString &desktop, const QString &accion, const QString &icono = QString());
    Q_INVOKABLE QString enviarAlEscritorio(const QString &desktop) const;
    // [{k, v}] para la ventana de Propiedades
    Q_INVOKABLE QVariantList propiedadesApp(const QString &desktop) const;
    // Con contraseña de administrador (pkexec titan-desinstalar) o flatpak
    Q_INVOKABLE void desinstalar(const QString &desktop, const QString &nombre);
    QVariantList categorias() const { return m_categorias; }
    QString categoria() const { return m_categoria; }
    QVariantList ajustes() const { return m_ajustes; }
    QVariantList archivos() const { return m_archivos; }
    bool buscandoArchivos() const { return m_buscandoArchivos; }
    void setCategoria(const QString &c);
    
signals:
    void appsChanged();
    void recentAppsChanged();
    void resultadosChanged();
    void desinstalacionTerminada(const QString &nombre, bool ok, const QString &mensaje);
    
private:
    void loadApps();
    void filtrar();
    void buscarAjustes(const QString &q);
    void lanzarBusquedaArchivos();
    
    QVariantList m_apps;
    QVariantList m_filteredApps;
    QVariantList m_categorias;
    QString m_categoria = QStringLiteral("todas");
    QString m_busqueda;
    QFileSystemWatcher *m_watcher;
    QVariantList m_ajustes;
    QVariantList m_archivos;
    bool m_buscandoArchivos = false;
    std::atomic<int> m_generacion{0};
    class QTimer *m_esperaArchivos = nullptr;
};

#endif
