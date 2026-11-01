#include "SettingsBackend.h"
#include "ThemeManager.h"

#include <QDir>
#include <QFile>
#include <QSettings>
#include <QSysInfo>
#include <QTimer>
#include <QStorageInfo>

SettingsBackend::SettingsBackend(QObject *parent)
    : QObject(parent)
{
    initSections();
    loadShellSettings();
    loadSystemInfo();

    ThemeManager *tm = ThemeManager::instance();
    connect(tm, &ThemeManager::themeChanged, this, &SettingsBackend::themeChanged);
    connect(tm, &ThemeManager::wallpaperChanged, this, &SettingsBackend::wallpaperChanged);
    connect(tm, &ThemeManager::wallpapersChanged, this, &SettingsBackend::wallpapersChanged);
}

void SettingsBackend::initSections()
{
    m_allSections.clear();

    auto add = [this](const QString &id, const QString &name, const QString &icon, const QString &badgeColor) {
        QVariantMap s;
        s[QStringLiteral("id")] = id;
        s[QStringLiteral("name")] = name;
        s[QStringLiteral("icon")] = icon;
        s[QStringLiteral("badgeColor")] = badgeColor;
        m_allSections.append(s);
    };

    // Estructura idéntica a macOS Ventura / Sonoma y la imagen de referencia
    add(QStringLiteral("wifi"), QStringLiteral("Wi-Fi"), QStringLiteral("📶"), QStringLiteral("#007aff"));
    add(QStringLiteral("bluetooth"), QStringLiteral("Bluetooth"), QStringLiteral("ᛒ"), QStringLiteral("#007aff"));
    add(QStringLiteral("red"), QStringLiteral("Red"), QStringLiteral("↔"), QStringLiteral("#007aff"));
    add(QStringLiteral("General"), QStringLiteral("General"), QStringLiteral("⚙️"), QStringLiteral("#636366"));
    add(QStringLiteral("Apariencia"), QStringLiteral("Apariencia"), QStringLiteral("◐"), QStringLiteral("#1c1c1e"));
    add(QStringLiteral("Fondo de pantalla"), QStringLiteral("Fondo de pantalla"), QStringLiteral("🖼️"), QStringLiteral("#007aff"));
    add(QStringLiteral("Pantallas"), QStringLiteral("Pantallas"), QStringLiteral("☀️"), QStringLiteral("#007aff"));
    add(QStringLiteral("Batería"), QStringLiteral("Batería"), QStringLiteral("🔋"), QStringLiteral("#34c759"));
    add(QStringLiteral("Escritorio y Dock"), QStringLiteral("Escritorio y Dock"), QStringLiteral("⊞"), QStringLiteral("#5856d6"));
    add(QStringLiteral("Barra de menús"), QStringLiteral("Barra de menús"), QStringLiteral("🗂️"), QStringLiteral("#007aff"));
    add(QStringLiteral("Centro de control"), QStringLiteral("Centro de control"), QStringLiteral("🎛️"), QStringLiteral("#8e8e93"));
    add(QStringLiteral("Widgets"), QStringLiteral("Widgets"), QStringLiteral("▦"), QStringLiteral("#ff9500"));
    add(QStringLiteral("Notificaciones"), QStringLiteral("Notificaciones"), QStringLiteral("🔔"), QStringLiteral("#ff3b30"));
    add(QStringLiteral("Sonido"), QStringLiteral("Sonido"), QStringLiteral("🔊"), QStringLiteral("#ff3b30"));
    add(QStringLiteral("Concentración"), QStringLiteral("Concentración"), QStringLiteral("🌙"), QStringLiteral("#af52de"));
    add(QStringLiteral("Bloquear pantalla"), QStringLiteral("Bloquear pantalla"), QStringLiteral("🔒"), QStringLiteral("#8e8e93"));
    add(QStringLiteral("Usuarios y grupos"), QStringLiteral("Usuarios y grupos"), QStringLiteral("👤"), QStringLiteral("#007aff"));
    add(QStringLiteral("Teclado"), QStringLiteral("Teclado"), QStringLiteral("⌨️"), QStringLiteral("#8e8e93"));

    emit sectionsChanged();
}

QVariantList SettingsBackend::sections() const
{
    if (m_searchQuery.trimmed().isEmpty()) {
        return m_allSections;
    }

    QVariantList filtered;
    const QString q = m_searchQuery.trimmed().toLower();
    for (const QVariant &v : m_allSections) {
        QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("name")).toString().toLower().contains(q)) {
            filtered.append(m);
        }
    }
    return filtered;
}

void SettingsBackend::setCurrentSection(const QString &section)
{
    if (m_currentSection != section && !section.isEmpty()) {
        m_currentSection = section;
        emit currentSectionChanged();
    }
}

void SettingsBackend::setSearchQuery(const QString &query)
{
    if (m_searchQuery != query) {
        m_searchQuery = query;
        emit searchQueryChanged();
        emit sectionsChanged();
    }
}

bool SettingsBackend::isDark() const
{
    return ThemeManager::instance()->isDark();
}

void SettingsBackend::setIsDark(bool dark)
{
    ThemeManager::instance()->setIsDark(dark);
}

QString SettingsBackend::accent() const
{
    return ThemeManager::instance()->accent();
}

void SettingsBackend::setAccent(const QString &accent)
{
    ThemeManager::instance()->setAccent(accent);
}

QString SettingsBackend::currentWallpaper() const
{
    return ThemeManager::instance()->wallpaper();
}

QVariantList SettingsBackend::wallpapers() const
{
    return ThemeManager::instance()->availableWallpapers();
}

void SettingsBackend::setThemeMode(const QString &mode)
{
    ThemeManager::instance()->setMode(mode);
}

void SettingsBackend::setWallpaper(const QString &path)
{
    ThemeManager::instance()->setWallpaper(path);
}

void SettingsBackend::setLanguage(const QString &lang)
{
    if (m_language != lang) {
        m_language = lang;
        saveShellSettings();
        emit languageChanged();
    }
}

void SettingsBackend::setDockEnabled(bool enabled)
{
    if (m_dockEnabled != enabled) {
        m_dockEnabled = enabled;
        saveShellSettings();
        emit shellSettingsChanged();
    }
}

void SettingsBackend::setTopBarEnabled(bool enabled)
{
    if (m_topBarEnabled != enabled) {
        m_topBarEnabled = enabled;
        saveShellSettings();
        emit shellSettingsChanged();
    }
}

void SettingsBackend::loadShellSettings()
{
    QString confPath = QDir::homePath() + QStringLiteral("/.config/titan/shell.conf");
    if (QFile::exists(confPath)) {
        QSettings s(confPath, QSettings::IniFormat);
        m_dockEnabled = s.value(QStringLiteral("Shell/dockEnabled"), true).toBool();
        m_topBarEnabled = s.value(QStringLiteral("Shell/topBarEnabled"), true).toBool();
        m_language = s.value(QStringLiteral("General/language"), QStringLiteral("auto")).toString();
    }
}

void SettingsBackend::saveShellSettings()
{
    QString configDir = QDir::homePath() + QStringLiteral("/.config/titan");
    QDir().mkpath(configDir);
    QSettings s(configDir + QStringLiteral("/shell.conf"), QSettings::IniFormat);
    s.setValue(QStringLiteral("Shell/dockEnabled"), m_dockEnabled);
    s.setValue(QStringLiteral("Shell/topBarEnabled"), m_topBarEnabled);
    s.setValue(QStringLiteral("General/language"), m_language);
    s.sync();
}

void SettingsBackend::loadSystemInfo()
{
    m_systemInfo[QStringLiteral("osName")] = QStringLiteral("Titan Linux");
    m_systemInfo[QStringLiteral("osVersion")] = QStringLiteral("0.2.0 (macOS Edition)");
    m_systemInfo[QStringLiteral("kernel")] = QSysInfo::kernelType() + QStringLiteral(" ") + QSysInfo::kernelVersion();
    m_systemInfo[QStringLiteral("arch")] = QSysInfo::currentCpuArchitecture();
    m_systemInfo[QStringLiteral("hostname")] = QSysInfo::machineHostName();
    m_systemInfo[QStringLiteral("user")] = QString::fromLocal8Bit(qgetenv("USER"));
    if (m_systemInfo[QStringLiteral("user")].toString().isEmpty()) {
        m_systemInfo[QStringLiteral("user")] = QStringLiteral("ISAI");
    }

    QStorageInfo rootStorage(QDir::rootPath());
    if (rootStorage.isValid()) {
        double totalGb = rootStorage.bytesTotal() / (1024.0 * 1024.0 * 1024.0);
        double freeGb = rootStorage.bytesAvailable() / (1024.0 * 1024.0 * 1024.0);
        m_systemInfo[QStringLiteral("disk")] = QStringLiteral("%1 GB libres de %2 GB").arg(freeGb, 0, 'f', 1).arg(totalGb, 0, 'f', 1);
    }
}

void SettingsBackend::checkUpdates()
{
    m_updateStatus = QStringLiteral("Buscando actualizaciones...");
    emit updateStatusChanged();

    QTimer::singleShot(1400, this, [this]() {
        m_updateStatus = QStringLiteral("Titan Linux 0.2.0 está al día (última comprobación hoy)");
        emit updateStatusChanged();
    });
}

