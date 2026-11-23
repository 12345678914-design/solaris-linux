#include <wayfire/per-output-plugin.hpp>
#include <wayfire/view.hpp>
#include <wayfire/workarea.hpp>
#include <wayfire/matcher.hpp>
#include <wayfire/workspace-set.hpp>
#include <wayfire/output.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/txn/transaction-manager.hpp>

#include "deco-subsurface.hpp"
#include "deco-theme.hpp"
#include <sys/inotify.h>
#include <unistd.h>
#include <cstdlib>
#include <string>
#include "wayfire/core.hpp"
#include "wayfire/plugin.hpp"
#include "wayfire/signal-provider.hpp"
#include "wayfire/toplevel-view.hpp"
#include "wayfire/toplevel.hpp"

class wayfire_titan_decor : public wf::plugin_interface_t
{
    wf::view_matcher_t ignore_views{"titan-decor/ignore_views"};
    wf::view_matcher_t forced_views{"titan-decor/forced_views"};

    wf::signal::connection_t<wf::txn::new_transaction_signal> on_new_tx =
        [=] (wf::txn::new_transaction_signal *ev)
    {
        // For each transaction, we need to consider what happens with participating views
        for (const auto& obj : ev->tx->get_objects())
        {
            if (auto toplevel = std::dynamic_pointer_cast<wf::toplevel_t>(obj))
            {
                // First check whether the toplevel already has decoration
                // In that case, we should just set the correct margins
                if (auto deco = toplevel->get_data<wf::titan_decorator_t>())
                {
                    toplevel->pending().margins = deco->get_margins(toplevel->pending());
                    continue;
                }

                // Second case: the view is already mapped, or the transaction does not map it.
                // The view is not being decorated, so nothing to do here.
                if (toplevel->current().mapped || !toplevel->pending().mapped)
                {
                    continue;
                }

                // Third case: the transaction will map the toplevel.
                auto view = wf::find_view_for_toplevel(toplevel);
                wf::dassert(view != nullptr, "Mapping a toplevel means there must be a corresponding view!");
                if (should_decorate_view(view))
                {
                    adjust_new_decorations(view);
                }
            }
        }
    };

    wf::signal::connection_t<wf::view_decoration_state_updated_signal> on_decoration_state_changed =
        [=] (wf::view_decoration_state_updated_signal *ev)
    {
        update_view_decoration(ev->view);
    };

    // allows criteria containing maximized or floating check
    wf::signal::connection_t<wf::view_tiled_signal> on_view_tiled =
        [=] (wf::view_tiled_signal *ev)
    {
        update_view_decoration(ev->view);
    };

    /* Ajustes escribe ~/.config/titan/theme.conf. Un solo vigilante (inotify)
     * para todo el plugin: si cambia el modo, el acento o el estilo de los
     * botones, se rehacen las barras de las ventanas abiertas. */
    int vigilante = -1;
    wl_event_source *fuente_vigilante = nullptr;
    wf::wl_timer<false> espera_tema;
    std::string firma;

    static int al_cambiar_tema(int fd, uint32_t, void *data)
    {
        char buf[4096];
        while (read(fd, buf, sizeof(buf)) > 0)
        {}

        auto self = static_cast<wayfire_titan_decor*>(data);
        // Ajustes puede escribir varias veces seguidas: se espera un momento.
        self->espera_tema.disconnect();
        self->espera_tema.set_timeout(150, [self] () { self->rehacer_si_cambio(); });
        return 0;
    }

    void rehacer_si_cambio()
    {
        const auto nueva = wf::titan_decor::decoration_theme_t::firma_tema();
        if (nueva == firma)
        {
            return;
        }

        firma = nueva;
        for (auto& view : wf::get_core().get_all_views())
        {
            auto toplevel = wf::toplevel_cast(view);
            if (!toplevel || !is_toplevel_decorated(toplevel->toplevel()))
            {
                continue;
            }

            // Se destruye la barra vieja (con su estilo) y se crea la nueva.
            remove_decoration(toplevel);
            adjust_new_decorations(toplevel);
            wf::get_core().tx_manager->schedule_object(toplevel->toplevel());
        }
    }

    void vigilar_tema()
    {
        const char *home = std::getenv("HOME");
        if (!home)
        {
            return;
        }

        vigilante = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
        if (vigilante < 0)
        {
            return;
        }

        const std::string dir = std::string(home) + "/.config/titan";
        if (inotify_add_watch(vigilante, dir.c_str(), IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE) < 0)
        {
            close(vigilante);
            vigilante = -1;
            return;
        }

        fuente_vigilante = wl_event_loop_add_fd(wf::get_core().ev_loop, vigilante,
            WL_EVENT_READABLE, al_cambiar_tema, this);
    }

  public:
    void init() override
    {
        firma = wf::titan_decor::decoration_theme_t::firma_tema();
        vigilar_tema();
        wf::get_core().connect(&on_decoration_state_changed);
        wf::get_core().tx_manager->connect(&on_new_tx);
        wf::get_core().connect(&on_view_tiled);

        for (auto& view : wf::get_core().get_all_views())
        {
            update_view_decoration(view);
        }
    }

    void fini() override
    {
        espera_tema.disconnect();
        if (fuente_vigilante)
        {
            wl_event_source_remove(fuente_vigilante);
            fuente_vigilante = nullptr;
        }

        if (vigilante >= 0)
        {
            close(vigilante);
            vigilante = -1;
        }

        for (auto view : wf::get_core().get_all_views())
        {
            if (auto toplevel = wf::toplevel_cast(view))
            {
                remove_decoration(toplevel);
                wf::get_core().tx_manager->schedule_object(toplevel->toplevel());
            }
        }
    }

    /**
     * Uses view_matcher_t to match whether the given view needs to be
     * ignored for decoration
     *
     * @param view The view to match
     * @return Whether the given view should be decorated?
     */
    bool ignore_decoration_of_view(wayfire_view view)
    {
        return ignore_views.matches(view);
    }

    /**
     * Uses view_matcher_t to match whether to force decorations onto the
     * given view
     *
     * @param view The view to match
     * @return Whether the given view should be decorated?
     */
    bool force_decoration_of_view(wayfire_view view)
    {
        return forced_views.matches(view);
    }

    bool should_decorate_view(wayfire_toplevel_view view)
    {
        return !ignore_decoration_of_view(view) &&
               (force_decoration_of_view(view) || view->should_be_decorated());
    }

    void adjust_new_decorations(wayfire_toplevel_view view)
    {
        auto toplevel = view->toplevel();

        toplevel->store_data(std::make_unique<wf::titan_decorator_t>(view));
        auto deco     = toplevel->get_data<wf::titan_decorator_t>();
        auto& pending = toplevel->pending();
        pending.margins = deco->get_margins(pending);

        if (!pending.fullscreen && !pending.tiled_edges)
        {
            pending.geometry = wf::expand_geometry_by_margins(pending.geometry, pending.margins);
            if (view->get_output())
            {
                pending.geometry = wf::clamp(pending.geometry, view->get_output()->workarea->get_workarea());
            }
        }
    }

    void remove_decoration(wayfire_toplevel_view view)
    {
        view->toplevel()->erase_data<wf::titan_decorator_t>();
        auto& pending = view->toplevel()->pending();
        if (!pending.fullscreen && !pending.tiled_edges)
        {
            pending.geometry = wf::shrink_geometry_by_margins(pending.geometry, pending.margins);
        }

        pending.margins = {0, 0, 0, 0};
    }

    bool is_toplevel_decorated(const std::shared_ptr<wf::toplevel_t>& toplevel)
    {
        return toplevel->has_data<wf::titan_decorator_t>();
    }

    void update_view_decoration(wayfire_view view)
    {
        if (auto toplevel = wf::toplevel_cast(view))
        {
            const bool wants_decoration = should_decorate_view(toplevel);
            if (wants_decoration != is_toplevel_decorated(toplevel->toplevel()))
            {
                if (wants_decoration)
                {
                    adjust_new_decorations(toplevel);
                } else
                {
                    remove_decoration(toplevel);
                }

                wf::get_core().tx_manager->schedule_object(toplevel->toplevel());
            }
        }
    }
};

DECLARE_WAYFIRE_PLUGIN(wayfire_titan_decor);
