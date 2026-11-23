/* Estilo "color": circulos de color con el simbolo siempre visible, a la
 * derecha y en el orden de Windows (_ [] X). Gris sin el foco. */
#include "estilo-botones.hpp"
#include <algorithm>
#include <cmath>

namespace wf
{
namespace titan_decor
{
namespace
{
class estilo_color_t : public estilo_botones_t
{
  public:
    medidas_botones_t medidas() const override
    {
        return {true, 16, 16, 7, 10, "minimize maximize close"};
    }

    void dibujar(cairo_t *cr, button_type_t b, double w, double h, const pintura_t& p) const override
    {
        const double raton = std::clamp(p.raton, -1.0, 1.0);
        unsigned fill = (b == BUTTON_CLOSE) ? 0xff5f57 : (b == BUTTON_MINIMIZE) ? 0xfebc2e : 0x28c840;
        if (!p.activa && (raton <= 1e-3))
        {
            fill = p.oscuro ? 0x4b4e58 : 0xcfcfd3;
        }

        const double r = std::min(w, h) / 2 - 0.5 - (raton > 0 ? 0 : 0.6);
        cairo_arc(cr, w / 2, h / 2, r, 0, 2 * M_PI);
        const double k = raton < 0 ? 0.8 : 1.0;
        cairo_set_source_rgba(cr, ((fill >> 16) & 0xff) / 255.0 * k, ((fill >> 8) & 0xff) / 255.0 * k,
            (fill & 0xff) / 255.0 * k, 1.0);
        cairo_fill_preserve(cr);
        cairo_set_line_width(cr, 0.6);
        cairo_set_source_rgba(cr, 0, 0, 0, 0.15);
        cairo_stroke(cr);

        cairo_set_source_rgba(cr, 0, 0, 0, p.activa || raton > 0 ? 0.62 : 0.35);
        pincel::simbolo(cr, b, w / 2, h / 2, b == BUTTON_TOGGLE_MAXIMIZE ? 6 : 6.5, 1.4);
    }
};
}

std::unique_ptr<estilo_botones_t> crear_estilo_color()
{
    return std::make_unique<estilo_color_t>();
}
}
}
