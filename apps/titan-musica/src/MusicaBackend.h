// Inti OS - Música: biblioteca, vistas (canciones, álbumes, artistas,
// géneros, listas, favoritas), cola de reproducción, letras, temporizador
// y control desde fuera (MPRIS: la Isla, las teclas multimedia, playerctl).
#pragma once

#include "Biblioteca.h"

#include <QAudioOutput>
#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QHash>
#include <QMediaPlayer>
#include <QObject>
#include <QSet>
#include <QTimer>
#include <QVariantList>

#include <atomic>

class MusicaBackend : public QObject
{
    Q_OBJECT
    // Biblioteca
    Q_PROPERTY(bool escaneando READ escaneando NOTIFY escaneandoChanged)
    Q_PROPERTY(int totalCanciones READ totalCanciones NOTIFY bibliotecaChanged)
    Q_PROPERTY(QVariantList albumes READ albumes NOTIFY bibliotecaChanged)
    Q_PROPERTY(QVariantList artistas READ artistas NOTIFY bibliotecaChanged)
    Q_PROPERTY(QVariantList generos READ generos NOTIFY bibliotecaChanged)
    Q_PROPERTY(QVariantList listas READ listas NOTIFY listasChanged)
    Q_PROPERTY(QStringList carpetas READ carpetas NOTIFY carpetasChanged)
    Q_PROPERTY(int datosVersion READ datosVersion NOTIFY datosChanged)
    // Vista actual
    Q_PROPERTY(QString vista READ vista NOTIFY vistaChanged)
    Q_PROPERTY(QVariantMap infoVista READ infoVista NOTIFY cancionesChanged)
    Q_PROPERTY(QVariantList canciones READ canciones NOTIFY cancionesChanged)
    Q_PROPERTY(QVariantList albumesArtista READ albumesArtista NOTIFY cancionesChanged)
    Q_PROPERTY(QString orden READ orden NOTIFY cancionesChanged)
    Q_PROPERTY(bool ordenAsc READ ordenAsc NOTIFY cancionesChanged)
    Q_PROPERTY(QString busqueda READ busqueda WRITE setBusqueda NOTIFY busquedaChanged)
    Q_PROPERTY(bool puedeVolver READ puedeVolver NOTIFY vistaChanged)
    // Reproducción
    Q_PROPERTY(QVariantMap actual READ actual NOTIFY actualChanged)
    Q_PROPERTY(bool reproduciendo READ reproduciendo NOTIFY estadoChanged)
    Q_PROPERTY(qint64 posicion READ posicion NOTIFY posicionChanged)
    Q_PROPERTY(qint64 duracion READ duracion NOTIFY duracionChanged)
    Q_PROPERTY(qreal volumen READ volumen WRITE setVolumen NOTIFY volumenChanged)
    Q_PROPERTY(bool silencio READ silencio NOTIFY volumenChanged)
    Q_PROPERTY(bool aleatorio READ aleatorio NOTIFY modoChanged)
    Q_PROPERTY(int repetir READ repetir NOTIFY modoChanged) // 0 no, 1 todo, 2 una
    Q_PROPERTY(QVariantList cola READ cola NOTIFY colaChanged) // lo que viene después
    Q_PROPERTY(QVariantList letra READ letra NOTIFY letraChanged)
    Q_PROPERTY(bool letraSincronizada READ letraSincronizada NOTIFY letraChanged)
    Q_PROPERTY(int temporizador READ temporizador NOTIFY temporizadorChanged) // min restantes; -1 fin de canción
    Q_PROPERTY(QString aviso READ aviso NOTIFY avisoChanged)

public:
    explicit MusicaBackend(QObject *parent = nullptr);
    ~MusicaBackend() override;

    bool escaneando() const { return m_escaneando; }
    int totalCanciones() const { return m_pistas.size(); }
    QVariantList albumes() const { return m_albumes; }
    QVariantList artistas() const { return m_artistas; }
    QVariantList generos() const { return m_generos; }
    QVariantList listas() const;
    QStringList carpetas() const { return m_carpetas; }
    int datosVersion() const { return m_datosVersion; }

    QString vista() const { return m_vista; }
    QVariantMap infoVista() const { return m_infoVista; }
    QVariantList canciones() const { return m_canciones; }
    QVariantList albumesArtista() const { return m_albumesArtista; }
    QString orden() const { return m_orden; }
    bool ordenAsc() const { return m_ordenAsc; }
    QString busqueda() const { return m_busqueda; }
    void setBusqueda(const QString &q);
    bool puedeVolver() const { return !m_pila.isEmpty(); }

    QVariantMap actual() const;
    bool reproduciendo() const;
    qint64 posicion() const { return m_posicion; }
    qint64 duracion() const { return m_duracion; }
    qreal volumen() const;
    bool silencio() const;
    bool aleatorio() const { return m_aleatorio; }
    int repetir() const { return m_repetir; }
    QVariantList cola() const;
    QVariantList letra() const { return m_letra; }
    bool letraSincronizada() const { return m_letraSinc; }
    int temporizador() const;
    QString aviso() const { return m_aviso; }

    // Para MPRIS
    QString rutaActual() const;
    bool hayAnterior() const { return m_indice >= 0; }
    bool haySiguiente() const;

public slots:
    // Navegación: "canciones", "recientes", "albumes", "artistas", "generos",
    // "favoritas", "masEscuchadas", "album:<clave>", "artista:<nombre>",
    // "genero:<nombre>", "lista:<id>"
    void abrir(const QString &vista);
    void volver();
    void ordenarPor(const QString &campo);

    // Reproducción
    void playTrack(int indice);                    // de la vista actual
    void reproducirVista(bool aleatorio);
    void reproducirRutas(const QStringList &rutas, int desde, bool aleatorio);
    void reproducirAlbum(const QString &clave, bool aleatorio);
    void play();
    void pause();
    void togglePlay();
    void stop();
    void siguiente();
    void anterior();
    void seek(qint64 ms);
    void setVolumen(qreal v);
    void toggleSilencio();
    void toggleAleatorio();
    void setAleatorio(bool a);
    void cicloRepetir();
    void setRepetir(int modo);

    // Cola ("A continuación")
    void aContinuacion(const QStringList &rutas);
    void aLaCola(const QStringList &rutas);
    void quitarDeCola(int i);       // i relativo a `cola`
    void saltarACola(int i);
    void moverEnCola(int desde, int hasta);
    void vaciarCola();

    // Favoritas y listas
    bool esFavorita(const QString &ruta) const;
    void alternarFavorita(const QString &ruta);
    QString crearLista(const QString &nombre, const QStringList &rutas);
    void renombrarLista(const QString &id, const QString &nombre);
    void borrarLista(const QString &id);
    void anadirALista(const QString &id, const QStringList &rutas);
    void quitarDeLista(const QString &id, int indice);

    // Archivos
    QVariantMap detalles(const QString &ruta) const;
    QString guardarEtiquetas(const QString &ruta, const QVariantMap &campos);
    void moverAPapelera(const QStringList &rutas);
    void mostrarEnFinder(const QString &ruta = QString());
    void anadirCarpeta(const QString &urlOruta);
    void quitarCarpeta(const QString &ruta);
    void refrescar();
    void openFile(const QString &ruta);
    void abrirArchivos(const QStringList &urls);   // soltar en la ventana

    void setTemporizador(int minutos);             // 0 quita, -1 al acabar la canción
    void cerrarAviso();
    void levantar() { emit levantarVentana(); }

signals:
    void escaneandoChanged();
    void bibliotecaChanged();
    void listasChanged();
    void carpetasChanged();
    void datosChanged();
    void vistaChanged();
    void cancionesChanged();
    void busquedaChanged();
    void actualChanged();
    void estadoChanged();
    void posicionChanged();
    void duracionChanged();
    void volumenChanged();
    void modoChanged();
    void colaChanged();
    void letraChanged();
    void temporizadorChanged();
    void avisoChanged();
    void saltoDePosicion(qint64 ms);   // para MPRIS Seeked
    void levantarVentana();

private:
    void escanear();
    void alTerminarEscaneo();
    void reconstruirIndices();
    void construirVista();
    QVariantMap mapa(const Pista &p) const;
    QVariantMap mapaDeRuta(const QString &ruta) const;
    void cargar(int indice, bool sonar);
    void alTerminarPista();
    void ponerAviso(const QString &t);
    void cargarDatos();
    void guardarDatosLuego();
    void guardarDatos();
    void guardarSesion();
    void restaurarSesion();
    void contarReproduccion();
    QStringList rutasVista() const;

    QMediaPlayer *m_player;
    QAudioOutput *m_salida;
    QFileSystemWatcher *m_vigia;
    QTimer m_reescaneo;
    QTimer m_guardar;
    QTimer m_temporizador;
    QFutureWatcher<QVector<Pista>> m_futuro;
    std::atomic_bool m_cancelar {false};
    bool m_escaneando = false;
    bool m_pendiente = false;

    QStringList m_carpetas;
    QStringList m_sueltos;
    QVector<Pista> m_pistas;
    QHash<QString, int> m_porRuta;
    QVariantList m_albumes;
    QVariantList m_artistas;
    QVariantList m_generos;

    // Datos guardados
    QSet<QString> m_favoritas;
    QHash<QString, int> m_reproducciones;
    QHash<QString, qint64> m_ultimaVez;
    struct Lista { QString id; QString nombre; QStringList rutas; };
    QVector<Lista> m_listas;
    int m_datosVersion = 0;

    QString m_vista = QStringLiteral("canciones");
    QStringList m_pila;
    QVariantMap m_infoVista;
    QVariantList m_canciones;
    QVariantList m_albumesArtista;
    QString m_orden;
    bool m_ordenAsc = true;
    QString m_busqueda;

    QStringList m_base;      // orden original del contexto
    QStringList m_cola;      // orden de reproducción (con aleatorio, mezclado)
    int m_indice = -1;
    bool m_aleatorio = false;
    int m_repetir = 0;
    qint64 m_posicion = 0;
    qint64 m_duracion = 0;
    qint64 m_posicionPendiente = -1;
    bool m_contada = false;
    QVariantList m_letra;
    bool m_letraSinc = false;
    bool m_finDeCancion = false;
    qint64 m_finTemporizador = 0;
    QString m_aviso;
    QVariantMap m_mapaActual;
    qreal m_volumen = 0.8;
    int m_erroresSeguidos = 0;
};
