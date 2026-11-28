/* Estilo "circulos": circulos grises suaves con el simbolo siempre visible,
 * a la derecha (como GNOME). */
#include "estilo-botones.hpp"
#include <algorithm>
#include <cmath>

namespace wf
{
namespace titan_decor
{
namespace
{
class estilo_circulos_t : public estilo_botones_t
{
  public:
    medidas_botones_t medidas() const override
    {
        return {true, 20, 20, 6, 8, "minimize maximize close"};
    }

    void dibujar(cairo_t *cr, button_type_t b, double w, double h, const pintura_t& p) const override
    {
        const double raton = std::clamp(p.raton, -1.0, 1.0);
        const double fondo = raton < 0 ? 0.25 : 0.09 + 0.08 * raton;
        cairo_arc(cr, w / 2, h / 2, std::min(w, h) / 2, 0, 2 * M_PI);
        pincel::color(cr, p.oscuro ? 0xffffff : 0x000000, fondo);
        cairo_fill(cr);
        pincel::color(cr, pincel::texto(p.oscuro), p.activa ? 1.0 : 0.5);
        pincel::simbolo(cr, b, w / 2, h / 2, 7, 1.5);
    }
};
}

std::unique_ptr<estilo_botones_t> crear_estilo_circulos()
{
    return std::make_unique<estilo_circulos_t>();
}
}
}
