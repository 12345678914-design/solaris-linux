#include <QGuiApplication>
#include <QTimer>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>
#include <iostream>

#include "SettingsBackend.h"
#include "Sistema.h"
#include "ThemeManager.h"
#include "TitanPrefs.h"
#include "Dispositivos.h"
#include "Conexiones.h"
#include "Personalizar.h"
#include "Predeterminadas.h"
#include "Usuarios.h"

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
    app.setApplicationName(QStringLiteral("titan-settings"));
    app.setApplicationDisplayName(QStringLiteral("Ajustes del Sistema"));
    app.setOrganizationName(QStringLiteral("TitanLinux"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/system.png")));

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    SettingsBackend backend;

    for (int i = 1; i < argc; ++i) {
        QString arg = QString::fromLocal8Bit(argv[i]);
        // --seccion=X o --seccion X (asi la abre el aviso de actualizaciones)
        if (arg == QStringLiteral("--seccion") && i + 1 < argc)
            arg = QStringLiteral("--seccion=") + QString::fromLocal8Bit(argv[++i]);
        // --actualizar: el botón "Actualizar" del aviso empieza ya, sin más preguntas
        if (arg == QStringLiteral("--actualizar")) {
            backend.setCurrentSection(QStringLiteral("General"));
            QTimer::singleShot(800, &backend, [&backend]() {
                if (!backend.updateRunning())
                    backend.installUpdates();
            });
        }
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
    Sistema sistema;
    engine.rootContext()->setContextProperty(QStringLiteral("settingsBackend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("sistema"), &sistema);
    TitanPrefs prefs;
    Dispositivos dispositivos;
    Conexiones conexiones;
    Personalizar personalizar(&prefs);
    Usuarios usuarios;
    engine.rootContext()->setContextProperty(QStringLiteral("prefs"), &prefs);
    engine.rootContext()->setContextProperty(QStringLiteral("dispositivos"), &dispositivos);
    engine.rootContext()->setContextProperty(QStringLiteral("conexiones"), &conexiones);
    engine.rootContext()->setContextProperty(QStringLiteral("personalizar"), &personalizar);
    Predeterminadas predeterminadas;
    engine.rootContext()->setContextProperty(QStringLiteral("predeterminadas"), &predeterminadas);
    engine.rootContext()->setContextProperty(QStringLiteral("usuarios"), &usuarios);
    // Solo para pruebas con un servicio de usuarios falso (TITAN_USUARIOS_SOCK):
    // entra ya desbloqueado como administrador ("usuario:clave").
    if (qEnvironmentVariableIsSet("TITAN_USUARIOS_SOCK") && qEnvironmentVariableIsSet("TITAN_AJUSTES_DESBLOQUEAR")) {
        const QString d = qEnvironmentVariable("TITAN_AJUSTES_DESBLOQUEAR");
        usuarios.recargar();
        usuarios.iniciarAdmin(d.section(QLatin1Char(':'), 0, 0), d.section(QLatin1Char(':'), 1));
    }
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

    if (engine.rootObjects().isEmpty()) {
        std::cerr << "titan-settings: fallo critico al cargar los componentes QML" << std::endl;
        return 1;
    }

    if (modoComprobar) {
        std::cout << "titan-settings=ok" << std::endl;
        std::cout << "estilo=macos" << std::endl;
        std::cout << "qml-componentes=ok" << std::endl;
        return 0;
    }

    return app.exec();
}

