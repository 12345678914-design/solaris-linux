#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include "MusicaBackend.h"
#include "ThemeManager.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("titan-musica"));
    app.setApplicationDisplayName(QStringLiteral("Música"));
    app.setOrganizationName(QStringLiteral("Titan"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/music.png")));

    QQmlApplicationEngine engine;

    MusicaBackend backend;
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

    return app.exec();
}

