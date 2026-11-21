#include "InstallerBackend.h"
#include "ThemeManager.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>
#include <QIcon>
#include <iostream>
#include <memory>
#include <QKeyEvent>
#include <QFile>
#include <pwd.h>
#include <unistd.h>

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
    app.setApplicationDisplayName(QStringLiteral("Instalador de Inti OS"));
    app.setOrganizationName(QStringLiteral("IntiOS"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/system.png")));

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    InstallerBackend backend;

    // El instalador corre como root (sudo desde el live). Para que tenga el
    // mismo tema que el escritorio (claro/oscuro y acento), ThemeManager lee el
    // theme.conf del usuario que lo lanzó, no el de root.
    ThemeManager *tema = nullptr;
    {
        const QByteArray sudoUser = qgetenv("SUDO_USER");
        const QByteArray homeOriginal = qgetenv("HOME");
        if (geteuid() == 0 && !sudoUser.isEmpty()) {
            // Solo si ya existe: ThemeManager crea ~/.config/titan si falta, y
            // como root dejaría esa carpeta de root en la casa del usuario.
            const struct passwd *pw = getpwnam(sudoUser.constData());
            if (pw && QFile::exists(QString::fromLocal8Bit(pw->pw_dir) + QStringLiteral("/.config/titan/theme.conf")))
                qputenv("HOME", pw->pw_dir);
        }
        tema = ThemeManager::instance();
        qputenv("HOME", homeOriginal);
    }

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("installerBackend"), &backend);
    // Solo para pruebas de la interfaz: abrir directamente en un paso.
    if (qEnvironmentVariableIsSet("TITAN_INSTALADOR_PASO"))
        backend.setCurrentStep(qEnvironmentVariableIntValue("TITAN_INSTALADOR_PASO"));
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), tema);

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
        // Los discos que se ofrecerian, para poder comprobar desde la consola
        // que el USB del live no sale y que el resto si.
        for (const QVariant &d : backend.disks())
            std::cout << "disco=" << d.toMap().value(QStringLiteral("name")).toString().toStdString() << std::endl;
        // TITAN_COMPROBAR_MANUAL=1: lee la tabla del disco elegido en modo
        // manual y planea «/boot/efi» (la EFI que haya, sin formatear) + «/»
        // en el primer hueco libre. Solo planea: no escribe nada en el disco.
        if (qEnvironmentVariableIsSet("TITAN_COMPROBAR_MANUAL")) {
            backend.setManualPartitioning(true);
            auto filas = [&]() { return backend.tablaManual(); };
            for (const QVariant &v : filas()) {
                const QVariantMap f = v.toMap();
                std::cout << "fila=" << f.value(QStringLiteral("tipo")).toString().toStdString() << "|"
                          << f.value(QStringLiteral("nodo")).toString().toStdString() << "|"
                          << f.value(QStringLiteral("uso")).toString().toStdString() << "|"
                          << f.value(QStringLiteral("tamanoTexto")).toString().toStdString() << std::endl;
            }
            std::cout << "plan-vacio=" << backend.validatePartitionPlan().toStdString() << std::endl;
            for (int i = 0; i < filas().size(); ++i)
                if (filas().at(i).toMap().value(QStringLiteral("flags")).toString().contains(QStringLiteral("esp"))) {
                    backend.editarParticion(i, QStringLiteral("/boot/efi"), false, QStringLiteral("fat32"));
                    break;
                }
            for (int i = 0; i < filas().size(); ++i)
                if (filas().at(i).toMap().value(QStringLiteral("tipo")).toString() == QStringLiteral("libre")) {
                    backend.crearEnHueco(i, 0, QStringLiteral("/"), QStringLiteral("ext4"));
                    break;
                }
            for (const QString &c : backend.cambiosPendientes())
                std::cout << "pendiente=" << c.toStdString() << std::endl;
            for (const QString &r : backend.resumenManual())
                std::cout << "resumen=" << r.toStdString() << std::endl;
            std::cout << "plan-con-pendientes=" << backend.validatePartitionPlan().toStdString() << std::endl;
        }
        return 0;
    }

    // Pruebas: TITAN_INSTALLER_CAPTURA=/ruta/prefijo guarda prefijo-N.png de
    // cada paso (0..6) y sale. No instala nada: solo cambia de pantalla.
    const QString captura = qEnvironmentVariable("TITAN_INSTALLER_CAPTURA");
    if (!captura.isEmpty()) {
        auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        auto paso = std::make_shared<int>(0);
        auto *timer = new QTimer(&app);
        timer->setInterval(900);
        QObject::connect(timer, &QTimer::timeout, &app, [win, captura, paso, &backend, timer]() {
            if (win)
                win->grabWindow().save(QStringLiteral("%1-%2.png").arg(captura).arg(*paso));
            if (++*paso > 6) {
                timer->stop();
                QCoreApplication::quit();
                return;
            }
            backend.setCurrentStep(*paso);
            // TITAN_INSTALLER_CAPTURA_NOMBRE: en el paso de la cuenta escribe
            // ese nombre tecla a tecla, como lo haría una persona.
            const QString nombre = qEnvironmentVariable("TITAN_INSTALLER_CAPTURA_NOMBRE");
            if (*paso == 3 && win && !nombre.isEmpty()) {
                if (QObject *campo = win->findChild<QObject *>(QStringLiteral("campoNombre"))) {
                    QMetaObject::invokeMethod(campo, "forceActiveFocus");
                    for (const QChar c : nombre) {
                        QKeyEvent pulsa(QEvent::KeyPress, 0, Qt::NoModifier, QString(c));
                        QCoreApplication::sendEvent(win, &pulsa);
                    }
                }
            }
        });
        timer->start();
    }

    return app.exec();
}
