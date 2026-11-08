#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <iostream>
#include "CalcBackend.h"
#include "ThemeManager.h"

int main(int argc, char *argv[])
{
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
    app.setApplicationName(QStringLiteral("titan-calc"));
    app.setApplicationDisplayName(QStringLiteral("Calculadora"));
    app.setOrganizationName(QStringLiteral("Titan"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/calculator.png")));

    CalcBackend calcBackend(&app);
    QQmlApplicationEngine engine;

    engine.rootContext()->setContextProperty(QStringLiteral("calcBackend"), &calcBackend);
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());

    const QUrl url(QStringLiteral("qrc:/qml/Calc.qml"));
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [url, modoComprobar](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                std::cerr << "titan-calc: error al cargar QML\n";
                QCoreApplication::exit(-1);
            } else if (modoComprobar && obj && url == objUrl) {
                std::cout << "titan-calc: verificado correctamente offscreen\n";
                QCoreApplication::exit(0);
            }
        },
        Qt::QueuedConnection);

    engine.load(url);

    return app.exec();
}
