#include "MusicaBackend.h"

#include <QAudio>
#include <QCollator>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QProcess>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <QtConcurrent/QtConcurrentRun>

#include <algorithm>

namespace {

QString rutaConf()
{
    return QDir::homePath() + QStringLiteral("/.config/titan/musica.conf");
}

QString rutaDatos()
{
    return QDir::homePath() + QStringLiteral("/.local/share/titan-musica/datos.json");
}

QString aLocal(const QString &s)
{
    if (s.startsWith(QStringLiteral("file:")))
        return QUrl(s).toLocalFile();
    return s;
}

QCollator &collator()
{
    static QCollator c = [] {
        QCollator x;
        x.setCaseSensitivity(Qt::CaseInsensitive);
        x.setNumericMode(true);
        return x;
    }();
    return c;
}

int cmp(const QString &a, const QString &b)
{
    return collator().compare(a, b);
}

QString textoCanciones(int n)
{
    return n == 1 ? QStringLiteral("1 canción") : QStringLiteral("%1 canciones").arg(n);
}

void mezclar(QStringList &l)
{
    for (int i = l.size() - 1; i > 0; --i)
        l.swapItemsAt(i, QRandomGenerator::global()->bounded(i + 1));
}

} // namespace

MusicaBackend::MusicaBackend(QObject *parent)
    : QObject(parent)
    , m_player(new QMediaPlayer(this))
    , m_salida(new QAudioOutput(this))
    , m_vigia(new QFileSystemWatcher(this))
{
    m_player->setAudioOutput(m_salida);

    connect(m_player, &QMediaPlayer::positionChanged, this, [this](qint64 p) {
        m_posicion = p;
        emit posicionChanged();
        if (!m_contada && m_duracion > 0 && p > qMin<qint64>(m_duracion / 2, 240000))
            contarReproduccion();
    });
    connect(m_player, &QMediaPlayer::durationChanged, this, [this](qint64 d) {
        m_duracion = d;
        emit duracionChanged();
    });
    connect(m_player, &QMediaPlayer::playbackStateChanged, this, [this] {
        emit estadoChanged();
        if (reproduciendo())
            m_erroresSeguidos = 0;
    });
    connect(m_player, &QMediaPlayer::mediaStatusChanged, this, [this](QMediaPlayer::MediaStatus st) {
        if ((st == QMediaPlayer::LoadedMedia || st == QMediaPlayer::BufferedMedia) && m_posicionPendiente >= 0) {
            m_player->setPosition(m_posicionPendiente);
            m_posicionPendiente = -1;
        }
        if (st == QMediaPlayer::EndOfMedia)
            alTerminarPista();
    });
    connect(m_player, &QMediaPlayer::errorOccurred, this, [this](QMediaPlayer::Error e, const QString &) {
        if (e == QMediaPlayer::NoError)
            return;
        const QString t = m_mapaActual.value(QStringLiteral("titulo")).toString();
        ponerAviso(QStringLiteral("No se puede reproducir «%1»").arg(t));
        // Saltar a la siguiente, sin entrar en bucle si ninguna suena.
        if (++m_erroresSeguidos < m_cola.size() && m_indice + 1 < m_cola.size())
            QTimer::singleShot(400, this, [this] { cargar(m_indice + 1, true); });
    });

    m_reescaneo.setSingleShot(true);
    m_reescaneo.setInterval(1500);
    connect(&m_reescaneo, &QTimer::timeout, this, &MusicaBackend::escanear);
    connect(m_vigia, &QFileSystemWatcher::directoryChanged, &m_reescaneo, qOverload<>(&QTimer::start));

    m_guardar.setSingleShot(true);
    m_guardar.setInterval(600);
    connect(&m_guardar, &QTimer::timeout, this, [this] {
        guardarDatos();
        guardarSesion();
    });

    m_temporizador.setInterval(1000);
    connect(&m_temporizador, &QTimer::timeout, this, [this] {
        if (m_finTemporizador > 0 && QDateTime::currentMSecsSinceEpoch() >= m_finTemporizador) {
            pause();
            setTemporizador(0);
            ponerAviso(QStringLiteral("Temporizador: la música se ha detenido"));
        }
        emit temporizadorChanged();
    });

    connect(&m_futuro, &QFutureWatcher<QVector<Pista>>::finished, this, &MusicaBackend::alTerminarEscaneo);

    // Carpetas de la biblioteca
    QSettings conf(rutaConf(), QSettings::IniFormat);
    m_carpetas = conf.value(QStringLiteral("Biblioteca/carpetas")).toStringList();
    if (!conf.contains(QStringLiteral("Biblioteca/carpetas"))) {
        const QStringList candidatas = {
            QStandardPaths::writableLocation(QStandardPaths::MusicLocation),
            QDir::homePath() + QStringLiteral("/Música"),
            QDir::homePath() + QStringLiteral("/Music"),
            QStandardPaths::writableLocation(QStandardPaths::DownloadLocation),
        };
        for (const QString &c : candidatas) {
            const QString canon = QFileInfo(c).canonicalFilePath();
            if (!canon.isEmpty() && !m_carpetas.contains(canon))
                m_carpetas << canon;
        }
    }

    cargarDatos();
    restaurarSesion();
    construirVista();
    escanear();
}

MusicaBackend::~MusicaBackend()
{
    m_cancelar = true;
    m_futuro.waitForFinished();
    guardarDatos();
    guardarSesion();
}

// ---------------------------------------------------------------- biblioteca

void MusicaBackend::escanear()
{
    if (m_escaneando) {
        m_pendiente = true;
        return;
    }
    m_escaneando = true;
    emit escaneandoChanged();
    const QStringList carpetas = m_carpetas;
    const QStringList sueltos = m_sueltos;
    m_futuro.setFuture(QtConcurrent::run([carpetas, sueltos, this] {
        return Biblioteca::escanear(carpetas, sueltos, &m_cancelar);
    }));
}

void MusicaBackend::alTerminarEscaneo()
{
    if (m_cancelar)
        return;
    m_pistas = m_futuro.result();
    m_escaneando = false;
    reconstruirIndices();

    // Vigilar las carpetas (y sus subcarpetas, con un tope).
    if (!m_vigia->directories().isEmpty())
        m_vigia->removePaths(m_vigia->directories());
    QSet<QString> dirs;
    for (const QString &c : std::as_const(m_carpetas)) {
        if (QDir(c).exists())
            dirs.insert(c);
    }
    for (const Pista &p : std::as_const(m_pistas)) {
        if (dirs.size() > 800)
            break;
        dirs.insert(QFileInfo(p.ruta).absolutePath());
    }
    if (!dirs.isEmpty())
        m_vigia->addPaths(QStringList(dirs.begin(), dirs.end()));

    if (!m_mapaActual.isEmpty()) {
        m_mapaActual = mapaDeRuta(rutaActual());
        emit actualChanged();
    }
    construirVista();
    emit escaneandoChanged();
    emit bibliotecaChanged();
    emit listasChanged();
    emit colaChanged();
    if (m_pendiente) {
        m_pendiente = false;
        escanear();
    }
}

void MusicaBackend::reconstruirIndices()
{
    m_porRuta.clear();
    for (int i = 0; i < m_pistas.size(); ++i)
        m_porRuta.insert(m_pistas.at(i).ruta, i);

    // Álbumes
    QHash<QString, QVariantMap> albumes;
    QHash<QString, QVariantMap> artistas;
    QHash<QString, QSet<QString>> albumesDeArtista;
    QHash<QString, QVariantMap> generos;
    for (const Pista &p : std::as_const(m_pistas)) {
        const QString clave = p.claveAlbum();
        const QString portada = p.portada.isEmpty() ? QString() : QUrl::fromLocalFile(p.portada).toString();
        QVariantMap &a = albumes[clave];
        if (a.isEmpty()) {
            a = {{QStringLiteral("clave"), clave}, {QStringLiteral("titulo"), p.album},
                 {QStringLiteral("artista"), p.artistaDeAlbum()}, {QStringLiteral("anio"), p.anio},
                 {QStringLiteral("portada"), portada}, {QStringLiteral("n"), 0},
                 {QStringLiteral("duracion"), qint64(0)}, {QStringLiteral("anadida"), p.mtime}};
        }
        a[QStringLiteral("n")] = a.value(QStringLiteral("n")).toInt() + 1;
        a[QStringLiteral("duracion")] = a.value(QStringLiteral("duracion")).toLongLong() + p.duracion;
        if (a.value(QStringLiteral("portada")).toString().isEmpty() && !portada.isEmpty())
            a[QStringLiteral("portada")] = portada;
        if (p.anio > a.value(QStringLiteral("anio")).toInt())
            a[QStringLiteral("anio")] = p.anio;
        if (p.mtime > a.value(QStringLiteral("anadida")).toLongLong())
            a[QStringLiteral("anadida")] = p.mtime;

        const QString artista = p.artistaDeAlbum();
        QVariantMap &ar = artistas[artista];
        if (ar.isEmpty())
            ar = {{QStringLiteral("nombre"), artista}, {QStringLiteral("n"), 0}, {QStringLiteral("portada"), QString()}};
        ar[QStringLiteral("n")] = ar.value(QStringLiteral("n")).toInt() + 1;
        if (ar.value(QStringLiteral("portada")).toString().isEmpty() && !portada.isEmpty())
            ar[QStringLiteral("portada")] = portada;
        albumesDeArtista[artista].insert(clave);

        if (!p.genero.isEmpty()) {
            QVariantMap &g = generos[p.genero];
            if (g.isEmpty())
                g = {{QStringLiteral("nombre"), p.genero}, {QStringLiteral("n"), 0}, {QStringLiteral("portada"), QString()}};
            g[QStringLiteral("n")] = g.value(QStringLiteral("n")).toInt() + 1;
            if (g.value(QStringLiteral("portada")).toString().isEmpty() && !portada.isEmpty())
                g[QStringLiteral("portada")] = portada;
        }
    }
    auto ordenar = [](QHash<QString, QVariantMap> &h, const char *campo) {
        QVariantList l;
        for (auto it = h.begin(); it != h.end(); ++it) {
            QVariantMap m = it.value();
            if (m.contains(QStringLiteral("duracion")))
                m[QStringLiteral("duracionTexto")] = Biblioteca::duracionLarga(m.value(QStringLiteral("duracion")).toLongLong());
            l << m;
        }
        const QString c = QString::fromLatin1(campo);
        std::sort(l.begin(), l.end(), [c](const QVariant &a, const QVariant &b) {
            return cmp(a.toMap().value(c).toString(), b.toMap().value(c).toString()) < 0;
        });
        return l;
    };
    for (auto it = artistas.begin(); it != artistas.end(); ++it)
        it.value()[QStringLiteral("albumes")] = albumesDeArtista.value(it.key()).size();
    m_albumes = ordenar(albumes, "titulo");
    m_artistas = ordenar(artistas, "nombre");
    m_generos = ordenar(generos, "nombre");
}

QVariantMap MusicaBackend::mapa(const Pista &p) const
{
    QVariantMap m = p.aMapa();
    m[QStringLiteral("reproducciones")] = m_reproducciones.value(p.ruta);
    return m;
}

QVariantMap MusicaBackend::mapaDeRuta(const QString &ruta) const
{
    const auto it = m_porRuta.constFind(ruta);
    if (it != m_porRuta.constEnd())
        return mapa(m_pistas.at(*it));
    if (ruta.isEmpty() || !QFile::exists(ruta))
        return {};
    return mapa(Biblioteca::leer(ruta));
}

QVariantList MusicaBackend::listas() const
{
    QVariantList r;
    for (const Lista &l : m_listas) {
        QStringList portadas;
        qint64 dur = 0;
        for (const QString &ruta : l.rutas) {
            const auto it = m_porRuta.constFind(ruta);
            if (it == m_porRuta.constEnd())
                continue;
            const Pista &p = m_pistas.at(*it);
            dur += p.duracion;
            const QString u = p.portada.isEmpty() ? QString() : QUrl::fromLocalFile(p.portada).toString();
            if (!u.isEmpty() && !portadas.contains(u) && portadas.size() < 4)
                portadas << u;
        }
        r << QVariantMap{{QStringLiteral("id"), l.id}, {QStringLiteral("nombre"), l.nombre},
                         {QStringLiteral("n"), l.rutas.size()}, {QStringLiteral("portadas"), portadas},
                         {QStringLiteral("duracionTexto"), Biblioteca::duracionLarga(dur)}};
    }
    return r;
}

// ---------------------------------------------------------------- vistas

void MusicaBackend::abrir(const QString &vista)
{
    if (!m_busqueda.isEmpty()) {
        m_busqueda.clear();
        emit busquedaChanged();
    }
    const bool raiz = !vista.contains(QLatin1Char(':'));
    if (raiz)
        m_pila.clear();
    else if (vista != m_vista)
        m_pila << m_vista;
    m_vista = vista;
    m_orden.clear();
    m_ordenAsc = true;
    emit vistaChanged();
    construirVista();
}

void MusicaBackend::volver()
{
    if (m_pila.isEmpty())
        return;
    m_vista = m_pila.takeLast();
    m_orden.clear();
    emit vistaChanged();
    construirVista();
}

void MusicaBackend::ordenarPor(const QString &campo)
{
    if (m_orden == campo)
        m_ordenAsc = !m_ordenAsc;
    else {
        m_orden = campo;
        m_ordenAsc = campo != QLatin1String("anadida") && campo != QLatin1String("reproducciones");
    }
    construirVista();
}

void MusicaBackend::setBusqueda(const QString &q)
{
    if (q == m_busqueda)
        return;
    m_busqueda = q;
    emit busquedaChanged();
    construirVista();
}

void MusicaBackend::construirVista()
{
    QVector<int> sel;
    QVariantMap info;
    QString natural; // orden por defecto
    const QString v = m_vista;
    const QString tipo = v.section(QLatin1Char(':'), 0, 0);
    const QString arg = v.section(QLatin1Char(':'), 1);
    m_albumesArtista.clear();

    if (!m_busqueda.trimmed().isEmpty()) {
        const QStringList palabras = m_busqueda.simplified().split(QLatin1Char(' '));
        for (int i = 0; i < m_pistas.size(); ++i) {
            const Pista &p = m_pistas.at(i);
            const QString todo = p.titulo + QLatin1Char(' ') + p.artista + QLatin1Char(' ') + p.album
                                 + QLatin1Char(' ') + p.artistaAlbum + QLatin1Char(' ') + p.genero;
            bool ok = true;
            for (const QString &w : palabras) {
                if (!todo.contains(w, Qt::CaseInsensitive)) {
                    ok = false;
                    break;
                }
            }
            if (ok)
                sel << i;
        }
        info = {{QStringLiteral("tipo"), QStringLiteral("busqueda")},
                {QStringLiteral("titulo"), QStringLiteral("Resultados de «%1»").arg(m_busqueda.trimmed())}};
        natural = QStringLiteral("titulo");
    } else if (tipo == QLatin1String("album")) {
        for (int i = 0; i < m_pistas.size(); ++i)
            if (m_pistas.at(i).claveAlbum() == arg)
                sel << i;
        natural = QStringLiteral("pista");
        for (const QVariant &a : std::as_const(m_albumes)) {
            if (a.toMap().value(QStringLiteral("clave")).toString() == arg) {
                info = a.toMap();
                break;
            }
        }
        info[QStringLiteral("tipo")] = QStringLiteral("album");
    } else if (tipo == QLatin1String("artista")) {
        QSet<QString> claves;
        for (int i = 0; i < m_pistas.size(); ++i) {
            const Pista &p = m_pistas.at(i);
            if (p.artistaDeAlbum() == arg || p.artista == arg) {
                sel << i;
                claves.insert(p.claveAlbum());
            }
        }
        for (const QVariant &a : std::as_const(m_albumes)) {
            if (claves.contains(a.toMap().value(QStringLiteral("clave")).toString()))
                m_albumesArtista << a;
        }
        std::sort(m_albumesArtista.begin(), m_albumesArtista.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap().value(QStringLiteral("anio")).toInt() > b.toMap().value(QStringLiteral("anio")).toInt();
        });
        natural = QStringLiteral("discografia");
        QString portada;
        for (const QVariant &a : std::as_const(m_artistas)) {
            if (a.toMap().value(QStringLiteral("nombre")).toString() == arg)
                portada = a.toMap().value(QStringLiteral("portada")).toString();
        }
        info = {{QStringLiteral("tipo"), QStringLiteral("artista")}, {QStringLiteral("titulo"), arg},
                {QStringLiteral("portada"), portada},
                {QStringLiteral("detalle"), QStringLiteral("%1 · %2")
                     .arg(m_albumesArtista.size() == 1 ? QStringLiteral("1 álbum") : QStringLiteral("%1 álbumes").arg(m_albumesArtista.size()),
                          textoCanciones(sel.size()))}};
    } else if (tipo == QLatin1String("genero")) {
        for (int i = 0; i < m_pistas.size(); ++i)
            if (m_pistas.at(i).genero == arg)
                sel << i;
        natural = QStringLiteral("artista");
        info = {{QStringLiteral("tipo"), QStringLiteral("genero")}, {QStringLiteral("titulo"), arg}};
    } else if (tipo == QLatin1String("lista")) {
        for (const Lista &l : std::as_const(m_listas)) {
            if (l.id != arg)
                continue;
            for (const QString &r : l.rutas) {
                const auto it = m_porRuta.constFind(r);
                if (it != m_porRuta.constEnd())
                    sel << *it;
            }
            info = {{QStringLiteral("tipo"), QStringLiteral("lista")}, {QStringLiteral("titulo"), l.nombre},
                    {QStringLiteral("id"), l.id}};
            for (const QVariant &x : listas()) {
                if (x.toMap().value(QStringLiteral("id")).toString() == l.id)
                    info[QStringLiteral("portadas")] = x.toMap().value(QStringLiteral("portadas"));
            }
        }
        natural = QString(); // orden de la lista
    } else if (v == QLatin1String("recientes")) {
        for (int i = 0; i < m_pistas.size(); ++i)
            sel << i;
        std::sort(sel.begin(), sel.end(), [this](int a, int b) { return m_pistas.at(a).mtime > m_pistas.at(b).mtime; });
        sel.resize(qMin<qsizetype>(sel.size(), 150));
        info = {{QStringLiteral("tipo"), v}, {QStringLiteral("titulo"), QStringLiteral("Añadidas recientemente")}};
    } else if (v == QLatin1String("favoritas")) {
        for (int i = 0; i < m_pistas.size(); ++i)
            if (m_favoritas.contains(m_pistas.at(i).ruta))
                sel << i;
        natural = QStringLiteral("titulo");
        info = {{QStringLiteral("tipo"), v}, {QStringLiteral("titulo"), QStringLiteral("Me gusta")}};
    } else if (v == QLatin1String("masEscuchadas")) {
        for (int i = 0; i < m_pistas.size(); ++i)
            if (m_reproducciones.value(m_pistas.at(i).ruta) > 0)
                sel << i;
        std::sort(sel.begin(), sel.end(), [this](int a, int b) {
            return m_reproducciones.value(m_pistas.at(a).ruta) > m_reproducciones.value(m_pistas.at(b).ruta);
        });
        sel.resize(qMin<qsizetype>(sel.size(), 100));
        info = {{QStringLiteral("tipo"), v}, {QStringLiteral("titulo"), QStringLiteral("Más escuchadas")}};
    } else if (v == QLatin1String("albumes") || v == QLatin1String("artistas") || v == QLatin1String("generos")) {
        const int n = v == QLatin1String("albumes") ? m_albumes.size() : v == QLatin1String("artistas") ? m_artistas.size() : m_generos.size();
        const QString nombre = v == QLatin1String("albumes") ? QStringLiteral("Álbumes") : v == QLatin1String("artistas") ? QStringLiteral("Artistas") : QStringLiteral("Géneros");
        info = {{QStringLiteral("tipo"), v}, {QStringLiteral("titulo"), nombre},
                {QStringLiteral("detalle"), QString::number(n)}};
    } else {
        for (int i = 0; i < m_pistas.size(); ++i)
            sel << i;
        natural = QStringLiteral("titulo");
        info = {{QStringLiteral("tipo"), QStringLiteral("canciones")}, {QStringLiteral("titulo"), QStringLiteral("Canciones")}};
    }

    // Orden
    const QString campo = m_orden.isEmpty() ? natural : m_orden;
    const bool asc = m_orden.isEmpty() ? true : m_ordenAsc;
    auto porPista = [this](int a, int b) {
        const Pista &x = m_pistas.at(a), &y = m_pistas.at(b);
        if (x.disco != y.disco)
            return x.disco < y.disco;
        if (x.numero != y.numero)
            return x.numero < y.numero;
        return cmp(x.titulo, y.titulo) < 0;
    };
    if (!campo.isEmpty()) {
        std::stable_sort(sel.begin(), sel.end(), [&](int a, int b) {
            const Pista &x = m_pistas.at(a), &y = m_pistas.at(b);
            int r = 0;
            if (campo == QLatin1String("titulo"))
                r = cmp(x.titulo, y.titulo);
            else if (campo == QLatin1String("artista")) {
                r = cmp(x.artista, y.artista);
                if (r == 0) r = cmp(x.album, y.album);
                if (r == 0) return porPista(a, b);
            } else if (campo == QLatin1String("album")) {
                r = cmp(x.album, y.album);
                if (r == 0) return porPista(a, b);
            } else if (campo == QLatin1String("duracion"))
                r = x.duracion < y.duracion ? -1 : x.duracion > y.duracion ? 1 : 0;
            else if (campo == QLatin1String("anadida"))
                r = x.mtime < y.mtime ? -1 : x.mtime > y.mtime ? 1 : 0;
            else if (campo == QLatin1String("reproducciones")) {
                const int px = m_reproducciones.value(x.ruta), py = m_reproducciones.value(y.ruta);
                r = px < py ? -1 : px > py ? 1 : 0;
            } else if (campo == QLatin1String("pista"))
                return porPista(a, b);
            else if (campo == QLatin1String("discografia")) {
                if (x.anio != y.anio)
                    return x.anio > y.anio;
                r = cmp(x.album, y.album);
                if (r == 0) return porPista(a, b);
            }
            return asc ? r < 0 : r > 0;
        });
    }

    m_canciones.clear();
    qint64 total = 0;
    for (int i : std::as_const(sel)) {
        m_canciones << mapa(m_pistas.at(i));
        total += m_pistas.at(i).duracion;
    }
    if (!info.contains(QStringLiteral("detalle"))) {
        QString d = textoCanciones(sel.size());
        if (total > 0)
            d += QStringLiteral(" · ") + Biblioteca::duracionLarga(total);
        if (tipo == QLatin1String("album") && info.value(QStringLiteral("anio")).toInt() > 0)
            d = info.value(QStringLiteral("anio")).toString() + QStringLiteral(" · ") + d;
        info[QStringLiteral("detalle")] = d;
    }
    m_infoVista = info;
    emit cancionesChanged();
}

QStringList MusicaBackend::rutasVista() const
{
    QStringList r;
    for (const QVariant &v : m_canciones)
        r << v.toMap().value(QStringLiteral("ruta")).toString();
    return r;
}

// ---------------------------------------------------------------- reproducción

QString MusicaBackend::rutaActual() const
{
    return (m_indice >= 0 && m_indice < m_cola.size()) ? m_cola.at(m_indice) : QString();
}

QVariantMap MusicaBackend::actual() const
{
    return m_mapaActual;
}

bool MusicaBackend::reproduciendo() const
{
    return m_player->playbackState() == QMediaPlayer::PlayingState;
}

qreal MusicaBackend::volumen() const
{
    return m_volumen;
}

bool MusicaBackend::silencio() const
{
    return m_salida->isMuted();
}

bool MusicaBackend::haySiguiente() const
{
    return m_indice + 1 < m_cola.size() || (m_repetir == 1 && !m_cola.isEmpty());
}

QVariantList MusicaBackend::cola() const
{
    QVariantList r;
    for (int i = m_indice + 1; i < m_cola.size() && r.size() < 300; ++i)
        r << mapaDeRuta(m_cola.at(i));
    return r;
}

void MusicaBackend::cargar(int indice, bool sonar)
{
    if (indice < 0 || indice >= m_cola.size())
        return;
    m_indice = indice;
    const QString ruta = m_cola.at(indice);
    m_mapaActual = mapaDeRuta(ruta);
    m_contada = false;
    m_posicion = 0;
    m_duracion = m_mapaActual.value(QStringLiteral("duracion")).toLongLong();
    m_player->setSource(QUrl::fromLocalFile(ruta));
    if (sonar)
        m_player->play();
    m_letra = Biblioteca::letra(ruta);
    m_letraSinc = !m_letra.isEmpty() && m_letra.first().toMap().value(QStringLiteral("ms")).toLongLong() >= 0;
    m_ultimaVez.insert(ruta, QDateTime::currentSecsSinceEpoch());
    emit actualChanged();
    emit posicionChanged();
    emit duracionChanged();
    emit colaChanged();
    emit letraChanged();
    emit estadoChanged();
    guardarDatosLuego();
}

void MusicaBackend::playTrack(int indice)
{
    reproducirRutas(rutasVista(), indice, false);
}

void MusicaBackend::reproducirVista(bool aleatorio)
{
    const QStringList r = rutasVista();
    if (r.isEmpty())
        return;
    reproducirRutas(r, aleatorio ? QRandomGenerator::global()->bounded(r.size()) : 0, aleatorio);
}

void MusicaBackend::reproducirAlbum(const QString &clave, bool aleatorio)
{
    QVector<int> sel;
    for (int i = 0; i < m_pistas.size(); ++i)
        if (m_pistas.at(i).claveAlbum() == clave)
            sel << i;
    std::sort(sel.begin(), sel.end(), [this](int a, int b) {
        const Pista &x = m_pistas.at(a), &y = m_pistas.at(b);
        if (x.disco != y.disco) return x.disco < y.disco;
        if (x.numero != y.numero) return x.numero < y.numero;
        return cmp(x.titulo, y.titulo) < 0;
    });
    QStringList r;
    for (int i : sel)
        r << m_pistas.at(i).ruta;
    if (!r.isEmpty())
        reproducirRutas(r, aleatorio ? QRandomGenerator::global()->bounded(r.size()) : 0, aleatorio);
}

void MusicaBackend::reproducirRutas(const QStringList &rutas, int desde, bool aleatorio)
{
    if (rutas.isEmpty())
        return;
    desde = qBound(0, desde, int(rutas.size()) - 1);
    if (aleatorio && !m_aleatorio) {
        m_aleatorio = true;
        emit modoChanged();
    }
    m_base = rutas;
    if (m_aleatorio) {
        QStringList resto = rutas;
        const QString primera = resto.takeAt(desde);
        mezclar(resto);
        m_cola = QStringList{primera} + resto;
        cargar(0, true);
    } else {
        m_cola = rutas;
        cargar(desde, true);
    }
    guardarDatosLuego();
}

void MusicaBackend::play()
{
    if (m_indice < 0) {
        if (m_canciones.isEmpty())
            return;
        reproducirVista(m_aleatorio);
        return;
    }
    if (m_player->source().isEmpty())
        cargar(m_indice, true);
    else
        m_player->play();
}

void MusicaBackend::pause()
{
    m_player->pause();
    guardarDatosLuego();
}

void MusicaBackend::togglePlay()
{
    reproduciendo() ? pause() : play();
}

void MusicaBackend::stop()
{
    m_player->stop();
    m_posicion = 0;
    emit posicionChanged();
}

void MusicaBackend::siguiente()
{
    if (m_cola.isEmpty())
        return;
    if (m_indice + 1 < m_cola.size()) {
        cargar(m_indice + 1, true);
    } else if (m_repetir == 1) {
        if (m_aleatorio)
            mezclar(m_cola);
        cargar(0, true);
    } else {
        // Fin de la cola: se queda en la última, parada al principio.
        m_player->stop();
        m_posicion = 0;
        emit posicionChanged();
    }
}

void MusicaBackend::anterior()
{
    if (m_cola.isEmpty())
        return;
    if (m_posicion > 3000 || (m_indice <= 0 && m_repetir != 1)) {
        seek(0);
        return;
    }
    cargar(m_indice > 0 ? m_indice - 1 : m_cola.size() - 1, true);
}

void MusicaBackend::alTerminarPista()
{
    if (!m_contada)
        contarReproduccion();
    if (m_finDeCancion) {
        setTemporizador(0);
        m_player->stop();
        ponerAviso(QStringLiteral("Temporizador: la música se ha detenido"));
        return;
    }
    if (m_repetir == 2) {
        m_player->setPosition(0);
        m_player->play();
        m_contada = false;
        return;
    }
    siguiente();
}

void MusicaBackend::seek(qint64 ms)
{
    ms = qMax<qint64>(0, ms);
    m_player->setPosition(ms);
    emit saltoDePosicion(ms);
}

void MusicaBackend::setVolumen(qreal v)
{
    v = qBound(0.0, v, 1.0);
    m_volumen = v;
    // El oído es logarítmico: la barra se mueve "igual" en todo el recorrido.
    m_salida->setVolume(QAudio::convertVolume(v, QAudio::LogarithmicVolumeScale, QAudio::LinearVolumeScale));
    if (m_salida->isMuted() && v > 0)
        m_salida->setMuted(false);
    emit volumenChanged();
    guardarDatosLuego();
}

void MusicaBackend::toggleSilencio()
{
    m_salida->setMuted(!m_salida->isMuted());
    emit volumenChanged();
}

void MusicaBackend::toggleAleatorio()
{
    setAleatorio(!m_aleatorio);
}

void MusicaBackend::setAleatorio(bool a)
{
    if (a == m_aleatorio)
        return;
    m_aleatorio = a;
    if (m_indice >= 0) {
        if (a) {
            QStringList resto = m_cola.mid(m_indice + 1);
            mezclar(resto);
            m_cola = m_cola.mid(0, m_indice + 1) + resto;
        } else {
            const QString cur = rutaActual();
            const int pos = m_base.indexOf(cur);
            if (pos >= 0) {
                m_cola = m_base;
                m_indice = pos;
            }
        }
        emit colaChanged();
    }
    emit modoChanged();
    guardarDatosLuego();
}

void MusicaBackend::cicloRepetir()
{
    setRepetir((m_repetir + 1) % 3);
}

void MusicaBackend::setRepetir(int modo)
{
    modo = qBound(0, modo, 2);
    if (modo == m_repetir)
        return;
    m_repetir = modo;
    emit modoChanged();
    guardarDatosLuego();
}

// ---------------------------------------------------------------- cola

void MusicaBackend::aContinuacion(const QStringList &rutas0)
{
    QStringList rutas;
    for (const QString &r : rutas0)
        rutas << aLocal(r);
    if (rutas.isEmpty())
        return;
    if (m_indice < 0) {
        reproducirRutas(rutas, 0, false);
        return;
    }
    for (int i = rutas.size() - 1; i >= 0; --i) {
        m_cola.insert(m_indice + 1, rutas.at(i));
        const int b = m_base.indexOf(rutaActual());
        m_base.insert(b >= 0 ? b + 1 : m_base.size(), rutas.at(i));
    }
    ponerAviso(rutas.size() == 1 ? QStringLiteral("Sonará a continuación")
                                 : QStringLiteral("%1 canciones sonarán a continuación").arg(rutas.size()));
    emit colaChanged();
    guardarDatosLuego();
}

void MusicaBackend::aLaCola(const QStringList &rutas0)
{
    QStringList rutas;
    for (const QString &r : rutas0)
        rutas << aLocal(r);
    if (rutas.isEmpty())
        return;
    if (m_indice < 0) {
        reproducirRutas(rutas, 0, false);
        return;
    }
    m_cola << rutas;
    m_base << rutas;
    ponerAviso(rutas.size() == 1 ? QStringLiteral("Añadida a la cola")
                                 : QStringLiteral("%1 canciones añadidas a la cola").arg(rutas.size()));
    emit colaChanged();
    guardarDatosLuego();
}

void MusicaBackend::quitarDeCola(int i)
{
    const int k = m_indice + 1 + i;
    if (i < 0 || k >= m_cola.size())
        return;
    const QString r = m_cola.takeAt(k);
    const int b = m_base.lastIndexOf(r);
    if (b >= 0)
        m_base.removeAt(b);
    emit colaChanged();
    guardarDatosLuego();
}

void MusicaBackend::saltarACola(int i)
{
    const int k = m_indice + 1 + i;
    if (i >= 0 && k < m_cola.size())
        cargar(k, true);
}

void MusicaBackend::moverEnCola(int desde, int hasta)
{
    const int a = m_indice + 1 + desde, b = m_indice + 1 + hasta;
    if (desde < 0 || hasta < 0 || a >= m_cola.size() || b >= m_cola.size() || a == b)
        return;
    m_cola.move(a, b);
    emit colaChanged();
    guardarDatosLuego();
}

void MusicaBackend::vaciarCola()
{
    if (m_indice < 0)
        return;
    m_cola = m_cola.mid(0, m_indice + 1);
    const QString cur = rutaActual();
    m_base = {cur};
    emit colaChanged();
    guardarDatosLuego();
}

// ---------------------------------------------------------------- favoritas y listas

bool MusicaBackend::esFavorita(const QString &ruta) const
{
    return m_favoritas.contains(ruta);
}

void MusicaBackend::alternarFavorita(const QString &ruta)
{
    if (ruta.isEmpty())
        return;
    if (!m_favoritas.remove(ruta))
        m_favoritas.insert(ruta);
    ++m_datosVersion;
    emit datosChanged();
    if (m_vista == QLatin1String("favoritas") && m_busqueda.isEmpty())
        construirVista();
    guardarDatosLuego();
}

QString MusicaBackend::crearLista(const QString &nombre, const QStringList &rutas)
{
    Lista l;
    l.id = QStringLiteral("l%1").arg(QDateTime::currentMSecsSinceEpoch());
    l.nombre = nombre.trimmed().isEmpty() ? QStringLiteral("Lista nueva") : nombre.trimmed();
    for (const QString &r : rutas)
        l.rutas << aLocal(r);
    m_listas << l;
    emit listasChanged();
    guardarDatosLuego();
    if (!rutas.isEmpty())
        ponerAviso(QStringLiteral("Añadida a «%1»").arg(l.nombre));
    return l.id;
}

void MusicaBackend::renombrarLista(const QString &id, const QString &nombre)
{
    for (Lista &l : m_listas) {
        if (l.id == id && !nombre.trimmed().isEmpty()) {
            l.nombre = nombre.trimmed();
            emit listasChanged();
            if (m_vista == QStringLiteral("lista:") + id)
                construirVista();
            guardarDatosLuego();
        }
    }
}

void MusicaBackend::borrarLista(const QString &id)
{
    for (int i = 0; i < m_listas.size(); ++i) {
        if (m_listas.at(i).id == id) {
            m_listas.removeAt(i);
            emit listasChanged();
            if (m_vista == QStringLiteral("lista:") + id)
                abrir(QStringLiteral("canciones"));
            guardarDatosLuego();
            return;
        }
    }
}

void MusicaBackend::anadirALista(const QString &id, const QStringList &rutas)
{
    for (Lista &l : m_listas) {
        if (l.id != id)
            continue;
        for (const QString &r : rutas)
            l.rutas << aLocal(r);
        emit listasChanged();
        if (m_vista == QStringLiteral("lista:") + id)
            construirVista();
        ponerAviso(QStringLiteral("Añadida a «%1»").arg(l.nombre));
        guardarDatosLuego();
    }
}

void MusicaBackend::quitarDeLista(const QString &id, int indice)
{
    for (Lista &l : m_listas) {
        if (l.id != id)
            continue;
        // El índice es el de la vista (solo pistas que existen): buscar la ruta.
        const QString ruta = m_canciones.value(indice).toMap().value(QStringLiteral("ruta")).toString();
        int vistos = -1;
        for (int i = 0; i < l.rutas.size(); ++i) {
            if (m_porRuta.contains(l.rutas.at(i)))
                ++vistos;
            if (vistos == indice && l.rutas.at(i) == ruta) {
                l.rutas.removeAt(i);
                break;
            }
        }
        emit listasChanged();
        construirVista();
        guardarDatosLuego();
    }
}

// ---------------------------------------------------------------- archivos

QVariantMap MusicaBackend::detalles(const QString &ruta) const
{
    QVariantMap m = mapaDeRuta(ruta);
    const QFileInfo fi(ruta);
    const double mb = fi.size() / (1024.0 * 1024.0);
    m[QStringLiteral("tamTexto")] = QStringLiteral("%1 MB").arg(QLocale().toString(mb, 'f', 1));
    m[QStringLiteral("carpeta")] = fi.absolutePath();
    m[QStringLiteral("editable")] = fi.isWritable();
    const qint64 ult = m_ultimaVez.value(ruta);
    m[QStringLiteral("ultimaVez")] = ult > 0 ? QLocale().toString(QDateTime::fromSecsSinceEpoch(ult), QStringLiteral("d MMM yyyy, HH:mm")) : QString();
    m[QStringLiteral("anadidaTexto")] = QLocale().toString(fi.lastModified(), QStringLiteral("d MMM yyyy"));
    return m;
}

QString MusicaBackend::guardarEtiquetas(const QString &ruta, const QVariantMap &campos)
{
    QString error;
    if (!Biblioteca::guardarEtiquetas(ruta, campos, &error))
        return error;
    const Pista p = Biblioteca::leer(ruta);
    const auto it = m_porRuta.constFind(ruta);
    if (it != m_porRuta.constEnd())
        m_pistas[*it] = p;
    reconstruirIndices();
    if (ruta == rutaActual()) {
        m_mapaActual = mapa(p);
        emit actualChanged();
    }
    construirVista();
    emit bibliotecaChanged();
    emit colaChanged();
    return {};
}

void MusicaBackend::moverAPapelera(const QStringList &rutas)
{
    int n = 0;
    for (const QString &r0 : rutas) {
        const QString r = aLocal(r0);
        if (r == rutaActual())
            m_player->stop();
        if (QFile::moveToTrash(r)) {
            ++n;
            const auto it = m_porRuta.constFind(r);
            if (it != m_porRuta.constEnd())
                m_pistas.removeAt(*it);
            reconstruirIndices();
            const int c = m_cola.indexOf(r);
            if (c > m_indice)
                m_cola.removeAt(c);
            m_base.removeAll(r);
            m_favoritas.remove(r);
        }
    }
    if (n == 0) {
        ponerAviso(QStringLiteral("No se pudo mover a la papelera"));
        return;
    }
    construirVista();
    emit bibliotecaChanged();
    emit colaChanged();
    emit listasChanged();
    ponerAviso(n == 1 ? QStringLiteral("Movida a la papelera") : QStringLiteral("%1 canciones movidas a la papelera").arg(n));
    guardarDatosLuego();
}

void MusicaBackend::mostrarEnFinder(const QString &ruta)
{
    const QString r = ruta.isEmpty() ? rutaActual() : aLocal(ruta);
    if (r.isEmpty())
        return;
    QProcess::startDetached(QStringLiteral("titan-finder"), {QFileInfo(r).absolutePath()});
}

void MusicaBackend::anadirCarpeta(const QString &urlOruta)
{
    const QString c = QFileInfo(aLocal(urlOruta)).canonicalFilePath();
    if (c.isEmpty() || !QFileInfo(c).isDir() || m_carpetas.contains(c))
        return;
    m_carpetas << c;
    QSettings conf(rutaConf(), QSettings::IniFormat);
    conf.setValue(QStringLiteral("Biblioteca/carpetas"), m_carpetas);
    emit carpetasChanged();
    ponerAviso(QStringLiteral("Buscando música en %1…").arg(QFileInfo(c).fileName()));
    escanear();
}

void MusicaBackend::quitarCarpeta(const QString &ruta)
{
    if (!m_carpetas.removeOne(ruta))
        return;
    QSettings conf(rutaConf(), QSettings::IniFormat);
    conf.setValue(QStringLiteral("Biblioteca/carpetas"), m_carpetas);
    emit carpetasChanged();
    escanear();
}

void MusicaBackend::refrescar()
{
    escanear();
}

void MusicaBackend::openFile(const QString &ruta)
{
    abrirArchivos({ruta});
}

void MusicaBackend::abrirArchivos(const QStringList &urls)
{
    QStringList rutas;
    for (const QString &u : urls) {
        const QFileInfo fi(aLocal(u));
        if (fi.isDir()) {
            QDirIterator it(fi.absoluteFilePath(), Biblioteca::filtros(), QDir::Files | QDir::Readable, QDirIterator::Subdirectories);
            QStringList dentro;
            while (it.hasNext())
                dentro << QFileInfo(it.next()).canonicalFilePath();
            std::sort(dentro.begin(), dentro.end(), [](const QString &a, const QString &b) { return cmp(a, b) < 0; });
            rutas << dentro;
        } else if (fi.isFile() && Biblioteca::esAudio(fi.fileName())) {
            rutas << fi.canonicalFilePath();
        }
    }
    if (rutas.isEmpty()) {
        if (!urls.isEmpty())
            ponerAviso(QStringLiteral("No es un archivo de música"));
        return;
    }
    bool nuevas = false;
    for (const QString &r : std::as_const(rutas)) {
        if (!m_porRuta.contains(r)) {
            if (!m_sueltos.contains(r))
                m_sueltos << r;
            m_pistas << Biblioteca::leer(r);
            nuevas = true;
        }
    }
    if (nuevas) {
        reconstruirIndices();
        construirVista();
        emit bibliotecaChanged();
    }
    reproducirRutas(rutas, 0, false);
}

// ---------------------------------------------------------------- temporizador y avisos

int MusicaBackend::temporizador() const
{
    if (m_finDeCancion)
        return -1;
    if (m_finTemporizador <= 0)
        return 0;
    const qint64 resto = m_finTemporizador - QDateTime::currentMSecsSinceEpoch();
    return int(qMax<qint64>(1, (resto + 59999) / 60000));
}

void MusicaBackend::setTemporizador(int minutos)
{
    m_finDeCancion = minutos < 0;
    m_finTemporizador = minutos > 0 ? QDateTime::currentMSecsSinceEpoch() + qint64(minutos) * 60000 : 0;
    if (minutos > 0)
        m_temporizador.start();
    else
        m_temporizador.stop();
    emit temporizadorChanged();
}

void MusicaBackend::ponerAviso(const QString &t)
{
    m_aviso = t;
    emit avisoChanged();
}

void MusicaBackend::cerrarAviso()
{
    if (m_aviso.isEmpty())
        return;
    m_aviso.clear();
    emit avisoChanged();
}

void MusicaBackend::contarReproduccion()
{
    const QString r = rutaActual();
    if (r.isEmpty())
        return;
    m_contada = true;
    m_reproducciones[r] = m_reproducciones.value(r) + 1;
    guardarDatosLuego();
}

// ---------------------------------------------------------------- guardar

void MusicaBackend::cargarDatos()
{
    QFile f(rutaDatos());
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
    for (const QJsonValue &v : o.value(QStringLiteral("favoritas")).toArray())
        m_favoritas.insert(v.toString());
    const QJsonObject rep = o.value(QStringLiteral("reproducciones")).toObject();
    for (auto it = rep.begin(); it != rep.end(); ++it)
        m_reproducciones.insert(it.key(), it.value().toInt());
    const QJsonObject ult = o.value(QStringLiteral("ultimaVez")).toObject();
    for (auto it = ult.begin(); it != ult.end(); ++it)
        m_ultimaVez.insert(it.key(), it.value().toInteger());
    for (const QJsonValue &v : o.value(QStringLiteral("listas")).toArray()) {
        const QJsonObject lo = v.toObject();
        Lista l;
        l.id = lo.value(QStringLiteral("id")).toString();
        l.nombre = lo.value(QStringLiteral("nombre")).toString();
        for (const QJsonValue &r : lo.value(QStringLiteral("rutas")).toArray())
            l.rutas << r.toString();
        if (!l.id.isEmpty())
            m_listas << l;
    }
}

void MusicaBackend::guardarDatosLuego()
{
    m_guardar.start();
}

void MusicaBackend::guardarDatos()
{
    QJsonObject o;
    QJsonArray fav;
    for (const QString &r : std::as_const(m_favoritas))
        fav.append(r);
    o.insert(QStringLiteral("favoritas"), fav);
    QJsonObject rep;
    for (auto it = m_reproducciones.constBegin(); it != m_reproducciones.constEnd(); ++it)
        rep.insert(it.key(), it.value());
    o.insert(QStringLiteral("reproducciones"), rep);
    QJsonObject ult;
    for (auto it = m_ultimaVez.constBegin(); it != m_ultimaVez.constEnd(); ++it)
        ult.insert(it.key(), it.value());
    o.insert(QStringLiteral("ultimaVez"), ult);
    QJsonArray ls;
    for (const Lista &l : std::as_const(m_listas)) {
        ls.append(QJsonObject{{QStringLiteral("id"), l.id}, {QStringLiteral("nombre"), l.nombre},
                              {QStringLiteral("rutas"), QJsonArray::fromStringList(l.rutas)}});
    }
    o.insert(QStringLiteral("listas"), ls);
    QDir().mkpath(QFileInfo(rutaDatos()).absolutePath());
    QSaveFile f(rutaDatos());
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(o).toJson(QJsonDocument::Indented));
        f.commit();
    }
}

void MusicaBackend::guardarSesion()
{
    QSettings conf(rutaConf(), QSettings::IniFormat);
    conf.beginGroup(QStringLiteral("Sesion"));
    conf.setValue(QStringLiteral("cola"), m_cola.mid(0, 2000));
    conf.setValue(QStringLiteral("base"), m_base.mid(0, 2000));
    conf.setValue(QStringLiteral("indice"), m_indice);
    conf.setValue(QStringLiteral("posicion"), m_posicion);
    conf.setValue(QStringLiteral("volumen"), m_volumen);
    conf.setValue(QStringLiteral("aleatorio"), m_aleatorio);
    conf.setValue(QStringLiteral("repetir"), m_repetir);
    conf.endGroup();
}

void MusicaBackend::restaurarSesion()
{
    QSettings conf(rutaConf(), QSettings::IniFormat);
    conf.beginGroup(QStringLiteral("Sesion"));
    setVolumen(conf.value(QStringLiteral("volumen"), 0.8).toReal());
    m_aleatorio = conf.value(QStringLiteral("aleatorio"), false).toBool();
    m_repetir = qBound(0, conf.value(QStringLiteral("repetir"), 0).toInt(), 2);
    QStringList cola;
    for (const QString &r : conf.value(QStringLiteral("cola")).toStringList())
        if (QFile::exists(r))
            cola << r;
    const int indice = conf.value(QStringLiteral("indice"), -1).toInt();
    const QString actual = conf.value(QStringLiteral("cola")).toStringList().value(indice);
    m_base = conf.value(QStringLiteral("base")).toStringList();
    if (!cola.isEmpty() && cola.contains(actual)) {
        m_cola = cola;
        m_posicionPendiente = conf.value(QStringLiteral("posicion"), 0).toLongLong();
        cargar(m_cola.indexOf(actual), false);
        m_posicion = m_posicionPendiente;
        emit posicionChanged();
    }
    conf.endGroup();
}
