#include "ThemeManager.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSettings>
#include <QProcess>
#include <QUrl>
#include <QDateTime>
#include <QDebug>

ThemeManager *ThemeManager::instance()
{
    static ThemeManager s_instance;
    return &s_instance;
}

ThemeManager::ThemeManager(QObject *parent)
    : QObject(parent)
    , m_watcher(new QFileSystemWatcher(this))
{
    m_configDir = QDir::homePath() + QStringLiteral("/.config/titan");
    m_configPath = m_configDir + QStringLiteral("/theme.conf");

    QDir().mkpath(m_configDir);

    load();
    scanWallpapers();

    m_watcher->addPath(m_configDir);
    if (QFile::exists(m_configPath)) {
        m_watcher->addPath(m_configPath);
    }

    connect(m_watcher, &QFileSystemWatcher::fileChanged, this, &ThemeManager::onConfigFileChanged);
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &ThemeManager::onConfigFileChanged);
}

void ThemeManager::load()
{
    if (QFile::exists(m_configPath)) {
        QSettings s(m_configPath, QSettings::IniFormat);
        s.beginGroup(QStringLiteral("Theme"));
        m_isDark = s.value(QStringLiteral("isDark"), false).toBool();
        m_accent = s.value(QStringLiteral("accent"), QStringLiteral("#0071e3")).toString();
        m_wallpaper = s.value(QStringLiteral("wallpaper")).toString();
        s.endGroup();
    } else {
        m_isDark = false;
        m_accent = QStringLiteral("#0071e3");
    }

    if (m_wallpaper.isEmpty() || !QFile::exists(m_wallpaper)) {
        const QString defaultWp = QStringLiteral("/usr/share/titan/wallpapers/01-macos-golden.jpg");
        if (QFile::exists(defaultWp)) {
            m_wallpaper = defaultWp;
        } else if (QFile::exists(QStringLiteral("/usr/share/titan/wallpaper.jpg"))) {
            m_wallpaper = QStringLiteral("/usr/share/titan/wallpaper.jpg");
        }
    }
}

void ThemeManager::save()
{
    QDir().mkpath(m_configDir);
    QSettings s(m_configPath, QSettings::IniFormat);
    s.beginGroup(QStringLiteral("Theme"));
    s.setValue(QStringLiteral("isDark"), m_isDark);
    s.setValue(QStringLiteral("accent"), m_accent);
    s.setValue(QStringLiteral("wallpaper"), m_wallpaper);
    s.endGroup();
    s.sync();

    // También actualizar ~/.config/titan/wallpaper para compatibilidad con titan-desktop
    QFile wpFile(m_configDir + QStringLiteral("/wallpaper"));
    if (wpFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
        wpFile.write(m_wallpaper.toUtf8() + "\n");
        wpFile.close();
    }
}

void ThemeManager::onConfigFileChanged()
{
    bool oldDark = m_isDark;
    QString oldAccent = m_accent;
    QString oldWp = m_wallpaper;

    load();

    if (oldDark != m_isDark || oldAccent != m_accent) {
        emit themeChanged();
    }
    if (oldWp != m_wallpaper) {
        emit wallpaperChanged();
    }

    if (QFile::exists(m_configPath) && !m_watcher->files().contains(m_configPath)) {
        m_watcher->addPath(m_configPath);
    }
}

void ThemeManager::setIsDark(bool dark)
{
    if (m_isDark != dark) {
        m_isDark = dark;
        save();
        syncLabwcTheme();
        emit themeChanged();
    }
}

void ThemeManager::setAccent(const QString &accent)
{
    if (m_accent != accent && !accent.isEmpty()) {
        m_accent = accent;
        save();
        emit themeChanged();
    }
}

void ThemeManager::setWallpaper(const QString &wallpaper)
{
    if (m_wallpaper != wallpaper && !wallpaper.isEmpty() && QFile::exists(wallpaper)) {
        m_wallpaper = wallpaper;
        save();
        emit wallpaperChanged();
    }
}

void ThemeManager::toggleTheme()
{
    setIsDark(!m_isDark);
}

void ThemeManager::setMode(const QString &mode)
{
    if (mode == QStringLiteral("dark")) {
        setIsDark(true);
    } else if (mode == QStringLiteral("light")) {
        setIsDark(false);
    } else if (mode == QStringLiteral("auto")) {
        // En modo auto, usar hora del sistema (noche = oscuro)
        int hora = QDateTime::currentDateTime().time().hour();
        setIsDark(hora < 7 || hora >= 19);
    }
}

QVariantList ThemeManager::availableWallpapers() const
{
    return m_wallpapers;
}

void ThemeManager::scanWallpapers()
{
    m_wallpapers.clear();

    const QString wpDir = QStringLiteral("/usr/share/titan/wallpapers");
    const QString thumbDir = wpDir + QStringLiteral("/thumbnails");

    QDir dir(wpDir);
    if (!dir.exists()) {
        // Buscar en el repo local si estamos en desarrollo
        QDir devDir(QDir::currentPath() + QStringLiteral("/iso/titan/airootfs/usr/share/titan/wallpapers"));
        if (devDir.exists()) {
            dir = devDir;
        }
    }

    if (dir.exists()) {
        const auto files = dir.entryInfoList({QStringLiteral("*.jpg"), QStringLiteral("*.png"), QStringLiteral("*.jpeg")}, QDir::Files, QDir::Name);
        for (const QFileInfo &fi : files) {
            QVariantMap item;
            QString base = fi.baseName();
            QString title = base;
            // Limpiar prefijo numérico como "01-macos-golden" -> "macOS Golden"
            if (title.length() > 3 && title.at(2) == QLatin1Char('-')) {
                title = title.mid(3);
            }
            title.replace(QLatin1Char('-'), QLatin1Char(' '));
            title.replace(QLatin1Char('_'), QLatin1Char(' '));
            // Capitalizar palabras
            QStringList words = title.split(QLatin1Char(' '));
            for (QString &w : words) {
                if (!w.isEmpty()) w[0] = w[0].toUpper();
            }
            title = words.join(QLatin1Char(' '));

            item[QStringLiteral("name")] = title;
            item[QStringLiteral("path")] = fi.absoluteFilePath();
            
            QString thumb = fi.absolutePath() + QStringLiteral("/thumbnails/") + fi.fileName();
            if (QFile::exists(thumb)) {
                item[QStringLiteral("thumbnail")] = QUrl::fromLocalFile(thumb).toString();
            } else {
                item[QStringLiteral("thumbnail")] = QUrl::fromLocalFile(fi.absoluteFilePath()).toString();
            }

            m_wallpapers.append(item);
        }
    }

    emit wallpapersChanged();
}

void ThemeManager::syncLabwcTheme()
{
    // Escribir themerc adecuado (Light u Oscuro) para que Firefox, OnlyOffice y ventanas nativas coincidan
    QString themercPath = QDir::homePath() + QStringLiteral("/.config/labwc/themerc");
    QFile f(themercPath);
    if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream out(&f);
        if (m_isDark) {
            out << "# Titan Linux - Tema macOS Dark para Labwc\n"
                << "window.active.title.bg: flat solid\n"
                << "window.active.title.bg.color: #1e2028\n"
                << "window.inactive.title.bg: flat solid\n"
                << "window.inactive.title.bg.color: #15161c\n"
                << "window.active.border.color: #383c4c\n"
                << "window.inactive.border.color: #20222c\n"
                << "border.width: 1\n"
                << "window.active.label.text.color: #f2f4f8\n"
                << "window.inactive.label.text.color: #6e7384\n";
        } else {
            out << "# Titan Linux - Tema macOS Light para Labwc\n"
                << "window.active.title.bg: flat solid\n"
                << "window.active.title.bg.color: #e8e8ed\n"
                << "window.inactive.title.bg: flat solid\n"
                << "window.inactive.title.bg.color: #f2f2f7\n"
                << "window.active.border.color: #d1d1d6\n"
                << "window.inactive.border.color: #e5e5ea\n"
                << "border.width: 1\n"
                << "window.active.label.text.color: #1d1d1f\n"
                << "window.inactive.label.text.color: #8e8e93\n";
        }
        out << "window.label.text.justify: center\n"
            << "window.active.button.close.unpressed.image.color: #ff5f56\n"
            << "window.active.button.close.hover.image.color: #e0443e\n"
            << "window.active.button.close.pressed.image.color: #c0322c\n"
            << "window.active.button.iconify.unpressed.image.color: #febc2e\n"
            << "window.active.button.iconify.hover.image.color: #dea123\n"
            << "window.active.button.iconify.pressed.image.color: #b88214\n"
            << "window.active.button.max.unpressed.image.color: #28c840\n"
            << "window.active.button.max.hover.image.color: #1aab29\n"
            << "window.active.button.max.pressed.image.color: #12821d\n"
            << "window.inactive.button.close.unpressed.image.color: #8e8e93\n"
            << "window.inactive.button.iconify.unpressed.image.color: #8e8e93\n"
            << "window.inactive.button.max.unpressed.image.color: #8e8e93\n"
            << "padding.width: 8\n"
            << "padding.height: 5\n"
            << "window.handle.width: 0\n"
            << "window.client.padding.width: 0\n";
        f.close();

        // Reconfigurar labwc en caliente
        QProcess::startDetached(QStringLiteral("labwc"), {QStringLiteral("--reconfigure")});
    }
}

