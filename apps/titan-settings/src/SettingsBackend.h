#ifndef SETTINGSBACKEND_H
#define SETTINGSBACKEND_H

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
    Q_PROPERTY(bool dockEnabled READ dockEnabled WRITE setDockEnabled NOTIFY shellSettingsChanged)
    Q_PROPERTY(bool topBarEnabled READ topBarEnabled WRITE setTopBarEnabled NOTIFY shellSettingsChanged)
    Q_PROPERTY(QVariantMap systemInfo READ systemInfo CONSTANT)
    Q_PROPERTY(QString updateStatus READ updateStatus NOTIFY updateStatusChanged)

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
    void setLanguage(const QString &lang);

    bool dockEnabled() const { return m_dockEnabled; }
    void setDockEnabled(bool enabled);

    bool topBarEnabled() const { return m_topBarEnabled; }
    void setTopBarEnabled(bool enabled);

    QVariantMap systemInfo() const { return m_systemInfo; }
    QString updateStatus() const { return m_updateStatus; }

    Q_INVOKABLE void setThemeMode(const QString &mode); // "light", "dark", "auto"
    Q_INVOKABLE void setWallpaper(const QString &path);
    Q_INVOKABLE void checkUpdates();

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

private:
    void initSections();
    void loadShellSettings();
    void saveShellSettings();
    void loadSystemInfo();

    QString m_currentSection = QStringLiteral("General");
    QString m_searchQuery;
    QVariantList m_allSections;
    QString m_language = QStringLiteral("auto");
    bool m_dockEnabled = true;
    bool m_topBarEnabled = true;
    QVariantMap m_systemInfo;
    QString m_updateStatus = QStringLiteral("El sistema está actualizado");
};

#endif // SETTINGSBACKEND_H

