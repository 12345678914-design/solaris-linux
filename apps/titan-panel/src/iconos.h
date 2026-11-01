#ifndef TITAN_ICONOS_H
#define TITAN_ICONOS_H

#include <QIcon>
#include <QString>

// Icono de una aplicacion. Si el tema no tiene el nombre pedido, genera una
// ficha con la inicial para que la barra y el centro nunca queden vacios.
QIcon iconoAplicacion(const QString &nombreTema, const QString &texto);

// Icono del boton Inicio. Se dibuja siempre para que la barra no dependa de
// que el tema de iconos traiga "start-here".
QIcon iconoInicio();

#endif
