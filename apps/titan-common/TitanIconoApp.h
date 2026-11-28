#pragma once
// Icono de una app, el mismo en el lanzador, el Dock y el escritorio.
//
// Antes cada uno tenía su buscador: el Dock y el escritorio probaban primero
// palabras sueltas ("video", "music", "control"...) y solo miraban algunos
// tamaños, así que una app de Flathub salía con su icono en el lanzador y con
// otro (o uno genérico) en el Dock y en el escritorio.
#include "TitanDesktopEntry.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QRegularExpression>
#include <QString>
#include <QStringList>
#include <QUrl>

namespace titan {

// Bases XDG con iconos y apps: el usuario, Flatpak (usuario y sistema) y el sistema.
inline QStringList basesDatos()
{
    const QString casa = QDir::homePath();
    return {casa + QStringLiteral("/.local/share"),
            casa + QStringLiteral("/.local/share/flatpak/exports/share"),
            QStringLiteral("/var/lib/flatpak/exports/share"),
            QStringLiteral("/usr/local/share"),
            QStringLiteral("/usr/share")};
}

inline QStringList dirsAplicaciones()
{
    QStringList d;
    for (const QString &b : basesDatos())
        d << b + QStringLiteral("/applications");
    return d;
}

// Fichero del tema hicolor (o pixmaps / iconos de Inti) con ese nombre; "" si no hay.
inline QString buscarIconoTema(const QString &nombre)
{
    if (nombre.isEmpty() || nombre.contains(QLatin1Char('/')))
        return QString();
    static QHash<QString, QString> cache;
    const auto it = cache.constFind(nombre);
    if (it != cache.constEnd() && QFile::exists(it.value()))
        return it.value();

    static const char *const tamanos[] = {"scalable", "512x512", "256x256", "192x192", "128x128",
                                          "96x96", "64x64", "48x48", "32x32"};
    QStringList dirs;
    for (const QString &b : basesDatos()) {
        for (const char *t : tamanos)
            dirs << b + QStringLiteral("/icons/hicolor/") + QLatin1String(t) + QStringLiteral("/apps/");
    }
    dirs << QStringLiteral("/usr/share/icons/Adwaita/scalable/apps/")
         << QStringLiteral("/usr/share/icons/Adwaita/48x48/apps/")
         << QStringLiteral("/usr/share/pixmaps/")
         << QStringLiteral("/usr/share/titan/icons/");
    for (const QString &d : dirs) {
        for (const char *ext : {".svg", ".png"}) {
            const QString f = d + nombre + QLatin1String(ext);
            if (QFile::exists(f)) {
                cache.insert(nombre, f);
                return f;
            }
        }
    }
    return QString();
}

// .desktop de una ventana por su app_id ("org.kde.kdenlive", "firefox"...):
// el fichero con ese nombre o el que la declara en StartupWMClass. "" si no hay.
inline QString desktopDeAppId(const QString &appId)
{
    const QString clave = appId.trimmed().toLower();
    if (clave.isEmpty())
        return QString();
    static QHash<QString, QString> cache;   // solo aciertos: una app instalada después se encuentra
    const auto it = cache.constFind(clave);
    if (it != cache.constEnd() && QFile::exists(it.value()))
        return it.value();

    const QStringList dirs = dirsAplicaciones();
    for (const QString &d : dirs) {
        const auto ficheros = QDir(d).entryInfoList({QStringLiteral("*.desktop")}, QDir::Files);
        for (const QFileInfo &f : ficheros) {
            if (f.completeBaseName().toLower() == clave) {
                cache.insert(clave, f.absoluteFilePath());
                return f.absoluteFilePath();
            }
        }
    }
    for (const QString &d : dirs) {
        const auto ficheros = QDir(d).entryInfoList({QStringLiteral("*.desktop")}, QDir::Files);
        for (const QFileInfo &f : ficheros) {
            if (leerDesktop(f.absoluteFilePath()).value(QStringLiteral("StartupWMClass")).toLower() == clave) {
                cache.insert(clave, f.absoluteFilePath());
                return f.absoluteFilePath();
            }
        }
    }
    return QString();
}

// Las apps propias (y Firefox, ONLYOFFICE, la App Store) llevan el icono de
// Inti OS, como en el lanzador. Se reconocen por el programa del Exec=.
inline QString iconoPropio(const QString &exec)
{
    QString prog = exec.trimmed().section(QLatin1Char(' '), 0, 0);
    prog = prog.mid(prog.lastIndexOf(QLatin1Char('/')) + 1);
    static const QHash<QString, QString> propios = {
        {QStringLiteral("titan-finder"), QStringLiteral("qrc:/icons/finder.png")},
        {QStringLiteral("firefox"), QStringLiteral("qrc:/icons/firefox.png")},
        {QStringLiteral("titan-fotos"), QStringLiteral("qrc:/icons/pictures.png")},
        {QStringLiteral("titan-musica"), QStringLiteral("qrc:/icons/music-app.png")},
        {QStringLiteral("titan-terminal"), QStringLiteral("qrc:/icons/terminal.png")},
        {QStringLiteral("kitty"), QStringLiteral("qrc:/icons/terminal.png")},
        {QStringLiteral("titan-calc"), QStringLiteral("qrc:/icons/calculator.png")},
        {QStringLiteral("titan-monitor"), QStringLiteral("qrc:/icons/monitor.png")},
        {QStringLiteral("titan-calendar"), QStringLiteral("qrc:/icons/calendar.png")},
        {QStringLiteral("titan-clock"), QStringLiteral("qrc:/icons/clock.png")},
        {QStringLiteral("titan-video"), QStringLiteral("qrc:/icons/video.png")},
        {QStringLiteral("plasma-discover"), QStringLiteral("qrc:/icons/apps-folder.png")},
        {QStringLiteral("titan-settings"), QStringLiteral("qrc:/icons/system.png")},
        {QStringLiteral("onlyoffice-desktopeditors"), QStringLiteral("qrc:/icons/onlyoffice.png")},
        {QStringLiteral("titan-acerca"), QStringLiteral("qrc:/icons/about.png")},
    };
    return propios.value(prog);
}

// Icono de una entrada .desktop (Icon= y Exec=) tal como lo pone el lanzador:
// el de Inti si es una app propia, el del tema (todos los tamaños, también
// Flatpak), y si no hay ninguno un icono de Inti parecido por el nombre.
// Devuelve "" si no encuentra nada (quien llama genera uno en SVG).
inline QString iconoApp(QString icono, const QString &exec)
{
    const QString propio = iconoPropio(exec);
    if (!propio.isEmpty())
        return propio;

    icono = icono.trimmed();
    if (icono.startsWith(QStringLiteral("qrc:/")) || icono.startsWith(QStringLiteral("file:/")))
        return icono;
    if (icono.startsWith(QLatin1Char('/'))) {
        if (QFile::exists(icono))
            return QUrl::fromLocalFile(icono).toString();
        // Ruta rota (app desinstalada a medias): se busca por el nombre.
        icono = QFileInfo(icono).completeBaseName();
    }
    // Icon=nombre.png: los temas guardan el nombre sin extensión.
    icono.remove(QRegularExpression(QStringLiteral("\\.(png|svg|xpm)$"), QRegularExpression::CaseInsensitiveOption));
    if (icono.isEmpty())
        return QString();

    const QString tema = buscarIconoTema(icono);
    if (!tema.isEmpty())
        return QUrl::fromLocalFile(tema).toString();

    // Sin icono en el sistema: uno de estilo macOS si el nombre lo sugiere
    const QString lower = icono.toLower();
    const QString execLower = exec.toLower();
    auto tiene = [&](std::initializer_list<const char *> palabras, bool enExec) {
        for (const char *p : palabras) {
            if (lower.contains(QLatin1String(p)) || (enExec && execLower.contains(QLatin1String(p))))
                return true;
        }
        return false;
    };
    if (tiene({"calc"}, true)) return QStringLiteral("qrc:/icons/calculator.png");
    if (tiene({"calendar"}, true)) return QStringLiteral("qrc:/icons/calendar.png");
    if (tiene({"clock"}, true)) return QStringLiteral("qrc:/icons/clock.png");
    if (tiene({"celluloid", "video"}, true)) return QStringLiteral("qrc:/icons/video.png");
    if (tiene({"software"}, true)) return QStringLiteral("qrc:/icons/apps-folder.png");
    if (tiene({"terminal", "kitty"}, true)) return QStringLiteral("qrc:/icons/terminal.png");
    if (tiene({"firefox", "browser", "chrome"}, true)) return QStringLiteral("qrc:/icons/firefox.png");
    if (tiene({"vim"}, true)) return QStringLiteral("qrc:/icons/developer.png");
    if (tiene({"htop"}, true)) return QStringLiteral("qrc:/icons/system.png");
    if (tiene({"code", "editor"}, true)) return QStringLiteral("qrc:/icons/vscode.png");
    if (tiene({"file", "folder", "pcmanfm"}, false) || execLower.contains(QStringLiteral("pcmanfm")))
        return QStringLiteral("qrc:/icons/files.png");
    if (tiene({"about", "info"}, false)) return QStringLiteral("qrc:/icons/about.png");
    if (tiene({"system", "setting", "control", "config"}, false)) return QStringLiteral("qrc:/icons/system.png");
    if (tiene({"music", "audio", "player", "spotify"}, false)) return QStringLiteral("qrc:/icons/music.png");
    if (tiene({"image", "photo", "picture", "gimp"}, false)) return QStringLiteral("qrc:/icons/pictures.png");
    if (tiene({"edit", "notes", "text"}, false)) return QStringLiteral("qrc:/icons/notes.png");
    if (tiene({"trash"}, false)) return QStringLiteral("qrc:/icons/trash.png");
    if (tiene({"dev", "build"}, false) || execLower.contains(QStringLiteral("gcc")) || execLower.contains(QStringLiteral("cmake")))
        return QStringLiteral("qrc:/icons/developer.png");
    return QString();
}

} // namespace titan
