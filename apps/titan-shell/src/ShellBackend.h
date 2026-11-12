#ifndef SHELLBACKEND_H
#define SHELLBACKEND_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariant>
#include <QVariantMap>
#include <QDBusAbstractAdaptor>

class DockModel;
class ShellBackend;

class NotificationsAdaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")
public:
    explicit NotificationsAdaptor(ShellBackend *parent);

public slots:
    uint Notify(const QString &app_name, uint replaces_id, const QString &app_icon,
                const QString &summary, const QString &body, const QStringList &actions,
                const QVariantMap &hints, int expire_timeout);
    void CloseNotification(uint id);
    QStringList GetCapabilities();
    void GetServerInformation(QString &name, QString &vendor, QString &version, QString &spec_version);

signals:
    void NotificationClosed(uint id, uint reason);
    void ActionInvoked(uint id, const QString &action_key);

private:
    ShellBackend *m_backend;
};

class ShellBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool launcherVisible READ launcherVisible WRITE setLauncherVisible NOTIFY launcherVisibleChanged)
    Q_PROPERTY(bool wallpaperPickerVisible READ wallpaperPickerVisible WRITE setWallpaperPickerVisible NOTIFY wallpaperPickerVisibleChanged)
    Q_PROPERTY(bool controlCenterVisible READ controlCenterVisible WRITE setControlCenterVisible NOTIFY controlCenterVisibleChanged)
    Q_PROPERTY(int controlCenterPage READ controlCenterPage WRITE setControlCenterPage NOTIFY controlCenterPageChanged)
    Q_PROPERTY(bool splashVisible READ splashVisible NOTIFY splashVisibleChanged)
    Q_PROPERTY(QString splashName READ splashName NOTIFY splashChanged)
    Q_PROPERTY(QString splashIcon READ splashIcon NOTIFY splashChanged)
    Q_PROPERTY(int splashWidth READ splashWidth NOTIFY splashSizeChanged)
    Q_PROPERTY(int splashHeight READ splashHeight NOTIFY splashSizeChanged)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled WRITE setWifiEnabled NOTIFY wifiStatusChanged)
    Q_PROPERTY(bool wifiConnected READ wifiConnected WRITE setWifiConnected NOTIFY wifiStatusChanged)
    Q_PROPERTY(QString wifiSsid READ wifiSsid NOTIFY wifiStatusChanged)
    Q_PROPERTY(QVariantList wifiNetworks READ wifiNetworks NOTIFY wifiNetworksChanged)
    Q_PROPERTY(bool wifiScanning READ wifiScanning NOTIFY wifiScanningChanged)
    Q_PROPERTY(bool bluetoothEnabled READ bluetoothEnabled WRITE setBluetoothEnabled NOTIFY bluetoothStatusChanged)
    Q_PROPERTY(bool bluetoothConnected READ bluetoothConnected WRITE setBluetoothConnected NOTIFY bluetoothStatusChanged)
    Q_PROPERTY(QString connectedBluetoothDevice READ connectedBluetoothDevice NOTIFY bluetoothStatusChanged)
    Q_PROPERTY(QVariantList bluetoothDevices READ bluetoothDevices NOTIFY bluetoothDevicesChanged)
    Q_PROPERTY(bool bluetoothScanning READ bluetoothScanning NOTIFY bluetoothScanningChanged)
    Q_PROPERTY(int batteryPercent READ batteryPercent NOTIFY batteryChanged)
    Q_PROPERTY(bool isCharging READ isCharging NOTIFY batteryChanged)
    Q_PROPERTY(bool hasBattery READ hasBattery NOTIFY batteryChanged)
    Q_PROPERTY(bool lowBatteryAlert READ lowBatteryAlert NOTIFY batteryChanged)
    Q_PROPERTY(bool hasHardwareBacklight READ hasHardwareBacklight NOTIFY brightnessChanged)
    Q_PROPERTY(bool ethernetConnected READ ethernetConnected NOTIFY ethernetStatusChanged)
    Q_PROPERTY(QString ethernetInterface READ ethernetInterface NOTIFY ethernetStatusChanged)
    Q_PROPERTY(bool prioritizeEthernet READ prioritizeEthernet WRITE setPrioritizeEthernet NOTIFY prioritizeEthernetChanged)
    Q_PROPERTY(bool wifiSuspendedForEthernet READ wifiSuspendedForEthernet NOTIFY wifiStatusChanged)
    Q_PROPERTY(qreal brightness READ brightness WRITE setBrightness NOTIFY brightnessChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(QVariantList wallpapers READ wallpapers NOTIFY wallpapersChanged)
    Q_PROPERTY(QString currentWallpaper READ currentWallpaper NOTIFY currentWallpaperChanged)
    Q_PROPERTY(QString blurredWallpaper READ blurredWallpaper NOTIFY blurredWallpaperChanged)
    Q_PROPERTY(QVariantList notifications READ notifications NOTIFY notificationsChanged)
    Q_PROPERTY(int unreadNotificationCount READ unreadNotificationCount NOTIFY notificationsChanged)
    Q_PROPERTY(bool notificationCenterVisible READ notificationCenterVisible WRITE setNotificationCenterVisible NOTIFY notificationCenterVisibleChanged)
    Q_PROPERTY(bool islandActive READ islandActive NOTIFY islandChanged)
    Q_PROPERTY(QVariantMap currentIslandNotification READ currentIslandNotification NOTIFY islandChanged)
    Q_PROPERTY(int islandQueueCount READ islandQueueCount NOTIFY islandChanged)
    Q_PROPERTY(bool workspacesVisible READ workspacesVisible WRITE setWorkspacesVisible NOTIFY workspacesVisibleChanged)
    Q_PROPERTY(QStringList workspaces READ workspaces NOTIFY workspacesChanged)
    Q_PROPERTY(int currentWorkspace READ currentWorkspace NOTIFY currentWorkspaceChanged)
    Q_PROPERTY(bool bootSplashActive READ bootSplashActive NOTIFY bootSplashActiveChanged)
    Q_PROPERTY(bool bootSplashFinished READ bootSplashFinished NOTIFY bootSplashFinishedChanged)
    Q_PROPERTY(bool lockScreenActive READ lockScreenActive NOTIFY lockScreenActiveChanged)
    Q_PROPERTY(QString userName READ userName CONSTANT)
    Q_PROPERTY(QString userDisplayName READ userDisplayName CONSTANT)
    Q_PROPERTY(bool isLiveSystem READ isLiveSystem CONSTANT)
    
public:
    explicit ShellBackend(QObject *parent = nullptr);
    
    void setDockModel(DockModel *dockModel) { m_dockModel = dockModel; }
    DockModel *dockModel() const { return m_dockModel; }

    bool launcherVisible() const;
    void setLauncherVisible(bool visible);

    bool wallpaperPickerVisible() const;
    void setWallpaperPickerVisible(bool visible);

    bool controlCenterVisible() const;
    void setControlCenterVisible(bool visible);

    bool splashVisible() const;
    QString splashName() const;
    QString splashIcon() const;
    int splashWidth() const { return m_splashWidth; }
    int splashHeight() const { return m_splashHeight; }

    bool wifiEnabled() const { return m_wifiEnabled; }
    void setWifiEnabled(bool enabled);
    bool wifiConnected() const { return m_wifiConnected; }
    void setWifiConnected(bool connected);
    QString wifiSsid() const { return m_wifiSsid; }
    QVariantList wifiNetworks() const { return m_wifiNetworks; }
    bool wifiScanning() const { return m_wifiScanning; }
    bool hasWifiAdapter() const;

    bool bluetoothEnabled() const { return m_bluetoothEnabled; }
    void setBluetoothEnabled(bool enabled);
    bool bluetoothConnected() const { return m_bluetoothConnected; }
    void setBluetoothConnected(bool connected);
    QString connectedBluetoothDevice() const { return m_connectedBluetoothDevice; }
    QVariantList bluetoothDevices() const { return m_bluetoothDevices; }
    bool bluetoothScanning() const { return m_bluetoothScanning; }

    Q_INVOKABLE void toggleWifi();
    Q_INVOKABLE void toggleBluetooth();
    Q_INVOKABLE void scanWifi();
    Q_INVOKABLE void connectWifi(const QString &ssid, const QString &password = QString());
    Q_INVOKABLE void disconnectWifi();
    Q_INVOKABLE void scanBluetooth();
    Q_INVOKABLE void connectBluetooth(const QString &mac);
    Q_INVOKABLE void disconnectBluetooth(const QString &mac);

    QVariantList wallpapers() const;
    QString currentWallpaper() const;
    QString blurredWallpaper() const { return QString(); }
    
    Q_INVOKABLE void toggleLauncher();
    Q_INVOKABLE void openLauncher();
    Q_INVOKABLE void closeLauncher();

    Q_INVOKABLE void toggleWallpaperPicker();
    Q_INVOKABLE void openWallpaperPicker();
    Q_INVOKABLE void closeWallpaperPicker();
    Q_INVOKABLE void setWallpaper(const QString &path);
    Q_INVOKABLE void toggleTheme();

    Q_INVOKABLE void toggleControlCenter();
    Q_INVOKABLE void openControlCenter();
    Q_INVOKABLE void closeControlCenter();
    int controlCenterPage() const { return m_controlCenterPage; }
    void setControlCenterPage(int page);
    Q_INVOKABLE void openControlCenterWifi();
    Q_INVOKABLE void openControlCenterBluetooth();

    Q_INVOKABLE void showSplash(const QString &name, const QString &icon, const QString &exec = QString());
    Q_INVOKABLE void hideSplash();
    
    Q_INVOKABLE void launchApp(const QString &appId, const QString &exec);
    Q_INVOKABLE void openAcerca();
    Q_INVOKABLE void openSettings(const QString &section = QString());
    Q_INVOKABLE void openTerminal();

    QVariantList notifications() const { return m_notifications; }
    int unreadNotificationCount() const;
    int lastNotificationId() const { return m_lastNotificationId; }
    bool notificationCenterVisible() const { return m_notificationCenterVisible; }
    void setNotificationCenterVisible(bool visible);
    bool islandActive() const { return m_islandActive; }
    QVariantMap currentIslandNotification() const { return m_currentIslandNotification; }
    int islandQueueCount() const { return 0; }

    Q_INVOKABLE void toggleNotificationCenter();
    Q_INVOKABLE void closeNotificationCenter();
    Q_INVOKABLE void clearNotifications();
    Q_INVOKABLE void removeNotification(int id);
    Q_INVOKABLE void dismissIsland();
    Q_INVOKABLE void notify(const QString &title, const QString &message, const QString &icon = QString(), const QString &appName = QString());
    Q_INVOKABLE void openFinder();
    Q_INVOKABLE void suspend();
    Q_INVOKABLE void reboot();
    Q_INVOKABLE void powerOff();

    bool workspacesVisible() const { return m_workspacesVisible; }
    void setWorkspacesVisible(bool visible);
    QStringList workspaces() const { return m_workspaces; }
    int currentWorkspace() const { return m_currentWorkspace; }
    Q_INVOKABLE void toggleWorkspaces();
    Q_INVOKABLE void addWorkspace();
    Q_INVOKABLE void removeWorkspace(int index);
    Q_INVOKABLE void switchToWorkspace(int index);
    Q_INVOKABLE void updateDockMask(QObject *windowObj, int x, int y, int w, int h, bool isMaximized, bool isRevealed, bool hasPopup = false);
    
    bool bootSplashActive() const { return m_bootSplashActive; }
    bool bootSplashFinished() const { return m_bootSplashFinished; }
    bool lockScreenActive() const { return m_lockScreenActive; }
    QString userName() const { return m_userName; }
    QString userDisplayName() const { return m_userDisplayName; }
    bool isLiveSystem() const;

    Q_INVOKABLE void finishBootSplash();
    Q_INVOKABLE void lockScreen();
    Q_INVOKABLE void unlockScreen();
    Q_INVOKABLE bool authenticateLock(const QString &password);

    int batteryPercent() const;
    bool isCharging() const;
    bool hasBattery() const;
    bool lowBatteryAlert() const;
    Q_INVOKABLE void dismissBatteryAlert();
    Q_INVOKABLE void setSimulatedBattery(int percent, bool charging);

    bool hasHardwareBacklight() const { return m_hasHardwareBacklight; }

    bool ethernetConnected() const { return m_ethernetConnected; }
    QString ethernetInterface() const { return m_ethernetInterface; }
    bool prioritizeEthernet() const { return m_prioritizeEthernet; }
    void setPrioritizeEthernet(bool prioritize);
    bool wifiSuspendedForEthernet() const { return m_wifiSuspendedForEthernet; }
    Q_INVOKABLE void togglePrioritizeEthernet();

    qreal brightness() const { return m_brightness; }
    Q_INVOKABLE void setBrightness(qreal level);

    qreal volume() const { return m_volume; }
    Q_INVOKABLE void setVolume(qreal level);

signals:
    void launcherVisibleChanged();
    void wallpaperPickerVisibleChanged();
    void controlCenterVisibleChanged();
    void controlCenterPageChanged();
    void splashVisibleChanged();
    void splashChanged();
    void splashSizeChanged();
    void wifiStatusChanged();
    void wifiNetworksChanged();
    void wifiScanningChanged();
    void ethernetStatusChanged();
    void prioritizeEthernetChanged();
    void bluetoothStatusChanged();
    void bluetoothDevicesChanged();
    void bluetoothScanningChanged();
    void batteryChanged();
    void brightnessChanged();
    void volumeChanged();
    void wallpapersChanged();
    void currentWallpaperChanged();
    void blurredWallpaperChanged();
    void notificationsChanged();
    void notificationCenterVisibleChanged();
    void islandChanged();
    void workspacesVisibleChanged();
    void workspacesChanged();
    void currentWorkspaceChanged();
    void bootSplashActiveChanged();
    void bootSplashFinishedChanged();
    void lockScreenActiveChanged();
    
private:
    void updateBatteryStatus();
    void syncHardwareStatus();

    bool m_bootSplashActive = true;
    bool m_bootSplashFinished = false;
    bool m_lockScreenActive = false;
    QString m_userName;
    QString m_userDisplayName;

    bool m_launcherVisible = false;
    bool m_wallpaperPickerVisible = false;
    bool m_controlCenterVisible = false;
    bool m_splashVisible = false;
    QString m_splashName;
    QString m_splashIcon;
    int m_splashWidth = 800;
    int m_splashHeight = 520;
    bool m_wifiEnabled = true;
    bool m_wifiConnected = false;
    bool m_wifiSuspendedForEthernet = false;
    int m_controlCenterPage = 0;
    bool m_ethernetConnected = false;
    QString m_ethernetInterface;
    bool m_prioritizeEthernet = true;
    bool m_hasHardwareBacklight = false;
    QString m_wifiSsid;
    QVariantList m_wifiNetworks;
    bool m_wifiScanning = false;
    bool m_bluetoothEnabled = true;
    bool m_bluetoothConnected = false;
    QString m_connectedBluetoothDevice = QStringLiteral("Solaris Sound Air");
    QVariantList m_bluetoothDevices;
    bool m_bluetoothScanning = false;
    qreal m_brightness = 0.85;
    qreal m_volume = 0.70;
    class QTimer *m_splashTimer = nullptr;
    class QTimer *m_batteryTimer = nullptr;
    int m_batteryPercent = 100;
    bool m_isCharging = true;
    bool m_hasBattery = false;
    bool m_lowBatteryAlert = false;
    bool m_batteryAlertDismissed = false;
    bool m_simulatedBattery = false;
    DockModel *m_dockModel = nullptr;

    QVariantList m_notifications;
    bool m_notificationCenterVisible = false;
    bool m_workspacesVisible = false;
    QStringList m_workspaces;
    int m_currentWorkspace = 0;
    bool m_islandActive = false;
    QVariantMap m_currentIslandNotification;
    class QTimer *m_islandTimer = nullptr;
    int m_lastNotificationId = 0;
};

#endif
