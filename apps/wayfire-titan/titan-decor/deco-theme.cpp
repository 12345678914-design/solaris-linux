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
 * Changes: macOS traffic lights (always in colour, grey when inactive,
 * symbol on hover), buttons on the left, centred title, and colours from
 * the Titan theme (light/dark).
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
    dark = titan_dark();
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
        return active ? hex(0x1e2028) : hex(0x17181e);
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
    cairo_surface_t *button_surface = cairo_image_surface_create(
        CAIRO_FORMAT_ARGB32, state.width, state.height);

    auto cr = cairo_create(button_surface);
    cairo_set_antialias(cr, CAIRO_ANTIALIAS_BEST);

    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
    cairo_paint(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

    // macOS traffic lights (the same as TitanWindow.qml).
    wf::color_t fill;
    switch (button)
    {
      case BUTTON_CLOSE:
        fill = hex(0xff5f57);
        break;

      case BUTTON_MINIMIZE:
        fill = hex(0xfebc2e);
        break;

      case BUTTON_TOGGLE_MAXIMIZE:
        fill = hex(0x28c840);
        break;

      default:
        assert(false);
    }

    // Inactive window: grey lights, unless the pointer is over them.
    const double hover = std::clamp(state.hover_progress, -1.0, 1.0);
    if (!state.active && (hover <= 1e-3))
    {
        fill = dark ? hex(0x4b4e58) : hex(0xcfcfd3);
    }

    // Pressed (negative hover): darker.
    if (hover < 0)
    {
        const double k = 1.0 + 0.35 * hover;
        fill = {fill.r * k, fill.g * k, fill.b * k, fill.a};
    }

    const double cx = state.width / 2.0, cy = state.height / 2.0;
    const double r  = state.width / 2.0 - 0.5;

    cairo_arc(cr, cx, cy, r, 0, 2 * M_PI);
    cairo_set_source_rgba(cr, fill.r, fill.g, fill.b, 1.0);
    cairo_fill_preserve(cr);
    // Thin edge, like macOS.
    cairo_set_line_width(cr, std::max(1.0, state.width / 14.0));
    cairo_set_source_rgba(cr, 0, 0, 0, dark ? 0.25 : 0.12);
    cairo_stroke(cr);

    // Symbol only on hover (fades in with the animation).
    const double glyph = std::fabs(hover);
    if (glyph > 1e-3)
    {
        const double s = state.width * 0.24;
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
        cairo_set_line_width(cr, std::max(1.2, state.width / 9.0));
        cairo_set_source_rgba(cr, 0, 0, 0, 0.55 * glyph);
        switch (button)
        {
          case BUTTON_CLOSE:
            cairo_move_to(cr, cx - s, cy - s);
            cairo_line_to(cr, cx + s, cy + s);
            cairo_move_to(cr, cx + s, cy - s);
            cairo_line_to(cr, cx - s, cy + s);
            cairo_stroke(cr);
            break;

          case BUTTON_MINIMIZE:
            cairo_move_to(cr, cx - s * 1.15, cy);
            cairo_line_to(cr, cx + s * 1.15, cy);
            cairo_stroke(cr);
            break;

          case BUTTON_TOGGLE_MAXIMIZE:
            // Two triangles on the diagonal, like the macOS full-screen button.
            cairo_move_to(cr, cx - s, cy - s * 0.15);
            cairo_line_to(cr, cx - s, cy - s);
            cairo_line_to(cr, cx - s * 0.15, cy - s);
            cairo_close_path(cr);
            cairo_move_to(cr, cx + s, cy + s * 0.15);
            cairo_line_to(cr, cx + s, cy + s);
            cairo_line_to(cr, cx + s * 0.15, cy + s);
            cairo_close_path(cr);
            cairo_fill(cr);
            break;

          default:
            break;
        }
    }

    cairo_destroy(cr);
    return button_surface;
}
}
}
