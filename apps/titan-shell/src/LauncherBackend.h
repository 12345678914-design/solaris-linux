#ifndef LAUNCHERBACKEND_H
#define LAUNCHERBACKEND_H

#include <QObject>
#include <QString>
#include <QVariantList>

class QFileSystemWatcher;

class LauncherBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)
    Q_PROPERTY(QVariantList recentApps READ recentApps NOTIFY recentAppsChanged)
    // Categorias con apps: [{id, nombre}], "todas" primero
    Q_PROPERTY(QVariantList categorias READ categorias NOTIFY appsChanged)
    Q_PROPERTY(QString categoria READ categoria WRITE setCategoria NOTIFY appsChanged)
    
public:
    explicit LauncherBackend(QObject *parent = nullptr);
    ~LauncherBackend() override;
    
    QVariantList apps() const;
    QVariantList recentApps() const { return QVariantList(); }
    
    Q_INVOKABLE void search(const QString &query);
    // enDock: rebota en el Dock (sin indicador junto al puntero)
    Q_INVOKABLE void launch(const QString &exec, bool enDock = false, const QString &icono = QString());
    Q_INVOKABLE void reload();
    QVariantList categorias() const { return m_categorias; }
    QString categoria() const { return m_categoria; }
    void setCategoria(const QString &c);
    
signals:
    void appsChanged();
    void recentAppsChanged();
    
private:
    void loadApps();
    void filtrar();
    
    QVariantList m_apps;
    QVariantList m_filteredApps;
    QVariantList m_categorias;
    QString m_categoria = QStringLiteral("todas");
    QString m_busqueda;
    QFileSystemWatcher *m_watcher;
};

#endif
