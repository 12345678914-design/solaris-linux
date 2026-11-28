// Inti OS - Monitor de recursos (titan-monitor): procesos, rendimiento con
// gráficas en el color de acento y programas que arrancan al iniciar sesión.
#include "MonitorBackend.h"
#include "ThemeManager.h"

#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

#include <iostream>

int main(int argc, char *argv[])
{
    bool modoComprobar = false;
    for (int i = 1; i < argc; ++i) {
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--comprobar")) {
            modoComprobar = true;
            qputenv("QT_QPA_PLATFORM", "offscreen");
            qputenv("QT_QPA_PLATFORMTHEME", "");
        }
    }

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("titan-monitor"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("Monitor de recursos"));
    QGuiApplication::setDesktopFileName(QStringLiteral("titan-monitor"));
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/icons/monitor.png")));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    MonitorBackend monitor;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("monitor"), &monitor);
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());

    const QUrl url(QStringLiteral("qrc:/qml/Monitor.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &app,
                     [url, modoComprobar](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl) {
            std::cerr << "titan-monitor: error al cargar QML\n";
            QCoreApplication::exit(-1);
        } else if (modoComprobar && obj && url == objUrl) {
            std::cout << "titan-monitor=ok\n";
            QCoreApplication::exit(0);
        }
    }, Qt::QueuedConnection);
    engine.load(url);
    return app.exec();
}
