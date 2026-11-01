# /etc/profile.d/10-titan.sh
# shellcheck shell=bash
# Titan Linux 0.1 - entorno de shell de la ISO en vivo.
#
# Define el prompt, los alias comodos y el mensaje de bienvenida. Lo carga
# bash en cada shell de login (que es lo que arranca getty con autologin).

# No ensuciar la salida de scripts no interactivos.
case $- in
  *i*) ;;
  *) return ;;
esac

# --- version de la distribucion, leida una sola vez -----------------------
if [[ -z "${TITAN_PRETTY_NAME:-}" ]]; then
  if [[ -r /etc/titan-release ]]; then
    TITAN_PRETTY_NAME="$(sed -n 's/^PRETTY_NAME="\(.*\)"$/\1/p' /etc/titan-release)"
  fi
  TITAN_PRETTY_NAME="${TITAN_PRETTY_NAME:-Titan Linux}"
  export TITAN_PRETTY_NAME
fi

# --- ¿esta shell es la que ve el usuario? ---------------------------------
# En tty1, /etc/profile.d/20-titan-scrollback.sh sustituye esta shell por una
# sesion de tmux, y la shell de dentro vuelve a leer ESTE MISMO fichero. Si las
# dos imprimieran el banner, se veria dos veces seguidas (que es lo que pasaba):
# una de la shell que va a morir y otra de la de dentro de tmux. Asi que la
# shell que va a ser sustituida no imprime nada y lo pone la de dentro, que es
# la que se ve de verdad.
#
# La condicion es la misma que la del envoltorio, a proposito: si no se va a
# sustituir (no hay tmux, o ya estamos dentro, o no es tty1), esta shell ES la
# visible y toca imprimir.
TITAN_SHELL_VISIBLE=1
if [ -z "${TMUX:-}" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ] \
   && command -v tmux >/dev/null 2>&1; then
  TITAN_SHELL_VISIBLE=0
fi
export TITAN_SHELL_VISIBLE

# --- banner ---------------------------------------------------------------
_titan_banner() {
  local cyan=$'\033[38;2;56;214;255m' blue=$'\033[38;2;79;196;255m'
  local violet=$'\033[38;2;146;150;255m' dim=$'\033[38;2;120;132;150m'
  local reset=$'\033[0m' bold=$'\033[1m'
  cat <<BANNER
${cyan}█████${reset} ${blue}█████${reset} ${cyan}█████${reset} ${violet} ██   ${reset} ${blue}█   █${reset}
${cyan}  ██${reset}   ${blue}  ██${reset}   ${cyan}  ██${reset}  ${violet}█████${reset}  ${blue}██  █${reset}
${cyan}  ██${reset}   ${blue}  ██${reset}   ${cyan}  ██${reset}  ${violet}█████${reset}  ${blue}█ █ █${reset}
${cyan}  ██${reset}   ${blue}  ██${reset}   ${cyan}  ██${reset}  ${violet}██ ██${reset}  ${blue}█  ██${reset}
${cyan}█████${reset}   ${blue}█████${reset}   ${cyan}█████${reset}  ${violet}█   █${reset}  ${blue}█   █${reset}
${dim}      L I N U X${reset}
${bold}${TITAN_PRETTY_NAME}${reset}
${dim}$(uname -sr)  |  en vivo: cambios descartados al apagar${reset}

BANNER
}

# --- prompt ---------------------------------------------------------------
# user@host:cwd $
PS1='\[\033[38;2;56;214;255m\]\u\[\033[38;2;120;132;150m\]@\[\033[38;2;79;196;255m\]\h\[\033[0m\]:\[\033[38;2;146;150;255m\]\w\[\033[0m\]\$ '
PS2='> '

# --- alias comodos -------------------------------------------------------
alias ll='ls -alhF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias lsblk='lsblk -f'
alias ping='ping -c 5'
alias please='sudo'

if [ "$TITAN_SHELL_VISIBLE" = 1 ] && [ -z "${TITAN_BANNER_IMPRESO:-}" ]; then
  # /etc/profile carga este fichero y despues ~/.bashrc lo vuelve a cargar en
  # la misma shell (para las shells que no son de login). Sin esta marca la
  # bienvenida sale dos veces seguidas. La marca se exporta para que tambien
  # la vean las shells hijas de la sesion.
  TITAN_BANNER_IMPRESO=1
  export TITAN_BANNER_IMPRESO
  _titan_banner

  # --- pista de que se puede consultar -----------------------------------
  # Las dos ultimas lineas no son decorativas. La consola de texto del kernel no
  # puede hacer scroll (la del live la dibuja fbcon, que no tiene historial; ver
  # /etc/tmux.conf), asi que la shell de tty1 corre dentro de una sesion de tmux:
  # con RePag se vuelve a leer lo que se salio de la pantalla, y con q o Esc se
  # vuelve al final, que es la ultima linea, la de abajo. La rueda del raton
  # tambien vale, y con Shift+RePag NO: el kernel se come esa tecla (por eso
  # aqui pone RePag y no Shift+RePag).
  cat <<'HINT'
    titan            resumen del sistema (fastfetch con logo de Titan)
    titan info       datos clave en formato clave=valor
    titan doctor     comprobacion de la instalacion
    titan commands   el catalogo de comandos basicos de Linux
    man <comando>    documentacion
    RePag o rueda    historial de la salida (q o Esc vuelve al final)
    Ctrl+b d         desprender la sesion sin cerrarla
HINT
fi
