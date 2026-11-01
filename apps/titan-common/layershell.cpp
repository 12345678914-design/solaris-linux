#include "layershell.h"

#include <LayerShellQt/window.h>

#include <QGuiApplication>
#include <QScreen>
#include <QWidget>
#include <QWindow>

#include <QDebug>

namespace TitanCapa {

bool aplicar(QWidget *ventana, Capa capa, int zonaExclusiva,
             bool tecladoExclusivo, const QString &ambito)
{
    if (!ventana) {
        return false;
    }
    if (!QGuiApplication::platformName().startsWith(
            QStringLiteral("wayland"))) {
        return false;
    }

    // La superficie nativa tiene que existir antes de pedirle a LayerShellQt
    // que la convierta en layer-shell, pero no debe estar visible todavia.
    ventana->setAttribute(Qt::WA_NativeWindow);
    ventana->winId();
    QWindow *qw = ventana->windowHandle();
    if (!qw) {
        return false;
    }

    LayerShellQt::Window *ls = LayerShellQt::Window::get(qw);
    if (!ls) {
        return false;
    }

    switch (capa) {
    case Capa::Fondo:
        ls->setLayer(LayerShellQt::Window::LayerBackground);
        break;
    case Capa::Barra:
        ls->setLayer(LayerShellQt::Window::LayerTop);
        break;
    case Capa::Centro:
        ls->setLayer(LayerShellQt::Window::LayerOverlay);
        break;
    }

    LayerShellQt::Window::Anchors anclas =
        LayerShellQt::Window::AnchorTop;
    anclas |= LayerShellQt::Window::AnchorBottom;
    anclas |= LayerShellQt::Window::AnchorLeft;
    anclas |= LayerShellQt::Window::AnchorRight;
    if (capa == Capa::Barra) {
        anclas = LayerShellQt::Window::AnchorBottom;
        anclas |= LayerShellQt::Window::AnchorLeft;
        anclas |= LayerShellQt::Window::AnchorRight;
    }
    ls->setAnchors(anclas);
    ls->setExclusiveZone(zonaExclusiva);
    ls->setKeyboardInteractivity(
        tecladoExclusivo
            ? LayerShellQt::Window::KeyboardInteractivityExclusive
            : LayerShellQt::Window::KeyboardInteractivityNone);
    ls->setScope(ambito);
    ls->setActivateOnShow(capa == Capa::Centro);

    if (QScreen *pantalla = QGuiApplication::primaryScreen()) {
        ls->setScreen(pantalla);
        const QRect area = pantalla->geometry();
        if (capa == Capa::Barra) {
            // La barra solo ocupa su alto; el ancho lo decide el compositor
            // al estar anclada a izquierda y derecha.
            ventana->resize(area.width(), ventana->height());
        } else {
            ventana->setGeometry(area);
        }
    }
    return true;
}

} // namespace TitanCapa
