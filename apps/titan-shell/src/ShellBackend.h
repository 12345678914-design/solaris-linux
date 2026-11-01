#ifndef SHELLBACKEND_H
#define SHELLBACKEND_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariant>

class ShellBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool launcherVisible READ launcherVisible WRITE setLauncherVisible NOTIFY launcherVisibleChanged)
    Q_PROPERTY(bool wallpaperPickerVisible READ wallpaperPickerVisible WRITE setWallpaperPickerVisible NOTIFY wallpaperPickerVisibleChanged)
    Q_PROPERTY(bool controlCenterVisible READ controlCenterVisible WRITE setControlCenterVisible NOTIFY controlCenterVisibleChanged)
    Q_PROPERTY(bool splashVisible READ splashVisible NOTIFY splashVisibleChanged)
    Q_PROPERTY(QString splashName READ splashName NOTIFY splashChanged)
    Q_PROPERTY(QString splashIcon READ splashIcon NOTIFY splashChanged)
    Q_PROPERTY(int splashWidth READ splashWidth NOTIFY splashSizeChanged)
    Q_PROPERTY(int splashHeight READ splashHeight NOTIFY splashSizeChanged)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled WRITE setWifiEnabled NOTIFY wifiStatusChanged)
    Q_PROPERTY(bool wifiConnected READ wifiConnected WRITE setWifiConnected NOTIFY wifiStatusChanged)
    Q_PROPERTY(QString wifiSsid READ wifiSsid NOTIFY wifiStatusChanged)
    Q_PROPERTY(bool bluetoothEnabled READ bluetoothEnabled WRITE setBluetoothEnabled NOTIFY bluetoothStatusChanged)
    Q_PROPERTY(bool bluetoothConnected READ bluetoothConnected WRITE setBluetoothConnected NOTIFY bluetoothStatusChanged)
    Q_PROPERTY(int batteryPercent READ batteryPercent NOTIFY batteryChanged)
    Q_PROPERTY(bool isCharging READ isCharging NOTIFY batteryChanged)
    Q_PROPERTY(bool hasBattery READ hasBattery NOTIFY batteryChanged)
    Q_PROPERTY(bool lowBatteryAlert READ lowBatteryAlert NOTIFY batteryChanged)
    Q_PROPERTY(QVariantList wallpapers READ wallpapers NOTIFY wallpapersChanged)
    Q_PROPERTY(QString currentWallpaper READ currentWallpaper NOTIFY currentWallpaperChanged)
    
public:
    explicit ShellBackend(QObject *parent = nullptr);
    
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

    bool bluetoothEnabled() const { return m_bluetoothEnabled; }
    void setBluetoothEnabled(bool enabled);
    bool bluetoothConnected() const { return m_bluetoothConnected; }
    void setBluetoothConnected(bool connected);

    Q_INVOKABLE void toggleWifi();
    Q_INVOKABLE void toggleBluetooth();

    QVariantList wallpapers() const;
    QString currentWallpaper() const;
    
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

    Q_INVOKABLE void showSplash(const QString &name, const QString &icon, const QString &exec = QString());
    Q_INVOKABLE void hideSplash();
    
    Q_INVOKABLE void launchApp(const QString &appId, const QString &exec);
    Q_INVOKABLE void openAcerca();
    Q_INVOKABLE void openSettings(const QString &section = QString());
    Q_INVOKABLE void openTerminal();
    Q_INVOKABLE void openFinder();
    Q_INVOKABLE void reboot();
    Q_INVOKABLE void powerOff();
    
    int batteryPercent() const;
    bool isCharging() const;
    bool hasBattery() const;
    bool lowBatteryAlert() const;
    Q_INVOKABLE void dismissBatteryAlert();

signals:
    void launcherVisibleChanged();
    void wallpaperPickerVisibleChanged();
    void controlCenterVisibleChanged();
    void splashVisibleChanged();
    void splashChanged();
    void splashSizeChanged();
    void wifiStatusChanged();
    void bluetoothStatusChanged();
    void batteryChanged();
    void wallpapersChanged();
    void currentWallpaperChanged();
    
private:
    void updateBatteryStatus();

    bool m_launcherVisible = false;
    bool m_wallpaperPickerVisible = false;
    bool m_controlCenterVisible = false;
    bool m_splashVisible = false;
    QString m_splashName;
    QString m_splashIcon;
    int m_splashWidth = 800;
    int m_splashHeight = 520;
    bool m_wifiEnabled = true;
    bool m_wifiConnected = true;
    QString m_wifiSsid = QStringLiteral("Titan-Net");
    bool m_bluetoothEnabled = true;
    bool m_bluetoothConnected = false;
    class QTimer *m_splashTimer = nullptr;
    class QTimer *m_batteryTimer = nullptr;
    int m_batteryPercent = 100;
    bool m_isCharging = true;
    bool m_hasBattery = false;
    bool m_lowBatteryAlert = false;
    bool m_batteryAlertDismissed = false;
};

#endif
