#include "Biblioteca.h"

#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocale>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QTextStream>
#include <QUrl>

#include <taglib/fileref.h>
#include <taglib/tag.h>
#include <taglib/tpropertymap.h>
#include <taglib/tstring.h>
#include <taglib/tvariant.h>

namespace {

QString aQ(const TagLib::String &s)
{
    return QString::fromUtf8(s.toCString(true)).trimmed();
}

TagLib::String aT(const QString &s)
{
    return TagLib::String(s.toUtf8().constData(), TagLib::String::UTF8);
}

QString primero(const TagLib::PropertyMap &p, const char *clave)
{
    const auto it = p.find(clave);
    if (it == p.end() || it->second.isEmpty())
        return {};
    return aQ(it->second.front());
}

int numeroDe(const QString &s)
{
    // "3/12" -> 3
    return s.section(QLatin1Char('/'), 0, 0).trimmed().toInt();
}

QString portadaDeCarpeta(const QString &dir)
{
    static const QStringList nombres = {
        QStringLiteral("cover"), QStringLiteral("folder"), QStringLiteral("front"),
        QStringLiteral("album"), QStringLiteral("albumart"), QStringLiteral("portada"),
    };
    const QFileInfoList imgs = QDir(dir).entryInfoList(
        {QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"), QStringLiteral("*.png"), QStringLiteral("*.webp")},
        QDir::Files | QDir::Readable);
    for (const QString &n : nombres) {
        for (const QFileInfo &fi : imgs) {
            if (fi.completeBaseName().toLower() == n)
                return fi.absoluteFilePath();
        }
    }
    return {};
}

QString guardarPortada(const QByteArray &datos, const QString &mime)
{
    if (datos.size() < 64)
        return {};
    const QString dir = Biblioteca::carpetaCache() + QStringLiteral("/portadas");
    QDir().mkpath(dir);
    const QString ext = mime.contains(QLatin1String("png")) ? QStringLiteral("png") : QStringLiteral("jpg");
    const QString ruta = dir + QLatin1Char('/')
                         + QString::fromLatin1(QCryptographicHash::hash(datos, QCryptographicHash::Md5).toHex())
                         + QLatin1Char('.') + ext;
    if (!QFile::exists(ruta)) {
        QSaveFile f(ruta);
        if (!f.open(QIODevice::WriteOnly))
            return {};
        f.write(datos);
        if (!f.commit())
            return {};
    }
    return ruta;
}

} // namespace

QVariantMap Pista::aMapa() const
{
    QString calidad = formato;
    if (hz > 0 && (formato == QLatin1String("FLAC") || formato == QLatin1String("WAV")))
        calidad += QStringLiteral(" · %1 kHz").arg(QLocale().toString(hz / 1000.0, 'f', hz % 1000 ? 1 : 0));
    else if (kbps > 0)
        calidad += QStringLiteral(" · %1 kbps").arg(kbps);
    return {
        {QStringLiteral("ruta"), ruta},
        {QStringLiteral("url"), QUrl::fromLocalFile(ruta).toString()},
        {QStringLiteral("titulo"), titulo},
        {QStringLiteral("artista"), artista},
        {QStringLiteral("artistaAlbum"), artistaDeAlbum()},
        {QStringLiteral("album"), album},
        {QStringLiteral("claveAlbum"), claveAlbum()},
        {QStringLiteral("genero"), genero},
        {QStringLiteral("anio"), anio},
        {QStringLiteral("numero"), numero},
        {QStringLiteral("disco"), disco},
        {QStringLiteral("duracion"), duracion},
        {QStringLiteral("duracionTexto"), Biblioteca::tiempo(duracion)},
        {QStringLiteral("formato"), formato},
        {QStringLiteral("calidad"), calidad},
        {QStringLiteral("portada"), portada.isEmpty() ? QString() : QUrl::fromLocalFile(portada).toString()},
        {QStringLiteral("anadida"), mtime},
    };
}

QJsonObject Pista::aJson() const
{
    return {
        {QStringLiteral("r"), ruta}, {QStringLiteral("t"), titulo}, {QStringLiteral("a"), artista},
        {QStringLiteral("aa"), artistaAlbum}, {QStringLiteral("al"), album}, {QStringLiteral("g"), genero},
        {QStringLiteral("f"), formato}, {QStringLiteral("p"), portada}, {QStringLiteral("y"), anio},
        {QStringLiteral("n"), numero}, {QStringLiteral("d"), disco}, {QStringLiteral("k"), kbps},
        {QStringLiteral("h"), hz}, {QStringLiteral("du"), duracion}, {QStringLiteral("m"), mtime},
        {QStringLiteral("s"), tam},
    };
}

Pista Pista::deJson(const QJsonObject &o)
{
    Pista p;
    p.ruta = o.value(QStringLiteral("r")).toString();
    p.titulo = o.value(QStringLiteral("t")).toString();
    p.artista = o.value(QStringLiteral("a")).toString();
    p.artistaAlbum = o.value(QStringLiteral("aa")).toString();
    p.album = o.value(QStringLiteral("al")).toString();
    p.genero = o.value(QStringLiteral("g")).toString();
    p.formato = o.value(QStringLiteral("f")).toString();
    p.portada = o.value(QStringLiteral("p")).toString();
    p.anio = o.value(QStringLiteral("y")).toInt();
    p.numero = o.value(QStringLiteral("n")).toInt();
    p.disco = o.value(QStringLiteral("d")).toInt();
    p.kbps = o.value(QStringLiteral("k")).toInt();
    p.hz = o.value(QStringLiteral("h")).toInt();
    p.duracion = o.value(QStringLiteral("du")).toInteger();
    p.mtime = o.value(QStringLiteral("m")).toInteger();
    p.tam = o.value(QStringLiteral("s")).toInteger();
    return p;
}

namespace Biblioteca {

QStringList filtros()
{
    return {QStringLiteral("*.mp3"), QStringLiteral("*.flac"), QStringLiteral("*.ogg"), QStringLiteral("*.oga"),
            QStringLiteral("*.opus"), QStringLiteral("*.m4a"), QStringLiteral("*.aac"), QStringLiteral("*.wav"),
            QStringLiteral("*.wma"), QStringLiteral("*.aiff"), QStringLiteral("*.aif"), QStringLiteral("*.ape"),
            QStringLiteral("*.wv"), QStringLiteral("*.mka")};
}

bool esAudio(const QString &ruta)
{
    const QString ext = QStringLiteral("*.") + QFileInfo(ruta).suffix().toLower();
    return filtros().contains(ext);
}

QString carpetaCache()
{
    return QDir::homePath() + QStringLiteral("/.cache/titan-musica");
}

Pista leer(const QString &ruta)
{
    const QFileInfo fi(ruta);
    Pista p;
    p.ruta = fi.canonicalFilePath().isEmpty() ? fi.absoluteFilePath() : fi.canonicalFilePath();
    p.formato = fi.suffix().toUpper();
    p.mtime = fi.lastModified().toSecsSinceEpoch();
    p.tam = fi.size();

    TagLib::FileRef f(QFile::encodeName(p.ruta).constData(), true, TagLib::AudioProperties::Average);
    if (!f.isNull()) {
        if (TagLib::Tag *t = f.tag()) {
            p.titulo = aQ(t->title());
            p.artista = aQ(t->artist());
            p.album = aQ(t->album());
            p.genero = aQ(t->genre());
            p.anio = static_cast<int>(t->year());
            p.numero = static_cast<int>(t->track());
        }
        const TagLib::PropertyMap props = f.properties();
        p.artistaAlbum = primero(props, "ALBUMARTIST");
        p.disco = numeroDe(primero(props, "DISCNUMBER"));
        if (p.numero == 0)
            p.numero = numeroDe(primero(props, "TRACKNUMBER"));
        if (const TagLib::AudioProperties *a = f.audioProperties()) {
            p.duracion = a->lengthInMilliseconds();
            p.kbps = a->bitrate();
            p.hz = a->sampleRate();
        }
        const auto fotos = f.complexProperties("PICTURE");
        for (const auto &foto : fotos) {
            const TagLib::ByteVector datos = foto.value("data").toByteVector();
            const QString mime = aQ(foto.value("mimeType").toString());
            p.portada = guardarPortada(QByteArray(datos.data(), static_cast<int>(datos.size())), mime);
            if (!p.portada.isEmpty())
                break;
        }
    }

    // Sin etiquetas: "Artista - Título.mp3" y la carpeta como álbum.
    if (p.titulo.isEmpty()) {
        const QString base = fi.completeBaseName();
        const int guion = base.indexOf(QStringLiteral(" - "));
        if (guion > 0) {
            if (p.artista.isEmpty())
                p.artista = base.left(guion).trimmed();
            p.titulo = base.mid(guion + 3).trimmed();
        } else {
            p.titulo = base;
        }
        // "01 Título" / "01. Título"
        static const QRegularExpression num(QStringLiteral("^(\\d{1,3})[ ._-]+(.+)$"));
        const auto m = num.match(p.titulo);
        if (m.hasMatch()) {
            if (p.numero == 0)
                p.numero = m.captured(1).toInt();
            p.titulo = m.captured(2).trimmed();
        }
    }
    if (p.artista.isEmpty())
        p.artista = QStringLiteral("Artista desconocido");
    if (p.album.isEmpty())
        p.album = fi.dir().dirName();
    if (p.portada.isEmpty())
        p.portada = portadaDeCarpeta(fi.absolutePath());
    return p;
}

QVector<Pista> escanear(const QStringList &carpetas, const QStringList &sueltos, const std::atomic_bool *cancelar)
{
    // Caché: ruta -> pista, válida si no cambian fecha ni tamaño.
    const QString rutaCache = carpetaCache() + QStringLiteral("/biblioteca.json");
    QHash<QString, Pista> cache;
    {
        QFile f(rutaCache);
        if (f.open(QIODevice::ReadOnly)) {
            const QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
            for (const QJsonValue &v : arr) {
                Pista p = Pista::deJson(v.toObject());
                cache.insert(p.ruta, p);
            }
        }
    }

    QVector<Pista> lista;
    QSet<QString> vistas;
    auto anadir = [&](const QFileInfo &fi) {
        const QString canon = fi.canonicalFilePath();
        if (canon.isEmpty() || vistas.contains(canon))
            return;
        vistas.insert(canon);
        const auto it = cache.constFind(canon);
        if (it != cache.constEnd() && it->mtime == fi.lastModified().toSecsSinceEpoch() && it->tam == fi.size()
            && (it->portada.isEmpty() || QFile::exists(it->portada))) {
            lista.append(*it);
        } else {
            lista.append(leer(canon));
        }
    };

    for (const QString &dir : carpetas) {
        if (dir.isEmpty() || !QDir(dir).exists())
            continue;
        QDirIterator it(dir, filtros(), QDir::Files | QDir::Readable, QDirIterator::Subdirectories | QDirIterator::FollowSymlinks);
        while (it.hasNext()) {
            if (cancelar && cancelar->load())
                return lista;
            it.next();
            anadir(it.fileInfo());
        }
    }
    for (const QString &s : sueltos) {
        const QFileInfo fi(s);
        if (fi.isFile())
            anadir(fi);
    }

    QDir().mkpath(carpetaCache());
    QJsonArray arr;
    for (const Pista &p : std::as_const(lista))
        arr.append(p.aJson());
    QSaveFile f(rutaCache);
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(arr).toJson(QJsonDocument::Compact));
        f.commit();
    }
    return lista;
}

bool guardarEtiquetas(const QString &ruta, const QVariantMap &c, QString *error)
{
    TagLib::FileRef f(QFile::encodeName(ruta).constData(), false);
    if (f.isNull() || !f.tag()) {
        if (error)
            *error = QStringLiteral("Este formato no admite etiquetas");
        return false;
    }
    if (!QFileInfo(ruta).isWritable()) {
        if (error)
            *error = QStringLiteral("No tienes permiso para cambiar este archivo");
        return false;
    }
    TagLib::Tag *t = f.tag();
    t->setTitle(aT(c.value(QStringLiteral("titulo")).toString()));
    t->setArtist(aT(c.value(QStringLiteral("artista")).toString()));
    t->setAlbum(aT(c.value(QStringLiteral("album")).toString()));
    t->setGenre(aT(c.value(QStringLiteral("genero")).toString()));
    t->setYear(static_cast<unsigned>(qMax(0, c.value(QStringLiteral("anio")).toInt())));
    t->setTrack(static_cast<unsigned>(qMax(0, c.value(QStringLiteral("numero")).toInt())));
    TagLib::PropertyMap props = f.properties();
    const QString aa = c.value(QStringLiteral("artistaAlbum")).toString().trimmed();
    if (aa.isEmpty())
        props.erase("ALBUMARTIST");
    else
        props.replace("ALBUMARTIST", TagLib::StringList(aT(aa)));
    f.setProperties(props);
    if (!f.save()) {
        if (error)
            *error = QStringLiteral("No se pudieron guardar los cambios");
        return false;
    }
    return true;
}

QVariantList letra(const QString &ruta)
{
    QString texto;
    const QFileInfo fi(ruta);
    for (const QString &ext : {QStringLiteral(".lrc"), QStringLiteral(".LRC"), QStringLiteral(".txt")}) {
        QFile f(fi.absolutePath() + QLatin1Char('/') + fi.completeBaseName() + ext);
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            texto = QString::fromUtf8(f.readAll());
            break;
        }
    }
    if (texto.isEmpty()) {
        TagLib::FileRef f(QFile::encodeName(ruta).constData(), false);
        if (!f.isNull()) {
            const TagLib::PropertyMap props = f.properties();
            for (const char *k : {"LYRICS", "UNSYNCEDLYRICS"}) {
                const auto it = props.find(k);
                if (it != props.end() && !it->second.isEmpty()) {
                    texto = QString::fromUtf8(it->second.toString("\n").toCString(true));
                    break;
                }
            }
        }
    }
    QVariantList r;
    if (texto.trimmed().isEmpty())
        return r;

    // [mm:ss.xx] puede repetirse al principio de una línea.
    static const QRegularExpression marca(QStringLiteral("\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]"));
    static const QRegularExpression etiqueta(QStringLiteral("^\\[[a-zA-Z]+:.*\\]$"));
    QVector<QPair<qint64, QString>> sinc;
    QStringList plano;
    const QStringList lineas = texto.split(QRegularExpression(QStringLiteral("\\r?\\n")));
    for (const QString &linea0 : lineas) {
        QString linea = linea0.trimmed();
        if (etiqueta.match(linea).hasMatch())
            continue; // [ar:...], [ti:...]
        QList<qint64> tiempos;
        auto m = marca.match(linea);
        while (m.hasMatch() && m.capturedStart() == 0) {
            QString frac = m.captured(3);
            qint64 ms = (m.captured(1).toLongLong() * 60 + m.captured(2).toLongLong()) * 1000;
            if (!frac.isEmpty())
                ms += frac.leftJustified(3, QLatin1Char('0')).left(3).toLongLong();
            tiempos << ms;
            linea = linea.mid(m.capturedLength()).trimmed();
            m = marca.match(linea);
        }
        if (tiempos.isEmpty())
            plano << linea;
        for (qint64 t : tiempos)
            sinc.append({t, linea});
    }
    if (!sinc.isEmpty()) {
        std::sort(sinc.begin(), sinc.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
        for (const auto &l : std::as_const(sinc))
            r << QVariantMap{{QStringLiteral("ms"), l.first}, {QStringLiteral("texto"), l.second}};
    } else {
        for (const QString &l : std::as_const(plano))
            r << QVariantMap{{QStringLiteral("ms"), -1}, {QStringLiteral("texto"), l}};
    }
    return r;
}

QString tiempo(qint64 ms)
{
    if (ms <= 0)
        return QStringLiteral("0:00");
    const qint64 s = ms / 1000;
    if (s >= 3600)
        return QStringLiteral("%1:%2:%3").arg(s / 3600).arg((s / 60) % 60, 2, 10, QLatin1Char('0')).arg(s % 60, 2, 10, QLatin1Char('0'));
    return QStringLiteral("%1:%2").arg(s / 60).arg(s % 60, 2, 10, QLatin1Char('0'));
}

QString duracionLarga(qint64 ms)
{
    const qint64 min = (ms + 30000) / 60000;
    if (min < 60)
        return QStringLiteral("%1 min").arg(min);
    return QStringLiteral("%1 h %2 min").arg(min / 60).arg(min % 60);
}

} // namespace Biblioteca
