// Inti OS - Fotos: biblioteca (con índice en caché), vistas, álbumes,
// favoritas, acciones sobre archivos y editor.
#include "FotosBackend.h"
#include "Edicion.h"
#include "Exif.h"
#include "Proveedores.h"
#include "ThemeManager.h"

#include <QBuffer>
#include <QClipboard>
#include <QCollator>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImageReader>
#include <QImageWriter>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QMimeData>
#include <QMutexLocker>
#include <QProcess>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>
#include <QtConcurrent/QtConcurrentRun>
#include <algorithm>

namespace {

const QStringList &extensiones()
{
    static const QStringList e = {QStringLiteral("png"), QStringLiteral("jpg"), QStringLiteral("jpeg"), QStringLiteral("webp"),
                                  QStringLiteral("bmp"), QStringLiteral("gif"), QStringLiteral("svg"), QStringLiteral("tif"),
                                  QStringLiteral("tiff"), QStringLiteral("avif"), QStringLiteral("heic"), QStringLiteral("heif"),
                                  QStringLiteral("jxl")};
    return e;
}

bool esImagen(const QFileInfo &fi)
{
    return extensiones().contains(fi.suffix().toLower());
}

QString rutaIndice()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/titan-fotos/indice.json");
}

QString rutaConf()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/titan-fotos/fotos.ini");
}

QString textoBytes(qint64 b)
{
    if (b < 1024) return QStringLiteral("%1 B").arg(b);
    if (b < 1024 * 1024) return QStringLiteral("%1 KB").arg(qRound(b / 1024.0));
    if (b < 1024LL * 1024 * 1024) return QStringLiteral("%1 MB").arg(b / (1024.0 * 1024.0), 0, 'f', 1);
    return QStringLiteral("%1 GB").arg(b / (1024.0 * 1024.0 * 1024.0), 0, 'f', 2);
}

// Lee una foto: si el índice ya la tiene con la misma fecha de modificación,
// no se vuelve a abrir el archivo.
Foto leerFoto(const QFileInfo &fi, const QHash<QString, Foto> &cache)
{
    Foto f;
    f.ruta = fi.absoluteFilePath();
    f.bytes = fi.size();
    f.mtime = fi.lastModified().toMSecsSinceEpoch();
    const auto it = cache.constFind(f.ruta);
    if (it != cache.constEnd() && it->mtime == f.mtime && it->bytes == f.bytes) {
        f = *it;
    } else {
        QImageReader r(f.ruta);
        r.setAutoTransform(true);
        QSize s = r.size();
        if (s.isValid() && (r.transformation() & QImageIOHandler::TransformationRotate90))
            s.transpose();
        f.ancho = s.width();
        f.alto = s.height();
        const QVariantMap ex = Exif::leer(f.ruta);
        f.fecha = ex.contains(QStringLiteral("fecha")) ? ex.value(QStringLiteral("fecha")).toDateTime().toMSecsSinceEpoch() : f.mtime;
        f.camara = ex.value(QStringLiteral("camara")).toString();
    }
    if (f.fecha <= 0)
        f.fecha = f.mtime;
    f.clave = ProveedorMiniaturas::clave(f.ruta);
    return f;
}

QHash<QString, Foto> leerIndice()
{
    QHash<QString, Foto> r;
    QFile f(rutaIndice());
    if (!f.open(QIODevice::ReadOnly))
        return r;
    const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
    for (auto it = o.begin(); it != o.end(); ++it) {
        const QJsonArray a = it.value().toArray();
        Foto x;
        x.ruta = it.key();
        x.mtime = qint64(a.at(0).toDouble());
        x.bytes = qint64(a.at(1).toDouble());
        x.fecha = qint64(a.at(2).toDouble());
        x.ancho = a.at(3).toInt();
        x.alto = a.at(4).toInt();
        x.camara = a.at(5).toString();
        r.insert(x.ruta, x);
    }
    return r;
}

void guardarIndice(const QList<Foto> &fotos)
{
    QJsonObject o;
    for (const Foto &f : fotos)
        o.insert(f.ruta, QJsonArray{double(f.mtime), double(f.bytes), double(f.fecha), f.ancho, f.alto, f.camara});
    QDir().mkpath(QFileInfo(rutaIndice()).absolutePath());
    QSaveFile s(rutaIndice());
    if (s.open(QIODevice::WriteOnly)) {
        s.write(QJsonDocument(o).toJson(QJsonDocument::Compact));
        s.commit();
    }
}

QList<Foto> escanearDirs(const QStringList &dirs, QHash<QString, Foto> cache)
{
    if (cache.isEmpty())
        cache = leerIndice();
    QList<Foto> r;
    QSet<QString> vistas;
    for (const QString &d : dirs) {
        QDirIterator it(d, QDir::Files | QDir::Readable, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QFileInfo fi(it.next());
            if (fi.fileName().startsWith(QLatin1Char('.')) || fi.absoluteFilePath().contains(QLatin1String("/."))
                || !esImagen(fi) || fi.size() == 0)
                continue;
            const QString canon = fi.canonicalFilePath();
            if (canon.isEmpty() || vistas.contains(canon))
                continue;
            vistas.insert(canon);
            r << leerFoto(QFileInfo(canon), cache);
        }
    }
    guardarIndice(r);
    return r;
}

QString textoFecha(qint64 ms, const QString &formato)
{
    static const QLocale es(QLocale::Spanish, QLocale::Spain);
    return es.toString(QDateTime::fromMSecsSinceEpoch(ms), formato);
}

} // namespace

// ---------------------------------------------------------------- arranque

FotosBackend::FotosBackend(QObject *parent)
    : QObject(parent)
    , m_watcher(new QFileSystemWatcher(this))
{
    cargarConf();
    m_reescaneo.setSingleShot(true);
    m_reescaneo.setInterval(1500);
    connect(&m_reescaneo, &QTimer::timeout, this, &FotosBackend::escanear);
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this]() { m_reescaneo.start(); });
    connect(&m_escaneo, &QFutureWatcher<QList<Foto>>::finished, this, &FotosBackend::alTerminarEscaneo);
    // Primero lo que ya se conoce (índice en caché): la ventana sale llena al momento
    const QHash<QString, Foto> indice = leerIndice();
    for (const Foto &f : indice) {
        if (!QFileInfo::exists(f.ruta))
            continue;
        Foto x = f;
        x.clave = ProveedorMiniaturas::clave(x.ruta);
        m_fotos << x;
    }
    for (int i = 0; i < m_fotos.size(); ++i) {
        m_porRuta.insert(m_fotos.at(i).ruta, i);
        m_claves.insert(m_fotos.at(i).clave, m_fotos.at(i).ruta);
    }
    filtrar(false);
    escanear();
}

FotosBackend::~FotosBackend()
{
    m_escaneo.waitForFinished();
}

QStringList FotosBackend::directorios() const
{
    QStringList d;
    auto anadir = [&](const QString &r) {
        if (!r.isEmpty() && QDir(r).exists() && !d.contains(QDir(r).canonicalPath()))
            d << QDir(r).canonicalPath();
    };
    const QString home = QDir::homePath();
    anadir(QStandardPaths::writableLocation(QStandardPaths::PicturesLocation));
    anadir(home + QStringLiteral("/Imágenes"));
    anadir(QStandardPaths::writableLocation(QStandardPaths::DownloadLocation));
    anadir(home + QStringLiteral("/Descargas"));
    anadir(QStandardPaths::writableLocation(QStandardPaths::DesktopLocation));
    anadir(QStringLiteral("/usr/share/backgrounds"));
    anadir(QStringLiteral("/usr/share/titan/wallpapers"));
    for (const QString &c : m_carpetasExtra)
        anadir(c);
    return d;
}

void FotosBackend::escanear()
{
    if (m_escaneo.isRunning()) {
        m_pendiente = true;
        return;
    }
    QHash<QString, Foto> cache;
    for (const Foto &f : std::as_const(m_fotos))
        cache.insert(f.ruta, f);
    const QStringList dirs = directorios();
    // Vigilar las carpetas (y sus subcarpetas directas) para ver fotos nuevas
    for (const QString &d : dirs) {
        QStringList vigilar{d};
        const QFileInfoList subs = QDir(d).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (int i = 0; i < subs.size() && i < 64; ++i)
            vigilar << subs.at(i).absoluteFilePath();
        for (const QString &v : vigilar)
            if (!m_watcher->directories().contains(v))
                m_watcher->addPath(v);
    }
    if (!m_cargando) {
        m_cargando = true;
        emit cargandoChanged();
    }
    m_escaneo.setFuture(QtConcurrent::run(escanearDirs, dirs, cache));
}

void FotosBackend::alTerminarEscaneo()
{
    QList<Foto> nuevas = m_escaneo.result();
    {
        QMutexLocker l(&m_mutexClaves);
        m_fotos = nuevas;
        m_porRuta.clear();
        for (int i = 0; i < m_fotos.size(); ++i) {
            m_porRuta.insert(m_fotos.at(i).ruta, i);
            m_claves.insert(m_fotos.at(i).clave, m_fotos.at(i).ruta);
        }
    }
    m_cargando = false;
    filtrar(true);
    emit cargandoChanged();
    if (m_pendiente) {
        m_pendiente = false;
        escanear();
    }
}

void FotosBackend::refresh()
{
    escanear();
}

// ---------------------------------------------------------------- configuración

void FotosBackend::cargarConf()
{
    QSettings c(rutaConf(), QSettings::IniFormat);
    const QStringList fav = c.value(QStringLiteral("favoritas")).toStringList();
    m_favoritas = QSet<QString>(fav.begin(), fav.end());
    m_carpetasExtra = c.value(QStringLiteral("carpetas")).toStringList();
    const QJsonArray al = QJsonDocument::fromJson(c.value(QStringLiteral("albumes")).toByteArray()).array();
    for (const QJsonValue &v : al) {
        const QJsonObject o = v.toObject();
        Album a;
        a.id = o.value(QStringLiteral("id")).toString();
        a.nombre = o.value(QStringLiteral("nombre")).toString();
        for (const QJsonValue &r : o.value(QStringLiteral("rutas")).toArray())
            a.rutas << r.toString();
        if (!a.id.isEmpty())
            m_albumes << a;
    }
}

void FotosBackend::guardarConf()
{
    QDir().mkpath(QFileInfo(rutaConf()).absolutePath());
    QSettings c(rutaConf(), QSettings::IniFormat);
    QStringList fav(m_favoritas.begin(), m_favoritas.end());
    fav.sort();
    c.setValue(QStringLiteral("favoritas"), fav);
    c.setValue(QStringLiteral("carpetas"), m_carpetasExtra);
    QJsonArray al;
    for (const Album &a : std::as_const(m_albumes))
        al.append(QJsonObject{{QStringLiteral("id"), a.id}, {QStringLiteral("nombre"), a.nombre}, {QStringLiteral("rutas"), QJsonArray::fromStringList(a.rutas)}});
    c.setValue(QStringLiteral("albumes"), QJsonDocument(al).toJson(QJsonDocument::Compact));
}

void FotosBackend::avisar(const QString &texto)
{
    m_aviso = texto;
    emit avisoChanged();
}

// ---------------------------------------------------------------- vistas

QString FotosBackend::origen(const QString &ruta) const
{
    if (ruta.startsWith(QLatin1String("/usr/share/")))
        return QStringLiteral("fondos");
    const QString l = ruta.toLower();
    const QString nombre = QFileInfo(ruta).fileName().toLower();
    if (l.contains(QLatin1String("/capturas")) || l.contains(QLatin1String("/screenshots")) || nombre.startsWith(QLatin1String("captura"))
        || nombre.startsWith(QLatin1String("screenshot")))
        return QStringLiteral("capturas");
    if (l.contains(QLatin1String("/fondos/")) || l.contains(QLatin1String("/wallpapers/")))
        return QStringLiteral("fondos");
    const QString desc = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if ((!desc.isEmpty() && ruta.startsWith(desc + QLatin1Char('/'))) || ruta.startsWith(QDir::homePath() + QStringLiteral("/Descargas/")))
        return QStringLiteral("descargas");
    return QStringLiteral("fotos");
}

const Foto *FotosBackend::buscar(const QString &ruta) const
{
    const auto it = m_porRuta.constFind(ruta);
    if (it != m_porRuta.constEnd())
        return &m_fotos.at(*it);
    for (const Foto &f : m_sueltas)
        if (f.ruta == ruta)
            return &f;
    return nullptr;
}

QVariantMap FotosBackend::mapa(const Foto &f) const
{
    QVariantMap m;
    const QFileInfo fi(f.ruta);
    m[QStringLiteral("path")] = f.ruta;
    m[QStringLiteral("url")] = QUrl::fromLocalFile(f.ruta).toString();
    m[QStringLiteral("name")] = fi.fileName();
    m[QStringLiteral("carpeta")] = fi.absolutePath();
    m[QStringLiteral("miniatura")] = QStringLiteral("image://miniatura/%1?%2").arg(f.clave).arg(f.mtime);
    m[QStringLiteral("bytes")] = f.bytes;
    m[QStringLiteral("size")] = textoBytes(f.bytes);
    m[QStringLiteral("ancho")] = f.ancho;
    m[QStringLiteral("alto")] = f.alto;
    m[QStringLiteral("dimensions")] = f.ancho > 0 ? QStringLiteral("%1 × %2").arg(f.ancho).arg(f.alto) : QString();
    m[QStringLiteral("fecha")] = f.fecha;
    m[QStringLiteral("date")] = textoFecha(f.fecha, QStringLiteral("d MMM yyyy, HH:mm"));
    m[QStringLiteral("mes")] = m_orden == QLatin1String("fecha") ? textoFecha(f.fecha, QStringLiteral("MMMM 'de' yyyy")) : QString();
    m[QStringLiteral("dia")] = textoFecha(f.fecha, QStringLiteral("d MMM"));
    m[QStringLiteral("favorita")] = m_favoritas.contains(f.ruta);
    m[QStringLiteral("camara")] = f.camara;
    m[QStringLiteral("editable")] = fi.isWritable() && !f.ruta.endsWith(QLatin1String(".svg"), Qt::CaseInsensitive)
                                    && !f.ruta.endsWith(QLatin1String(".gif"), Qt::CaseInsensitive);
    m[QStringLiteral("borrable")] = QFileInfo(fi.absolutePath()).isWritable();
    return m;
}

void FotosBackend::filtrar(bool conservarFoto)
{
    const QString rutaActual = conservarFoto && m_indice >= 0 && m_indice < m_rutasVisibles.size() ? m_rutasVisibles.at(m_indice) : QString();
    const qint64 hace30 = QDateTime::currentDateTime().addDays(-30).toMSecsSinceEpoch();

    // Cuentas para la barra lateral
    QVariantMap cuentas;
    int nFototeca = 0, nFav = 0, nRec = 0, nCap = 0, nFon = 0, nDes = 0;
    for (const Foto &f : std::as_const(m_fotos)) {
        const QString o = origen(f.ruta);
        if (!f.ruta.startsWith(QLatin1String("/usr/share/"))) ++nFototeca;
        if (m_favoritas.contains(f.ruta)) ++nFav;
        if (f.mtime >= hace30 && o != QLatin1String("fondos")) ++nRec;
        if (o == QLatin1String("capturas")) ++nCap;
        if (o == QLatin1String("fondos")) ++nFon;
        if (o == QLatin1String("descargas")) ++nDes;
    }
    cuentas[QStringLiteral("fototeca")] = nFototeca;
    cuentas[QStringLiteral("favoritas")] = nFav;
    cuentas[QStringLiteral("recientes")] = nRec;
    cuentas[QStringLiteral("capturas")] = nCap;
    cuentas[QStringLiteral("fondos")] = nFon;
    cuentas[QStringLiteral("descargas")] = nDes;
    for (const Album &a : std::as_const(m_albumes)) {
        int n = 0;
        for (const QString &r : a.rutas)
            if (buscar(r)) ++n;
        cuentas[QStringLiteral("album:") + a.id] = n;
    }
    m_cuentas = cuentas;

    // Fotos de la vista
    QList<const Foto *> sel;
    const QString v = m_vista;
    if (v == QLatin1String("suelta")) {
        for (const Foto &f : std::as_const(m_sueltas)) sel << &f;
    } else if (v.startsWith(QLatin1String("album:"))) {
        const QString id = v.mid(6);
        for (const Album &a : std::as_const(m_albumes))
            if (a.id == id)
                for (const QString &r : a.rutas)
                    if (const Foto *f = buscar(r)) sel << f;
    } else {
        const QString carpeta = v.startsWith(QLatin1String("carpeta:")) ? v.mid(8) + QLatin1Char('/') : QString();
        for (const Foto &f : std::as_const(m_fotos)) {
            const QString o = origen(f.ruta);
            bool entra;
            if (!carpeta.isEmpty()) entra = f.ruta.startsWith(carpeta);
            else if (v == QLatin1String("favoritas")) entra = m_favoritas.contains(f.ruta);
            else if (v == QLatin1String("recientes")) entra = f.mtime >= hace30 && o != QLatin1String("fondos");
            else if (v == QLatin1String("capturas") || v == QLatin1String("fondos") || v == QLatin1String("descargas")) entra = o == v;
            else entra = !f.ruta.startsWith(QLatin1String("/usr/share/"));
            if (entra) sel << &f;
        }
    }

    // Búsqueda: nombre, carpeta, mes y cámara
    if (!m_busqueda.trimmed().isEmpty()) {
        const QStringList palabras = m_busqueda.trimmed().split(QLatin1Char(' '), Qt::SkipEmptyParts);
        QList<const Foto *> r;
        for (const Foto *f : std::as_const(sel)) {
            const QString heno = f->ruta.mid(f->ruta.lastIndexOf(QLatin1Char('/'), f->ruta.lastIndexOf(QLatin1Char('/')) - 1)) + QLatin1Char(' ')
                                 + textoFecha(f->fecha, QStringLiteral("MMMM yyyy")) + QLatin1Char(' ') + f->camara;
            bool todas = true;
            for (const QString &p : palabras)
                if (!heno.contains(p, Qt::CaseInsensitive)) { todas = false; break; }
            if (todas) r << f;
        }
        sel = r;
    }

    // Orden
    QCollator col(QLocale(QLocale::Spanish));
    col.setNumericMode(true);
    col.setCaseSensitivity(Qt::CaseInsensitive);
    const bool asc = m_ordenAsc;
    std::stable_sort(sel.begin(), sel.end(), [&](const Foto *a, const Foto *b) {
        int c;
        if (m_orden == QLatin1String("nombre")) c = col.compare(QFileInfo(a->ruta).fileName(), QFileInfo(b->ruta).fileName());
        else if (m_orden == QLatin1String("tamano")) c = a->bytes < b->bytes ? -1 : (a->bytes > b->bytes ? 1 : 0);
        else c = a->fecha < b->fecha ? -1 : (a->fecha > b->fecha ? 1 : 0);
        return asc ? c < 0 : c > 0;
    });

    m_visibles.clear();
    m_rutasVisibles.clear();
    for (const Foto *f : std::as_const(sel)) {
        m_visibles << mapa(*f);
        m_rutasVisibles << f->ruta;
    }
    const int antes = m_indice;
    if (!rutaActual.isEmpty()) {
        m_indice = m_rutasVisibles.indexOf(rutaActual);
        if (m_indice < 0 && !m_rutasVisibles.isEmpty())
            m_indice = qMin(antes, int(m_rutasVisibles.size()) - 1); // se borró: la siguiente
    } else if (!conservarFoto || m_indice >= m_rutasVisibles.size()) {
        m_indice = -1;
    }
    emit photosChanged();
    emit currentPhotoChanged();
}

QString FotosBackend::statusText() const
{
    const int n = m_visibles.size();
    QString t = n == 0 ? QStringLiteral("Sin fotos") : n == 1 ? QStringLiteral("1 foto") : QStringLiteral("%1 fotos").arg(n);
    qint64 total = 0;
    for (const QString &r : m_rutasVisibles)
        if (const Foto *f = buscar(r)) total += f->bytes;
    if (total > 0)
        t += QStringLiteral(" · ") + textoBytes(total);
    if (m_cargando)
        t += QStringLiteral(" · buscando fotos…");
    return t;
}

QString FotosBackend::tituloVista() const
{
    const QString &v = m_vista;
    if (v == QLatin1String("favoritas")) return QStringLiteral("Favoritas");
    if (v == QLatin1String("recientes")) return QStringLiteral("Recientes");
    if (v == QLatin1String("capturas")) return QStringLiteral("Capturas de pantalla");
    if (v == QLatin1String("fondos")) return QStringLiteral("Fondos de pantalla");
    if (v == QLatin1String("descargas")) return QStringLiteral("Descargas");
    if (v == QLatin1String("suelta")) return QFileInfo(m_carpetaSuelta).fileName();
    if (v.startsWith(QLatin1String("carpeta:"))) return QFileInfo(v.mid(8)).fileName();
    if (v.startsWith(QLatin1String("album:")))
        for (const Album &a : m_albumes)
            if (a.id == v.mid(6)) return a.nombre;
    return QStringLiteral("Fototeca");
}

QVariantMap FotosBackend::cuentas() const
{
    return m_cuentas;
}

QVariantList FotosBackend::albumes() const
{
    QVariantList l;
    for (const Album &a : m_albumes) {
        QVariantMap m;
        m[QStringLiteral("id")] = a.id;
        m[QStringLiteral("nombre")] = a.nombre;
        // Portada: la primera foto que siga existiendo
        for (const QString &r : a.rutas)
            if (const Foto *f = buscar(r)) {
                m[QStringLiteral("portada")] = QStringLiteral("image://miniatura/%1?%2").arg(f->clave).arg(f->mtime);
                break;
            }
        l << m;
    }
    return l;
}

void FotosBackend::abrir(const QString &vista)
{
    if (m_vista != vista) {
        m_vista = vista;
        emit vistaChanged();
    }
    m_indice = -1;
    filtrar(false);
}

void FotosBackend::setSearchQuery(const QString &q)
{
    if (m_busqueda == q)
        return;
    m_busqueda = q;
    emit searchQueryChanged();
    filtrar(m_indice >= 0);
}

void FotosBackend::ordenarPor(const QString &campo)
{
    if (m_orden == campo)
        m_ordenAsc = !m_ordenAsc;
    else {
        m_orden = campo;
        m_ordenAsc = campo == QLatin1String("nombre");
    }
    filtrar(true);
}

void FotosBackend::anadirCarpeta(const QString &url)
{
    const QString r = QUrl(url).isLocalFile() ? QUrl(url).toLocalFile() : url;
    const QString c = QDir(r).canonicalPath();
    if (c.isEmpty() || m_carpetasExtra.contains(c))
        return;
    m_carpetasExtra << c;
    guardarConf();
    emit carpetasChanged();
    escanear();
    abrir(QStringLiteral("carpeta:") + c);
}

void FotosBackend::quitarCarpeta(const QString &ruta)
{
    if (!m_carpetasExtra.removeAll(ruta))
        return;
    m_watcher->removePaths(m_watcher->directories().filter(ruta));
    guardarConf();
    emit carpetasChanged();
    if (m_vista == QStringLiteral("carpeta:") + ruta)
        abrir(QStringLiteral("fototeca"));
    escanear();
}

// ---------------------------------------------------------------- visor

QVariantMap FotosBackend::currentPhoto() const
{
    if (m_indice >= 0 && m_indice < m_visibles.size())
        return m_visibles.at(m_indice).toMap();
    return {};
}

void FotosBackend::selectPhoto(int index)
{
    const int nuevo = index >= 0 && index < m_visibles.size() ? index : -1;
    if (nuevo == m_indice)
        return;
    m_indice = nuevo;
    emit currentPhotoChanged();
}

void FotosBackend::nextPhoto()
{
    if (!m_visibles.isEmpty() && m_indice >= 0)
        selectPhoto((m_indice + 1) % m_visibles.size());
}

void FotosBackend::previousPhoto()
{
    if (!m_visibles.isEmpty() && m_indice >= 0)
        selectPhoto((m_indice - 1 + m_visibles.size()) % m_visibles.size());
}

int FotosBackend::indiceDe(const QString &ruta) const
{
    return m_rutasVisibles.indexOf(ruta);
}

// Abrir un archivo desde fuera (Finder, «Abrir con»): se ve esa foto y con las
// flechas se recorre su carpeta.
void FotosBackend::openFile(const QString &filePath)
{
    QString local = filePath;
    if (local.startsWith(QLatin1String("file:")))
        local = QUrl(filePath).toLocalFile();
    const QFileInfo fi(local);
    if (!fi.exists() || !fi.isFile())
        return;
    const QString ruta = fi.canonicalFilePath();
    m_carpetaSuelta = fi.absolutePath();
    QHash<QString, Foto> cache;
    for (const Foto &f : std::as_const(m_fotos))
        cache.insert(f.ruta, f);
    m_sueltas.clear();
    const QFileInfoList hermanas = QDir(m_carpetaSuelta).entryInfoList(QDir::Files | QDir::Readable);
    for (const QFileInfo &h : hermanas)
        if (esImagen(h) || h.canonicalFilePath() == ruta)
            m_sueltas << leerFoto(QFileInfo(h.canonicalFilePath()), cache);
    {
        QMutexLocker l(&m_mutexClaves);
        for (const Foto &f : std::as_const(m_sueltas))
            m_claves.insert(f.clave, f.ruta);
    }
    m_vista = QStringLiteral("suelta");
    m_busqueda.clear();
    emit searchQueryChanged();
    emit vistaChanged();
    filtrar(false);
    selectPhoto(m_rutasVisibles.indexOf(ruta));
    emit levantarVentana();
}

QVariantMap FotosBackend::detalles(const QString &ruta) const
{
    QVariantMap d = Exif::leer(ruta);
    const QFileInfo fi(ruta);
    const Foto *f = buscar(ruta);
    d[QStringLiteral("nombre")] = fi.fileName();
    d[QStringLiteral("carpeta")] = fi.absolutePath();
    d[QStringLiteral("formato")] = fi.suffix().toUpper();
    d[QStringLiteral("tamano")] = textoBytes(fi.size());
    if (f && f->ancho > 0) {
        d[QStringLiteral("dimensiones")] = QStringLiteral("%1 × %2").arg(f->ancho).arg(f->alto);
        d[QStringLiteral("megapixeles")] = QStringLiteral("%1 MP").arg(f->ancho * double(f->alto) / 1e6, 0, 'f', 1);
    }
    const bool hayCaptura = d.contains(QStringLiteral("fecha"));
    const qint64 ms = hayCaptura ? d.value(QStringLiteral("fecha")).toDateTime().toMSecsSinceEpoch() : fi.lastModified().toMSecsSinceEpoch();
    d[QStringLiteral("fechaTexto")] = textoFecha(ms, QStringLiteral("dddd, d 'de' MMMM 'de' yyyy · HH:mm"));
    d[QStringLiteral("fechaEtiqueta")] = hayCaptura ? QStringLiteral("Tomada") : QStringLiteral("Modificada");
    d.remove(QStringLiteral("fecha"));
    d[QStringLiteral("favorita")] = m_favoritas.contains(ruta);
    QStringList enAlbumes;
    for (const Album &a : m_albumes)
        if (a.rutas.contains(ruta))
            enAlbumes << a.nombre;
    d[QStringLiteral("albumes")] = enAlbumes.join(QStringLiteral(", "));
    return d;
}

QString FotosBackend::rutaDeClave(const QString &clave) const
{
    QMutexLocker l(&m_mutexClaves);
    return m_claves.value(clave);
}

// ---------------------------------------------------------------- acciones

void FotosBackend::alternarFavorita(const QStringList &rutas)
{
    if (rutas.isEmpty())
        return;
    // Con varias: si alguna no lo es, todas pasan a favoritas
    bool todas = true;
    for (const QString &r : rutas)
        if (!m_favoritas.contains(r)) todas = false;
    for (const QString &r : rutas) {
        if (todas) m_favoritas.remove(r);
        else m_favoritas.insert(r);
    }
    guardarConf();
    filtrar(true);
}

int FotosBackend::moverAPapelera(const QStringList &rutas)
{
    int hechas = 0;
    QStringList fallos;
    for (const QString &r : rutas) {
        if (QFile::moveToTrash(r)) {
            ++hechas;
            m_favoritas.remove(r);
            const auto it = m_porRuta.find(r);
            if (it != m_porRuta.end()) {
                m_fotos.removeAt(*it);
                m_porRuta.clear();
                for (int i = 0; i < m_fotos.size(); ++i)
                    m_porRuta.insert(m_fotos.at(i).ruta, i);
            }
            for (int i = 0; i < m_sueltas.size(); ++i)
                if (m_sueltas.at(i).ruta == r) { m_sueltas.removeAt(i); break; }
        } else {
            fallos << QFileInfo(r).fileName();
        }
    }
    if (!fallos.isEmpty())
        avisar(fallos.size() == 1 ? QStringLiteral("No se pudo mover «%1» a la papelera (¿es del sistema?).").arg(fallos.first())
                                  : QStringLiteral("%1 fotos no se pudieron mover a la papelera.").arg(fallos.size()));
    else if (hechas > 0)
        avisar(hechas == 1 ? QStringLiteral("Foto movida a la papelera") : QStringLiteral("%1 fotos movidas a la papelera").arg(hechas));
    guardarConf();
    filtrar(true);
    return hechas;
}

QString FotosBackend::renombrar(const QString &ruta, const QString &nombre0)
{
    const QString nombre = nombre0.trimmed();
    const QFileInfo fi(ruta);
    if (nombre.isEmpty() || nombre.contains(QLatin1Char('/')))
        return QStringLiteral("El nombre no es válido.");
    QString nuevoNombre = nombre;
    if (QFileInfo(nombre).suffix().isEmpty() && !fi.suffix().isEmpty())
        nuevoNombre += QLatin1Char('.') + fi.suffix();
    const QString nueva = fi.absolutePath() + QLatin1Char('/') + nuevoNombre;
    if (nueva == ruta)
        return QString();
    if (QFileInfo::exists(nueva))
        return QStringLiteral("Ya hay un archivo con ese nombre.");
    if (!QFile::rename(ruta, nueva))
        return QStringLiteral("No se pudo cambiar el nombre (¿permisos?).");
    if (m_favoritas.remove(ruta))
        m_favoritas.insert(nueva);
    for (Album &a : m_albumes)
        for (QString &r : a.rutas)
            if (r == ruta) r = nueva;
    guardarConf();
    auto mover = [&](Foto &f) {
        f.ruta = nueva;
        f.clave = ProveedorMiniaturas::clave(nueva);
        QMutexLocker l(&m_mutexClaves);
        m_claves.insert(f.clave, nueva);
    };
    const auto it = m_porRuta.find(ruta);
    if (it != m_porRuta.end()) {
        const int i = *it;
        mover(m_fotos[i]);
        m_porRuta.erase(it);
        m_porRuta.insert(nueva, i);
    }
    for (Foto &f : m_sueltas)
        if (f.ruta == ruta) mover(f);
    const bool estaba = m_indice >= 0 && m_rutasVisibles.value(m_indice) == ruta;
    filtrar(true);
    if (estaba)
        selectPhoto(m_rutasVisibles.indexOf(nueva));
    return QString();
}

void FotosBackend::copiarAlPortapapeles(const QStringList &rutas)
{
    if (rutas.isEmpty())
        return;
    auto *datos = new QMimeData;
    QList<QUrl> urls;
    QByteArray gnome("copy");
    for (const QString &r : rutas) {
        urls << QUrl::fromLocalFile(r);
        gnome += '\n' + QUrl::fromLocalFile(r).toEncoded();
    }
    datos->setUrls(urls);
    datos->setData(QStringLiteral("x-special/gnome-copied-files"), gnome);
    if (rutas.size() == 1) {
        QImageReader rd(rutas.first());
        rd.setAutoTransform(true);
        const QImage img = rd.read();
        if (!img.isNull())
            datos->setImageData(img);
    }
    QGuiApplication::clipboard()->setMimeData(datos);
    avisar(rutas.size() == 1 ? QStringLiteral("Foto copiada") : QStringLiteral("%1 fotos copiadas").arg(rutas.size()));
}

bool FotosBackend::setAsWallpaper(const QString &filePath)
{
    const QString target = filePath.isEmpty() ? currentPhoto().value(QStringLiteral("path")).toString() : filePath;
    if (target.isEmpty() || !QFile::exists(target)) {
        QProcess::startDetached(QStringLiteral("titan-shell"), {QStringLiteral("--toggle-wallpaper")});
        return true;
    }
    ThemeManager::instance()->setWallpaper(target);
    QProcess::startDetached(QStringLiteral("titan-desktop"), {QStringLiteral("--wallpaper"), target});
    avisar(QStringLiteral("Fondo de pantalla cambiado"));
    return true;
}

void FotosBackend::openInFinder(const QString &filePath)
{
    const QString target = filePath.isEmpty() ? currentPhoto().value(QStringLiteral("path")).toString() : filePath;
    if (target.isEmpty())
        return;
    const QFileInfo fi(target);
    QProcess::startDetached(QStringLiteral("titan-finder"), {fi.isDir() ? fi.absoluteFilePath() : fi.absolutePath()});
}

// ---------------------------------------------------------------- álbumes

QString FotosBackend::crearAlbum(const QString &nombre0, const QStringList &rutas)
{
    Album a;
    a.id = QUuid::createUuid().toString(QUuid::Id128).left(10);
    a.nombre = nombre0.trimmed().isEmpty() ? QStringLiteral("Álbum sin título") : nombre0.trimmed();
    for (const QString &r : rutas)
        if (!a.rutas.contains(r)) a.rutas << r;
    m_albumes << a;
    guardarConf();
    emit albumesChanged();
    filtrar(true);
    if (!rutas.isEmpty())
        avisar(QStringLiteral("Álbum «%1» creado con %2 %3").arg(a.nombre).arg(rutas.size()).arg(rutas.size() == 1 ? QStringLiteral("foto") : QStringLiteral("fotos")));
    return a.id;
}

void FotosBackend::renombrarAlbum(const QString &id, const QString &nombre)
{
    for (Album &a : m_albumes)
        if (a.id == id && !nombre.trimmed().isEmpty()) {
            a.nombre = nombre.trimmed();
            guardarConf();
            emit albumesChanged();
            emit vistaChanged();
        }
}

void FotosBackend::borrarAlbum(const QString &id)
{
    for (int i = 0; i < m_albumes.size(); ++i)
        if (m_albumes.at(i).id == id) {
            m_albumes.removeAt(i);
            guardarConf();
            emit albumesChanged();
            if (m_vista == QStringLiteral("album:") + id)
                abrir(QStringLiteral("fototeca"));
            else
                filtrar(true);
            return;
        }
}

void FotosBackend::anadirAAlbum(const QString &id, const QStringList &rutas)
{
    for (Album &a : m_albumes)
        if (a.id == id) {
            int n = 0;
            for (const QString &r : rutas)
                if (!a.rutas.contains(r)) { a.rutas << r; ++n; }
            guardarConf();
            emit albumesChanged();
            filtrar(true);
            avisar(n == 0 ? QStringLiteral("Ya estaban en «%1»").arg(a.nombre)
                          : QStringLiteral("%1 %2 a «%3»").arg(n).arg(n == 1 ? QStringLiteral("foto añadida") : QStringLiteral("fotos añadidas"), a.nombre));
        }
}

void FotosBackend::quitarDeAlbum(const QString &id, const QStringList &rutas)
{
    for (Album &a : m_albumes)
        if (a.id == id) {
            for (const QString &r : rutas)
                a.rutas.removeAll(r);
            guardarConf();
            emit albumesChanged();
            filtrar(true);
        }
}

// ---------------------------------------------------------------- editor

void FotosBackend::empezarEdicion(const QString &ruta)
{
    QImageReader r(ruta);
    r.setAutoTransform(true);
    QSize s = r.size();
    if (s.isValid() && (r.transformation() & QImageIOHandler::TransformationRotate90))
        s.transpose();
    // Vista previa reducida: ajustar es inmediato también con fotos de 24 MP
    if (s.isValid() && (s.width() > 1800 || s.height() > 1800)) {
        QSize red = s;
        red.scale(1800, 1800, Qt::KeepAspectRatio);
        if (r.transformation() & QImageIOHandler::TransformationRotate90)
            red.transpose();
        r.setScaledSize(red);
    }
    QImage img = r.read();
    QMutexLocker l(&m_mutexEdicion);
    m_rutaEdicion = ruta;
    m_baseEdicion = img.convertToFormat(img.hasAlphaChannel() ? QImage::Format_ARGB32 : QImage::Format_RGB32);
}

QImage FotosBackend::vistaPrevia(const QString &params, const QSize &pedido)
{
    QImage base;
    {
        QMutexLocker l(&m_mutexEdicion);
        base = m_baseEdicion;
    }
    if (base.isNull())
        return base;
    if (pedido.isValid() && pedido.width() > 0 && pedido.height() > 0 && (base.width() > pedido.width() || base.height() > pedido.height()))
        base = base.scaled(pedido, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    // Sin recorte: el recuadro se dibuja encima en la interfaz
    return Edicion::aplicar(base, Ajustes::leer(params), false);
}

QString FotosBackend::guardarEdicion(const QString &ruta, const QString &params, bool comoCopia)
{
    const Ajustes a = Ajustes::leer(params);
    QImageReader r(ruta);
    r.setAutoTransform(true);
    const QByteArray formato = r.format();
    QImage img = r.read();
    if (img.isNull()) {
        avisar(QStringLiteral("No se pudo abrir la foto para guardarla."));
        return QString();
    }
    img = Edicion::aplicar(img, a, true);

    const QFileInfo fi(ruta);
    QString destino = ruta;
    QByteArray fmt = formato.isEmpty() ? fi.suffix().toLower().toLatin1() : formato;
    if (!QImageWriter::supportedImageFormats().contains(fmt))
        fmt = "png";
    // Si no se puede escribir ahí (fondos del sistema), la copia va a Imágenes
    QString dir = fi.absolutePath();
    if (!QFileInfo(dir).isWritable() || !fi.isWritable()) {
        comoCopia = true;
        dir = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
        QDir().mkpath(dir);
    }
    if (comoCopia) {
        const QString ext = fmt == "jpeg" ? QStringLiteral("jpg") : QString::fromLatin1(fmt);
        const QString base = fi.completeBaseName();
        destino = dir + QStringLiteral("/%1 (editada).%2").arg(base, ext);
        for (int n = 2; QFileInfo::exists(destino); ++n)
            destino = dir + QStringLiteral("/%1 (editada %2).%3").arg(base).arg(n).arg(ext);
    }
    QBuffer buf;
    buf.open(QIODevice::WriteOnly);
    QImageWriter w(&buf, fmt);
    if (fmt == "jpeg" || fmt == "jpg" || fmt == "webp")
        w.setQuality(93);
    if (!w.write(img)) {
        avisar(QStringLiteral("No se pudo guardar: %1").arg(w.errorString()));
        return QString();
    }
    QByteArray bytes = buf.data();
    // JPEG: conservar el EXIF del original (fecha, cámara, GPS)
    if ((fmt == "jpeg" || fmt == "jpg") && bytes.startsWith("\xFF\xD8")) {
        const QByteArray exif = Exif::segmentoParaCopia(ruta);
        if (!exif.isEmpty())
            bytes.insert(2, exif);
    }
    QSaveFile f(destino);
    if (!f.open(QIODevice::WriteOnly) || f.write(bytes) != bytes.size() || !f.commit()) {
        avisar(QStringLiteral("No se pudo guardar: %1").arg(f.errorString()));
        return QString();
    }
    releer(destino);
    if (comoCopia) {
        // La copia hereda favorita y álbumes del original
        if (m_favoritas.contains(ruta))
            m_favoritas.insert(destino);
        for (Album &al : m_albumes)
            if (al.rutas.contains(ruta))
                al.rutas << destino;
        guardarConf();
        emit albumesChanged();
    }
    filtrar(true);
    if (comoCopia)
        selectPhoto(m_rutasVisibles.indexOf(destino));
    avisar(comoCopia ? QStringLiteral("Guardada como «%1»").arg(QFileInfo(destino).fileName()) : QStringLiteral("Cambios guardados"));
    return destino;
}

// Vuelve a leer un archivo (tras editarlo) sin esperar al escaneo.
void FotosBackend::releer(const QString &ruta)
{
    const Foto f = leerFoto(QFileInfo(ruta), {});
    {
        QMutexLocker l(&m_mutexClaves);
        m_claves.insert(f.clave, f.ruta);
    }
    const auto it = m_porRuta.constFind(ruta);
    if (it != m_porRuta.constEnd())
        m_fotos[*it] = f;
    else if (m_vista != QLatin1String("suelta") || QFileInfo(ruta).absolutePath() != m_carpetaSuelta) {
        m_fotos << f;
        m_porRuta.insert(ruta, m_fotos.size() - 1);
    }
    bool enSueltas = false;
    for (Foto &s : m_sueltas)
        if (s.ruta == ruta) { s = f; enSueltas = true; }
    if (!enSueltas && !m_carpetaSuelta.isEmpty() && QFileInfo(ruta).absolutePath() == m_carpetaSuelta)
        m_sueltas << f;
}
