#include "Predeterminadas.h"
#include "TitanDesktopEntry.h"
#include "TitanPredeterminadas.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QProcess>
#include <QSaveFile>
#include <QSet>
#include <QTextStream>
#include <algorithm>

namespace {

struct Tipo {
    const char *id;
    const char *nombre;
    const char *detalle;
    const char *simbolo;
    QStringList mimes;   // el primero decide cuál está puesta ahora
};

const QList<Tipo> &tiposConocidos()
{
    static const QList<Tipo> t = {
        {"navegador", "Navegador web", "Páginas web y enlaces", "🌐",
         {"x-scheme-handler/https", "x-scheme-handler/http", "text/html", "application/xhtml+xml"}},
        {"correo", "Correo electrónico", "Enlaces de correo (mailto:)", "✉️",
         {"x-scheme-handler/mailto", "message/rfc822"}},
        {"pdf", "Documentos PDF", ".pdf", "📕", {"application/pdf"}},
        {"texto", "Documentos de texto", ".docx, .doc, .odt, .rtf", "📄",
         {"application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/msword",
          "application/vnd.oasis.opendocument.text", "application/rtf", "text/rtf"}},
        {"hojas", "Hojas de cálculo", ".xlsx, .xls, .ods, .csv", "📊",
         {"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "application/vnd.ms-excel",
          "application/vnd.oasis.opendocument.spreadsheet", "text/csv"}},
        {"presentaciones", "Presentaciones", ".pptx, .ppt, .odp", "📽️",
         {"application/vnd.openxmlformats-officedocument.presentationml.presentation", "application/vnd.ms-powerpoint",
          "application/vnd.oasis.opendocument.presentation"}},
        {"imagenes", "Fotos e imágenes", ".jpg, .png, .webp, .gif…", "🖼️",
         {"image/jpeg", "image/png", "image/webp", "image/gif", "image/bmp", "image/tiff", "image/avif", "image/heif"}},
        {"musica", "Música", ".mp3, .flac, .ogg, .wav…", "🎵",
         {"audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav", "audio/wav", "audio/mp4", "audio/aac", "audio/x-m4a", "audio/opus"}},
        {"video", "Vídeos", ".mp4, .mkv, .webm, .avi…", "🎬",
         {"video/mp4", "video/x-matroska", "video/webm", "video/x-msvideo", "video/quicktime", "video/mpeg"}},
        {"notas", "Archivos de texto sencillo", ".txt", "📝", {"text/plain"}},
    };
    return t;
}

QString predeterminadaDe(const QString &mime)
{
    QProcess xdg;
    xdg.start(QStringLiteral("xdg-mime"), {QStringLiteral("query"), QStringLiteral("default"), mime});
    if (!xdg.waitForFinished(1500))
        return QString();
    return QString::fromUtf8(xdg.readAllStandardOutput()).trimmed().section(QLatin1Char(';'), 0, 0);
}

} // namespace

Predeterminadas::Predeterminadas(QObject *parent) : QObject(parent) {}

void Predeterminadas::recargar()
{
    // Todas las apps visibles con los tipos que dicen abrir
    struct App { QString fichero, nombre; QSet<QString> mimes; };
    QList<App> apps;
    QSet<QString> vistos;
    const QString idioma = QLocale().name().left(2);
    for (const QString &carpeta : titan::dirsAplicaciones()) {
        const QFileInfoList ficheros = QDir(carpeta).entryInfoList({QStringLiteral("*.desktop")}, QDir::Files);
        for (const QFileInfo &fi : ficheros) {
            if (vistos.contains(fi.fileName()))
                continue;
            vistos.insert(fi.fileName());
            const auto d = titan::leerDesktop(fi.absoluteFilePath());
            if (titan::esVerdadero(d.value(QStringLiteral("NoDisplay"))) || titan::esVerdadero(d.value(QStringLiteral("Hidden")))
                || d.value(QStringLiteral("Type")) != QLatin1String("Application"))
                continue;
            const QStringList m = d.value(QStringLiteral("MimeType")).split(QLatin1Char(';'), Qt::SkipEmptyParts);
            if (m.isEmpty())
                continue;
            QString nombre = d.value(QStringLiteral("Name[") + idioma + QLatin1Char(']'));
            if (nombre.isEmpty()) nombre = d.value(QStringLiteral("Name"));
            apps.append({fi.fileName(), nombre, QSet<QString>(m.begin(), m.end())});
        }
    }

    m_tipos.clear();
    for (const Tipo &t : tiposConocidos()) {
        const QString actual = predeterminadaDe(t.mimes.first());
        QVariantList opciones;
        QSet<QString> nombres;
        bool actualEsta = false;
        for (const App &a : std::as_const(apps)) {
            if (!a.mimes.contains(t.mimes.first()) && !(t.mimes.size() > 1 && a.mimes.contains(t.mimes.at(1))))
                continue;
            if (nombres.contains(a.nombre) && a.fichero != actual)
                continue;   // dos .desktop con el mismo nombre: uno basta
            nombres.insert(a.nombre);
            actualEsta = actualEsta || a.fichero == actual;
            opciones.append(QVariantMap{{QStringLiteral("valor"), a.fichero}, {QStringLiteral("texto"), a.nombre}});
        }
        std::sort(opciones.begin(), opciones.end(), [](const QVariant &x, const QVariant &y) {
            return x.toMap().value(QStringLiteral("texto")).toString().localeAwareCompare(y.toMap().value(QStringLiteral("texto")).toString()) < 0;
        });
        if (!actual.isEmpty() && !actualEsta)
            opciones.prepend(QVariantMap{{QStringLiteral("valor"), actual}, {QStringLiteral("texto"), QFileInfo(actual).completeBaseName()}});
        m_tipos.append(QVariantMap{{QStringLiteral("id"), QString::fromUtf8(t.id)},
                                   {QStringLiteral("nombre"), QString::fromUtf8(t.nombre)},
                                   {QStringLiteral("detalle"), QString::fromUtf8(t.detalle)},
                                   {QStringLiteral("simbolo"), QString::fromUtf8(t.simbolo)},
                                   {QStringLiteral("actual"), actual},
                                   {QStringLiteral("opciones"), opciones}});
    }
    emit cambiado();
}

bool Predeterminadas::elegir(const QString &id, const QString &desktop)
{
    // Solo un .desktop que exista de verdad
    if (!desktop.endsWith(QLatin1String(".desktop")) || titan::rutaDesktop(desktop).isEmpty())
        return false;
    const Tipo *tipo = nullptr;
    for (const Tipo &t : tiposConocidos())
        if (QLatin1String(t.id) == id) tipo = &t;
    if (!tipo)
        return false;

    // Reescribe solo esas líneas de [Default Applications]; el resto se queda igual
    const QString ruta = titan::mimeappsPropio();
    QStringList lineas;
    {
        QFile f(ruta);
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&f);
            while (!in.atEnd()) lineas << in.readLine();
        }
    }
    int inicio = -1;
    for (int i = 0; i < lineas.size(); ++i)
        if (lineas.at(i).trimmed() == QLatin1String("[Default Applications]")) { inicio = i; break; }
    if (inicio < 0) {
        if (!lineas.isEmpty() && !lineas.last().trimmed().isEmpty()) lineas << QString();
        lineas << QStringLiteral("[Default Applications]");
        inicio = lineas.size() - 1;
    }
    int fin = inicio + 1;
    while (fin < lineas.size() && !lineas.at(fin).trimmed().startsWith(QLatin1Char('['))) ++fin;
    for (int i = fin - 1; i > inicio; --i) {
        const QString clave = lineas.at(i).section(QLatin1Char('='), 0, 0).trimmed();
        if (tipo->mimes.contains(clave)) { lineas.removeAt(i); --fin; }
    }
    QStringList nuevas;
    for (const QString &m : tipo->mimes) nuevas << m + QLatin1Char('=') + desktop + QLatin1Char(';');
    for (int k = 0; k < nuevas.size(); ++k) lineas.insert(inicio + 1 + k, nuevas.at(k));

    QDir().mkpath(QFileInfo(ruta).absolutePath());
    QSaveFile out(ruta);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;
    out.write(lineas.join(QLatin1Char('\n')).toUtf8() + '\n');
    if (!out.commit())
        return false;
    recargar();
    return true;
}
