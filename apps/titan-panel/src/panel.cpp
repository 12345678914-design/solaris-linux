#include "panel.h"

#include "catalogo.h"
#include "centro.h"
#include "config.h"
#include "iconos.h"
#include "layershell.h"

#include <QAction>
#include <QColor>
#include <QDateTime>
#include <QDebug>
#include <QFontMetrics>
#include <QGuiApplication>
#include <QHBoxLayout>
#include <QHash>
#include <QLabel>
#include <QMenu>
#include <QPainter>
#include <QProcess>
#include <QScreen>
#include <QStringList>
#include <QTimer>
#include <QToolButton>

namespace {

QString conAlfa(const QColor &color, double alfa)
{
    return QStringLiteral("rgba(%1, %2, %3, %4)")
        .arg(color.red())
        .arg(color.green())
        .arg(color.blue())
        .arg(alfa, 0, 'f', 2);
}

QString elidir(const QString &texto, int ancho, const QFont &fuente)
{
    return QFontMetrics(fuente).elidedText(texto, Qt::ElideRight, ancho);
}

} // namespace

Panel::Panel(Catalogo *catalogo, MonitorTareas *tareas, QWidget *padre)
    : QWidget(padre)
    , m_catalogo(catalogo)
    , m_tareas(tareas)
{
    const Config &cfg = Config::instancia();
    setWindowFlags(Qt::FramelessWindowHint | Qt::Window);
    setAttribute(Qt::WA_TranslucentBackground);
    setFixedHeight(cfg.barraAlto());
    setObjectName(QStringLiteral("panel"));

    setStyleSheet(QStringLiteral(
        "QToolButton {"
        "  color: #e8ecff;"
        "  background: transparent;"
        "  border: 1px solid transparent;"
        "  border-radius: 8px;"
        "  padding: 3px 8px;"
        "  font-size: 9.5pt;"
        "}"
        "QToolButton:hover { background: rgba(255, 255, 255, 0.10); }"
        "QToolButton:pressed { background: rgba(255, 255, 255, 0.18); }"
        "QLabel#reloj {"
        "  color: #dbe4ff;"
        "  font-size: 10.5pt;"
        "  padding: 0 6px;"
        "}"));

    auto *fila = new QHBoxLayout(this);
    fila->setContentsMargins(12, 0, 14, 0);
    fila->setSpacing(6);
    auto *contenedorCentral = new QWidget(this);
    auto *layoutCentral = new QHBoxLayout(contenedorCentral);
    layoutCentral->setContentsMargins(0, 0, 0, 0);
    layoutCentral->setSpacing(6);

    m_inicio = new QToolButton(contenedorCentral);
    m_inicio->setIcon(iconoInicio());
    m_inicio->setIconSize(QSize(26, 26));
    m_inicio->setToolButtonStyle(Qt::ToolButtonIconOnly);
    m_inicio->setToolTip(cfg.inicioTexto());
    m_inicio->setAccessibleName(cfg.inicioTexto());
    m_inicio->setCursor(Qt::PointingHandCursor);
    m_inicio->setFixedSize(qMax(38, cfg.barraAlto() - 10),
                           qMax(34, cfg.barraAlto() - 16));
    m_inicio->setStyleSheet(QStringLiteral(
        "QToolButton {"
        "  background: rgba(79, 196, 255, 0.18);"
        "  border: 1px solid #4fc4ff;"
        "  border-radius: 9px;"
        "  padding: 0;"
        "}"
        "QToolButton:hover { background: rgba(79, 196, 255, 0.30); }"));
    layoutCentral->addWidget(m_inicio);

    // Las ancladas usan el mismo icono que su entrada del menu de inicio.
    // utilities-terminal y system-file-manager solo existen en AdwaitaLegacy;
    // con el tema hicolor del live se quedaban en la inicial T/A. kitty y
    // pcmanfm-qt si estan en hicolor y son las entradas reales del catalogo.
    m_terminal = crearAnclada(QStringLiteral("kitty"),
                              QStringLiteral("utilities-terminal"),
                              QStringLiteral("Terminal"));
    m_archivos = crearAnclada(QStringLiteral("pcmanfm-qt"),
                              QStringLiteral("system-file-manager"),
                              QStringLiteral("Archivos"));
    layoutCentral->addWidget(m_terminal);
    layoutCentral->addWidget(m_archivos);

    m_zonaTareas = new QWidget(this);
    m_zonaTareas->setAttribute(Qt::WA_TranslucentBackground);
    m_filaTareas = new QHBoxLayout(m_zonaTareas);
    m_filaTareas->setContentsMargins(0, 0, 0, 0);
    m_filaTareas->setSpacing(6);
    layoutCentral->addWidget(m_zonaTareas);
    layoutCentral->addStretch(1);

    fila->addStretch(1);
    fila->addWidget(contenedorCentral);
    fila->addStretch(1);

    m_reloj = new QLabel(this);
    m_reloj->setObjectName(QStringLiteral("reloj"));
    fila->addWidget(m_reloj);

    connect(m_terminal, &QToolButton::clicked, this,
            [this] { abrirAnclada(true); });
    connect(m_archivos, &QToolButton::clicked, this,
            [this] { abrirAnclada(false); });
    connect(m_inicio, &QToolButton::clicked, this, &Panel::abrirCentro);

    m_centro = new Centro(m_catalogo, nullptr);

    if (m_tareas) {
        connect(m_tareas, &MonitorTareas::cambiado,
                this, &Panel::reconstruirTareas);
    }

    auto *reloj = new QTimer(this);
    connect(reloj, &QTimer::timeout, this, &Panel::actualizarReloj);
    reloj->start(30000);
    actualizarReloj();

    const bool capa = TitanCapa::aplicar(
        this, TitanCapa::Capa::Barra, cfg.barraAlto(), false,
        QStringLiteral("titan-panel"));
    if (!capa) {
        qWarning() << "titan-panel: barra sin layer-shell";
        if (QScreen *pantalla = QGuiApplication::primaryScreen()) {
            const QRect area = pantalla->geometry();
            setGeometry(area.x(),
                        area.y() + area.height() - cfg.barraAlto(),
                        area.width(), cfg.barraAlto());
        }
    }

    reconstruirTareas();
}

Panel::~Panel()
{
    delete m_centro;
    m_centro = nullptr;
}

QToolButton *Panel::crearAnclada(const QString &appId,
                                 const QString &iconoRespaldo,
                                 const QString &texto)
{
    auto *boton = new QToolButton(this);
    const int lado = qMax(34, Config::instancia().barraAlto() - 14);
    QString icono;
    if (m_catalogo) {
        icono = m_catalogo->iconoParaAppId(appId);
    }
    if (icono.isEmpty()) {
        icono = iconoRespaldo;
    }
    boton->setIcon(iconoAplicacion(icono, texto));
    boton->setIconSize(QSize(24, 24));
    boton->setToolButtonStyle(Qt::ToolButtonIconOnly);
    boton->setToolTip(texto);
    boton->setAccessibleName(texto);
    boton->setCursor(Qt::PointingHandCursor);
    boton->setAutoRaise(true);
    boton->setFixedSize(lado, lado);
    return boton;
}

QVector<Panel::Grupo> Panel::agrupar() const
{
    QVector<Grupo> grupos;
    QHash<QString, int> indices;
    if (!m_tareas) {
        return grupos;
    }
    for (const Ventana &ventana : m_tareas->ventanas()) {
        const QString clave = ventana.appId.isEmpty()
                                  ? ventana.titulo
                                  : ventana.appId;
        auto it = indices.find(clave);
        if (it == indices.end()) {
            Grupo grupo;
            grupo.appId = clave;
            grupos << grupo;
            indices.insert(clave, grupos.size() - 1);
            it = indices.find(clave);
        }
        grupos[it.value()].ventanas << ventana;
    }
    return grupos;
}

QString Panel::nombreGrupo(const Grupo &grupo) const
{
    if (m_catalogo) {
        if (const Aplicacion *app = m_catalogo->buscarPorAppId(grupo.appId)) {
            return app->nombre;
        }
    }
    if (!grupo.ventanas.isEmpty() &&
        !grupo.ventanas.first().titulo.isEmpty()) {
        return grupo.ventanas.first().titulo;
    }
    return grupo.appId.isEmpty() ? QStringLiteral("Ventana") : grupo.appId;
}

QString Panel::iconoGrupo(const Grupo &grupo) const
{
    if (m_catalogo) {
        const QString icono = m_catalogo->iconoParaAppId(grupo.appId);
        if (!icono.isEmpty()) {
            return icono;
        }
    }
    return grupo.appId;
}

void Panel::limpiarTareas()
{
    while (QLayoutItem *item = m_filaTareas->takeAt(0)) {
        if (QWidget *widget = item->widget()) {
            widget->hide();
            widget->deleteLater();
        }
        delete item;
    }
}

void Panel::reconstruirTareas()
{
    if (!m_filaTareas) {
        return;
    }
    limpiarTareas();

    const QVector<Grupo> grupos = agrupar();
    QStringList firma;
    for (const Grupo &grupo : grupos) {
        firma << grupo.appId;
        for (const Ventana &ventana : grupo.ventanas) {
            firma << ventana.titulo
                  << (ventana.activa ? "A" : "-")
                  << (ventana.minimizada ? "M" : "-")
                  << (ventana.maximizada ? "X" : "-");
        }
    }
    if (firma.join(QLatin1Char('|')) != m_firma) {
        m_firma = firma.join(QLatin1Char('|'));
        qWarning().noquote() << "titan-panel: ventanas:" << m_firma;
    }

    const QColor acento(Config::instancia().barraAcento());
    for (const Grupo &grupo : grupos) {
        bool activa = false;
        bool todasMinimizadas = true;
        for (const Ventana &ventana : grupo.ventanas) {
            activa = activa || ventana.activa;
            todasMinimizadas = todasMinimizadas && ventana.minimizada;
        }

        auto *boton = new QToolButton(m_zonaTareas);
        const int lado = qMax(34, Config::instancia().barraAlto() - 14);
        boton->setToolButtonStyle(Qt::ToolButtonIconOnly);
        boton->setIcon(iconoAplicacion(iconoGrupo(grupo),
                                       nombreGrupo(grupo)));
        boton->setIconSize(QSize(24, 24));
        boton->setAutoRaise(true);
        boton->setCursor(Qt::PointingHandCursor);
        boton->setFixedSize(lado, lado);
        boton->setAccessibleName(nombreGrupo(grupo));

        QStringList pistas;
        for (const Ventana &ventana : grupo.ventanas) {
            QString pista = ventana.titulo.isEmpty()
                                ? nombreGrupo(grupo)
                                : ventana.titulo;
            if (ventana.minimizada) {
                pista += QStringLiteral(" (minimizada)");
            }
            pistas << pista;
        }
        if (grupo.ventanas.size() > 1) {
            pistas.prepend(QStringLiteral("%1 ventanas")
                               .arg(grupo.ventanas.size()));
        }
        boton->setToolTip(pistas.join(QLatin1Char('\n')));

        const QString color = todasMinimizadas
                                  ? QStringLiteral("#8a94ab")
                                  : QStringLiteral("#eef2ff");
        const QString fondo = activa
                                  ? conAlfa(acento, 0.24)
                                  : QStringLiteral(
                                        "rgba(255, 255, 255, 0.06)");
        const QString borde = activa
                                  ? acento.name()
                                  : QStringLiteral("transparent");
        boton->setStyleSheet(
            QStringLiteral("QToolButton { background: %1;"
                           " border: 1px solid %2; border-radius: 9px;"
                           " color: %3; padding: 0; }"
                           "QToolButton:hover {"
                           " background: rgba(255, 255, 255, 0.14); }")
                .arg(fondo, borde, color));

        connect(boton, &QToolButton::clicked, this,
                [this, grupo, boton] { alPulsarGrupo(grupo, boton); });
        boton->setContextMenuPolicy(Qt::CustomContextMenu);
        connect(boton, &QToolButton::customContextMenuRequested, this,
                [this, grupo, boton](const QPoint &) {
                    mostrarMenuGrupo(grupo, boton);
                });

        m_filaTareas->addWidget(boton);
    }
    m_filaTareas->addStretch(1);
}

void Panel::alPulsarGrupo(const Grupo &grupo, QWidget *origen)
{
    if (grupo.ventanas.isEmpty() || !m_tareas) {
        return;
    }
    if (grupo.ventanas.size() > 1) {
        mostrarMenuGrupo(grupo, origen);
        return;
    }
    const Ventana &ventana = grupo.ventanas.first();
    if (ventana.activa) {
        qWarning().noquote() << "titan-panel: minimizar" << ventana.titulo;
        m_tareas->minimizar(ventana.id, true);
    } else {
        qWarning().noquote() << "titan-panel: activar" << ventana.titulo;
        m_tareas->activar(ventana.id);
    }
}

void Panel::mostrarMenuGrupo(const Grupo &grupo, QWidget *origen)
{
    if (!m_tareas || !origen) {
        return;
    }
    QMenu menu(this);
    menu.setStyleSheet(QStringLiteral(
        "QMenu { background: #141a2e; color: #e8ecff;"
        " border: 1px solid #33405f; padding: 4px; }"
        "QMenu::item:selected { background: #2b3b66; }"
        "QMenu::item:disabled { color: #7f8aa5; }"));

    for (const Ventana &ventana : grupo.ventanas) {
        QString titulo = ventana.titulo.isEmpty()
                             ? nombreGrupo(grupo)
                             : ventana.titulo;
        if (ventana.minimizada) {
            titulo += QStringLiteral(" (minimizada)");
        }
        QAction *accion = menu.addAction(elidir(titulo, 320, menu.font()));
        accion->setCheckable(true);
        accion->setChecked(ventana.activa);
        const quintptr id = ventana.id;
        connect(accion, &QAction::triggered, this,
                [this, id] { m_tareas->activar(id); });
    }

    menu.addSeparator();
    if (grupo.ventanas.size() == 1) {
        const Ventana &ventana = grupo.ventanas.first();
        QAction *minimizar = menu.addAction(
            ventana.minimizada ? QStringLiteral("Restaurar")
                               : QStringLiteral("Minimizar"));
        const quintptr id = ventana.id;
        const bool estaMinimizada = ventana.minimizada;
        connect(minimizar, &QAction::triggered, this,
                [this, id, estaMinimizada] {
                    if (estaMinimizada) {
                        m_tareas->activar(id);
                    } else {
                        m_tareas->minimizar(id, true);
                    }
                });
    } else {
        QAction *minimizar = menu.addAction(
            QStringLiteral("Minimizar todas"));
        connect(minimizar, &QAction::triggered, this, [this, grupo] {
            for (const Ventana &ventana : grupo.ventanas) {
                m_tareas->minimizar(ventana.id, true);
            }
        });
    }

    QAction *cerrar = menu.addAction(
        grupo.ventanas.size() == 1 ? QStringLiteral("Cerrar")
                                   : QStringLiteral("Cerrar todas"));
    connect(cerrar, &QAction::triggered, this, [this, grupo] {
        for (const Ventana &ventana : grupo.ventanas) {
            m_tareas->cerrar(ventana.id);
        }
    });

    const QPoint origenGlobal = origen->mapToGlobal(QPoint(0, 0));
    menu.ensurePolished();
    menu.adjustSize();
    int x = origenGlobal.x();
    int y = origenGlobal.y() - menu.height();
    if (QScreen *pantalla = origen->screen()) {
        const QRect area = pantalla->geometry();
        if (y < area.top()) {
            y = origenGlobal.y() + origen->height();
        }
        x = qBound(area.left(), x, area.right() - menu.width());
        y = qBound(area.top(), y, area.bottom() - menu.height());
    }
    menu.exec(QPoint(x, y));
}

void Panel::abrirAnclada(bool terminal)
{
    const QString clave = terminal ? QStringLiteral("kitty")
                                   : QStringLiteral("pcmanfm");
    for (const Grupo &grupo : agrupar()) {
        if (grupo.appId.contains(clave, Qt::CaseInsensitive)) {
            alPulsarGrupo(grupo, terminal ? m_terminal : m_archivos);
            return;
        }
    }
    const Config &cfg = Config::instancia();
    lanzarPrograma(terminal ? cfg.terminal() : cfg.explorador());
}

void Panel::lanzarPrograma(const QString &programa)
{
    QStringList partes = QProcess::splitCommand(programa);
    if (partes.isEmpty()) {
        qWarning() << "titan-panel: programa vacio";
        return;
    }
    const QString ejecutable = partes.takeFirst();
    if (!QProcess::startDetached(ejecutable, partes)) {
        qWarning().noquote() << "titan-panel: no se pudo lanzar" << programa;
    } else {
        qWarning().noquote() << "titan-panel: lanzado" << programa;
    }
}

void Panel::abrirCentro()
{
    if (m_centro) {
        m_centro->abrir();
    }
}

void Panel::actualizarReloj()
{
    m_reloj->setText(QDateTime::currentDateTime().toString(
        QStringLiteral("ddd d MMM  HH:mm")));
}

void Panel::paintEvent(QPaintEvent *)
{
    const Config &cfg = Config::instancia();
    QColor fondo(cfg.barraFondo());
    if (!fondo.isValid()) {
        fondo = QColor(QStringLiteral("#0b1020"));
    }
    fondo.setAlphaF(cfg.barraAlfa());

    QPainter pintor(this);
    pintor.fillRect(rect(), fondo);
    pintor.setPen(QColor(cfg.barraAcento()));
    pintor.drawLine(0, 0, width(), 0);
}
