# /etc/profile.d/20-titan-scrollback.sh
# shellcheck shell=bash
#
# Titan Linux 0.1 - historial de la salida en la consola de texto.
#
# Este fichero envuelve la shell de tty1 dentro de una sesion de tmux para que
# la salida que se sale de la pantalla se pueda volver a leer. El porque esta
# en /etc/tmux.conf: la consola del kernel no tiene scroll (en fbcon no hay,
# y en la ISO la consola acaba siendo fbcon), asi que el historial lo tiene que
# aportar un terminal de espacio de usuario.
#
# Reglas, a proposito:
#   - Solo tty1. Es la consola que ve una persona mirando la ventana de QEMU.
#     ttyS0 (la consola por serie, que usan las pruebas automaticas) y el
#     instalador por consola siguen siendo shells normales, sin intermediarios:
#     meter tmux en medio del camino de la serie solo traeria problemas.
#   - Solo shell interactiva: ni scripts ni subshells.
#   - Nunca dos veces: dentro de tmux la variable TMUX ya esta puesta, y el
#     'exec' de abajo no vuelve a ejecutarse.
#   - Si tmux no esta, se sigue con la shell normal. Un 'exec' fallido
#     devolveria al usuario al prompt de login del getty, que es peor.

case $- in
  *i*) ;;
  *) return ;;
esac

[ "$(tty 2>/dev/null)" = "/dev/tty1" ] || return
[ -n "${TMUX:-}" ] && return
command -v tmux >/dev/null 2>&1 || return

# '-A' reutiliza la sesion si ya existe, para que un 'Ctrl+b d' (desprender)
# no deje al usuario fuera de su sesion con todo lo que tenia abierto.
exec tmux new-session -A -s titan
