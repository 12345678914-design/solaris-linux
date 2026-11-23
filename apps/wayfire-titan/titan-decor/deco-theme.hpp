#pragma once
#include <wayfire/render-manager.hpp>
#include <wayfire/scene-render.hpp>
#include "deco-button.hpp"
#include "estilo-botones.hpp"
#include <memory>

namespace wf
{
namespace titan_decor
{
/**
 * A  class which manages the outlook of decorations.
 * It is responsible for determining the background colors, sizes, etc.
 */
class decoration_theme_t
{
  public:
    /** Create a new theme with the default parameters */
    decoration_theme_t();

    /** @return The available height for displaying the title */
    int get_title_height() const;
    /** @return The available border for resizing */
    int get_border_size() const;
    /** @return The scale factor for buttons */
    double get_button_scale() const;
    /** @return The vertical padding for buttons */
    int get_button_padding() const;
    /** Set the flags for buttons */
    void set_buttons(button_type_t flags);
    button_type_t button_flags;

    /**
     * Fill the given rectangle with the background color(s).
     *
     * @param data The render data (pass, target, damage)
     * @param rectangle The rectangle to redraw.
     * @param active Whether to use active or inactive colors
     */
    void render_background(const wf::scene::render_instruction_t& data,
        wf::geometry_t rectangle, bool active) const;

    /**
     * Render the given text on a cairo_surface_t with the given size.
     * The caller is responsible for freeing the memory afterwards.
     */
    cairo_surface_t *render_text(std::string text, int width, int height, bool active) const;

    /** Bar colour (Titan theme or the plugin options). */
    wf::color_t get_bar_color(bool active) const;

    struct button_state_t
    {
        /** Button width */
        double width;
        /** Button height */
        double height;
        /** Button outline size */
        double border;
        /** Progress of button hover, in range [-1, 1].
         * Negative numbers are usually used for pressed state. */
        double hover_progress;
        /** Whether the window is the active one (traffic lights in colour). */
        bool active = true;
    };

    /**
     * Get the icon for the given button.
     * The caller is responsible for freeing the memory afterwards.
     *
     * @param button The button type.
     * @param state The button state.
     */
    cairo_surface_t *get_button_surface(button_type_t button,
        const button_state_t& state) const;

    /** Estilo de botones elegido en Ajustes > Ventanas (solo se crea ese). */
    const medidas_botones_t& get_medidas() const
    {
        return medidas;
    }

    /** Lo que se leyo de theme.conf: si cambia, hay que rehacer la barra. */
    static std::string firma_tema();

  private:
    /** Titan theme read from ~/.config/titan/theme.conf when the window opens. */
    bool dark = true;
    unsigned accent = 0x0071e3;
    std::unique_ptr<estilo_botones_t> estilo;
    medidas_botones_t medidas;
    wf::option_wrapper_t<bool> follow_titan_theme{"titan-decor/follow_titan_theme"};
    wf::option_wrapper_t<std::string> font{"titan-decor/font"};
    wf::option_wrapper_t<wf::color_t> font_color{"titan-decor/font_color"};
    wf::option_wrapper_t<int> title_height{"titan-decor/title_height"};
    wf::option_wrapper_t<int> border_size{"titan-decor/border_size"};
    wf::option_wrapper_t<double> font_scale{"titan-decor/font_scale"};
    wf::option_wrapper_t<double> button_scale{"titan-decor/button_scale"};
    wf::option_wrapper_t<int> button_padding{"titan-decor/button_padding"};
    wf::option_wrapper_t<wf::color_t> active_color{"titan-decor/active_color"};
    wf::option_wrapper_t<wf::color_t> inactive_color{"titan-decor/inactive_color"};
};
}
}
