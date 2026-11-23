/* Estilo "contorno": circulos de linea fina; al pasar el raton el contorno
 * toma el acento (rojo en cerrar). */
#include "estilo-botones.hpp"
#include <algorithm>
#include <cmath>

namespace wf
{
namespace titan_decor
{
namespace
{
class estilo_contorno_t : public estilo_botones_t
{
  public:
    medidas_botones_t medidas() const override
    {
        return {true, 19, 19, 6, 8, "minimize maximize close"};
    }

    void dibujar(cairo_t *cr, button_type_t b, double w, double h, const pintura_t& p) const override
    {
        const double raton = std::clamp(p.raton, -1.0, 1.0);
        const double f = std::fabs(raton);
        const unsigned tinta = (b == BUTTON_CLOSE) ? 0xe5484d : p.acento;
        const double r = std::min(w, h) / 2 - 0.8;

        cairo_arc(cr, w / 2, h / 2, r, 0, 2 * M_PI);
        if (f > 1e-3)
        {
            pincel::color(cr, tinta, (raton < 0 ? 0.3 : 0.15) * f);
            cairo_fill_preserve(cr);
        }

        cairo_set_line_width(cr, 1.1);
        if (f > 0.5)
        {
            pincel::color(cr, tinta);
        } else
        {
            pincel::color(cr, p.oscuro ? 0xffffff : 0x000000, p.activa ? 0.45 : 0.25);
        }

        cairo_stroke(cr);

        if (f > 0.5)
        {
            pincel::color(cr, tinta);
        } else
        {
            pincel::color(cr, pincel::texto(p.oscuro), p.activa ? 1.0 : 0.45);
        }

        pincel::simbolo(cr, b, w / 2, h / 2, 6.5, 1.3);
    }
};
}

std::unique_ptr<estilo_botones_t> crear_estilo_contorno()
{
    return std::make_unique<estilo_contorno_t>();
}
}
}
