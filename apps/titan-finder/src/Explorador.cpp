// Explorador de archivos: Deshacer (Ctrl+Z), Recientes, Anclar a Acceso
// rápido y búsqueda dentro de las subcarpetas.
#include "FinderBackend.h"

#include <QDateTime>
#include <QFile>
#include <QMimeDatabase>
#include <QSet>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <QXmlStreamReader>
#include <QtConcurrent/QtConcurrentRun>


// ---------------------------------------------------------------- Deshacer

void FinderBackend::apuntarDeshacer(const QString &tipo, const QVariantList &pares, const QString &texto)
{
    if (m_deshaciendo || pares.isEmpty())
        return;
    m_deshacer.append({{QStringLiteral("tipo"), tipo}, {QStringLiteral("pares"), pares}, {QStringLiteral("texto"), texto}});
    while (m_deshacer.size() > 30)
        m_deshacer.removeFirst();
    emit deshacerChanged();
}

QString FinderBackend::textoDeshacer() const
{
    return m_deshacer.isEmpty() ? QString() : m_deshacer.last().value(QStringLiteral("texto")).toString();
}

void FinderBackend::deshacer()
{
    if (m_deshacer.isEmpty()) {
        ponerAviso(QStringLiteral("No hay nada que deshacer"));
        return;
    }
    if (m_ocupado) {
        ponerAviso(QStringLiteral("Espera a que termine la operación anterior"));
        return;
    }
    const QVariantMap op = m_deshacer.takeLast();
    emit deshacerChanged();
    const QString tipo = op.value(QStringLiteral("tipo")).toString();
    const QVariantList pares = op.value(QStringLiteral("pares")).toList();
    m_deshaciendo = true;

    int fallos = 0;
    QVariantList trabajos;          // lo que hay que volver a mover (en otro hilo)
    QStringList restaurarDe;        // lo que hay que sacar de la Papelera
    for (const QVariant &v : pares) {
        const QVariantMap p = v.toMap();
        const QString a = p.value(QStringLiteral("a")).toString();   // como estaba
        const QString b = p.value(QStringLiteral("b")).toString();   // como quedó
        if (tipo == QLatin1String("renombrar")) {
            if (QFileInfo::exists(a) || !QFile::rename(b, a))
                ++fallos;
        } else if (tipo == QLatin1String("papelera")) {
            restaurarDe << b;
        } else if (tipo == QLatin1String("crear")) {
            if (!QFile::moveToTrash(b))
                ++fallos;
        } else if (p.value(QStringLiteral("mover")).toBool()) {
            if (QFileInfo::exists(b) || QFileInfo(b).isSymLink())
                trabajos << QVariantMap{{QStringLiteral("src"), b},
                                        {QStringLiteral("dir"), QFileInfo(a).absolutePath()},
                                        {QStringLiteral("mover"), true}};
            else
                ++fallos;
        } else {
            // Una copia: se quita (a la Papelera, por si acaso)
            if (!QFile::moveToTrash(b))
                ++fallos;
        }
    }

    if (!restaurarDe.isEmpty())
        restaurar(restaurarDe);
    if (!trabajos.isEmpty()) {
        lanzar(trabajos, false);   // apunta según m_deshaciendo al lanzarse
    } else {
        refresh();
        if (restaurarDe.isEmpty())
            ponerAviso(fallos == 0 ? QStringLiteral("Deshecho") : QStringLiteral("No se pudo deshacer del todo"));
    }
    m_deshaciendo = false;
}

// ---------------------------------------------------------------- Anclar

void FinderBackend::anclar(const QString &path)
{
    const QFileInfo fi(path);
    if (!fi.isDir())
        return;
    QSettings ajustes(QStringLiteral("titan"), QStringLiteral("explorador"));
    QStringList l = ajustes.value(QStringLiteral("ancladas")).toStringList();
    if (l.contains(fi.absoluteFilePath()))
        return;
    l << fi.absoluteFilePath();
    ajustes.setValue(QStringLiteral("ancladas"), l);
    initFavorites();
    emit favoritesChanged();
    ponerAviso(QStringLiteral("«%1» anclada a Acceso rápido").arg(fi.fileName()));
}

void FinderBackend::desanclar(const QString &path)
{
    QSettings ajustes(QStringLiteral("titan"), QStringLiteral("explorador"));
    QStringList l = ajustes.value(QStringLiteral("ancladas")).toStringList();
    if (l.removeAll(path) == 0)
        return;
    ajustes.setValue(QStringLiteral("ancladas"), l);
    initFavorites();
    emit favoritesChanged();
}

bool FinderBackend::estaAnclada(const QString &path) const
{
    return QSettings(QStringLiteral("titan"), QStringLiteral("explorador"))
        .value(QStringLiteral("ancladas")).toStringList().contains(path);
}

// ---------------------------------------------------------------- Recientes
//
// ~/.local/share/recently-used.xbel es el estándar de freedesktop: lo
// escriben Firefox, LibreOffice, las apps GTK... y aquí el propio Explorador.

namespace {
QString ficheroRecientes()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/recently-used.xbel");
}
}

void FinderBackend::cargarRecientes()
{
    QFile f(ficheroRecientes());
    if (!f.open(QIODevice::ReadOnly))
        return;
    struct Reciente { QString ruta; qint64 cuando; };
    QList<Reciente> l;
    QXmlStreamReader xml(&f);
    while (!xml.atEnd()) {
        if (xml.readNext() != QXmlStreamReader::StartElement || xml.name() != QLatin1String("bookmark"))
            continue;
        const auto at = xml.attributes();
        const QUrl url(at.value(QLatin1String("href")).toString());
        if (!url.isLocalFile())
            continue;
        QString cuando = at.value(QLatin1String("visited")).toString();
        if (cuando.isEmpty())
            cuando = at.value(QLatin1String("modified")).toString();
        l.append({url.toLocalFile(), QDateTime::fromString(cuando, Qt::ISODateWithMs).toMSecsSinceEpoch()});
    }
    std::sort(l.begin(), l.end(), [](const Reciente &a, const Reciente &b) { return a.cuando > b.cuando; });
    const QString papelera = rutaPapelera();
    QSet<QString> vistos;
    for (const Reciente &r : std::as_const(l)) {
        if (m_rawEntries.size() >= 60)
            break;
        const QFileInfo fi(r.ruta);
        if (vistos.contains(r.ruta) || !fi.exists() || fi.isDir() || r.ruta.startsWith(papelera))
            continue;
        if (!m_showHiddenFiles && fi.isHidden())
            continue;
        vistos.insert(r.ruta);
        QVariantMap e = entradaDe(fi);
        e[QStringLiteral("reciente")] = r.cuando;
        m_rawEntries.append(e);
    }
}

void FinderBackend::apuntarReciente(const QString &path)
{
    const QFileInfo fi(path);
    if (!fi.isFile() || path.startsWith(rutaPapelera()))
        return;
    const QString fichero = ficheroRecientes();
    QFile f(fichero);
    QString xml;
    if (f.open(QIODevice::ReadOnly)) {
        xml = QString::fromUtf8(f.readAll());
        f.close();
    }
    if (!xml.contains(QLatin1String("</xbel>"))) {
        if (!xml.trimmed().isEmpty())
            return; // no es un xbel que entendamos: no se toca
        xml = QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                             "<xbel version=\"1.0\"\n"
                             "      xmlns:bookmark=\"http://www.freedesktop.org/standards/desktop-bookmarks\"\n"
                             "      xmlns:mime=\"http://www.freedesktop.org/standards/shared-mime-info\"\n"
                             ">\n</xbel>\n");
    }
    const QString ahora = QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm:ss.zzz'000Z'"));
    const QString href = QString::fromUtf8(QUrl::fromLocalFile(fi.absoluteFilePath()).toEncoded()).toHtmlEscaped();
    const QString abre = QStringLiteral("<bookmark href=\"%1\"").arg(href);
    const qsizetype i = xml.indexOf(abre);
    if (i >= 0) {
        // Ya estaba: solo se actualiza la fecha de la visita
        const qsizetype fin = xml.indexOf(QLatin1Char('>'), i);
        if (fin < 0)
            return;
        QString etiqueta = xml.mid(i, fin - i);
        etiqueta.replace(QRegularExpression(QStringLiteral("visited=\"[^\"]*\"")), QStringLiteral("visited=\"%1\"").arg(ahora));
        etiqueta.replace(QRegularExpression(QStringLiteral("modified=\"[^\"]*\"")), QStringLiteral("modified=\"%1\"").arg(ahora));
        xml.replace(i, fin - i, etiqueta);
    } else {
        const QString mime = QMimeDatabase().mimeTypeForFile(fi).name().toHtmlEscaped();
        const QString nuevo = QStringLiteral(
            "  <bookmark href=\"%1\" added=\"%2\" modified=\"%2\" visited=\"%2\">\n"
            "    <info>\n"
            "      <metadata owner=\"http://freedesktop.org\">\n"
            "        <mime:mime-type type=\"%3\"/>\n"
            "        <bookmark:applications>\n"
            "          <bookmark:application name=\"Explorador de archivos\" exec=\"&apos;titan-finder %u&apos;\" modified=\"%2\" count=\"1\"/>\n"
            "        </bookmark:applications>\n"
            "      </metadata>\n"
            "    </info>\n"
            "  </bookmark>\n").arg(href, ahora, mime);
        xml.insert(xml.lastIndexOf(QLatin1String("</xbel>")), nuevo);
    }
    QSaveFile out(fichero);
    if (out.open(QIODevice::WriteOnly)) {
        out.write(xml.toUtf8());
        out.commit();
    }
}

// ---------------------------------------------------------------- Búsqueda
//
// Primero se filtra al instante lo de la carpeta abierta; un momento después
// se busca en las subcarpetas en otro hilo (sin congelar la ventana). Se para
// solo si se cambia el texto, a los 300 resultados o tras recorrer mucho.

void FinderBackend::buscarEnSubcarpetas()
{
    const QString texto = sinAcentos(m_searchQuery.trimmed());
    if (texto.size() < 2 || enRecientes() || enPapelera() || !QFileInfo(m_currentPath).isDir())
        return;
    const int generacion = ++m_generacionBusqueda;
    const QString base = m_currentPath;
    const bool ocultos = m_showHiddenFiles;
    const QString papelera = rutaPapelera();

    m_buscando = true;
    emit busquedaChanged();
    disconnect(&m_busqueda, nullptr, this, nullptr);
    connect(&m_busqueda, &QFutureWatcher<QVariantList>::finished, this, [this, generacion] {
        if (generacion != m_generacionBusqueda)
            return; // ya se busca otra cosa
        m_buscando = false;
        emit busquedaChanged();
        m_extraBusqueda.clear();
        for (const QVariant &v : m_busqueda.result()) {
            const QFileInfo fi(v.toString());
            QVariantMap e = entradaDe(fi);
            e[QStringLiteral("dondeEsta")] = QDir(m_currentPath).relativeFilePath(fi.absolutePath());
            m_extraBusqueda.append(e);
        }
        filterAndSortEntries();
    });

    m_busqueda.setFuture(QtConcurrent::run([base, texto, ocultos, papelera, generacion, this]() {
        QVariantList encontrados;
        QStringList pendientes;
        const QDir::Filters extra = ocultos ? QDir::Filters(QDir::Hidden) : QDir::Filters();
        // Las de la carpeta abierta ya se ven: se empieza por sus subcarpetas
        for (const QFileInfo &d : QDir(base).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | extra))
            if (!d.isSymLink())
                pendientes << d.absoluteFilePath();
        int vistos = 0;
        while (!pendientes.isEmpty() && encontrados.size() < 300 && vistos < 150000) {
            if (generacion != m_generacionBusqueda)
                return QVariantList();
            const QString dir = pendientes.takeFirst();
            if (dir.startsWith(papelera))
                continue;
            const QFileInfoList l = QDir(dir).entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot | QDir::System | extra);
            for (const QFileInfo &fi : l) {
                ++vistos;
                if (sinAcentos(fi.fileName()).contains(texto))
                    encontrados << fi.absoluteFilePath();
                if (fi.isDir() && !fi.isSymLink())
                    pendientes << fi.absoluteFilePath();
            }
        }
        return encontrados;
    }));
}
