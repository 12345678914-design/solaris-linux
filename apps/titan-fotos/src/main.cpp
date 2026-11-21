#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <iostream>
#include "Exif.h"
#include "FotosBackend.h"
#include "Proveedores.h"
#include "ThemeManager.h"

int main(int argc, char *argv[])
{
    // titan-fotos --exif FOTO: muestra los datos EXIF que lee Fotos (sin ventana)
    if (argc == 3 && QString::fromLocal8Bit(argv[1]) == QStringLiteral("--exif")) {
        const QVariantMap d = Exif::leer(QString::fromLocal8Bit(argv[2]));
        for (auto it = d.constBegin(); it != d.constEnd(); ++it) {
            const QString v = it.value().typeId() == QMetaType::QDateTime ? it.value().toDateTime().toString(Qt::ISODate) : it.value().toString();
            std::cout << it.key().toStdString() << "=" << v.toStdString() << std::endl;
        }
        return d.isEmpty() ? 1 : 0;
    }

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
    app.setApplicationName(QStringLiteral("titan-fotos"));
    app.setApplicationDisplayName(QStringLiteral("Fotos"));
    app.setOrganizationName(QStringLiteral("Titan"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/pictures.png")));

    FotosBackend backend;
    QQmlApplicationEngine engine;

    for (int i = 1; i < argc; ++i) {
        QString arg = QString::fromLocal8Bit(argv[i]);
        if (!arg.startsWith(QLatin1Char('-'))) {
            backend.openFile(arg);
            break;
        }
    }

    engine.addImageProvider(QStringLiteral("miniatura"), new ProveedorMiniaturas(&backend));
    engine.addImageProvider(QStringLiteral("edicion"), new ProveedorEdicion(&backend));
    engine.rootContext()->setContextProperty(QStringLiteral("fotosBackend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());

    const QUrl url(QStringLiteral("qrc:/qml/Fotos.qml"));
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
        std::cerr << "titan-fotos: fallo critico al cargar los componentes QML" << std::endl;
        return 1;
    }

    if (modoComprobar) {
        std::cout << "titan-fotos=ok" << std::endl;
        std::cout << "qml-componentes=ok" << std::endl;
        return 0;
    }

    return app.exec();
}

