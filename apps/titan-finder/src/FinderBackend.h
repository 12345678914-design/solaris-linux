#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QFileInfo>
#include <QDir>
#include <QFile>
#include <QFileSystemWatcher>
#include <QTimer>
#include <QFutureWatcher>
#include <functional>
#include <atomic>

QString sinAcentos(const QString &t);

class FinderBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY currentPathChanged)
    Q_PROPERTY(QString currentPathName READ currentPathName NOTIFY currentPathChanged)
    Q_PROPERTY(bool canGoBack READ canGoBack NOTIFY historyChanged)
    Q_PROPERTY(bool canGoForward READ canGoForward NOTIFY historyChanged)
    Q_PROPERTY(bool canGoUp READ canGoUp NOTIFY currentPathChanged)
    Q_PROPERTY(QVariantList pathSegments READ pathSegments NOTIFY currentPathChanged)
    Q_PROPERTY(QVariantList entries READ entries NOTIFY entriesChanged)
    Q_PROPERTY(QVariantList favorites READ favorites NOTIFY favoritesChanged)
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    Q_PROPERTY(bool showHiddenFiles READ showHiddenFiles WRITE setShowHiddenFiles NOTIFY showHiddenFilesChanged)
    Q_PROPERTY(QString searchQuery READ searchQuery WRITE setSearchQuery NOTIFY searchQueryChanged)
    Q_PROPERTY(QString viewMode READ viewMode WRITE setViewMode NOTIFY viewModeChanged)
    // Panel de detalles a la derecha (vista previa, datos y acciones); se recuerda
    // Deshacer (Ctrl+Z): texto de lo último que se puede deshacer ("" = nada)
    Q_PROPERTY(QString textoDeshacer READ textoDeshacer NOTIFY deshacerChanged)
    // Recientes: lista virtual con lo último abierto (recently-used.xbel)
    Q_PROPERTY(bool enRecientes READ enRecientes NOTIFY currentPathChanged)
    // Red: otros equipos y carpetas compartidas (Red.h)
    Q_PROPERTY(bool enRed READ enRed NOTIFY currentPathChanged)
    // Pestañas, como en el Explorador de Windows 11: [{titulo, ruta}]
    Q_PROPERTY(QVariantList pestanas READ pestanas NOTIFY pestanasChanged)
    Q_PROPERTY(int pestanaActual READ pestanaActual NOTIFY pestanasChanged)
    // Para arrastrar pestañas entre ventanas (cada ventana es un proceso)
    Q_PROPERTY(qint64 proceso READ proceso CONSTANT)
    Q_PROPERTY(bool buscandoRed READ buscandoRed NOTIFY currentPathChanged)
    // La búsqueda también mira dentro de las subcarpetas (en otro hilo)
    Q_PROPERTY(bool buscando READ buscando NOTIFY busquedaChanged)
    Q_PROPERTY(bool panelDetalles READ panelDetalles WRITE setPanelDetalles NOTIFY panelDetallesChanged)
    Q_PROPERTY(QString sortBy READ sortBy WRITE setSortBy NOTIFY sortChanged)
    Q_PROPERTY(bool sortAscending READ sortAscending WRITE setSortAscending NOTIFY sortChanged)
    Q_PROPERTY(QString totalItemsText READ totalItemsText NOTIFY entriesChanged)
    Q_PROPERTY(QString freeSpaceText READ freeSpaceText NOTIFY freeSpaceTextChanged)
    Q_PROPERTY(bool hasClipboard READ hasClipboard NOTIFY clipboardChanged)
    Q_PROPERTY(QString clipboardPath READ clipboardPath NOTIFY clipboardChanged)
    // Papelera, avisos y operaciones en segundo plano
    Q_PROPERTY(bool enPapelera READ enPapelera NOTIFY currentPathChanged)
    Q_PROPERTY(bool papeleraVacia READ papeleraVacia NOTIFY entriesChanged)
    Q_PROPERTY(QString rutaCasa READ rutaCasa CONSTANT)
    Q_PROPERTY(bool dentroDeCasaActual READ dentroDeCasaActual NOTIFY currentPathChanged)
    Q_PROPERTY(bool puedeEscribir READ puedeEscribir NOTIFY currentPathChanged)
    Q_PROPERTY(bool portapapelesCortado READ portapapelesCortado NOTIFY clipboardChanged)
    Q_PROPERTY(int portapapelesCantidad READ portapapelesCantidad NOTIFY clipboardChanged)
    Q_PROPERTY(bool ocupado READ ocupado NOTIFY ocupadoChanged)
    Q_PROPERTY(QString aviso READ aviso NOTIFY avisoChanged)

public:
    explicit FinderBackend(QObject *parent = nullptr);
    ~FinderBackend() override = default;

    QString currentPath() const { return m_currentPath; }
    QString currentPathName() const;
    bool canGoBack() const { return m_historyIndex > 0; }
    bool canGoForward() const { return m_historyIndex + 1 < m_history.size(); }
    bool canGoUp() const;
    QVariantList pathSegments() const;
    QVariantList entries() const { return m_filteredEntries; }
    QVariantList favorites() const { return m_favorites; }
    QVariantList devices() const { return m_devices; }

    bool showHiddenFiles() const { return m_showHiddenFiles; }
    void setShowHiddenFiles(bool show);

    QString searchQuery() const { return m_searchQuery; }
    void setSearchQuery(const QString &query);

    QString viewMode() const { return m_viewMode; }
    bool panelDetalles() const { return m_panelDetalles; }
    QString textoDeshacer() const;
    bool enRecientes() const { return m_currentPath == rutaRecientes(); }
    bool enRed() const;
    bool buscandoRed() const { return m_buscandoRed; }
    QVariantList pestanas() const;
    int pestanaActual() const { return m_actual; }
    qint64 proceso() const;
    bool buscando() const { return m_buscando; }
    static QString rutaRecientes() { return QStringLiteral("recent:///"); }
    void setPanelDetalles(bool v);
    void setViewMode(const QString &mode);

    QString sortBy() const { return m_sortBy; }
    void setSortBy(const QString &by);

    bool sortAscending() const { return m_sortAscending; }
    void setSortAscending(bool asc);

    QString totalItemsText() const;
    QString freeSpaceText() const { return m_freeSpaceText; }
    bool hasClipboard() const { return portapapelesCantidad() > 0; }
    QString clipboardPath() const { return m_clipboardPath; }

    bool enPapelera() const;
    bool papeleraVacia() const;
    bool dentroDeCasaActual() const { return dentroDeCasa(m_currentPath); }
    QString rutaCasa() const { return QDir::homePath(); }
    bool puedeEscribir() const;
    bool portapapelesCortado() const;
    int portapapelesCantidad() const;
    bool ocupado() const { return m_ocupado; }
    QString aviso() const { return m_aviso; }

    // Reglas: mover solo dentro de la carpeta personal (y nunca sus carpetas
    // principales); lo demás se copia. Ver Operaciones.cpp.
    Q_INVOKABLE bool dentroDeCasa(const QString &path) const;
    Q_INVOKABLE bool esProtegida(const QString &path) const;
    Q_INVOKABLE void arrastrar(const QStringList &paths);
    Q_INVOKABLE void soltar(const QVariantList &urls, const QString &destino, bool copiar);
    Q_INVOKABLE void cortar(const QStringList &paths);
    Q_INVOKABLE bool eliminarDefinitivamente(const QStringList &paths);
    Q_INVOKABLE bool vaciarPapelera();
    Q_INVOKABLE bool restaurar(const QStringList &paths);
    Q_INVOKABLE void cerrarAviso();
    // Comprimir en .zip (como Ubuntu) y "Extraer aquí" (zip, tar.*, 7z, rar)
    Q_INVOKABLE bool esComprimido(const QString &path) const;
    Q_INVOKABLE void comprimir(const QStringList &paths);
    Q_INVOKABLE void extraer(const QString &path);
    // Menú del clic derecho: documentos nuevos, "Abrir con" y "Copiar ruta"
    Q_INVOKABLE QVariantList tiposNuevos() const;
    Q_INVOKABLE QString nuevoArchivo(const QString &tipo);
    Q_INVOKABLE QVariantList aplicacionesPara(const QString &path) const;
    Q_INVOKABLE void abrirCon(const QString &path, const QString &desktop);
    Q_INVOKABLE void copiarRuta(const QStringList &paths);
    Q_INVOKABLE QString escritorio() const { return QDir::homePath() + QStringLiteral("/Escritorio"); }

    Q_INVOKABLE void goTo(const QString &path);
    Q_INVOKABLE void goBack();
    Q_INVOKABLE void goForward();
    Q_INVOKABLE void goUp();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void openItem(const QString &path);
    // Pestañas. ruta "" = Carpeta personal. activar=false: se abre detrás
    Q_INVOKABLE void nuevaPestana(const QString &ruta = QString(), bool activar = true);
    // false si era la única (entonces se cierra la ventana)
    Q_INVOKABLE bool cerrarPestana(int i);
    Q_INVOKABLE void irAPestana(int i);
    Q_INVOKABLE void moverPestana(int de, int a);
    // JSON con la carpeta y el historial, para soltarla en otra ventana
    Q_INVOKABLE QString datosPestana(int i);
    // La que llega soltada desde otra ventana del Explorador; en "antes" (-1 = al final)
    Q_INVOKABLE bool recibirPestana(const QString &json, int antes = -1);
    // Sacarla a una ventana nueva (soltada fuera de cualquier ventana)
    Q_INVOKABLE void separarPestana(int i);
    Q_INVOKABLE void abrirEnVentanaNueva(const QString &ruta);
    // Usuario y contraseña de una carpeta compartida (ver credencialesRed)
    Q_INVOKABLE void responderCredenciales(bool aceptar, const QString &usuario, const QString &dominio,
                                           const QString &clave, bool anonimo);
    Q_INVOKABLE void openTerminal(const QString &path = QString());
    Q_INVOKABLE bool createFolder(const QString &name = QString());
    Q_INVOKABLE bool deleteItem(const QString &path);
    Q_INVOKABLE bool deleteItems(const QStringList &paths);
    Q_INVOKABLE bool renameItem(const QString &oldPath, const QString &newName);
    Q_INVOKABLE bool sendToDesktop(const QString &path);
    Q_INVOKABLE void startDrag(const QString &path);
    Q_INVOKABLE bool importFile(const QString &urlOrPath, const QString &targetDir = QString());
    Q_INVOKABLE void copyItem(const QString &path);
    Q_INVOKABLE void copyItems(const QStringList &paths);
    Q_INVOKABLE bool moveItems(const QStringList &paths, const QString &targetDir = QString());
    Q_INVOKABLE bool paste(const QString &destinationDir = QString());
    Q_INVOKABLE QVariantMap getFileProperties(const QString &path);
    Q_INVOKABLE QVariantMap detalles(const QString &path) const;   // panel de detalles
    Q_INVOKABLE void deshacer();
    Q_INVOKABLE void anclar(const QString &path);       // a Acceso rápido
    Q_INVOKABLE void desanclar(const QString &path);
    Q_INVOKABLE bool estaAnclada(const QString &path) const;
    Q_INVOKABLE void sort(const QString &criteria);
    Q_INVOKABLE void refreshDevices();
    Q_INVOKABLE bool mountDevice(const QString &deviceNode);
    Q_INVOKABLE bool unmountDevice(const QString &deviceNode);
    Q_INVOKABLE bool mountAndOpen(const QString &deviceNode);

signals:
    void currentPathChanged();
    void historyChanged();
    void entriesChanged();
    void favoritesChanged();
    void devicesChanged();
    void showHiddenFilesChanged();
    void searchQueryChanged();
    void viewModeChanged();
    void panelDetallesChanged();
    void sortChanged();
    void freeSpaceTextChanged();
    void clipboardChanged();
    void ocupadoChanged();
    void avisoChanged();
    void deshacerChanged();
    void busquedaChanged();
    void pestanasChanged();
    void credencialesRed(const QString &mensaje, const QString &usuario, const QString &dominio, bool anonimoPosible);

private slots:
    void onDirectoryChanged(const QString &path);

private:
    void loadDirectory(const QString &path);
    void filterAndSortEntries();
    void initFavorites();
    void updateFreeSpace();
    QString resolveIcon(const QFileInfo &info) const;
    QString resolveType(const QFileInfo &info) const;
    QString formatBytes(qint64 bytes) const;

    QString m_currentPath;
    QStringList m_history;
    int m_historyIndex;
    bool m_showHiddenFiles;
    QString m_searchQuery;
    QString m_viewMode; // "grid" or "list"
    QString m_sortBy;   // "name", "date", "size", "kind"
    bool m_sortAscending;
    bool m_panelDetalles = true;
    QString m_freeSpaceText;

    QVariantList m_rawEntries;
    QVariantList m_filteredEntries;
    QVariantList m_favorites;
    QVariantList m_devices;
    QFileSystemWatcher *m_watcher;
    QTimer *m_deviceTimer;
    QString m_clipboardPath;

    void ponerAviso(const QString &t);
    void lanzar(const QVariantList &trabajos, bool limpiarPortapapeles);
    void enFondo(const QString &mensaje, const std::function<QString()> &trabajo);
    QString rutaPapelera() const;
    bool m_ocupado = false;
    QString m_aviso;
    QFutureWatcher<QString> m_operacion;

    // Deshacer: pila de {tipo, pares[{a, b}], texto}; tipo = mover | copiar |
    // renombrar | papelera | crear. Lo que se deshace no se vuelve a apuntar.
    void apuntarDeshacer(const QString &tipo, const QVariantList &pares, const QString &texto);
    QList<QVariantMap> m_deshacer;
    bool m_deshaciendo = false;

    // Recientes y búsqueda en subcarpetas
    void cargarRecientes();
    class Red *m_red = nullptr;
    bool m_buscandoRed = false;
    struct Pestana { QStringList historial; int indice = -1; };
    QList<Pestana> m_pestanas{Pestana{}};
    int m_actual = 0;
    void guardarPestana();
    void cargarPestana(int i);
    QString nombreDe(const QString &ruta) const;
    void apuntarReciente(const QString &path);
    void buscarEnSubcarpetas();
    QVariantMap entradaDe(const QFileInfo &info) const;
    QFutureWatcher<QVariantList> m_busqueda;
    QTimer *m_temporizadorBusqueda = nullptr;
    std::atomic<int> m_generacionBusqueda{0};   // la lee el hilo de búsqueda
    bool m_buscando = false;
    QVariantList m_extraBusqueda;   // resultados de las subcarpetas
};

