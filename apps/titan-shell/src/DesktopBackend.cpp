#include "TitanBinary.h"
#include "DesktopBackend.h"
#include "ColaApps.h"
#include "TitanIconoSvg.h"
#include "TitanDesktopEntry.h"
#include "TitanIconoApp.h"

#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QFile>
#include <QSettings>
#include <QSet>
#include <QTimer>
#include <QUrl>
#include <QRegularExpression>
#include <QJsonDocument>
#include <QJsonObject>
#include <QGuiApplication>
#include <QScreen>
#include <QClipboard>
#include <QMimeData>

static QString resolveDesktopBinary(const QString &program)
{
    return titan::resolverBinario(program);
}

DesktopBackend::DesktopBackend(QObject *parent)
    : QObject(parent)
    , m_watcher(new QFileSystemWatcher(this))
{
    m_desktopPath = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    if (m_desktopPath.isEmpty() || !QDir(m_desktopPath).exists()) {
        m_desktopPath = QDir::homePath() + QStringLiteral("/Escritorio");
    }

    QDir().mkpath(m_desktopPath);
    ensureSampleDesktop();
    syncStoreAppsToDesktop();
    loadPositions();
    loadItems();

    m_watcher->addPath(m_desktopPath);

    // Apps de la tienda (Flatpak): se vigila su carpeta; si aún no existe
    // (ninguna app instalada), la carpeta más cercana que sí exista.
    vigilarTienda();

    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this](const QString &path) {
        if (path.contains(QStringLiteral("flatpak"))) {
            vigilarTienda();
            syncStoreAppsToDesktop();
            // Al desinstalar, Flatpak puede quitar la entrada antes que la
            // carpeta de la app: se repasa otra vez un poco después.
            QTimer::singleShot(4000, this, [this]() { syncStoreAppsToDesktop(); refresh(); });
        }
        refresh();
    });
}

static QStringList dirsTienda()
{
    return {QStringLiteral("/var/lib/flatpak/exports/share/applications"),
            QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share/applications")};
}

void DesktopBackend::vigilarTienda()
{
    for (QString d : dirsTienda()) {
        // Sin permiso para crearla (la del sistema es de root): se sube hasta
        // una que exista, y al aparecer la de verdad se vigila esa.
        if (!QDir(d).exists())
            QDir().mkpath(d);
        while (!QDir(d).exists() && d.count(QLatin1Char('/')) > 2)
            d = d.left(d.lastIndexOf(QLatin1Char('/')));
        if (QDir(d).exists() && !m_watcher->directories().contains(d))
            m_watcher->addPath(d);
    }
}

// Las apps instaladas desde la App Store salen en el escritorio (como en
// macOS al bajar una app), y se quitan al desinstalarlas. Lo ya puesto se
// apunta en ~/.config/titan/escritorio-tienda.list: si alguien borra el
// icono a mano, no vuelve a aparecer.
void DesktopBackend::syncStoreAppsToDesktop()
{
    const QString registro = QDir::homePath() + QStringLiteral("/.config/titan/escritorio-tienda.list");
    QSet<QString> puestas;
    const bool primeraVez = !QFile::exists(registro);
    {
        QFile f(registro);
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const auto lineas = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
            for (const QString &l : lineas)
                puestas.insert(l.trimmed());
        }
    }
    const QSet<QString> antes = puestas;

    QSet<QString> instaladas;
    for (const QString &dirRuta : dirsTienda()) {
        const auto entradas = QDir(dirRuta).entryInfoList({QStringLiteral("*.desktop")}, QDir::Files);
        for (const QFileInfo &info : entradas) {
            const QString nombre = info.fileName();
            instaladas.insert(nombre);
            if (puestas.contains(nombre))
                continue;
            puestas.insert(nombre);
            // La primera vez solo se apunta lo que ya había (sus iconos ya se
            // pusieron antes, o los quitó la persona).
            if (primeraVez)
                continue;
            const QString destino = m_desktopPath + QLatin1Char('/') + nombre;
            if (QFile::exists(destino))
                continue;
            const auto ini = titan::leerDesktop(info.absoluteFilePath());
            if (titan::esVerdadero(ini.value(QStringLiteral("NoDisplay"))))
                continue;
            if (ini.value(QStringLiteral("Type"), QStringLiteral("Application")) != QStringLiteral("Application"))
                continue;
            if (QFile::copy(info.absoluteFilePath(), destino)) {
                QFile::setPermissions(destino,
                    QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                    QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                    QFileDevice::ReadOther | QFileDevice::ExeOther);
            }
        }
    }

    // Desinstaladas: fuera del registro y, si el icono del escritorio es de
    // esa app de Flatpak (X-Flatpak=), fuera del escritorio. También limpia
    // los que quedaron de antes de este arreglo.
    const auto enEscritorio = QDir(m_desktopPath).entryInfoList({QStringLiteral("*.desktop")}, QDir::Files);
    for (const QFileInfo &fi : enEscritorio) {
        if (instaladas.contains(fi.fileName()))
            continue;
        const auto ini = titan::leerDesktop(fi.absoluteFilePath());
        const QString app = ini.value(QStringLiteral("X-Flatpak"));
        if (app.isEmpty())
            continue;
        // Solo si de verdad ya no está (ni en el sistema ni en el usuario)
        if (QDir(QStringLiteral("/var/lib/flatpak/app/") + app).exists()
            || QDir(QDir::homePath() + QStringLiteral("/.local/share/flatpak/app/") + app).exists())
            continue;
        QFile::remove(fi.absoluteFilePath());
        m_positions.remove(fi.absoluteFilePath());
    }
    for (auto it = puestas.begin(); it != puestas.end();) {
        if (!instaladas.contains(*it)) it = puestas.erase(it);
        else ++it;
    }

    if (puestas != antes || primeraVez) {
        QDir().mkpath(QFileInfo(registro).absolutePath());
        QFile f(registro);
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
            QStringList l(puestas.begin(), puestas.end());
            l.sort();
            f.write((l.join(QLatin1Char('\n')) + QLatin1Char('\n')).toUtf8());
        }
    }
}

void DesktopBackend::ensureSampleDesktop()
{
    QDir desk(m_desktopPath);

    // 1. Carpeta Planning como en la referencia de macOS
    if (!desk.exists(QStringLiteral("Planning"))) {
        desk.mkdir(QStringLiteral("Planning"));
        QFile sampleNotes(m_desktopPath + QStringLiteral("/Planning/Proyectos 2026.txt"));
        if (sampleNotes.open(QIODevice::WriteOnly | QIODevice::Text)) {
            sampleNotes.write("Plan de desarrollo y diseño TITAN Linux estilo macOS\n");
            sampleNotes.close();
        }
    }

    // 2. Acceso directo a Firefox en el Escritorio
    QString ffShortcut = m_desktopPath + QStringLiteral("/firefox.desktop");
    if (!QFile::exists(ffShortcut)) {
        QFile f(ffShortcut);
        if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
            f.write(
                "[Desktop Entry]\n"
                "Version=1.0\n"
                "Name=Firefox\n"
                "GenericName=Navegador Web\n"
                "Comment=Navega por la red\n"
                "Exec=firefox %u\n"
                "Icon=firefox\n"
                "Terminal=false\n"
                "Type=Application\n"
                "Categories=Network;WebBrowser;\n"
            );
            f.close();
            f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                             QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                             QFileDevice::ReadOther | QFileDevice::ExeOther);
        }
    }

    // 3. Acceso directo a ONLYOFFICE en el Escritorio
    QString ooShortcut = m_desktopPath + QStringLiteral("/onlyoffice-desktopeditors.desktop");
    if (!QFile::exists(ooShortcut)) {
        QFile f(ooShortcut);
        if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
            f.write(
                "[Desktop Entry]\n"
                "Version=1.0\n"
                "Name=ONLYOFFICE\n"
                "GenericName=Suite Ofimática\n"
                "Comment=Editor de documentos, hojas de cálculo y presentaciones\n"
                "Exec=onlyoffice-desktopeditors %U\n"
                "Icon=onlyoffice-desktopeditors\n"
                "Terminal=false\n"
                "Type=Application\n"
                "Categories=Office;WordProcessor;Spreadsheet;Presentation;\n"
            );
            f.close();
            f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                             QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                             QFileDevice::ReadOther | QFileDevice::ExeOther);
        }
    }
}

void DesktopBackend::loadItems()
{
    m_items.clear();
    QDir desk(m_desktopPath);
    const QFileInfoList list = desk.entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries, QDir::DirsFirst | QDir::Name);

    const int maxRows = filasEscritorio();

    // Las posiciones se guardan como casilla (columna desde la derecha, fila),
    // no en píxeles: así el escritorio sale igual con cualquier resolución o
    // escala. Antes se suponía una pantalla de 1920 px y, en un portátil de
    // 1366 o 1536 px, los iconos nuevos quedaban fuera de la pantalla.
    QSet<QPair<int, int>> occupiedSlots;
    for (auto it = m_positions.begin(); it != m_positions.end(); ++it) {
        const QPair<int, int> c = casillaDe(it.value().toMap());
        if (c.first >= 0)
            occupiedSlots.insert(c);
    }

    int nextFreeCol = 0;
    int nextFreeRow = 0;
    auto findNextSlot = [&]() -> QPair<int, int> {
        while (occupiedSlots.contains(qMakePair(nextFreeCol, nextFreeRow))) {
            nextFreeRow++;
            if (nextFreeRow >= maxRows) {
                nextFreeRow = 0;
                nextFreeCol++;
            }
        }
        QPair<int, int> slot = qMakePair(nextFreeCol, nextFreeRow);
        occupiedSlots.insert(slot);
        return slot;
    };

    bool isLive = QDir(QStringLiteral("/run/archiso")).exists();
    bool positionsModified = false;

    // Limpiar de m_positions archivos que ya no existan
    QSet<QString> currentPaths;
    for (const QFileInfo &fi : list) {
        currentPaths.insert(fi.absoluteFilePath());
    }
    QStringList toRemove;
    for (auto it = m_positions.begin(); it != m_positions.end(); ++it) {
        if (!currentPaths.contains(it.key())) {
            toRemove.append(it.key());
        }
    }
    for (const QString &rem : toRemove) {
        m_positions.remove(rem);
        positionsModified = true;
    }

    for (const QFileInfo &fi : list) {
        if (fi.fileName().startsWith(QLatin1Char('.'))) continue;

        // Si ya está instalado en el disco (no es sesión en vivo), el instalador no debe existir en el escritorio
        if (!isLive && (fi.fileName().contains(QStringLiteral("instalar"), Qt::CaseInsensitive) ||
                        fi.fileName().contains(QStringLiteral("calamares"), Qt::CaseInsensitive))) {
            QFile::remove(fi.absoluteFilePath());
            m_positions.remove(fi.absoluteFilePath());
            positionsModified = true;
            continue;
        }

        QVariantMap item;
        QString path = fi.absoluteFilePath();
        item[QStringLiteral("path")] = path;
        item[QStringLiteral("isDir")] = fi.isDir();

        if (fi.suffix().toLower() == QStringLiteral("desktop")) {
            // QSettings no sirve para .desktop: con una coma el valor sale vacío.
            const QHash<QString, QString> ini = titan::leerDesktop(path);

            QString name = ini.value(QStringLiteral("Name[es]"));
            if (name.isEmpty()) name = ini.value(QStringLiteral("Name[es_ES]"));
            if (name.isEmpty()) {
                name = ini.value(QStringLiteral("Name"));
            }
            if (name.isEmpty()) {
                name = fi.completeBaseName();
            }

            QString icon = ini.value(QStringLiteral("Icon"));
            QString exec = ini.value(QStringLiteral("Exec"));

            item[QStringLiteral("name")] = name;
            // El mismo icono que en el lanzador y el Dock (TitanIconoApp.h)
            QString icono = titan::iconoApp(icon, exec);
            if (!titan::iconoExiste(icono))
                icono = titan::iconoGenerado(name, exec + QLatin1Char(' ') + icon + QLatin1Char(' ') +
                                                       ini.value(QStringLiteral("Categories")));
            item[QStringLiteral("icon")] = icono;
            item[QStringLiteral("isApp")] = true;
            item[QStringLiteral("exec")] = exec;
        } else {
            QString iconToUse;
            if (fi.isSymLink()) {
                QFileInfo targetFi(fi.symLinkTarget());
                if (targetFi.exists()) {
                    iconToUse = resolveIcon(targetFi.fileName(), targetFi.isDir());
                } else {
                    iconToUse = resolveIcon(fi.fileName(), fi.isDir());
                }
            } else {
                iconToUse = resolveIcon(fi.fileName(), fi.isDir());
            }

            item[QStringLiteral("name")] = fi.fileName();
            item[QStringLiteral("icon")] = iconToUse;
            item[QStringLiteral("isApp")] = fi.isExecutable();
            item[QStringLiteral("exec")] = fi.isExecutable() ? path : QString();
        }

        QPair<int, int> casilla = m_positions.contains(path) ? casillaDe(m_positions.value(path).toMap()) : qMakePair(-1, -1);
        if (casilla.first < 0) {
            // Siguiente casilla libre, bajando por la columna
            casilla = findNextSlot();
            positionsModified = true;
        }
        QVariantMap pos;
        pos[QStringLiteral("col")] = casilla.first;
        pos[QStringLiteral("row")] = casilla.second;
        if (m_positions.value(path).toMap() != pos) {
            m_positions[path] = pos; // las antiguas (x, y) pasan a casilla
            positionsModified = true;
        }
        item[QStringLiteral("gridCol")] = casilla.first;
        item[QStringLiteral("gridRow")] = casilla.second;
        item[QStringLiteral("hasSavedPos")] = false;

        m_items.append(item);
    }

    if (positionsModified) {
        savePositions();
    }

    emit itemsChanged();
}

QString DesktopBackend::resolveAppIcon(const QString &iconName, const QString &exec) const
{
    QString icon = iconName.trimmed();
    QString ex = exec.trimmed();

    if (icon.startsWith(QStringLiteral("qrc:/"))) {
        return icon;
    }

    if (icon.startsWith(QLatin1Char('/'))) {
        if (QFile::exists(icon)) {
            return QUrl::fromLocalFile(icon).toString();
        }
        int lastSlash = icon.lastIndexOf(QLatin1Char('/'));
        icon = icon.mid(lastSlash + 1);
    }

    QString iconBase = icon;
    if (iconBase.endsWith(QStringLiteral(".png"), Qt::CaseInsensitive) ||
        iconBase.endsWith(QStringLiteral(".svg"), Qt::CaseInsensitive) ||
        iconBase.endsWith(QStringLiteral(".xpm"), Qt::CaseInsensitive)) {
        iconBase.chop(4);
    }

    QString lower = iconBase.toLower();
    QString execLower = ex.toLower();

    // 1. Mapeo específico a iconos macOS incorporados (qrc:/icons/...)
    if (lower.contains(QStringLiteral("onlyoffice")) || lower.contains(QStringLiteral("desktopeditors")) ||
        execLower.contains(QStringLiteral("onlyoffice")) || execLower.contains(QStringLiteral("desktopeditors"))) {
        return QStringLiteral("qrc:/icons/onlyoffice.png");
    }

    if (lower.contains(QStringLiteral("calc")) || execLower.contains(QStringLiteral("calc")) ||
        lower.contains(QStringLiteral("calculator"))) {
        return QStringLiteral("qrc:/icons/calculator.png");
    }

    if (lower.contains(QStringLiteral("calendar")) || execLower.contains(QStringLiteral("calendar"))) {
        return QStringLiteral("qrc:/icons/calendar.png");
    }

    if (lower.contains(QStringLiteral("clock")) || execLower.contains(QStringLiteral("clock"))) {
        return QStringLiteral("qrc:/icons/clock.png");
    }

    if (lower.contains(QStringLiteral("celluloid")) || lower.contains(QStringLiteral("video")) ||
        execLower.contains(QStringLiteral("celluloid")) || execLower.contains(QStringLiteral("video")) ||
        execLower.contains(QStringLiteral("mpv")) || execLower.contains(QStringLiteral("vlc"))) {
        return QStringLiteral("qrc:/icons/video.png");
    }

    if (lower.contains(QStringLiteral("software")) || lower.contains(QStringLiteral("store")) ||
        lower.contains(QStringLiteral("discover")) || execLower.contains(QStringLiteral("software")) ||
        execLower.contains(QStringLiteral("discover")) || lower.contains(QStringLiteral("package"))) {
        return QStringLiteral("qrc:/icons/apps-folder.png");
    }

    if (lower.contains(QStringLiteral("terminal")) || execLower.contains(QStringLiteral("terminal")) ||
        lower.contains(QStringLiteral("kitty")) || execLower.contains(QStringLiteral("kitty")) ||
        lower.contains(QStringLiteral("alacritty")) || execLower.contains(QStringLiteral("alacritty")) ||
        lower.contains(QStringLiteral("foot")) || execLower.contains(QStringLiteral("foot")) ||
        lower.contains(QStringLiteral("console"))) {
        return QStringLiteral("qrc:/icons/terminal.png");
    }

    if (lower.contains(QStringLiteral("firefox")) || lower.contains(QStringLiteral("browser")) ||
        lower.contains(QStringLiteral("navigator")) || lower.contains(QStringLiteral("safari")) ||
        execLower.contains(QStringLiteral("firefox")) || execLower.contains(QStringLiteral("chrome")) ||
        execLower.contains(QStringLiteral("chromium")) || execLower.contains(QStringLiteral("brave"))) {
        return QStringLiteral("qrc:/icons/firefox.png");
    }

    if (lower.contains(QStringLiteral("finder")) || lower.contains(QStringLiteral("pcmanfm")) ||
        lower.contains(QStringLiteral("dolphin")) || lower.contains(QStringLiteral("nautilus")) ||
        execLower.contains(QStringLiteral("finder")) || execLower.contains(QStringLiteral("pcmanfm")) ||
        lower.contains(QStringLiteral("file-manager"))) {
        return QStringLiteral("qrc:/icons/finder.png");
    }

    if (lower.contains(QStringLiteral("photo")) || lower.contains(QStringLiteral("picture")) ||
        lower.contains(QStringLiteral("foto")) || lower.contains(QStringLiteral("loupe")) ||
        lower.contains(QStringLiteral("eog")) || lower.contains(QStringLiteral("gimp")) ||
        execLower.contains(QStringLiteral("foto")) || execLower.contains(QStringLiteral("picture"))) {
        return QStringLiteral("qrc:/icons/pictures.png");
    }

    if (lower.contains(QStringLiteral("music")) || lower.contains(QStringLiteral("musica")) ||
        lower.contains(QStringLiteral("audio")) || lower.contains(QStringLiteral("player")) ||
        lower.contains(QStringLiteral("rhythmbox")) || lower.contains(QStringLiteral("spotify")) ||
        execLower.contains(QStringLiteral("musica")) || execLower.contains(QStringLiteral("music"))) {
        return QStringLiteral("qrc:/icons/music.png");
    }

    if (lower.contains(QStringLiteral("code")) || lower.contains(QStringLiteral("develop")) ||
        lower.contains(QStringLiteral("vim")) || lower.contains(QStringLiteral("neovim")) ||
        execLower.contains(QStringLiteral("code")) || execLower.contains(QStringLiteral("vim"))) {
        return QStringLiteral("qrc:/icons/vscode.png");
    }

    if (lower.contains(QStringLiteral("notes")) || lower.contains(QStringLiteral("kate")) ||
        lower.contains(QStringLiteral("gedit")) || lower.contains(QStringLiteral("mousepad")) ||
        lower.contains(QStringLiteral("text-editor")) || execLower.contains(QStringLiteral("gedit")) ||
        execLower.contains(QStringLiteral("kate"))) {
        return QStringLiteral("qrc:/icons/notes.png");
    }

    if (lower.contains(QStringLiteral("setting")) || lower.contains(QStringLiteral("config")) ||
        lower.contains(QStringLiteral("control")) || lower.contains(QStringLiteral("preference")) ||
        execLower.contains(QStringLiteral("settings"))) {
        return QStringLiteral("qrc:/icons/system.png");
    }

    if (lower.contains(QStringLiteral("about")) || lower.contains(QStringLiteral("info")) ||
        lower.contains(QStringLiteral("acerca"))) {
        return QStringLiteral("qrc:/icons/about.png");
    }

    // 2. Búsqueda profunda en directorios estándar del sistema Linux
    static const QStringList iconSearchPaths = {
        QStringLiteral("/usr/share/icons/hicolor/scalable/apps/"),
        QStringLiteral("/usr/share/icons/hicolor/512x512/apps/"),
        QStringLiteral("/usr/share/icons/hicolor/256x256/apps/"),
        QStringLiteral("/usr/share/icons/hicolor/128x128/apps/"),
        QStringLiteral("/usr/share/icons/hicolor/64x64/apps/"),
        QStringLiteral("/usr/share/icons/hicolor/48x48/apps/"),
        QStringLiteral("/usr/share/icons/hicolor/32x32/apps/"),
        QStringLiteral("/usr/share/icons/Adwaita/scalable/apps/"),
        QStringLiteral("/usr/share/icons/Adwaita/48x48/apps/"),
        QStringLiteral("/usr/share/pixmaps/"),
        QStringLiteral("/usr/share/titan/icons/"),
        QStringLiteral("/var/lib/flatpak/exports/share/icons/hicolor/scalable/apps/"),
        QStringLiteral("/var/lib/flatpak/exports/share/icons/hicolor/128x128/apps/"),
        QDir::homePath() + QStringLiteral("/.local/share/icons/hicolor/scalable/apps/"),
        QDir::homePath() + QStringLiteral("/.local/share/icons/hicolor/128x128/apps/")
    };

    QStringList candidates = { iconBase, iconBase.toLower(), icon };
    if (!ex.isEmpty()) {
        QString exBase = ex.split(QLatin1Char(' ')).first();
        if (exBase.contains(QLatin1Char('/'))) exBase = exBase.mid(exBase.lastIndexOf(QLatin1Char('/')) + 1);
        candidates.append(exBase);
        candidates.append(exBase.toLower());
    }

    for (const QString &cand : candidates) {
        if (cand.isEmpty()) continue;
        for (const QString &p : iconSearchPaths) {
            QString png = p + cand + QStringLiteral(".png");
            if (QFile::exists(png)) return QUrl::fromLocalFile(png).toString();
            QString svg = p + cand + QStringLiteral(".svg");
            if (QFile::exists(svg)) return QUrl::fromLocalFile(svg).toString();
        }
    }

    // 3. Sin icono en el sistema: SVG generado (categoria o iniciales).
    return titan::iconoGenerado(iconBase.isEmpty() ? icon : iconBase, ex + QLatin1Char(' ') + icon);
}

QString DesktopBackend::resolveIcon(const QString &fileName, bool isDir) const
{
    if (isDir) {
        return QStringLiteral("qrc:/icons/folder.png");
    }

    const QString lower = fileName.toLower();

    // 1. Imágenes: mostrar vista previa local directa si existe
    if (lower.endsWith(QStringLiteral(".png")) || lower.endsWith(QStringLiteral(".jpg")) ||
        lower.endsWith(QStringLiteral(".jpeg")) || lower.endsWith(QStringLiteral(".webp")) ||
        lower.endsWith(QStringLiteral(".svg"))) {
        QString fullPath = m_desktopPath + QStringLiteral("/") + fileName;
        if (QFile::exists(fullPath)) {
            return QUrl::fromLocalFile(fullPath).toString();
        }
        return QStringLiteral("qrc:/icons/pictures.png");
    }

    // 2. Audio
    if (lower.endsWith(QStringLiteral(".mp3")) || lower.endsWith(QStringLiteral(".wav")) ||
        lower.endsWith(QStringLiteral(".ogg")) || lower.endsWith(QStringLiteral(".flac")) ||
        lower.endsWith(QStringLiteral(".m4a")) || lower.endsWith(QStringLiteral(".aac"))) {
        return QStringLiteral("qrc:/icons/file-audio.png");
    }

    // 3. Video
    if (lower.endsWith(QStringLiteral(".mp4")) || lower.endsWith(QStringLiteral(".mkv")) ||
        lower.endsWith(QStringLiteral(".webm")) || lower.endsWith(QStringLiteral(".avi")) ||
        lower.endsWith(QStringLiteral(".mov"))) {
        return QStringLiteral("qrc:/icons/file-video.png");
    }

    // 4. Documentos PDF
    if (lower.endsWith(QStringLiteral(".pdf"))) {
        return QStringLiteral("qrc:/icons/file-pdf.png");
    }

    // 5. Documentos Word / Writer
    if (lower.endsWith(QStringLiteral(".doc")) || lower.endsWith(QStringLiteral(".docx")) ||
        lower.endsWith(QStringLiteral(".odt")) || lower.endsWith(QStringLiteral(".rtf"))) {
        return QStringLiteral("qrc:/icons/file-word.png");
    }

    // 6. Hojas de Cálculo Excel / Calc
    if (lower.endsWith(QStringLiteral(".xls")) || lower.endsWith(QStringLiteral(".xlsx")) ||
        lower.endsWith(QStringLiteral(".ods")) || lower.endsWith(QStringLiteral(".csv"))) {
        return QStringLiteral("qrc:/icons/file-excel.png");
    }

    // 7. Presentaciones PowerPoint / Impress
    if (lower.endsWith(QStringLiteral(".ppt")) || lower.endsWith(QStringLiteral(".pptx")) ||
        lower.endsWith(QStringLiteral(".odp"))) {
        return QStringLiteral("qrc:/icons/file-powerpoint.png");
    }

    // 8. Archivos de Código y Scripts
    if (lower.endsWith(QStringLiteral(".sh")) || lower.endsWith(QStringLiteral(".py")) ||
        lower.endsWith(QStringLiteral(".cpp")) || lower.endsWith(QStringLiteral(".h")) ||
        lower.endsWith(QStringLiteral(".rs")) || lower.endsWith(QStringLiteral(".js")) ||
        lower.endsWith(QStringLiteral(".json")) || lower.endsWith(QStringLiteral(".qml")) ||
        lower.endsWith(QStringLiteral(".html")) || lower.endsWith(QStringLiteral(".css"))) {
        return QStringLiteral("qrc:/icons/file-code.png");
    }

    // 9. Archivos Comprimidos
    if (lower.endsWith(QStringLiteral(".zip")) || lower.endsWith(QStringLiteral(".tar")) ||
        lower.endsWith(QStringLiteral(".gz")) || lower.endsWith(QStringLiteral(".xz")) ||
        lower.endsWith(QStringLiteral(".7z")) || lower.endsWith(QStringLiteral(".bz2"))) {
        return QStringLiteral("qrc:/icons/file-archive.png");
    }

    // 10. Texto plano
    if (lower.endsWith(QStringLiteral(".txt")) || lower.endsWith(QStringLiteral(".md")) ||
        lower.endsWith(QStringLiteral(".log")) || lower.endsWith(QStringLiteral(".conf"))) {
        return QStringLiteral("qrc:/icons/file-text.png");
    }

    // 11. Ejecutables / Binarios
    QString fullPath = m_desktopPath + QStringLiteral("/") + fileName;
    QFileInfo fi(fullPath);
    if (fi.isExecutable()) {
        QString appIcon = resolveAppIcon(fileName, fileName);
        if (appIcon != QStringLiteral("qrc:/icons/apps-folder.png")) {
            return appIcon;
        }
        return QStringLiteral("qrc:/icons/file-exec.png");
    }

    return QStringLiteral("qrc:/icons/file-generic.png");
}

void DesktopBackend::openItem(const QString &path, bool enDock)
{
    QFileInfo fi(path);
    if (!fi.exists()) return;

    if (fi.suffix().toLower() == QStringLiteral("desktop")) {
        const QHash<QString, QString> ini = titan::leerDesktop(path);

        QString type = ini.value(QStringLiteral("Type"));
        QString url = ini.value(QStringLiteral("URL"));
        if (type == QLatin1String("Link") && !url.isEmpty()) {
            QUrl targetUrl(url);
            QString localPath = targetUrl.isLocalFile() ? targetUrl.toLocalFile() : url;
            openItem(localPath);
            return;
        }

        QString exec = ini.value(QStringLiteral("Exec"));
        exec.remove(QRegularExpression(QStringLiteral("%[a-zA-Z]")));
        exec = exec.trimmed();

        bool inTerminal = titan::esVerdadero(ini.value(QStringLiteral("Terminal")));
        if (inTerminal) {
            QString term = resolveDesktopBinary(QStringLiteral("titan-terminal"));
            if (QFile::exists(term)) {
                QProcess::startDetached(term, {QStringLiteral("-e"), exec});
                return;
            } else if (QFile::exists(QStringLiteral("/usr/bin/kitty"))) {
                // kitty espera el programa y sus argumentos por separado
                QProcess::startDetached(QStringLiteral("/usr/bin/kitty"), QProcess::splitCommand(exec));
                return;
            }
        }

        if (!exec.isEmpty()) {
            QStringList parts = QProcess::splitCommand(exec);
            if (!parts.isEmpty()) {
                QString prog = resolveDesktopBinary(parts.takeFirst());
                // De una en una, en orden (ColaApps)
                ColaApps::instancia()->lanzar(prog, parts, enDock, ini.value(QStringLiteral("Icon")));
                return;
            }
        }
        return;
    }

    // Resolver destino si es un enlace simbólico para determinar tipo y ruta real
    QString realPath = fi.isSymLink() ? fi.symLinkTarget() : path;
    QFileInfo realFi(realPath.isEmpty() ? path : realPath);

    if (fi.isDir() || realFi.isDir()) {
        QProcess::startDetached(resolveDesktopBinary(QStringLiteral("titan-finder")), {realFi.absoluteFilePath()});
        return;
    }

    const QString ext = realFi.suffix().toLower();

    // Documentos ofimáticos -> ONLYOFFICE DEBE SER EL PREDETERMINADO
    if (ext == QStringLiteral("docx") || ext == QStringLiteral("doc")  ||
        ext == QStringLiteral("xlsx") || ext == QStringLiteral("xls")  ||
        ext == QStringLiteral("pptx") || ext == QStringLiteral("ppt")  ||
        ext == QStringLiteral("odt")  || ext == QStringLiteral("ods")  || ext == QStringLiteral("odp") ||
        ext == QStringLiteral("rtf")  || ext == QStringLiteral("csv")) {
        QString oo = resolveDesktopBinary(QStringLiteral("onlyoffice-desktopeditors"));
        if (!oo.isEmpty() && QFile::exists(oo)) {
            QProcess::startDetached(oo, {realFi.absoluteFilePath()});
            return;
        }
    }

    if (ext == QStringLiteral("png") || ext == QStringLiteral("jpg") || ext == QStringLiteral("jpeg") || ext == QStringLiteral("webp")) {
        QProcess::startDetached(resolveDesktopBinary(QStringLiteral("titan-fotos")), {realFi.absoluteFilePath()});
        return;
    }

    if (ext == QStringLiteral("mp3") || ext == QStringLiteral("wav") || ext == QStringLiteral("ogg") || ext == QStringLiteral("flac")) {
        QProcess::startDetached(resolveDesktopBinary(QStringLiteral("titan-musica")), {realFi.absoluteFilePath()});
        return;
    }

    // Instaladores .deb (Ubuntu) y .rpm (Fedora): titan-paquete
    if ((ext.compare(QStringLiteral("deb"), Qt::CaseInsensitive) == 0 || ext.compare(QStringLiteral("rpm"), Qt::CaseInsensitive) == 0)
        && QFile::exists(resolveDesktopBinary(QStringLiteral("titan-paquete")))) {
        QProcess::startDetached(resolveDesktopBinary(QStringLiteral("titan-paquete")), {realFi.absoluteFilePath()});
        return;
    }

    // Programas de Windows (.exe/.msi): con Wine (titan-exe lo ofrece si falta)
    if ((ext.compare(QStringLiteral("exe"), Qt::CaseInsensitive) == 0 || ext.compare(QStringLiteral("msi"), Qt::CaseInsensitive) == 0)
        && QFile::exists(resolveDesktopBinary(QStringLiteral("titan-exe")))) {
        QProcess::startDetached(resolveDesktopBinary(QStringLiteral("titan-exe")), {realFi.absoluteFilePath()});
        return;
    }

    // AppImage: preguntar e instalar como en Windows (titan-appimage)
    if (ext.compare(QStringLiteral("appimage"), Qt::CaseInsensitive) == 0
        && QFile::exists(resolveDesktopBinary(QStringLiteral("titan-appimage")))) {
        QProcess::startDetached(resolveDesktopBinary(QStringLiteral("titan-appimage")), {realFi.absoluteFilePath()});
        return;
    }

    if (realFi.isExecutable() && (ext == QStringLiteral("sh") || ext == QStringLiteral("bin") || ext.isEmpty())) {
        QProcess::startDetached(realFi.absoluteFilePath(), QStringList());
        return;
    }

    // Default opener
    QProcess::startDetached(QStringLiteral("xdg-open"), {realFi.absoluteFilePath()});
}

void DesktopBackend::openInFinder()
{
    QProcess::startDetached(resolveDesktopBinary(QStringLiteral("titan-finder")), {m_desktopPath});
}

QString DesktopBackend::nuevaCarpeta(qreal x, qreal y)
{
    QDir dir(m_desktopPath);
    QString nombre = QStringLiteral("Nueva carpeta");
    for (int n = 2; dir.exists(nombre) && n < 1000; ++n)
        nombre = QStringLiteral("Nueva carpeta (%1)").arg(n);
    if (!dir.mkdir(nombre))
        return QString();
    const QString ruta = dir.filePath(nombre);
    moveItem(ruta, x, y);
    refresh();
    return ruta;
}

void DesktopBackend::refresh()
{
    loadItems();
}

void DesktopBackend::removeItem(const QString &path)
{
    deleteItems({path});
}

void DesktopBackend::moveItem(const QString &path, qreal x, qreal y)
{
    QVariantMap px;
    px[QStringLiteral("x")] = x;
    px[QStringLiteral("y")] = y;
    const QPair<int, int> c = casillaDe(px);
    moveItemToSlot(path, c.first, c.second);
}

void DesktopBackend::moveItemToSlot(const QString &path, int col, int row)
{
    QVariantMap pos;
    pos[QStringLiteral("col")] = qMax(0, col);
    pos[QStringLiteral("row")] = qMax(0, row);
    m_positions[path] = pos;
    savePositions();
    emit positionsChanged();
}

int DesktopBackend::anchoEscritorio()
{
    QScreen *p = QGuiApplication::primaryScreen();
    return p && p->size().width() > 200 ? p->size().width() : 1920;
}

int DesktopBackend::filasEscritorio()
{
    // Igual que DesktopIcons.qml: (alto - gridTop - 74) / cellHeight
    QScreen *p = QGuiApplication::primaryScreen();
    const int alto = p && p->size().height() > 200 ? p->size().height() : 1080;
    return qMax(1, (alto - 36 - 74) / 102);
}

QPair<int, int> DesktopBackend::casillaDe(const QVariantMap &pos)
{
    if (pos.contains(QStringLiteral("col")))
        return qMakePair(qMax(0, pos.value(QStringLiteral("col")).toInt()), qMax(0, pos.value(QStringLiteral("row")).toInt()));
    const qreal x = pos.value(QStringLiteral("x"), -1.0).toDouble();
    const qreal y = pos.value(QStringLiteral("y"), -1.0).toDouble();
    if (x < 0 || y < 0)
        return qMakePair(-1, -1);
    // Formato antiguo en píxeles. Lo que cae fuera de esta pantalla venía de
    // suponer 1920 px de ancho.
    int ancho = anchoEscritorio();
    if (x > ancho - 96)
        ancho = 1920;
    return qMakePair(qMax(0, qRound((ancho - 16.0 - 90.0 - x) / 96.0)), qMax(0, qRound((y - 36.0) / 102.0)));
}

QVariantMap DesktopBackend::iconPosition(const QString &path)
{
    if (m_positions.contains(path)) {
        return m_positions.value(path).toMap();
    }
    QVariantMap def;
    def[QStringLiteral("x")] = -1.0;
    def[QStringLiteral("y")] = -1.0;
    return def;
}

void DesktopBackend::loadPositions()
{
    QString configPath = QDir::homePath() + QStringLiteral("/.config/titan/desktop_positions.json");
    QFile file(configPath);
    if (!file.open(QIODevice::ReadOnly)) return;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    if (!doc.isObject()) return;

    QJsonObject root = doc.object();
    for (auto it = root.begin(); it != root.end(); ++it) {
        m_positions[it.key()] = it.value().toObject().toVariantMap(); // {col,row} o antiguo {x,y}
    }
}

void DesktopBackend::savePositions()
{
    QString configDir = QDir::homePath() + QStringLiteral("/.config/titan");
    QDir().mkpath(configDir);

    QString configPath = configDir + QStringLiteral("/desktop_positions.json");

    QJsonObject root;
    for (auto it = m_positions.begin(); it != m_positions.end(); ++it) {
        root[it.key()] = QJsonObject::fromVariantMap(it.value().toMap());
    }

    QFile file(configPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) return;
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    file.close();
}

bool DesktopBackend::importFile(const QString &urlOrPath, qreal x, qreal y, bool isMove)
{
    QString localPath = urlOrPath;
    if (localPath.startsWith(QLatin1String("file://"))) {
        localPath = QUrl(urlOrPath).toLocalFile();
    }
    if (localPath.isEmpty() || !QFile::exists(localPath)) return false;

    QFileInfo fi(localPath);
    if (fi.absolutePath() == m_desktopPath) {
        if (x >= 0 && y >= 0) {
            moveItem(localPath, x, y);
        }
        return true;
    }

    QString destName = fi.fileName();
    QString destPath = m_desktopPath + QStringLiteral("/") + destName;
    int counter = 1;
    while (QFile::exists(destPath)) {
        QString base = fi.completeBaseName();
        QString ext = fi.suffix().isEmpty() ? QString() : (QStringLiteral(".") + fi.suffix());
        destPath = m_desktopPath + QStringLiteral("/") + base + QStringLiteral(" (") + QString::number(++counter) + QStringLiteral(")") + ext;
    }

    bool ok = false;
    if (isMove) {
        ok = QFile::rename(localPath, destPath);
        if (!ok) {
            if (fi.isDir()) {
                ok = QFile::link(localPath, destPath);
            } else {
                ok = QFile::copy(localPath, destPath);
                if (ok && fi.isWritable()) {
                    QFile::remove(localPath);
                }
            }
        }
    } else {
        if (fi.isDir()) {
            ok = QFile::link(localPath, destPath);
        } else {
            ok = QFile::copy(localPath, destPath);
            if (!ok) {
                ok = QFile::link(localPath, destPath);
            }
        }
    }

    if (ok) {
        if (x >= 0 && y >= 0) {
            moveItem(destPath, x, y);
        }
        refresh();
    }
    return ok;
}

void DesktopBackend::copyItems(const QStringList &paths)
{
    if (paths.isEmpty()) return;
    QMimeData *mime = new QMimeData();
    QList<QUrl> urls;
    for (const QString &p : paths) {
        if (QFile::exists(p) || QDir(p).exists()) {
            urls.append(QUrl::fromLocalFile(p));
        }
    }
    mime->setUrls(urls);
    mime->setText(paths.join(QLatin1Char('\n')));
    QGuiApplication::clipboard()->setMimeData(mime);
}

void DesktopBackend::deleteItems(const QStringList &paths)
{
    // "Quitar del escritorio": a la Papelera (se puede recuperar). Nunca se
    // borra para siempre desde aquí, ni siquiera si falla la Papelera.
    for (const QString &p : paths) {
        QFileInfo fi(p);
        if (!fi.exists() && !fi.isSymLink()) continue;
        if (QFile::moveToTrash(p))
            m_positions.remove(p);
    }
    savePositions();
    refresh();
}

void DesktopBackend::pasteItems(qreal x, qreal y)
{
    const QMimeData *mime = QGuiApplication::clipboard()->mimeData();
    if (!mime || !mime->hasUrls()) return;

    const QList<QUrl> urls = mime->urls();
    qreal curX = (x >= 0) ? x : 100.0;
    qreal curY = (y >= 0) ? y : 100.0;

    for (int i = 0; i < urls.size(); ++i) {
        QString local = urls[i].toLocalFile();
        if (local.isEmpty() || !QFile::exists(local)) continue;
        importFile(local, curX + (i * 16), curY + (i * 16), false);
    }
}

bool DesktopBackend::hasClipboard() const
{
    const QMimeData *mime = QGuiApplication::clipboard()->mimeData();
    return mime && mime->hasUrls() && !mime->urls().isEmpty();
}

void DesktopBackend::moveItems(const QStringList &paths, const QString &targetDir)
{
    QString destDir = targetDir.isEmpty() ? (QDir::homePath() + QStringLiteral("/Documentos")) : targetDir;
    QDir().mkpath(destDir);

    for (const QString &p : paths) {
        QFileInfo fi(p);
        if (!fi.exists()) continue;
        QString destPath = destDir + QStringLiteral("/") + fi.fileName();
        if (destPath != p) {
            QFile::rename(p, destPath);
            m_positions.remove(p);
        }
    }
    savePositions();
    refresh();
}

