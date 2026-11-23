#include "deco-theme.hpp"
#include <wayfire/core.hpp>
#include <wayfire/opengl.hpp>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <string>

/*
 * Inti OS: Wayfire window bar with the Titan look.
 * Based on Wayfire's "decoration" plugin (MIT, see LICENSE-wayfire).
 * Changes: window buttons drawn by the style chosen in Ajustes > Ventanas
 * (estilo-*.cpp, one class per style), centred title, and colours from the
 * Titan theme (light/dark, accent).
 */
namespace
{
/** isDark from ~/.config/titan/theme.conf ([Theme] isDark=true). Dark by default. */
bool titan_dark()
{
    const char *home = std::getenv("HOME");
    if (!home)
    {
        return true;
    }

    std::ifstream f(std::string(home) + "/.config/titan/theme.conf");
    std::string line;
    while (std::getline(f, line))
    {
        if (line.rfind("isDark", 0) == 0)
        {
            return line.find("true") != std::string::npos;
        }
    }

    return true;
}

/** accent from ~/.config/titan/theme.conf ([Theme] accent=#rrggbb). Blue by default. */
unsigned titan_accent()
{
    const char *home = std::getenv("HOME");
    if (home)
    {
        std::ifstream f(std::string(home) + "/.config/titan/theme.conf");
        std::string line;
        while (std::getline(f, line))
        {
            if (line.rfind("accent", 0) == 0)
            {
                auto h = line.find('#');
                if ((h != std::string::npos) && (line.size() >= h + 7))
                {
                    try
                    {
                        return (unsigned)std::stoul(line.substr(h + 1, 6), nullptr, 16);
                    } catch (...)
                    {}
                }
            }
        }
    }

    return 0x0071e3;
}

/** windowStyle from ~/.config/titan/theme.conf ([Theme] windowStyle=acento). */
std::string titan_estilo()
{
    const char *home = std::getenv("HOME");
    if (home)
    {
        std::ifstream f(std::string(home) + "/.config/titan/theme.conf");
        std::string line;
        while (std::getline(f, line))
        {
            if (line.rfind("windowStyle=", 0) == 0)
            {
                std::string v = line.substr(12);
                while (!v.empty() && ((v.back() == '\r') || (v.back() == ' ')))
                {
                    v.pop_back();
                }

                return v;
            }
        }
    }

    return "actual";
}

wf::color_t hex(unsigned rgb, double a = 1.0)
{
    return {((rgb >> 16) & 0xff) / 255.0, ((rgb >> 8) & 0xff) / 255.0, (rgb & 0xff) / 255.0, a};
}
}

namespace wf
{
namespace titan_decor
{
/** Create a new theme with the default parameters */
decoration_theme_t::decoration_theme_t()
{
    dark    = titan_dark();
    accent  = titan_accent();
    estilo  = crear_estilo_botones(titan_estilo());
    medidas = estilo->medidas();
}

std::string decoration_theme_t::firma_tema()
{
    return std::string(titan_dark() ? "1" : "0") + "/" + std::to_string(titan_accent()) + "/" + titan_estilo();
}

wf::color_t decoration_theme_t::get_bar_color(bool active) const
{
    if (!follow_titan_theme)
    {
        return active ? (wf::color_t)active_color : (wf::color_t)inactive_color;
    }

    // Same colours as the Titan apps' bar and labwc's themerc.
    if (dark)
    {
        return active ? hex(0x111113) : hex(0x0a0a0b);
    }

    return active ? hex(0xe8e8eb) : hex(0xf3f3f5);
}

/** @return The available height for displaying the title */
int decoration_theme_t::get_title_height() const
{
    return title_height;
}

/** @return The available border for resizing */
int decoration_theme_t::get_border_size() const
{
    return border_size;
}

/** @return The scale factor for buttons */
double decoration_theme_t::get_button_scale() const
{
    return button_scale;
}

/** @return The vertical padding for buttons */
int decoration_theme_t::get_button_padding() const
{
    return button_padding;
}

/** @return The available border for resizing */
void decoration_theme_t::set_buttons(button_type_t flags)
{
    button_flags = flags;
}

/**
 * Fill the given rectangle with the background color(s).
 *
 * @param fb The target framebuffer, must have been bound already
 * @param rectangle The rectangle to redraw.
 * @param scissor The GL scissor rectangle to use.
 * @param active Whether to use active or inactive colors
 */
void decoration_theme_t::render_background(const wf::scene::render_instruction_t& data,
    wf::geometry_t rectangle, bool active) const
{
    data.pass->add_rect(get_bar_color(active), data.target, rectangle, data.damage);
    if (!follow_titan_theme)
    {
        return;
    }

    // Línea de 1 px alrededor de la ventana con el color de acento de Ajustes
    // (más suave si no está activa), como las apps de Inti.
    const wf::color_t c = hex(accent, active ? 1.0 : 0.45);
    const auto& r = rectangle;
    data.pass->add_rect(c, data.target, {r.x, r.y, r.width, 1}, data.damage);
    data.pass->add_rect(c, data.target, {r.x, r.y + r.height - 1, r.width, 1}, data.damage);
    data.pass->add_rect(c, data.target, {r.x, r.y, 1, r.height}, data.damage);
    data.pass->add_rect(c, data.target, {r.x + r.width - 1, r.y, 1, r.height}, data.damage);
}

/**
 * Render the given text on a cairo_surface_t with the given size.
 * The caller is responsible for freeing the memory afterwards.
 */
cairo_surface_t*decoration_theme_t::render_text(std::string text,
    int width, int height, bool active) const
{
    const auto format = CAIRO_FORMAT_ARGB32;
    auto surface = cairo_image_surface_create(format, width, height);

    if ((height == 0) || (width == 0))
    {
        return surface;
    }

    wf::color_t color = font_color;
    if (follow_titan_theme)
    {
        color = dark ? (active ? hex(0xf2f4f8) : hex(0x7a7f8e)) :
            (active ? hex(0x2c2c2e) : hex(0xa0a0a6));
    }

    auto cr = cairo_create(surface);
    const float font_size = height * font_scale;

    PangoFontDescription *font_desc = pango_font_description_from_string(((std::string)font).c_str());
    pango_font_description_set_absolute_size(font_desc, font_size * PANGO_SCALE);

    PangoLayout *layout = pango_cairo_create_layout(cr);
    pango_layout_set_font_description(layout, font_desc);
    pango_layout_set_text(layout, text.c_str(), text.size());
    // Centred title, with "…" if it doesn't fit (macOS).
    pango_layout_set_width(layout, width * PANGO_SCALE);
    pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
    pango_layout_set_alignment(layout, PANGO_ALIGN_CENTER);
    pango_layout_set_single_paragraph_mode(layout, TRUE);

    int text_w = 0, text_h = 0;
    pango_layout_get_pixel_size(layout, &text_w, &text_h);
    cairo_move_to(cr, 0, std::max(0.0, (height - text_h) / 2.0));
    cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
    pango_cairo_show_layout(cr, layout);

    pango_font_description_free(font_desc);
    g_object_unref(layout);
    cairo_destroy(cr);

    return surface;
}

cairo_surface_t*decoration_theme_t::get_button_surface(button_type_t button,
    const button_state_t& state) const
{
    // Se pinta al doble de tamaño: se ve nítido aunque la pantalla escale.
    const double k = 2.0;
    cairo_surface_t *button_surface = cairo_image_surface_create(
        CAIRO_FORMAT_ARGB32, std::ceil(state.width * k), std::ceil(state.height * k));

    auto cr = cairo_create(button_surface);
    cairo_set_antialias(cr, CAIRO_ANTIALIAS_BEST);
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
    cairo_paint(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
    cairo_scale(cr, k, k);

    const pintura_t p{dark, accent, state.active, std::clamp(state.hover_progress, -1.0, 1.0)};
    estilo->dibujar(cr, button, state.width, state.height, p);

    cairo_destroy(cr);
    return button_surface;
}
}
}
