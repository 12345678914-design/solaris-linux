/* Estilo "windows": _ [] X planos a la derecha, zonas anchas de todo el alto;
 * cerrar se pone rojo al pasar el raton. */
#include "estilo-botones.hpp"
#include <algorithm>
#include <cmath>

namespace wf
{
namespace titan_decor
{
namespace
{
class estilo_windows_t : public estilo_botones_t
{
  public:
    medidas_botones_t medidas() const override
    {
        return {true, 40, 28, 0, 0, "minimize maximize close"};
    }

    void dibujar(cairo_t *cr, button_type_t b, double w, double h, const pintura_t& p) const override
    {
        const double raton = std::clamp(p.raton, -1.0, 1.0);
        const double f = std::fabs(raton);
        const bool cerrar = (b == BUTTON_CLOSE);
        if (f > 1e-3)
        {
            cairo_rectangle(cr, 0, 0, w, h);
            if (cerrar)
            {
                pincel::color(cr, raton < 0 ? 0xb3261e : 0xc42b1c, f);
            } else
            {
                pincel::color(cr, p.oscuro ? 0xffffff : 0x000000, raton < 0 ? 0.05 : 0.09 * f);
            }

            cairo_fill(cr);
        }

        unsigned c = pincel::texto(p.oscuro);
        double a   = p.activa ? 1.0 : 0.45;
        if (cerrar && (f > 0.5))
        {
            c = 0xffffff;
            a = 1.0;
        }

        pincel::color(cr, c, a);
        pincel::simbolo(cr, b, w / 2, h / 2, 9, 1.0);
    }
};
}

std::unique_ptr<estilo_botones_t> crear_estilo_windows()
{
    return std::make_unique<estilo_windows_t>();
}
}
}
