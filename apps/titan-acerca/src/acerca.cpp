#include "acerca.h"

#include "config.h"

#include <QApplication>
#include <QFile>
#include <QFont>
#include <QFormLayout>
#include <QGuiApplication>
#include <QHBoxLayout>
#include <QIcon>
#include <QKeySequence>
#include <QLabel>
#include <QPainter>
#include <QPushButton>
#include <QRegularExpression>
#include <QScreen>
#include <QShortcut>
#include <QStorageInfo>
#include <QStringList>
#include <QSysInfo>
#include <QVBoxLayout>
#include <QProcess>
#include <QDir>

namespace {

QString limpiar(const QString &texto)
{
    return texto.simplified();
}

QString formatearBytes(qint64 bytes)
{
    if (bytes <= 0) {
        return QStringLiteral("No disponible");
    }
    const double gib = 1024.0 * 1024.0 * 1024.0;
    const double mib = 1024.0 * 1024.0;
    if (bytes >= gib) {
        return QStringLiteral("%1 GiB").arg(bytes / gib, 0, 'f', 1);
    }
    if (bytes >= mib) {
        return QStringLiteral("%1 MiB").arg(bytes / mib, 0, 'f', 1);
    }
    return QStringLiteral("%1 KiB").arg(bytes / 1024.0, 0, 'f', 1);
}

QString leerProcesador()
{
    QFile fichero(QStringLiteral("/proc/cpuinfo"));
    if (fichero.open(QIODevice::ReadOnly | QIODevice::Text)) {
        while (true) {
            const QByteArray cruda = fichero.readLine();
            if (cruda.isEmpty()) {
                break;
            }
            const QString linea =
                QString::fromLocal8Bit(cruda).trimmed();
            const int dosPuntos = linea.indexOf(QLatin1Char(':'));
            if (dosPuntos <= 0) {
                continue;
            }
            const QString clave = linea.left(dosPuntos).trimmed();
            if (clave == QStringLiteral("model name") ||
                clave == QStringLiteral("Hardware") ||
                clave == QStringLiteral("Processor")) {
                const QString valor = limpiar(linea.mid(dosPuntos + 1));
                if (!valor.isEmpty()) {
                    return valor;
                }
            }
        }
    }
    return QSysInfo::prettyProductName();
}

QString leerRam()
{
    QFile fichero(QStringLiteral("/proc/meminfo"));
    if (!fichero.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QStringLiteral("No disponible");
    }
    while (true) {
        const QByteArray cruda = fichero.readLine();
        if (cruda.isEmpty()) {
            break;
        }
        const QString linea = QString::fromLocal8Bit(cruda).trimmed();
        if (!linea.startsWith(QStringLiteral("MemTotal:"))) {
            continue;
        }
        const QStringList partes = linea.split(
            QRegularExpression(QStringLiteral("\\s+")),
            Qt::SkipEmptyParts);
        if (partes.size() >= 2) {
            bool bien = false;
            const qint64 kib = partes.at(1).toLongLong(&bien);
            if (bien) {
                return formatearBytes(kib * 1024);
            }
        }
    }
    return QStringLiteral("No disponible");
}

QString leerDisco()
{
    const QStorageInfo raiz = QStorageInfo::root();
    if (!raiz.isValid()) {
        return QStringLiteral("No disponible");
    }
    return QStringLiteral("%1 libres de %2")
        .arg(formatearBytes(raiz.bytesAvailable()),
             formatearBytes(raiz.bytesTotal()));
}

QString leerGpu()
{
    QProcess proc;
    proc.start(QStringLiteral("sh"), {QStringLiteral("-c"), QStringLiteral("lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -n1 | cut -d':' -f3-")});
    if (proc.waitForFinished(1000)) {
        QString out = QString::fromLocal8Bit(proc.readAllStandardOutput()).trimmed();
        if (!out.isEmpty()) return out;
    }
    return QStringLiteral("Gráficos integrados / Genérico");
}

} // namespace

DatosEquipo leerDatosEquipo()
{
    DatosEquipo datos;
    datos.os = QStringLiteral("Inti OS");
    datos.version = QStringLiteral("1.0 (Edición Escritorio)");
    datos.kernel = QSysInfo::kernelType() + QStringLiteral(" ") + QSysInfo::kernelVersion();
    datos.equipo = QSysInfo::machineHostName();
    if (datos.equipo.isEmpty()) {
        datos.equipo = QStringLiteral("inti-pc");
    }
    datos.usuario = QString::fromLocal8Bit(qgetenv("USER"));
    if (datos.usuario.isEmpty()) {
        datos.usuario = QStringLiteral("inti");
    }
    datos.procesador = leerProcesador();
    datos.gpu = leerGpu();
    datos.ram = leerRam();
    datos.disco = leerDisco();
    datos.arquitectura = QSysInfo::currentCpuArchitecture();
    if (datos.arquitectura.isEmpty()) {
        datos.arquitectura = QStringLiteral("x86_64");
    }
    return datos;
}

QPixmap iconoComputadora(int lado)
{
    QPixmap lienzo(lado, lado);
    lienzo.fill(Qt::transparent);

    QPainter pintor(&lienzo);
    pintor.setRenderHint(QPainter::Antialiasing);

    const QColor acento(QStringLiteral("#4fc4ff"));
    const QColor fondo(QStringLiteral("#0b1020"));
    const QRectF marco(lado * 0.10, lado * 0.16,
                       lado * 0.80, lado * 0.56);

    pintor.setBrush(fondo);
    pintor.setPen(QPen(acento, qMax(2.0, lado * 0.025)));
    pintor.drawRoundedRect(marco, lado * 0.06, lado * 0.06);

    pintor.setBrush(QColor(QStringLiteral("#17345c")));
    pintor.setPen(Qt::NoPen);
    pintor.drawRoundedRect(marco.adjusted(lado * 0.06, lado * 0.06,
                                         -lado * 0.06, -lado * 0.12),
                           lado * 0.03, lado * 0.03);

    pintor.setBrush(acento);
    pintor.drawRoundedRect(QRectF(lado * 0.46, lado * 0.72,
                                 lado * 0.08, lado * 0.10),
                           lado * 0.02, lado * 0.02);
    pintor.drawRoundedRect(QRectF(lado * 0.30, lado * 0.82,
                                 lado * 0.40, lado * 0.06),
                           lado * 0.03, lado * 0.03);
    pintor.end();

    return lienzo;
}

QPixmap obtenerLogoSolaris(int lado)
{
    const QStringList rutas = {
        QStringLiteral(":/icons/icons/solaris-logo.png"),
        QStringLiteral("/usr/share/pixmaps/solaris-logo.png"),
        QStringLiteral("/usr/share/titan/solaris-logo.png"),
        QStringLiteral("apps/titan-acerca/icons/solaris-logo.png"),
        QStringLiteral(":/icons/icons/solaris-symbol.png")
    };
    for (const QString &ruta : rutas) {
        if (QFile::exists(ruta)) {
            QPixmap pix(ruta);
            if (!pix.isNull()) {
                return pix.scaled(lado, lado, Qt::KeepAspectRatio, Qt::SmoothTransformation);
            }
        }
    }
    return iconoComputadora(lado);
}

AcercaVentana::AcercaVentana(QWidget *padre)
    : QWidget(padre)
{
    setWindowTitle(QStringLiteral("Acerca de Inti OS"));
    setObjectName(QStringLiteral("acerca"));
    setWindowFlags(Qt::Window | Qt::WindowTitleHint | Qt::WindowSystemMenuHint |
                   Qt::WindowMinimizeButtonHint | Qt::WindowMaximizeButtonHint |
                   Qt::WindowCloseButtonHint);
    setFixedSize(560, 520);
    setWindowIcon(QIcon(obtenerLogoSolaris(64)));
    construir(leerDatosEquipo());

    if (QScreen *pantalla = QGuiApplication::primaryScreen()) {
        const QRect area = pantalla->availableGeometry();
        move(area.center() - rect().center());
    }

    auto *escape = new QShortcut(QKeySequence(Qt::Key_Escape), this);
    connect(escape, &QShortcut::activated, this, &QWidget::close);
}

void AcercaVentana::construir(const DatosEquipo &datos)
{
    setStyleSheet(QStringLiteral(
        "QWidget#acerca {"
        "  background: qlineargradient(x1:0, y1:0, x2:0, y2:1,"
        "    stop:0.0 rgba(36, 42, 62, 240),"
        "    stop:0.4 rgba(22, 27, 40, 235),"
        "    stop:1.0 rgba(13, 16, 26, 245));"
        "  border: 1px solid rgba(255, 255, 255, 0.14);"
        "}"
        "QLabel { color: #f2f5ff; }"
        "QLabel#equipo { font-size: 20pt; font-weight: 700; color: #ffffff; }"
        "QLabel#subtitulo { color: #a2b0d0; font-size: 10pt; }"
        "QLabel#clave { color: #9bb0d4; font-size: 10pt; font-weight: 600; }"
        "QLabel#valor { color: #f2f5ff; font-size: 10pt; }"
        "QPushButton {"
        "  background: qlineargradient(x1:0, y1:0, x2:0, y2:1,"
        "    stop:0.0 rgba(0, 113, 227, 0.85),"
        "    stop:1.0 rgba(0, 92, 190, 0.90));"
        "  color: #ffffff;"
        "  border: 1px solid rgba(255, 255, 255, 0.25);"
        "  border-radius: 8px;"
        "  padding: 8px 28px;"
        "  font-size: 10.5pt;"
        "  font-weight: 600;"
        "}"
        "QPushButton:hover {"
        "  background: qlineargradient(x1:0, y1:0, x2:0, y2:1,"
        "    stop:0.0 rgba(20, 133, 247, 0.92),"
        "    stop:1.0 rgba(0, 105, 215, 0.95));"
        "}"
        "QPushButton:pressed {"
        "  background: rgba(0, 80, 170, 0.95);"
        "}"));

    auto *raiz = new QVBoxLayout(this);
    raiz->setContentsMargins(36, 16, 36, 16);
    raiz->setSpacing(4);

    auto *icono = new QLabel(this);
    icono->setAlignment(Qt::AlignCenter);
    icono->setPixmap(obtenerLogoSolaris(80));
    raiz->addWidget(icono);

    auto *equipo = new QLabel(QStringLiteral("Inti OS"), this);
    equipo->setObjectName(QStringLiteral("equipo"));
    equipo->setAlignment(Qt::AlignCenter);
    raiz->addWidget(equipo);

    auto *subtitulo = new QLabel(datos.version, this);
    subtitulo->setObjectName(QStringLiteral("subtitulo"));
    subtitulo->setAlignment(Qt::AlignCenter);
    raiz->addWidget(subtitulo);

    auto *formulario = new QFormLayout();
    formulario->setContentsMargins(0, 8, 0, 4);
    formulario->setHorizontalSpacing(16);
    formulario->setVerticalSpacing(4);
    formulario->setLabelAlignment(Qt::AlignRight | Qt::AlignTop);
    formulario->setFormAlignment(Qt::AlignHCenter);

    auto agregar = [this, formulario](const QString &clave,
                                      const QString &valor) {
        auto *etiqueta = new QLabel(clave, this);
        etiqueta->setObjectName(QStringLiteral("clave"));
        auto *dato = new QLabel(valor, this);
        dato->setObjectName(QStringLiteral("valor"));
        dato->setWordWrap(true);
        dato->setTextInteractionFlags(Qt::TextSelectableByMouse);
        formulario->addRow(etiqueta, dato);
    };

    agregar(QStringLiteral("Sistema operativo:"), datos.os);
    agregar(QStringLiteral("Versión del kernel:"), datos.kernel);
    agregar(QStringLiteral("Procesador (CPU):"), datos.procesador);
    agregar(QStringLiteral("Gráficos (GPU):"), datos.gpu);
    agregar(QStringLiteral("Memoria (RAM):"), datos.ram);
    agregar(QStringLiteral("Almacenamiento:"), datos.disco);
    agregar(QStringLiteral("Usuario:"), datos.usuario);
    agregar(QStringLiteral("Nombre del equipo:"), datos.equipo);

    raiz->addLayout(formulario);
    raiz->addStretch(1);

    auto *aceptar = new QPushButton(QStringLiteral("Aceptar"), this);
    aceptar->setCursor(Qt::PointingHandCursor);
    aceptar->setMinimumSize(140, 32);
    aceptar->setDefault(true);
    connect(aceptar, &QPushButton::clicked, this, &QWidget::close);

    auto *filaBoton = new QHBoxLayout();
    filaBoton->addStretch(1);
    filaBoton->addWidget(aceptar);
    filaBoton->addStretch(1);
    raiz->addLayout(filaBoton);
}
