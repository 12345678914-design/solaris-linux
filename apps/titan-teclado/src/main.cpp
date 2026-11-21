// Inti OS - titan-teclado: teclado en pantalla.
//
//   titan-teclado          lo abre; si ya está abierto, lo cierra (un solo
//                          lanzador o atajo sirve para las dos cosas)
//
// Es una capa "top" de layer-shell pegada abajo, con zona exclusiva (las
// ventanas maximizadas se quedan por encima, no debajo) y SIN teclado: así el
// foco sigue en la app donde se escribe y wtype le manda las letras.
#include "Teclado.h"
#include "ThemeManager.h"

#include <QGuiApplication>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QScreen>

#include <LayerShellQt/window.h>

int main(int argc, char *argv[])
{
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("titan-teclado"));
    app.setDesktopFileName(QStringLiteral("titan-teclado"));

    // Ya abierto: se le pide que se cierre y ya está.
    const QString nombre = QStringLiteral("titan-teclado-%1").arg(qEnvironmentVariable("USER"));
    {
        QLocalSocket s;
        s.connectToServer(nombre);
        if (s.waitForConnected(300)) {
            s.write("salir\n");
            s.flush();
            s.waitForBytesWritten(300);
            return 0;
        }
    }
    QLocalServer::removeServer(nombre);
    QLocalServer servidor;
    servidor.listen(nombre);
    QObject::connect(&servidor, &QLocalServer::newConnection, &app, [&servidor] {
        while (QLocalSocket *c = servidor.nextPendingConnection()) {
            QObject::connect(c, &QLocalSocket::readyRead, c, [c] {
                if (c->readAll().startsWith("salir"))
                    QGuiApplication::quit();
            });
        }
    });

    Teclado teclado;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("teclado"), &teclado);
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());
    engine.load(QUrl(QStringLiteral("qrc:/qml/Teclado.qml")));
    if (engine.rootObjects().isEmpty())
        return 1;

    auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    if (win && QGuiApplication::platformName().startsWith(QStringLiteral("wayland"))) {
        // Alto: un tercio de la pantalla como mucho (como en un móvil apaisado)
        const QScreen *pantalla = QGuiApplication::primaryScreen();
        const int alto = pantalla ? qBound(220, pantalla->geometry().height() / 3, 330) : 280;
        win->setHeight(alto);
        win->create();
        if (auto *ls = LayerShellQt::Window::get(win)) {
            ls->setLayer(LayerShellQt::Window::LayerTop);
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorBottom;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            ls->setAnchors(a);
            ls->setExclusiveZone(alto);
            ls->setScope(QStringLiteral("titan-teclado"));
            ls->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
        }
    }
    if (win)
        win->show();
    return app.exec();
}
