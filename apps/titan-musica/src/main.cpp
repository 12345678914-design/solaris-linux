#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <iostream>
#include "MusicaBackend.h"
#include "Mpris.h"
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QFileInfo>
#include <QUrl>
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

    // Ya abierta: le pasa los archivos a esa ventana y la trae al frente.
    QStringList archivos;
    for (const QString &arg : app.arguments().mid(1)) {
        if (!arg.startsWith(QLatin1Char('-')))
            archivos << (arg.contains(QStringLiteral("://")) ? arg : QUrl::fromLocalFile(QFileInfo(arg).absoluteFilePath()).toString());
    }
    if (!modoComprobar) {
        QDBusConnection bus = QDBusConnection::sessionBus();
        if (bus.isConnected() && bus.interface()->isServiceRegistered(Mpris::servicio)) {
            QDBusInterface rep(Mpris::servicio, Mpris::ruta, QStringLiteral("org.mpris.MediaPlayer2.Player"), bus);
            QDBusInterface raiz(Mpris::servicio, Mpris::ruta, QStringLiteral("org.mpris.MediaPlayer2"), bus);
            if (rep.isValid()) {
                if (!archivos.isEmpty())
                    rep.call(QStringLiteral("OpenUri"), archivos.first());
                raiz.call(QStringLiteral("Raise"));
                return 0;
            }
        }
    }

    MusicaBackend backend;
    if (!modoComprobar)
        Mpris::registrar(&backend);
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

    // "titan-musica cancion.mp3" (o doble clic en Finder): suenan esos archivos.
    if (!archivos.isEmpty())
        backend.abrirArchivos(archivos);

    return app.exec();
}

