#include "DockModel.h"
#include "WindowTracker.h"
#include "ShellBackend.h"
#include <QProcess>
#include <QDebug>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTimer>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QUrl>
#include <QSettings>

static QString cleanAppId(const QString &raw)
{
    if (raw.isEmpty()) return QString();
    QString s = raw.trimmed();
    if (s.contains(QLatin1Char('/'))) {
        int idx = s.lastIndexOf(QLatin1Char('/'));
        s = s.mid(idx + 1);
    }
    int spaceIdx = s.indexOf(QLatin1Char(' '));
    if (spaceIdx > 0) {
        s = s.left(spaceIdx);
    }
    if (s.endsWith(QStringLiteral(".desktop"), Qt::CaseInsensitive)) {
        s.chop(8);
    }
    return s.trimmed().toLower();
}

static bool appsMatch(const QString &targetAppId, const QString &targetExec, const QString &candidateAppId, const QString &candidateTitle = QString())
{
    QString tId = cleanAppId(targetAppId);
    QString tEx = cleanAppId(targetExec);
    QString cId = cleanAppId(candidateAppId);
    QString cTitle = candidateTitle.trimmed().toLower();

    // 1. ONLYOFFICE / DesktopEditors
    bool tIsOnlyOffice = tId.contains(QStringLiteral("onlyoffice")) || tEx.contains(QStringLiteral("onlyoffice")) ||
                         tId.contains(QStringLiteral("desktopeditors")) || tEx.contains(QStringLiteral("desktopeditors"));
    bool cIsOnlyOffice = cId.contains(QStringLiteral("onlyoffice")) || cId.contains(QStringLiteral("desktopeditors")) ||
                         cTitle.contains(QStringLiteral("onlyoffice")) || cTitle.contains(QStringLiteral("desktop editors"));
    if (tIsOnlyOffice && cIsOnlyOffice) return true;

    // 2. Firefox / Safari / Navegador Web
    bool tIsBrowser = tId.contains(QStringLiteral("firefox")) || tEx.contains(QStringLiteral("firefox")) ||
                      tId.contains(QStringLiteral("safari")) || tId.contains(QStringLiteral("navigator")) ||
                      tId.contains(QStringLiteral("browser"));
    bool cIsBrowser = cId.contains(QStringLiteral("firefox")) || cId.contains(QStringLiteral("navigator")) ||
                      cId.contains(QStringLiteral("browser")) || cTitle.contains(QStringLiteral("firefox")) ||
                      cTitle.contains(QStringLiteral("mozilla")) || cId == QStringLiteral("safari");
    if (tIsBrowser && cIsBrowser) return true;

    // 3. Terminal (kitty, titan-terminal, alacritty, foot, bash, etc.)
    bool tIsTerm = tId.contains(QStringLiteral("terminal")) || tEx.contains(QStringLiteral("terminal")) ||
                    tId.contains(QStringLiteral("kitty")) || tEx.contains(QStringLiteral("kitty"));
    bool cIsTerm = cId.contains(QStringLiteral("terminal")) || cId.contains(QStringLiteral("kitty")) ||
                    cId.contains(QStringLiteral("foot")) || cId.contains(QStringLiteral("alacritty")) ||
                    cTitle.contains(QStringLiteral("terminal")) || cTitle.contains(QStringLiteral("kitty"));
    if (tIsTerm && cIsTerm) return true;

    // 4. Finder / Gestor de Archivos
    bool tIsFinder = tId.contains(QStringLiteral("finder")) || tEx.contains(QStringLiteral("finder")) ||
                     tId.contains(QStringLiteral("files")) || tId.contains(QStringLiteral("pcmanfm"));
    bool cIsFinder = cId.contains(QStringLiteral("finder")) || cId.contains(QStringLiteral("pcmanfm")) ||
                     cId.contains(QStringLiteral("dolphin")) || cId.contains(QStringLiteral("nautilus")) ||
                     cId.contains(QStringLiteral("files")) || cTitle.contains(QStringLiteral("finder"));
    if (tIsFinder && cIsFinder) return true;

    // 5. Ajustes / Configuración del Sistema
    bool tIsSettings = tId.contains(QStringLiteral("settings")) || tEx.contains(QStringLiteral("settings"));
    bool cIsSettings = cId.contains(QStringLiteral("settings")) || cId.contains(QStringLiteral("systemsettings")) ||
                       cTitle.contains(QStringLiteral("ajustes"));
    if (tIsSettings && cIsSettings) return true;

    // 6. Tienda / App Store
    bool tIsStore = tId.contains(QStringLiteral("software")) || tEx.contains(QStringLiteral("software")) ||
                    tId.contains(QStringLiteral("discover")) || tEx.contains(QStringLiteral("discover"));
    bool cIsStore = cId.contains(QStringLiteral("software")) || cId.contains(QStringLiteral("discover")) ||
                    cTitle.contains(QStringLiteral("software")) || cTitle.contains(QStringLiteral("tienda"));
    if (tIsStore && cIsStore) return true;

    // 7. Fotos
    bool tIsFotos = tId.contains(QStringLiteral("fotos")) || tEx.contains(QStringLiteral("fotos")) ||
                    tId.contains(QStringLiteral("pictures")) || tId.contains(QStringLiteral("loupe")) || tId.contains(QStringLiteral("eog"));
    bool cIsFotos = cId.contains(QStringLiteral("fotos")) || cId.contains(QStringLiteral("pictures")) ||
                    cId.contains(QStringLiteral("loupe")) || cId.contains(QStringLiteral("eog")) || cTitle.contains(QStringLiteral("fotos"));
    if (tIsFotos && cIsFotos) return true;

    // 8. Música
    bool tIsMusica = tId.contains(QStringLiteral("musica")) || tEx.contains(QStringLiteral("musica")) ||
                     tId.contains(QStringLiteral("music")) || tId.contains(QStringLiteral("rhythmbox"));
    bool cIsMusica = cId.contains(QStringLiteral("musica")) || cId.contains(QStringLiteral("music")) ||
                     cId.contains(QStringLiteral("rhythmbox")) || cTitle.contains(QStringLiteral("música"));
    if (tIsMusica && cIsMusica) return true;

    // 9. Calculadora
    bool tIsCalc = tId.contains(QStringLiteral("calc")) || tEx.contains(QStringLiteral("calc"));
    bool cIsCalc = cId.contains(QStringLiteral("calc")) || cTitle.contains(QStringLiteral("calculadora"));
    if (tIsCalc && cIsCalc) return true;

    // 10. Calendario
    bool tIsCal = tId.contains(QStringLiteral("calendar")) || tEx.contains(QStringLiteral("calendar"));
    bool cIsCal = cId.contains(QStringLiteral("calendar")) || cTitle.contains(QStringLiteral("calendario"));
    if (tIsCal && cIsCal) return true;

    // 11. Reloj
    bool tIsClock = tId.contains(QStringLiteral("clock")) || tEx.contains(QStringLiteral("clock"));
    bool cIsClock = cId.contains(QStringLiteral("clock")) || cTitle.contains(QStringLiteral("reloj"));
    if (tIsClock && cIsClock) return true;

    // 12. Video
    bool tIsVideo = tId.contains(QStringLiteral("video")) || tEx.contains(QStringLiteral("video")) ||
                    tId.contains(QStringLiteral("celluloid")) || tId.contains(QStringLiteral("mpv"));
    bool cIsVideo = cId.contains(QStringLiteral("video")) || cId.contains(QStringLiteral("celluloid")) ||
                    cId.contains(QStringLiteral("mpv")) || cTitle.contains(QStringLiteral("video"));
    if (tIsVideo && cIsVideo) return true;

    // 13. Motores de ejecución / intérpretes (Love2D, Python, Wine, Electron, Java)
    static const QStringList runners = {
        QStringLiteral("love"), QStringLiteral("love2d"),
        QStringLiteral("python"), QStringLiteral("python3"),
        QStringLiteral("wine"), QStringLiteral("wine64"),
        QStringLiteral("electron"), QStringLiteral("java")
    };
    if (runners.contains(cId) && !cTitle.isEmpty()) {
        if (!tId.isEmpty() && (cTitle.contains(tId) || tId.contains(cTitle))) return true;
        if (!tEx.isEmpty() && (cTitle.contains(tEx) || tEx.contains(cTitle))) return true;
    }

    // 14. Comparación estándar directa o substring
    if (!tId.isEmpty() && !cId.isEmpty()) {
        if (tId == cId || tId.contains(cId) || cId.contains(tId)) return true;
    }
    if (!tEx.isEmpty() && !cId.isEmpty()) {
        if (tEx == cId || tEx.contains(cId) || cId.contains(tEx)) return true;
    }
    return false;
}

DockModel::DockModel(WindowTracker *tracker, ShellBackend *backend, QObject *parent)
    : QAbstractListModel(parent)
    , m_tracker(tracker)
    , m_backend(backend)
{
    loadPinnedApps();
    m_apps = m_pinnedApps;

    if (m_tracker) {
        connect(m_tracker, &WindowTracker::windowsChanged, this, &DockModel::updateWindowStates);
        connect(m_tracker, &WindowTracker::currentWorkspaceWindowsChanged, this, &DockModel::updateWindowStates);
    }
}

void DockModel::initDefaultPinnedApps()
{
    m_pinnedApps.clear();

    auto addPinned = [this](const QString &appId, const QString &name, const QString &icon, const QString &exec) {
        QVariantMap app;
        app[QStringLiteral("appId")] = appId;
        app[QStringLiteral("name")] = name;
        app[QStringLiteral("icon")] = icon;
        app[QStringLiteral("exec")] = exec;
        app[QStringLiteral("running")] = false;
        app[QStringLiteral("hasWindow")] = false;
        app[QStringLiteral("active")] = false;
        app[QStringLiteral("launching")] = false;
        app[QStringLiteral("isPinned")] = true;
        app[QStringLiteral("showSeparator")] = false;
        m_pinnedApps.append(app);
    };

    addPinned(QStringLiteral("titan-finder"), QStringLiteral("Finder"), QStringLiteral("qrc:/icons/finder.png"), QStringLiteral("titan-finder"));
    addPinned(QStringLiteral("firefox"), QStringLiteral("Firefox"), QStringLiteral("qrc:/icons/firefox.png"), QStringLiteral("firefox"));
    addPinned(QStringLiteral("onlyoffice-desktopeditors"), QStringLiteral("ONLYOFFICE"), QStringLiteral("qrc:/icons/onlyoffice.png"), QStringLiteral("onlyoffice-desktopeditors"));
    addPinned(QStringLiteral("titan-fotos"), QStringLiteral("Fotos"), QStringLiteral("qrc:/icons/pictures.png"), QStringLiteral("titan-fotos"));
    addPinned(QStringLiteral("titan-musica"), QStringLiteral("Música"), QStringLiteral("qrc:/icons/music-app.png"), QStringLiteral("titan-musica"));
    addPinned(QStringLiteral("titan-terminal"), QStringLiteral("Terminal"), QStringLiteral("qrc:/icons/terminal.png"), QStringLiteral("titan-terminal"));
    addPinned(QStringLiteral("titan-settings"), QStringLiteral("Ajustes"), QStringLiteral("qrc:/icons/system.png"), QStringLiteral("titan-settings"));
    addPinned(QStringLiteral("org.gnome.Software"), QStringLiteral("App Store"), QStringLiteral("file:///usr/share/titan/icons/apps-folder.png"), QStringLiteral("gnome-software"));
    addPinned(QStringLiteral("titan-acerca"), QStringLiteral("Acerca de Solaris"), QStringLiteral("qrc:/icons/about.png"), QStringLiteral("titan-acerca"));
    addPinned(QStringLiteral("titan-trash"), QStringLiteral("Papelera"), QStringLiteral("qrc:/icons/trash.png"), QStringLiteral("titan-finder ") + QDir::homePath() + QStringLiteral("/.local/share/Trash/files"));
}

void DockModel::loadPinnedApps()
{
    QString path = QDir::homePath() + QStringLiteral("/.config/titan/dock_pinned.json");
    QFile file(path);
    if (file.exists() && file.open(QIODevice::ReadOnly)) {
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        file.close();
        if (doc.isArray()) {
            m_pinnedApps.clear();
            QJsonArray arr = doc.array();
            for (const auto &val : arr) {
                QJsonObject obj = val.toObject();
                QVariantMap app;
                app[QStringLiteral("appId")] = obj.value(QStringLiteral("appId")).toString();
                app[QStringLiteral("name")] = obj.value(QStringLiteral("name")).toString();
                app[QStringLiteral("icon")] = obj.value(QStringLiteral("icon")).toString();
                app[QStringLiteral("exec")] = obj.value(QStringLiteral("exec")).toString();
                app[QStringLiteral("running")] = false;
                app[QStringLiteral("hasWindow")] = false;
                app[QStringLiteral("active")] = false;
                app[QStringLiteral("launching")] = false;
                app[QStringLiteral("isPinned")] = true;
                app[QStringLiteral("showSeparator")] = false;
                m_pinnedApps.append(app);
            }
            if (!m_pinnedApps.isEmpty()) {
                return;
            }
        }
    }

    initDefaultPinnedApps();
}

void DockModel::savePinnedApps()
{
    QString cfgDir = QDir::homePath() + QStringLiteral("/.config/titan");
    QDir().mkpath(cfgDir);
    QString path = cfgDir + QStringLiteral("/dock_pinned.json");

    QJsonArray arr;
    for (const auto &app : m_pinnedApps) {
        QJsonObject obj;
        obj[QStringLiteral("appId")] = app.value(QStringLiteral("appId")).toString();
        obj[QStringLiteral("name")] = app.value(QStringLiteral("name")).toString();
        obj[QStringLiteral("icon")] = app.value(QStringLiteral("icon")).toString();
        obj[QStringLiteral("exec")] = app.value(QStringLiteral("exec")).toString();
        arr.append(obj);
    }

    QFile file(path);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(arr).toJson(QJsonDocument::Indented));
        file.close();
    }
}

QString DockModel::resolveDynamicIcon(const QString &appId, const QString &title) const
{
    QString cleanId = cleanAppId(appId);
    QString cleanTitle = title.trimmed().toLower();

    // 1. Iconos estándar del sistema Solaris / Titan
    if (cleanId.contains(QStringLiteral("onlyoffice")) || cleanTitle.contains(QStringLiteral("onlyoffice"))) return QStringLiteral("qrc:/icons/onlyoffice.png");
    if (cleanId.contains(QStringLiteral("firefox")) || cleanTitle.contains(QStringLiteral("firefox")) || cleanId.contains(QStringLiteral("safari"))) return QStringLiteral("qrc:/icons/firefox.png");
    if (cleanId.contains(QStringLiteral("terminal")) || cleanId.contains(QStringLiteral("kitty")) || cleanId.contains(QStringLiteral("foot")) || cleanId.contains(QStringLiteral("alacritty"))) return QStringLiteral("qrc:/icons/terminal.png");
    if (cleanId.contains(QStringLiteral("calc")) || cleanTitle.contains(QStringLiteral("calculadora"))) return QStringLiteral("qrc:/icons/calculator.png");
    if (cleanId.contains(QStringLiteral("calendar")) || cleanTitle.contains(QStringLiteral("calendario"))) return QStringLiteral("qrc:/icons/calendar.png");
    if (cleanId.contains(QStringLiteral("clock")) || cleanTitle.contains(QStringLiteral("reloj"))) return QStringLiteral("qrc:/icons/clock.png");
    if (cleanId.contains(QStringLiteral("video")) || cleanId.contains(QStringLiteral("celluloid")) || cleanId.contains(QStringLiteral("mpv")) || cleanId.contains(QStringLiteral("vlc"))) return QStringLiteral("qrc:/icons/video.png");
    if (cleanId.contains(QStringLiteral("software")) || cleanId.contains(QStringLiteral("discover")) || cleanTitle.contains(QStringLiteral("software")) || cleanTitle.contains(QStringLiteral("tienda"))) return QStringLiteral("qrc:/icons/apps-folder.png");
    if (cleanId.contains(QStringLiteral("fotos")) || cleanId.contains(QStringLiteral("picture")) || cleanId.contains(QStringLiteral("loupe"))) return QStringLiteral("qrc:/icons/pictures.png");
    if (cleanId.contains(QStringLiteral("musica")) || cleanId.contains(QStringLiteral("music")) || cleanId.contains(QStringLiteral("rhythmbox"))) return QStringLiteral("qrc:/icons/music-app.png");
    if (cleanId.contains(QStringLiteral("code")) || cleanId.contains(QStringLiteral("develop"))) return QStringLiteral("qrc:/icons/vscode.png");
    if (cleanId.contains(QStringLiteral("finder")) || cleanId.contains(QStringLiteral("files")) || cleanId.contains(QStringLiteral("pcmanfm"))) return QStringLiteral("qrc:/icons/finder.png");
    if (cleanId.contains(QStringLiteral("settings")) || cleanId.contains(QStringLiteral("control")) || cleanTitle.contains(QStringLiteral("ajustes"))) return QStringLiteral("qrc:/icons/system.png");

    // 2. Búsqueda profunda en directorios de iconos del sistema (PNG y SVG)
    static const QStringList genericRunners = {
        QStringLiteral("love"), QStringLiteral("love2d"),
        QStringLiteral("python"), QStringLiteral("python3"),
        QStringLiteral("wine"), QStringLiteral("wine64"),
        QStringLiteral("electron"), QStringLiteral("java"),
        QStringLiteral("gjs"), QStringLiteral("bash"), QStringLiteral("sh")
    };

    static const QStringList iconSearchPaths = {
        QStringLiteral("/usr/share/icons/hicolor/scalable/apps/"),
        QStringLiteral("/usr/share/icons/hicolor/512x512/apps/"),
        QStringLiteral("/usr/share/icons/hicolor/256x256/apps/"),
        QStringLiteral("/usr/share/icons/hicolor/128x128/apps/"),
        QStringLiteral("/usr/share/icons/hicolor/64x64/apps/"),
        QStringLiteral("/usr/share/icons/hicolor/48x48/apps/"),
        QStringLiteral("/usr/share/icons/Adwaita/scalable/apps/"),
        QStringLiteral("/usr/share/icons/Adwaita/48x48/apps/"),
        QStringLiteral("/usr/share/pixmaps/"),
        QStringLiteral("/usr/share/titan/icons/"),
        QStringLiteral("/var/lib/flatpak/exports/share/icons/hicolor/scalable/apps/"),
        QStringLiteral("/var/lib/flatpak/exports/share/icons/hicolor/128x128/apps/"),
        QDir::homePath() + QStringLiteral("/.local/share/icons/hicolor/scalable/apps/"),
        QDir::homePath() + QStringLiteral("/.local/share/icons/hicolor/128x128/apps/")
    };

    QStringList candidates;
    if (!cleanTitle.isEmpty()) {
        candidates.append(cleanTitle);
        if (cleanTitle.contains(QLatin1Char(' '))) {
            candidates.append(cleanTitle.split(QLatin1Char(' ')).first());
        }
    }
    if (!genericRunners.contains(cleanId) && !cleanId.isEmpty()) {
        candidates.append(cleanId);
    }
    if (!genericRunners.contains(appId.toLower()) && !appId.isEmpty() && appId.toLower() != cleanId) {
        candidates.append(appId.toLower());
    }

    for (const QString &c : candidates) {
        if (c.isEmpty()) continue;
        for (const QString &p : iconSearchPaths) {
            QString png = p + c + QStringLiteral(".png");
            if (QFile::exists(png)) return QUrl::fromLocalFile(png).toString();
            QString svg = p + c + QStringLiteral(".svg");
            if (QFile::exists(svg)) return QUrl::fromLocalFile(svg).toString();
        }
    }

    // 3. Buscar en archivos .desktop para obtener su Icon= exacto
    static const QStringList appDirs = {
        QStringLiteral("/usr/share/applications/"),
        QStringLiteral("/usr/local/share/applications/"),
        QStringLiteral("/var/lib/flatpak/exports/share/applications/"),
        QDir::homePath() + QStringLiteral("/.local/share/applications/")
    };
    for (const QString &dir : appDirs) {
        QDir d(dir);
        if (!d.exists()) continue;
        const auto entryList = d.entryInfoList({QStringLiteral("*.desktop")}, QDir::Files);
        for (const auto &fi : entryList) {
            QString base = fi.completeBaseName().toLower();
            bool match = false;
            if (!cleanTitle.isEmpty() && (base == cleanTitle || base.contains(cleanTitle))) {
                match = true;
            } else if (!genericRunners.contains(cleanId) && (base == cleanId || base.contains(cleanId))) {
                match = true;
            }

            if (match) {
                QSettings ini(fi.absoluteFilePath(), QSettings::IniFormat);
                ini.beginGroup(QStringLiteral("Desktop Entry"));
                QString iconVal = ini.value(QStringLiteral("Icon")).toString();
                if (!iconVal.isEmpty()) {
                    if (iconVal.startsWith(QLatin1Char('/')) && QFile::exists(iconVal)) {
                        return QUrl::fromLocalFile(iconVal).toString();
                    }
                    for (const QString &p : iconSearchPaths) {
                        QString png = p + iconVal + QStringLiteral(".png");
                        if (QFile::exists(png)) return QUrl::fromLocalFile(png).toString();
                        QString svg = p + iconVal + QStringLiteral(".svg");
                        if (QFile::exists(svg)) return QUrl::fromLocalFile(svg).toString();
                    }
                }
            }
        }
    }

    // Fallback: icono de aplicación elegante estilo macOS, NUNCA el engranaje de ajustes
    return QStringLiteral("qrc:/icons/apps-folder.png");
}

int DockModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_apps.size();
}

QVariant DockModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_apps.size()) return QVariant();
    
    const QVariantMap &app = m_apps[index.row()];
    
    switch (role) {
    case AppIdRole: return app[QStringLiteral("appId")];
    case NameRole: return app[QStringLiteral("name")];
    case IconRole: return app[QStringLiteral("icon")];
    case ExecRole: return app[QStringLiteral("exec")];
    case RunningRole: return app[QStringLiteral("running")];
    case HasWindowRole: return app[QStringLiteral("hasWindow")];
    case ActiveRole: return app[QStringLiteral("active")];
    case LaunchingRole: return app.value(QStringLiteral("launching"), false);
    case IsPinnedRole: return app.value(QStringLiteral("isPinned"), false);
    case ShowSeparatorRole: return app.value(QStringLiteral("showSeparator"), false);
    case WindowsListRole: return getWindowsForApp(app[QStringLiteral("appId")].toString());
    default: return QVariant();
    }
}

QHash<int, QByteArray> DockModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[AppIdRole] = "appId";
    roles[NameRole] = "name";
    roles[IconRole] = "icon";
    roles[ExecRole] = "exec";
    roles[RunningRole] = "running";
    roles[HasWindowRole] = "hasWindow";
    roles[ActiveRole] = "active";
    roles[LaunchingRole] = "launching";
    roles[IsPinnedRole] = "isPinned";
    roles[ShowSeparatorRole] = "showSeparator";
    roles[WindowsListRole] = "windowsList";
    return roles;
}

void DockModel::updateWindowStates()
{
    if (!m_tracker) return;

    const QVariantList openWindows = m_tracker->currentWorkspaceWindows();

    beginResetModel();
    m_apps = m_pinnedApps;

    // 1. Marcar estado de apps ancladas
    for (int i = 0; i < m_apps.size(); ++i) {
        QString appId = m_apps[i][QStringLiteral("appId")].toString();
        QString exec = m_apps[i][QStringLiteral("exec")].toString();
        m_apps[i][QStringLiteral("isPinned")] = true;
        bool isRunning = false;
        bool isActive = false;

        for (const auto &wVal : openWindows) {
            QVariantMap w = wVal.toMap();
            QString winAppId = w[QStringLiteral("appId")].toString();
            QString winTitle = w[QStringLiteral("title")].toString();
            if (winAppId.isEmpty()) continue;

            if (appsMatch(appId, exec, winAppId, winTitle)) {
                isRunning = true;
                if (w[QStringLiteral("active")].toBool()) {
                    isActive = true;
                }
            }
        }

        m_apps[i][QStringLiteral("running")] = isRunning;
        m_apps[i][QStringLiteral("hasWindow")] = isRunning;
        m_apps[i][QStringLiteral("active")] = isActive;

        bool isLaunchingNow = false;
        for (auto it = m_launchTimers.begin(); it != m_launchTimers.end(); ++it) {
            if (appsMatch(appId, exec, it.key())) {
                if (isRunning) {
                    if (it.value()) {
                        it.value()->stop();
                        it.value()->deleteLater();
                    }
                    m_launchingAppInfo.remove(it.key());
                    it = m_launchTimers.erase(it);
                    if (it == m_launchTimers.end()) break;
                } else {
                    isLaunchingNow = true;
                }
            }
        }

        m_apps[i][QStringLiteral("launching")] = isRunning ? false : isLaunchingNow;
    }

    // 2. Agregar aplicaciones abiertas no ancladas (dinámicas)
    QList<QVariantMap> dynamicApps;
    for (const auto &wVal : openWindows) {
        QVariantMap w = wVal.toMap();
        QString winAppId = w[QStringLiteral("appId")].toString();
        QString winTitle = w[QStringLiteral("title")].toString();
        if (winAppId.isEmpty()) continue;

        bool yaEnDock = false;
        for (const auto &dockApp : m_apps) {
            if (appsMatch(dockApp[QStringLiteral("appId")].toString(), dockApp[QStringLiteral("exec")].toString(), winAppId, winTitle)) {
                yaEnDock = true;
                break;
            }
        }
        for (const auto &dynApp : dynamicApps) {
            if (appsMatch(dynApp[QStringLiteral("appId")].toString(), dynApp[QStringLiteral("exec")].toString(), winAppId, winTitle)) {
                yaEnDock = true;
                break;
            }
        }

        if (!yaEnDock) {
            QString chosenIcon;
            QString chosenName = winTitle.isEmpty() ? winAppId : winTitle;
            QString matchedKey;

            // Reconciliar con cualquier app que se esté abriendo desde el menú de inicio
            for (auto it = m_launchTimers.begin(); it != m_launchTimers.end(); ++it) {
                QString lId = it.key();
                QVariantMap info = m_launchingAppInfo.value(lId);
                QString lName = info.value(QStringLiteral("name")).toString();
                QString lExec = info.value(QStringLiteral("exec")).toString();
                QString lIcon = info.value(QStringLiteral("icon")).toString();

                if (appsMatch(lId, lExec, winAppId, winTitle) ||
                    (!winTitle.isEmpty() && !lName.isEmpty() && (winTitle.contains(lName, Qt::CaseInsensitive) || lName.contains(winTitle, Qt::CaseInsensitive)))) {
                    if (!lIcon.isEmpty() && !lIcon.contains(QStringLiteral("apps-folder.png")) && !lIcon.contains(QStringLiteral("system.png"))) {
                        chosenIcon = lIcon;
                    }
                    if (!lName.isEmpty()) {
                        chosenName = lName;
                    }
                    matchedKey = lId;
                    break;
                }
            }

            if (!matchedKey.isEmpty()) {
                if (m_launchTimers.contains(matchedKey) && m_launchTimers[matchedKey]) {
                    m_launchTimers[matchedKey]->stop();
                    m_launchTimers[matchedKey]->deleteLater();
                    m_launchTimers.remove(matchedKey);
                }
                m_launchingAppInfo.remove(matchedKey);
            } else {
                for (auto it = m_launchTimers.begin(); it != m_launchTimers.end();) {
                    if (it.value()) {
                        it.value()->stop();
                        it.value()->deleteLater();
                    }
                    m_launchingAppInfo.remove(it.key());
                    it = m_launchTimers.erase(it);
                }
            }

            if (chosenIcon.isEmpty()) {
                chosenIcon = resolveDynamicIcon(winAppId, winTitle);
            }

            QVariantMap dynamicApp;
            dynamicApp[QStringLiteral("appId")] = winAppId;
            dynamicApp[QStringLiteral("name")] = chosenName;
            dynamicApp[QStringLiteral("icon")] = chosenIcon;
            dynamicApp[QStringLiteral("exec")] = winAppId;
            dynamicApp[QStringLiteral("running")] = true;
            dynamicApp[QStringLiteral("hasWindow")] = true;
            dynamicApp[QStringLiteral("active")] = w[QStringLiteral("active")].toBool();
            dynamicApp[QStringLiteral("launching")] = false;
            dynamicApp[QStringLiteral("isPinned")] = false;
            dynamicApps.append(dynamicApp);
        }
    }

    // 3. Conservar aplicaciones no ancladas que están abriéndose para que su icono rebote en el Dock
    for (auto it = m_launchTimers.begin(); it != m_launchTimers.end(); ++it) {
        QString launchingId = it.key();
        bool alreadyInApps = false;
        for (const auto &dockApp : m_apps) {
            if (appsMatch(dockApp[QStringLiteral("appId")].toString(), dockApp[QStringLiteral("exec")].toString(), launchingId)) {
                alreadyInApps = true;
                break;
            }
        }
        for (const auto &dynApp : dynamicApps) {
            if (appsMatch(dynApp[QStringLiteral("appId")].toString(), dynApp[QStringLiteral("exec")].toString(), launchingId)) {
                alreadyInApps = true;
                break;
            }
        }
        if (!alreadyInApps && m_launchingAppInfo.contains(launchingId)) {
            QVariantMap lInfo = m_launchingAppInfo[launchingId];
            lInfo[QStringLiteral("isPinned")] = false;
            dynamicApps.append(lInfo);
        }
    }

    // 4. Insertar apps dinámicas antes de titan-trash (para que Papelera siempre esté al final)
    int trashIdx = -1;
    for (int i = 0; i < m_apps.size(); ++i) {
        if (m_apps[i][QStringLiteral("appId")].toString() == QStringLiteral("titan-trash")) {
            trashIdx = i;
            break;
        }
    }
    if (trashIdx >= 0) {
        for (int d = 0; d < dynamicApps.size(); ++d) {
            m_apps.insert(trashIdx + d, dynamicApps[d]);
        }
    } else {
        m_apps.append(dynamicApps);
    }

    // 5. Calcular separadores visuales estilo macOS:
    // - Separador antes de la primera app no anclada.
    // - Separador antes de la Papelera.
    bool firstUnpinnedFound = false;
    for (int i = 0; i < m_apps.size(); ++i) {
        bool isPinned = m_apps[i].value(QStringLiteral("isPinned"), false).toBool();
        QString id = m_apps[i].value(QStringLiteral("appId")).toString();
        bool showSep = false;

        if (!isPinned && !firstUnpinnedFound) {
            showSep = true;
            firstUnpinnedFound = true;
        } else if (id == QStringLiteral("titan-trash")) {
            showSep = true;
        }

        m_apps[i][QStringLiteral("showSeparator")] = showSep;
    }

    endResetModel();
}

static QString resolveBinary(const QString &program)
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

void DockModel::setAppLaunching(const QString &appId, const QString &exec, const QString &name, const QString &icon)
{
    if (appId.isEmpty() && exec.isEmpty()) return;

    QString targetId = cleanAppId(!appId.isEmpty() ? appId : exec);

    int foundIdx = -1;
    for (int i = 0; i < m_apps.size(); ++i) {
        QString curId = m_apps[i][QStringLiteral("appId")].toString();
        QString curExec = m_apps[i][QStringLiteral("exec")].toString();
        if (appsMatch(curId, curExec, appId, name) || (!exec.isEmpty() && appsMatch(curId, curExec, exec, name))) {
            foundIdx = i;
            break;
        }
    }

    if (foundIdx >= 0) {
        m_apps[foundIdx][QStringLiteral("launching")] = true;
        QModelIndex idx = index(foundIdx);
        emit dataChanged(idx, idx, {LaunchingRole});
    } else {
        QVariantMap launchInfo;
        launchInfo[QStringLiteral("appId")] = targetId;
        launchInfo[QStringLiteral("name")] = name.isEmpty() ? targetId : name;
        QString resolvedIcon = icon;
        if (resolvedIcon.isEmpty() || resolvedIcon.contains(QStringLiteral("system.png"))) {
            resolvedIcon = resolveDynamicIcon(targetId, name);
        }
        launchInfo[QStringLiteral("icon")] = resolvedIcon;
        launchInfo[QStringLiteral("exec")] = exec.isEmpty() ? targetId : exec;
        launchInfo[QStringLiteral("running")] = false;
        launchInfo[QStringLiteral("hasWindow")] = false;
        launchInfo[QStringLiteral("active")] = false;
        launchInfo[QStringLiteral("launching")] = true;
        launchInfo[QStringLiteral("isPinned")] = false;
        launchInfo[QStringLiteral("showSeparator")] = true;
        m_launchingAppInfo[targetId] = launchInfo;

        int insertPos = m_apps.size();
        for (int i = 0; i < m_apps.size(); ++i) {
            if (m_apps[i][QStringLiteral("appId")].toString() == QStringLiteral("titan-trash")) {
                insertPos = i;
                break;
            }
        }

        beginInsertRows(QModelIndex(), insertPos, insertPos);
        m_apps.insert(insertPos, launchInfo);
        endInsertRows();
    }

    if (m_launchTimers.contains(targetId)) {
        if (m_launchTimers[targetId]) {
            m_launchTimers[targetId]->stop();
            m_launchTimers[targetId]->deleteLater();
        }
        m_launchTimers.remove(targetId);
    }

    QTimer *timer = new QTimer(this);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, this, [this, targetId]() {
        m_launchTimers.remove(targetId);
        m_launchingAppInfo.remove(targetId);
        for (int i = 0; i < m_apps.size(); ++i) {
            QString curId = m_apps[i][QStringLiteral("appId")].toString();
            QString curExec = m_apps[i][QStringLiteral("exec")].toString();
            if (appsMatch(curId, curExec, targetId)) {
                m_apps[i][QStringLiteral("launching")] = false;
                bool isPinned = m_apps[i].value(QStringLiteral("isPinned"), false).toBool();
                if (!isPinned && !m_apps[i][QStringLiteral("hasWindow")].toBool()) {
                    beginRemoveRows(QModelIndex(), i, i);
                    m_apps.removeAt(i);
                    endRemoveRows();
                } else {
                    QModelIndex idx = index(i);
                    emit dataChanged(idx, idx, {LaunchingRole});
                }
                break;
            }
        }
    });
    m_launchTimers[targetId] = timer;
    timer->start(12000);
}

void DockModel::launchApp(const QString &appId, const QString &exec, const QString &name, const QString &icon)
{
    setAppLaunching(appId, exec, name, icon);

    QString toExec = exec.isEmpty() ? appId : exec;
    if (!toExec.isEmpty()) {
        QStringList parts = toExec.split(' ');
        QString program = parts.takeFirst();
        QString resolved = resolveBinary(program);
        QProcess::startDetached(resolved, parts);
    }
}

void DockModel::activateApp(const QString &appId)
{
    if (appId == QStringLiteral("internal:launchpad")) {
        if (m_backend) {
            m_backend->toggleLauncher();
        }
        return;
    }

    // Si ya tiene ventana abierta, activarla mediante el tracker
    bool hasRunning = false;
    for (const auto &app : m_apps) {
        QString aId = app[QStringLiteral("appId")].toString();
        QString aExec = app[QStringLiteral("exec")].toString();
        if (appsMatch(aId, aExec, appId)) {
            if (app[QStringLiteral("running")].toBool()) {
                hasRunning = true;
            }
            break;
        }
    }

    if (hasRunning && m_tracker) {
        m_tracker->activateWindow(appId);
        return;
    }

    // Si no está corriendo, lanzarla y activar rebote
    for (const auto &app : m_apps) {
        QString aId = app[QStringLiteral("appId")].toString();
        QString aExec = app[QStringLiteral("exec")].toString();
        if (appsMatch(aId, aExec, appId)) {
            QString exec = app[QStringLiteral("exec")].toString();
            QString name = app[QStringLiteral("name")].toString();
            QString icon = app[QStringLiteral("icon")].toString();
            setAppLaunching(aId, exec, name, icon);

            if (!exec.isEmpty()) {
                QStringList parts = exec.split(' ');
                QString program = parts.takeFirst();
                QString resolved = resolveBinary(program);
                QProcess::startDetached(resolved, parts);
            }
            break;
        }
    }
}

void DockModel::pinApp(const QString &appId)
{
    for (const auto &p : m_pinnedApps) {
        if (appsMatch(p[QStringLiteral("appId")].toString(), p[QStringLiteral("exec")].toString(), appId)) {
            return;
        }
    }

    QVariantMap appToPin;
    for (const auto &a : m_apps) {
        if (appsMatch(a[QStringLiteral("appId")].toString(), a[QStringLiteral("exec")].toString(), appId)) {
            appToPin = a;
            break;
        }
    }

    if (appToPin.isEmpty()) {
        appToPin[QStringLiteral("appId")] = appId;
        appToPin[QStringLiteral("name")] = appId;
        appToPin[QStringLiteral("icon")] = resolveDynamicIcon(appId, appId);
        appToPin[QStringLiteral("exec")] = appId;
    }

    appToPin[QStringLiteral("isPinned")] = true;
    appToPin[QStringLiteral("running")] = false;
    appToPin[QStringLiteral("hasWindow")] = false;
    appToPin[QStringLiteral("active")] = false;
    appToPin[QStringLiteral("launching")] = false;

    int insertIdx = m_pinnedApps.size();
    for (int i = 0; i < m_pinnedApps.size(); ++i) {
        if (m_pinnedApps[i][QStringLiteral("appId")].toString() == QStringLiteral("titan-trash")) {
            insertIdx = i;
            break;
        }
    }
    m_pinnedApps.insert(insertIdx, appToPin);
    savePinnedApps();
    updateWindowStates();
}

void DockModel::unpinApp(const QString &appId)
{
    if (appId == QStringLiteral("titan-finder") || appId == QStringLiteral("titan-trash")) {
        return;
    }

    for (int i = 0; i < m_pinnedApps.size(); ++i) {
        if (appsMatch(m_pinnedApps[i][QStringLiteral("appId")].toString(), m_pinnedApps[i][QStringLiteral("exec")].toString(), appId)) {
            m_pinnedApps.removeAt(i);
            break;
        }
    }

    savePinnedApps();
    updateWindowStates();
}

bool DockModel::isAppPinned(const QString &appId) const
{
    for (const auto &p : m_pinnedApps) {
        if (appsMatch(p[QStringLiteral("appId")].toString(), p[QStringLiteral("exec")].toString(), appId)) {
            return true;
        }
    }
    return false;
}

void DockModel::closeApp(const QString &appId)
{
    if (m_tracker) {
        m_tracker->closeWindow(appId);
    }
}

QVariantList DockModel::getWindowsForApp(const QString &appId) const
{
    if (m_tracker) {
        return m_tracker->windowsForApp(appId);
    }
    return QVariantList();
}

void DockModel::activateWindowById(qulonglong windowId)
{
    if (m_tracker) {
        m_tracker->activateWindowById(windowId);
    }
}

void DockModel::moveItem(int fromIndex, int toIndex)
{
    if (fromIndex < 0 || fromIndex >= m_apps.size() || toIndex < 0 || toIndex >= m_apps.size() || fromIndex == toIndex)
        return;

    beginMoveRows(QModelIndex(), fromIndex, fromIndex, QModelIndex(), toIndex > fromIndex ? toIndex + 1 : toIndex);
    m_apps.move(fromIndex, toIndex);
    if (fromIndex >= 0 && fromIndex < m_pinnedApps.size() && toIndex >= 0 && toIndex < m_pinnedApps.size()) {
        m_pinnedApps.move(fromIndex, toIndex);
        savePinnedApps();
    }
    endMoveRows();
}
