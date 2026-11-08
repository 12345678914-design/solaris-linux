#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <iostream>
#include "MusicaBackend.h"
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
    app.setApplicationName(QStringLiteral("titan-musica"));
    app.setApplicationDisplayName(QStringLiteral("Música"));
    app.setOrganizationName(QStringLiteral("Titan"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/music.png")));

    MusicaBackend backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("musicaBackend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());

    const QUrl url(QStringLiteral("qrc:/qml/Musica.qml"));
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                QCoreApplication::exit(-1);
            }
        },
        Qt::QueuedConnection);

    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        std::cerr << "titan-musica: fallo critico al cargar los componentes QML" << std::endl;
        return 1;
    }

    if (modoComprobar) {
        std::cout << "titan-musica=ok" << std::endl;
        std::cout << "qml-componentes=ok" << std::endl;
        return 0;
    }

    return app.exec();
}

