#include "TitanBinary.h"
#include "TitanUsuario.h"
#include "ShellBackend.h"
#include "TitanPrefs.h"
#include "TitanIconoSvg.h"
#include "DockModel.h"
#include "ThemeManager.h"
#include "WayfireIpc.h"
#include <QProcess>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QDir>
#include <QSettings>
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
#include <QSaveFile>
#include <QHash>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>

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
    Q_UNUSED(expire_timeout)
    // replaces_id: la app actualiza una notificacion suya (p. ej. progreso);
    // se quita la vieja sin avisar de cierre (no se ha cerrado, se sustituye).
    if (replaces_id > 0)
        m_backend->removeNotificationSilently(static_cast<int>(replaces_id));
    // Imagen en las pistas (notify-send -i fichero ya llega como app_icon;
    // algunas apps la mandan en image-path).
    QString icono = app_icon;
    if (icono.isEmpty())
        icono = hints.value(QStringLiteral("image-path")).toString();
    if (icono.startsWith(QStringLiteral("file://")))
        icono = QUrl(icono).toLocalFile();
    // Urgencia critica (bateria agotandose...): se ensena aunque haya No molestar.
    const bool urgente = hints.value(QStringLiteral("urgency")).toInt() >= 2;
    m_backend->notify(summary, body, icono, app_name, actions, urgente);
    return static_cast<uint>(m_backend->lastNotificationId());
}

void NotificationsAdaptor::CloseNotification(uint id)
{
    // La app la retira: motivo 3 ("cerrada con CloseNotification").
    m_backend->closeNotificationByApp(static_cast<int>(id));
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
    return titan::resolverBinario(program);
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
    // Sonido al conectar el cargador. La primera lectura no suena: solo
    // los cambios mientras la sesión está abierta.
    connect(this, &ShellBackend::batteryChanged, this, [this]() {
        const int ahora = m_hasBattery ? (m_isCharging ? 1 : 0) : -1;
        if (m_cargaPrevia == 0 && ahora == 1) {
            const QString sonido = QStringLiteral("/usr/share/sounds/freedesktop/stereo/power-plug.oga");
            if (QFile::exists(sonido))
                QProcess::startDetached(QStringLiteral("pw-play"), {sonido});
        }
        m_cargaPrevia = ahora;
    });
    m_batteryTimer->start();

    m_islandTimer = new QTimer(this);
    m_islandTimer->setSingleShot(true);
    connect(m_islandTimer, &QTimer::timeout, this, &ShellBackend::dismissIsland);

    m_workspaces = {
        QStringLiteral("Escritorio 1")
    };

    // En Wayfire el cambio de escritorio tambien puede venir del teclado
    // (Ctrl+Super+flechas, Super+N) o de un gesto: se refleja aqui sin
    // volver a pedirlo al compositor.
    if (WayfireIpc::instancia()->disponible()) {
        connect(WayfireIpc::instancia(), &WayfireIpc::escritorioCambiado, this, [this](int x) {
            if (x < 0) return;
            bool cambiaLista = false;
            while (m_workspaces.size() <= x) {
                m_workspaces.append(QStringLiteral("Escritorio ") + QString::number(m_workspaces.size() + 1));
                cambiaLista = true;
            }
            if (cambiaLista) emit workspacesChanged();
            if (m_currentWorkspace != x) {
                m_currentWorkspace = x;
                emit currentWorkspaceChanged();
            }
        });
    }

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

    m_userName = titan::usuarioActual();
    m_userDisplayName = m_userName;
    if (!m_userDisplayName.isEmpty()) m_userDisplayName[0] = m_userDisplayName[0].toUpper();

    m_bootSplashActive = true;
    m_bootSplashFinished = false;
    // Con greetd la persona ya se ha identificado en la pantalla de inicio:
    // no se le vuelve a pedir la contrasena al arrancar el escritorio.
    m_lockScreenActive = !isLiveSystem() && !canSwitchUser();
    if (m_lockScreenActive && usarBloqueoSeguro()) {
        // Entrada por consola sin pantalla de inicio: se bloquea con gtklock.
        m_lockScreenActive = false;
        QTimer::singleShot(1200, this, &ShellBackend::lockScreen);
    }

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
            n1[QStringLiteral("ssid")] = m_wifiSsid.isEmpty() ? QStringLiteral("Inti-Fiber-5G") : m_wifiSsid;
            n1[QStringLiteral("signal")] = 95;
            n1[QStringLiteral("connected")] = m_wifiConnected;
            n1[QStringLiteral("security")] = QStringLiteral("WPA2/WPA3");
            found.append(n1);

            QVariantMap n2;
            n2[QStringLiteral("ssid")] = QStringLiteral("Inti-Guest");
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
        m_dockModel->launchApp(QStringLiteral("titan-acerca"), QStringLiteral("titan-acerca"), QStringLiteral("Acerca de Inti OS"), QStringLiteral("qrc:/icons/about.png"));
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
        m_dockModel->launchApp(QStringLiteral("titan-finder"), QStringLiteral("titan-finder"), QStringLiteral("Explorador de archivos"), QStringLiteral("qrc:/icons/finder.png"));
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

void ShellBackend::toggleCalendario()
{
    m_calendarioVisible = !m_calendarioVisible;
    if (m_calendarioVisible) {
        // Uno a la vez, como en Windows (fecha y avisos van juntos ahí)
        setNotificationCenterVisible(false);
        setControlCenterVisible(false);
    }
    emit calendarioVisibleChanged();
}

void ShellBackend::closeCalendario()
{
    if (!m_calendarioVisible) return;
    m_calendarioVisible = false;
    emit calendarioVisibleChanged();
}

void ShellBackend::clearNotifications()
{
    // Motivo 2: la ha descartado el usuario (spec de notificaciones).
    for (const QVariant &v : std::as_const(m_notifications))
        emit NotificationClosed(v.toMap().value(QStringLiteral("id")).toUInt(), 2);
    m_notifications.clear();
    emit notificationsChanged();
}

bool ShellBackend::takeNotification(int id)
{
    for (int i = 0; i < m_notifications.size(); ++i) {
        if (m_notifications[i].toMap().value(QStringLiteral("id")).toInt() == id) {
            m_notifications.removeAt(i);
            emit notificationsChanged();
            if (m_islandActive && m_currentIslandNotification.value(QStringLiteral("id")).toInt() == id)
                dismissIsland();
            return true;
        }
    }
    return false;
}

void ShellBackend::removeNotification(int id)
{
    if (takeNotification(id))
        emit NotificationClosed(static_cast<uint>(id), 2);
}

void ShellBackend::removeNotificationSilently(int id)
{
    takeNotification(id);
}

void ShellBackend::closeNotificationByApp(int id)
{
    if (takeNotification(id))
        emit NotificationClosed(static_cast<uint>(id), 3);
}

void ShellBackend::invokeNotificationAction(int id, const QString &key)
{
    // Pulsar un boton (o la notificacion, accion "default") la cierra.
    emit ActionInvoked(static_cast<uint>(id), key.isEmpty() ? QStringLiteral("default") : key);
    if (takeNotification(id))
        emit NotificationClosed(static_cast<uint>(id), 2);
}

void ShellBackend::dismissIsland()
{
    if (m_islandActive) {
        m_islandActive = false;
        m_islandQueue = 0;
        emit islandChanged();
    }
}

void ShellBackend::mantenerIsla(bool encima)
{
    if (!m_islandTimer || !m_islandActive)
        return;
    if (encima)
        m_islandTimer->stop();
    else
        m_islandTimer->start(3000);
}

// ---------------------------------------------------------------- teclas
// Ejecuta un programa y espera poco: wpctl y brightnessctl tardan milisegundos.
static QString salidaDe(const QString &prog, const QStringList &args, int ms = 800)
{
    QProcess p;
    p.start(prog, args);
    if (!p.waitForFinished(ms))
        return QString();
    return QString::fromUtf8(p.readAllStandardOutput()).trimmed();
}

bool ShellBackend::leerVolumen(const QString &dispositivo, qreal *valor, bool *silencio)
{
    // "Volume: 0.45" o "Volume: 0.45 [MUTED]"
    const QString o = salidaDe(QStringLiteral("wpctl"), {QStringLiteral("get-volume"), dispositivo});
    if (!o.startsWith(QStringLiteral("Volume:")))
        return false;
    const QStringList partes = o.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    bool ok = false;
    const qreal v = partes.size() >= 2 ? partes.at(1).toDouble(&ok) : 0;
    if (!ok)
        return false;
    *valor = qBound(0.0, v, 1.0);
    *silencio = o.contains(QStringLiteral("MUTED"));
    return true;
}

bool ShellBackend::brilloRelativo(const QString &dispositivo, const QString &cambio, qreal *valor)
{
    // brightnessctl -m: "intel_backlight,backlight,412,43%,960". Va por logind,
    // asi que no hace falta root. -n 1: bajar nunca apaga del todo la pantalla.
    QStringList args{QStringLiteral("-m")};
    if (dispositivo.isEmpty())
        args << QStringLiteral("-c") << QStringLiteral("backlight");
    else
        args << QStringLiteral("-d") << dispositivo;
    if (!cambio.isEmpty())
        args << QStringLiteral("-n1") << QStringLiteral("set") << cambio;
    const QString o = salidaDe(QStringLiteral("brightnessctl"), args);
    const QStringList c = o.split(QLatin1Char('\n')).value(0).split(QLatin1Char(','));
    if (c.size() < 5)
        return false;
    const double actual = c.at(2).toDouble(), maximo = c.at(4).toDouble();
    if (maximo <= 0)
        return false;
    *valor = qBound(0.0, actual / maximo, 1.0);
    return true;
}

void ShellBackend::mostrarIndicador(const QString &tipo, qreal valor, bool silencio)
{
    m_indicador = QVariantMap{{QStringLiteral("tipo"), tipo},
                              {QStringLiteral("valor"), valor},
                              {QStringLiteral("silencio"), silencio}};
    m_indicadorActivo = true;
    if (!m_indicadorTimer) {
        m_indicadorTimer = new QTimer(this);
        m_indicadorTimer->setSingleShot(true);
        connect(m_indicadorTimer, &QTimer::timeout, this, [this]() {
            m_indicadorActivo = false;
            emit indicadorChanged();
        });
    }
    m_indicadorTimer->start(1600);
    emit indicadorChanged();
}

bool ShellBackend::altPulsada() const
{
    return QGuiApplication::queryKeyboardModifiers() & Qt::AltModifier;
}

void ShellBackend::tecla(const QString &accion)
{
    const QString salida = QStringLiteral("@DEFAULT_AUDIO_SINK@");
    const QString micro = QStringLiteral("@DEFAULT_AUDIO_SOURCE@");
    qreal v = 0;
    bool mudo = false;

    if (accion == QStringLiteral("volumen-subir") || accion == QStringLiteral("volumen-bajar")) {
        const bool sube = accion == QStringLiteral("volumen-subir");
        // -l 1.0: no pasar del 100 % (como Ubuntu y macOS)
        salidaDe(QStringLiteral("wpctl"), {QStringLiteral("set-volume"), QStringLiteral("-l"), QStringLiteral("1.0"),
                                           salida, sube ? QStringLiteral("5%+") : QStringLiteral("5%-")});
        if (sube)
            salidaDe(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), salida, QStringLiteral("0")});
        if (leerVolumen(salida, &v, &mudo)) {
            m_volume = v;
            emit volumeChanged();
            mostrarIndicador(QStringLiteral("volumen"), v, mudo);
        }
    } else if (accion == QStringLiteral("silenciar")) {
        salidaDe(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), salida, QStringLiteral("toggle")});
        if (leerVolumen(salida, &v, &mudo))
            mostrarIndicador(QStringLiteral("volumen"), v, mudo);
    } else if (accion == QStringLiteral("micro-silenciar")) {
        salidaDe(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), micro, QStringLiteral("toggle")});
        if (leerVolumen(micro, &v, &mudo))
            mostrarIndicador(QStringLiteral("micro"), v, mudo);
    } else if (accion == QStringLiteral("brillo-subir") || accion == QStringLiteral("brillo-bajar")) {
        const bool sube = accion == QStringLiteral("brillo-subir");
        if (m_hasHardwareBacklight
            && brilloRelativo(QString(), sube ? QStringLiteral("5%+") : QStringLiteral("5%-"), &v)) {
            m_brightness = qMax(0.05, v);
            emit brightnessChanged();
        } else {
            // Sin pantalla con retroiluminacion (sobremesa): monitor por DDC/CI
            setBrightness(m_brightness + (sube ? 0.1 : -0.1));
            v = m_brightness;
        }
        mostrarIndicador(QStringLiteral("brillo"), v, false);
    } else if (accion == QStringLiteral("teclado-subir") || accion == QStringLiteral("teclado-bajar")
               || accion == QStringLiteral("teclado-alternar")) {
        QString cambio = accion == QStringLiteral("teclado-subir") ? QStringLiteral("34%+")
                       : accion == QStringLiteral("teclado-bajar") ? QStringLiteral("34%-") : QString();
        const QString kbd = QStringLiteral("*::kbd_backlight");
        if (cambio.isEmpty() && brilloRelativo(kbd, QString(), &v))
            cambio = v > 0 ? QStringLiteral("0") : QStringLiteral("100%");
        // -n1 no vale aqui (apagar la luz del teclado si se puede)
        QStringList args{QStringLiteral("-m"), QStringLiteral("-d"), kbd, QStringLiteral("set"), cambio};
        const QStringList c = salidaDe(QStringLiteral("brightnessctl"), args).split(QLatin1Char(','));
        if (c.size() >= 5 && c.at(4).toDouble() > 0)
            mostrarIndicador(QStringLiteral("teclado"), c.at(2).toDouble() / c.at(4).toDouble(), false);
    } else if (accion == QStringLiteral("reproducir") || accion == QStringLiteral("pausa")
               || accion == QStringLiteral("siguiente") || accion == QStringLiteral("anterior")
               || accion == QStringLiteral("parar")) {
        static const QHash<QString, QString> orden{
            {QStringLiteral("reproducir"), QStringLiteral("play-pause")}, {QStringLiteral("pausa"), QStringLiteral("pause")},
            {QStringLiteral("siguiente"), QStringLiteral("next")}, {QStringLiteral("anterior"), QStringLiteral("previous")},
            {QStringLiteral("parar"), QStringLiteral("stop")}};
        QProcess::startDetached(QStringLiteral("playerctl"), {orden.value(accion)});
    } else if (accion == QStringLiteral("alt-tab") || accion == QStringLiteral("alt-tab-atras")) {
        emit altTab(accion == QStringLiteral("alt-tab") ? 1 : -1);
    } else if (accion == QStringLiteral("seguridad") || accion == QStringLiteral("portapapeles")
               || accion == QStringLiteral("emojis") || accion == QStringLiteral("atajos")
               || accion == QStringLiteral("proyectar") || accion == QStringLiteral("herramientas")) {
        // Ctrl+Alt+Supr siempre abre (no alterna): es la tecla de "socorro"
        if (accion == QStringLiteral("seguridad"))
            setPanel(accion);
        else
            abrirPanel(accion);
    } else if (accion == QStringLiteral("monitor")) {
        abrirApp(QStringLiteral("titan-monitor"));
    } else if (accion == QStringLiteral("calculadora")) {
        QProcess::startDetached(QStringLiteral("titan-calc"), {});
    } else if (accion == QStringLiteral("navegador")) {
        QProcess::startDetached(QStringLiteral("xdg-open"), {QStringLiteral("https://")});
    } else if (accion == QStringLiteral("correo")) {
        QProcess::startDetached(QStringLiteral("xdg-open"), {QStringLiteral("mailto:")});
    } else if (accion == QStringLiteral("archivos")) {
        QProcess::startDetached(QStringLiteral("titan-finder"), {});
    } else if (accion == QStringLiteral("ajustes")) {
        openSettings();
    } else if (accion == QStringLiteral("buscar")) {
        toggleLauncher();
    } else if (accion == QStringLiteral("bloquear")) {
        lockScreen();
    } else if (accion == QStringLiteral("pantallas")) {
        QProcess::startDetached(QStringLiteral("titan-elegir-pantalla"), {});
    }
}

void ShellBackend::setPanel(const QString &p)
{
    static const QSet<QString> validos{QString(), QStringLiteral("seguridad"), QStringLiteral("portapapeles"),
                                       QStringLiteral("emojis"), QStringLiteral("atajos"),
                                       QStringLiteral("proyectar"), QStringLiteral("herramientas")};
    if (!validos.contains(p) || p == m_panel)
        return;
    m_panel = p;
    emit panelChanged();
}

QVariantList ShellBackend::emojis()
{
    if (m_emojis.isEmpty()) {
        QFile f(QStringLiteral(":/datos/emojis.json"));
        if (f.open(QIODevice::ReadOnly))
            m_emojis = QJsonDocument::fromJson(f.readAll()).array().toVariantList();
    }
    return m_emojis;
}

void ShellBackend::abrirApp(const QString &programa)
{
    // Solo los de Inti que se abren desde los paneles del sistema
    static const QSet<QString> permitidos{QStringLiteral("titan-monitor"), QStringLiteral("titan-settings"),
                                          QStringLiteral("titan-bienvenida"), QStringLiteral("titan-manual"),
                                          QStringLiteral("titan-finder"), QStringLiteral("titan-terminal"),
                                          QStringLiteral("gnome-disks"), QStringLiteral("titan-informe")};
    if (permitidos.contains(programa))
        QProcess::startDetached(programa, {});
}

void ShellBackend::proyectar(const QString &modo)
{
    static const QSet<QString> modos{QStringLiteral("solo-esta"), QStringLiteral("duplicar"),
                                     QStringLiteral("extender"), QStringLiteral("solo-segunda")};
    if (modos.contains(modo))
        QProcess::startDetached(QStringLiteral("titan-proyectar"), {modo});
}

QString ShellBackend::estadoProyeccion() const
{
    QProcess p;
    p.start(QStringLiteral("titan-proyectar"), {QStringLiteral("estado")});
    if (!p.waitForFinished(1500))
        return QStringLiteral("1 solo-esta");
    const QString r = QString::fromUtf8(p.readAllStandardOutput()).trimmed();
    return r.isEmpty() ? QStringLiteral("1 solo-esta") : r;
}

void ShellBackend::abrirAppsInstaladas()
{
    QProcess::startDetached(QStringLiteral("plasma-discover"), {QStringLiteral("--mode"), QStringLiteral("installed")});
}

void ShellBackend::cambiarUsuarioSinCerrar()
{
    if (!canSwitchUser())
        return;
    lockScreen();
    QTimer::singleShot(900, this, [] {
        QProcess::startDetached(QStringLiteral("titan-cambiar-usuario"), {});
    });
}

void ShellBackend::setPrefs(TitanPrefs *p)
{
    m_prefs = p;
    // Cambiar en Ajustes que se ve en el bloqueo se aplica al momento.
    if (m_prefs)
        connect(m_prefs, &TitanPrefs::cambiado, this, [this]() {
            emit avisosBloqueoChanged();
            escribirAvisosBloqueo();
        });
    connect(this, &ShellBackend::notificationsChanged, this, [this]() {
        emit avisosBloqueoChanged();
        escribirAvisosBloqueo();
    });   // setPrefs se llama una sola vez (main.cpp)
    escribirAvisosBloqueo();
}

QVariantList ShellBackend::avisosBloqueo() const
{
    // Como Android: todo, sin contenido (app y hora) o nada.
    const QString modo = m_prefs ? m_prefs->s(QStringLiteral("Notificaciones/bloqueo")) : QStringLiteral("todo");
    QVariantList lista;
    if (modo == QStringLiteral("nada"))
        return lista;
    const bool contenido = modo != QStringLiteral("sinContenido")
                           && (!m_prefs || m_prefs->b(QStringLiteral("Notificaciones/vistaPrevia")));
    for (const QVariant &v : m_notifications) {
        if (lista.size() >= 30)
            break;
        const QVariantMap n = v.toMap();
        QVariantMap a;
        a[QStringLiteral("id")] = n.value(QStringLiteral("id"));
        a[QStringLiteral("appName")] = n.value(QStringLiteral("appName"));
        a[QStringLiteral("icon")] = n.value(QStringLiteral("icon"));
        a[QStringLiteral("time")] = n.value(QStringLiteral("time"));
        if (modo == QStringLiteral("sinContenido")) {
            a[QStringLiteral("title")] = QStringLiteral("Contenido oculto");
            a[QStringLiteral("message")] = QString();
        } else {
            a[QStringLiteral("title")] = n.value(QStringLiteral("title"));
            a[QStringLiteral("message")] = contenido ? n.value(QStringLiteral("message")) : QVariant(QString());
        }
        lista.append(a);
    }
    return lista;
}

// Valor de GKeyFile (lo lee el modulo de gtklock con g_key_file).
static QString valorClave(QString t)
{
    t.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
    t.replace(QLatin1Char('\n'), QStringLiteral("\\n"));
    t.replace(QLatin1Char('\r'), QStringLiteral("\\r"));
    t.replace(QLatin1Char('\t'), QStringLiteral("\\t"));
    if (t.startsWith(QLatin1Char(' ')))
        t = QStringLiteral("\\s") + t.mid(1);
    return t;
}

void ShellBackend::escribirAvisosBloqueo()
{
    // La pantalla de bloqueo segura (gtklock) es otro programa: se le pasan
    // los avisos en un fichero de XDG_RUNTIME_DIR, que solo puede leer este
    // usuario y desaparece al cerrar su sesion. Asi, al cambiar de usuario
    // nadie mas los ve.
    const QString dir = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (dir.isEmpty() || !QFileInfo(dir).isDir())
        return;
    QSaveFile f(dir + QStringLiteral("/titan-avisos-bloqueo"));
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text))
        return;
    f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    QString out = QStringLiteral("# Inti OS - avisos para la pantalla de bloqueo (titan-shell)\n");
    int i = 0;
    for (const QVariant &v : avisosBloqueo()) {
        const QVariantMap a = v.toMap();
        QString icono = a.value(QStringLiteral("icon")).toString();
        if (icono.startsWith(QStringLiteral("file://")))
            icono = QUrl(icono).toLocalFile();
        else if (!icono.startsWith(QLatin1Char('/')))
            icono.clear();   // qrc: no existe fuera del shell
        out += QStringLiteral("\n[aviso %1]\n").arg(i++);
        out += QStringLiteral("app=") + valorClave(a.value(QStringLiteral("appName")).toString()) + QLatin1Char('\n');
        out += QStringLiteral("titulo=") + valorClave(a.value(QStringLiteral("title")).toString()) + QLatin1Char('\n');
        out += QStringLiteral("texto=") + valorClave(a.value(QStringLiteral("message")).toString()) + QLatin1Char('\n');
        out += QStringLiteral("icono=") + valorClave(icono) + QLatin1Char('\n');
        out += QStringLiteral("hora=") + valorClave(a.value(QStringLiteral("time")).toString()) + QLatin1Char('\n');
    }
    f.write(out.toUtf8());
    f.commit();
}

// Clave de una app en las preferencias ('/' separaria grupos en QSettings).
static QString claveApp(const QString &app)
{
    QString k = app.isEmpty() ? QStringLiteral("Sistema") : app;
    k.replace(QLatin1Char('/'), QLatin1Char('_'));
    k.replace(QLatin1Char('\\'), QLatin1Char('_'));
    return k;
}

void ShellBackend::registrarAppNotificadora(const QString &app, const QString &icono)
{
    // Ajustes > Notificaciones ensena las apps que han avisado alguna vez.
    // Fichero aparte: shell.conf solo lo escribe Ajustes.
    QSettings s(QDir::homePath() + QStringLiteral("/.config/titan/notificaciones-apps.conf"), QSettings::IniFormat);
    const QString k = QStringLiteral("apps/") + claveApp(app);
    if (s.value(k + QStringLiteral("/nombre")).toString() == app && s.value(k + QStringLiteral("/icono")).toString() == icono)
        return;
    s.setValue(k + QStringLiteral("/nombre"), app.isEmpty() ? QStringLiteral("Sistema") : app);
    s.setValue(k + QStringLiteral("/icono"), icono);
}

void ShellBackend::setNoMolestar(bool activo)
{
    if (m_prefs)
        m_prefs->poner(QStringLiteral("Notificaciones/noMolestar"), activo);
}

void ShellBackend::notify(const QString &title, const QString &message, const QString &icon, const QString &appName,
                          const QStringList &actions, bool urgente)
{
    m_lastNotificationId++;
    // Notificaciones desactivadas para esta app en Ajustes: no se ensena nada.
    const QString clave = claveApp(appName);
    if (m_prefs && !urgente) {
        const QVariant permitir = m_prefs->v(QStringLiteral("Notificaciones/apps/") + clave);
        if (permitir.isValid() && (permitir.toString() == QStringLiteral("false") || permitir == QVariant(false))) {
            registrarAppNotificadora(appName, icon);
            return;
        }
    }
    QVariantMap n;
    n[QStringLiteral("id")] = m_lastNotificationId;
    // Acciones: lista plana [clave, texto, clave, texto...]. "default" es el
    // clic en la notificacion; no lleva boton propio.
    QVariantList botones;
    for (int i = 0; i + 1 < actions.size(); i += 2) {
        if (actions.at(i) == QStringLiteral("default")) {
            n[QStringLiteral("defaultAction")] = true;
            continue;
        }
        QVariantMap b;
        b[QStringLiteral("key")] = actions.at(i);
        b[QStringLiteral("label")] = actions.at(i + 1);
        botones.append(b);
    }
    n[QStringLiteral("actions")] = botones;
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
            resolvedIcon = titan::iconoGenerado(appName.isEmpty() ? resolvedIcon : appName, resolvedIcon);
        }
    } else if (resolvedIcon.startsWith(QLatin1Char('/')) && !titan::iconoExiste(resolvedIcon)) {
        resolvedIcon = titan::iconoGenerado(appName.isEmpty() ? QFileInfo(resolvedIcon).completeBaseName() : appName,
                                            resolvedIcon);
    }

    n[QStringLiteral("icon")] = resolvedIcon;
    n[QStringLiteral("time")] = QTime::currentTime().toString(QStringLiteral("hh:mm"));
    n[QStringLiteral("read")] = false;

    m_notifications.prepend(n);
    emit notificationsChanged();
    registrarAppNotificadora(appName, icon);

    // No molestar / Concentracion: se guarda en el centro, sin aviso ni sonido.
    if (m_prefs && m_prefs->noMolestarActivo() && !urgente)
        return;

    QVariantMap aviso = n;
    if (m_prefs && !m_prefs->b(QStringLiteral("Notificaciones/vistaPrevia")))
        aviso[QStringLiteral("message")] = QString();
    m_currentIslandNotification = aviso;
    // Si ya habia un aviso en la isla, el nuevo lo sustituye y cuenta "+N".
    m_islandQueue = m_islandActive ? m_islandQueue + 1 : 0;
    m_islandActive = true;
    emit islandChanged();

    if (m_islandTimer) {
        m_islandTimer->start(5000);
    }

    if (m_prefs && m_prefs->b(QStringLiteral("Notificaciones/sonido"))) {
        const QString sonido = QStringLiteral("/usr/share/sounds/freedesktop/stereo/message.oga");
        if (QFile::exists(sonido))
            QProcess::startDetached(QStringLiteral("pw-play"), {sonido});
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
    if (m_workspacesVisible)
        emit workspacesCloseRequested();
    else
        setWorkspacesVisible(true);
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

void ShellBackend::switchToWorkspace(int index, bool cerrarVista)
{
    if (index >= 0 && index < m_workspaces.size()) {
        m_currentWorkspace = index;
        emit currentWorkspaceChanged();
        if (!WayfireIpc::instancia()->irAEscritorio(index)) {
            // labwc: GoToDesktop va atado a Super+N en rc.xml.
            QString cmd = QStringLiteral("wtype -M logo -k %1 -m logo 2>/dev/null || wtype -M win -k %1 -m win 2>/dev/null").arg(index + 1);
            QProcess::startDetached(QStringLiteral("sh"), {QStringLiteral("-c"), cmd});
        }
        if (cerrarVista)
            setWorkspacesVisible(false);
    }
}

void ShellBackend::updateDockMask(QObject *windowObj, int x, int y, int w, int h, bool isMaximized, bool isRevealed, bool hasPopup,
                                  const QString &posicion)
{
    auto *win = qobject_cast<QQuickWindow*>(windowObj);
    if (!win) return;

    QRegion region;
    if (hasPopup) {
        // Al abrir un menú contextual en el Dock, la ventana completa recibe eventos
        // para interactuar con las opciones o cerrarlo al hacer clic fuera
        region = QRegion(0, 0, win->width(), win->height());
    } else if (isMaximized && !isRevealed) {
        // Tira de activación ultrafina (3 px) en el centro del borde del Dock
        if (posicion == QStringLiteral("izquierda") || posicion == QStringLiteral("derecha")) {
            int trigH = qMin(win->height(), 600);
            int trigY = (win->height() - trigH) / 2;
            region = QRegion(posicion == QStringLiteral("izquierda") ? 0 : win->width() - 3, trigY, 3, trigH);
        } else {
            int trigW = qMin(win->width(), 600);
            int trigX = (win->width() - trigW) / 2;
            region = QRegion(trigX, win->height() - 3, trigW, 3);
        }
    } else {
        // Solo el área física del Dock y su margen inmediato (para que las ventanas detrás reciban clics normalmente)
        if (w > 0 && h > 0) {
            region = QRegion(x, y, w, h);
        }
    }
    win->setMask(region);
}

bool ShellBackend::canSwitchUser() const
{
    return !qEnvironmentVariableIsEmpty("TITAN_DESDE_GREETD");
}

void ShellBackend::switchUser()
{
    // Termina esta sesion (se cierran sus apps); greetd vuelve a mostrar la
    // pantalla de inicio con todas las cuentas.
    if (!canSwitchUser())
        return;
    // Los avisos de esta sesion no deben verse en la de otro usuario.
    const QString dir = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (!dir.isEmpty())
        QFile::remove(dir + QStringLiteral("/titan-avisos-bloqueo"));
    const QString sesion = qEnvironmentVariable("XDG_SESSION_ID");
    QStringList args{QStringLiteral("terminate-session")};
    if (!sesion.isEmpty())
        args << sesion;
    QProcess::startDetached(QStringLiteral("loginctl"), args);
}

bool ShellBackend::isLiveSystem() const
{
    // Solo /run/archiso: lo crea el arranque del live y no existe en un
    // sistema instalado. Antes tambien valia /etc/titan-build.env, pero el
    // instalador copia ese fichero al disco, y en el sistema instalado el
    // bloqueo aceptaba cualquier contrasena.
    return QFile::exists(QStringLiteral("/run/archiso"));
}

bool ShellBackend::usarBloqueoSeguro() const
{
    return !isLiveSystem() &&
           QFile::exists(QStringLiteral("/usr/local/bin/titan-bloquear")) &&
           QFile::exists(QStringLiteral("/usr/bin/gtklock"));
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
    // Bloqueo de verdad (ext-session-lock con gtklock): lo garantiza el
    // compositor y no depende de que titan-shell siga vivo. La pantalla de
    // bloqueo en QML queda solo para el live o si falta gtklock.
    if (usarBloqueoSeguro()) {
        QProcess::startDetached(QStringLiteral("/usr/local/bin/titan-bloquear"), {});
        return;
    }
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

