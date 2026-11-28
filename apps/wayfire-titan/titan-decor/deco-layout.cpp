#include "deco-layout.hpp"
#include <algorithm>
#include "deco-theme.hpp"
#include <wayfire/core.hpp>
#include <wayfire/nonstd/reverse.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>
#include <wayfire/util.hpp>
#include <sstream>
#include <cmath>

namespace wf
{
namespace titan_decor
{
/**
 * Represents an area of the decoration which reacts to input events.
 */
decoration_area_t::decoration_area_t(decoration_area_type_t type, wf::geometry_t g)
{
    this->type     = type;
    this->geometry = g;

    assert(type != DECORATION_AREA_BUTTON);
}

/**
 * Initialize a new decoration area holding a button
 */
decoration_area_t::decoration_area_t(wf::geometry_t g,
    std::function<void(wf::geometry_t)> damage_callback,
    const decoration_theme_t& theme)
{
    this->type     = DECORATION_AREA_BUTTON;
    this->geometry = g;

    this->button = std::make_unique<button_t>(theme,
        std::bind(damage_callback, g));
}

wf::geometry_t decoration_area_t::get_geometry() const
{
    return geometry;
}

button_t& decoration_area_t::as_button()
{
    assert(button);

    return *button;
}

decoration_area_type_t decoration_area_t::get_type() const
{
    return type;
}

decoration_layout_t::decoration_layout_t(const decoration_theme_t& th,
    std::function<void(wf::geometry_t)> callback) :

    titlebar_size(th.get_title_height()),
    border_size(th.get_border_size()),
    // Medidas del estilo de Ajustes > Ventanas (pensadas para 28 px de barra).
    button_width(std::lround(th.get_medidas().ancho * titlebar_size / 28.0)),
    button_height(std::lround(th.get_medidas().alto * titlebar_size / 28.0)),
    button_padding_width(std::lround(th.get_medidas().separacion * titlebar_size / 28.0)),
    button_padding_height((titlebar_size - button_height) / 2),
    theme(th),
    damage_callback(callback)
{}

wf::geometry_t decoration_layout_t::create_buttons(int width, int)
{
    const auto& m = theme.get_medidas();
    std::stringstream stream(std::string(m.orden));
    std::vector<button_type_t> buttons;
    std::string button_name;
    while (stream >> button_name)
    {
        if ((button_name == "minimize") && (theme.button_flags & BUTTON_MINIMIZE))
        {
            buttons.push_back(BUTTON_MINIMIZE);
        }

        if ((button_name == "maximize") && (theme.button_flags & BUTTON_TOGGLE_MAXIMIZE))
        {
            buttons.push_back(BUTTON_TOGGLE_MAXIMIZE);
        }

        if ((button_name == "close") && (theme.button_flags & BUTTON_CLOSE))
        {
            buttons.push_back(BUTTON_CLOSE);
        }
    }

    // Inti OS: los botones van a la izquierda o a la derecha segun el estilo.
    const int margen = std::lround(m.margen * titlebar_size / 28.0);
    const int n = (int)buttons.size();
    const int total = n > 0 ? n * button_width + (n - 1) * button_padding_width : 0;
    const int x0 = m.derecha ? (width - border_size - margen - total) : (border_size + margen);

    wf::geometry_t button_geometry = {
        (double)x0,
        (double)(button_padding_height + border_size),
        (double)button_width,
        (double)button_height,
    };

    for (auto type : buttons)
    {
        this->layout_areas.push_back(std::make_unique<decoration_area_t>(
            button_geometry, damage_callback, theme));
        this->layout_areas.back()->as_button().set_button_type(type);
        this->layout_areas.back()->as_button().set_active(active);
        button_geometry.x += button_width + button_padding_width;
    }

    // Zona de los botones con su margen (para mover la ventana entre ellos).
    if (m.derecha)
    {
        return {(double)x0, (double)border_size, (double)(width - border_size - x0), (double)titlebar_size};
    }

    return {(double)border_size, (double)border_size, (double)(x0 + total + margen - border_size),
        (double)titlebar_size};
}

/** Regenerate layout using the new size */
void decoration_layout_t::resize(int width, int height)
{
    this->layout_areas.clear();
    if (this->titlebar_size > 0)
    {
        auto zona = create_buttons(width, height);

        /* Padding around the buttons, allows move */
        this->layout_areas.push_back(std::make_unique<decoration_area_t>(
            DECORATION_AREA_MOVE, zona));

        /* Titulo centrado en la ventana: deja el mismo hueco en los dos lados
         * que ocupan los botones. El resto de la barra tambien mueve. */
        const double hueco = zona.width;
        wf::geometry_t title_geometry = {
            border_size + hueco,
            (double)border_size,
            std::max(0.0, width - 2.0 * (border_size + hueco)),
            (double)titlebar_size,
        };
        const double lado_libre_x = theme.get_medidas().derecha ? border_size : title_geometry.x + title_geometry.width;
        this->layout_areas.push_back(std::make_unique<decoration_area_t>(
            DECORATION_AREA_MOVE, wf::geometry_t{lado_libre_x, (double)border_size,
                std::max(0.0, hueco), (double)titlebar_size}));
        this->layout_areas.push_back(std::make_unique<decoration_area_t>(
            DECORATION_AREA_TITLE, title_geometry));
    }

    /* Resizing edges - left */
    wf::geometry_t border_geometry = {0.0, 0.0, (double)border_size, (double)height};
    this->layout_areas.push_back(std::make_unique<decoration_area_t>(
        DECORATION_AREA_RESIZE_LEFT, border_geometry));

    /* Resizing edges - right */
    border_geometry = {(double)(width - border_size), 0.0, (double)border_size, (double)height};
    this->layout_areas.push_back(std::make_unique<decoration_area_t>(
        DECORATION_AREA_RESIZE_RIGHT, border_geometry));

    /* Resizing edges - top */
    border_geometry = {0.0, 0.0, (double)width, (double)border_size};
    this->layout_areas.push_back(std::make_unique<decoration_area_t>(
        DECORATION_AREA_RESIZE_TOP, border_geometry));

    /* Resizing edges - bottom */
    border_geometry = {0.0, (double)(height - border_size), (double)width, (double)border_size};
    this->layout_areas.push_back(std::make_unique<decoration_area_t>(
        DECORATION_AREA_RESIZE_BOTTOM, border_geometry));
}

/**
 * @return The decoration areas which need to be rendered, in top to bottom
 *  order.
 */
std::vector<nonstd::observer_ptr<decoration_area_t>> decoration_layout_t::get_renderable_areas()
{
    std::vector<nonstd::observer_ptr<decoration_area_t>> renderable;
    for (auto& area : layout_areas)
    {
        if (area->get_type() & DECORATION_AREA_RENDERABLE_BIT)
        {
            renderable.push_back({area});
        }
    }

    return renderable;
}

wf::regionf_t decoration_layout_t::calculate_region() const
{
    wf::regionf_t r{};
    for (auto& area : layout_areas)
    {
        auto g = area->get_geometry();
        if ((g.width > 0) && (g.height > 0))
        {
            r |= g;
        }
    }

    return r;
}

void decoration_layout_t::unset_hover(std::optional<wf::pointf_t> position)
{
    auto area = find_area_at(position);
    if (area && (area->get_type() == DECORATION_AREA_BUTTON))
    {
        area->as_button().set_hover(false);
    }
}

/** Handle motion event to (x, y) relative to the decoration */
decoration_layout_t::action_response_t decoration_layout_t::handle_motion(
    int x, int y)
{
    auto previous_area = find_area_at(current_input);
    auto current_area  = find_area_at(wf::pointf_t{(double)x, (double)y});

    if (previous_area == current_area)
    {
        if (is_grabbed && current_area &&
            (current_area->get_type() & DECORATION_AREA_MOVE_BIT))
        {
            is_grabbed = false;
            return {DECORATION_ACTION_MOVE, 0};
        }
    } else
    {
        unset_hover(current_input);
        if (current_area && (current_area->get_type() == DECORATION_AREA_BUTTON))
        {
            current_area->as_button().set_hover(true);
        }
    }

    this->current_input = wf::pointf_t{(double)x, (double)y};
    update_cursor();

    return {DECORATION_ACTION_NONE, 0};
}

/**
 * Handle press or release event.
 * @param pressed Whether the event is a press(true) or release(false)
 *  event.
 * @return The action which needs to be carried out in response to this
 *  event.
 * */
decoration_layout_t::action_response_t decoration_layout_t::handle_press_event(
    bool pressed, uint32_t button)
{
    if (pressed)
    {
        auto area = find_area_at(current_input);
        if (area && (area->get_type() & DECORATION_AREA_MOVE_BIT))
        {
            if (timer.is_connected())
            {
                double_click_at_release = true;
            } else
            {
                timer.set_timeout(300, [] () { return false; });
            }
        }

        if (area && (area->get_type() & DECORATION_AREA_RESIZE_BIT) && (button == BTN_LEFT))
        {
            return {DECORATION_ACTION_RESIZE, calculate_resize_edges()};
        }

        if (area && (area->get_type() == DECORATION_AREA_BUTTON))
        {
            area->as_button().set_pressed(true);
        }

        is_grabbed  = true;
        grab_origin = current_input.value_or(wf::pointf_t{0.0, 0.0});
    }

    if (!pressed && double_click_at_release)
    {
        double_click_at_release = false;
        if (button == BTN_LEFT)
        {
            return {DECORATION_ACTION_TOGGLE_MAXIMIZE, 0};
        }
    } else if (!pressed && is_grabbed)
    {
        is_grabbed = false;
        auto begin_area = find_area_at(grab_origin);
        auto end_area   = find_area_at(current_input);

        if (begin_area && (begin_area->get_type() == DECORATION_AREA_BUTTON))
        {
            begin_area->as_button().set_pressed(false);
            if (end_area && (begin_area == end_area))
            {
                switch (begin_area->as_button().get_button_type())
                {
                  case BUTTON_CLOSE:
                    if (button == BTN_LEFT)
                    {
                        return {DECORATION_ACTION_CLOSE, 0};
                    }

                    break;

                  case BUTTON_TOGGLE_MAXIMIZE:
                    if (button == BTN_LEFT)
                    {
                        return {DECORATION_ACTION_TOGGLE_MAXIMIZE, 0};
                    } else if (button == BTN_MIDDLE)
                    {
                        return {DECORATION_ACTION_TOGGLE_MAXIMIZE_VERTICAL, 0};
                    } else if (button == BTN_RIGHT)
                    {
                        return {DECORATION_ACTION_TOGGLE_MAXIMIZE_HORIZONTAL, 0};
                    }

                    break;

                  case BUTTON_MINIMIZE:
                    if (button == BTN_LEFT)
                    {
                        return {DECORATION_ACTION_MINIMIZE, 0};
                    }

                    break;

                  default:
                    break;
                }
            }
        }
    }

    return {DECORATION_ACTION_NONE, 0};
}

/**
 * Find the layout area at the given coordinates, if any
 * @return The layout area or null on failure
 */
nonstd::observer_ptr<decoration_area_t> decoration_layout_t::find_area_at(std::optional<wf::pointf_t> point)
{
    if (!point)
    {
        return nullptr;
    }

    for (auto& area : this->layout_areas)
    {
        if (area->get_geometry() & *point)
        {
            return {area};
        }
    }

    return nullptr;
}

/** Calculate resize edges based on @current_input */
uint32_t decoration_layout_t::calculate_resize_edges() const
{
    if (!this->current_input.has_value())
    {
        return 0;
    }

    uint32_t edges = 0;
    for (auto& area : layout_areas)
    {
        if (area->get_geometry() & *this->current_input)
        {
            if (area->get_type() & DECORATION_AREA_RESIZE_BIT)
            {
                edges |= (area->get_type() & ~DECORATION_AREA_RESIZE_BIT);
            }
        }
    }

    return edges;
}

/** Update the cursor based on @current_input */
void decoration_layout_t::update_cursor() const
{
    uint32_t edges   = calculate_resize_edges();
    auto cursor_name = edges > 0 ?
        wlr_xcursor_get_resize_name((wlr_edges)edges) : "default";
    wf::get_core().set_cursor(cursor_name);
}

void decoration_layout_t::handle_focus_lost()
{
    if (is_grabbed)
    {
        this->is_grabbed = false;
        auto area = find_area_at(grab_origin);
        if (area && (area->get_type() == DECORATION_AREA_BUTTON))
        {
            area->as_button().set_pressed(false);
        }
    }

    this->unset_hover(current_input);
}
void decoration_layout_t::set_active(bool active)
{
    this->active = active;
    for (auto& area : layout_areas)
    {
        if (area->get_type() == DECORATION_AREA_BUTTON)
        {
            area->as_button().set_active(active);
        }
    }
}
}
}
