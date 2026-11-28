// Inti OS - titan-polkit: agente de autenticacion de polkit para la sesion.
//
// Lo arranca titan-sesion. La ventana es una capa "overlay" de layer-shell
// que ocupa toda la pantalla (fondo oscurecido + tarjeta centrada) y se queda
// con el teclado mientras esta abierta, para que la contrasena no acabe
// escrita en otra ventana.
//
//   TITAN_POLKIT_DEMO=1 titan-polkit   ensena la ventana sin polkitd (pruebas)
#include "Agente.h"
#include "ThemeManager.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QDebug>
#include <unistd.h>

#include <PolkitQt1/Subject>
#include <LayerShellQt/window.h>

int main(int argc, char *argv[])
{
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("titan-polkit"));
    app.setDesktopFileName(QStringLiteral("titan-polkit"));
    app.setQuitOnLastWindowClosed(false);

    const bool demo = qEnvironmentVariableIsSet("TITAN_POLKIT_DEMO");
    Agente agente;

    if (!demo) {
        // El agente se registra para la sesion de este proceso (logind).
        PolkitQt1::UnixSessionSubject sesion(getpid());
        if (!agente.registerListener(sesion, QStringLiteral("/org/intios/PolicyKit1/AuthenticationAgent"))) {
            qCritical() << "titan-polkit: no se pudo registrar el agente (¿ya hay otro agente en esta sesion?)";
            return 1;
        }
    }

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("agente"), &agente);
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());
    engine.load(QUrl(QStringLiteral("qrc:/qml/Dialogo.qml")));
    if (engine.rootObjects().isEmpty())
        return 1;

    auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    if (win && QGuiApplication::platformName().startsWith(QStringLiteral("wayland"))) {
        win->create();
        if (auto *ls = LayerShellQt::Window::get(win)) {
            ls->setLayer(LayerShellQt::Window::LayerOverlay);
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorTop;
            a |= LayerShellQt::Window::AnchorBottom;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            ls->setAnchors(a);
            ls->setExclusiveZone(-1);
            ls->setScope(QStringLiteral("titan-polkit"));
            ls->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
        }
    }
    if (win) {
        auto actualizar = [win, &agente]() { win->setVisible(agente.activo()); };
        QObject::connect(&agente, &Agente::cambiado, win, actualizar);
        actualizar();
    }

    if (demo)
        agente.demostracion();

    return app.exec();
}
