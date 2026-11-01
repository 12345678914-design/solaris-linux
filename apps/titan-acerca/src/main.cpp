#include "acerca.h"
#include "config.h"

#include <QApplication>
#include <QCoreApplication>
#include <QStringList>
#include <QTextStream>
#include <QTimer>

#include <cstdio>

namespace {

bool tieneArgumento(const QStringList &argumentos, const QString &buscado)
{
    return argumentos.contains(buscado);
}

int comprobar()
{
    const DatosEquipo datos = leerDatosEquipo();
    QTextStream salida(stdout);
    salida << "equipo=" << datos.equipo << '\n';
    salida << "ram=" << datos.ram << '\n';
    salida << "procesador=" << datos.procesador << '\n';
    salida << "disco=" << datos.disco << '\n';
    salida << "arquitectura=" << datos.arquitectura << '\n';
    salida << "boton=Aceptar\n";
    salida << "icono=computadora\n";
    return 0;
}

} // namespace

int main(int argc, char *argv[])
{
    QStringList argumentos;
    for (int i = 0; i < argc; ++i) {
        argumentos << QString::fromLocal8Bit(argv[i]);
    }

    if (tieneArgumento(argumentos, QStringLiteral("--comprobar"))) {
        QCoreApplication app(argc, argv);
        return comprobar();
    }

    QApplication app(argc, argv);
    const Config &cfg = Config::instancia();
    QApplication::setApplicationName(QStringLiteral("titan-acerca"));
    QApplication::setApplicationVersion(cfg.soVersion());
    QApplication::setOrganizationName(cfg.soNombre());
    QApplication::setDesktopFileName(QStringLiteral("titan-acerca"));

    AcercaVentana ventana;
    ventana.show();

    const int indiceCaptura =
        argumentos.indexOf(QStringLiteral("--captura"));
    if (indiceCaptura >= 0 && indiceCaptura + 1 < argumentos.size()) {
        QApplication::processEvents();
        if (!ventana.grab().save(argumentos.at(indiceCaptura + 1))) {
            std::fprintf(stderr, "no se pudo guardar la captura\n");
            return 1;
        }
        return 0;
    }

    if (tieneArgumento(argumentos, QStringLiteral("--autocerrar"))) {
        QTimer::singleShot(1200, &app, &QCoreApplication::quit);
    }

    return app.exec();
}
