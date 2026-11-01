#ifndef TITAN_LAYERSHELL_H
#define TITAN_LAYERSHELL_H

#include <QString>

class QWidget;

// Envoltorio pequeno de LayerShellQt. Devuelve false cuando no se esta en
// Wayland o cuando el compositor no ofrece layer-shell; en ese caso la
// ventana sigue funcionando como ventana normal para las pruebas en host.
namespace TitanCapa {

enum class Capa {
    Fondo,
    Barra,
    Centro,
};

bool aplicar(QWidget *ventana, Capa capa, int zonaExclusiva,
             bool tecladoExclusivo, const QString &ambito);

} // namespace TitanCapa

#endif
