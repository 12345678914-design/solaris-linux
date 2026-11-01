#include "config.h"
#include "escritorio.h"
#include "layershell.h"

#include <QApplication>
#include <QCoreApplication>
#include <QDebug>
#include <QScreen>
#include <QTimer>
#include <QDir>
#include <QFile>
#include <QLocalServer>
#include <QLocalSocket>

#include <cstdio>

namespace {

bool tieneArgumento(int argc, char *argv[], const char *buscado)
{
    for (int i = 1; i < argc; ++i) {
        if (qstrcmp(argv[i], buscado) == 0) {
            return true;
        }
    }
    return false;
}

} // namespace

int main(int argc, char *argv[])
{
    // Modo de comprobacion: no abre ventana ni necesita servidor grafico
    if (tieneArgumento(argc, argv, "--comprobar")) {
        QCoreApplication aplicacion(argc, argv);
        const Config &cfg = Config::instancia();
        std::printf("config=%s\n", qPrintable(cfg.rutaCargada()));
        std::printf("so=%s\n", qPrintable(cfg.soNombre()));
        std::printf("version=%s\n", qPrintable(cfg.soVersion()));
        std::printf("usuario=%s\n", qPrintable(cfg.usuario()));
        std::printf("hostname=%s\n", qPrintable(cfg.hostname()));
        std::printf("terminal=%s\n", qPrintable(cfg.terminal()));
        std::printf("explorador=%s\n", qPrintable(cfg.explorador()));
        std::printf("escritorio=%s\n", qPrintable(cfg.escritorio()));
        std::printf("barra_superior=no\n");
        std::printf("tarjeta_central=no\n");
        std::printf("salir=no\n");
        return 0;
    }

    // Modo cambio de fondo de pantalla interactivo
    for (int i = 1; i < argc; ++i) {
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--wallpaper") && i + 1 < argc) {
            QCoreApplication aplicacion(argc, argv);
            QString ruta = QString::fromLocal8Bit(argv[i + 1]);
            QString cfgDir = QDir::homePath() + QStringLiteral("/.config/titan");
            QDir().mkpath(cfgDir);
            QFile f(cfgDir + QStringLiteral("/wallpaper"));
            if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                f.write(ruta.toUtf8() + "\n");
                f.close();
            }

            const QString socketName = QStringLiteral("titan-desktop-ipc-") + qgetenv("USER");
            QLocalSocket socket;
            socket.connectToServer(socketName);
            if (socket.waitForConnected(600)) {
                socket.write(ruta.toUtf8() + "\n");
                socket.flush();
                socket.waitForBytesWritten(600);
            }
            return 0;
        }
    }

    QApplication aplicacion(argc, argv);

    const Config &cfg = Config::instancia();
    QApplication::setApplicationName(QStringLiteral("titan-desktop"));
    QApplication::setApplicationVersion(cfg.soVersion());
    QApplication::setOrganizationName(cfg.soNombre());

    const QStringList argumentos = QApplication::arguments();

    Escritorio escritorio;

    // Servidor IPC local para recibir cambios de fondo en vivo con animación
    const QString socketName = QStringLiteral("titan-desktop-ipc-") + qgetenv("USER");
    QLocalServer server;
    server.removeServer(socketName);
    if (server.listen(socketName)) {
        QObject::connect(&server, &QLocalServer::newConnection, [&server, &escritorio]() {
            while (QLocalSocket *client = server.nextPendingConnection()) {
                QObject::connect(client, &QLocalSocket::readyRead, [client, &escritorio]() {
                    QString ruta = QString::fromUtf8(client->readAll()).trimmed();
                    if (!ruta.isEmpty()) {
                        escritorio.cambiarFondo(ruta);
                    }
                    client->disconnectFromServer();
                });
            }
        });
    }

    // Modo captura: pinta el escritorio en memoria y lo guarda como PNG
    const int indiceCaptura = argumentos.indexOf(QStringLiteral("--captura"));
    if (indiceCaptura >= 0 && indiceCaptura + 1 < argumentos.size()) {
        escritorio.resize(1280, 800);
        escritorio.show();
        QApplication::processEvents();
        escritorio.grab().save(argumentos.at(indiceCaptura + 1));
        return 0;
    }

    if (argumentos.contains(QStringLiteral("--ventana"))) {
        escritorio.resize(1100, 720);
        escritorio.show();
    } else if (argumentos.contains(QStringLiteral("--escritorio"))) {
        if (QScreen *pantalla = QApplication::primaryScreen()) {
            escritorio.setGeometry(pantalla->geometry());
        } else {
            escritorio.resize(1280, 800);
        }
        const bool capa = TitanCapa::aplicar(
            &escritorio, TitanCapa::Capa::Fondo, -1, false,
            QStringLiteral("titan-fondo"));
        if (!capa) {
            qWarning() << "titan-desktop: fondo sin layer-shell";
        }
        escritorio.show();
    } else {
        escritorio.showFullScreen();
    }

    // Para las pruebas automaticas
    if (argumentos.contains(QStringLiteral("--autocerrar"))) {
        QTimer::singleShot(1200, &aplicacion, &QCoreApplication::quit);
    }

    return aplicacion.exec();
}
