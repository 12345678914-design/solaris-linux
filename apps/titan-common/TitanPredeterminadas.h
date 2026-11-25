// Inti OS - aplicaciones predeterminadas que elige cada persona en
// Ajustes > Aplicaciones predeterminadas (las guarda en ~/.config/mimeapps.list,
// el estándar freedesktop que también leen Firefox, GTK y xdg-open).
//
// El escritorio y el Explorador abren algunos tipos con apps fijas (Fotos,
// Música, ONLYOFFICE); con esto, lo que la persona elija va siempre antes.
#pragma once

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QProcess>
#include <QStandardPaths>
#include <QString>
#include <QStringList>
#include <QTextStream>

#include "TitanIconoApp.h"

namespace titan {

inline QString mimeappsPropio()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/mimeapps.list");
}

// Valor de [Default Applications] para ese tipo en el mimeapps.list de la persona
inline QString elegidaPara(const QString &mime)
{
    QFile f(mimeappsPropio());
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();
    bool dentro = false;
    QTextStream in(&f);
    while (!in.atEnd()) {
        const QString l = in.readLine().trimmed();
        if (l.startsWith(QLatin1Char('['))) {
            dentro = l == QLatin1String("[Default Applications]");
            continue;
        }
        if (dentro && l.startsWith(mime + QLatin1Char('=')))
            return l.mid(mime.size() + 1);
    }
    return QString();
}

// Ruta del .desktop (nombre como "org.gnome.Evince.desktop"); "" si no existe
inline QString rutaDesktop(const QString &nombre)
{
    if (nombre.isEmpty() || nombre.contains(QLatin1Char('/')))
        return QString();
    for (const QString &d : dirsAplicaciones()) {
        const QString r = d + QLatin1Char('/') + nombre;
        if (QFile::exists(r))
            return r;
    }
    return QString();
}

// Si la persona eligió una app para el tipo de este archivo, lo abre con
// ella y devuelve true. Si no eligió nada, false (sigue lo de siempre).
inline bool abrirConElegida(const QString &ruta)
{
    const QMimeType mime = QMimeDatabase().mimeTypeForFile(ruta);
    QStringList tipos{mime.name()};
    tipos << mime.aliases();
    for (const QString &t : std::as_const(tipos)) {
        for (const QString &app : elegidaPara(t).split(QLatin1Char(';'), Qt::SkipEmptyParts)) {
            const QString desktop = rutaDesktop(app.trimmed());
            if (!desktop.isEmpty())
                return QProcess::startDetached(QStringLiteral("gio"), {QStringLiteral("launch"), desktop, ruta});
        }
    }
    return false;
}

} // namespace titan
