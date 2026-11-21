#ifndef SETTINGSBACKEND_H
#define SETTINGSBACKEND_H

class QTimer;
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class SettingsBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentSection READ currentSection WRITE setCurrentSection NOTIFY currentSectionChanged)
    Q_PROPERTY(QString searchQuery READ searchQuery WRITE setSearchQuery NOTIFY searchQueryChanged)
    Q_PROPERTY(QVariantList sections READ sections NOTIFY sectionsChanged)
    Q_PROPERTY(bool isDark READ isDark WRITE setIsDark NOTIFY themeChanged)
    Q_PROPERTY(QString accent READ accent WRITE setAccent NOTIFY themeChanged)
    Q_PROPERTY(QString currentWallpaper READ currentWallpaper NOTIFY wallpaperChanged)
    Q_PROPERTY(QVariantList wallpapers READ wallpapers NOTIFY wallpapersChanged)
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)
    Q_PROPERTY(QString languageStatus READ languageStatus NOTIFY languageChanged)
    Q_PROPERTY(bool dockEnabled READ dockEnabled WRITE setDockEnabled NOTIFY shellSettingsChanged)
    Q_PROPERTY(bool topBarEnabled READ topBarEnabled WRITE setTopBarEnabled NOTIFY shellSettingsChanged)
    Q_PROPERTY(QVariantMap systemInfo READ systemInfo CONSTANT)
    Q_PROPERTY(QString updateStatus READ updateStatus NOTIFY updateStatusChanged)
    Q_PROPERTY(bool updateChecking READ updateChecking NOTIFY updateCheckingChanged)
    Q_PROPERTY(bool updatePromptVisible READ updatePromptVisible NOTIFY updatePromptVisibleChanged)
    Q_PROPERTY(int updateCount READ updateCount NOTIFY updateCountChanged)
    Q_PROPERTY(QString updateSize READ updateSize NOTIFY updateSizeChanged)
    // Actualización en curso (titan-actualizar-sistema): barra, registro, reinicio
    Q_PROPERTY(bool updateRunning READ updateRunning NOTIFY updateProgressChanged)
    Q_PROPERTY(double updateProgress READ updateProgress NOTIFY updateProgressChanged)
    Q_PROPERTY(QString updateLog READ updateLog NOTIFY updateLogChanged)
    Q_PROPERTY(QString updateResult READ updateResult NOTIFY updateProgressChanged)
    Q_PROPERTY(bool updateNeedsReboot READ updateNeedsReboot NOTIFY updateProgressChanged)
    // Avisos de Arch que afectan a este equipo (antes de actualizar)
    Q_PROPERTY(QVariantList updateNews READ updateNews NOTIFY updateNewsChanged)
    // "estable" (Arch de hace 7 días) | "al-dia"
    Q_PROPERTY(QString updateMode READ updateMode NOTIFY updateModeChanged)

    // Wi-Fi
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled WRITE setWifiEnabled NOTIFY wifiStatusChanged)
    Q_PROPERTY(bool wifiConnected READ wifiConnected NOTIFY wifiStatusChanged)
    Q_PROPERTY(QString wifiSsid READ wifiSsid NOTIFY wifiStatusChanged)
    Q_PROPERTY(bool wifiScanning READ wifiScanning NOTIFY wifiScanningChanged)
    Q_PROPERTY(QVariantList wifiNetworks READ wifiNetworks NOTIFY wifiNetworksChanged)

    // Bluetooth
    Q_PROPERTY(bool bluetoothEnabled READ bluetoothEnabled WRITE setBluetoothEnabled NOTIFY bluetoothStatusChanged)
    Q_PROPERTY(bool bluetoothConnected READ bluetoothConnected NOTIFY bluetoothStatusChanged)
    Q_PROPERTY(QString connectedBluetoothDevice READ connectedBluetoothDevice NOTIFY bluetoothStatusChanged)
    Q_PROPERTY(bool bluetoothScanning READ bluetoothScanning NOTIFY bluetoothScanningChanged)
    Q_PROPERTY(QVariantList bluetoothDevices READ bluetoothDevices NOTIFY bluetoothDevicesChanged)

public:
    explicit SettingsBackend(QObject *parent = nullptr);
    ~SettingsBackend() override = default;

    QString currentSection() const { return m_currentSection; }
    void setCurrentSection(const QString &section);

    QString searchQuery() const { return m_searchQuery; }
    void setSearchQuery(const QString &query);

    QVariantList sections() const;

    bool isDark() const;
    void setIsDark(bool dark);

    QString accent() const;
    void setAccent(const QString &accent);

    QString currentWallpaper() const;
    QVariantList wallpapers() const;

    QString language() const { return m_language; }
    QString languageStatus() const { return m_languageStatus; }
    void setLanguage(const QString &lang);

    bool dockEnabled() const { return m_dockEnabled; }
    void setDockEnabled(bool enabled);

    bool topBarEnabled() const { return m_topBarEnabled; }
    void setTopBarEnabled(bool enabled);

    QVariantMap systemInfo() const { return m_systemInfo; }
    QString updateStatus() const { return m_updateStatus; }
    bool updateChecking() const { return m_updateChecking; }
    bool updatePromptVisible() const { return m_updatePromptVisible; }
    int updateCount() const { return m_updateCount; }
    QString updateSize() const { return m_updateSize; }
    bool updateRunning() const { return m_updateRunning; }
    double updateProgress() const { return m_updateProgress; }
    QString updateLog() const { return m_updateLogLines.join(QLatin1Char('\n')); }
    QString updateResult() const { return m_updateResult; }
    bool updateNeedsReboot() const { return m_updateNeedsReboot; }
    QVariantList updateNews() const { return m_updateNews; }
    QString updateMode() const { return m_updateMode; }

    // Wi-Fi
    bool wifiEnabled() const { return m_wifiEnabled; }
    void setWifiEnabled(bool enabled);
    bool wifiConnected() const { return m_wifiConnected; }
    QString wifiSsid() const { return m_wifiSsid; }
    bool wifiScanning() const { return m_wifiScanning; }
    QVariantList wifiNetworks() const { return m_wifiNetworks; }

    // Bluetooth
    bool bluetoothEnabled() const { return m_bluetoothEnabled; }
    void setBluetoothEnabled(bool enabled);
    bool bluetoothConnected() const { return m_bluetoothConnected; }
    QString connectedBluetoothDevice() const { return m_connectedBluetoothDevice; }
    bool bluetoothScanning() const { return m_bluetoothScanning; }
    QVariantList bluetoothDevices() const { return m_bluetoothDevices; }

    Q_INVOKABLE void setThemeMode(const QString &mode); // "light", "dark", "auto"
    Q_INVOKABLE void setWallpaper(const QString &path);
    Q_INVOKABLE void checkUpdates();
    // Con avisos de Arch pendientes primero los enseña; ignorarAvisos = "Actualizar igualmente"
    Q_INVOKABLE void installUpdates(bool ignorarAvisos = false);
    Q_INVOKABLE void setUpdateMode(const QString &modo);
    Q_INVOKABLE void cancelUpdates();
    Q_INVOKABLE void rebootNow();

    Q_INVOKABLE void scanWifi();
    Q_INVOKABLE void connectWifi(const QString &ssid, const QString &password = QString());
    Q_INVOKABLE void disconnectWifi();

    Q_INVOKABLE void scanBluetooth();
    Q_INVOKABLE void connectBluetooth(const QString &mac);
    Q_INVOKABLE void disconnectBluetooth(const QString &mac);

signals:
    void currentSectionChanged();
    void searchQueryChanged();
    void sectionsChanged();
    void themeChanged();
    void wallpaperChanged();
    void wallpapersChanged();
    void languageChanged();
    void shellSettingsChanged();
    void updateStatusChanged();
    void updateCheckingChanged();
    void updatePromptVisibleChanged();
    void updateCountChanged();
    void updateSizeChanged();
    void updateProgressChanged();
    void updateLogChanged();
    void updateNewsChanged();
    void updateModeChanged();

    void wifiStatusChanged();
    void wifiScanningChanged();
    void wifiNetworksChanged();

    void bluetoothStatusChanged();
    void bluetoothScanningChanged();
    void bluetoothDevicesChanged();

private:
    void initSections();
    void loadShellSettings();
    void saveShellSettings();
    void loadSystemInfo();
    void updateNetworkStatus();

    QString m_currentSection = QStringLiteral("General");
    QString m_searchQuery;
    QVariantList m_allSections;
    QString m_language = QStringLiteral("auto");
    QString m_languageStatus;
    bool m_languageBusy = false;
    void applyUserLanguage(const QString &lang, const QString &codigo);
    bool m_dockEnabled = true;
    bool m_topBarEnabled = true;
    QVariantMap m_systemInfo;
    QString m_updateStatus = QStringLiteral("El sistema está actualizado");
    bool m_updateChecking = false;
    bool m_updatePromptVisible = false;
    int m_updateCount = 0;
    QString m_updateSize = QStringLiteral("0 MB");
    bool m_updateRunning = false;
    double m_updateProgress = 0;
    QString m_updateResult;          // "" | "ok" | "error"
    bool m_updateNeedsReboot = false;
    QStringList m_updateLogLines;
    QTimer *m_updateTimer = nullptr;
    qint64 m_updateOffset = 0;
    QByteArray m_updatePartial;
    int m_updateDownloads = 0;
    int m_updateIdle = 0;
    QVariantList m_updateNews;
    QString m_updateMode = QStringLiteral("estable");
    void startUpdate();
    void readUpdateMode();
    void followUpdate();
    void readUpdateLog();
    void appendUpdateLine(const QString &linea);
    void finishUpdate(bool ok, const QString &texto);

    // Wi-Fi
    bool m_wifiEnabled = true;
    bool m_wifiConnected = false;
    QString m_wifiSsid;
    bool m_wifiScanning = false;
    QVariantList m_wifiNetworks;

    // Bluetooth
    bool m_bluetoothEnabled = true;
    bool m_bluetoothConnected = false;
    QString m_connectedBluetoothDevice;
    bool m_bluetoothScanning = false;
    QVariantList m_bluetoothDevices;
};

#endif // SETTINGSBACKEND_H

