// Inti OS - iconos que siguen el color de acento (como las carpetas de macOS).
//
// "image://tinte/<rrggbb>/<ruta en qrc>" devuelve el PNG con su parte azul
// llevada al tono del acento. Se conservan el sombreado y lo que no es azul
// (los simbolos blancos de las carpetas, la cara del Finder...). Con un acento
// gris (Grafito) la carpeta sale gris.
//
// En QML:  source: "image://tinte/" + acento.substring(1) + "/icons/folder.png"
#pragma once

#include <QColor>
#include <QImage>
#include <QQuickImageProvider>
#include <QStringList>
#include <QtMath>

class TitanTinte : public QQuickImageProvider
{
public:
    TitanTinte()
        : QQuickImageProvider(QQuickImageProvider::Image)
    {
    }

    // Iconos que se tiñen (los demas se devuelven tal cual desde qrc).
    static bool seTine(const QString &ruta)
    {
        static const QStringList nombres = {
            QStringLiteral("folder.png"), QStringLiteral("desktop.png"), QStringLiteral("downloads.png"),
            QStringLiteral("apps-folder.png"), QStringLiteral("music-folder.png"), QStringLiteral("finder.png")};
        for (const QString &n : nombres)
            if (ruta.endsWith(QLatin1Char('/') + n))
                return true;
        return false;
    }

    QImage requestImage(const QString &id, QSize *size, const QSize &pedido) override
    {
        const int barra = id.indexOf(QLatin1Char('/'));
        const QColor acento(QLatin1Char('#') + id.left(barra));
        QImage img(QLatin1Char(':') + id.mid(barra));
        if (img.isNull())
            img = QImage(QStringLiteral(":/") + id.mid(barra + 1));
        if (!img.isNull() && acento.isValid())
            tenir(img, acento);
        if (size)
            *size = img.size();
        if (pedido.isValid() && !img.isNull() && (pedido.width() > 0 || pedido.height() > 0))
            img = img.scaled(pedido.width() > 0 ? pedido.width() : img.width(),
                             pedido.height() > 0 ? pedido.height() : img.height(),
                             Qt::KeepAspectRatio, Qt::SmoothTransformation);
        return img;
    }

private:
    static bool esAzul(float h, float s) { return s > 0.12f && h >= 170.0f / 360.0f && h <= 260.0f / 360.0f; }

    static void tenir(QImage &img, const QColor &acento)
    {
        img = img.convertToFormat(QImage::Format_ARGB32);
        // Azul de referencia: media de los pixeles azules bien saturados.
        double sumS = 0, sumV = 0, n = 0;
        for (int y = 0; y < img.height(); ++y) {
            const QRgb *fila = reinterpret_cast<const QRgb *>(img.constScanLine(y));
            for (int x = 0; x < img.width(); ++x) {
                if (qAlpha(fila[x]) < 128)
                    continue;
                float h, s, v, a;
                QColor::fromRgba(fila[x]).getHsvF(&h, &s, &v, &a);
                if (esAzul(h, s) && s > 0.35f) {
                    sumS += s;
                    sumV += v;
                    n += 1;
                }
            }
        }
        if (n < 1)
            return;
        float ah, as, av, aa;
        acento.getHsvF(&ah, &as, &av, &aa);
        if (ah < 0)
            ah = 0; // gris: sin tono
        const double kS = as / (sumS / n);
        const double kV = av / (sumV / n);
        for (int y = 0; y < img.height(); ++y) {
            QRgb *fila = reinterpret_cast<QRgb *>(img.scanLine(y));
            for (int x = 0; x < img.width(); ++x) {
                const QRgb p = fila[x];
                if (qAlpha(p) == 0)
                    continue;
                float h, s, v, a;
                QColor::fromRgba(p).getHsvF(&h, &s, &v, &a);
                if (!esAzul(h, s))
                    continue;
                // Transicion suave en los bordes (poco saturados)
                const float w = qBound(0.0f, (s - 0.12f) / 0.18f, 1.0f);
                const QColor nuevo = QColor::fromHsvF(ah, qBound(0.0, s * kS, 1.0), qBound(0.0, v * kV, 1.0), a);
                const QColor viejo = QColor::fromRgba(p);
                fila[x] = qRgba(qRound(viejo.red() + (nuevo.red() - viejo.red()) * w),
                                qRound(viejo.green() + (nuevo.green() - viejo.green()) * w),
                                qRound(viejo.blue() + (nuevo.blue() - viejo.blue()) * w), qAlpha(p));
            }
        }
    }
};
