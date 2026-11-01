#include "ShellBackend.h"
#include "ThemeManager.h"
#include <QProcess>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTimer>

static QString resolveShellBinary(const QString &program)
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

ShellBackend::ShellBackend(QObject *parent)
    : QObject(parent)
    , m_launcherVisible(false)
    , m_wallpaperPickerVisible(false)
    , m_controlCenterVisible(false)
    , m_splashVisible(false)
    , m_splashTimer(new QTimer(this))
    , m_batteryTimer(new QTimer(this))
{
    m_splashTimer->setSingleShot(true);
    connect(m_splashTimer, &QTimer::timeout, this, &ShellBackend::hideSplash);

    updateBatteryStatus();
    m_batteryTimer->setInterval(4000);
    connect(m_batteryTimer, &QTimer::timeout, this, &ShellBackend::updateBatteryStatus);
    m_batteryTimer->start();

    ThemeManager *tm = ThemeManager::instance();
    connect(tm, &ThemeManager::wallpapersChanged, this, &ShellBackend::wallpapersChanged);
    connect(tm, &ThemeManager::wallpaperChanged, this, &ShellBackend::currentWallpaperChanged);
}

bool ShellBackend::launcherVisible() const
{
    return m_launcherVisible;
}

void ShellBackend::setLauncherVisible(bool visible)
{
    if (m_launcherVisible != visible) {
        m_launcherVisible = visible;
        if (visible && m_wallpaperPickerVisible) {
            setWallpaperPickerVisible(false);
        }
        emit launcherVisibleChanged();
    }
}

bool ShellBackend::wallpaperPickerVisible() const
{
    return m_wallpaperPickerVisible;
}

void ShellBackend::setWallpaperPickerVisible(bool visible)
{
    if (m_wallpaperPickerVisible != visible) {
        m_wallpaperPickerVisible = visible;
        if (visible && m_launcherVisible) {
            setLauncherVisible(false);
        }
        emit wallpaperPickerVisibleChanged();
    }
}

QVariantList ShellBackend::wallpapers() const
{
    return ThemeManager::instance()->availableWallpapers();
}

QString ShellBackend::currentWallpaper() const
{
    return ThemeManager::instance()->wallpaper();
}

void ShellBackend::toggleLauncher()
{
    setLauncherVisible(!m_launcherVisible);
}

void ShellBackend::openLauncher()
{
    setLauncherVisible(true);
}

void ShellBackend::closeLauncher()
{
    setLauncherVisible(false);
}

void ShellBackend::toggleWallpaperPicker()
{
    setWallpaperPickerVisible(!m_wallpaperPickerVisible);
}

void ShellBackend::openWallpaperPicker()
{
    setWallpaperPickerVisible(true);
}

void ShellBackend::closeWallpaperPicker()
{
    setWallpaperPickerVisible(false);
}

void ShellBackend::setWallpaper(const QString &path)
{
    ThemeManager::instance()->setWallpaper(path);
    QProcess::startDetached(QStringLiteral("titan-desktop"), QStringList() << QStringLiteral("--wallpaper") << path);
}

void ShellBackend::toggleTheme()
{
    ThemeManager::instance()->toggleTheme();
}

void ShellBackend::openSettings(const QString &section)
{
    QString bin = resolveShellBinary(QStringLiteral("titan-settings"));
    if (!section.isEmpty()) {
        QProcess::startDetached(bin, {QStringLiteral("--seccion"), section});
    } else {
        QProcess::startDetached(bin);
    }
    setLauncherVisible(false);
    setWallpaperPickerVisible(false);
}

void ShellBackend::setWifiEnabled(bool enabled)
{
    if (m_wifiEnabled != enabled) {
        m_wifiEnabled = enabled;
        if (!m_wifiEnabled) {
            m_wifiConnected = false;
        } else {
            m_wifiConnected = true;
        }
        emit wifiStatusChanged();
    }
}

void ShellBackend::setWifiConnected(bool connected)
{
    if (m_wifiConnected != connected) {
        m_wifiConnected = connected;
        emit wifiStatusChanged();
    }
}

void ShellBackend::toggleWifi()
{
    setWifiEnabled(!m_wifiEnabled);
}

void ShellBackend::setBluetoothEnabled(bool enabled)
{
    if (m_bluetoothEnabled != enabled) {
        m_bluetoothEnabled = enabled;
        if (!m_bluetoothEnabled) {
            m_bluetoothConnected = false;
        }
        emit bluetoothStatusChanged();
    }
}

void ShellBackend::setBluetoothConnected(bool connected)
{
    if (m_bluetoothConnected != connected) {
        m_bluetoothConnected = connected;
        emit bluetoothStatusChanged();
    }
}

void ShellBackend::toggleBluetooth()
{
    setBluetoothEnabled(!m_bluetoothEnabled);
}

void ShellBackend::launchApp(const QString &appId, const QString &exec)
{
    showSplash(appId, appId, exec);
    if (!exec.isEmpty()) {
        QStringList parts = exec.split(' ');
        QString program = parts.takeFirst();
        QString resolved = resolveShellBinary(program);
        QProcess::startDetached(resolved, parts);
    }
    setLauncherVisible(false);
}

void ShellBackend::openAcerca()
{
    showSplash(QStringLiteral("Acerca de Titan"), QStringLiteral("qrc:/icons/about.png"), QStringLiteral("titan-acerca"));
    QProcess::startDetached(resolveShellBinary(QStringLiteral("titan-acerca")));
}

void ShellBackend::openTerminal()
{
    showSplash(QStringLiteral("Terminal"), QStringLiteral("qrc:/icons/terminal.png"), QStringLiteral("titan-terminal"));
    QProcess::startDetached(resolveShellBinary(QStringLiteral("titan-terminal")));
}

void ShellBackend::openFinder()
{
    showSplash(QStringLiteral("Finder"), QStringLiteral("qrc:/icons/finder.png"), QStringLiteral("titan-finder"));
    QProcess::startDetached(resolveShellBinary(QStringLiteral("titan-finder")));
}

void ShellBackend::reboot()
{
    QProcess::startDetached(QStringLiteral("systemctl"), QStringList() << QStringLiteral("reboot"));
}

void ShellBackend::powerOff()
{
    QProcess::startDetached(QStringLiteral("systemctl"), QStringList() << QStringLiteral("poweroff"));
}

bool ShellBackend::controlCenterVisible() const
{
    return m_controlCenterVisible;
}

void ShellBackend::setControlCenterVisible(bool visible)
{
    if (m_controlCenterVisible != visible) {
        m_controlCenterVisible = visible;
        emit controlCenterVisibleChanged();
    }
}

void ShellBackend::toggleControlCenter()
{
    setControlCenterVisible(!m_controlCenterVisible);
}

void ShellBackend::openControlCenter()
{
    setControlCenterVisible(true);
}

void ShellBackend::closeControlCenter()
{
    setControlCenterVisible(false);
}

bool ShellBackend::splashVisible() const
{
    return m_splashVisible;
}

QString ShellBackend::splashName() const
{
    return m_splashName;
}

QString ShellBackend::splashIcon() const
{
    return m_splashIcon;
}

void ShellBackend::showSplash(const QString &name, const QString &icon, const QString &exec)
{
    m_splashName = name;
    m_splashIcon = icon;
    emit splashChanged();

    QString norm = (name + " " + exec + " " + icon).toLower();
    int w = 800;
    int h = 520;
    if (norm.contains("terminal")) {
        w = 800; h = 500;
    } else if (norm.contains("finder") || norm.contains("archivo") || norm.contains("file")) {
        w = 960; h = 620;
    } else if (norm.contains("foto") || norm.contains("picture")) {
        w = 980; h = 640;
    } else if (norm.contains("musica") || norm.contains("music")) {
        w = 960; h = 600;
    } else if (norm.contains("setting") || norm.contains("ajuste") || norm.contains("preferenc")) {
        w = 920; h = 600;
    } else if (norm.contains("acerca") || norm.contains("about")) {
        w = 560; h = 520;
    } else if (norm.contains("onlyoffice") || norm.contains("office")) {
        w = 1024; h = 700;
    } else if (norm.contains("firefox") || norm.contains("safari") || norm.contains("browser") || norm.contains("navegador")) {
        w = 1024; h = 680;
    }

    if (m_splashWidth != w || m_splashHeight != h) {
        m_splashWidth = w;
        m_splashHeight = h;
        emit splashSizeChanged();
    }

    m_splashVisible = true;
    emit splashVisibleChanged();

    // El splash se oculta automáticamente tras 1.4 segundos
    m_splashTimer->start(1400);
}

void ShellBackend::hideSplash()
{
    if (m_splashVisible) {
        m_splashVisible = false;
        emit splashVisibleChanged();
    }
}

int ShellBackend::batteryPercent() const
{
    return m_batteryPercent;
}

bool ShellBackend::isCharging() const
{
    return m_isCharging;
}

bool ShellBackend::hasBattery() const
{
    return m_hasBattery;
}

bool ShellBackend::lowBatteryAlert() const
{
    return m_lowBatteryAlert;
}

void ShellBackend::dismissBatteryAlert()
{
    m_batteryAlertDismissed = true;
    if (m_lowBatteryAlert) {
        m_lowBatteryAlert = false;
        emit batteryChanged();
    }
}

void ShellBackend::updateBatteryStatus()
{
    QDir powerDir(QStringLiteral("/sys/class/power_supply"));
    if (!powerDir.exists()) {
        m_hasBattery = false;
        m_batteryPercent = 100;
        m_isCharging = true;
        emit batteryChanged();
        return;
    }

    bool foundBat = false;
    int cap = 100;
    bool charging = false;

    const auto entries = powerDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const auto &info : entries) {
        if (info.fileName().startsWith(QStringLiteral("BAT"), Qt::CaseInsensitive)) {
            foundBat = true;
            // Capacidad
            QFile capFile(info.absoluteFilePath() + QStringLiteral("/capacity"));
            if (capFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                bool ok = false;
                int c = capFile.readLine().trimmed().toInt(&ok);
                if (ok) cap = qBound(0, c, 100);
            }
            // Estado de carga
            QFile statFile(info.absoluteFilePath() + QStringLiteral("/status"));
            if (statFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                QString st = QString::fromUtf8(statFile.readLine()).trimmed().toLower();
                if (st.contains(QStringLiteral("charging")) || st.contains(QStringLiteral("full"))) {
                    charging = true;
                }
            }
            break;
        }
    }

    // Si no hay batería identificada como BAT, verificar si el adaptador de CA está conectado
    if (!foundBat) {
        m_hasBattery = false;
        m_batteryPercent = 100;
        m_isCharging = true;
        m_lowBatteryAlert = false;
        emit batteryChanged();
        return;
    }

    m_hasBattery = true;
    m_batteryPercent = cap;
    m_isCharging = charging;

    // Si se conecta a la corriente, resetear descarte de alerta
    if (charging) {
        m_batteryAlertDismissed = false;
        m_lowBatteryAlert = false;
    } else if (cap < 10 && !m_batteryAlertDismissed) {
        m_lowBatteryAlert = true;
    } else {
        m_lowBatteryAlert = false;
    }

    emit batteryChanged();
}
