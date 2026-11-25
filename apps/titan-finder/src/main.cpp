#include "TitanTinte.h"
#include "FinderBackend.h"
#include "Red.h"
#include "ThemeManager.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QDir>

#include <iostream>

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

    // Respeta QT_QUICK_BACKEND solo si fue solicitado por el entorno (modo seguro o VM)

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("titan-finder"));
    QGuiApplication::setDesktopFileName(QStringLiteral("titan-finder"));

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    FinderBackend finderBackend;
    for (int i = 1; i < argc; ++i) {
        QString arg = QString::fromLocal8Bit(argv[i]);
        // Carpeta local, o de red: \\\\PC\\Carpeta, smb://...
        if (!arg.startsWith(QLatin1Char('-')) && (QDir(arg).exists() || !Red::normalizar(arg).isEmpty())) {
            finderBackend.goTo(arg);
            break;
        }
    }

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("tinte"), new TitanTinte); // carpetas con el acento
    engine.rootContext()->setContextProperty(QStringLiteral("finderBackend"), &finderBackend);
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());

    const QUrl url(QStringLiteral("qrc:/qml/Finder.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);

    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        std::cerr << "titan-finder: fallo critico al cargar los componentes QML" << std::endl;
        return 1;
    }

    if (modoComprobar) {
        std::cout << "titan-finder=ok" << std::endl;
        std::cout << "qml-componentes=ok" << std::endl;
        return 0;
    }

    return app.exec();
}
