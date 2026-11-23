/* Estilo "capsula": los tres botones juntos en una capsula a la derecha.
 * Cada boton pinta su trozo: minimizar el extremo izquierdo, cerrar el derecho. */
#include "estilo-botones.hpp"
#include <algorithm>
#include <cmath>

namespace wf
{
namespace titan_decor
{
namespace
{
class estilo_capsula_t : public estilo_botones_t
{
  public:
    medidas_botones_t medidas() const override
    {
        return {true, 30, 22, 0, 8, "minimize maximize close"};
    }

    static void trozo(cairo_t *cr, button_type_t b, double w, double h)
    {
        const double r = h / 2;
        if (b == BUTTON_MINIMIZE)
        {
            cairo_new_sub_path(cr);
            cairo_arc(cr, r, r, r, M_PI / 2, 3 * M_PI / 2);
            cairo_line_to(cr, w, 0);
            cairo_line_to(cr, w, h);
            cairo_close_path(cr);
        } else if (b == BUTTON_CLOSE)
        {
            cairo_new_sub_path(cr);
            cairo_move_to(cr, 0, 0);
            cairo_arc(cr, w - r, r, r, -M_PI / 2, M_PI / 2);
            cairo_line_to(cr, 0, h);
            cairo_close_path(cr);
        } else
        {
            cairo_rectangle(cr, 0, 0, w, h);
        }
    }

    void dibujar(cairo_t *cr, button_type_t b, double w, double h, const pintura_t& p) const override
    {
        const double raton = std::clamp(p.raton, -1.0, 1.0);
        const double f = std::fabs(raton);
        const unsigned base = p.oscuro ? 0xffffff : 0x000000;
        const bool cerrar   = (b == BUTTON_CLOSE);

        trozo(cr, b, w, h);
        pincel::color(cr, base, 0.08);
        cairo_fill(cr);
        if (f > 1e-3)
        {
            trozo(cr, b, w, h);
            if (cerrar)
            {
                pincel::color(cr, raton < 0 ? 0xc93a3f : 0xe5484d, f);
            } else
            {
                pincel::color(cr, base, (raton < 0 ? 0.2 : 0.12) * f);
            }

            cairo_fill(cr);
        }

        if (b != BUTTON_MINIMIZE)
        {
            // Raya que separa este trozo del anterior.
            cairo_move_to(cr, 0.5, h * 0.25);
            cairo_line_to(cr, 0.5, h * 0.75);
            cairo_set_line_width(cr, 1);
            pincel::color(cr, base, 0.15);
            cairo_stroke(cr);
        }

        if (cerrar && (f > 0.5))
        {
            pincel::color(cr, 0xffffff);
        } else
        {
            pincel::color(cr, pincel::texto(p.oscuro), p.activa ? 1.0 : 0.45);
        }

        pincel::simbolo(cr, b, w / 2, h / 2, 8, 1.3);
    }
};
}

std::unique_ptr<estilo_botones_t> crear_estilo_capsula()
{
    return std::make_unique<estilo_capsula_t>();
}
}
}
