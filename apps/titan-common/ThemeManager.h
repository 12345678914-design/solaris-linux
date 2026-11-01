#ifndef TITAN_THEMEMANAGER_H
#define TITAN_THEMEMANAGER_H

#include <QObject>
#include <QString>
#include <QFileSystemWatcher>
#include <QVariantList>

class ThemeManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isDark READ isDark WRITE setIsDark NOTIFY themeChanged)
    Q_PROPERTY(QString accent READ accent WRITE setAccent NOTIFY themeChanged)
    Q_PROPERTY(QString wallpaper READ wallpaper WRITE setWallpaper NOTIFY wallpaperChanged)
    Q_PROPERTY(QVariantList availableWallpapers READ availableWallpapers NOTIFY wallpapersChanged)

public:
    static ThemeManager *instance();

    explicit ThemeManager(QObject *parent = nullptr);
    ~ThemeManager() override = default;

    bool isDark() const { return m_isDark; }
    void setIsDark(bool dark);

    QString accent() const { return m_accent; }
    void setAccent(const QString &accent);

    QString wallpaper() const { return m_wallpaper; }
    void setWallpaper(const QString &wallpaper);

    QVariantList availableWallpapers() const;

    Q_INVOKABLE void toggleTheme();
    Q_INVOKABLE void setMode(const QString &mode); // "light", "dark", "auto"

signals:
    void themeChanged();
    void wallpaperChanged();
    void wallpapersChanged();

private slots:
    void onConfigFileChanged();

private:
    void load();
    void save();
    void syncLabwcTheme();
    void scanWallpapers();

    bool m_isDark = false;
    QString m_accent = QStringLiteral("#0071e3");
    QString m_wallpaper;
    QVariantList m_wallpapers;
    QFileSystemWatcher *m_watcher = nullptr;
    QString m_configPath;
    QString m_configDir;
};

#endif // TITAN_THEMEMANAGER_H

