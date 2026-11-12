#include "InstallerBackend.h"
#include "ThemeManager.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>
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

    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("titan-installer"));
    app.setApplicationDisplayName(QStringLiteral("Instalador de Solaris Linux"));
    app.setOrganizationName(QStringLiteral("SolarisLinux"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/system.png")));

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    InstallerBackend backend;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("installerBackend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());

    const QUrl url(QStringLiteral("qrc:/qml/InstallerWindow.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);

    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        std::cerr << "titan-installer: error cargando interfaz QML" << std::endl;
        return -1;
    }

    if (modoComprobar) {
        std::cout << "titan-installer=ok" << std::endl;
        std::cout << "interfaz=calamares-native" << std::endl;
        return 0;
    }

    return app.exec();
}
