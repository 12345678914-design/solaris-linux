#include "estilo-botones.hpp"

namespace wf
{
namespace titan_decor
{
std::unique_ptr<estilo_botones_t> crear_estilo_botones(const std::string& n)
{
    if (n == "windows")
    {
        return crear_estilo_windows();
    }

    if (n == "circulos")
    {
        return crear_estilo_circulos();
    }

    if (n == "acento")
    {
        return crear_estilo_acento();
    }

    if (n == "capsula")
    {
        return crear_estilo_capsula();
    }

    if (n == "contorno")
    {
        return crear_estilo_contorno();
    }

    if (n == "color")
    {
        return crear_estilo_color();
    }

    return crear_estilo_actual();
}
}
}
