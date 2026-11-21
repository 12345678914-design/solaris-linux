#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <QFileInfo>
#include <QUrl>
#include <iostream>
#include "VideoBackend.h"
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
    app.setApplicationName("Titan Video");
    app.setOrganizationName("TitanOS");
    app.setWindowIcon(QIcon("/usr/share/titan/icons/video.png"));

    VideoBackend videoBackend(&app);

    // Open file from CLI if passed
    for (int i = 1; i < argc; ++i) {
        QString arg = QString::fromLocal8Bit(argv[i]);
        if (!arg.startsWith(QLatin1Char('-'))) {
            // El .desktop pasa %U: llegan URLs (file:///...), no rutas.
            // También se aceptan URLs de red (http, rtsp...) tal cual.
            const QUrl asUrl(arg);
            if (asUrl.isValid() && !asUrl.scheme().isEmpty() && asUrl.scheme().size() > 1 && !asUrl.isLocalFile()) {
                videoBackend.setSourceUrl(asUrl);
            } else {
                QFileInfo fi(asUrl.isLocalFile() ? asUrl.toLocalFile() : arg);
                if (fi.exists())
                    videoBackend.setSourceUrl(QUrl::fromLocalFile(fi.absoluteFilePath()));
            }
            break;
        }
    }

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("themeManager", ThemeManager::instance());
    // TitanTheme.qml busca "titanThemeManager": sin él la app no sigue el modo oscuro ni el acento.
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());
    engine.rootContext()->setContextProperty("videoBackend", &videoBackend);

    const QUrl url(QStringLiteral("qrc:/qml/Video.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url, modoComprobar](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl) {
            std::cerr << "titan-video: error al cargar QML\n";
            QCoreApplication::exit(-1);
        } else if (modoComprobar && obj && url == objUrl) {
            std::cout << "titan-video: verificado correctamente offscreen\n";
            QCoreApplication::exit(0);
        }
    }, Qt::QueuedConnection);

    engine.load(url);

    return app.exec();
}
