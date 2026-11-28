// titan-gestos: gestos del panel táctil para Inti OS (como en Ubuntu,
// Fedora o macOS).
//
// Wayfire solo trae, para el panel táctil, el cambio de escritorio con tres
// dedos a los lados (plugin vswipe). Este plugin añade el resto:
//
//   3 dedos arriba     ver todas las ventanas (scale)
//   3 dedos abajo      mostrar el escritorio (o cerrar la vista de ventanas)
//   4 dedos arriba     Launchpad (todas las apps)
//   4 dedos abajo      ver los escritorios (expo)
//   pellizcar 4 dedos  Launchpad; separarlos: mostrar el escritorio
//
// Cada gesto se decide al levantar los dedos: dirección dominante y un
// recorrido mínimo, así un roce no hace nada. Las acciones se cambian en
// [titan-gestos] de wayfire.ini: "ipc metodo/de/wayfire", "comando programa"
// o "none". Los gestos de dos dedos (desplazar, zoom) siguen yendo a las apps.

#include <wayfire/plugin.hpp>
#include <wayfire/core.hpp>
#include <wayfire/output.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/plugins/ipc/ipc-helpers.hpp>
#include <wayfire/util/log.hpp>

#include <cmath>
#include <string>

class titan_gestos : public wf::plugin_interface_t
{
    wf::option_wrapper_t<std::string> arriba_3{"titan-gestos/arriba_3"};
    wf::option_wrapper_t<std::string> abajo_3{"titan-gestos/abajo_3"};
    wf::option_wrapper_t<std::string> arriba_4{"titan-gestos/arriba_4"};
    wf::option_wrapper_t<std::string> abajo_4{"titan-gestos/abajo_4"};
    wf::option_wrapper_t<std::string> izquierda_4{"titan-gestos/izquierda_4"};
    wf::option_wrapper_t<std::string> derecha_4{"titan-gestos/derecha_4"};
    wf::option_wrapper_t<std::string> pellizcar_4{"titan-gestos/pellizcar_4"};
    wf::option_wrapper_t<std::string> separar_4{"titan-gestos/separar_4"};
    wf::option_wrapper_t<bool> activado{"titan-gestos/activado"};
    wf::option_wrapper_t<double> recorrido{"titan-gestos/recorrido"};

    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc;

    // Deslizamiento en curso
    uint32_t dedos = 0;
    double suma_x  = 0, suma_y = 0;
    // Pellizco en curso
    uint32_t dedos_pellizco = 0;
    double escala = 1.0;

    static bool activo(const std::string& plugin)
    {
        auto *salida = wf::get_core().seat->get_active_output();
        return salida && salida->is_plugin_active(plugin);
    }

    void ejecutar(const std::string& accion)
    {
        if (accion.empty() || (accion == "none"))
        {
            return;
        }

        if (accion.rfind("ipc ", 0) == 0)
        {
            wf::json_t datos;
            datos["origen"] = std::string("titan-gestos");
            ipc->call_method(accion.substr(4), std::move(datos));
        } else if (accion.rfind("comando ", 0) == 0)
        {
            wf::get_core().run(accion.substr(8));
        } else
        {
            LOGW("titan-gestos: accion desconocida: ", accion);
        }
    }

    // Con la vista de ventanas o de escritorios abierta, el gesto contrario
    // la cierra (como en Ubuntu: deslizar abajo vuelve de la vista general).
    bool cerrar_vista_abierta()
    {
        if (activo("scale"))
        {
            ejecutar("ipc scale/toggle");
            return true;
        }

        if (activo("expo"))
        {
            ejecutar("ipc expo/toggle");
            return true;
        }

        return false;
    }

    // Decide y ejecuta el gesto de deslizar (n dedos, recorrido total)
    void deslizar(uint32_t n, double suma_x, double suma_y)
    {
        if (!activado || ((n != 3) && (n != 4)))
        {
            return;
        }

        const double ax = std::abs(suma_x), ay = std::abs(suma_y);
        const double minimo = recorrido;
        const bool vertical = (ay >= minimo) && (ay > ax * 1.3);
        const bool horizontal = (ax >= minimo) && (ax > ay * 1.3);

        if (n == 3)
        {
            // A los lados: lo hace vswipe (cambiar de escritorio)
            if (!vertical)
            {
                return;
            }

            if (suma_y < 0)
            {
                if (!activo("scale"))
                {
                    ejecutar(arriba_3);
                }
            } else if (!cerrar_vista_abierta())
            {
                ejecutar(abajo_3);
            }

            return;
        }

        if (vertical)
        {
            if (suma_y < 0)
            {
                if (!activo("expo"))
                {
                    ejecutar(arriba_4);
                }
            } else if (!cerrar_vista_abierta())
            {
                ejecutar(abajo_4);
            }
        } else if (horizontal)
        {
            ejecutar(suma_x < 0 ? izquierda_4 : derecha_4);
        }
    }

    void pellizcar(uint32_t n, double escala)
    {
        // Solo con 4 o más dedos: el de dos es el zoom de las apps
        if (!activado || (n < 4))
        {
            return;
        }

        if (escala < 0.7)
        {
            ejecutar(pellizcar_4);
        } else if (escala > 1.4)
        {
            ejecutar(separar_4);
        }
    }

    // Para probar sin panel táctil (y diagnosticar):
    //   {"dedos":3,"dx":0,"dy":-200} o {"dedos":4,"escala":0.5}
    static double numero(const wf::json_t& datos, const char *clave, double defecto)
    {
        if (!datos.has_member(clave))
        {
            return defecto;
        }

        if (datos[clave].is_int64())
        {
            return (double)(int64_t)datos[clave];
        }

        return datos[clave].is_double() ? (double)datos[clave] : defecto;
    }

    wf::ipc::method_callback simular = [=] (const wf::json_t& datos)
    {
        const auto n = (uint32_t)numero(datos, "dedos", 3);
        if (datos.has_member("escala"))
        {
            pellizcar(n, numero(datos, "escala", 1.0));
        } else
        {
            deslizar(n, numero(datos, "dx", 0), numero(datos, "dy", 0));
        }

        return wf::ipc::json_ok();
    };

    wf::signal::connection_t<wf::input_event_signal<wlr_pointer_swipe_begin_event>> al_empezar =
        [=] (wf::input_event_signal<wlr_pointer_swipe_begin_event> *ev)
    {
        dedos  = ev->event->fingers;
        suma_x = suma_y = 0;
    };

    wf::signal::connection_t<wf::input_event_signal<wlr_pointer_swipe_update_event>> al_mover =
        [=] (wf::input_event_signal<wlr_pointer_swipe_update_event> *ev)
    {
        suma_x += ev->event->dx;
        suma_y += ev->event->dy;
    };

    wf::signal::connection_t<wf::input_event_signal<wlr_pointer_swipe_end_event>> al_terminar =
        [=] (wf::input_event_signal<wlr_pointer_swipe_end_event> *ev)
    {
        const uint32_t n = dedos;
        dedos = 0;
        if (!ev->event->cancelled)
        {
            deslizar(n, suma_x, suma_y);
        }
    };

    wf::signal::connection_t<wf::input_event_signal<wlr_pointer_pinch_begin_event>> al_empezar_pellizco =
        [=] (wf::input_event_signal<wlr_pointer_pinch_begin_event> *ev)
    {
        dedos_pellizco = ev->event->fingers;
        escala = 1.0;
    };

    wf::signal::connection_t<wf::input_event_signal<wlr_pointer_pinch_update_event>> al_pellizcar =
        [=] (wf::input_event_signal<wlr_pointer_pinch_update_event> *ev)
    {
        escala = ev->event->scale;
    };

    wf::signal::connection_t<wf::input_event_signal<wlr_pointer_pinch_end_event>> al_soltar_pellizco =
        [=] (wf::input_event_signal<wlr_pointer_pinch_end_event> *ev)
    {
        const uint32_t n = dedos_pellizco;
        dedos_pellizco = 0;
        if (!ev->event->cancelled)
        {
            pellizcar(n, escala);
        }
    };

  public:
    void init() override
    {
        auto& core = wf::get_core();
        core.connect(&al_empezar);
        core.connect(&al_mover);
        core.connect(&al_terminar);
        core.connect(&al_empezar_pellizco);
        core.connect(&al_pellizcar);
        core.connect(&al_soltar_pellizco);
        ipc->register_method("titan-gestos/simular", simular);
    }

    void fini() override
    {
        al_empezar.disconnect();
        al_mover.disconnect();
        al_terminar.disconnect();
        al_empezar_pellizco.disconnect();
        al_pellizcar.disconnect();
        al_soltar_pellizco.disconnect();
        ipc->unregister_method("titan-gestos/simular");
    }
};

DECLARE_WAYFIRE_PLUGIN(titan_gestos);
