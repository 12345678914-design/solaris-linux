/* Estilo "acento": _ [] X a la derecha; al pasar el raton minimizar y
 * maximizar se tinen del color de acento y cerrar se pone rojo. */
#include "estilo-botones.hpp"
#include <algorithm>
#include <cmath>

namespace wf
{
namespace titan_decor
{
namespace
{
class estilo_acento_t : public estilo_botones_t
{
  public:
    medidas_botones_t medidas() const override
    {
        return {true, 30, 22, 3, 6, "minimize maximize close"};
    }

    void dibujar(cairo_t *cr, button_type_t b, double w, double h, const pintura_t& p) const override
    {
        const double raton = std::clamp(p.raton, -1.0, 1.0);
        const double f = std::fabs(raton);
        const bool cerrar = (b == BUTTON_CLOSE);
        if (f > 1e-3)
        {
            pincel::caja(cr, 0, 0, w, h, 7);
            if (cerrar)
            {
                pincel::color(cr, raton < 0 ? 0xc93a3f : 0xe5484d, f);
            } else
            {
                pincel::color(cr, p.acento, (raton < 0 ? 0.32 : 0.2) * f);
            }

            cairo_fill(cr);
        }

        if (cerrar && (f > 0.5))
        {
            pincel::color(cr, 0xffffff);
        } else if (!cerrar && (f > 0.5))
        {
            pincel::color(cr, p.acento);
        } else
        {
            pincel::color(cr, pincel::texto(p.oscuro), p.activa ? 1.0 : 0.45);
        }

        pincel::simbolo(cr, b, w / 2, h / 2, 9, 1.4);
    }
};
}

std::unique_ptr<estilo_botones_t> crear_estilo_acento()
{
    return std::make_unique<estilo_acento_t>();
}
}
}
