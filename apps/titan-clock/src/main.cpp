#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <iostream>
#include "ClockBackend.h"
#include "ThemeManager.h"

int main(int argc, char *argv[]) {
    bool modoComprobar = false;
    for (int i = 1; i < argc; ++i) {
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--comprobar")) {
            modoComprobar = true;
            qputenv("QT_QPA_PLATFORM", "offscreen");
            qputenv("QT_QPA_PLATFORMTHEME", "");
            break;
        }
    }

    QGuiApplication app(argc, argv);
    app.setApplicationName("Titan Reloj");
    app.setOrganizationName("TitanOS");
    app.setWindowIcon(QIcon("/usr/share/titan/icons/clock.png"));

    ClockBackend clockBackend(&app);
    QQmlApplicationEngine engine;

    engine.rootContext()->setContextProperty("themeManager", ThemeManager::instance());
    // TitanTheme.qml busca "titanThemeManager": sin él la app no sigue el modo oscuro ni el acento.
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());
    engine.rootContext()->setContextProperty("clockBackend", &clockBackend);

    const QUrl url(QStringLiteral("qrc:/qml/Clock.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url, modoComprobar](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl) {
            std::cerr << "titan-clock: error al cargar QML\n";
            QCoreApplication::exit(-1);
        } else if (modoComprobar && obj && url == objUrl) {
            std::cout << "titan-clock: verificado correctamente offscreen\n";
            QCoreApplication::exit(0);
        }
    }, Qt::QueuedConnection);

    engine.load(url);

    return app.exec();
}
