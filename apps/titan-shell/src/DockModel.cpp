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

DockModel::DockModel(WindowTracker *tracker, ShellBackend *backend, QObject *parent)
    : QAbstractListModel(parent)
    , m_tracker(tracker)
    , m_backend(backend)
{
    // Aplicaciones ancladas estilo macOS (Finder, Launchpad, Safari, Fotos, Música, Terminal, Acerca, Papelera)
    QVariantMap finder;
    finder[QStringLiteral("appId")] = QStringLiteral("titan-finder");
    finder[QStringLiteral("name")] = QStringLiteral("Finder");
    finder[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/finder.png");
    finder[QStringLiteral("exec")] = QStringLiteral("titan-finder");
    finder[QStringLiteral("running")] = false;
    finder[QStringLiteral("hasWindow")] = false;
    finder[QStringLiteral("active")] = false;
    m_pinnedApps.append(finder);

    QVariantMap safari;
    safari[QStringLiteral("appId")] = QStringLiteral("firefox");
    safari[QStringLiteral("name")] = QStringLiteral("Safari");
    safari[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/safari.png");
    safari[QStringLiteral("exec")] = QStringLiteral("firefox");
    safari[QStringLiteral("running")] = false;
    safari[QStringLiteral("hasWindow")] = false;
    safari[QStringLiteral("active")] = false;
    m_pinnedApps.append(safari);

    QVariantMap onlyoffice;
    onlyoffice[QStringLiteral("appId")] = QStringLiteral("onlyoffice-desktopeditors");
    onlyoffice[QStringLiteral("name")] = QStringLiteral("ONLYOFFICE");
    onlyoffice[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/onlyoffice.png");
    onlyoffice[QStringLiteral("exec")] = QStringLiteral("onlyoffice-desktopeditors");
    onlyoffice[QStringLiteral("running")] = false;
    onlyoffice[QStringLiteral("hasWindow")] = false;
    onlyoffice[QStringLiteral("active")] = false;
    m_pinnedApps.append(onlyoffice);

    QVariantMap fotos;
    fotos[QStringLiteral("appId")] = QStringLiteral("titan-fotos");
    fotos[QStringLiteral("name")] = QStringLiteral("Fotos");
    fotos[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/pictures.png");
    fotos[QStringLiteral("exec")] = QStringLiteral("titan-fotos");
    fotos[QStringLiteral("running")] = false;
    fotos[QStringLiteral("hasWindow")] = false;
    fotos[QStringLiteral("active")] = false;
    m_pinnedApps.append(fotos);

    QVariantMap musica;
    musica[QStringLiteral("appId")] = QStringLiteral("titan-musica");
    musica[QStringLiteral("name")] = QStringLiteral("Música");
    musica[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/music.png");
    musica[QStringLiteral("exec")] = QStringLiteral("titan-musica");
    musica[QStringLiteral("running")] = false;
    musica[QStringLiteral("hasWindow")] = false;
    musica[QStringLiteral("active")] = false;
    m_pinnedApps.append(musica);

    QVariantMap terminal;
    terminal[QStringLiteral("appId")] = QStringLiteral("titan-terminal");
    terminal[QStringLiteral("name")] = QStringLiteral("Terminal");
    terminal[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/terminal.png");
    terminal[QStringLiteral("exec")] = QStringLiteral("titan-terminal");
    terminal[QStringLiteral("running")] = false;
    terminal[QStringLiteral("hasWindow")] = false;
    terminal[QStringLiteral("active")] = false;
    m_pinnedApps.append(terminal);

    QVariantMap settings;
    settings[QStringLiteral("appId")] = QStringLiteral("titan-settings");
    settings[QStringLiteral("name")] = QStringLiteral("Ajustes del Sistema");
    settings[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/system.png");
    settings[QStringLiteral("exec")] = QStringLiteral("titan-settings");
    settings[QStringLiteral("running")] = false;
    settings[QStringLiteral("hasWindow")] = false;
    settings[QStringLiteral("active")] = false;
    m_pinnedApps.append(settings);

    QVariantMap about;
    about[QStringLiteral("appId")] = QStringLiteral("titan-acerca");
    about[QStringLiteral("name")] = QStringLiteral("Acerca de Titan");
    about[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/about.png");
    about[QStringLiteral("exec")] = QStringLiteral("titan-acerca");
    about[QStringLiteral("running")] = false;
    about[QStringLiteral("hasWindow")] = false;
    about[QStringLiteral("active")] = false;
    m_pinnedApps.append(about);

    QVariantMap trash;
    trash[QStringLiteral("appId")] = QStringLiteral("titan-trash");
    trash[QStringLiteral("name")] = QStringLiteral("Papelera");
    trash[QStringLiteral("icon")] = QStringLiteral("qrc:/icons/trash.png");
    trash[QStringLiteral("exec")] = QStringLiteral("titan-finder ") + QDir::homePath() + QStringLiteral("/.local/share/Trash/files");
    trash[QStringLiteral("running")] = false;
    trash[QStringLiteral("hasWindow")] = false;
    trash[QStringLiteral("active")] = false;
    m_pinnedApps.append(trash);

    m_apps = m_pinnedApps;

    if (m_tracker) {
        connect(m_tracker, &WindowTracker::windowsChanged, this, &DockModel::updateWindowStates);
    }
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
    return roles;
}

static bool isFirefox(const QString &str) {
    const QString s = str.toLower();
    return s.contains("firefox") || s.contains("navigator") || s == "browser" || s.contains("mozilla") || s == "safari";
}

void DockModel::updateWindowStates()
{
    if (!m_tracker) return;

    const QVariantList openWindows = m_tracker->windows();

    beginResetModel();
    m_apps = m_pinnedApps;

    for (int i = 0; i < m_apps.size(); ++i) {
        QString appId = m_apps[i][QStringLiteral("appId")].toString();
        QString exec = m_apps[i][QStringLiteral("exec")].toString();
        bool isRunning = false;
        bool isActive = false;

        for (const auto &wVal : openWindows) {
            QVariantMap w = wVal.toMap();
            QString winAppId = w[QStringLiteral("appId")].toString();
            QString winTitle = w[QStringLiteral("title")].toString();
            if (winAppId.isEmpty()) continue;

            bool matches = false;
            if (isFirefox(appId) || isFirefox(exec)) {
                if (isFirefox(winAppId) || isFirefox(winTitle)) {
                    matches = true;
                }
            } else if (winAppId.contains(appId, Qt::CaseInsensitive) ||
                       appId.contains(winAppId, Qt::CaseInsensitive) ||
                       (!exec.isEmpty() && (winAppId.contains(exec, Qt::CaseInsensitive) || exec.contains(winAppId, Qt::CaseInsensitive)))) {
                matches = true;
            }

            if (matches) {
                isRunning = true;
                if (w[QStringLiteral("active")].toBool()) {
                    isActive = true;
                }
            }
        }

        m_apps[i][QStringLiteral("running")] = isRunning;
        m_apps[i][QStringLiteral("hasWindow")] = isRunning;
        m_apps[i][QStringLiteral("active")] = isActive;
    }

    // Agregar aplicaciones abiertas no ancladas
    for (const auto &wVal : openWindows) {
        QVariantMap w = wVal.toMap();
        QString winAppId = w[QStringLiteral("appId")].toString();
        QString winTitle = w[QStringLiteral("title")].toString();
        if (winAppId.isEmpty()) continue;

        bool yaEnDock = false;
        for (const auto &dockApp : m_apps) {
            QString id = dockApp[QStringLiteral("appId")].toString();
            QString exec = dockApp[QStringLiteral("exec")].toString();

            if (isFirefox(winAppId) || isFirefox(winTitle)) {
                if (isFirefox(id) || isFirefox(exec)) {
                    yaEnDock = true;
                    break;
                }
            }

            if (id.contains(winAppId, Qt::CaseInsensitive) ||
                winAppId.contains(id, Qt::CaseInsensitive) ||
                (!exec.isEmpty() && (exec.contains(winAppId, Qt::CaseInsensitive) || winAppId.contains(exec, Qt::CaseInsensitive)))) {
                yaEnDock = true;
                break;
            }
        }

        if (!yaEnDock) {
            QVariantMap dynamicApp;
            dynamicApp[QStringLiteral("appId")] = winAppId;
            dynamicApp[QStringLiteral("name")] = winTitle.isEmpty() ? winAppId : winTitle;
            QString dynamicIcon = QStringLiteral("qrc:/icons/developer.png");
            if (winAppId.contains(QStringLiteral("term"), Qt::CaseInsensitive)) dynamicIcon = QStringLiteral("qrc:/icons/terminal.png");
            else if (winAppId.contains(QStringLiteral("browser"), Qt::CaseInsensitive) || winAppId.contains(QStringLiteral("firefox"), Qt::CaseInsensitive)) dynamicIcon = QStringLiteral("qrc:/icons/safari.png");
            else if (winAppId.contains(QStringLiteral("code"), Qt::CaseInsensitive)) dynamicIcon = QStringLiteral("qrc:/icons/vscode.png");
            else if (winAppId.contains(QStringLiteral("fm"), Qt::CaseInsensitive) || winAppId.contains(QStringLiteral("file"), Qt::CaseInsensitive)) dynamicIcon = QStringLiteral("qrc:/icons/files.png");
            dynamicApp[QStringLiteral("icon")] = dynamicIcon;
            dynamicApp[QStringLiteral("exec")] = winAppId;
            dynamicApp[QStringLiteral("running")] = true;
            dynamicApp[QStringLiteral("hasWindow")] = true;
            dynamicApp[QStringLiteral("active")] = w[QStringLiteral("active")].toBool();
            m_apps.append(dynamicApp);
        }
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
        bool match = (aId == appId) || (isFirefox(appId) && isFirefox(aId));
        if (match) {
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

    // Si no está corriendo, lanzarla
    for (const auto &app : m_apps) {
        QString aId = app[QStringLiteral("appId")].toString();
        bool match = (aId == appId) || (isFirefox(appId) && isFirefox(aId));
        if (match) {
            QString exec = app[QStringLiteral("exec")].toString();
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

void DockModel::moveItem(int fromIndex, int toIndex)
{
    if (fromIndex < 0 || fromIndex >= m_apps.size() || toIndex < 0 || toIndex >= m_apps.size() || fromIndex == toIndex)
        return;

    beginMoveRows(QModelIndex(), fromIndex, fromIndex, QModelIndex(), toIndex > fromIndex ? toIndex + 1 : toIndex);
    m_apps.move(fromIndex, toIndex);
    endMoveRows();
}
