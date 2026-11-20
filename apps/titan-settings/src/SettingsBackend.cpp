#include "SettingsBackend.h"
#include "ThemeManager.h"
#include "TitanUsuario.h"

#include <QDir>
#include <QFile>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
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

    updateNetworkStatus();
    QTimer *netTimer = new QTimer(this);
    connect(netTimer, &QTimer::timeout, this, &SettingsBackend::updateNetworkStatus);
    netTimer->start(8000);
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

    // Estructura idéntica a macOS Ventura / Sonoma y la imagen de referencia (sin Widgets)
    add(QStringLiteral("wifi"), QStringLiteral("Wi-Fi"), QStringLiteral("📶"), QStringLiteral("#007aff"));
    add(QStringLiteral("bluetooth"), QStringLiteral("Bluetooth"), QStringLiteral("ᛒ"), QStringLiteral("#007aff"));
    add(QStringLiteral("red"), QStringLiteral("Red"), QStringLiteral("↔"), QStringLiteral("#007aff"));
    add(QStringLiteral("VPN"), QStringLiteral("VPN"), QStringLiteral("🔐"), QStringLiteral("#007aff"));
    add(QStringLiteral("General"), QStringLiteral("General"), QStringLiteral("⚙️"), QStringLiteral("#636366"));
    add(QStringLiteral("Accesibilidad"), QStringLiteral("Accesibilidad"), QStringLiteral("♿"), QStringLiteral("#007aff"));
    add(QStringLiteral("Apariencia"), QStringLiteral("Apariencia"), QStringLiteral("◐"), QStringLiteral("#1c1c1e"));
    add(QStringLiteral("Fondo de pantalla"), QStringLiteral("Fondo de pantalla"), QStringLiteral("🖼️"), QStringLiteral("#007aff"));
    add(QStringLiteral("Pantallas"), QStringLiteral("Pantallas"), QStringLiteral("☀️"), QStringLiteral("#007aff"));
    add(QStringLiteral("Batería"), QStringLiteral("Batería"), QStringLiteral("🔋"), QStringLiteral("#34c759"));
    add(QStringLiteral("Escritorio y Dock"), QStringLiteral("Escritorio y Dock"), QStringLiteral("⊞"), QStringLiteral("#5856d6"));
    add(QStringLiteral("Barra de menús"), QStringLiteral("Barra de menús"), QStringLiteral("🗂️"), QStringLiteral("#007aff"));
    add(QStringLiteral("Centro de control"), QStringLiteral("Centro de control"), QStringLiteral("🎛️"), QStringLiteral("#8e8e93"));
    add(QStringLiteral("Notificaciones"), QStringLiteral("Notificaciones"), QStringLiteral("🔔"), QStringLiteral("#ff3b30"));
    add(QStringLiteral("Sonido"), QStringLiteral("Sonido"), QStringLiteral("🔊"), QStringLiteral("#ff3b30"));
    add(QStringLiteral("Concentración"), QStringLiteral("Concentración"), QStringLiteral("🌙"), QStringLiteral("#af52de"));
    add(QStringLiteral("Bloquear pantalla"), QStringLiteral("Bloquear pantalla"), QStringLiteral("🔒"), QStringLiteral("#8e8e93"));
    add(QStringLiteral("Privacidad y seguridad"), QStringLiteral("Privacidad y seguridad"), QStringLiteral("🛡️"), QStringLiteral("#007aff"));
    add(QStringLiteral("Compartir"), QStringLiteral("Compartir"), QStringLiteral("🖥️"), QStringLiteral("#007aff"));
    add(QStringLiteral("Usuarios y grupos"), QStringLiteral("Usuarios y grupos"), QStringLiteral("👤"), QStringLiteral("#007aff"));
    add(QStringLiteral("Teclado"), QStringLiteral("Teclado"), QStringLiteral("⌨️"), QStringLiteral("#8e8e93"));
    add(QStringLiteral("Ratón y panel táctil"), QStringLiteral("Ratón y panel táctil"), QStringLiteral("🖱️"), QStringLiteral("#8e8e93"));
    add(QStringLiteral("Impresoras y escáneres"), QStringLiteral("Impresoras y escáneres"), QStringLiteral("🖨️"), QStringLiteral("#8e8e93"));
    add(QStringLiteral("Almacenamiento"), QStringLiteral("Almacenamiento"), QStringLiteral("💽"), QStringLiteral("#8e8e93"));
    add(QStringLiteral("Restaurar sistema"), QStringLiteral("Restaurar sistema"), QStringLiteral("🕘"), QStringLiteral("#34c759"));

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

        if (section == QStringLiteral("Wi-Fi") || section == QStringLiteral("wifi") || section == QStringLiteral("Red") || section == QStringLiteral("red")) {
            scanWifi();
        } else if (section == QStringLiteral("Bluetooth") || section == QStringLiteral("bluetooth")) {
            scanBluetooth();
        }
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

        // Aplicar locale según Arch Linux
        QString localeCode = QStringLiteral("es_ES.UTF-8");
        QString localeGenEntry = QStringLiteral("es_ES.UTF-8 UTF-8");
        if (lang == QStringLiteral("en")) {
            localeCode = QStringLiteral("en_US.UTF-8");
            localeGenEntry = QStringLiteral("en_US.UTF-8 UTF-8");
        } else if (lang == QStringLiteral("quz")) {
            localeCode = QStringLiteral("quz_PE.UTF-8");
            localeGenEntry = QStringLiteral("quz_PE.UTF-8 UTF-8");
        } else if (lang == QStringLiteral("auto")) {
            localeCode = QStringLiteral("es_ES.UTF-8");
            localeGenEntry = QStringLiteral("es_ES.UTF-8 UTF-8");
        }

        // 1. Escribir configuración de usuario en ~/.config/locale.conf
        QString confDir = QDir::homePath() + QStringLiteral("/.config");
        QDir().mkpath(confDir);
        QFile uLocale(confDir + QStringLiteral("/locale.conf"));
        if (uLocale.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
            QTextStream ts(&uLocale);
            ts << "LANG=" << localeCode << "\n";
            ts << "LC_ALL=" << localeCode << "\n";
            uLocale.close();
        }

        // 2. Método completo: habilitar en /etc/locale.gen, ejecutar locale-gen y actualizar /etc/locale.conf
        QString script = QStringLiteral(
            "grep -qE '^[# ]*%1' /etc/locale.gen && sudo sed -i 's/^[# ]*%1/%1/' /etc/locale.gen || echo '%2' | sudo tee -a /etc/locale.gen; "
            "sudo locale-gen; "
            "echo 'LANG=%3' | sudo tee /etc/locale.conf; "
            "echo 'LC_ALL=%3' | sudo tee -a /etc/locale.conf; "
            "localectl set-locale LANG=%3 2>/dev/null || true"
        ).arg(localeGenEntry.section(QLatin1Char(' '), 0, 0), localeGenEntry, localeCode);

        QProcess::startDetached(QStringLiteral("bash"), {QStringLiteral("-c"), script});

        qputenv("LANG", localeCode.toUtf8());
        qputenv("LC_ALL", localeCode.toUtf8());

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
    m_systemInfo[QStringLiteral("osName")] = QStringLiteral("Inti OS");
    m_systemInfo[QStringLiteral("osVersion")] = QStringLiteral("1.0 (Edición Escritorio)");
    m_systemInfo[QStringLiteral("kernel")] = QSysInfo::kernelType() + QStringLiteral(" ") + QSysInfo::kernelVersion();
    m_systemInfo[QStringLiteral("arch")] = QSysInfo::currentCpuArchitecture();
    m_systemInfo[QStringLiteral("hostname")] = QSysInfo::machineHostName();
    m_systemInfo[QStringLiteral("user")] = titan::usuarioActual();

    QStorageInfo rootStorage(QDir::rootPath());
    if (rootStorage.isValid()) {
        double totalGb = rootStorage.bytesTotal() / (1024.0 * 1024.0 * 1024.0);
        double freeGb = rootStorage.bytesAvailable() / (1024.0 * 1024.0 * 1024.0);
        m_systemInfo[QStringLiteral("disk")] = QStringLiteral("%1 GB libres de %2 GB").arg(freeGb, 0, 'f', 1).arg(totalGb, 0, 'f', 1);
    }
}

namespace {
// Base de datos temporal de checkupdates (la sincroniza sin tocar la del
// sistema); con ella se calcula el tamaño real de la descarga.
QString baseActualizaciones()
{
    return QDir::tempPath() + QStringLiteral("/titan-checkup-db-") + QString::fromLocal8Bit(qgetenv("USER")) + QLatin1Char('/');
}

QString tamanoLegible(qint64 b)
{
    if (b >= 1024LL * 1024 * 1024)
        return QStringLiteral("%1 GiB").arg(b / (1024.0 * 1024.0 * 1024.0), 0, 'f', 2);
    if (b >= 1024 * 1024)
        return QStringLiteral("%1 MiB").arg(b / (1024.0 * 1024.0), 0, 'f', 1);
    return QStringLiteral("%1 KiB").arg(qMax<qint64>(1, b / 1024));
}
} // namespace

void SettingsBackend::checkUpdates()
{
    if (m_updateChecking) return;

    auto fin = [this](const QString &estado, int cuantas, const QString &tamano) {
        m_updateChecking = false;
        m_updateCount = cuantas;
        m_updateSize = tamano;
        m_updateStatus = estado;
        m_updatePromptVisible = cuantas > 0;
        emit updateCheckingChanged();
        emit updatePromptVisibleChanged();
        emit updateCountChanged();
        emit updateSizeChanged();
        emit updateStatusChanged();
    };

    m_updateChecking = true;
    m_updatePromptVisible = false;
    m_updateStatus = QStringLiteral("Buscando actualizaciones…");
    emit updateCheckingChanged();
    emit updatePromptVisibleChanged();
    emit updateStatusChanged();

    if (QStandardPaths::findExecutable(QStringLiteral("checkupdates")).isEmpty()) {
        fin(QStringLiteral("No se puede comprobar: falta el paquete pacman-contrib."), 0, QStringLiteral("0 MB"));
        return;
    }
    if (QStandardPaths::findExecutable(QStringLiteral("fakeroot")).isEmpty()) {
        fin(QStringLiteral("No se puede comprobar: falta el paquete fakeroot."), 0, QStringLiteral("0 MB"));
        return;
    }

    // En segundo plano: sincronizar la base temporal puede tardar un rato y
    // antes se cortaba a los 15 s y daba "al día" sin haber comprobado nada.
    auto *proc = new QProcess(this);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("CHECKUPDATES_DB"), baseActualizaciones());
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    proc->setProcessEnvironment(env);
    auto *limite = new QTimer(proc);
    limite->setSingleShot(true);
    connect(limite, &QTimer::timeout, proc, [proc]() { proc->kill(); });
    limite->start(180000);

    connect(proc, &QProcess::finished, this, [this, proc, fin](int codigo, QProcess::ExitStatus estado) {
        proc->deleteLater();
        const QString salida = QString::fromUtf8(proc->readAllStandardOutput()).trimmed();
        const QString error = QString::fromUtf8(proc->readAllStandardError()).trimmed();
        // checkupdates: 0 = hay, 2 = no hay, 1 u otro = no se pudo comprobar
        if (estado != QProcess::NormalExit || (codigo != 0 && codigo != 2)) {
            QString motivo = error.section(QLatin1Char('\n'), -1).remove(QStringLiteral("==> ERROR: ")).trimmed();
            if (estado != QProcess::NormalExit)
                motivo = QStringLiteral("tardó demasiado");
            if (motivo.contains(QStringLiteral("database"), Qt::CaseInsensitive) || motivo.isEmpty())
                motivo = QStringLiteral("¿hay conexión a Internet?");
            fin(QStringLiteral("No se pudo comprobar: %1").arg(motivo), 0, QStringLiteral("0 MB"));
            return;
        }

        QStringList paquetes;
        for (const QString &l : salida.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            const QString p = l.section(QLatin1Char(' '), 0, 0).trimmed();
            if (!p.isEmpty())
                paquetes << p;
        }

        // Flatpak (Tienda) también cuenta, si está.
        int flatpaks = 0;
        if (!QStandardPaths::findExecutable(QStringLiteral("flatpak")).isEmpty()) {
            QProcess fp;
            fp.start(QStringLiteral("flatpak"), {QStringLiteral("remote-ls"), QStringLiteral("--updates"), QStringLiteral("--columns=application")});
            if (fp.waitForFinished(20000) && fp.exitCode() == 0)
                flatpaks = QString::fromUtf8(fp.readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts).size();
        }

        const int total = paquetes.size() + flatpaks;
        if (total == 0) {
            fin(QStringLiteral("El sistema está al día."), 0, QStringLiteral("0 MB"));
            return;
        }

        // Tamaño real de lo que hay que descargar (paquetes aún no en caché)
        qint64 bytes = 0;
        bool tamanoOk = false;
        auto medir = [](const QStringList &pk, qint64 *suma) {
            QProcess tam;
            tam.start(QStringLiteral("pacman"), QStringList{QStringLiteral("-Sp"), QStringLiteral("--dbpath"), baseActualizaciones(),
                                                            QStringLiteral("--print-format"), QStringLiteral("%s")} + pk);
            if (!tam.waitForFinished(10000) || tam.exitCode() != 0)
                return false;
            for (const QString &l : QString::fromUtf8(tam.readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts))
                *suma += l.trimmed().toLongLong();
            return true;
        };
        if (!paquetes.isEmpty()) {
            tamanoOk = medir(paquetes, &bytes);
            if (!tamanoOk) {
                // Algún paquete cambió de nombre en el repositorio: uno a uno.
                bytes = 0;
                for (const QString &pk : std::as_const(paquetes))
                    tamanoOk = medir({pk}, &bytes) || tamanoOk;
            }
        }
        QString partes;
        if (!paquetes.isEmpty())
            partes = paquetes.size() == 1 ? QStringLiteral("1 paquete") : QStringLiteral("%1 paquetes").arg(paquetes.size());
        if (flatpaks > 0)
            partes += (partes.isEmpty() ? QString() : QStringLiteral(" y ")) +
                      (flatpaks == 1 ? QStringLiteral("1 app de la Tienda") : QStringLiteral("%1 apps de la Tienda").arg(flatpaks));
        const QString tamano = tamanoOk && bytes > 0 ? tamanoLegible(bytes) : QStringLiteral("—");
        fin(tamanoOk && bytes > 0 ? QStringLiteral("Hay actualizaciones: %1 (%2 de descarga)").arg(partes, tamano)
                                  : QStringLiteral("Hay actualizaciones: %1").arg(partes),
            total, tamano);
    });
    proc->start(QStringLiteral("checkupdates"), {QStringLiteral("--nocolor")});
}

void SettingsBackend::cancelUpdates()
{
    m_updatePromptVisible = false;
    m_updateStatus = QStringLiteral("Actualización cancelada por el usuario");
    emit updatePromptVisibleChanged();
    emit updateStatusChanged();
}

void SettingsBackend::installUpdates()
{
    m_updatePromptVisible = false;
    m_updateStatus = QStringLiteral("Instalando actualizaciones en la terminal...");
    emit updatePromptVisibleChanged();
    emit updateStatusChanged();

    // Buscar terminal
    QString term = QStringLiteral("titan-terminal");
    if (!QStandardPaths::findExecutable(term).isEmpty() || QFile::exists(QStringLiteral("/usr/local/bin/titan-terminal"))) {
        term = QStringLiteral("/usr/local/bin/titan-terminal");
    } else if (!QStandardPaths::findExecutable(QStringLiteral("kitty")).isEmpty()) {
        term = QStringLiteral("kitty");
    } else if (!QStandardPaths::findExecutable(QStringLiteral("foot")).isEmpty()) {
        term = QStringLiteral("foot");
    }

    QString script = QStringLiteral("echo '=== Inti OS - Actualizar el sistema ==='; echo; "
                                    "sudo pacman -Syu; r=$?; "
                                    "if command -v flatpak >/dev/null; then echo; echo '=== Apps de la Tienda (Flatpak) ==='; flatpak update -y; fi; "
                                    "echo; if [ $r -eq 0 ]; then echo 'Listo: el sistema está actualizado.'; "
                                    "else echo 'La actualización no terminó (código '$r'). Revisa los mensajes de arriba.'; fi; "
                                    "read -p 'Pulsa Intro para cerrar...'");

    QProcess::startDetached(term, QStringList() << QStringLiteral("-e") << QStringLiteral("bash") << QStringLiteral("-c") << script);
}

void SettingsBackend::updateNetworkStatus()
{
    // 1. Estado de Wi-Fi
    QProcess pWifi;
    pWifi.start(QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("WIFI"), QStringLiteral("general")});
    if (pWifi.waitForFinished(1200)) {
        QString out = QString::fromUtf8(pWifi.readAllStandardOutput()).trimmed().toLower();
        bool en = (out == QStringLiteral("enabled"));
        if (m_wifiEnabled != en) {
            m_wifiEnabled = en;
            emit wifiStatusChanged();
        }
    }

    // 2. Wi-Fi conectado y SSID
    QProcess pConn;
    pConn.start(QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("DEVICE,TYPE,STATE,CONNECTION"), QStringLiteral("dev")});
    if (pConn.waitForFinished(1200)) {
        QString out = QString::fromUtf8(pConn.readAllStandardOutput());
        const auto lines = out.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        bool connected = false;
        QString activeSsid;
        for (const QString &line : lines) {
            auto fields = line.split(QLatin1Char(':'));
            if (fields.size() >= 4 && fields.at(1) == QStringLiteral("wifi") && fields.at(2) == QStringLiteral("connected")) {
                connected = true;
                activeSsid = fields.at(3);
                break;
            }
        }
        if (m_wifiConnected != connected || m_wifiSsid != activeSsid) {
            m_wifiConnected = connected;
            m_wifiSsid = activeSsid;
            emit wifiStatusChanged();
        }
    }

    // 3. Bluetooth status
    QProcess pBt;
    pBt.start(QStringLiteral("rfkill"), {QStringLiteral("list"), QStringLiteral("bluetooth")});
    if (pBt.waitForFinished(1200)) {
        QString out = QString::fromUtf8(pBt.readAllStandardOutput()).toLower();
        bool blocked = out.contains(QStringLiteral("soft blocked: yes")) || out.contains(QStringLiteral("hard blocked: yes"));
        bool en = !out.isEmpty() && !blocked;
        if (m_bluetoothEnabled != en) {
            m_bluetoothEnabled = en;
            emit bluetoothStatusChanged();
        }
    }

    // 4. Dispositivo Bluetooth conectado
    if (m_bluetoothEnabled) {
        QProcess pBtDev;
        pBtDev.start(QStringLiteral("bluetoothctl"), {QStringLiteral("devices"), QStringLiteral("Connected")});
        if (pBtDev.waitForFinished(1200)) {
            QString out = QString::fromUtf8(pBtDev.readAllStandardOutput()).trimmed();
            if (!out.isEmpty()) {
                QStringList parts = out.split(QLatin1Char(' '), Qt::SkipEmptyParts);
                if (parts.size() >= 3) {
                    parts.removeFirst(); // Device
                    parts.removeFirst(); // MAC
                    QString devName = parts.join(QLatin1Char(' '));
                    if (!m_bluetoothConnected || m_connectedBluetoothDevice != devName) {
                        m_connectedBluetoothDevice = devName;
                        m_bluetoothConnected = true;
                        emit bluetoothStatusChanged();
                    }
                }
            } else {
                if (m_bluetoothConnected) {
                    m_bluetoothConnected = false;
                    m_connectedBluetoothDevice.clear();
                    emit bluetoothStatusChanged();
                }
            }
        }
    }
}

void SettingsBackend::setWifiEnabled(bool enabled)
{
    if (m_wifiEnabled != enabled) {
        m_wifiEnabled = enabled;
        if (!m_wifiEnabled) {
            m_wifiConnected = false;
            m_wifiSsid.clear();
            QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), QStringLiteral("off")});
        } else {
            QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), QStringLiteral("on")});
            QProcess::startDetached(QStringLiteral("rfkill"), {QStringLiteral("unblock"), QStringLiteral("wifi")});
            scanWifi();
        }
        emit wifiStatusChanged();
    }
}

void SettingsBackend::scanWifi()
{
    if (m_wifiScanning) return;
    m_wifiScanning = true;
    emit wifiScanningChanged();

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

        std::stable_sort(found.begin(), found.end(), [](const QVariantMap &a, const QVariantMap &b) {
            bool aConn = a.value(QStringLiteral("connected")).toBool();
            bool bConn = b.value(QStringLiteral("connected")).toBool();
            if (aConn != bConn) return aConn;
            return a.value(QStringLiteral("signal")).toInt() > b.value(QStringLiteral("signal")).toInt();
        });

        m_wifiNetworks.clear();
        for (const auto &m : found) {
            m_wifiNetworks.append(m);
        }
        emit wifiNetworksChanged();
    });

    proc->start(QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"), QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("list")});
}

void SettingsBackend::connectWifi(const QString &ssid, const QString &password)
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
        }
        scanWifi();
    });
    connProc->start(QStringLiteral("nmcli"), args);
}

void SettingsBackend::disconnectWifi()
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
}

void SettingsBackend::setBluetoothEnabled(bool enabled)
{
    if (m_bluetoothEnabled != enabled) {
        m_bluetoothEnabled = enabled;
        if (!m_bluetoothEnabled) {
            m_bluetoothConnected = false;
            m_connectedBluetoothDevice.clear();
            QProcess::startDetached(QStringLiteral("bluetoothctl"), {QStringLiteral("power"), QStringLiteral("off")});
            QProcess::startDetached(QStringLiteral("rfkill"), {QStringLiteral("block"), QStringLiteral("bluetooth")});
        } else {
            QProcess::startDetached(QStringLiteral("rfkill"), {QStringLiteral("unblock"), QStringLiteral("bluetooth")});
            QProcess::startDetached(QStringLiteral("bluetoothctl"), {QStringLiteral("power"), QStringLiteral("on")});
            scanBluetooth();
        }
        emit bluetoothStatusChanged();
    }
}

void SettingsBackend::scanBluetooth()
{
    if (m_bluetoothScanning) return;
    m_bluetoothScanning = true;
    emit bluetoothScanningChanged();

    QProcess::startDetached(QStringLiteral("rfkill"), {QStringLiteral("unblock"), QStringLiteral("bluetooth")});
    QProcess::startDetached(QStringLiteral("bluetoothctl"), {QStringLiteral("power"), QStringLiteral("on")});

    QProcess *scanProc = new QProcess(this);
    connect(scanProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, [this, scanProc](int, QProcess::ExitStatus) {
        scanProc->deleteLater();
        m_bluetoothScanning = false;
        emit bluetoothScanningChanged();

        QProcess *devProc = new QProcess(this);
        connect(devProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, [this, devProc](int, QProcess::ExitStatus) {
            QByteArray out = devProc->readAllStandardOutput();
            devProc->deleteLater();

            QList<QVariantMap> devs;
            if (!out.isEmpty()) {
                QString text = QString::fromUtf8(out);
                QStringList lines = text.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
                for (const QString &line : lines) {
                    QStringList parts = line.trimmed().split(QLatin1Char(' '), Qt::SkipEmptyParts);
                    if (parts.size() >= 3 && parts.at(0) == QStringLiteral("Device")) {
                        QString mac = parts.at(1);
                        parts.removeFirst();
                        parts.removeFirst();
                        QString name = parts.join(QLatin1Char(' '));
                        bool connected = (name == m_connectedBluetoothDevice && m_bluetoothConnected);

                        QVariantMap m;
                        m[QStringLiteral("mac")] = mac;
                        m[QStringLiteral("name")] = name;
                        m[QStringLiteral("connected")] = connected;
                        if (connected) devs.prepend(m);
                        else devs.append(m);
                    }
                }
            }
            m_bluetoothDevices.clear();
            for (const auto &d : devs) {
                m_bluetoothDevices.append(d);
            }
            emit bluetoothDevicesChanged();
        });
        devProc->start(QStringLiteral("bluetoothctl"), {QStringLiteral("devices")});
    });

    scanProc->start(QStringLiteral("bluetoothctl"), {QStringLiteral("--timeout"), QStringLiteral("4"), QStringLiteral("scan"), QStringLiteral("on")});
}

void SettingsBackend::connectBluetooth(const QString &mac)
{
    if (mac.isEmpty()) return;
    QProcess::startDetached(QStringLiteral("bluetoothctl"), {QStringLiteral("connect"), mac});
    QTimer::singleShot(2500, this, &SettingsBackend::scanBluetooth);
}

void SettingsBackend::disconnectBluetooth(const QString &mac)
{
    if (mac.isEmpty()) return;
    QProcess::startDetached(QStringLiteral("bluetoothctl"), {QStringLiteral("disconnect"), mac});
    QTimer::singleShot(1500, this, &SettingsBackend::scanBluetooth);
}

