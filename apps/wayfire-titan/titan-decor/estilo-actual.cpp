/* Estilo "actual": semaforo de colores a la izquierda; el simbolo sale al
 * pasar el raton; gris si la ventana no tiene el foco. */
#include "estilo-botones.hpp"
#include <algorithm>
#include <cmath>

namespace wf
{
namespace titan_decor
{
namespace
{
class estilo_actual_t : public estilo_botones_t
{
  public:
    medidas_botones_t medidas() const override
    {
        return {false, 13, 13, 8, 15, "close minimize maximize"};
    }

    void dibujar(cairo_t *cr, button_type_t b, double w, double h, const pintura_t& p) const override
    {
        unsigned fill = (b == BUTTON_CLOSE) ? 0xff5f57 : (b == BUTTON_MINIMIZE) ? 0xfebc2e : 0x28c840;
        const double raton = std::clamp(p.raton, -1.0, 1.0);
        if (!p.activa && (raton <= 1e-3))
        {
            fill = p.oscuro ? 0x4b4e58 : 0xcfcfd3;
        }

        const double cx = w / 2, cy = h / 2, r = std::min(w, h) / 2 - 0.5;
        cairo_arc(cr, cx, cy, r, 0, 2 * M_PI);
        const double k = raton < 0 ? 1.0 + 0.35 * raton : 1.0;
        cairo_set_source_rgba(cr, ((fill >> 16) & 0xff) / 255.0 * k, ((fill >> 8) & 0xff) / 255.0 * k,
            (fill & 0xff) / 255.0 * k, 1.0);
        cairo_fill_preserve(cr);
        cairo_set_line_width(cr, 0.6);
        cairo_set_source_rgba(cr, 0, 0, 0, p.oscuro ? 0.25 : 0.12);
        cairo_stroke(cr);

        const double vis = std::fabs(raton);
        if (vis <= 1e-3)
        {
            return;
        }

        cairo_set_source_rgba(cr, 0, 0, 0, 0.55 * vis);
        const double s = r * 0.48;
        if (b == BUTTON_TOGGLE_MAXIMIZE)
        {
            // Dos triangulos en la diagonal (pantalla completa).
            cairo_move_to(cr, cx - s, cy - s * 0.15);
            cairo_line_to(cr, cx - s, cy - s);
            cairo_line_to(cr, cx - s * 0.15, cy - s);
            cairo_close_path(cr);
            cairo_move_to(cr, cx + s, cy + s * 0.15);
            cairo_line_to(cr, cx + s, cy + s);
            cairo_line_to(cr, cx + s * 0.15, cy + s);
            cairo_close_path(cr);
            cairo_fill(cr);
        } else
        {
            pincel::simbolo(cr, b, cx, cy, 2 * s, 1.3);
        }
    }
};
}

std::unique_ptr<estilo_botones_t> crear_estilo_actual()
{
    return std::make_unique<estilo_actual_t>();
}
}
}
