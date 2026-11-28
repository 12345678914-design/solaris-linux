#ifndef TITAN_THEMEMANAGER_H
#define TITAN_THEMEMANAGER_H

#include <QObject>
#include <QString>
#include <QFileSystemWatcher>
#include <QVariantList>
#include <QStringList>

class ThemeManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isDark READ isDark WRITE setIsDark NOTIFY themeChanged)
    Q_PROPERTY(QString accent READ accent WRITE setAccent NOTIFY themeChanged)
    Q_PROPERTY(QString wallpaper READ wallpaper WRITE setWallpaper NOTIFY wallpaperChanged)
    Q_PROPERTY(QVariantList availableWallpapers READ availableWallpapers NOTIFY wallpapersChanged)
    // Estilo de los botones de ventana (Ajustes > Ventanas): actual, windows,
    // circulos, acento, capsula, contorno o color.
    Q_PROPERTY(QString windowStyle READ windowStyle WRITE setWindowStyle NOTIFY windowStyleChanged)

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

    QString windowStyle() const { return m_windowStyle; }
    void setWindowStyle(const QString &estilo);
    static bool estiloValido(const QString &estilo);

    Q_INVOKABLE void toggleTheme();
    Q_INVOKABLE void setMode(const QString &mode); // "light", "dark", "auto"
    // Solo el shell: mantiene GTK/portal (color-scheme) igual que theme.conf.
    void setSincronizaSistema(bool activo);

signals:
    void themeChanged();
    void wallpaperChanged();
    void wallpapersChanged();
    void windowStyleChanged();

private slots:
    void onConfigFileChanged();

private:
    void load();
    void save();
    void syncLabwcTheme();
    void sincronizarGtk();
    void repasarSistema();
    static bool shellActivo();
    bool m_sincronizaSistema = false;
    // Lo último que se llevó a GTK/portal (-1: nada aún)
    int m_ultimoOscuro = -1;
    QString m_ultimoAcento;
    class QTimer *m_retrasoSync = nullptr;
    void aplicarPaleta();
    void scanWallpapers();

    bool m_isDark = false;
    QString m_accent = QStringLiteral("#0071e3");
    QString m_wallpaper;
    QString m_windowStyle = QStringLiteral("actual");
    QVariantList m_wallpapers;
    QFileSystemWatcher *m_watcher = nullptr;
    QString m_configPath;
    QString m_configDir;
};

#endif // TITAN_THEMEMANAGER_H

