#!/bin/bash
# ---------------------------------------------------------------------------
# Titan Linux -- perfiles de escritorio
#
# ESTE FICHERO ES EDITABLE: para anadir un escritorio, o quitar uno, basta con
# anadir o borrar una linea de ESCRITORIOS. No hay que tocar nada mas del
# instalador.
#
# Formato de cada linea, separado por '|':
#
#   id | nombre | frase del menu | paquetes | gestor de sesion | grafico | visor de PDF | espacio minimo
#   |          |                |          |                   |         |              |
#   id          como se llama en el resto del instalador (sin espacios)
#   nombre      lo que ve el usuario en el menu
#   frase       cuando conviene elegirlo, en una linea
#   paquetes    los que se pasan a pacstrap
#   gestor      quien muestra la pantalla de entrada al arrancar
#   grafico     'si' si es grafico, 'no' si es solo consola
#   visor       visor de PDF que encaja con ese escritorio
#   espacio     tamano minimo en GiB, solo para avisar si el disco da
#
# Si un escritorio usa greetd hace falta seatd en sus paquetes.
#
# OJO con los nombres: Arch ha convertido los meta-paquetes de grupos en
# GRUPOS de pacman. 'gnome', 'plasma', 'i3', 'xfce4' y 'xfce4-goodies' ya no son
# paquetes, son grupos, pero se instalan igual de bien ('pacman -S gnome'
# instala el grupo entero). Los nombres que aparecen mas abajo se han
# comprobado contra la API de paquetes de Arch; uno mal escrito hace que
# pacstrap falle a mitad de la instalacion, con el disco ya partido.
# ---------------------------------------------------------------------------

ESCRITORIOS=(
  "gnome|GNOME|Completo y sin sorpresas: menus claros y todo funciona. El mas recomendado.|gnome|gdm|si|evince|12"
  "kde|KDE Plasma|Muy personalizable y con muchos programas. Algo mas pesado que GNOME.|plasma plasma-nano|sddm|si|okular|14"
  "niri|niri|Teclado, raton y panel, muy fluido y aligerito. Para quien trabaja con el teclado.|niri waybar fuzzel mako swaybg xdg-desktop-portal-gnome xdg-desktop-portal-wlr wl-clipboard pipewire wireplumber seatd greetd greetd-tuigreet|greetd|si|evince|6"
  "hyprland|Hyprland|Como niri pero con animaciones. Muy bonito, pide algo mas de GPU.|hyprland waybar fuzzel mako swaybg xdg-desktop-portal-gnome xdg-desktop-portal-wlr wl-clipboard pipewire wireplumber seatd greetd greetd-tuigreet|greetd|si|evince|6"
  "sway|Sway|Escritorio en mosaico, muy estable y sin adornos. Un clasico.|sway swaybg swaylock waybar fuzzel mako xdg-desktop-portal-gnome xdg-desktop-portal-wlr wl-clipboard pipewire wireplumber seatd greetd greetd-tuigreet|greetd|si|evince|6"
  "i3|i3 (X11)|El mas ligero de todos. Arranca en cualquier equipo, aunque sea viejo.|i3 i3lock i3status dmenu xterm xorg-server xorg-xinit|i3|si|evince|5"
  "xfce|XFCE|Ligero y con el aspecto de escritorio de toda la vida.|xfce4 xfce4-goodies|lightdm|si|evince|7"
  "cinnamon|Cinnamon|Ligero y con el aspecto clasico de Linux.|cinnamon nemo cinnamon-menus|lightdm|si|evince|8"
  "ninguno|Solo terminal|Nada de escritorio: consola, 'titan' y 'fastfetch'. Lo que mas rapido arranca.|ninguno|ninguno|no|ninguno|2"
)

# El que sale marcado en el menu. Se cambia en esta sola linea.
ESCRITORIO_POR_DEFECTO="gnome"

# --- acceso a los campos -----------------------------------------------------

# campo LINEA N  -> el campo N (1..) separado por '|'
# El trabajo de verdad lo hace campo_de_linea (en lib-comun.sh), que no toca IFS.
campo() { campo_de_linea "$1" "$2"; }

escritorio_por_defecto() { printf '%s' "${ESCRITORIO_POR_DEFECTO}"; }

# opciones_escritorio -> "id:texto|id:texto" para dialog --menu
opciones_escritorio() {
  local linea out=""
  for linea in "${ESCRITORIOS[@]}"; do
    out+="${linea%%|*}:$(campo "${linea}" 2)  -  $(campo "${linea}" 3)|"
  done
  printf '%s' "${out%|}"
}

# datos_escritorio ID -> "paquetes|gestor|grafico|visor|espacio"
datos_escritorio() {
  local id="$1" linea
  for linea in "${ESCRITORIOS[@]}"; do
    if [[ "${linea%%|*}" == "${id}" ]]; then
      printf '%s|%s|%s|%s|%s' "$(campo "${linea}" 4)" "$(campo "${linea}" 5)" \
                            "$(campo "${linea}" 6)" "$(campo "${linea}" 7)" "$(campo "${linea}" 8)"
      return 0
    fi
  done
  return 1
}

nombre_escritorio() {
  local id="$1" linea
  for linea in "${ESCRITORIOS[@]}"; do
    if [[ "${linea%%|*}" == "${id}" ]]; then campo "${linea}" 2; return 0; fi
  done
  printf '%s' "${id}"
}

# El terminal grafico del sistema. Decision del proyecto: kitty siempre que haya
# escritorio grafico, porque es el que mejor se lleva con el estilo del resto.
# Para i3, que ya trae alacritty y dmenu en su lista, se respeta lo suyo.
terminal_escritorio() {
  local id="$1" grafico
  grafico="$(datos_escritorio "${id}" | cut -d'|' -f3)"
  [[ "${grafico}" == "no" ]] && { printf ''; return 0; }
  printf 'kitty'
}

# Lo que necesita cualquier escritorio grafico para funcionar como la gente
# espera: sonido, microfono, gestor de ficheros, acceso a las unidades del
# movil y descompresores.
complementos_escritorio() {
  local id="$1" grafico
  grafico="$(datos_escritorio "${id}" | cut -d'|' -f3)"
  [[ "${grafico}" == "no" ]] && return 0
  case "${id}" in
    kde) printf 'pipewire wireplumber pipewire-pulse plasma-workspace dolphin gvfs gvfs-mtp file-roller' ;;
    *)   printf 'pipewire wireplumber pipewire-pulse gvfs gvfs-mtp file-roller' ;;
  esac
}
