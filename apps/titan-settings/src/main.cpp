#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>
#include <iostream>

#include "SettingsBackend.h"
#include "ThemeManager.h"

int main(int argc, char *argv[])
{
    for (int i = 1; i < argc; ++i) {
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--comprobar")) {
            std::cout << "titan-settings=ok" << std::endl;
            std::cout << "estilo=macos" << std::endl;
            return 0;
        }
    }

    if (qEnvironmentVariableIsEmpty("QT_QUICK_BACKEND")) {
        qputenv("QT_QUICK_BACKEND", "software");
    }
    if (qEnvironmentVariableIsEmpty("QSG_RHI_BACKEND")) {
        qputenv("QSG_RHI_BACKEND", "software");
    }

    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("titan-settings"));
    app.setApplicationDisplayName(QStringLiteral("Ajustes del Sistema"));
    app.setOrganizationName(QStringLiteral("TitanLinux"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/system.png")));

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    SettingsBackend backend;

    for (int i = 1; i < argc; ++i) {
        QString arg = QString::fromLocal8Bit(argv[i]);
        if (arg.startsWith(QStringLiteral("--seccion="))) {
            QString sec = arg.mid(10);
            if (sec == QStringLiteral("wallpaper") || sec == QStringLiteral("fondo")) {
                backend.setCurrentSection(QStringLiteral("Fondo de pantalla"));
            } else if (sec == QStringLiteral("appearance") || sec == QStringLiteral("apariencia")) {
                backend.setCurrentSection(QStringLiteral("Apariencia"));
            } else {
                backend.setCurrentSection(sec);
            }
        }
    }

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("settingsBackend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());

    const QUrl url(QStringLiteral("qrc:/qml/SettingsWindow.qml"));
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

