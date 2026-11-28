// Inti OS - Bienvenida (titan-bienvenida): la primera vez que se entra en la
// cuenta pregunta lo justo para sentirse en casa (botones de las ventanas a
// la izquierda o como en Windows, claro u oscuro, color) y enseña los atajos
// útiles. Todo se puede cambiar luego en Ajustes.
//   titan-bienvenida               se abre siempre (menú de inicio)
//   titan-bienvenida --primera-vez solo si no se ha visto (autoarranque) y
//                                  nunca en la sesión en vivo (ahí va el instalador)
#include "ThemeManager.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QIcon>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QStandardPaths>

#include <iostream>

namespace {
QString marca()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/titan/bienvenida-vista");
}
}

class Bienvenida : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    // Ya no se vuelve a abrir sola
    Q_INVOKABLE void terminar()
    {
        QDir().mkpath(QFileInfo(marca()).absolutePath());
        QFile f(marca());
        if (f.open(QIODevice::WriteOnly))
            f.write("1\n");
    }
    Q_INVOKABLE void abrir(const QString &que)
    {
        if (que == QLatin1String("manual"))
            QProcess::startDetached(QStringLiteral("titan-manual"), {});
        else if (que == QLatin1String("ajustes"))
            QProcess::startDetached(QStringLiteral("titan-settings"), {});
        else if (que == QLatin1String("tienda"))
            QProcess::startDetached(QStringLiteral("plasma-discover"), {});
    }
};

int main(int argc, char *argv[])
{
    bool comprobar = false;
    bool primeraVez = false;
    for (int i = 1; i < argc; ++i) {
        const QString a = QString::fromLocal8Bit(argv[i]);
        if (a == QStringLiteral("--comprobar")) {
            comprobar = true;
            qputenv("QT_QPA_PLATFORM", "offscreen");
            qputenv("QT_QPA_PLATFORMTHEME", "");
        } else if (a == QStringLiteral("--primera-vez")) {
            primeraVez = true;
        }
    }
    if (primeraVez && (QFile::exists(marca()) || QFile::exists(QStringLiteral("/run/archiso"))))
        return 0;

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("titan-bienvenida"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("Bienvenida"));
    QGuiApplication::setDesktopFileName(QStringLiteral("titan-bienvenida"));
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/icons/inti.png")));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    Bienvenida bienvenida;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("bienvenida"), &bienvenida);
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());
    const QUrl url(QStringLiteral("qrc:/qml/Bienvenida.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &app, [url, comprobar](QObject *obj, const QUrl &u) {
        if (!obj && u == url) {
            std::cerr << "titan-bienvenida: error al cargar QML\n";
            QCoreApplication::exit(-1);
        } else if (comprobar && obj && u == url) {
            std::cout << "titan-bienvenida=ok\n";
            QCoreApplication::exit(0);
        }
    }, Qt::QueuedConnection);
    engine.load(url);
    return app.exec();
}

#include "main.moc"
