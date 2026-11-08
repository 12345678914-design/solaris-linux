#include "ShellBackend.h"
#include "WindowTracker.h"
#include "DockModel.h"
#include "LauncherBackend.h"
#include "DesktopBackend.h"
#include "ThemeManager.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QLocalServer>
#include <QLocalSocket>
#include <iostream>

#include <LayerShellQt/window.h>

namespace {

void configurarCapa(QQuickWindow *win, LayerShellQt::Window::Layer capa,
                    LayerShellQt::Window::Anchors anclas, int zonaExclusiva,
                    const QString &ambito,
                    LayerShellQt::Window::KeyboardInteractivity teclado = LayerShellQt::Window::KeyboardInteractivityNone,
                    bool hacerVisible = true)
{
    if (!win) return;
    if (!QGuiApplication::platformName().startsWith(QStringLiteral("wayland"))) {
        if (hacerVisible) win->setVisible(true);
        return;
    }

    win->create();
    auto *ls = LayerShellQt::Window::get(win);
    if (!ls) {
        qWarning() << "LayerShellQt fallo para" << win->objectName();
        if (hacerVisible) win->setVisible(true);
        return;
    }

    ls->setLayer(capa);
    ls->setAnchors(anclas);
    ls->setExclusiveZone(zonaExclusiva);
    ls->setScope(ambito);
    ls->setKeyboardInteractivity(teclado);
    if (hacerVisible) {
        win->setVisible(true);
    }
}

} // namespace

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

    for (int i = 1; i < argc && !modoComprobar; ++i) {
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--toggle-launcher")) {
            const QString socketName = QStringLiteral("titan-shell-ipc-") + qgetenv("USER");
            QLocalSocket socket;
            socket.connectToServer(socketName);
            if (socket.waitForConnected(600)) {
                socket.write("toggle-launcher\n");
                socket.flush();
                socket.waitForBytesWritten(600);
            }
            return 0;
        }
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--toggle-workspaces")) {
            const QString socketName = QStringLiteral("titan-shell-ipc-") + qgetenv("USER");
            QLocalSocket socket;
            socket.connectToServer(socketName);
            if (socket.waitForConnected(600)) {
                socket.write("toggle-workspaces\n");
                socket.flush();
                socket.waitForBytesWritten(600);
            }
            return 0;
        }
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--battery") && i + 1 < argc) {
            QString val = QString::fromLocal8Bit(argv[i + 1]);
            QString state = (i + 2 < argc) ? QString::fromLocal8Bit(argv[i + 2]) : QStringLiteral("discharging");
            const QString socketName = QStringLiteral("titan-shell-ipc-") + qgetenv("USER");
            QLocalSocket socket;
            socket.connectToServer(socketName);
            if (socket.waitForConnected(600)) {
                socket.write(QStringLiteral("set-battery %1 %2\n").arg(val, state).toUtf8());
                socket.flush();
                socket.waitForBytesWritten(600);
            }
            return 0;
        }
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--toggle-wallpaper")) {
            const QString socketName = QStringLiteral("titan-shell-ipc-") + qgetenv("USER");
            QLocalSocket socket;
            socket.connectToServer(socketName);
            if (socket.waitForConnected(600)) {
                socket.write("toggle-wallpaper\n");
                socket.flush();
                socket.waitForBytesWritten(600);
            }
            return 0;
        }
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--toggle-theme")) {
            const QString socketName = QStringLiteral("titan-shell-ipc-") + qgetenv("USER");
            QLocalSocket socket;
            socket.connectToServer(socketName);
            if (socket.waitForConnected(600)) {
                socket.write("toggle-theme\n");
                socket.flush();
                socket.waitForBytesWritten(600);
            } else {
                ThemeManager::instance()->toggleTheme();
            }
            return 0;
        }
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--toggle-notifications")) {
            const QString socketName = QStringLiteral("titan-shell-ipc-") + qgetenv("USER");
            QLocalSocket socket;
            socket.connectToServer(socketName);
            if (socket.waitForConnected(600)) {
                socket.write("toggle-notifications\n");
                socket.flush();
                socket.waitForBytesWritten(600);
            }
            return 0;
        }
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--notify") && i + 1 < argc) {
            QString title = QString::fromLocal8Bit(argv[i + 1]);
            QString msg = (i + 2 < argc) ? QString::fromLocal8Bit(argv[i + 2]) : QStringLiteral("");
            const QString socketName = QStringLiteral("titan-shell-ipc-") + qgetenv("USER");
            QLocalSocket socket;
            socket.connectToServer(socketName);
            if (socket.waitForConnected(600)) {
                socket.write(QStringLiteral("notify %1|%2\n").arg(title, msg).toUtf8());
                socket.flush();
                socket.waitForBytesWritten(600);
            }
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
    QGuiApplication::setApplicationName(QStringLiteral("titan-shell"));
    QGuiApplication::setOrganizationName(QStringLiteral("SolarisLinux"));
    
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    
    ShellBackend shellBackend;
    WindowTracker windowTracker;
    DockModel dockModel(&windowTracker, &shellBackend);
    
    QObject::connect(&shellBackend, &ShellBackend::currentWorkspaceChanged, &windowTracker, [&windowTracker, &shellBackend]() {
        windowTracker.setCurrentWorkspace(shellBackend.currentWorkspace());
    });
    QObject::connect(&windowTracker, &WindowTracker::requestWorkspaceSwitch, &shellBackend, [&shellBackend](int ws) {
        shellBackend.switchToWorkspace(ws);
    });
    shellBackend.setDockModel(&dockModel);
    LauncherBackend launcherBackend;
    DesktopBackend desktopBackend;

    // Servidor IPC local para responder instantáneamente a la tecla Mod (--toggle-launcher)
    const QString socketName = QStringLiteral("titan-shell-ipc-") + qgetenv("USER");
    QLocalServer server;
    server.removeServer(socketName);
    if (server.listen(socketName)) {
        QObject::connect(&server, &QLocalServer::newConnection, [&server, &shellBackend]() {
            while (QLocalSocket *client = server.nextPendingConnection()) {
                QObject::connect(client, &QLocalSocket::readyRead, [client, &shellBackend]() {
                    const QByteArray cmd = client->readAll().trimmed();
                    if (cmd == "toggle-launcher") {
                        shellBackend.toggleLauncher();
                    } else if (cmd == "toggle-workspaces") {
                        shellBackend.toggleWorkspaces();
                    } else if (cmd == "toggle-wallpaper") {
                        shellBackend.toggleWallpaperPicker();
                    } else if (cmd == "toggle-theme") {
                        shellBackend.toggleTheme();
                    } else if (cmd == "toggle-notifications") {
                        shellBackend.toggleNotificationCenter();
                    } else if (cmd.startsWith("notify ")) {
                        QString payload = QString::fromUtf8(cmd.mid(7));
                        QStringList parts = payload.split(QLatin1Char('|'));
                        QString t = parts.value(0);
                        QString m = parts.value(1);
                        shellBackend.notify(t, m);
                    } else if (cmd.startsWith("set-battery")) {
                        const auto parts = cmd.split(' ');
                        if (parts.size() >= 2) {
                            int pct = parts[1].toInt();
                            bool chg = (parts.size() >= 3 && parts[2] == "charging");
                            shellBackend.setSimulatedBattery(pct, chg);
                        }
                    }
                    client->disconnectFromServer();
                });
            }
        });
    }
    
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());
    engine.rootContext()->setContextProperty(QStringLiteral("shellBackend"), &shellBackend);
    engine.rootContext()->setContextProperty(QStringLiteral("windowTracker"), &windowTracker);
    engine.rootContext()->setContextProperty(QStringLiteral("dockModel"), &dockModel);
    engine.rootContext()->setContextProperty(QStringLiteral("launcherBackend"), &launcherBackend);
    engine.rootContext()->setContextProperty(QStringLiteral("desktopBackend"), &desktopBackend);
    
    const QUrl url(QStringLiteral("qrc:/qml/Shell.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    
    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        std::cerr << "titan-shell: fallo critico al cargar los componentes QML" << std::endl;
        return -1;
    }

    if (modoComprobar) {
        std::cout << "titan-shell=ok" << std::endl;
        std::cout << "estilo=macos" << std::endl;
        std::cout << "capas=layer-shell-qt" << std::endl;
        std::cout << "qml-componentes=ok" << std::endl;
        return 0;
    }

    // Configurar ventanas LayerShell
    // Con QtObject como raíz de Shell.qml, los Window son propiedades hijas del QtObject
    // findChildren los encuentra correctamente
    QList<QQuickWindow*> windows;
    for (QObject *obj : engine.rootObjects()) {
        if (auto *w = qobject_cast<QQuickWindow*>(obj)) {
            windows.append(w);
        }
        const auto children = obj->findChildren<QQuickWindow*>(QString(), Qt::FindDirectChildrenOnly);
        for (QQuickWindow *cw : children) {
            if (!windows.contains(cw)) windows.append(cw);
        }
        // También busca recursivamente por si acaso
        const auto allChildren = obj->findChildren<QQuickWindow*>();
        for (QQuickWindow *cw : allChildren) {
            if (!windows.contains(cw)) windows.append(cw);
        }
    }
    qDebug() << "Ventanas encontradas:" << windows.size();
    for (QQuickWindow *win : windows) {
        QString name = win->objectName();
        if (name == QStringLiteral("topBarWindow")) {
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorTop;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            configurarCapa(win, LayerShellQt::Window::LayerTop, a, 28, QStringLiteral("titan-topbar"));
        } else if (name == QStringLiteral("dockWindow")) {
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorBottom;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            configurarCapa(win, LayerShellQt::Window::LayerOverlay, a, 0, QStringLiteral("titan-dock"));
            QObject::connect(&shellBackend, &ShellBackend::launcherVisibleChanged, win, [win, &shellBackend]() {
                win->setVisible(!shellBackend.launcherVisible());
            });
        } else if (name == QStringLiteral("controlCenterWindow")) {
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorTop;
            a |= LayerShellQt::Window::AnchorBottom;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            configurarCapa(win, LayerShellQt::Window::LayerOverlay, a, 0, QStringLiteral("titan-control-center"),
                           LayerShellQt::Window::KeyboardInteractivityOnDemand, false);
            QObject::connect(&shellBackend, &ShellBackend::controlCenterVisibleChanged, win, [win, &shellBackend]() {
                win->setVisible(shellBackend.controlCenterVisible());
            });
        } else if (name == QStringLiteral("launcherWindow")) {
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorTop;
            a |= LayerShellQt::Window::AnchorBottom;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            configurarCapa(win, LayerShellQt::Window::LayerOverlay, a, 0, QStringLiteral("titan-launcher"),
                           LayerShellQt::Window::KeyboardInteractivityOnDemand, false);
            QObject::connect(&shellBackend, &ShellBackend::launcherVisibleChanged, win, [win, &shellBackend]() {
                win->setVisible(shellBackend.launcherVisible());
            });
        } else if (name == QStringLiteral("wallpaperPickerWindow")) {
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorTop;
            a |= LayerShellQt::Window::AnchorBottom;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            configurarCapa(win, LayerShellQt::Window::LayerOverlay, a, 0, QStringLiteral("titan-wallpaper-picker"),
                           LayerShellQt::Window::KeyboardInteractivityOnDemand, false);
            QObject::connect(&shellBackend, &ShellBackend::wallpaperPickerVisibleChanged, win, [win, &shellBackend]() {
                win->setVisible(shellBackend.wallpaperPickerVisible());
            });
        } else if (name == QStringLiteral("desktopIconsWindow")) {
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorTop;
            a |= LayerShellQt::Window::AnchorBottom;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            configurarCapa(win, LayerShellQt::Window::LayerBottom, a, 0, QStringLiteral("titan-desktop-icons"));
        } else if (name == QStringLiteral("lowBatteryWindow")) {
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorTop;
            a |= LayerShellQt::Window::AnchorBottom;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            configurarCapa(win, LayerShellQt::Window::LayerOverlay, a, 0, QStringLiteral("titan-low-battery"),
                           LayerShellQt::Window::KeyboardInteractivityOnDemand, false);
            QObject::connect(&shellBackend, &ShellBackend::batteryChanged, win, [win, &shellBackend]() {
                win->setVisible(shellBackend.lowBatteryAlert());
            });
        } else if (name == QStringLiteral("notificationCenterWindow")) {
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorTop;
            a |= LayerShellQt::Window::AnchorBottom;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            configurarCapa(win, LayerShellQt::Window::LayerOverlay, a, 0, QStringLiteral("titan-notification-center"),
                           LayerShellQt::Window::KeyboardInteractivityOnDemand, false);
            QObject::connect(&shellBackend, &ShellBackend::notificationCenterVisibleChanged, win, [win, &shellBackend]() {
                win->setVisible(shellBackend.notificationCenterVisible());
            });
        } else if (name == QStringLiteral("dynamicIslandWindow")) {
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorTop;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            configurarCapa(win, LayerShellQt::Window::LayerOverlay, a, 0, QStringLiteral("titan-dynamic-island"),
                           LayerShellQt::Window::KeyboardInteractivityNone, false);
            QObject::connect(&shellBackend, &ShellBackend::islandChanged, win, [win, &shellBackend]() {
                win->setVisible(shellBackend.islandActive());
            });
        } else if (name == QStringLiteral("workspacesWindow")) {
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorTop;
            a |= LayerShellQt::Window::AnchorBottom;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            configurarCapa(win, LayerShellQt::Window::LayerOverlay, a, 0, QStringLiteral("titan-workspaces"),
                           LayerShellQt::Window::KeyboardInteractivityOnDemand, false);
            QObject::connect(&shellBackend, &ShellBackend::workspacesVisibleChanged, win, [win, &shellBackend]() {
                win->setVisible(shellBackend.workspacesVisible());
            });
        }
    }
    
    return app.exec();
}
