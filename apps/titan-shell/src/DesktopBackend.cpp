#include "DesktopBackend.h"

#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QFile>
#include <QSettings>
#include <QUrl>
#include <QRegularExpression>
#include <QJsonDocument>
#include <QJsonObject>

static QString resolveDesktopBinary(const QString &program)
{
    if (QFile::exists(program)) return program;
    QString inPath = QStandardPaths::findExecutable(program);
    if (!inPath.isEmpty()) return inPath;

    const QStringList candidates = {
        QStringLiteral("/usr/local/bin/") + program,
        QStringLiteral("/usr/bin/") + program,
        QCoreApplication::applicationDirPath() + QStringLiteral("/../") + program + QStringLiteral("/") + program,
        QCoreApplication::applicationDirPath() + QStringLiteral("/../") + program + QStringLiteral("/build/") + program,
        QDir::currentPath() + QStringLiteral("/apps/") + program + QStringLiteral("/") + program,
        QDir::currentPath() + QStringLiteral("/apps/") + program + QStringLiteral("/build/") + program,
        QDir::currentPath() + QStringLiteral("/iso/titan/airootfs/usr/local/bin/") + program,
        QStringLiteral("/home/isai/Proyectos/titan-linux/apps/") + program + QStringLiteral("/") + program,
        QStringLiteral("/home/isai/Proyectos/titan-linux/iso/titan/airootfs/usr/local/bin/") + program
    };

    for (const QString &c : candidates) {
        if (QFile::exists(c) && QFileInfo(c).isExecutable()) {
            return c;
        }
    }
    return program;
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
    loadPositions();
    loadItems();

    m_watcher->addPath(m_desktopPath);
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &DesktopBackend::refresh);
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

    const qreal cellWidth = 96.0;
    const qreal cellHeight = 102.0;
    const qreal gridTop = 36.0;
    const qreal gridRight = 16.0;
    const int maxRows = 7;

    QSet<QPair<int, int>> occupiedSlots;
    for (auto it = m_positions.begin(); it != m_positions.end(); ++it) {
        QVariantMap pos = it.value().toMap();
        qreal px = pos.value(QStringLiteral("x"), -1.0).toDouble();
        qreal py = pos.value(QStringLiteral("y"), -1.0).toDouble();
        if (px >= 0 && py >= 0) {
            int col = qMax(0, qRound((1920.0 - gridRight - 90.0 - px) / cellWidth));
            int row = qMax(0, qMin(maxRows - 1, qRound((py - gridTop) / cellHeight)));
            occupiedSlots.insert(qMakePair(col, row));
        }
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

    for (const QFileInfo &fi : list) {
        if (fi.fileName().startsWith(QLatin1Char('.'))) continue;

        QVariantMap item;
        QString path = fi.absoluteFilePath();
        item[QStringLiteral("path")] = path;
        item[QStringLiteral("isDir")] = fi.isDir();

        if (fi.suffix().toLower() == QStringLiteral("desktop")) {
            QSettings ini(path, QSettings::IniFormat);
            ini.beginGroup(QStringLiteral("Desktop Entry"));

            QString name = ini.value(QStringLiteral("Name[es]")).toString();
            if (name.isEmpty()) {
                name = ini.value(QStringLiteral("Name")).toString();
            }
            if (name.isEmpty()) {
                name = fi.completeBaseName();
            }

            QString icon = ini.value(QStringLiteral("Icon")).toString();
            QString exec = ini.value(QStringLiteral("Exec")).toString();

            item[QStringLiteral("name")] = name;
            item[QStringLiteral("icon")] = resolveAppIcon(icon, exec);
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

        qreal posX = -1.0;
        qreal posY = -1.0;
        if (m_positions.contains(path)) {
            QVariantMap pos = m_positions[path].toMap();
            posX = pos.value(QStringLiteral("x"), -1.0).toDouble();
            posY = pos.value(QStringLiteral("y"), -1.0).toDouble();
        }

        if (posX < 0 || posY < 0) {
            auto slot = findNextSlot();
            item[QStringLiteral("gridCol")] = slot.first;
            item[QStringLiteral("gridRow")] = slot.second;
            item[QStringLiteral("hasSavedPos")] = false;
        } else {
            item[QStringLiteral("savedX")] = posX;
            item[QStringLiteral("savedY")] = posY;
            item[QStringLiteral("hasSavedPos")] = true;
        }

        m_items.append(item);
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

    // 3. Icono de fallback estilizado macOS
    return QStringLiteral("qrc:/icons/apps-folder.png");
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

void DesktopBackend::openItem(const QString &path)
{
    QFileInfo fi(path);
    if (!fi.exists()) return;

    if (fi.suffix().toLower() == QStringLiteral("desktop")) {
        QSettings ini(path, QSettings::IniFormat);
        ini.beginGroup(QStringLiteral("Desktop Entry"));

        QString type = ini.value(QStringLiteral("Type")).toString();
        QString url = ini.value(QStringLiteral("URL")).toString();
        if (type == QLatin1String("Link") && !url.isEmpty()) {
            QUrl targetUrl(url);
            QString localPath = targetUrl.isLocalFile() ? targetUrl.toLocalFile() : url;
            openItem(localPath);
            return;
        }

        QString exec = ini.value(QStringLiteral("Exec")).toString();
        exec.remove(QRegularExpression(QStringLiteral("%[a-zA-Z]")));
        exec = exec.trimmed();

        bool inTerminal = ini.value(QStringLiteral("Terminal"), false).toBool();
        if (inTerminal) {
            QString term = resolveDesktopBinary(QStringLiteral("titan-terminal"));
            if (QFile::exists(term)) {
                QProcess::startDetached(term, {QStringLiteral("-e"), exec});
                return;
            } else if (QFile::exists(QStringLiteral("/usr/bin/kitty"))) {
                QProcess::startDetached(QStringLiteral("/usr/bin/kitty"), {exec});
                return;
            }
        }

        if (!exec.isEmpty()) {
            QStringList parts = QProcess::splitCommand(exec);
            if (!parts.isEmpty()) {
                QString prog = resolveDesktopBinary(parts.takeFirst());
                QProcess::startDetached(prog, parts);
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

void DesktopBackend::refresh()
{
    loadItems();
}

void DesktopBackend::removeItem(const QString &path)
{
    QFileInfo fi(path);
    if (!fi.exists()) return;

    if (fi.isDir()) {
        QDir dir(path);
        dir.removeRecursively();
    } else {
        QFile::remove(path);
    }

    refresh();
}

void DesktopBackend::moveItem(const QString &path, qreal x, qreal y)
{
    QVariantMap pos;
    pos[QStringLiteral("x")] = x;
    pos[QStringLiteral("y")] = y;
    m_positions[path] = pos;
    savePositions();
    emit positionsChanged();
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
        QJsonObject posObj = it.value().toObject();
        QVariantMap pos;
        pos[QStringLiteral("x")] = posObj.value(QStringLiteral("x")).toDouble(-1.0);
        pos[QStringLiteral("y")] = posObj.value(QStringLiteral("y")).toDouble(-1.0);
        m_positions[it.key()] = pos;
    }
}

void DesktopBackend::savePositions()
{
    QString configDir = QDir::homePath() + QStringLiteral("/.config/titan");
    QDir().mkpath(configDir);

    QString configPath = configDir + QStringLiteral("/desktop_positions.json");

    QJsonObject root;
    for (auto it = m_positions.begin(); it != m_positions.end(); ++it) {
        QVariantMap posMap = it.value().toMap();
        QJsonObject posObj;
        posObj[QStringLiteral("x")] = posMap.value(QStringLiteral("x")).toDouble();
        posObj[QStringLiteral("y")] = posMap.value(QStringLiteral("y")).toDouble();
        root[it.key()] = posObj;
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

