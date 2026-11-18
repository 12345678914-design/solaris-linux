// Inti OS - Fotos: proveedores de imágenes para QML.
//
//  image://miniatura/<md5>   miniatura de 256 px, guardada en
//                            ~/.cache/thumbnails/large (estándar freedesktop,
//                            la comparten otras aplicaciones)
//  image://edicion/<params>  vista previa del editor (ver Edicion.h)
#pragma once

#include "Edicion.h"
#include "FotosBackend.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QImageReader>
#include <QQuickImageProvider>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>

class ProveedorMiniaturas : public QQuickImageProvider
{
public:
    explicit ProveedorMiniaturas(FotosBackend *b)
        : QQuickImageProvider(QQuickImageProvider::Image), m_b(b)
    {
    }

    static QString clave(const QString &ruta)
    {
        return QString::fromLatin1(QCryptographicHash::hash(QUrl::fromLocalFile(ruta).toEncoded(), QCryptographicHash::Md5).toHex());
    }

    QImage requestImage(const QString &id, QSize *size, const QSize &pedido) override
    {
        const QString md5 = id.section(QLatin1Char('?'), 0, 0);
        const QString ruta = m_b->rutaDeClave(md5);
        QImage img;
        if (!ruta.isEmpty())
            img = miniatura(ruta, md5);
        if (size)
            *size = img.size();
        if (!img.isNull() && pedido.isValid() && (pedido.width() < img.width() && pedido.height() < img.height()))
            img = img.scaled(pedido, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
        return img;
    }

private:
    static QImage miniatura(const QString &ruta, const QString &md5)
    {
        const QFileInfo fi(ruta);
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/thumbnails/large/");
        const QString cache = dir + md5 + QStringLiteral(".png");
        const QString mtime = QString::number(fi.lastModified().toSecsSinceEpoch());
        {
            QImageReader r(cache);
            if (r.canRead() && r.text(QStringLiteral("Thumb::MTime")) == mtime) {
                const QImage c = r.read();
                if (!c.isNull())
                    return c;
            }
        }
        QImageReader r(ruta);
        r.setAutoTransform(true);
        QSize s = r.size();
        if (s.isValid() && (s.width() > 256 || s.height() > 256)) {
            s.scale(256, 256, Qt::KeepAspectRatio);
            r.setScaledSize(s);
        }
        QImage img = r.read();
        if (img.isNull())
            return img;
        if (img.width() > 256 || img.height() > 256)
            img = img.scaled(256, 256, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        // Las vectoriales y las pequeñas no se guardan (no hace falta)
        if (!ruta.endsWith(QLatin1String(".svg"), Qt::CaseInsensitive) && fi.size() > 64 * 1024 && QDir().mkpath(dir)) {
            QImage guardar = img;
            guardar.setText(QStringLiteral("Thumb::URI"), QUrl::fromLocalFile(ruta).toString(QUrl::FullyEncoded));
            guardar.setText(QStringLiteral("Thumb::MTime"), mtime);
            guardar.setText(QStringLiteral("Software"), QStringLiteral("Inti OS Fotos"));
            QSaveFile f(cache);
            if (f.open(QIODevice::WriteOnly) && guardar.save(&f, "PNG"))
                f.commit();
        }
        return img;
    }

    FotosBackend *m_b;
};

class ProveedorEdicion : public QQuickImageProvider
{
public:
    explicit ProveedorEdicion(FotosBackend *b)
        : QQuickImageProvider(QQuickImageProvider::Image), m_b(b)
    {
    }
    QImage requestImage(const QString &id, QSize *size, const QSize &pedido) override
    {
        const QImage img = m_b->vistaPrevia(id.section(QLatin1Char('#'), 0, 0), pedido);
        if (size)
            *size = img.size();
        return img;
    }

private:
    FotosBackend *m_b;
};
