// Inti OS - Finder: copiar, mover, arrastrar en grupo, portapapeles y Papelera.
//
// Reglas para MOVER (arrastrar o Cortar + Pegar):
//   - origen y destino tienen que estar dentro de la carpeta personal;
//   - las carpetas principales (Escritorio, Documentos, Descargas…) y las
//     ocultas de configuración (.config, .local…) no se mueven nunca;
//   - una carpeta no puede ir dentro de sí misma.
// Si no se cumple, se COPIA (y se avisa). Soltar en la Papelera = tirar.
// Las copias grandes van en segundo plano: la ventana no se congela.
#include "FinderBackend.h"

#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QDrag>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QGuiApplication>
#include <QMimeData>
#include <QPainter>
#include <QPainterPath>
#include <QPixmap>
#include <QProcess>
#include <QStandardPaths>
#include <QSettings>
#include <QUrl>
#include <QtConcurrent/QtConcurrentRun>

namespace {

QString aLocal(const QString &s)
{
    if (s.startsWith(QStringLiteral("file:")))
        return QUrl(s).toLocalFile();
    return s;
}

QString canon(const QString &p)
{
    const QFileInfo fi(p);
    const QString c = fi.canonicalFilePath();
    return c.isEmpty() ? fi.absoluteFilePath() : c;
}

QString casa()
{
    return canon(QDir::homePath());
}

// "foto.jpg" -> "foto (copia).jpg", "foto (copia 2).jpg"...  o "foto 2.jpg"
QString nombreLibre(const QString &dir, const QFileInfo &src, bool copia)
{
    QString destino = dir + QLatin1Char('/') + src.fileName();
    if (!QFileInfo::exists(destino) && !QFileInfo(destino).isSymLink())
        return destino;
    const bool sinExt = src.isDir() || src.suffix().isEmpty() || src.completeBaseName().isEmpty();
    QString base = sinExt ? src.fileName() : src.completeBaseName();
    if (copia) // "Foto (copia 2)" -> "Foto": no encadenar "(copia) (copia)"
        base.remove(QRegularExpression(QStringLiteral(" \\(copia( \\d+)?\\)$")));
    const QString ext = sinExt ? QString() : QLatin1Char('.') + src.suffix();
    for (int n = 1; n < 10000; ++n) {
        QString nombre;
        if (copia)
            nombre = n == 1 ? QStringLiteral("%1 (copia)%2").arg(base, ext) : QStringLiteral("%1 (copia %2)%3").arg(base).arg(n).arg(ext);
        else
            nombre = QStringLiteral("%1 %2%3").arg(base).arg(n + 1).arg(ext);
        destino = dir + QLatin1Char('/') + nombre;
        if (!QFileInfo::exists(destino) && !QFileInfo(destino).isSymLink())
            return destino;
    }
    return {};
}

bool copiarRec(const QString &src, const QString &dst)
{
    const QFileInfo fi(src);
    if (fi.isSymLink())
        return QFile::link(fi.symLinkTarget(), dst);
    if (fi.isDir()) {
        if (!QDir().mkpath(dst))
            return false;
        QFile::setPermissions(dst, fi.permissions());
        const QStringList hijos = QDir(src).entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
        for (const QString &h : hijos) {
            if (!copiarRec(src + QLatin1Char('/') + h, dst + QLatin1Char('/') + h))
                return false;
        }
        return true;
    }
    return QFile::copy(src, dst);
}

bool borrarRec(const QString &p)
{
    const QFileInfo fi(p);
    if (fi.isDir() && !fi.isSymLink())
        return QDir(p).removeRecursively();
    return QFile::remove(p);
}

// Trabajo: {src, dir, mover, copia}. Corre en otro hilo; devuelve el aviso.
QString ejecutar(const QVariantList &trabajos)
{
    int hechos = 0, fallos = 0;
    bool algunMovido = false, algunCopiado = false;
    QString primerError;
    for (const QVariant &v : trabajos) {
        const QVariantMap t = v.toMap();
        const QString src = t.value(QStringLiteral("src")).toString();
        const QString dir = t.value(QStringLiteral("dir")).toString();
        const bool mover = t.value(QStringLiteral("mover")).toBool();
        const QFileInfo fi(src);
        const QString dst = nombreLibre(dir, fi, !mover && fi.absolutePath() == dir);
        bool ok = false;
        if (dst.isEmpty()) {
            ok = false;
        } else if (mover) {
            ok = QFile::rename(src, dst);
            if (!ok) { // otro disco: copiar y borrar el original
                ok = copiarRec(src, dst);
                if (ok)
                    ok = borrarRec(src);
                else
                    borrarRec(dst);
            }
            algunMovido |= ok;
        } else {
            ok = copiarRec(src, dst);
            if (!ok && QFileInfo::exists(dst))
                borrarRec(dst);
            algunCopiado |= ok;
        }
        if (ok) {
            ++hechos;
        } else {
            ++fallos;
            if (primerError.isEmpty())
                primerError = fi.fileName();
        }
    }
    if (fallos > 0)
        return fallos == 1 && hechos == 0
                   ? QStringLiteral("No se pudo con «%1»").arg(primerError)
                   : QStringLiteral("%1 hechos, %2 no se pudieron (por ejemplo «%3»)").arg(hechos).arg(fallos).arg(primerError);
    const QString que = algunMovido && !algunCopiado ? QStringLiteral("movido") : (algunCopiado && !algunMovido ? QStringLiteral("copiado") : QStringLiteral("listo"));
    if (hechos == 1)
        return que == QLatin1String("movido") ? QStringLiteral("1 elemento movido") : que == QLatin1String("copiado") ? QStringLiteral("1 elemento copiado") : QStringLiteral("Listo");
    return QStringLiteral("%1 elementos %2s").arg(hechos).arg(que);
}

QPixmap iconoDe(const QString &icono)
{
    QPixmap pm;
    if (icono.startsWith(QStringLiteral("qrc:")))
        pm.load(icono.mid(3));
    else if (icono.startsWith(QStringLiteral("file:")))
        pm.load(QUrl(icono).toLocalFile());
    return pm;
}

QString trashInfo(const QString &papelera, const QString &nombre)
{
    return papelera + QStringLiteral("/info/") + nombre + QStringLiteral(".trashinfo");
}

} // namespace

// ---------------------------------------------------------------- reglas

bool FinderBackend::dentroDeCasa(const QString &path) const
{
    const QString h = casa();
    const QString c = canon(aLocal(path));
    return c == h || c.startsWith(h + QLatin1Char('/'));
}

bool FinderBackend::esProtegida(const QString &path) const
{
    const QString c = canon(aLocal(path));
    const QString h = casa();
    if (c == h || c == QStringLiteral("/"))
        return true;
    if (QFileInfo(c).absolutePath() != h)
        return false;
    static const QStringList principales = {
        QStringLiteral("Escritorio"), QStringLiteral("Desktop"), QStringLiteral("Documentos"), QStringLiteral("Documents"),
        QStringLiteral("Descargas"), QStringLiteral("Downloads"), QStringLiteral("Imágenes"), QStringLiteral("Pictures"),
        QStringLiteral("Música"), QStringLiteral("Musica"), QStringLiteral("Music"), QStringLiteral("Vídeos"),
        QStringLiteral("Videos"), QStringLiteral("Plantillas"), QStringLiteral("Templates"), QStringLiteral("Público"),
        QStringLiteral("Public"), QStringLiteral("Proyectos"),
        QStringLiteral(".config"), QStringLiteral(".local"), QStringLiteral(".cache"), QStringLiteral(".ssh"),
        QStringLiteral(".gnupg"), QStringLiteral(".mozilla"),
    };
    return principales.contains(QFileInfo(c).fileName());
}

QString FinderBackend::rutaPapelera() const
{
    return casa() + QStringLiteral("/.local/share/Trash");
}

bool FinderBackend::enPapelera() const
{
    const QString f = rutaPapelera() + QStringLiteral("/files");
    const QString c = canon(m_currentPath);
    return c == f || c.startsWith(f + QLatin1Char('/'));
}

bool FinderBackend::papeleraVacia() const
{
    return QDir(rutaPapelera() + QStringLiteral("/files")).isEmpty(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
}

bool FinderBackend::puedeEscribir() const
{
    return !enPapelera() && QFileInfo(m_currentPath).isWritable();
}

void FinderBackend::ponerAviso(const QString &t)
{
    m_aviso = t;
    emit avisoChanged();
}

void FinderBackend::cerrarAviso()
{
    if (!m_aviso.isEmpty()) {
        m_aviso.clear();
        emit avisoChanged();
    }
}

// ---------------------------------------------------------------- arrastrar y soltar

void FinderBackend::arrastrar(const QStringList &paths0)
{
    QList<QUrl> urls;
    QStringList paths;
    for (const QString &p0 : paths0) {
        const QString p = aLocal(p0);
        if (QFileInfo::exists(p) || QFileInfo(p).isSymLink()) {
            urls << QUrl::fromLocalFile(p);
            paths << p;
        }
    }
    if (urls.isEmpty())
        return;

    auto *mime = new QMimeData;
    mime->setUrls(urls);
    mime->setText(paths.join(QLatin1Char('\n')));
    mime->setData(QStringLiteral("application/x-titan-finder"), QByteArray("1"));

    // Imagen: hasta 3 iconos apilados y el número de elementos.
    const int lado = 64, extra = 10 * (qMin<int>(paths.size(), 3) - 1);
    QPixmap lienzo(lado + extra + 18, lado + extra + 14);
    lienzo.fill(Qt::transparent);
    {
        QPainter pt(&lienzo);
        pt.setRenderHint(QPainter::Antialiasing);
        pt.setRenderHint(QPainter::SmoothPixmapTransform);
        const int n = qMin<int>(paths.size(), 3);
        for (int i = n - 1; i >= 0; --i) {
            QPixmap ic = iconoDe(resolveIcon(QFileInfo(paths.at(i))));
            if (ic.isNull())
                continue;
            ic = ic.scaled(lado, lado, Qt::KeepAspectRatio, Qt::SmoothTransformation);
            pt.setOpacity(i == 0 ? 1.0 : 0.8);
            pt.drawPixmap(i * 10 + (lado - ic.width()) / 2, 14 + i * 10 - 10 * (n - 1) + extra + (lado - ic.height()) / 2, ic);
        }
        pt.setOpacity(1.0);
        if (paths.size() > 1) {
            const QString t = QString::number(paths.size());
            QFont f = pt.font();
            f.setBold(true);
            f.setPixelSize(12);
            pt.setFont(f);
            const int w = qMax(22, QFontMetrics(f).horizontalAdvance(t) + 12);
            const QRect r(lienzo.width() - w, 0, w, 22);
            pt.setPen(Qt::NoPen);
            pt.setBrush(QColor(QStringLiteral("#ff3b30")));
            pt.drawRoundedRect(r, 11, 11);
            pt.setPen(Qt::white);
            pt.drawText(r, Qt::AlignCenter, t);
        }
    }

    auto *drag = new QDrag(this);
    drag->setMimeData(mime);
    drag->setPixmap(lienzo);
    drag->setHotSpot(QPoint(lado / 2, lienzo.height() - lado / 2));
    drag->exec(Qt::CopyAction | Qt::MoveAction, Qt::MoveAction);
    refresh();
}

void FinderBackend::soltar(const QVariantList &urls, const QString &destino0, bool copiar)
{
    if (m_ocupado) {
        ponerAviso(QStringLiteral("Espera a que termine la operación anterior"));
        return;
    }
    const QString destino = canon(aLocal(destino0.isEmpty() ? m_currentPath : destino0));
    const QFileInfo di(destino);
    if (!di.isDir())
        return;

    QStringList fuentes;
    for (const QVariant &u : urls) {
        const QString p = canon(aLocal(u.toString()));
        if (!p.isEmpty() && (QFileInfo::exists(p) || QFileInfo(p).isSymLink()) && !fuentes.contains(p))
            fuentes << p;
    }
    if (fuentes.isEmpty())
        return;

    // Soltar en la Papelera = tirar
    const QString papFiles = rutaPapelera() + QStringLiteral("/files");
    if (destino == papFiles) {
        deleteItems(fuentes);
        return;
    }
    if (!di.isWritable()) {
        ponerAviso(QStringLiteral("No tienes permiso para guardar en «%1»").arg(di.fileName().isEmpty() ? destino : di.fileName()));
        return;
    }
    if (canon(destino).startsWith(papFiles + QLatin1Char('/'))) {
        ponerAviso(QStringLiteral("No se puede guardar dentro de la Papelera"));
        return;
    }

    const bool destinoEnCasa = dentroDeCasa(destino);
    QVariantList trabajos;
    bool degradado = false, dentroDeSiMisma = false;
    int igual = 0;
    for (const QString &src : std::as_const(fuentes)) {
        if (destino == src || destino.startsWith(src + QLatin1Char('/'))) {
            dentroDeSiMisma = true;
            continue;
        }
        bool mover = !copiar;
        if (mover && (!destinoEnCasa || !dentroDeCasa(src) || esProtegida(src))) {
            mover = false;
            degradado = true;
        }
        if (mover && QFileInfo(src).absolutePath() == destino) {
            ++igual; // ya está aquí
            continue;
        }
        trabajos << QVariantMap{{QStringLiteral("src"), src}, {QStringLiteral("dir"), destino}, {QStringLiteral("mover"), mover}};
    }
    if (dentroDeSiMisma && trabajos.isEmpty()) {
        ponerAviso(QStringLiteral("Una carpeta no se puede meter dentro de sí misma"));
        return;
    }
    if (trabajos.isEmpty())
        return;
    lanzar(trabajos, false);
    if (degradado)
        ponerAviso(QStringLiteral("Solo se mueve dentro de tu carpeta personal: lo demás se ha copiado"));
    Q_UNUSED(igual)
}

void FinderBackend::lanzar(const QVariantList &trabajos, bool limpiarPortapapeles)
{
    m_ocupado = true;
    emit ocupadoChanged();
    const int n = trabajos.size();
    ponerAviso(n == 1 ? QStringLiteral("Trabajando…") : QStringLiteral("Trabajando con %1 elementos…").arg(n));
    if (!m_operacion.isRunning()) {
        disconnect(&m_operacion, nullptr, this, nullptr);
        connect(&m_operacion, &QFutureWatcher<QString>::finished, this, [this, limpiarPortapapeles] {
            m_ocupado = false;
            emit ocupadoChanged();
            const QString aviso = m_operacion.result();
            if (limpiarPortapapeles) {
                QGuiApplication::clipboard()->clear();
                m_clipboardPath.clear();
                emit clipboardChanged();
            }
            refresh();
            ponerAviso(aviso);
        });
    }
    m_operacion.setFuture(QtConcurrent::run(ejecutar, trabajos));
}

// ---------------------------------------------------------------- portapapeles

void FinderBackend::cortar(const QStringList &paths)
{
    QList<QUrl> urls;
    QStringList validas;
    for (const QString &p0 : paths) {
        const QString p = aLocal(p0);
        if (!QFileInfo::exists(p))
            continue;
        if (!dentroDeCasa(p) || esProtegida(p)) {
            ponerAviso(QStringLiteral("«%1» no se puede mover: solo se mueve dentro de tu carpeta personal. Usa Copiar.").arg(QFileInfo(p).fileName()));
            return;
        }
        urls << QUrl::fromLocalFile(p);
        validas << p;
    }
    if (urls.isEmpty())
        return;
    auto *mime = new QMimeData;
    mime->setUrls(urls);
    mime->setText(validas.join(QLatin1Char('\n')));
    QByteArray gnome("cut");
    for (const QUrl &u : std::as_const(urls))
        gnome += '\n' + u.toEncoded();
    mime->setData(QStringLiteral("x-special/gnome-copied-files"), gnome);
    mime->setData(QStringLiteral("application/x-kde-cutselection"), QByteArray("1"));
    QGuiApplication::clipboard()->setMimeData(mime);
    m_clipboardPath = validas.first();
    emit clipboardChanged();
    ponerAviso(validas.size() == 1 ? QStringLiteral("Cortado: pégalo donde quieras moverlo")
                                   : QStringLiteral("%1 elementos cortados: pégalos donde quieras moverlos").arg(validas.size()));
}

bool FinderBackend::portapapelesCortado() const
{
    const QMimeData *m = QGuiApplication::clipboard()->mimeData();
    if (!m)
        return false;
    if (m->data(QStringLiteral("application/x-kde-cutselection")) == "1")
        return true;
    return m->data(QStringLiteral("x-special/gnome-copied-files")).startsWith("cut");
}

int FinderBackend::portapapelesCantidad() const
{
    const QMimeData *m = QGuiApplication::clipboard()->mimeData();
    if (!m || !m->hasUrls())
        return 0;
    int n = 0;
    for (const QUrl &u : m->urls())
        if (u.isLocalFile() && QFileInfo::exists(u.toLocalFile()))
            ++n;
    return n;
}

// ---------------------------------------------------------------- Papelera

bool FinderBackend::eliminarDefinitivamente(const QStringList &paths)
{
    const QString pap = rutaPapelera();
    int n = 0;
    for (const QString &p0 : paths) {
        const QString p = canon(aLocal(p0));
        if (esProtegida(p))
            continue;
        if (borrarRec(p)) {
            ++n;
            if (QFileInfo(p).absolutePath() == pap + QStringLiteral("/files"))
                QFile::remove(trashInfo(pap, QFileInfo(p).fileName()));
        }
    }
    refresh();
    ponerAviso(n == 1 ? QStringLiteral("1 elemento eliminado para siempre") : QStringLiteral("%1 elementos eliminados para siempre").arg(n));
    return n == paths.size();
}

bool FinderBackend::vaciarPapelera()
{
    const QString pap = rutaPapelera();
    bool ok = true;
    for (const QString &sub : {QStringLiteral("files"), QStringLiteral("info"), QStringLiteral("expunged")}) {
        QDir d(pap + QLatin1Char('/') + sub);
        const QStringList hijos = d.entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
        for (const QString &h : hijos)
            ok &= borrarRec(d.filePath(h));
    }
    QDir().mkpath(pap + QStringLiteral("/files"));
    QDir().mkpath(pap + QStringLiteral("/info"));
    refresh();
    ponerAviso(ok ? QStringLiteral("Papelera vaciada") : QStringLiteral("Algunos elementos no se pudieron eliminar"));
    return ok;
}

bool FinderBackend::restaurar(const QStringList &paths)
{
    const QString pap = rutaPapelera();
    int n = 0, sinOrigen = 0;
    for (const QString &p0 : paths) {
        const QString p = aLocal(p0);
        const QString nombre = QFileInfo(p).fileName();
        QSettings info(trashInfo(pap, nombre), QSettings::IniFormat);
        QString origen = QUrl::fromPercentEncoding(info.value(QStringLiteral("Trash Info/Path")).toString().toUtf8());
        if (origen.isEmpty()) {
            ++sinOrigen;
            continue;
        }
        if (!origen.startsWith(QLatin1Char('/')))
            origen = QDir::homePath() + QLatin1Char('/') + origen;
        const QFileInfo oi(origen);
        QDir().mkpath(oi.absolutePath());
        QString destino = origen;
        if (QFileInfo::exists(destino)) {
            const QFileInfo tmp(p);
            destino = nombreLibre(oi.absolutePath(), QFileInfo(oi.absolutePath() + QLatin1Char('/') + oi.fileName()), false);
            Q_UNUSED(tmp)
        }
        if (QFile::rename(p, destino) || (copiarRec(p, destino) && borrarRec(p))) {
            QFile::remove(trashInfo(pap, nombre));
            ++n;
        }
    }
    refresh();
    if (sinOrigen > 0 && n == 0)
        ponerAviso(QStringLiteral("No se sabe de dónde venía: arrástralo a otra carpeta"));
    else
        ponerAviso(n == 1 ? QStringLiteral("1 elemento recuperado") : QStringLiteral("%1 elementos recuperados").arg(n));
    return n > 0;
}

// ---------------------------------------------------------------- comprimir / extraer
//
// Como "Comprimir" y "Extraer aquí" de Ubuntu. bsdtar (libarchive, siempre
// está: lo usa pacman) hace el .zip y abre zip, tar.*, 7z e iso; los .rar van
// con unrar y los .7z con 7z si están. bsdtar no escribe fuera de la carpeta
// de destino (quita las rutas absolutas y rechaza las que suben con "..").

namespace {

// Extensión de archivo comprimido, con las dobles (tar.gz) primero.
QString extComprimido(const QString &nombre)
{
    static const QStringList exts = {
        QStringLiteral("tar.gz"), QStringLiteral("tar.xz"), QStringLiteral("tar.zst"), QStringLiteral("tar.bz2"),
        QStringLiteral("tgz"), QStringLiteral("txz"), QStringLiteral("tbz2"), QStringLiteral("tar"),
        QStringLiteral("zip"), QStringLiteral("7z"), QStringLiteral("rar")};
    const QString l = nombre.toLower();
    for (const QString &e : exts)
        if (l.endsWith(QLatin1Char('.') + e) && l.size() > e.size() + 1)
            return e;
    return {};
}

bool correr(const QString &prog, const QStringList &args, const QString &dir = QString())
{
    QProcess p;
    if (!dir.isEmpty())
        p.setWorkingDirectory(dir);
    p.setProcessChannelMode(QProcess::MergedChannels);
    p.start(prog, args);
    if (!p.waitForStarted(5000))
        return false;
    p.closeWriteChannel();
    p.waitForFinished(-1);
    return p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0;
}

} // namespace

bool FinderBackend::esComprimido(const QString &path) const
{
    const QFileInfo fi(aLocal(path));
    return fi.isFile() && !extComprimido(fi.fileName()).isEmpty();
}

void FinderBackend::enFondo(const QString &mensaje, const std::function<QString()> &trabajo)
{
    m_ocupado = true;
    emit ocupadoChanged();
    ponerAviso(mensaje);
    if (!m_operacion.isRunning()) {
        disconnect(&m_operacion, nullptr, this, nullptr);
        connect(&m_operacion, &QFutureWatcher<QString>::finished, this, [this] {
            m_ocupado = false;
            emit ocupadoChanged();
            refresh();
            ponerAviso(m_operacion.result());
        });
    }
    m_operacion.setFuture(QtConcurrent::run(trabajo));
}

void FinderBackend::comprimir(const QStringList &paths0)
{
    if (m_ocupado) {
        ponerAviso(QStringLiteral("Espera a que termine la operación anterior"));
        return;
    }
    QStringList nombres;
    QString dir;
    for (const QString &p0 : paths0) {
        const QFileInfo fi(aLocal(p0));
        if (!fi.exists() && !fi.isSymLink())
            continue;
        if (dir.isEmpty())
            dir = fi.absolutePath();
        if (fi.absolutePath() != dir)
            continue; // la selección siempre es de una misma carpeta
        nombres << fi.fileName();
    }
    if (nombres.isEmpty())
        return;
    if (!QFileInfo(dir).isWritable() || dir.startsWith(rutaPapelera())) {
        ponerAviso(QStringLiteral("No tienes permiso para guardar aquí"));
        return;
    }
    // "Informe.pdf" -> "Informe.zip"; varios -> "Archivo.zip" (como Ubuntu)
    QString base = QStringLiteral("Archivo");
    if (nombres.size() == 1) {
        const QFileInfo fi(dir + QLatin1Char('/') + nombres.first());
        base = fi.isDir() || fi.completeBaseName().isEmpty() ? fi.fileName() : fi.completeBaseName();
    }
    const QString destino = nombreLibre(dir, QFileInfo(dir + QLatin1Char('/') + base + QStringLiteral(".zip")), false);
    if (destino.isEmpty())
        return;
    enFondo(QStringLiteral("Comprimiendo…"), [dir, nombres, destino] {
        // Primero a un nombre oculto: si falla a medias no queda un .zip roto
        const QString tmp = dir + QStringLiteral("/.") + QFileInfo(destino).fileName() + QStringLiteral(".parte");
        QStringList args = {QStringLiteral("--format"), QStringLiteral("zip"), QStringLiteral("-cf"), tmp, QStringLiteral("--")};
        args += nombres;
        if (!correr(QStringLiteral("bsdtar"), args, dir) || !QFile::rename(tmp, destino)) {
            QFile::remove(tmp);
            return QStringLiteral("No se ha podido comprimir");
        }
        return QStringLiteral("Creado «%1»").arg(QFileInfo(destino).fileName());
    });
}

void FinderBackend::extraer(const QString &path0)
{
    if (m_ocupado) {
        ponerAviso(QStringLiteral("Espera a que termine la operación anterior"));
        return;
    }
    const QFileInfo fi(aLocal(path0));
    const QString ext = extComprimido(fi.fileName());
    if (!fi.isFile() || ext.isEmpty())
        return;
    const QString dir = fi.absolutePath();
    if (!QFileInfo(dir).isWritable() || dir.startsWith(rutaPapelera())) {
        ponerAviso(QStringLiteral("No tienes permiso para extraer aquí"));
        return;
    }
    const QString archivo = fi.absoluteFilePath();
    const QString base = fi.fileName().left(fi.fileName().size() - ext.size() - 1);
    enFondo(QStringLiteral("Extrayendo «%1»…").arg(fi.fileName()), [dir, archivo, base, ext] {
        // A una carpeta oculta y luego a su sitio: así un fallo no deja nada
        // a medias a la vista.
        const QString tmp = dir + QStringLiteral("/.extrayendo-") + base;
        QDir(tmp).removeRecursively();
        if (!QDir().mkpath(tmp))
            return QStringLiteral("No se ha podido extraer");
        bool ok;
        if (ext == QStringLiteral("rar") && !QStandardPaths::findExecutable(QStringLiteral("unrar")).isEmpty())
            ok = correr(QStringLiteral("unrar"), {QStringLiteral("x"), QStringLiteral("-o-"), QStringLiteral("-idq"), QStringLiteral("-p-"), archivo, tmp + QLatin1Char('/')});
        else if (ext == QStringLiteral("7z") && !QStandardPaths::findExecutable(QStringLiteral("7z")).isEmpty())
            ok = correr(QStringLiteral("7z"), {QStringLiteral("x"), QStringLiteral("-y"), QStringLiteral("-p"), QStringLiteral("-o") + tmp, archivo});
        else
            ok = correr(QStringLiteral("bsdtar"), {QStringLiteral("-xf"), archivo, QStringLiteral("-C"), tmp});
        const QStringList dentro = QDir(tmp).entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
        if (!ok || dentro.isEmpty()) {
            QDir(tmp).removeRecursively();
            return QStringLiteral("No se ha podido extraer «%1» (¿está dañado o tiene contraseña?)").arg(QFileInfo(archivo).fileName());
        }
        // Si dentro hay una sola cosa, se saca tal cual (sin carpeta de más);
        // si hay varias, van en una carpeta con el nombre del archivo.
        QString final;
        if (dentro.size() == 1) {
            const QFileInfo unico(tmp + QLatin1Char('/') + dentro.first());
            final = nombreLibre(dir, unico, false);
            if (final.isEmpty() || !QFile::rename(unico.absoluteFilePath(), final)) {
                QDir(tmp).removeRecursively();
                return QStringLiteral("No se ha podido extraer");
            }
            QDir(tmp).removeRecursively();
        } else {
            final = nombreLibre(dir, QFileInfo(dir + QLatin1Char('/') + base), false);
            if (final.isEmpty() || !QDir().rename(tmp, final)) {
                QDir(tmp).removeRecursively();
                return QStringLiteral("No se ha podido extraer");
            }
        }
        return QStringLiteral("Extraído en «%1»").arg(QFileInfo(final).fileName());
    });
}
