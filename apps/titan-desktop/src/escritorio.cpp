#include "escritorio.h"
#include "config.h"

#include <QColor>
#include <QFile>
#include <QDir>
#include <QSettings>
#include <QLinearGradient>
#include <QPainter>
#include <QEasingCurve>

Escritorio::Escritorio(QWidget *padre)
    : QWidget(padre)
    , m_watcher(new QFileSystemWatcher(this))
    , m_anim(new QVariantAnimation(this))
{
    const Config &cfg = Config::instancia();

    setWindowTitle(cfg.soNombre() + QStringLiteral(" - escritorio"));
    setWindowFlags(Qt::FramelessWindowHint);
    setAttribute(Qt::WA_TranslucentBackground, false);

    m_anim->setDuration(450);
    m_anim->setStartValue(0.0);
    m_anim->setEndValue(1.0);
    m_anim->setEasingCurve(QEasingCurve::InOutCubic);
    connect(m_anim, &QVariantAnimation::valueChanged, this, [this](const QVariant &val) {
        m_progresoTransicion = val.toReal();
        update();
    });

    cargarFondo();

    // Observar directorio ~/.config/titan para cambios de fondo en vivo
    const QString configDir = QDir::homePath() + QStringLiteral("/.config/titan");
    QDir().mkpath(configDir);
    m_watcher->addPath(configDir);

    const QString userCfg = configDir + QStringLiteral("/wallpaper");
    if (QFile::exists(userCfg)) {
        m_watcher->addPath(userCfg);
    }
    const QString themeConf = configDir + QStringLiteral("/theme.conf");
    if (QFile::exists(themeConf)) {
        m_watcher->addPath(themeConf);
    }

    connect(m_watcher, &QFileSystemWatcher::fileChanged, this, &Escritorio::cargarFondo);
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &Escritorio::cargarFondo);
}

void Escritorio::cambiarFondo(const QString &nuevaRuta)
{
    if (nuevaRuta.isEmpty() || !QFile::exists(nuevaRuta) || nuevaRuta == m_rutaActual) {
        return;
    }

    QPixmap nuevoPix(nuevaRuta);
    if (nuevoPix.isNull()) {
        return;
    }

    // Preparar transición suave de crossfade
    if (!m_fondo.isNull()) {
        m_fondoPrevio = m_fondo;
        m_fondoPrevioEscalado = m_fondoEscalado;
    }

    m_rutaActual = nuevaRuta;
    m_fondo = nuevoPix;
    m_fondoEscalado = QPixmap();
    m_tamanoPrevio = QSize();

    m_progresoTransicion = 0.0;
    m_anim->stop();
    m_anim->start();
}

void Escritorio::cargarFondo()
{
    QString rutaFondo;

    // 1. Archivo ~/.config/titan/wallpaper
    const QString userCfg = QDir::homePath() + QStringLiteral("/.config/titan/wallpaper");
    if (QFile::exists(userCfg)) {
        QFile f(userCfg);
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QString linea = QString::fromUtf8(f.readLine()).trimmed();
            if (!linea.isEmpty() && QFile::exists(linea)) {
                rutaFondo = linea;
            }
        }
    }

    // 2. Archivo ~/.config/titan/theme.conf
    if (rutaFondo.isEmpty()) {
        const QString themeConf = QDir::homePath() + QStringLiteral("/.config/titan/theme.conf");
        if (QFile::exists(themeConf)) {
            QSettings s(themeConf, QSettings::IniFormat);
            QString w = s.value(QStringLiteral("Theme/wallpaper")).toString();
            if (!w.isEmpty() && QFile::exists(w)) {
                rutaFondo = w;
            }
        }
    }

    // 3. Predeterminados
    if (rutaFondo.isEmpty()) {
        if (QFile::exists(QStringLiteral("/usr/share/titan/wallpaper.jpg"))) {
            rutaFondo = QStringLiteral("/usr/share/titan/wallpaper.jpg");
        } else if (QFile::exists(QStringLiteral(":/wallpaper.jpg"))) {
            rutaFondo = QStringLiteral(":/wallpaper.jpg");
        }
    }

    if (!rutaFondo.isEmpty() && QFile::exists(rutaFondo)) {
        if (m_rutaActual.isEmpty()) {
            m_rutaActual = rutaFondo;
            m_fondo.load(rutaFondo);
            m_fondoEscalado = QPixmap();
            m_tamanoPrevio = QSize();
            m_progresoTransicion = 1.0;
            update();
        } else if (rutaFondo != m_rutaActual) {
            cambiarFondo(rutaFondo);
        }
    }
}

void Escritorio::paintEvent(QPaintEvent *)
{
    QPainter pintor(this);
    pintor.setRenderHint(QPainter::Antialiasing);
    pintor.setRenderHint(QPainter::SmoothPixmapTransform);

    // Si hay animación de transición activa entre dos fondos
    if (m_anim->state() == QAbstractAnimation::Running && !m_fondoPrevio.isNull()) {
        // Escalar fondo previo si es necesario
        if (m_fondoPrevioEscalado.isNull() || m_fondoPrevioEscalado.size() != size()) {
            m_fondoPrevioEscalado = m_fondoPrevio.scaled(size(), Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
        }
        int px = (width() - m_fondoPrevioEscalado.width()) / 2;
        int py = (height() - m_fondoPrevioEscalado.height()) / 2;
        pintor.setOpacity(1.0 - m_progresoTransicion);
        pintor.drawPixmap(px, py, m_fondoPrevioEscalado);

        // Escalar fondo nuevo
        if (m_fondoEscalado.isNull() || m_tamanoPrevio != size()) {
            m_tamanoPrevio = size();
            m_fondoEscalado = m_fondo.scaled(size(), Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
        }
        int nx = (width() - m_fondoEscalado.width()) / 2;
        int ny = (height() - m_fondoEscalado.height()) / 2;
        pintor.setOpacity(m_progresoTransicion);
        pintor.drawPixmap(nx, ny, m_fondoEscalado);
        return;
    }

    // Dibujo normal de un solo fondo
    if (!m_fondo.isNull()) {
        if (m_fondoEscalado.isNull() || size() != m_tamanoPrevio) {
            m_tamanoPrevio = size();
            m_fondoEscalado = m_fondo.scaled(size(), Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
        }
        int x = (width() - m_fondoEscalado.width()) / 2;
        int y = (height() - m_fondoEscalado.height()) / 2;
        pintor.setOpacity(1.0);
        pintor.drawPixmap(x, y, m_fondoEscalado);
        return;
    }

    // Degradado de respaldo
    const Config &cfg = Config::instancia();
    QLinearGradient degradado(0, 0, width(), height());
    degradado.setColorAt(0.0, QColor(cfg.fondoColor1()));
    degradado.setColorAt(1.0, QColor(cfg.fondoColor2()));
    pintor.fillRect(rect(), degradado);
}
