// titan-wobbly-guard: plugin de Wayfire para Inti OS.
//
// El plugin "resize" de Wayfire arranca el efecto gelatina (wobbly) al
// empezar a redimensionar, anclado a la esquina contraria. Mientras el
// cliente va cambiando de tamano, la malla del wobbly intenta seguir una
// geometria que no para de cambiar y la ventana se mueve de forma rara; si
// se encadenan redimensionados, la deformacion se acumula.
//
// Este plugin quita el efecto en cuanto empieza un redimensionado: la
// ventana se queda quieta mientras cambia de tamano. Al terminar no queda
// nada pendiente, y el siguiente movimiento crea una malla nueva desde cero.
// Mover ventanas, maximizar con el plugin grid, etc. siguen con gelatina.

#include <wayfire/plugin.hpp>
#include <wayfire/core.hpp>
#include <wayfire/output.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/view-transform.hpp>
#include <wayfire/util.hpp>
#include <wayfire/plugins/wobbly/wobbly-signal.hpp>

#include <set>

class titan_wobbly_guard : public wf::plugin_interface_t
{
    // Vistas a las que hay que quitar la gelatina en la siguiente vuelta del
    // bucle (el orden de entrega de la senal no esta garantizado: puede que el
    // plugin wobbly aun no haya creado la malla cuando llega aqui).
    std::set<wayfire_toplevel_view> pendientes;
    wf::wl_idle_call idle_quitar;

    static bool redimensionando(wayfire_toplevel_view view)
    {
        auto *salida = view->get_output();
        return salida && salida->is_plugin_active("resize");
    }

    void quitar_pendientes()
    {
        for (auto& view : pendientes)
        {
            auto nodo = view->get_transformed_node();
            if (nodo && nodo->get_transformer("wobbly"))
            {
                nodo->rem_transformer("wobbly");
            }
        }

        pendientes.clear();
    }

    wf::signal::connection_t<wobbly_signal> al_wobbly = [=] (wobbly_signal *ev)
    {
        if (!ev->view || !(ev->events & (WOBBLY_EVENT_GRAB | WOBBLY_EVENT_ACTIVATE)))
        {
            return;
        }

        if (!redimensionando(ev->view))
        {
            return;
        }

        pendientes.insert(ev->view);
        idle_quitar.run_once([=] () { quitar_pendientes(); });
    };

    // Si la ventana se cierra antes de que corra el idle, se olvida.
    wf::signal::connection_t<wf::view_unmapped_signal> al_desmapear =
        [=] (wf::view_unmapped_signal *ev)
    {
        if (auto toplevel = wf::toplevel_cast(ev->view))
        {
            pendientes.erase(toplevel);
        }
    };

  public:
    void init() override
    {
        wf::get_core().connect(&al_wobbly);
        wf::get_core().connect(&al_desmapear);
    }

    void fini() override
    {
        al_wobbly.disconnect();
        al_desmapear.disconnect();
        pendientes.clear();
    }
};

DECLARE_WAYFIRE_PLUGIN(titan_wobbly_guard);
