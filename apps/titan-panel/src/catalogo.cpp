#include "catalogo.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QTextStream>

#include <algorithm>

namespace {

QString desescapar(const QString &texto)
{
    QString salida;
    salida.reserve(texto.size());
    for (int i = 0; i < texto.size(); ++i) {
        const QChar c = texto.at(i);
        if (c != QLatin1Char('\\') || i + 1 >= texto.size()) {
            salida.append(c);
            continue;
        }
        const QChar siguiente = texto.at(++i);
        switch (siguiente.unicode()) {
        case 's':
            salida.append(QLatin1Char(' '));
            break;
        case 'n':
            salida.append(QLatin1Char('\n'));
            break;
        case 't':
            salida.append(QLatin1Char('\t'));
            break;
        case 'r':
            salida.append(QLatin1Char('\r'));
            break;
        case '\\':
            salida.append(QLatin1Char('\\'));
            break;
        default:
            salida.append(siguiente);
            break;
        }
    }
    return salida;
}

bool verdadero(const QString &valor)
{
    return valor.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0;
}

QString ejecutableValido(const QString &programa)
{
    if (programa.isEmpty()) {
        return QString();
    }
    const QString encontrado = QStandardPaths::findExecutable(programa);
    if (!encontrado.isEmpty()) {
        return encontrado;
    }
    const QFileInfo info(programa);
    if (info.isFile() && info.isExecutable()) {
        return info.absoluteFilePath();
    }
    return QString();
}

} // namespace

QString Catalogo::limpiarExec(const QString &exec)
{
    // Los codigos de campo se sustituyen por nada. %% se protege primero para
    // que el porcentaje literal no se confunda con un codigo.
    QString limpio = exec;
    limpio.replace(QStringLiteral("%%"), QStringLiteral("\x01"));
    static const QRegularExpression codigos(
        QStringLiteral("%[fFuUdDnNickvm]"));
    limpio.remove(codigos);
    limpio.replace(QStringLiteral("\x01"), QStringLiteral("%"));
    return limpio.simplified();
}

void Catalogo::cargar()
{
    QStringList directorios;
    const QStringList xdg =
        QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
    for (const QString &dir : xdg) {
        if (!directorios.contains(dir)) {
            directorios << dir;
        }
    }
    cargarDesde(directorios);
}

void Catalogo::cargarDesde(const QStringList &directorios)
{
    m_aplicaciones.clear();
    QSet<QString> vistos;

    for (const QString &directorio : directorios) {
        QDir base(directorio);
        if (!base.exists()) {
            continue;
        }
        QStringList ficheros;
        QDirIterator iterador(directorio,
                             {QStringLiteral("*.desktop")},
                             QDir::Files,
                             QDirIterator::Subdirectories);
        while (iterador.hasNext()) {
            ficheros << iterador.next();
        }
        std::sort(ficheros.begin(), ficheros.end());
        for (const QString &ruta : ficheros) {
            const QString id = base.relativeFilePath(ruta)
                                   .replace(QLatin1Char('/'),
                                            QLatin1Char('-'));
            if (vistos.contains(id)) {
                continue;
            }

            QFile fichero(ruta);
            if (!fichero.open(QIODevice::ReadOnly | QIODevice::Text)) {
                continue;
            }
            QTextStream entrada(&fichero);
            QString seccion;
            QString nombre;
            QString nombreEs;
            QString comentario;
            QString comentarioEs;
            QString icono;
            QString exec;
            QString wmClass;
            QString tipo = QStringLiteral("Application");
            QString tryExec;
            bool terminal = false;
            bool oculto = false;

            while (!entrada.atEnd()) {
                const QString linea = entrada.readLine();
                if (linea.startsWith(QLatin1Char('['))) {
                    seccion = linea.trimmed();
                    continue;
                }
                if (seccion != QStringLiteral("[Desktop Entry]")) {
                    continue;
                }
                const int igual = linea.indexOf(QLatin1Char('='));
                if (igual <= 0) {
                    continue;
                }
                const QString clave = linea.left(igual).trimmed();
                const QString valor =
                    desescapar(linea.mid(igual + 1).trimmed());
                if (clave == QStringLiteral("Name")) {
                    nombre = valor;
                } else if (clave == QStringLiteral("Name[es]")) {
                    nombreEs = valor;
                } else if (clave == QStringLiteral("Comment")) {
                    comentario = valor;
                } else if (clave == QStringLiteral("Comment[es]")) {
                    comentarioEs = valor;
                } else if (clave == QStringLiteral("Icon")) {
                    icono = valor;
                } else if (clave == QStringLiteral("Exec")) {
                    exec = valor;
                } else if (clave == QStringLiteral("StartupWMClass")) {
                    wmClass = valor;
                } else if (clave == QStringLiteral("Type")) {
                    tipo = valor;
                } else if (clave == QStringLiteral("TryExec")) {
                    tryExec = valor;
                } else if (clave == QStringLiteral("Terminal")) {
                    terminal = verdadero(valor);
                } else if (clave == QStringLiteral("NoDisplay") ||
                           clave == QStringLiteral("Hidden")) {
                    oculto = oculto || verdadero(valor);
                }
            }

            if (oculto || tipo != QStringLiteral("Application") ||
                exec.trimmed().isEmpty()) {
                continue;
            }
            if (!tryExec.isEmpty() && ejecutableValido(tryExec).isEmpty()) {
                continue;
            }

            Aplicacion app;
            app.id = id;
            app.ruta = ruta;
            app.nombre = nombreEs.isEmpty() ? nombre : nombreEs;
            if (app.nombre.isEmpty()) {
                app.nombre = QFileInfo(ruta).completeBaseName();
            }
            app.comentario =
                comentarioEs.isEmpty() ? comentario : comentarioEs;
            app.icono = icono;
            if (app.icono.isEmpty()) {
                app.icono = app.id;
                if (app.icono.endsWith(QStringLiteral(".desktop"))) {
                    app.icono.chop(8);
                }
            }
            app.exec = limpiarExec(exec);
            app.wmClass = wmClass;
            if (app.wmClass.isEmpty()) {
                app.wmClass = QFileInfo(ruta).completeBaseName();
            }
            app.terminal = terminal;
            m_aplicaciones << app;
            vistos.insert(id);
        }
    }

    std::sort(m_aplicaciones.begin(), m_aplicaciones.end(),
              [](const Aplicacion &a, const Aplicacion &b) {
                  return QString::localeAwareCompare(a.nombre, b.nombre) < 0;
              });
}

QVector<Aplicacion> Catalogo::aplicaciones() const
{
    return m_aplicaciones;
}

const Aplicacion *Catalogo::buscarPorAppId(const QString &appId) const
{
    if (appId.isEmpty()) {
        return nullptr;
    }
    for (const Aplicacion &app : m_aplicaciones) {
        QString id = app.id;
        if (id.endsWith(QStringLiteral(".desktop"))) {
            id.chop(8);
        }
        if (id.compare(appId, Qt::CaseInsensitive) == 0 ||
            app.wmClass.compare(appId, Qt::CaseInsensitive) == 0) {
            return &app;
        }
    }
    return nullptr;
}

QString Catalogo::iconoParaAppId(const QString &appId) const
{
    const Aplicacion *app = buscarPorAppId(appId);
    return app ? app->icono : QString();
}

bool Catalogo::lanzar(const Aplicacion &app, const QString &terminal,
                      QString *error)
{
    const QString limpio = limpiarExec(app.exec);
    QStringList partes = QProcess::splitCommand(limpio);
    if (partes.isEmpty()) {
        if (error) {
            *error = QStringLiteral("La entrada no tiene un comando.");
        }
        return false;
    }

    QString programa;
    QStringList argumentos;
    if (app.terminal) {
        QStringList term = QProcess::splitCommand(terminal);
        if (term.isEmpty()) {
            if (error) {
                *error = QStringLiteral("No hay terminal configurado.");
            }
            return false;
        }
        programa = term.takeFirst();
        argumentos = term + partes;
    } else {
        int inicio = 0;
        while (inicio < partes.size() &&
               partes.at(inicio).contains(QLatin1Char('=')) &&
               !partes.at(inicio).startsWith(QLatin1Char('-')) &&
               !partes.at(inicio).contains(QLatin1Char('/'))) {
            ++inicio;
        }
        if (inicio > 0) {
            programa = QStringLiteral("/usr/bin/env");
            argumentos = partes;
        } else {
            programa = partes.takeFirst();
            argumentos = partes;
        }
    }

    if (!QProcess::startDetached(programa, argumentos)) {
        if (error) {
            *error = QStringLiteral("No se pudo ejecutar %1.").arg(programa);
        }
        return false;
    }
    return true;
}
