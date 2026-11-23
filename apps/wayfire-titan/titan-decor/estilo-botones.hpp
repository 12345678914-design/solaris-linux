#pragma once
/*
 * Inti OS - estilos de los botones de ventana (_ minimizar, [] maximizar, X cerrar).
 *
 * Cada estilo es una clase aparte en su propio fichero (estilo-*.cpp), sin
 * relacion con los demas. Solo se crea el elegido en Ajustes > Ventanas
 * (theme.conf: [Theme] windowStyle=...): al cambiarlo se destruye el anterior
 * y se crea el nuevo, asi que los que no se usan no gastan memoria.
 */
#include <algorithm>
#include <cairo.h>
#include <cmath>
#include <memory>
#include <string>
#include "deco-button.hpp"

namespace wf
{
namespace titan_decor
{
/** Donde y como de grandes van los botones (medidas en px para una barra de 28 px). */
struct medidas_botones_t
{
    bool derecha;       // false: a la izquierda (como macOS)
    double ancho;       // ancho de cada boton
    double alto;        // alto de cada boton
    double separacion;  // hueco entre botones
    double margen;      // hueco hasta el borde de la ventana
    const char *orden;  // de izquierda a derecha
};

/** Lo que hace falta para pintar un boton. */
struct pintura_t
{
    bool oscuro;    // modo oscuro
    unsigned acento; // color de acento 0xRRGGBB
    bool activa;    // ventana con el foco
    double raton;   // 0 normal, 1 raton encima, negativo pulsado
};

class estilo_botones_t
{
  public:
    virtual ~estilo_botones_t() = default;
    virtual medidas_botones_t medidas() const = 0;
    /** Pinta un boton en un lienzo de w x h (ya escalado). */
    virtual void dibujar(cairo_t *cr, button_type_t boton, double w, double h,
        const pintura_t& p) const = 0;
};

/** Nombres validos: actual windows circulos acento capsula contorno color. */
std::unique_ptr<estilo_botones_t> crear_estilo_botones(const std::string& nombre);

std::unique_ptr<estilo_botones_t> crear_estilo_actual();
std::unique_ptr<estilo_botones_t> crear_estilo_windows();
std::unique_ptr<estilo_botones_t> crear_estilo_circulos();
std::unique_ptr<estilo_botones_t> crear_estilo_acento();
std::unique_ptr<estilo_botones_t> crear_estilo_capsula();
std::unique_ptr<estilo_botones_t> crear_estilo_contorno();
std::unique_ptr<estilo_botones_t> crear_estilo_color();

/* Utilidades de dibujo (solo funciones, sin estado). */
namespace pincel
{
inline void color(cairo_t *cr, unsigned rgb, double a = 1.0)
{
    cairo_set_source_rgba(cr, ((rgb >> 16) & 0xff) / 255.0, ((rgb >> 8) & 0xff) / 255.0,
        (rgb & 0xff) / 255.0, a);
}

/** Simbolo _ [] X centrado en (cx, cy), de lado s y grosor g. */
inline void simbolo(cairo_t *cr, button_type_t b, double cx, double cy, double s, double g)
{
    const double m = s / 2;
    cairo_set_line_width(cr, g);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
    switch (b)
    {
      case BUTTON_MINIMIZE:
        cairo_move_to(cr, cx - m, cy);
        cairo_line_to(cr, cx + m, cy);
        break;

      case BUTTON_TOGGLE_MAXIMIZE:
      {
        const double r = s * 0.18;
        cairo_new_sub_path(cr);
        cairo_arc(cr, cx + m - r, cy - m + r, r, -M_PI / 2, 0);
        cairo_arc(cr, cx + m - r, cy + m - r, r, 0, M_PI / 2);
        cairo_arc(cr, cx - m + r, cy + m - r, r, M_PI / 2, M_PI);
        cairo_arc(cr, cx - m + r, cy - m + r, r, M_PI, 3 * M_PI / 2);
        cairo_close_path(cr);
        break;
      }

      default:
        cairo_move_to(cr, cx - m, cy - m);
        cairo_line_to(cr, cx + m, cy + m);
        cairo_move_to(cr, cx + m, cy - m);
        cairo_line_to(cr, cx - m, cy + m);
        break;
    }

    cairo_stroke(cr);
}

/** Rectangulo redondeado (esquinas de radio r). */
inline void caja(cairo_t *cr, double x, double y, double w, double h, double r)
{
    r = std::min(r, std::min(w, h) / 2);
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - r, y + r, r, -M_PI / 2, 0);
    cairo_arc(cr, x + w - r, y + h - r, r, 0, M_PI / 2);
    cairo_arc(cr, x + r, y + h - r, r, M_PI / 2, M_PI);
    cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
    cairo_close_path(cr);
}

/** Color del texto de la barra (claro u oscuro). */
inline unsigned texto(bool oscuro)
{
    return oscuro ? 0xf2f2f5 : 0x1d1d1f;
}
} // namespace pincel
}
}
