#include "centro.h"

#include "catalogo.h"
#include "iconos.h"
#include "layershell.h"
#include "config.h"

#include <QDebug>
#include <QFontMetrics>
#include <QFrame>
#include <QGridLayout>
#include <QGuiApplication>
#include <QHBoxLayout>
#include <QKeySequence>
#include <QLabel>
#include <QLineEdit>
#include <QMouseEvent>
#include <QPainter>
#include <QProcess>
#include <QScreen>
#include <QScrollArea>
#include <QShortcut>
#include <QStringList>
#include <QToolButton>
#include <QVBoxLayout>

Centro::Centro(Catalogo *catalogo, QWidget *padre)
    : QWidget(padre)
    , m_catalogo(catalogo)
{
    setWindowFlags(Qt::FramelessWindowHint | Qt::Window);
    setAttribute(Qt::WA_TranslucentBackground);
    setObjectName(QStringLiteral("centro"));
    construir();

    const Config &cfg = Config::instancia();
    QScreen *pantalla = QGuiApplication::primaryScreen();
    const QRect area = pantalla ? pantalla->geometry()
                                : QRect(0, 0, 1280, 720);
    const int ancho = qMin(cfg.centroAncho(), area.width() - 40);
    const int alto = qMin(cfg.centroAlto(), area.height() - 40);
    m_tarjeta->setFixedSize(ancho, alto);
    setGeometry(area);

    const bool capa = TitanCapa::aplicar(
        this, TitanCapa::Capa::Centro, -1, true,
        QStringLiteral("titan-centro"));
    if (!capa) {
        qWarning() << "titan-panel: centro sin layer-shell";
    }

    auto *escape = new QShortcut(QKeySequence(Qt::Key_Escape), this);
    connect(escape, &QShortcut::activated, this, &Centro::cerrar);
}

void Centro::construir()
{
    auto *raiz = new QVBoxLayout(this);
    raiz->setContentsMargins(0, 0, 0, 0);
    raiz->addStretch(1);

    auto *fila = new QHBoxLayout();
    fila->addStretch(1);

    m_tarjeta = new QFrame(this);
    m_tarjeta->setObjectName(QStringLiteral("tarjeta"));
    m_tarjeta->setAttribute(Qt::WA_StyledBackground, true);
    fila->addWidget(m_tarjeta);
    fila->addStretch(1);
    raiz->addLayout(fila);
    raiz->addStretch(1);

    auto *columna = new QVBoxLayout(m_tarjeta);
    columna->setContentsMargins(28, 24, 28, 20);
    columna->setSpacing(12);

    auto *titulo = new QLabel(QStringLiteral("Aplicaciones"), m_tarjeta);
    titulo->setObjectName(QStringLiteral("titulo"));
    columna->addWidget(titulo);

    auto *sub = new QLabel(
        QStringLiteral("Busca por nombre o abre cualquier programa instalado."),
        m_tarjeta);
    sub->setObjectName(QStringLiteral("subtitulo"));
    sub->setWordWrap(true);
    columna->addWidget(sub);

    m_busqueda = new QLineEdit(m_tarjeta);
    m_busqueda->setObjectName(QStringLiteral("busqueda"));
    m_busqueda->setPlaceholderText(QStringLiteral("Buscar aplicaciones..."));
    m_busqueda->setClearButtonEnabled(true);
    m_busqueda->setMinimumHeight(40);
    columna->addWidget(m_busqueda);
    connect(m_busqueda, &QLineEdit::textChanged,
            this, &Centro::filtrar);

    m_desplazamiento = new QScrollArea(m_tarjeta);
    m_desplazamiento->setObjectName(QStringLiteral("lista"));
    m_desplazamiento->setWidgetResizable(true);
    m_desplazamiento->setFrameShape(QFrame::NoFrame);
    m_desplazamiento->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    m_desplazamiento->setVerticalScrollBarPolicy(Qt::ScrollBarAsNeeded);

    m_contenedor = new QWidget(m_desplazamiento);
    m_contenedor->setObjectName(QStringLiteral("contenedor"));
    m_rejilla = new QGridLayout(m_contenedor);
    m_rejilla->setContentsMargins(0, 0, 0, 0);
    m_rejilla->setHorizontalSpacing(8);
    m_rejilla->setVerticalSpacing(8);
    m_rejilla->setAlignment(Qt::AlignTop | Qt::AlignHCenter);
    m_desplazamiento->setWidget(m_contenedor);
    columna->addWidget(m_desplazamiento, 1);

    m_aviso = new QLabel(m_tarjeta);
    m_aviso->setObjectName(QStringLiteral("aviso"));
    m_aviso->setWordWrap(true);
    m_aviso->hide();
    columna->addWidget(m_aviso);

    auto *separador = new QFrame(m_tarjeta);
    separador->setObjectName(QStringLiteral("separador"));
    separador->setFrameShape(QFrame::HLine);
    columna->addWidget(separador);

    auto *filaEnergia = new QHBoxLayout();
    filaEnergia->setSpacing(10);
    filaEnergia->addStretch(1);

    auto *apagar = new QToolButton(m_tarjeta);
    apagar->setObjectName(QStringLiteral("apagar"));
    apagar->setText(QStringLiteral("Apagar"));
    apagar->setIcon(iconoAplicacion(QStringLiteral("system-shutdown"),
                                    QStringLiteral("Apagar")));
    apagar->setIconSize(QSize(20, 20));
    apagar->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
    apagar->setCursor(Qt::PointingHandCursor);
    apagar->setMinimumHeight(36);
    connect(apagar, &QToolButton::clicked, this, &Centro::apagar);
    filaEnergia->addWidget(apagar);

    auto *reiniciar = new QToolButton(m_tarjeta);
    reiniciar->setObjectName(QStringLiteral("reiniciar"));
    reiniciar->setText(QStringLiteral("Reiniciar"));
    reiniciar->setIcon(iconoAplicacion(QStringLiteral("system-reboot"),
                                       QStringLiteral("Reiniciar")));
    reiniciar->setIconSize(QSize(20, 20));
    reiniciar->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
    reiniciar->setCursor(Qt::PointingHandCursor);
    reiniciar->setMinimumHeight(36);
    connect(reiniciar, &QToolButton::clicked, this, &Centro::reiniciar);
    filaEnergia->addWidget(reiniciar);

    filaEnergia->addStretch(1);
    columna->addLayout(filaEnergia);

    setStyleSheet(QStringLiteral(
        "#centro { background: transparent; }"
        "QFrame#tarjeta {"
        "  background: rgba(10, 15, 32, 0.98);"
        "  border: 1px solid rgba(120, 160, 255, 0.30);"
        "  border-radius: 20px;"
        "}"
        "QLabel#titulo { color: #eef2ff; font-size: 22pt;"
        "                font-weight: 700; }"
        "QLabel#subtitulo { color: #98a6c8; font-size: 10pt; }"
        "QLabel#aviso { color: #ff9f9f; font-size: 9pt; }"
        "QFrame#separador { color: rgba(255, 255, 255, 0.12); }"
        "QToolButton#apagar {"
        "  color: #ffd6d6;"
        "  background: rgba(190, 60, 60, 0.16);"
        "  border: 1px solid rgba(255, 120, 120, 0.35);"
        "}"
        "QToolButton#apagar:hover { background: rgba(190, 60, 60, 0.32); }"
        "QToolButton#reiniciar {"
        "  color: #d9ecff;"
        "  background: rgba(79, 196, 255, 0.12);"
        "  border: 1px solid rgba(79, 196, 255, 0.35);"
        "}"
        "QToolButton#reiniciar:hover {"
        "  background: rgba(79, 196, 255, 0.28);"
        "}"
        "QLineEdit#busqueda {"
        "  background: rgba(255, 255, 255, 0.08);"
        "  color: #eef2ff;"
        "  border: 1px solid rgba(255, 255, 255, 0.18);"
        "  border-radius: 10px;"
        "  padding: 8px 12px;"
        "  font-size: 11pt;"
        "}"
        "QLineEdit#busqueda:focus { border-color: #4fc4ff; }"
        "QScrollArea#lista, QWidget#contenedor { background: transparent; }"
        "QToolButton {"
        "  color: #e8ecff;"
        "  background: transparent;"
        "  border: 1px solid transparent;"
        "  border-radius: 12px;"
        "  padding: 7px;"
        "}"
        "QToolButton:hover {"
        "  background: rgba(255, 255, 255, 0.10);"
        "  border-color: rgba(120, 160, 255, 0.35);"
        "}"
        "QToolButton:pressed { background: rgba(255, 255, 255, 0.18); }"
        "QScrollBar:vertical {"
        "  background: transparent; width: 8px; margin: 0;"
        "}"
        "QScrollBar::handle:vertical {"
        "  background: rgba(255, 255, 255, 0.25);"
        "  border-radius: 4px; min-height: 24px;"
        "}"
        "QScrollBar::add-line:vertical,"
        "QScrollBar::sub-line:vertical { height: 0; }"));

    reconstruir();
}

void Centro::limpiarRejilla()
{
    while (QLayoutItem *item = m_rejilla->takeAt(0)) {
        if (QWidget *widget = item->widget()) {
            widget->deleteLater();
        }
        delete item;
    }
}

void Centro::reconstruir()
{
    limpiarRejilla();
    const QString filtro = m_busqueda->text().trimmed();
    const int columnas = Config::instancia().centroColumnas();
    int indice = 0;

    for (const Aplicacion &app : m_catalogo->aplicaciones()) {
        if (!filtro.isEmpty() &&
            !app.nombre.contains(filtro, Qt::CaseInsensitive) &&
            !app.comentario.contains(filtro, Qt::CaseInsensitive) &&
            !app.id.contains(filtro, Qt::CaseInsensitive)) {
            continue;
        }

        auto *boton = new QToolButton(m_contenedor);
        boton->setToolButtonStyle(Qt::ToolButtonTextUnderIcon);
        boton->setIcon(iconoAplicacion(app.icono, app.nombre));
        boton->setIconSize(QSize(48, 48));
        boton->setFixedSize(132, 112);
        boton->setAutoRaise(true);
        boton->setCursor(Qt::PointingHandCursor);
        boton->setToolTip(app.comentario.isEmpty() ? app.nombre
                                                   : app.comentario);
        const QFontMetrics medidas(boton->font());
        boton->setText(medidas.elidedText(
            app.nombre, Qt::ElideRight, 120));

        const QString id = app.id;
        connect(boton, &QToolButton::clicked, this,
                [this, id] { lanzar(id); });

        const int columna = indice % columnas;
        const int fila = indice / columnas;
        m_rejilla->addWidget(boton, fila, columna, Qt::AlignCenter);
        ++indice;
    }

    if (indice == 0) {
        auto *vacio = new QLabel(
            QStringLiteral("No hay aplicaciones que coincidan."),
            m_contenedor);
        vacio->setAlignment(Qt::AlignCenter);
        vacio->setStyleSheet(QStringLiteral(
            "color: #98a6c8; font-size: 11pt; padding: 30px;"));
        m_rejilla->addWidget(vacio, 0, 0, 1, columnas);
    }
    for (int i = 0; i < columnas; ++i) {
        m_rejilla->setColumnStretch(i, 1);
    }
}

void Centro::filtrar(const QString &)
{
    reconstruir();
}

void Centro::lanzar(const QString &id)
{
    for (const Aplicacion &app : m_catalogo->aplicaciones()) {
        if (app.id != id) {
            continue;
        }
        QString error;
        if (Catalogo::lanzar(app, Config::instancia().terminal(), &error)) {
            m_aviso->hide();
            cerrar();
        } else {
            m_aviso->setText(error);
            m_aviso->show();
        }
        return;
    }
}

void Centro::abrir()
{
    qWarning() << "titan-panel: centro abierto";
    m_busqueda->clear();
    reconstruir();
    show();
    raise();
    m_busqueda->setFocus();
}

void Centro::cerrar()
{
    qWarning() << "titan-panel: centro cerrado";
    hide();
    m_busqueda->clear();
}

void Centro::apagar()
{
    ejecutarOrden(Config::instancia().apagar());
}

void Centro::reiniciar()
{
    ejecutarOrden(Config::instancia().reiniciar());
}

void Centro::ejecutarOrden(const QString &orden)
{
    qWarning().noquote() << "titan-panel: accion" << orden;
    QStringList partes = QProcess::splitCommand(orden);
    if (partes.isEmpty()) {
        return;
    }
    const QString programa = partes.takeFirst();
    if (!QProcess::startDetached(programa, partes)) {
        qWarning().noquote() << "titan-panel: no se pudo ejecutar" << orden;
        return;
    }
    cerrar();
}

bool Centro::estaAbierto() const
{
    return isVisible();
}

void Centro::paintEvent(QPaintEvent *)
{
    const double oscuridad = Config::instancia().centroOscuridad();
    QPainter pintor(this);
    pintor.fillRect(rect(), QColor(0, 0, 0,
                                   int(255.0 * oscuridad)));
}

void Centro::mousePressEvent(QMouseEvent *evento)
{
    if (evento->button() == Qt::LeftButton &&
        !m_tarjeta->geometry().contains(evento->position().toPoint())) {
        cerrar();
        return;
    }
    QWidget::mousePressEvent(evento);
}
