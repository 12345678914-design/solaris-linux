// titan-greeter: pantalla de inicio de sesion de Inti OS (sistema instalado).
//
// La arranca greetd como usuario 'greeter' dentro de cage
// (/usr/lib/titan/titan-greeter-sesion). Muestra las cuentas del sistema,
// pide la contrasena y le pasa la sesion a greetd; los administradores
// pueden crear usuarios y grupos desde aqui (titan-usuarios-helper).
//
// Sin greetd (GREETD_SOCK vacio) arranca igual, para probar la interfaz,
// pero no puede iniciar sesiones.

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>

#include "GreetdCliente.h"
#include "Sistema.h"
#include "Usuarios.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("titan-greeter"));
    app.setDesktopFileName(QStringLiteral("titan-greeter"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    GreetdCliente greetd;
    const QString orden = qEnvironmentVariable("TITAN_GREETER_SESION",
                                               QStringLiteral("/usr/lib/titan/titan-arranque-grafico"));
    greetd.setOrdenSesion({orden});
    QObject::connect(&greetd, &GreetdCliente::sesionLista, &app, &QCoreApplication::quit, Qt::QueuedConnection);

    Usuarios usuarios;
    Sistema sistema;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("greetd"), &greetd);
    engine.rootContext()->setContextProperty(QStringLiteral("usuarios"), &usuarios);
    engine.rootContext()->setContextProperty(QStringLiteral("sistema"), &sistema);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Greeter.qml")));
    if (engine.rootObjects().isEmpty())
        return 1;

    // Pruebas: TITAN_GREETER_CAPTURA=fichero.png guarda la pantalla y sale.
    const QString captura = qEnvironmentVariable("TITAN_GREETER_CAPTURA");
    if (!captura.isEmpty()) {
        auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        const int espera = qEnvironmentVariableIntValue("TITAN_GREETER_CAPTURA_MS");
        QTimer::singleShot(espera > 0 ? espera : 1500, &app, [win, captura]() {
            if (win)
                win->grabWindow().save(captura);
            QCoreApplication::quit();
        });
    }
    return app.exec();
}
