#pragma once
// Busqueda unica de los ejecutables del escritorio (titan-finder, titan-terminal...).
//
// Orden: ruta absoluta dada tal cual, $PATH, /usr/local/bin, /usr/bin y, solo
// para desarrollo (make run), las carpetas hermanas del propio binario dentro
// de apps/. Nunca se busca en el directorio actual: un fichero con el mismo
// nombre en el home del usuario no debe ejecutarse en lugar del programa.

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QString>
#include <QStringList>

namespace titan {

inline bool esEjecutable(const QString &ruta)
{
    const QFileInfo fi(ruta);
    return fi.exists() && fi.isFile() && fi.isExecutable();
}

inline QString resolverBinario(const QString &programa)
{
    if (programa.isEmpty()) return programa;

    if (QDir::isAbsolutePath(programa)) return programa;

    // Un nombre con '/' relativo dependeria del directorio actual: no se acepta.
    if (programa.contains(QLatin1Char('/'))) return programa;

    const QString enPath = QStandardPaths::findExecutable(programa);
    if (!enPath.isEmpty()) return enPath;

    const QString dirApp = QCoreApplication::applicationDirPath();
    const QStringList candidatos = {
        QStringLiteral("/usr/local/bin/") + programa,
        QStringLiteral("/usr/bin/") + programa,
        dirApp + QStringLiteral("/../") + programa + QStringLiteral("/") + programa,
        dirApp + QStringLiteral("/../") + programa + QStringLiteral("/build/") + programa,
    };
    for (const QString &c : candidatos) {
        if (esEjecutable(c)) return QFileInfo(c).canonicalFilePath();
    }
    return programa;
}

} // namespace titan
