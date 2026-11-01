#!/bin/bash
# ---------------------------------------------------------------------------
# Titan Linux -- tipos de uso y catalogo de aplicaciones
#
# ESTE FICHERO ES EDITABLE. El flujo del instalador es:
#
#   1. el usuario dice para que va a usar el equipo ('tipo de uso')
#   2. de ahi sale una lista de aplicaciones YA ELEGIDAS
#   3. el usuario puede anadir o quitar las que quiera antes de instalar
#
# Para cambiar lo que se ofrece, se tocan solo los dos arrays de abajo.
#
# --- TIPOS DE USO -----------------------------------------------------------
# Formato:  id | nombre | frase del menu | aplicaciones que recomienda
#
# La ultima palabra de la frase es para que se entienda de un vistazo.
USOS=(
  "ordinario|Uso diario|Navegar, correo, documentos, Multimedia y lo basico de cada dia.|firefox thunderbird gnome-disk-utility vlc codecs xournalpp ufw"
  "oficina|Oficina|Documentos, hojas de calculo, presentaciones y PDF.|libreoffice xournalpp file-roller codecs ufw"
  "desarrollo|Desarrollo|Programar, git, GitHub y contenedores.|git gh lazygit neovim code podman base-devel ufw"
  "multimedia|Musica y video|Reproducir y editar imagen, audio y video.|mpv vlc codecs gimp krita ufw"
  "creativo|Creativo|Dibujar, retocar fotos y hacer carteleria.|gimp inkscape krita codecs ufw"
  "juego|Juegos|Jugar con Store y que el equipo llegue alordable al juego.|steam gamemode codecs ufw"
  "minimal|Minimo|Nada de aplicaciones: solo el sistema y el escritorio.|ufw"
)

# Si no se marca ninguno, este es el de por defecto.
USO_POR_DEFECTO="ordinario"

# --- CATALOGO DE APLICACIONES ----------------------------------------------
# Formato:  id | nombre | lo que hace | paquete(s) | categoria | donde se ofrece
#
#   id        como se llama en el resto del instalador
#   nombre    lo que ve el usuario. NO hay que escribir "(aislado)" aqui:
#             titulo_app lo anade solo cuando el paquete viene de la tienda.
#   que_hace  una frase, sin ruido
#   paquete   lo que se pasa a pacman. Si empieza por 'flatpak:' es una app de
#             la tienda (Flathub) y se instala aislada, no como paquete del
#             sistema. Puede llevar varios paquetes separados por espacios.
#   categoria solo para ordenar el menu
#   usos      para que tipos de uso la recomiendan
#
# Los nombres de paquete se han comprobado contra la API de Arch. Ojo: AUR no
# se usa, asi que las apps que solo estan ahi (ONLYOFFICE, ungoogled-chromium,
# VS Code de Microsoft...) no se ofrecen: mejor una lista corta que instalar y
# quepa. Los grupos de pacman ('gnome', 'plasma'...) si valen y se instalan
# con su nombre.
#
# La tienda de apps (flatpak) se ofrece marcada: es la forma de instalar mas
# programas sin tocar el sistema.
CATALOGO=(
  # --- basicas ---------------------------------------------------------------
  "firefox|Firefox|Navegador dentro de una caja de arena: no puede tocar el sistema.|flatpak:org.mozilla.firefox|navegador|ordinario"
  "thunderbird|Thunderbird|Correo electronico, tambien aislado.|flatpak:org.mozilla.Thunderbird|navegador|ordinario"
  "chromium|Chromium|Navegador de los repos de Arch, integrado en el sistema.|chromium|navegador|"
  "transmission|Transmission|Descargas torrent.|transmission-gtk|navegador|ordinario"
  "vlc|VLC|Reproductor que entiende practicamente cualquier formato.|vlc|multimedia|ordinario multimedia"
  "mpv|mpv|Reproductor minimo y muy fluido, para quien no quiere mas.|mpv|multimedia|multimedia"
  "codecs|Codecs de audio y video|Los formatos que las apps no traen de serie.|gst-plugins-good gst-plugins-bad gst-plugins-ugly ffmpeg|multimedia|ordinario oficina multimedia creativo desarrollo"
  "xournalpp|Xournal++|Anotar y firmar PDF.|xournalpp|oficina|ordinario oficina"
  "file-roller|File Roller|Abrir y crear ZIP, 7z y demas.|file-roller|utilidad|oficina"
  "gnome-disk-utility|Discos|Ver el estado del disco y montar particiones sin consola.|gnome-disk-utility|utilidad|ordinario"

  # --- ofimatica ------------------------------------------------------------
  "libreoffice|LibreOffice|Writer, Calc e Impress. Trae todos los idiomas.|libreoffice-fresh|oficina|oficina"

  # --- desarrollo -----------------------------------------------------------
  "git|Git|Control de versiones, la base de todo desarrollo.|git|desarrollo|desarrollo"
  "gh|GitHub CLI|La linea de comandos de GitHub (gh).|github-cli|desarrollo|desarrollo"
  "lazygit|Lazygit|Git con interfaz grafica en la terminal, muy comoda.|lazygit|desarrollo|desarrollo"
  "neovim|Neovim|Editor de texto y de codigo.|neovim|desarrollo|desarrollo"
  "code|Visual Studio Code|Editor de codigo de Microsoft, el mas usado.|code|desarrollo|desarrollo"
  "podman|Podman|Contenedores sin necesidad de root: mas seguro que Docker.|podman podman-compose|desarrollo|desarrollo"
  "base-devel|Herramientas de compilacion|El necesario para compilar programas de Arch.|base-devel|desarrollo|desarrollo"

  # --- creativo -------------------------------------------------------------
  "gimp|GIMP|Retocar fotos y dibujar.|gimp|creativo|creativo multimedia"
  "inkscape|Inkscape|Dibujar vectores: logos, iconos, carteles.|inkscape|creativo|creativo"
  "krita|Krita|Pintura digital y ilustracion.|krita|creativo|creativo multimedia"

  # --- juegos ---------------------------------------------------------------
  "steam|Steam|La tienda de juegos de Valve. Necesita el repositorio multilib.|steam|multijuego|juego"
  "gamemode|El modo juego|Que el equipo gaste la CPU donde toca mientras juegas.|gamemode lib32-gamemode|multijuego|juego"

  # --- proteccion -----------------------------------------------------------
  "ufw|Cortafuegos|Bloquea lo que entra de fuera. Se instala, pero no se activa solo.|ufw|proteccion|ordinario oficina desarrollo multimedia creativo juego"
  "clamav|Antivirus bajo demanda|Busca malware cuando tu lo pidas.|clamav|proteccion|"
)

# --- funciones de acceso ----------------------------------------------------
#
# Todas parten la linea de la fila con campo_de_linea (lib-comun.sh), que no
# toca IFS. Con 'read -a' + IFS estos bucles se contaminaban entre si y las
# listas de apps salian a medias.

# opciones_uso -> "id:texto" para el menu de tipo de uso
opciones_uso() {
  local linea out=""
  for linea in "${USOS[@]}"; do
    out+="${linea%%|*}:$(campo_uso "${linea}" 2)  -  $(campo_uso "${linea}" 3)|"
  done
  printf '%s' "${out%|}"
}

campo_uso() { campo_de_linea "$1" "$2"; }

nombre_uso() {
  local id="$1" linea
  for linea in "${USOS[@]}"; do
    if [[ "${linea%%|*}" == "${id}" ]]; then campo_uso "${linea}" 2; return 0; fi
  done
  printf '%s' "${id}"
}

# uso_apps ID -> las apps que el tipo de uso declara en su cuarta columna. Se
# usa para ensenar la lista al usuario; lo que de verdad instala el instalador
# es app_recomendadas, que mira el catalogo.
uso_apps() {
  local id="$1" linea
  for linea in "${USOS[@]}"; do
    if [[ "${linea%%|*}" == "${id}" ]]; then campo_uso "${linea}" 4; return 0; fi
  done
  printf ''
}

# app_recomendadas "uso1 uso2 ..." -> ids de apps, sin repetir, en el orden del
# catalogo (que es el orden en que se ven en la lista).
#
# El cortafuegos (ufw) se anade siempre, va en la ultima parte de la lista: es
# la politica del proyecto que ningun equipo salga sin el preparado, y si
# dependiera solo de la sexta columna del catalogo, un uso de uso nuevo se
# quedaria sin el sin que nadie se entere.
app_recomendadas() {
  local usos="$1" app salida="" linea donde uso
  for linea in "${CATALOGO[@]}"; do
    app="${linea%%|*}"
    donde="$(campo_de_linea "${linea}" 6)"
    for uso in ${usos}; do
      if [[ " ${donde} " == *" ${uso} "* ]]; then
        salida+="${app} "
        break
      fi
    done
  done
  if [[ " ${salida}" == *" ufw "* ]]; then
    salida="${salida% }"
  else
    salida="${salida:+${salida} }ufw"
  fi
  printf '%s' "${salida% }"
}

# app_datos ID -> "nombre|que_hace|paquete|categoria"
app_datos() {
  local id="$1" linea
  for linea in "${CATALOGO[@]}"; do
    if [[ "${linea%%|*}" == "${id}" ]]; then
      printf '%s|%s|%s|%s' "$(campo_de_linea "${linea}" 2)" "$(campo_de_linea "${linea}" 3)" \
                           "$(campo_de_linea "${linea}" 4)" "$(campo_de_linea "${linea}" 5)"
      return 0
    fi
  done
  return 1
}

# opciones_app -> "id:texto" ordenado por categoria, para el checklist. El
# orden de las categorias es el de esta lista.
opciones_app() {
  local out="" cat_actual="" linea id
  for cat_actual in navegador oficina desarrollo multimedia creativo multijuego utilidad proteccion; do
    for linea in "${CATALOGO[@]}"; do
      [[ "$(campo_de_linea "${linea}" 5)" == "${cat_actual}" ]] || continue
      id="${linea%%|*}"
      out+="${id}:$(titulo_app "${id}")  -  $(campo_de_linea "${linea}" 3)|"
    done
  done
  printf '%s' "${out%|}"
}

# titulo_app ID -> "nombre (aislado)" si viene de la tienda de apps
titulo_app() {
  local id="$1" nombre paquete
  nombre="$(campo_de_linea "$(linea_app "${id}")" 2)"
  paquete="$(paquete_app "${id}")"
  if [[ "${paquete}" == flatpak:* ]]; then
    printf '%s (aislado)' "${nombre}"
  else
    printf '%s' "${nombre}"
  fi
}

# linea_app ID -> la fila entera del catalogo (o vacio si no existe)
linea_app() {
  local id="$1" linea
  for linea in "${CATALOGO[@]}"; do
    [[ "${linea%%|*}" == "${id}" ]] && { printf '%s' "${linea}"; return 0; }
  done
  return 1
}

# paquete_app ID -> el campo de paquete tal cual ("flatpak:org.mozilla.firefox"
# si viene de la tienda, o los paquetes separados por espacios)
paquete_app() { campo_de_linea "$(linea_app "$1")" 4; }

# field_app ID N -> campo N del catalogo (1=id, 2=nombre, 3=que_hace,
# 4=paquete, 5=categoria, 6=usos que la recomiendan)
field_app() { campo_de_linea "$(linea_app "$1")" "$2"; }
