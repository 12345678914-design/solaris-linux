#pragma once
// Nombre de la cuenta que ejecuta la sesion. Se consulta la base de usuarios
// (getpwuid) antes que $USER, que puede faltar o estar falseado. Nunca se
// devuelve un nombre inventado: si no se puede saber, se devuelve vacio.

#include <QString>
#include <pwd.h>
#include <unistd.h>

namespace titan {

inline QString usuarioActual()
{
    if (const passwd *pw = getpwuid(geteuid())) {
        if (pw->pw_name && *pw->pw_name) return QString::fromLocal8Bit(pw->pw_name);
    }
    return QString::fromLocal8Bit(qgetenv("USER"));
}

} // namespace titan
