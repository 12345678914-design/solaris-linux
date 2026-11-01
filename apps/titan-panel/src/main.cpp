#include "catalogo.h"
#include "centro.h"
#include "config.h"
#include "panel.h"
#include "tareas.h"

#include <QApplication>
#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QPixmap>
#include <QStringList>
#include <QTextStream>
#include <QTimer>

#include <cstdio>

namespace {

int listarAplicaciones(const QStringList &argumentos)
{
    Catalogo catalogo;
    QStringList directorios;
    for (int i = 2; i < argumentos.size(); ++i) {
        if (!argumentos.at(i).startsWith(QLatin1Char('-'))) {
            directorios << argumentos.at(i);
        }
    }
    if (directorios.isEmpty()) {
        catalogo.cargar();
    } else {
        catalogo.cargarDesde(directorios);
    }

    QTextStream salida(stdout);
    for (const Aplicacion &app : catalogo.aplicaciones()) {
        salida << app.id << '|' << app.nombre << '|' << app.icono << '|'
               << app.exec << '|' << (app.terminal ? "1" : "0") << '|'
               << app.wmClass << '\n';
    }
    return 0;
}

int comprobar()
{
    const Config &cfg = Config::instancia();
    Catalogo catalogo;
    catalogo.cargar();

    QTextStream salida(stdout);
    salida << "config=" << cfg.rutaCargada() << '\n';
    salida << "so=" << cfg.soNombre() << '\n';
    salida << "barra_alto=" << cfg.barraAlto() << '\n';
    salida << "barra_alfa=" << cfg.barraAlfa() << '\n';
    salida << "inicio=" << cfg.inicioTexto() << '\n';
    salida << "centro=" << cfg.centroAncho() << 'x' << cfg.centroAlto()
           << '\n';
    salida << "columnas=" << cfg.centroColumnas() << '\n';
    salida << "apps=" << catalogo.aplicaciones().size() << '\n';
    salida << "tareas=icono\n";
    salida << "inicio_estilo=icono\n";
    salida << "barra_orden=inicio,terminal,archivos,tareas,reloj\n";
    salida << "anclada_terminal=kitty\n";
    salida << "anclada_archivos=pcmanfm-qt\n";
    salida << "apagar=" << cfg.apagar() << '\n';
    salida << "reiniciar=" << cfg.reiniciar() << '\n';
    return 0;
}

int capturar(int argc, char *argv[], const QStringList &argumentos)
{
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("titan-panel"));

    int indiceRuta = argumentos.indexOf(QStringLiteral("--captura"));
    if (indiceRuta < 0 || indiceRuta + 1 >= argumentos.size()) {
        std::fprintf(stderr, "falta la ruta de la captura\n");
        return 2;
    }
    const QString ruta = argumentos.at(indiceRuta + 1);
    const bool centro = argumentos.contains(QStringLiteral("--centro"));

    Catalogo catalogo;
    catalogo.cargar();

    if (centro) {
        Centro ventana(&catalogo, nullptr);
        ventana.resize(1280, 720);
        ventana.show();
        QApplication::processEvents();
        const QPixmap imagen = ventana.grab();
        if (!imagen.save(ruta)) {
            std::fprintf(stderr, "no se pudo guardar %s\n",
                         qPrintable(ruta));
            return 1;
        }
        return 0;
    }

    Panel panel(&catalogo, nullptr, nullptr);
    panel.resize(1280, Config::instancia().barraAlto());
    panel.show();
    QApplication::processEvents();
    const QPixmap imagen = panel.grab();
    if (!imagen.save(ruta)) {
        std::fprintf(stderr, "no se pudo guardar %s\n", qPrintable(ruta));
        return 1;
    }
    return 0;
}

} // namespace

int main(int argc, char *argv[])
{
    QStringList argumentos;
    for (int i = 0; i < argc; ++i) {
        argumentos << QString::fromLocal8Bit(argv[i]);
    }

    if (argumentos.contains(QStringLiteral("--comprobar"))) {
        QCoreApplication app(argc, argv);
        return comprobar();
    }
    if (argumentos.contains(QStringLiteral("--listar-apps"))) {
        QCoreApplication app(argc, argv);
        return listarAplicaciones(argumentos);
    }
    if (argumentos.contains(QStringLiteral("--captura"))) {
        return capturar(argc, argv, argumentos);
    }

    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("titan-panel"));
    QApplication::setApplicationVersion(QStringLiteral("0.1"));
    QApplication::setDesktopFileName(QStringLiteral("titan-panel"));

    Catalogo catalogo;
    catalogo.cargar();

    MonitorTareas tareas;
    QString error;
    if (!tareas.iniciar(&error)) {
        qWarning().noquote() << "titan-panel: " << error;
    }

    Panel panel(&catalogo, &tareas, nullptr);
    panel.show();

    if (argumentos.contains(QStringLiteral("--centro"))) {
        QTimer::singleShot(400, &panel, &Panel::abrirCentro);
    }
    if (argumentos.contains(QStringLiteral("--autocerrar"))) {
        QTimer::singleShot(1800, &app, &QCoreApplication::quit);
    }

    return app.exec();
}
