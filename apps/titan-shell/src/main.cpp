#include "TitanTinte.h"
#include <QTimer>
#include "ShellBackend.h"
#include "Usuarios.h"
#include "WindowTracker.h"
#include "WayfireIpc.h"
#include "DockModel.h"
#include "LauncherBackend.h"
#include "DesktopBackend.h"
#include "ThemeManager.h"
#include "Mpris.h"
#include "TitanPrefs.h"
#include <QQuickItem>
#include <QRegion>

#include <QGuiApplication>
#include <QDir>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QLocalServer>
#include <QLocalSocket>
#include <iostream>
#include <memory>
#include <QScreen>

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

    // Qt 6 pierde la zona de clics (mascara) al ocultar y volver a mostrar
    // una ventana: la superficie nueva nace sin ella y Qt no la reenvia
    // porque "no ha cambiado". Sin esto, el Dock movido a un lado (se oculta
    // para reanclarlo) se comia el raton en toda su franja de 320 px.
    QObject::connect(win, &QWindow::visibleChanged, win, [win](bool visible) {
        if (!visible)
            return;
        QTimer::singleShot(0, win, [win]() {
            const QRegion m = win->mask();
            if (m.isEmpty())
                return;
            win->setMask(QRegion());
            win->setMask(m);
        });
    });

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
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--toggle-control-center")) {
            const QString socketName = QStringLiteral("titan-shell-ipc-") + qgetenv("USER");
            QLocalSocket socket;
            socket.connectToServer(socketName);
            if (socket.waitForConnected(600)) {
                socket.write("toggle-control-center\n");
                socket.flush();
                socket.waitForBytesWritten(600);
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
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--lock")) {
            const QString socketName = QStringLiteral("titan-shell-ipc-") + qgetenv("USER");
            QLocalSocket socket;
            socket.connectToServer(socketName);
            if (socket.waitForConnected(600)) {
                socket.write("lock\n");
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

    // Respeta QT_QUICK_BACKEND solo si fue solicitado explícitamente por el entorno (modo seguro o VM).
    // Si no está definido, Qt Quick utilizará aceleración por hardware nativa (OpenGL/Vulkan).
    
    // Asegurar que las aplicaciones de la tienda Flatpak sean reconocidas por Wayland y el entorno
    {
        QString curXdg = QString::fromLocal8Bit(qgetenv("XDG_DATA_DIRS"));
        QString flatpakDirs = QStringLiteral("/var/lib/flatpak/exports/share:") + QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share");
        if (curXdg.isEmpty()) {
            qputenv("XDG_DATA_DIRS", (flatpakDirs + QStringLiteral(":/usr/local/share:/usr/share")).toLocal8Bit());
        } else if (!curXdg.contains(QStringLiteral("flatpak"))) {
            qputenv("XDG_DATA_DIRS", (flatpakDirs + QStringLiteral(":") + curXdg).toLocal8Bit());
        }
    }

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("titan-shell"));
    QGuiApplication::setOrganizationName(QStringLiteral("IntiOS"));
    
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
                    } else if (cmd == "toggle-control-center") {
                        shellBackend.toggleControlCenter();
                    } else if (cmd == "lock") {
                        shellBackend.lockScreen();
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
    
    // Lo que suena ahora (MPRIS), para la Isla Dinamica. Antes que el motor
    // QML: se destruye despues de el.
    Mpris mpris;
    // Preferencias del escritorio (Ajustes las cambia; aqui se aplican en vivo).
    TitanPrefs prefs;
    shellBackend.setPrefs(&prefs);

    // El shell mantiene claro/oscuro de GTK y del portal igual que theme.conf
    // (Firefox y OnlyOffice en modo "sistema" lo leen de ahí).
    if (!modoComprobar)
        ThemeManager::instance()->setSincronizaSistema(true);

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("tinte"), new TitanTinte); // carpetas con el acento
    engine.rootContext()->setContextProperty(QStringLiteral("titanThemeManager"), ThemeManager::instance());
    engine.rootContext()->setContextProperty(QStringLiteral("prefs"), &prefs);
    engine.rootContext()->setContextProperty(QStringLiteral("shellBackend"), &shellBackend);
    engine.rootContext()->setContextProperty(QStringLiteral("windowTracker"), &windowTracker);
    engine.rootContext()->setContextProperty(QStringLiteral("dockModel"), &dockModel);
    engine.rootContext()->setContextProperty(QStringLiteral("launcherBackend"), &launcherBackend);
    engine.rootContext()->setContextProperty(QStringLiteral("desktopBackend"), &desktopBackend);
    engine.rootContext()->setContextProperty(QStringLiteral("mpris"), &mpris);
    // Usuarios y grupos (panel compartido con titan-greeter, en la pantalla de bloqueo)
    Usuarios usuarios;
    engine.rootContext()->setContextProperty(QStringLiteral("usuarios"), &usuarios);
    // Desenfoque real: Wayfire con el plugin blur (wayfire.ini lo aplica a las
    // capas titan-*). Con labwc o sin GPU, GlassPanel sigue con el fondo falso.
    // TITAN_BLUR=0 lo desactiva a mano.
    const bool blurReal = qgetenv("TITAN_BLUR") != "0"
        && qgetenv("QT_QUICK_BACKEND") != "software"
        && WayfireIpc::instancia()->disponible()
        && WayfireIpc::instancia()->pluginActivo(QStringLiteral("blur"));
    engine.rootContext()->setContextProperty(QStringLiteral("compositorBlur"), blurReal);
    
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
            bool shouldShow = shellBackend.bootSplashFinished() && !shellBackend.lockScreenActive()
                              && prefs.b(QStringLiteral("Barra/visible"));
            configurarCapa(win, LayerShellQt::Window::LayerTop, a, 28, QStringLiteral("titan-topbar"),
                           LayerShellQt::Window::KeyboardInteractivityNone, shouldShow);
            // Oculta (Ajustes > Barra de menus), la barra deja de reservar sus 28 px.
            auto updateTopBarVis = [win, &shellBackend, &prefs]() {
                win->setVisible(shellBackend.bootSplashFinished() && !shellBackend.lockScreenActive()
                                && prefs.b(QStringLiteral("Barra/visible")));
            };
            QObject::connect(&shellBackend, &ShellBackend::bootSplashFinishedChanged, win, updateTopBarVis);
            QObject::connect(&shellBackend, &ShellBackend::lockScreenActiveChanged, win, updateTopBarVis);
            QObject::connect(&prefs, &TitanPrefs::cambiado, win, updateTopBarVis);
        } else if (name == QStringLiteral("dockWindow")) {
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorBottom;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            auto dockDebeVerse = [&shellBackend, &prefs]() {
                return shellBackend.bootSplashFinished() && !shellBackend.lockScreenActive()
                       && !shellBackend.launcherVisible() && prefs.b(QStringLiteral("Dock/visible"));
            };
            configurarCapa(win, LayerShellQt::Window::LayerOverlay, a, 0, QStringLiteral("titan-dock"),
                           LayerShellQt::Window::KeyboardInteractivityNone, false);
            // Posicion del Dock (Ajustes > Escritorio y Dock): abajo, izquierda o
            // derecha. La capa se ancla a ese borde; para cambiarla se oculta,
            // se reancla y se vuelve a mostrar.
            auto posicionActual = std::make_shared<QString>();
            auto colocarDock = [win, &prefs, posicionActual, dockDebeVerse]() {
                const QString pos = prefs.s(QStringLiteral("Dock/posicion"));
                const bool cambia = pos != *posicionActual;
                *posicionActual = pos;
                if (cambia && QGuiApplication::platformName().startsWith(QStringLiteral("wayland"))) {
                    if (auto *ls = LayerShellQt::Window::get(win)) {
                        LayerShellQt::Window::Anchors an;
                        QSize tam;
                        QScreen *pantalla = win->screen();
                        const QSize sc = pantalla ? pantalla->size() : QSize(1280, 800);
                        if (pos == QStringLiteral("izquierda") || pos == QStringLiteral("derecha")) {
                            an = LayerShellQt::Window::AnchorTop;
                            an |= LayerShellQt::Window::AnchorBottom;
                            an |= pos == QStringLiteral("izquierda") ? LayerShellQt::Window::AnchorLeft
                                                                     : LayerShellQt::Window::AnchorRight;
                            ls->setDesiredSize(QSize(320, 0));
                            tam = QSize(320, sc.height());
                        } else {
                            an = LayerShellQt::Window::AnchorBottom;
                            an |= LayerShellQt::Window::AnchorLeft;
                            an |= LayerShellQt::Window::AnchorRight;
                            ls->setDesiredSize(QSize(0, 320));
                            tam = QSize(sc.width(), 320);
                        }
                        const bool estabaVisible = win->isVisible();
                        if (estabaVisible)
                            win->setVisible(false);
                        ls->setAnchors(an);
                        win->resize(tam);
                        if (estabaVisible)
                            win->setVisible(true);
                    }
                }
                const bool ver = dockDebeVerse();
                if (win->isVisible() != ver)
                    win->setVisible(ver);
            };
            colocarDock();
            auto updateDockVis = [win, dockDebeVerse]() {
                win->setVisible(dockDebeVerse());
            };
            QObject::connect(&shellBackend, &ShellBackend::bootSplashFinishedChanged, win, updateDockVis);
            QObject::connect(&shellBackend, &ShellBackend::lockScreenActiveChanged, win, updateDockVis);
            QObject::connect(&shellBackend, &ShellBackend::launcherVisibleChanged, win, updateDockVis);
            QObject::connect(&prefs, &TitanPrefs::cambiado, win, colocarDock);
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
            bool shouldShow = shellBackend.bootSplashFinished() && !shellBackend.lockScreenActive();
            configurarCapa(win, LayerShellQt::Window::LayerBottom, a, 0, QStringLiteral("titan-desktop-icons"),
                           LayerShellQt::Window::KeyboardInteractivityNone, shouldShow);
            auto updateDeskVis = [win, &shellBackend]() {
                win->setVisible(shellBackend.bootSplashFinished() && !shellBackend.lockScreenActive());
            };
            QObject::connect(&shellBackend, &ShellBackend::bootSplashFinishedChanged, win, updateDeskVis);
            QObject::connect(&shellBackend, &ShellBackend::lockScreenActiveChanged, win, updateDeskVis);
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
            // Anclada solo arriba: el compositor la centra y la ventana mide lo
            // que la isla (Shell.qml), sin ocupar el resto de la franja.
            // Zona exclusiva -1: arriba del todo, encima de la barra superior.
            configurarCapa(win, LayerShellQt::Window::LayerOverlay, LayerShellQt::Window::AnchorTop, -1,
                           QStringLiteral("titan-dynamic-island"),
                           LayerShellQt::Window::KeyboardInteractivityNone, false);
            // Visible con una notificacion o con musica sonando.
            auto actualizarIsla = [win, &shellBackend, &mpris]() {
                // La pantalla de bloqueo ensena sus propios avisos y musica.
                win->setVisible((shellBackend.islandActive() || mpris.disponible())
                                && !shellBackend.lockScreenActive());
            };
            QObject::connect(&shellBackend, &ShellBackend::lockScreenActiveChanged, win, actualizarIsla);
            QObject::connect(&shellBackend, &ShellBackend::islandChanged, win, actualizarIsla);
            QObject::connect(&mpris, &Mpris::cambiado, win, actualizarIsla);
            actualizarIsla();
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
        } else if (name == QStringLiteral("bootSplashWindow")) {
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorTop;
            a |= LayerShellQt::Window::AnchorBottom;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            configurarCapa(win, LayerShellQt::Window::LayerOverlay, a, 0, QStringLiteral("titan-boot-splash"),
                           LayerShellQt::Window::KeyboardInteractivityExclusive, true);
            QObject::connect(&shellBackend, &ShellBackend::bootSplashActiveChanged, win, [win, &shellBackend]() {
                win->setVisible(shellBackend.bootSplashActive());
            });
        } else if (name == QStringLiteral("lockScreenWindow")) {
            LayerShellQt::Window::Anchors a = LayerShellQt::Window::AnchorTop;
            a |= LayerShellQt::Window::AnchorBottom;
            a |= LayerShellQt::Window::AnchorLeft;
            a |= LayerShellQt::Window::AnchorRight;
            bool shouldBeVisible = shellBackend.lockScreenActive() && shellBackend.bootSplashFinished();
            configurarCapa(win, LayerShellQt::Window::LayerOverlay, a, 0, QStringLiteral("titan-lock-screen"),
                           LayerShellQt::Window::KeyboardInteractivityExclusive, shouldBeVisible);
            auto updateLockVisibility = [win, &shellBackend]() {
                bool vis = shellBackend.lockScreenActive() && shellBackend.bootSplashFinished();
                win->setVisible(vis);
            };
            QObject::connect(&shellBackend, &ShellBackend::lockScreenActiveChanged, win, updateLockVisibility);
            QObject::connect(&shellBackend, &ShellBackend::bootSplashFinishedChanged, win, updateLockVisibility);
        }
    }
    
    return app.exec();
}
