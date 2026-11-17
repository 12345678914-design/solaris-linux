#pragma once
// Lectura de ficheros .desktop compartida por el lanzador y el escritorio.
#include <QFile>
#include <QHash>
#include <QString>
#include <QStringList>
#include <QtGlobal>

namespace titan {

// Lector mínimo de ficheros .desktop (grupo [Desktop Entry]). QSettings no
// sirve: trata las comas como listas (un Name= o Exec= con coma salía vacío y
// la app desaparecía) y no entiende las claves localizadas como Name[es].
inline QHash<QString, QString> leerDesktop(const QString &ruta)
{
    QHash<QString, QString> claves;
    QFile f(ruta);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return claves;
    bool enEntrada = false;
    while (!f.atEnd()) {
        const QString linea = QString::fromUtf8(f.readLine()).trimmed();
        if (linea.isEmpty() || linea.startsWith(QLatin1Char('#')))
            continue;
        if (linea.startsWith(QLatin1Char('['))) {
            enEntrada = (linea == QStringLiteral("[Desktop Entry]"));
            continue;
        }
        if (!enEntrada)
            continue;
        const int igual = linea.indexOf(QLatin1Char('='));
        if (igual <= 0)
            continue;
        const QString clave = linea.left(igual).trimmed();
        if (!claves.contains(clave))
            claves.insert(clave, linea.mid(igual + 1).trimmed());
    }
    return claves;
}

inline bool esVerdadero(const QString &v)
{
    return v.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0;
}

// ¿Está 'nuestro' escritorio en una lista "A;B;C;" de OnlyShowIn/NotShowIn?
inline bool listaContieneEscritorio(const QString &lista)
{
    const QStringList propios = qEnvironmentVariable("XDG_CURRENT_DESKTOP", QStringLiteral("Titan:labwc"))
                                    .split(QLatin1Char(':'), Qt::SkipEmptyParts);
    const QStringList items = lista.split(QLatin1Char(';'), Qt::SkipEmptyParts);
    for (const QString &d : propios) {
        if (items.contains(d, Qt::CaseInsensitive))
            return true;
    }
    return false;
}

} // namespace titan
