// Inti OS - Fotos: ajustes del editor. La vista previa y el archivo guardado
// pasan por la misma función, así que lo que se ve es lo que se guarda.
//
// Parámetros (texto separado por ';'):
//   rot;fh;fv;brillo;contraste;saturacion;calidez;filtro;x;y;w;h
//   rot = 0/90/180/270, fh/fv = 0/1, ajustes en [-1, 1], filtro = nombre,
//   x,y,w,h = recorte normalizado (0..1) sobre la imagen ya girada.
#pragma once

#include <QImage>
#include <QRectF>
#include <QStringList>
#include <QTransform>
#include <QtMath>

struct Ajustes
{
    int rot = 0;
    bool fh = false, fv = false;
    double brillo = 0, contraste = 0, saturacion = 0, calidez = 0;
    QString filtro;
    QRectF recorte{0, 0, 1, 1};

    static Ajustes leer(const QString &texto)
    {
        Ajustes a;
        const QStringList p = texto.split(QLatin1Char(';'));
        auto num = [&](int i, double def) {
            bool ok = false;
            const double v = p.value(i).toDouble(&ok);
            return ok ? v : def;
        };
        a.rot = ((int(num(0, 0)) % 360) + 360) % 360;
        a.fh = num(1, 0) != 0;
        a.fv = num(2, 0) != 0;
        a.brillo = qBound(-1.0, num(3, 0), 1.0);
        a.contraste = qBound(-1.0, num(4, 0), 1.0);
        a.saturacion = qBound(-1.0, num(5, 0), 1.0);
        a.calidez = qBound(-1.0, num(6, 0), 1.0);
        a.filtro = p.value(7);
        const QRectF r(num(8, 0), num(9, 0), num(10, 1), num(11, 1));
        a.recorte = r.intersected(QRectF(0, 0, 1, 1));
        if (a.recorte.width() < 0.01 || a.recorte.height() < 0.01)
            a.recorte = QRectF(0, 0, 1, 1);
        return a;
    }
    bool hayColor() const
    {
        return brillo != 0 || contraste != 0 || saturacion != 0 || calidez != 0 || (!filtro.isEmpty() && filtro != QLatin1String("ninguno"));
    }
    bool hayRecorte() const { return recorte != QRectF(0, 0, 1, 1); }
};

namespace Edicion {

inline QImage geometria(const QImage &img, const Ajustes &a, bool recortar)
{
    QImage r = img;
    if (a.fh || a.fv)
        r = r.flipped((a.fh ? Qt::Horizontal : Qt::Orientations()) | (a.fv ? Qt::Vertical : Qt::Orientations()));
    if (a.rot)
        r = r.transformed(QTransform().rotate(a.rot));
    if (recortar && a.hayRecorte()) {
        const QRect c(qRound(a.recorte.x() * r.width()), qRound(a.recorte.y() * r.height()),
                      qMax(1, qRound(a.recorte.width() * r.width())), qMax(1, qRound(a.recorte.height() * r.height())));
        r = r.copy(c.intersected(r.rect()));
    }
    return r;
}

inline void color(QImage &img, const Ajustes &a)
{
    if (!a.hayColor())
        return;
    if (img.format() != QImage::Format_ARGB32 && img.format() != QImage::Format_RGB32)
        img = img.convertToFormat(img.hasAlphaChannel() ? QImage::Format_ARGB32 : QImage::Format_RGB32);

    // Lo que añade cada filtro (se suma a los deslizadores)
    double br = a.brillo * 0.35, ct = a.contraste, sat = a.saturacion, cal = a.calidez;
    double sepia = 0, desvaido = 0;
    bool bn = false;
    const QString &f = a.filtro;
    if (f == QLatin1String("vivo")) { sat += 0.35; ct += 0.12; }
    else if (f == QLatin1String("dramatico")) { ct += 0.40; sat -= 0.25; br -= 0.03; }
    else if (f == QLatin1String("bn")) { bn = true; ct += 0.10; }
    else if (f == QLatin1String("sepia")) { sepia = 1.0; }
    else if (f == QLatin1String("calido")) { cal += 0.45; sat += 0.08; }
    else if (f == QLatin1String("frio")) { cal -= 0.45; }
    else if (f == QLatin1String("nostalgia")) { desvaido = 0.6; sepia = 0.35; sat -= 0.15; }
    const double kC = 1.0 + qBound(-0.95, ct, 1.5) * 0.85;
    const double kS = qMax(0.0, 1.0 + sat);

    // Tabla por canal para brillo + contraste (lo caro); el resto por píxel
    uchar lut[256];
    for (int i = 0; i < 256; ++i) {
        double v = i / 255.0 + br;
        v = (v - 0.5) * kC + 0.5;
        if (desvaido > 0) v = v * (1.0 - 0.22 * desvaido) + 0.10 * desvaido;
        lut[i] = uchar(qBound(0, qRound(v * 255.0), 255));
    }
    const int dR = qRound(cal * 0.09 * 255), dB = qRound(-cal * 0.09 * 255);

    for (int y = 0; y < img.height(); ++y) {
        QRgb *fila = reinterpret_cast<QRgb *>(img.scanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const QRgb p = fila[x];
            double r = lut[qRed(p)], g = lut[qGreen(p)], b = lut[qBlue(p)];
            const double gris = 0.299 * r + 0.587 * g + 0.114 * b;
            if (bn) {
                r = g = b = gris;
            } else if (kS != 1.0) {
                r = gris + (r - gris) * kS;
                g = gris + (g - gris) * kS;
                b = gris + (b - gris) * kS;
            }
            if (sepia > 0) {
                const double sr = 0.393 * r + 0.769 * g + 0.189 * b;
                const double sg = 0.349 * r + 0.686 * g + 0.168 * b;
                const double sb = 0.272 * r + 0.534 * g + 0.131 * b;
                r += (sr - r) * sepia;
                g += (sg - g) * sepia;
                b += (sb - b) * sepia;
            }
            r += dR;
            b += dB;
            fila[x] = qRgba(qBound(0, int(r + 0.5), 255), qBound(0, int(g + 0.5), 255), qBound(0, int(b + 0.5), 255), qAlpha(p));
        }
    }
}

inline QImage aplicar(const QImage &img, const Ajustes &a, bool recortar)
{
    QImage r = geometria(img, a, recortar);
    color(r, a);
    return r;
}

} // namespace Edicion
