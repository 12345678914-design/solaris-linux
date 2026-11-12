#include "ShellBackend.h"
#include "DockModel.h"
#include "ThemeManager.h"
#include <QProcess>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTimer>
#include <QTime>
#include <QSet>
#include <QVariantMap>
#include <QRegularExpression>
#include <QDBusConnection>
#include <QUrl>
#include <QQuickWindow>

NotificationsAdaptor::NotificationsAdaptor(ShellBackend *parent)
    : QDBusAbstractAdaptor(parent)
    , m_backend(parent)
{
    setAutoRelaySignals(true);
}

uint NotificationsAdaptor::Notify(const QString &app_name, uint replaces_id, const QString &app_icon,
                                  const QString &summary, const QString &body, const QStringList &actions,
                                  const QVariantMap &hints, int expire_timeout)
{
    Q_UNUSED(replaces_id)
    Q_UNUSED(actions)
    Q_UNUSED(hints)
    Q_UNUSED(expire_timeout)
    m_backend->notify(summary, body, app_icon, app_name);
    return static_cast<uint>(m_backend->lastNotificationId());
}

void NotificationsAdaptor::CloseNotification(uint id)
{
    Q_UNUSED(id)
    m_backend->dismissIsland();
}

QStringList NotificationsAdaptor::GetCapabilities()
{
    return {QStringLiteral("body"), QStringLiteral("actions"), QStringLiteral("icon-static")};
}

void NotificationsAdaptor::GetServerInformation(QString &name, QString &vendor, QString &version, QString &spec_version)
{
    name = QStringLiteral("Titan Shell Notification Daemon");
    vendor = QStringLiteral("Titan Linux");
    version = QStringLiteral("1.0");
    spec_version = QStringLiteral("1.2");
}

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
    , m_batteryTimer(new QTimer(this))
{
    updateBatteryStatus();
    syncHardwareStatus();
    if (!m_ethernetConnected) {
        setWifiEnabled(true);
    }
    scanWifi();
    scanBluetooth();
    m_batteryTimer->setInterval(3500);
    connect(m_batteryTimer, &QTimer::timeout, this, [this]() {
        updateBatteryStatus();
    });
    m_batteryTimer->start();

    m_islandTimer = new QTimer(this);
    m_islandTimer->setSingleShot(true);
    connect(m_islandTimer, &QTimer::timeout, this, &ShellBackend::dismissIsland);

    m_workspaces = {
        QStringLiteral("Escritorio 1")
    };

    // Registrar servicio D-Bus org.freedesktop.Notifications
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected()) {
        new NotificationsAdaptor(this);
        bus.registerService(QStringLiteral("org.freedesktop.Notifications"));
        bus.registerObject(QStringLiteral("/org/freedesktop/Notifications"), this);
    }

    // Notificación inicial de bienvenida al arrancar
    QTimer::singleShot(2500, this, [this]() {
        notify(QStringLiteral("Bienvenido a Inti OS"),
               QStringLiteral("Sistema preparado y listo. Disfruta de la experiencia macOS en Linux."),
               QStringLiteral("qrc:/icons/solaris-logo.png"),
               QStringLiteral("Inti OS"));
    });

    m_userName = QString::fromLocal8Bit(qgetenv("USER"));
    if (m_userName.isEmpty()) m_userName = QStringLiteral("isai");
    m_userDisplayName = m_userName;
    if (!m_userDisplayName.isEmpty()) m_userDisplayName[0] = m_userDisplayName[0].toUpper();

    m_bootSplashActive = true;
    m_bootSplashFinished = false;
    m_lockScreenActive = !isLiveSystem();

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

bool ShellBackend::hasWifiAdapter() const
{
    QDir netDir(QStringLiteral("/sys/class/net"));
    if (netDir.exists()) {
        const QStringList entries = netDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &entry : entries) {
            if (entry == QStringLiteral("lo")) continue;
            if (entry.startsWith(QLatin1String("wl"))) return true;
            if (QDir(QStringLiteral("/sys/class/net/") + entry + QStringLiteral("/wireless")).exists()) {
                return true;
            }
            if (QFile::exists(QStringLiteral("/sys/class/net/") + entry + QStringLiteral("/phy80211"))) {
                return true;
            }
        }
    }
    return false;
}

void ShellBackend::setWifiEnabled(bool enabled)
{
    if (m_wifiEnabled != enabled) {
        m_wifiEnabled = enabled;
        if (enabled) {
            QProcess::startDetached(QStringLiteral("rfkill"), {QStringLiteral("unblock"), QStringLiteral("wifi")});
            QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), QStringLiteral("on")});
            scanWifi();
        } else {
            m_wifiConnected = false;
            m_wifiSsid.clear();
            QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), QStringLiteral("off")});
            QProcess::startDetached(QStringLiteral("rfkill"), {QStringLiteral("block"), QStringLiteral("wifi")});
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
    m_wifiSuspendedForEthernet = false;
    setWifiEnabled(!m_wifiEnabled);
}

void ShellBackend::setPrioritizeEthernet(bool prioritize)
{
    if (m_prioritizeEthernet != prioritize) {
        m_prioritizeEthernet = prioritize;
        emit prioritizeEthernetChanged();
        if (m_prioritizeEthernet && m_ethernetConnected && m_wifiEnabled) {
            m_wifiSuspendedForEthernet = true;
            setWifiEnabled(false);
        }
    }
}

void ShellBackend::togglePrioritizeEthernet()
{
    setPrioritizeEthernet(!m_prioritizeEthernet);
}

void ShellBackend::setBluetoothEnabled(bool enabled)
{
    if (m_bluetoothEnabled != enabled) {
        m_bluetoothEnabled = enabled;
        if (!m_bluetoothEnabled) {
            m_bluetoothConnected = false;
        } else {
            scanBluetooth();
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
    bool newState = !m_bluetoothEnabled;
    m_bluetoothEnabled = newState;
    emit bluetoothStatusChanged();
    if (newState) {
        QProcess::startDetached(QStringLiteral("bluetoothctl"), {QStringLiteral("power"), QStringLiteral("on")});
        QProcess::startDetached(QStringLiteral("rfkill"), {QStringLiteral("unblock"), QStringLiteral("bluetooth")});
        scanBluetooth();
    } else {
        QProcess::startDetached(QStringLiteral("bluetoothctl"), {QStringLiteral("power"), QStringLiteral("off")});
        QProcess::startDetached(QStringLiteral("rfkill"), {QStringLiteral("block"), QStringLiteral("bluetooth")});
    }
}

void ShellBackend::setBrightness(qreal level)
{
    m_brightness = qBound(0.05, level, 1.0);
    emit brightnessChanged();
    int percent = qRound(m_brightness * 100);

    // 1. Hardware real con backlight en sysfs
    if (m_hasHardwareBacklight) {
        QProcess::startDetached(QStringLiteral("brightnessctl"), {QStringLiteral("set"), QString::number(percent) + QStringLiteral("%")});
        QDir blDir(QStringLiteral("/sys/class/backlight"));
        const auto entries = blDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const auto &info : entries) {
            QFile maxFile(info.absoluteFilePath() + QStringLiteral("/max_brightness"));
            QFile actFile(info.absoluteFilePath() + QStringLiteral("/brightness"));
            if (maxFile.open(QIODevice::ReadOnly) && actFile.open(QIODevice::WriteOnly)) {
                int maxVal = maxFile.readLine().trimmed().toInt();
                if (maxVal > 0) {
                    int target = qBound(1, qRound(maxVal * m_brightness), maxVal);
                    actFile.write(QByteArray::number(target));
                    actFile.close();
                }
            }
        }
    }

    // 2. Monitores externos via DDC/CI
    QProcess::startDetached(QStringLiteral("ddcutil"), {QStringLiteral("setvcp"), QStringLiteral("10"), QString::number(percent), QStringLiteral("--brief")});
}

void ShellBackend::setVolume(qreal level)
{
    m_volume = qBound(0.0, level, 1.0);
    emit volumeChanged();
    int percent = qRound(m_volume * 100);
    QProcess::startDetached(QStringLiteral("pactl"), {QStringLiteral("set-sink-volume"), QStringLiteral("@DEFAULT_SINK@"), QString::number(percent) + QStringLiteral("%")});
    QProcess::startDetached(QStringLiteral("wpctl"), {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QString::number(m_volume, 'f', 2)});
    QProcess::startDetached(QStringLiteral("amixer"), {QStringLiteral("sset"), QStringLiteral("Master"), QString::number(percent) + QStringLiteral("%")});
    if (percent > 0) {
        QProcess::startDetached(QStringLiteral("pactl"), {QStringLiteral("set-sink-mute"), QStringLiteral("@DEFAULT_SINK@"), QStringLiteral("0")});
        QProcess::startDetached(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QStringLiteral("0")});
        QProcess::startDetached(QStringLiteral("amixer"), {QStringLiteral("sset"), QStringLiteral("Master"), QStringLiteral("unmute")});
    }
}

void ShellBackend::syncHardwareStatus()
{
    // 0. Leer volumen actual del sistema
    QProcess pVol;
    pVol.start(QStringLiteral("wpctl"), {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")});
    if (pVol.waitForFinished(250)) {
        QString out = QString::fromUtf8(pVol.readAllStandardOutput()).trimmed();
        if (out.startsWith(QStringLiteral("Volume:"))) {
            QStringList parts = out.split(QLatin1Char(' '), Qt::SkipEmptyParts);
            if (parts.size() >= 2) {
                bool ok = false;
                qreal v = parts.at(1).toDouble(&ok);
                if (ok && v >= 0.0) {
                    m_volume = qBound(0.0, v, 1.0);
                    emit volumeChanged();
                }
            }
        }
    }

    // 1. Leer brillo y verificar presencia de backlight en hardware real
    QDir blDir(QStringLiteral("/sys/class/backlight"));
    bool foundBacklight = false;
    if (blDir.exists()) {
        const auto entries = blDir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System);
        for (const auto &info : entries) {
            foundBacklight = true;
            QFile actFile(info.absoluteFilePath() + QStringLiteral("/brightness"));
            QFile maxFile(info.absoluteFilePath() + QStringLiteral("/max_brightness"));
            if (actFile.open(QIODevice::ReadOnly) && maxFile.open(QIODevice::ReadOnly)) {
                bool ok1 = false, ok2 = false;
                qreal act = actFile.readLine().trimmed().toDouble(&ok1);
                qreal max = maxFile.readLine().trimmed().toDouble(&ok2);
                if (ok1 && ok2 && max > 0) {
                    m_brightness = qBound(0.05, act / max, 1.0);
                    emit brightnessChanged();
                    break;
                }
            }
        }
    }
    m_hasHardwareBacklight = foundBacklight;

    // 2. Comprobar Ethernet (cable conectado vs desconectado)
    bool ethNow = false;
    QString ethIface;
    QDir netDir(QStringLiteral("/sys/class/net"));
    if (netDir.exists()) {
        const auto entries = netDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const auto &info : entries) {
            QString name = info.fileName();
            if (name.startsWith(QLatin1Char('e')) || name.startsWith(QStringLiteral("eth")) || name.startsWith(QStringLiteral("en"))) {
                QFile carrierFile(info.absoluteFilePath() + QStringLiteral("/carrier"));
                if (carrierFile.open(QIODevice::ReadOnly)) {
                    QString cVal = QString::fromUtf8(carrierFile.readLine()).trimmed();
                    if (cVal == QStringLiteral("1")) {
                        ethNow = true;
                        ethIface = name;
                        break;
                    }
                }
            }
        }
    }

    // Respaldo de detección de Ethernet con nmcli si sysfs no reporta carrier
    if (!ethNow) {
        QProcess pEth;
        pEth.start(QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("DEVICE,TYPE,STATE"), QStringLiteral("dev")});
        if (pEth.waitForFinished(250)) {
            QString out = QString::fromUtf8(pEth.readAllStandardOutput());
            for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                QStringList fields = line.split(QLatin1Char(':'));
                if (fields.size() >= 3 && fields.at(1) == QStringLiteral("ethernet") && fields.at(2) == QStringLiteral("connected")) {
                    ethNow = true;
                    ethIface = fields.at(0);
                    break;
                }
            }
        }
    }

    m_ethernetInterface = ethIface;

    // Conmutación inteligente: Si Ethernet está conectado y la prioridad está activa,
    // se desactiva Wi-Fi para priorizar la conexión cableada. Al desconectar Ethernet,
    // se reactiva Wi-Fi automáticamente.
    if (ethNow != m_ethernetConnected) {
        m_ethernetConnected = ethNow;
        emit ethernetStatusChanged();

        if (m_prioritizeEthernet) {
            if (m_ethernetConnected) {
                if (m_wifiEnabled) {
                    m_wifiSuspendedForEthernet = true;
                    setWifiEnabled(false);
                }
            } else {
                if (m_wifiSuspendedForEthernet || !m_wifiEnabled) {
                    m_wifiSuspendedForEthernet = false;
                    setWifiEnabled(true);
                } else {
                    scanWifi();
                }
            }
        } else if (!m_ethernetConnected) {
            scanWifi();
        }
    }

    // 3. Comprobar Wi-Fi (rfkill o nmcli)
    QProcess pWifi;
    pWifi.start(QStringLiteral("rfkill"), {QStringLiteral("list"), QStringLiteral("wifi")});
    if (pWifi.waitForFinished(300)) {
        QString out = QString::fromUtf8(pWifi.readAllStandardOutput()).toLower();
        if (!out.isEmpty()) {
            bool blocked = out.contains(QStringLiteral("soft blocked: yes")) || out.contains(QStringLiteral("hard blocked: yes"));
            m_wifiEnabled = !blocked;
            emit wifiStatusChanged();
        }
    }

    // 4. Comprobar Bluetooth
    QProcess pBt;
    pBt.start(QStringLiteral("rfkill"), {QStringLiteral("list"), QStringLiteral("bluetooth")});
    if (pBt.waitForFinished(300)) {
        QString out = QString::fromUtf8(pBt.readAllStandardOutput()).toLower();
        if (!out.isEmpty()) {
            bool blocked = out.contains(QStringLiteral("soft blocked: yes")) || out.contains(QStringLiteral("hard blocked: yes"));
            m_bluetoothEnabled = !blocked;
            emit bluetoothStatusChanged();
        }
    }

    // 5. Nombre de la red Wi-Fi activa
    if (m_wifiEnabled) {
        QProcess pSsid;
        pSsid.start(QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("DEVICE,TYPE,STATE,CONNECTION"), QStringLiteral("dev")});
        if (pSsid.waitForFinished(400)) {
            QString out = QString::fromUtf8(pSsid.readAllStandardOutput());
            bool foundConn = false;
            for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                QStringList fields = line.split(QLatin1Char(':'));
                if (fields.size() >= 4 && fields.at(1).trimmed() == QStringLiteral("wifi")) {
                    QString state = fields.at(2).trimmed().toLower();
                    QString conn = fields.at(3).trimmed();
                    if (state == QStringLiteral("connected") && !conn.isEmpty() && conn != QStringLiteral("--")) {
                        m_wifiSsid = conn;
                        m_wifiConnected = true;
                        foundConn = true;
                        emit wifiStatusChanged();
                        break;
                    }
                }
            }
            if (!foundConn && m_wifiConnected) {
                m_wifiConnected = false;
                m_wifiSsid.clear();
                emit wifiStatusChanged();
            }
        }
    } else {
        if (m_wifiConnected) {
            m_wifiConnected = false;
            m_wifiSsid.clear();
            emit wifiStatusChanged();
        }
    }

    // 6. Nombre de dispositivo Bluetooth conectado
    if (m_bluetoothEnabled) {
        QProcess pBtDev;
        pBtDev.start(QStringLiteral("bluetoothctl"), {QStringLiteral("devices"), QStringLiteral("Connected")});
        if (pBtDev.waitForFinished(350)) {
            QString out = QString::fromUtf8(pBtDev.readAllStandardOutput()).trimmed();
            if (!out.isEmpty()) {
                QStringList lines = out.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
                if (!lines.isEmpty()) {
                    QString first = lines.first();
                    QStringList parts = first.split(QLatin1Char(' '), Qt::SkipEmptyParts);
                    if (parts.size() >= 3) {
                        parts.removeFirst();
                        parts.removeFirst();
                        m_connectedBluetoothDevice = parts.join(QLatin1Char(' '));
                        m_bluetoothConnected = true;
                        emit bluetoothStatusChanged();
                    }
                }
            }
        }
    }
}

void ShellBackend::scanWifi()
{
    if (m_wifiScanning) return;
    m_wifiScanning = true;
    emit wifiScanningChanged();

    // Asegurarse de que el Wi-Fi esté desbloqueado y activo
    QProcess::startDetached(QStringLiteral("rfkill"), {QStringLiteral("unblock"), QStringLiteral("wifi")});
    QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), QStringLiteral("on")});
    QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("rescan")});

    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, [this, proc](int exitCode, QProcess::ExitStatus) {
        Q_UNUSED(exitCode);
        QByteArray out = proc->readAllStandardOutput();
        proc->deleteLater();
        m_wifiScanning = false;
        emit wifiScanningChanged();

        QList<QVariantMap> found;
        QSet<QString> seenSsids;

        if (!out.isEmpty()) {
            QString text = QString::fromUtf8(out);
            QStringList lines = text.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
            for (const QString &line : lines) {
                // nmcli -t escapa dos puntos dentro del SSID como \:
                QString unescaped = line;
                unescaped.replace(QStringLiteral("\\:"), QStringLiteral("__COLON__"));
                QStringList fields = unescaped.split(QLatin1Char(':'));
                if (fields.size() >= 3) {
                    bool inUse = fields.at(0).trimmed() == QStringLiteral("*");
                    QString rawSsid = fields.at(1);
                    QString ssid = rawSsid.replace(QStringLiteral("__COLON__"), QStringLiteral(":")).trimmed();
                    if (ssid.isEmpty() || ssid == QStringLiteral("--")) continue;
                    if (seenSsids.contains(ssid)) continue;
                    seenSsids.insert(ssid);

                    int signal = fields.at(2).trimmed().toInt();
                    QString security = fields.size() > 3 ? fields.at(3).trimmed() : QString();
                    if (security.isEmpty() || security == QStringLiteral("--")) {
                        security = QStringLiteral("Abierta");
                    }

                    QVariantMap net;
                    net[QStringLiteral("ssid")] = ssid;
                    net[QStringLiteral("signal")] = qBound(10, signal, 100);
                    net[QStringLiteral("connected")] = inUse;
                    net[QStringLiteral("security")] = security;

                    if (inUse) {
                        m_wifiConnected = true;
                        m_wifiSsid = ssid;
                        emit wifiStatusChanged();
                        found.prepend(net);
                    } else {
                        found.append(net);
                    }
                }
            }
        }

        // Ordenar redes por intensidad de señal descendente (la conectada siempre primera)
        std::stable_sort(found.begin(), found.end(), [](const QVariantMap &a, const QVariantMap &b) {
            bool aConn = a.value(QStringLiteral("connected")).toBool();
            bool bConn = b.value(QStringLiteral("connected")).toBool();
            if (aConn != bConn) return aConn;
            return a.value(QStringLiteral("signal")).toInt() > b.value(QStringLiteral("signal")).toInt();
        });

        // Solo si NO existe ningún hardware Wi-Fi físico, proveer redes de demostración para pruebas visuales en QEMU
        if (found.isEmpty() && !hasWifiAdapter()) {
            QVariantMap n1;
            n1[QStringLiteral("ssid")] = m_wifiSsid.isEmpty() ? QStringLiteral("Solaris-Fiber-5G") : m_wifiSsid;
            n1[QStringLiteral("signal")] = 95;
            n1[QStringLiteral("connected")] = m_wifiConnected;
            n1[QStringLiteral("security")] = QStringLiteral("WPA2/WPA3");
            found.append(n1);

            QVariantMap n2;
            n2[QStringLiteral("ssid")] = QStringLiteral("Solaris-Guest");
            n2[QStringLiteral("signal")] = 80;
            n2[QStringLiteral("connected")] = false;
            n2[QStringLiteral("security")] = QStringLiteral("Abierta");
            found.append(n2);

            QVariantMap n3;
            n3[QStringLiteral("ssid")] = QStringLiteral("Red_Oficina_Alta");
            n3[QStringLiteral("signal")] = 65;
            n3[QStringLiteral("connected")] = false;
            n3[QStringLiteral("security")] = QStringLiteral("WPA2");
            found.append(n3);

            QVariantMap n4;
            n4[QStringLiteral("ssid")] = QStringLiteral("Infinitum-WiFi-88");
            n4[QStringLiteral("signal")] = 42;
            n4[QStringLiteral("connected")] = false;
            n4[QStringLiteral("security")] = QStringLiteral("WPA2");
            found.append(n4);
        }

        m_wifiNetworks.clear();
        for (const auto &m : found) {
            m_wifiNetworks.append(m);
        }
        emit wifiNetworksChanged();
    });

    proc->start(QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"), QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("list")});
}

void ShellBackend::connectWifi(const QString &ssid, const QString &password)
{
    if (ssid.isEmpty()) return;

    QStringList args = {QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("connect"), ssid};
    if (!password.isEmpty()) {
        args << QStringLiteral("password") << password;
    }

    QProcess *connProc = new QProcess(this);
    connect(connProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, [this, connProc, ssid](int exitCode, QProcess::ExitStatus) {
        connProc->deleteLater();

        if (exitCode == 0) {
            m_wifiConnected = true;
            m_wifiSsid = ssid;
            emit wifiStatusChanged();

            for (int i = 0; i < m_wifiNetworks.size(); ++i) {
                QVariantMap m = m_wifiNetworks[i].toMap();
                m[QStringLiteral("connected")] = (m[QStringLiteral("ssid")].toString() == ssid);
                m_wifiNetworks[i] = m;
            }
            emit wifiNetworksChanged();

            notify(QStringLiteral("Wi-Fi Conectado"), QStringLiteral("Conectado con éxito a ") + ssid, QStringLiteral("network-wireless"), QStringLiteral("Red"));
        } else {
            notify(QStringLiteral("Error de conexión Wi-Fi"), QStringLiteral("No se pudo conectar a ") + ssid + QStringLiteral(". Verifica la contraseña o la señal."), QStringLiteral("dialog-error"), QStringLiteral("Red"));
        }
        scanWifi();
    });

    connProc->start(QStringLiteral("nmcli"), args);
}

void ShellBackend::disconnectWifi()
{
    m_wifiConnected = false;
    QString currentSsid = m_wifiSsid;
    m_wifiSsid.clear();
    emit wifiStatusChanged();

    for (int i = 0; i < m_wifiNetworks.size(); ++i) {
        QVariantMap m = m_wifiNetworks[i].toMap();
        m[QStringLiteral("connected")] = false;
        m_wifiNetworks[i] = m;
    }
    emit wifiNetworksChanged();

    if (!currentSsid.isEmpty()) {
        QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("down"), QStringLiteral("id"), currentSsid});
    }
    QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("device"), QStringLiteral("disconnect"), QStringLiteral("wlan0")});
    QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("device"), QStringLiteral("disconnect"), QStringLiteral("wlp2s0")});
    QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("device"), QStringLiteral("disconnect"), QStringLiteral("wlp3s0")});
}

void ShellBackend::scanBluetooth()
{
    if (m_bluetoothScanning) return;
    m_bluetoothScanning = true;
    emit bluetoothScanningChanged();

    // Asegurarse de que el adaptador Bluetooth esté desbloqueado y encendido
    QProcess::startDetached(QStringLiteral("rfkill"), {QStringLiteral("unblock"), QStringLiteral("bluetooth")});
    QProcess::startDetached(QStringLiteral("bluetoothctl"), {QStringLiteral("power"), QStringLiteral("on")});

    QProcess *scanProc = new QProcess(this);
    // Escanear el espectro en vivo con bluetoothctl durante 5 segundos
    scanProc->start(QStringLiteral("bluetoothctl"), {QStringLiteral("--timeout"), QStringLiteral("5"), QStringLiteral("scan"), QStringLiteral("on")});

    connect(scanProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, [this, scanProc](int, QProcess::ExitStatus) {
        QByteArray scanOut = scanProc->readAllStandardOutput();
        scanProc->deleteLater();

        // Tras el escaneo activo, consultar la lista completa de dispositivos registrados en BlueZ
        QProcess *devProc = new QProcess(this);
        connect(devProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, [this, devProc, scanOut](int, QProcess::ExitStatus) {
            QByteArray devOut = devProc->readAllStandardOutput();
            devProc->deleteLater();

            m_bluetoothScanning = false;
            emit bluetoothScanningChanged();

            QList<QVariantMap> found;
            QSet<QString> seenMacs;

            auto parseLine = [this, &found, &seenMacs](const QString &line) {
                QString cleaned = line.trimmed();
                static const QRegularExpression devRegex(QStringLiteral(R"((?:\[.*?\]\s+)?Device\s+([0-9A-Fa-f:]{17})\s+(?:Name:\s+)?(.*))"));
                QRegularExpressionMatch match = devRegex.match(cleaned);
                if (match.hasMatch()) {
                    QString mac = match.captured(1).trimmed();
                    QString name = match.captured(2).trimmed();
                    if (mac.isEmpty() || seenMacs.contains(mac)) return;
                    if (name.isEmpty()) name = mac;

                    seenMacs.insert(mac);

                    QString lower = name.toLower();
                    QString type = QStringLiteral("device");
                    if (lower.contains("auricular") || lower.contains("sound") || lower.contains("headphone") ||
                        lower.contains("airpod") || lower.contains("buds") || lower.contains("audio") || lower.contains("speaker") || lower.contains("altavoz")) {
                        type = QStringLiteral("audio");
                    } else if (lower.contains("mouse") || lower.contains("raton") || lower.contains("trackpad")) {
                        type = QStringLiteral("mouse");
                    } else if (lower.contains("teclado") || lower.contains("keyboard") || lower.contains("keychron")) {
                        type = QStringLiteral("keyboard");
                    } else if (lower.contains("phone") || lower.contains("movil") || lower.contains("galaxy") || lower.contains("iphone") || lower.contains("pixel")) {
                        type = QStringLiteral("phone");
                    }

                    bool connected = (name == m_connectedBluetoothDevice && m_bluetoothConnected);

                    QVariantMap dev;
                    dev[QStringLiteral("mac")] = mac;
                    dev[QStringLiteral("name")] = name;
                    dev[QStringLiteral("connected")] = connected;
                    dev[QStringLiteral("type")] = type;

                    if (connected) {
                        found.prepend(dev);
                    } else {
                        found.append(dev);
                    }
                }
            };

            // Procesar dispositivos capturados durante el escaneo y de la base de datos
            QString fullText = QString::fromUtf8(scanOut) + QStringLiteral("\n") + QString::fromUtf8(devOut);
            QStringList lines = fullText.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
            for (const QString &line : lines) {
                parseLine(line);
            }

            m_bluetoothDevices.clear();
            for (const auto &m : found) {
                m_bluetoothDevices.append(m);
            }
            emit bluetoothDevicesChanged();
        });

        devProc->start(QStringLiteral("bluetoothctl"), {QStringLiteral("devices")});
    });
}

void ShellBackend::connectBluetooth(const QString &mac)
{
    if (mac.isEmpty()) return;

    m_bluetoothConnected = true;
    for (int i = 0; i < m_bluetoothDevices.size(); ++i) {
        QVariantMap m = m_bluetoothDevices[i].toMap();
        if (m[QStringLiteral("mac")].toString() == mac) {
            m[QStringLiteral("connected")] = true;
            m_connectedBluetoothDevice = m[QStringLiteral("name")].toString();
        } else {
            m[QStringLiteral("connected")] = false;
        }
        m_bluetoothDevices[i] = m;
    }
    emit bluetoothStatusChanged();
    emit bluetoothDevicesChanged();

    QProcess::startDetached(QStringLiteral("bluetoothctl"), {QStringLiteral("connect"), mac});
}

void ShellBackend::disconnectBluetooth(const QString &mac)
{
    m_bluetoothConnected = false;
    for (int i = 0; i < m_bluetoothDevices.size(); ++i) {
        QVariantMap m = m_bluetoothDevices[i].toMap();
        if (mac.isEmpty() || m[QStringLiteral("mac")].toString() == mac) {
            m[QStringLiteral("connected")] = false;
        }
        m_bluetoothDevices[i] = m;
    }
    emit bluetoothStatusChanged();
    emit bluetoothDevicesChanged();

    if (!mac.isEmpty()) {
        QProcess::startDetached(QStringLiteral("bluetoothctl"), {QStringLiteral("disconnect"), mac});
    }
}

void ShellBackend::launchApp(const QString &appId, const QString &exec)
{
    if (m_dockModel) {
        m_dockModel->launchApp(appId, exec);
    } else if (!exec.isEmpty()) {
        QStringList parts = exec.split(' ');
        QString program = parts.takeFirst();
        QString resolved = resolveShellBinary(program);
        QProcess::startDetached(resolved, parts);
    }
    setLauncherVisible(false);
}

void ShellBackend::openAcerca()
{
    if (m_dockModel) {
        m_dockModel->launchApp(QStringLiteral("titan-acerca"), QStringLiteral("titan-acerca"), QStringLiteral("Acerca de Solaris"), QStringLiteral("qrc:/icons/about.png"));
    } else {
        QProcess::startDetached(resolveShellBinary(QStringLiteral("titan-acerca")));
    }
}

void ShellBackend::openTerminal()
{
    if (m_dockModel) {
        m_dockModel->launchApp(QStringLiteral("titan-terminal"), QStringLiteral("titan-terminal"), QStringLiteral("Terminal"), QStringLiteral("qrc:/icons/terminal.png"));
    } else {
        QProcess::startDetached(resolveShellBinary(QStringLiteral("titan-terminal")));
    }
}

void ShellBackend::openFinder()
{
    if (m_dockModel) {
        m_dockModel->launchApp(QStringLiteral("titan-finder"), QStringLiteral("titan-finder"), QStringLiteral("Finder"), QStringLiteral("qrc:/icons/finder.png"));
    } else {
        QProcess::startDetached(resolveShellBinary(QStringLiteral("titan-finder")));
    }
}

void ShellBackend::suspend()
{
    QProcess::startDetached(QStringLiteral("systemctl"), QStringList() << QStringLiteral("suspend"));
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
        if (m_controlCenterVisible) {
            syncHardwareStatus();
            scanWifi();
            scanBluetooth();
        }
    }
}

void ShellBackend::toggleControlCenter()
{
    if (m_controlCenterVisible && m_controlCenterPage != 0) {
        setControlCenterPage(0);
        return;
    }
    setControlCenterVisible(!m_controlCenterVisible);
    if (!m_controlCenterVisible) {
        m_controlCenterPage = 0;
        emit controlCenterPageChanged();
    }
}

void ShellBackend::openControlCenter()
{
    m_controlCenterPage = 0;
    emit controlCenterPageChanged();
    setControlCenterVisible(true);
}

void ShellBackend::closeControlCenter()
{
    setControlCenterVisible(false);
    m_controlCenterPage = 0;
    emit controlCenterPageChanged();
}

void ShellBackend::setControlCenterPage(int page)
{
    if (m_controlCenterPage != page) {
        m_controlCenterPage = page;
        emit controlCenterPageChanged();
    }
}

void ShellBackend::openControlCenterWifi()
{
    setControlCenterPage(1);
    setControlCenterVisible(true);
    scanWifi();
}

void ShellBackend::openControlCenterBluetooth()
{
    setControlCenterPage(2);
    setControlCenterVisible(true);
    scanBluetooth();
}

bool ShellBackend::splashVisible() const
{
    return false;
}

QString ShellBackend::splashName() const
{
    return QString();
}

QString ShellBackend::splashIcon() const
{
    return QString();
}

void ShellBackend::showSplash(const QString &name, const QString &icon, const QString &exec)
{
    // En lugar de ventana de splash centrada, el icono de la aplicación en el Dock rebota como una pelota
    if (m_dockModel) {
        QString id = exec.isEmpty() ? name : exec;
        m_dockModel->setAppLaunching(id, exec, name, icon);
    }
}

void ShellBackend::hideSplash()
{
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

void ShellBackend::setSimulatedBattery(int percent, bool charging)
{
    m_simulatedBattery = true;
    m_hasBattery = true;
    m_batteryPercent = qBound(0, percent, 100);
    m_isCharging = charging;
    if (charging) {
        m_batteryAlertDismissed = false;
        m_lowBatteryAlert = false;
    } else if (m_batteryPercent < 10 && !m_batteryAlertDismissed) {
        m_lowBatteryAlert = true;
    } else {
        m_lowBatteryAlert = false;
    }
    emit batteryChanged();
}

void ShellBackend::updateBatteryStatus()
{
    if (m_simulatedBattery) return;

    // 0. Sincronización de batería de host en máquinas virtuales QEMU (virtio-serial port o fw_cfg)
    static const QString virtioPort = QStringLiteral("/dev/virtio-ports/titan.battery");
    static const QString fwCfgPath = QStringLiteral("/sys/firmware/qemu_fw_cfg/by_name/opt/titan/battery/raw");

    QString qemuBatData;
    if (QFile::exists(virtioPort)) {
        QFile vFile(virtioPort);
        if (vFile.open(QIODevice::ReadOnly | QIODevice::Unbuffered)) {
            QByteArray content = vFile.readAll().trimmed();
            if (!content.isEmpty()) {
                qemuBatData = QString::fromUtf8(content.split('\n').last()).trimmed();
            }
        }
    }
    if (qemuBatData.isEmpty() && QFile::exists(fwCfgPath)) {
        QFile fFile(fwCfgPath);
        if (fFile.open(QIODevice::ReadOnly)) {
            qemuBatData = QString::fromUtf8(fFile.readAll()).trimmed();
        }
    }
    if (!qemuBatData.isEmpty()) {
        const QStringList parts = qemuBatData.split(QLatin1Char('|'));
        if (parts.size() >= 2) {
            bool ok = false;
            int capVal = parts.at(0).trimmed().toInt(&ok);
            if (ok) {
                QString statVal = parts.at(1).trimmed().toLower();
                bool chg = (statVal == QStringLiteral("charging") || statVal == QStringLiteral("full"));
                if (parts.size() >= 3 && parts.at(2).trimmed() == QStringLiteral("1")) {
                    if (capVal >= 95) chg = true;
                }
                m_hasBattery = true;
                m_batteryPercent = qBound(0, capVal, 100);
                m_isCharging = chg;
                if (chg) {
                    m_batteryAlertDismissed = false;
                    m_lowBatteryAlert = false;
                } else if (m_batteryPercent < 10 && !m_batteryAlertDismissed) {
                    m_lowBatteryAlert = true;
                } else {
                    m_lowBatteryAlert = false;
                }
                emit batteryChanged();
                return;
            }
        }
    }

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
    bool hasAc = false;
    bool acOnline = false;

    const auto entries = powerDir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System);
    for (const auto &info : entries) {
        QString name = info.fileName();
        if (name.startsWith(QStringLiteral("AC"), Qt::CaseInsensitive) ||
            name.startsWith(QStringLiteral("ADP"), Qt::CaseInsensitive) ||
            name.contains(QStringLiteral("ac"), Qt::CaseInsensitive)) {
            hasAc = true;
            QFile onlineFile(info.absoluteFilePath() + QStringLiteral("/online"));
            if (onlineFile.open(QIODevice::ReadOnly)) {
                if (onlineFile.readLine().trimmed() == "1") {
                    acOnline = true;
                }
            }
        }
        if (name.contains(QStringLiteral("BAT"), Qt::CaseInsensitive)) {
            foundBat = true;
            // Capacidad
            QFile capFile(info.absoluteFilePath() + QStringLiteral("/capacity"));
            if (capFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                bool ok = false;
                int c = capFile.readLine().trimmed().toInt(&ok);
                if (ok) cap = qBound(0, c, 100);
            }
            // Estado de carga exacto
            QFile statFile(info.absoluteFilePath() + QStringLiteral("/status"));
            if (statFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                QString st = QString::fromUtf8(statFile.readLine()).trimmed().toLower();
                if (st == QStringLiteral("charging")) {
                    charging = true;
                } else if (st == QStringLiteral("discharging")) {
                    charging = false;
                } else if (st == QStringLiteral("full")) {
                    charging = true;
                }
            }
        }
    }

    // Si detectamos adaptador AC y no está conectado a la corriente, no está cargando
    if (hasAc && !acOnline) {
        charging = false;
    } else if (hasAc && acOnline && foundBat && !charging) {
        if (cap >= 95) {
            charging = true;
        }
    }

    // Si no hay batería identificada como BAT
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

int ShellBackend::unreadNotificationCount() const
{
    int count = 0;
    for (const QVariant &v : m_notifications) {
        if (!v.toMap().value(QStringLiteral("read"), false).toBool()) {
            count++;
        }
    }
    return count;
}

void ShellBackend::setNotificationCenterVisible(bool visible)
{
    if (m_notificationCenterVisible != visible) {
        m_notificationCenterVisible = visible;
        emit notificationCenterVisibleChanged();
        if (visible) {
            for (int i = 0; i < m_notifications.size(); ++i) {
                QVariantMap m = m_notifications[i].toMap();
                m[QStringLiteral("read")] = true;
                m_notifications[i] = m;
            }
            emit notificationsChanged();
        }
    }
}

void ShellBackend::toggleNotificationCenter()
{
    setNotificationCenterVisible(!m_notificationCenterVisible);
}

void ShellBackend::closeNotificationCenter()
{
    setNotificationCenterVisible(false);
}

void ShellBackend::clearNotifications()
{
    m_notifications.clear();
    emit notificationsChanged();
}

void ShellBackend::removeNotification(int id)
{
    for (int i = 0; i < m_notifications.size(); ++i) {
        if (m_notifications[i].toMap().value(QStringLiteral("id")).toInt() == id) {
            m_notifications.removeAt(i);
            emit notificationsChanged();
            break;
        }
    }
}

void ShellBackend::dismissIsland()
{
    if (m_islandActive) {
        m_islandActive = false;
        emit islandChanged();
    }
}

void ShellBackend::notify(const QString &title, const QString &message, const QString &icon, const QString &appName)
{
    m_lastNotificationId++;
    QVariantMap n;
    n[QStringLiteral("id")] = m_lastNotificationId;
    n[QStringLiteral("title")] = title.isEmpty() ? QStringLiteral("Notificación") : title;
    n[QStringLiteral("message")] = message;
    n[QStringLiteral("appName")] = appName.isEmpty() ? QStringLiteral("Sistema") : appName;

    QString resolvedIcon = icon;
    if (resolvedIcon.isEmpty()) {
        resolvedIcon = QStringLiteral("qrc:/icons/system.png");
    } else if (!resolvedIcon.startsWith(QStringLiteral("qrc:/")) && !resolvedIcon.startsWith(QLatin1Char('/'))) {
        static const QStringList searchPaths = {
            QStringLiteral("/usr/share/icons/hicolor/128x128/apps/"),
            QStringLiteral("/usr/share/icons/hicolor/scalable/apps/"),
            QStringLiteral("/usr/share/icons/hicolor/64x64/apps/"),
            QStringLiteral("/usr/share/pixmaps/"),
            QStringLiteral("/usr/share/titan/icons/")
        };
        bool found = false;
        for (const QString &sp : searchPaths) {
            if (QFile::exists(sp + resolvedIcon + QStringLiteral(".png"))) {
                resolvedIcon = QUrl::fromLocalFile(sp + resolvedIcon + QStringLiteral(".png")).toString();
                found = true;
                break;
            }
            if (QFile::exists(sp + resolvedIcon + QStringLiteral(".svg"))) {
                resolvedIcon = QUrl::fromLocalFile(sp + resolvedIcon + QStringLiteral(".svg")).toString();
                found = true;
                break;
            }
        }
        if (!found) {
            resolvedIcon = QStringLiteral("qrc:/icons/system.png");
        }
    }

    n[QStringLiteral("icon")] = resolvedIcon;
    n[QStringLiteral("time")] = QTime::currentTime().toString(QStringLiteral("hh:mm"));
    n[QStringLiteral("read")] = false;

    m_notifications.prepend(n);
    emit notificationsChanged();

    m_currentIslandNotification = n;
    m_islandActive = true;
    emit islandChanged();

    if (m_islandTimer) {
        m_islandTimer->start(5000);
    }
}

void ShellBackend::setWorkspacesVisible(bool visible)
{
    if (m_workspacesVisible != visible) {
        m_workspacesVisible = visible;
        emit workspacesVisibleChanged();
    }
}

void ShellBackend::toggleWorkspaces()
{
    setWorkspacesVisible(!m_workspacesVisible);
}

void ShellBackend::addWorkspace()
{
    int nextNum = m_workspaces.size() + 1;
    m_workspaces.append(QStringLiteral("Escritorio ") + QString::number(nextNum));
    emit workspacesChanged();
}

void ShellBackend::removeWorkspace(int index)
{
    if (index >= 0 && index < m_workspaces.size() && m_workspaces.size() > 1) {
        m_workspaces.removeAt(index);
        if (m_currentWorkspace >= m_workspaces.size()) {
            m_currentWorkspace = m_workspaces.size() - 1;
            emit currentWorkspaceChanged();
        }
        emit workspacesChanged();
    }
}

void ShellBackend::switchToWorkspace(int index)
{
    if (index >= 0 && index < m_workspaces.size()) {
        m_currentWorkspace = index;
        emit currentWorkspaceChanged();
        QString cmd = QStringLiteral("wtype -M logo -k %1 -m logo 2>/dev/null || wtype -M win -k %1 -m win 2>/dev/null").arg(index + 1);
        QProcess::startDetached(QStringLiteral("sh"), {QStringLiteral("-c"), cmd});
        setWorkspacesVisible(false);
    }
}

void ShellBackend::updateDockMask(QObject *windowObj, int x, int y, int w, int h, bool isMaximized, bool isRevealed, bool hasPopup)
{
    auto *win = qobject_cast<QQuickWindow*>(windowObj);
    if (!win) return;

    QRegion region;
    if (hasPopup) {
        // Al abrir un menú contextual en el Dock, la ventana completa recibe eventos
        // para interactuar con las opciones o cerrarlo al hacer clic fuera
        region = QRegion(0, 0, win->width(), win->height());
    } else if (isMaximized && !isRevealed) {
        // Tira de activación ultrafina (3 px) en el centro inferior
        int trigW = qMin(win->width(), 600);
        int trigX = (win->width() - trigW) / 2;
        region = QRegion(trigX, win->height() - 3, trigW, 3);
    } else {
        // Solo el área física del Dock y su margen inmediato (para que las ventanas detrás reciban clics normalmente)
        if (w > 0 && h > 0) {
            region = QRegion(x, y, w, h);
        }
    }
    win->setMask(region);
}

bool ShellBackend::isLiveSystem() const
{
    return QFile::exists(QStringLiteral("/run/archiso")) ||
           QFile::exists(QStringLiteral("/run/archiso/bootmnt")) ||
           QFile::exists(QStringLiteral("/etc/titan-build.env"));
}

void ShellBackend::finishBootSplash()
{
    if (m_bootSplashActive) {
        m_bootSplashActive = false;
        m_bootSplashFinished = true;
        emit bootSplashActiveChanged();
        emit bootSplashFinishedChanged();
    }
}

void ShellBackend::lockScreen()
{
    if (!m_lockScreenActive) {
        m_lockScreenActive = true;
        emit lockScreenActiveChanged();
    }
}

void ShellBackend::unlockScreen()
{
    if (m_lockScreenActive) {
        m_lockScreenActive = false;
        emit lockScreenActiveChanged();
    }
}

bool ShellBackend::authenticateLock(const QString &password)
{
    // 1. En entorno Live ISO se puede ingresar con Enter o cualquier contraseña
    if (isLiveSystem()) {
        unlockScreen();
        return true;
    }

    // 2. Si no hay contraseña ingresada y el usuario actual no requiere contraseña
    if (password.trimmed().isEmpty()) {
        QProcess pChk;
        pChk.start(QStringLiteral("su"), QStringList() << QStringLiteral("-c") << QStringLiteral("true") << m_userName);
        if (pChk.waitForStarted(800)) {
            pChk.write("\n");
            pChk.closeWriteChannel();
            if (pChk.waitForFinished(1500) && pChk.exitCode() == 0) {
                unlockScreen();
                return true;
            }
        }
    }

    // 3. Verificación con proceso su
    {
        QProcess pSu;
        pSu.start(QStringLiteral("su"), QStringList() << QStringLiteral("-c") << QStringLiteral("true") << m_userName);
        if (pSu.waitForStarted(1000)) {
            pSu.write((password + QStringLiteral("\n")).toUtf8());
            pSu.closeWriteChannel();
            if (pSu.waitForFinished(3000) && pSu.exitCode() == 0) {
                unlockScreen();
                return true;
            }
        }
    }

    // 4. Verificación con proceso sudo -k -S true (usando stdin)
    {
        QProcess pSudo;
        pSudo.start(QStringLiteral("sudo"), QStringList() << QStringLiteral("-k") << QStringLiteral("-S") << QStringLiteral("true"));
        if (pSudo.waitForStarted(1000)) {
            pSudo.write((password + QStringLiteral("\n")).toUtf8());
            pSudo.closeWriteChannel();
            if (pSudo.waitForFinished(3000) && pSudo.exitCode() == 0) {
                unlockScreen();
                return true;
            }
        }
    }

    return false;
}

