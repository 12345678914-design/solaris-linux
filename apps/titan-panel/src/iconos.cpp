#include "iconos.h"

#include <QColor>
#include <QPainter>
#include <QPixmap>

QIcon iconoAplicacion(const QString &nombreTema, const QString &texto)
{
    if (!nombreTema.isEmpty()) {
        QIcon icono = QIcon::fromTheme(nombreTema);
        if (icono.isNull() &&
            !nombreTema.endsWith(QStringLiteral("-symbolic"))) {
            icono = QIcon::fromTheme(
                nombreTema + QStringLiteral("-symbolic"));
        }
        if (!icono.isNull()) {
            return icono;
        }
    }
    QIcon generico =
        QIcon::fromTheme(QStringLiteral("application-x-executable"));
    if (generico.isNull()) {
        generico = QIcon::fromTheme(
            QStringLiteral("application-x-executable-symbolic"));
    }
    if (!generico.isNull()) {
        return generico;
    }

    // Ultimo recurso: una ventana neutra, nunca una letra. Las iniciales
    // (T de Terminal, A de Archivos) parecian nombres de aplicacion y no
    // coincidian con el icono que el usuario ve en el menu de inicio.
    const int tono = int(qHash(texto) % 360);
    QPixmap lienzo(64, 64);
    lienzo.fill(Qt::transparent);

    QPainter pintor(&lienzo);
    pintor.setRenderHint(QPainter::Antialiasing);
    pintor.setPen(Qt::NoPen);
    pintor.setBrush(QColor::fromHsl(tono, 150, 110));
    pintor.drawRoundedRect(QRectF(2, 2, 60, 60), 14, 14);

    pintor.setBrush(QColor(QStringLiteral("#f4f7ff")));
    pintor.drawRoundedRect(QRectF(13, 18, 38, 29), 5, 5);
    pintor.setBrush(QColor::fromHsl(tono, 150, 110).darker(145));
    pintor.drawRoundedRect(QRectF(17, 23, 30, 5), 2, 2);
    pintor.drawRoundedRect(QRectF(17, 32, 22, 3), 1, 1);
    pintor.drawRoundedRect(QRectF(17, 38, 26, 3), 1, 1);
    pintor.end();

    return QIcon(lienzo);
}

QIcon iconoInicio()
{
    QPixmap lienzo(64, 64);
    lienzo.fill(Qt::transparent);

    QPainter pintor(&lienzo);
    pintor.setRenderHint(QPainter::Antialiasing);
    pintor.setPen(Qt::NoPen);
    pintor.setBrush(QColor(QStringLiteral("#4fc4ff")));
    pintor.drawRoundedRect(QRectF(7, 7, 22, 22), 6, 6);
    pintor.setBrush(QColor(QStringLiteral("#8be0ff")));
    pintor.drawRoundedRect(QRectF(35, 7, 22, 22), 6, 6);
    pintor.setBrush(QColor(QStringLiteral("#8be0ff")));
    pintor.drawRoundedRect(QRectF(7, 35, 22, 22), 6, 6);
    pintor.setBrush(QColor(QStringLiteral("#4fc4ff")));
    pintor.drawRoundedRect(QRectF(35, 35, 22, 22), 6, 6);
    pintor.end();

    return QIcon(lienzo);
}
