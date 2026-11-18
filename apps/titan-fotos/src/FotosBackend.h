// Inti OS - Fotos: biblioteca, álbumes, favoritas, visor y editor.
#pragma once

#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QHash>
#include <QImage>
#include <QMutex>
#include <QObject>
#include <QSet>
#include <QString>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

// Datos de una foto (lo que se guarda en el índice en caché)
struct Foto
{
    QString ruta;
    qint64 bytes = 0;
    qint64 mtime = 0;   // ms
    qint64 fecha = 0;   // ms: captura (EXIF) o modificación
    int ancho = 0;
    int alto = 0;
    QString camara;
    QString clave;      // md5 de la URI (miniaturas freedesktop)
};

class FotosBackend : public QObject
{
    Q_OBJECT
    // Lista visible (según vista, búsqueda y orden)
    Q_PROPERTY(QVariantList photos READ photos NOTIFY photosChanged)
    Q_PROPERTY(int count READ count NOTIFY photosChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY photosChanged)
    Q_PROPERTY(QString vista READ vista NOTIFY vistaChanged)
    Q_PROPERTY(QString tituloVista READ tituloVista NOTIFY vistaChanged)
    Q_PROPERTY(QString searchQuery READ searchQuery WRITE setSearchQuery NOTIFY searchQueryChanged)
    Q_PROPERTY(QString orden READ orden NOTIFY photosChanged)
    Q_PROPERTY(bool ordenAsc READ ordenAsc NOTIFY photosChanged)
    Q_PROPERTY(bool cargando READ cargando NOTIFY cargandoChanged)
    Q_PROPERTY(QVariantMap cuentas READ cuentas NOTIFY photosChanged)
    Q_PROPERTY(QVariantList albumes READ albumes NOTIFY albumesChanged)
    Q_PROPERTY(QStringList carpetas READ carpetas NOTIFY carpetasChanged)
    // Visor
    Q_PROPERTY(int currentIndex READ currentIndex WRITE selectPhoto NOTIFY currentPhotoChanged)
    Q_PROPERTY(QVariantMap currentPhoto READ currentPhoto NOTIFY currentPhotoChanged)
    Q_PROPERTY(QString aviso READ aviso NOTIFY avisoChanged)

public:
    explicit FotosBackend(QObject *parent = nullptr);
    ~FotosBackend() override;

    QVariantList photos() const { return m_visibles; }
    int count() const { return m_visibles.size(); }
    QString statusText() const;
    QString vista() const { return m_vista; }
    QString tituloVista() const;
    QString searchQuery() const { return m_busqueda; }
    void setSearchQuery(const QString &q);
    QString orden() const { return m_orden; }
    bool ordenAsc() const { return m_ordenAsc; }
    bool cargando() const { return m_cargando; }
    QVariantMap cuentas() const;
    QVariantList albumes() const;
    QStringList carpetas() const { return m_carpetasExtra; }
    int currentIndex() const { return m_indice; }
    QVariantMap currentPhoto() const;
    QString aviso() const { return m_aviso; }

    // Usados por los proveedores de imágenes (otro hilo)
    QString rutaDeClave(const QString &clave) const;
    QImage vistaPrevia(const QString &params, const QSize &pedido);

    // ---- Vistas y orden
    Q_INVOKABLE void abrir(const QString &vista);
    Q_INVOKABLE void ordenarPor(const QString &campo);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void anadirCarpeta(const QString &url);
    Q_INVOKABLE void quitarCarpeta(const QString &ruta);
    // ---- Visor
    Q_INVOKABLE void selectPhoto(int index);
    Q_INVOKABLE void nextPhoto();
    Q_INVOKABLE void previousPhoto();
    Q_INVOKABLE void openFile(const QString &filePath);
    Q_INVOKABLE int indiceDe(const QString &ruta) const;
    Q_INVOKABLE QVariantMap detalles(const QString &ruta) const;
    // ---- Acciones (aceptan una o varias rutas)
    Q_INVOKABLE bool esFavorita(const QString &ruta) const { return m_favoritas.contains(ruta); }
    Q_INVOKABLE void alternarFavorita(const QStringList &rutas);
    Q_INVOKABLE int moverAPapelera(const QStringList &rutas);
    Q_INVOKABLE QString renombrar(const QString &ruta, const QString &nombre);
    Q_INVOKABLE void copiarAlPortapapeles(const QStringList &rutas);
    Q_INVOKABLE bool setAsWallpaper(const QString &filePath = QString());
    Q_INVOKABLE void openInFinder(const QString &filePath = QString());
    // ---- Álbumes
    Q_INVOKABLE QString crearAlbum(const QString &nombre, const QStringList &rutas);
    Q_INVOKABLE void renombrarAlbum(const QString &id, const QString &nombre);
    Q_INVOKABLE void borrarAlbum(const QString &id);
    Q_INVOKABLE void anadirAAlbum(const QString &id, const QStringList &rutas);
    Q_INVOKABLE void quitarDeAlbum(const QString &id, const QStringList &rutas);
    // ---- Editor: params "rot;fh;fv;brillo;contraste;saturacion;calidez;filtro;x;y;w;h"
    Q_INVOKABLE void empezarEdicion(const QString &ruta);
    Q_INVOKABLE QString guardarEdicion(const QString &ruta, const QString &params, bool comoCopia);

signals:
    void photosChanged();
    void vistaChanged();
    void searchQueryChanged();
    void cargandoChanged();
    void albumesChanged();
    void carpetasChanged();
    void currentPhotoChanged();
    void avisoChanged();
    void levantarVentana();

private:
    void escanear();
    void alTerminarEscaneo();
    void filtrar(bool conservarFoto = true);
    QVariantMap mapa(const Foto &f) const;
    QStringList directorios() const;
    void guardarConf();
    void cargarConf();
    void avisar(const QString &texto);
    QString origen(const QString &ruta) const;
    const Foto *buscar(const QString &ruta) const;
    void releer(const QString &ruta);

    QList<Foto> m_fotos;                 // biblioteca entera
    QHash<QString, int> m_porRuta;       // ruta -> índice en m_fotos
    QHash<QString, QString> m_claves;    // md5 -> ruta (para el hilo de miniaturas)
    mutable QMutex m_mutexClaves;
    QVariantList m_visibles;
    QStringList m_rutasVisibles;
    QString m_vista = QStringLiteral("fototeca");
    QString m_busqueda;
    QString m_orden = QStringLiteral("fecha");
    bool m_ordenAsc = false;
    bool m_cargando = false;
    int m_indice = -1;
    QString m_aviso;
    QSet<QString> m_favoritas;
    struct Album { QString id, nombre; QStringList rutas; };
    QList<Album> m_albumes;
    QStringList m_carpetasExtra;
    QString m_carpetaSuelta;             // carpeta de un archivo abierto desde fuera
    QFileSystemWatcher *m_watcher;
    QTimer m_reescaneo;
    QFutureWatcher<QList<Foto>> m_escaneo;
    bool m_pendiente = false;
    QList<Foto> m_sueltas;              // fotos de esa carpeta
    QVariantMap m_cuentas;
    // Editor
    QMutex m_mutexEdicion;
    QString m_rutaEdicion;
    QImage m_baseEdicion;                // reducida para la vista previa
};
