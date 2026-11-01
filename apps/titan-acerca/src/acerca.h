#ifndef TITAN_ACERCA_H
#define TITAN_ACERCA_H

#include <QString>
#include <QWidget>

#include <QPixmap>

struct DatosEquipo
{
    QString equipo;
    QString ram;
    QString procesador;
    QString disco;
    QString arquitectura;
};

// Lee los datos del equipo desde /proc, QStorageInfo y QSysInfo. No necesita
// privilegios y funciona igual en el live que en el sistema instalado.
DatosEquipo leerDatosEquipo();

// Icono de computadora dibujado a mano: no depende del tema de iconos.
QPixmap iconoComputadora(int lado);

class AcercaVentana : public QWidget
{
    Q_OBJECT

public:
    explicit AcercaVentana(QWidget *padre = nullptr);

private:
    void construir(const DatosEquipo &datos);
};

#endif
