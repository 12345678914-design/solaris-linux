#include "Exif.h"

#include <QFile>
#include <QtEndian>

namespace {

// Bloque TIFF del EXIF ("II*\0" o "MM\0*")
class Tiff
{
public:
    explicit Tiff(const QByteArray &d)
        : m_d(d)
    {
        m_ok = d.size() >= 8 && (d.startsWith("II") || d.startsWith("MM"));
        m_le = d.startsWith("II");
    }
    bool ok() const { return m_ok; }
    quint16 u16(int o) const
    {
        if (o < 0 || o + 2 > m_d.size()) return 0;
        const auto *p = reinterpret_cast<const uchar *>(m_d.constData() + o);
        return m_le ? qFromLittleEndian<quint16>(p) : qFromBigEndian<quint16>(p);
    }
    quint32 u32(int o) const
    {
        if (o < 0 || o + 4 > m_d.size()) return 0;
        const auto *p = reinterpret_cast<const uchar *>(m_d.constData() + o);
        return m_le ? qFromLittleEndian<quint32>(p) : qFromBigEndian<quint32>(p);
    }
    // Recorre un IFD: tag -> (tipo, cantidad, desplazamiento del valor)
    struct Entrada { quint16 tipo = 0; quint32 n = 0; int valor = 0; };
    QHash<quint16, Entrada> ifd(int o) const
    {
        QHash<quint16, Entrada> r;
        const int cuantas = u16(o);
        if (cuantas <= 0 || cuantas > 500) return r;
        for (int i = 0; i < cuantas; ++i) {
            const int e = o + 2 + i * 12;
            if (e + 12 > m_d.size()) break;
            Entrada en;
            en.tipo = u16(e + 2);
            en.n = u32(e + 4);
            static const int tam[] = {0, 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8};
            const int bytes = (en.tipo < 13 ? tam[en.tipo] : 1) * int(en.n);
            en.valor = bytes <= 4 ? e + 8 : int(u32(e + 8));
            r.insert(u16(e), en);
        }
        return r;
    }
    QString texto(const Entrada &e) const
    {
        if (e.valor < 0 || e.valor + int(e.n) > m_d.size()) return {};
        return QString::fromLatin1(m_d.constData() + e.valor, int(e.n)).section(QLatin1Char('\0'), 0, 0).trimmed();
    }
    double racional(const Entrada &e, int i = 0) const
    {
        const int o = e.valor + i * 8;
        const quint32 a = u32(o), b = u32(o + 4);
        if (e.tipo == 10) return b ? double(qint32(a)) / double(qint32(b)) : 0;
        return b ? double(a) / double(b) : 0;
    }
    quint32 entero(const Entrada &e) const { return e.tipo == 3 ? u16(e.valor) : u32(e.valor); }

private:
    QByteArray m_d;
    bool m_ok = false;
    bool m_le = true;
};

QByteArray bloqueExif(const QString &ruta)
{
    QFile f(ruta);
    if (!f.open(QIODevice::ReadOnly)) return {};
    const QByteArray cab = f.read(12);
    // JPEG: segmentos hasta APP1 "Exif\0\0"
    if (cab.startsWith("\xFF\xD8")) {
        f.seek(2);
        for (int vueltas = 0; vueltas < 40; ++vueltas) {
            const QByteArray m = f.read(4);
            if (m.size() < 4 || uchar(m[0]) != 0xFF) return {};
            const uchar tipo = uchar(m[1]);
            const int largo = (uchar(m[2]) << 8) | uchar(m[3]);
            if (tipo == 0xDA || tipo == 0xD9) return {};
            if (tipo == 0xE1) {
                const QByteArray d = f.read(largo - 2);
                if (d.startsWith(QByteArrayLiteral("Exif\0\0")))
                    return d.mid(6);
            } else {
                f.seek(f.pos() + largo - 2);
            }
        }
        return {};
    }
    // PNG: chunk eXIf
    if (cab.startsWith("\x89PNG")) {
        f.seek(8);
        for (int vueltas = 0; vueltas < 200; ++vueltas) {
            const QByteArray c = f.read(8);
            if (c.size() < 8) return {};
            const quint32 largo = qFromBigEndian<quint32>(reinterpret_cast<const uchar *>(c.constData()));
            const QByteArray tipo = c.mid(4, 4);
            if (tipo == "eXIf") return f.read(largo);
            if (tipo == "IDAT" || tipo == "IEND") return {};
            f.seek(f.pos() + largo + 4);
        }
        return {};
    }
    // WebP: RIFF ... chunk "EXIF"
    if (cab.startsWith("RIFF") && cab.mid(8, 4) == "WEBP") {
        f.seek(12);
        for (int vueltas = 0; vueltas < 50; ++vueltas) {
            const QByteArray c = f.read(8);
            if (c.size() < 8) return {};
            const quint32 largo = qFromLittleEndian<quint32>(reinterpret_cast<const uchar *>(c.constData() + 4));
            if (c.startsWith("EXIF")) {
                QByteArray d = f.read(largo);
                return d.startsWith(QByteArrayLiteral("Exif\0\0")) ? d.mid(6) : d;
            }
            f.seek(f.pos() + largo + (largo & 1));
        }
    }
    return {};
}

} // namespace

QVariantMap Exif::leer(const QString &ruta)
{
    QVariantMap r;
    const Tiff t(bloqueExif(ruta));
    if (!t.ok()) return r;
    const auto ifd0 = t.ifd(int(t.u32(4)));
    QString marca = ifd0.contains(0x010F) ? t.texto(ifd0.value(0x010F)) : QString();
    QString modelo = ifd0.contains(0x0110) ? t.texto(ifd0.value(0x0110)) : QString();
    if (!marca.isEmpty() && modelo.startsWith(marca, Qt::CaseInsensitive))
        marca.clear();
    const QString camara = (marca + QLatin1Char(' ') + modelo).trimmed();
    if (!camara.isEmpty()) r.insert(QStringLiteral("camara"), camara);

    QString fecha;
    if (ifd0.contains(0x0132)) fecha = t.texto(ifd0.value(0x0132));
    if (ifd0.contains(0x8769)) {
        const auto ex = t.ifd(int(t.entero(ifd0.value(0x8769))));
        if (ex.contains(0x9003)) fecha = t.texto(ex.value(0x9003));
        if (ex.contains(0x829A)) {
            const double s = t.racional(ex.value(0x829A));
            if (s > 0) r.insert(QStringLiteral("exposicion"), s >= 1 ? QStringLiteral("%1 s").arg(s, 0, 'g', 3) : QStringLiteral("1/%1 s").arg(qRound(1.0 / s)));
        }
        if (ex.contains(0x829D)) {
            const double f = t.racional(ex.value(0x829D));
            if (f > 0) r.insert(QStringLiteral("apertura"), QStringLiteral("ƒ/%1").arg(f, 0, 'g', 2));
        }
        if (ex.contains(0x8827)) r.insert(QStringLiteral("iso"), QStringLiteral("ISO %1").arg(t.entero(ex.value(0x8827))));
        if (ex.contains(0x920A)) {
            const double mm = t.racional(ex.value(0x920A));
            if (mm > 0) r.insert(QStringLiteral("focal"), QStringLiteral("%1 mm").arg(mm, 0, 'g', 3));
        }
        if (ex.contains(0x9209)) r.insert(QStringLiteral("flash"), (t.entero(ex.value(0x9209)) & 1) ? QStringLiteral("Con flash") : QStringLiteral("Sin flash"));
        if (ex.contains(0xA434)) {
            const QString obj = t.texto(ex.value(0xA434));
            if (!obj.isEmpty()) r.insert(QStringLiteral("objetivo"), obj);
        }
    }
    const QDateTime dt = QDateTime::fromString(fecha, QStringLiteral("yyyy:MM:dd HH:mm:ss"));
    if (dt.isValid() && dt.date().year() > 1980) r.insert(QStringLiteral("fecha"), dt);

    if (ifd0.contains(0x8825)) {
        const auto g = t.ifd(int(t.entero(ifd0.value(0x8825))));
        if (g.contains(2) && g.contains(4)) {
            auto grados = [&](const Tiff::Entrada &e) { return t.racional(e, 0) + t.racional(e, 1) / 60.0 + t.racional(e, 2) / 3600.0; };
            double lat = grados(g.value(2)), lon = grados(g.value(4));
            if (g.contains(1) && t.texto(g.value(1)).startsWith(QLatin1Char('S'))) lat = -lat;
            if (g.contains(3) && t.texto(g.value(3)).startsWith(QLatin1Char('W'))) lon = -lon;
            if (lat != 0 || lon != 0) {
                r.insert(QStringLiteral("lat"), lat);
                r.insert(QStringLiteral("lon"), lon);
            }
        }
    }
    return r;
}

QByteArray Exif::segmentoParaCopia(const QString &ruta)
{
    QByteArray tiff = bloqueExif(ruta);
    const Tiff t(tiff);
    if (!t.ok() || tiff.size() > 60000)
        return {};
    // Orientación (0x0112) del IFD0 -> 1
    const int ifd0 = int(t.u32(4));
    const int cuantas = t.u16(ifd0);
    const bool le = tiff.startsWith("II");
    for (int i = 0; i < cuantas && i < 500; ++i) {
        const int e = ifd0 + 2 + i * 12;
        if (e + 12 > tiff.size())
            break;
        if (t.u16(e) == 0x0112) {
            uchar *v = reinterpret_cast<uchar *>(tiff.data() + e + 8);
            if (le) qToLittleEndian<quint16>(1, v);
            else qToBigEndian<quint16>(1, v);
        }
    }
    const QByteArray datos = QByteArrayLiteral("Exif\0\0") + tiff;
    QByteArray seg("\xFF\xE1", 2);
    seg.append(char((datos.size() + 2) >> 8));
    seg.append(char((datos.size() + 2) & 0xFF));
    return seg + datos;
}
