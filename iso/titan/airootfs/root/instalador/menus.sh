#!/bin/bash
# ---------------------------------------------------------------------------
# Titan Linux -- las pantallas del instalador
#
# El orden de las pantallas es este, y es el que sigue el usuario de arriba
# abajo. Las que se pueden saltar (en modo autopilot, o pulsando Esc) tienen su
# valor por defecto escrito justo al lado.
#
#   1. bienvenida
#   2. red              (esta la llama paso-red.sh, porque puede ser un bucle)
#   3. tipo de uso       <- de aqui sale la lista de apps
#   4. escritorio
#   5. aplicaciones      (las del tipo de uso, ya marcadas; se pueden cambiar)
#   6. disco             (esta la llama paso-disco.sh)
#   7. cuentas
#   8. arranque
#   9. resumen y confirmacion
#
# ---------------------------------------------------------------------------

menu_bienvenida() {
  if [[ "${AUTO}" == "1" ]]; then info "[autopiloto] bienvenida saltada"; return 0; fi
  ventana --title "Titan Linux" --backtitle "Instalador" \
    --msgbox "
  ${C_TITULO}Titan Linux${C_RESET}

  Vas a instalar Titan Linux en este equipo.

  Necesitas internet: de ahi se descarga el sistema, el escritorio y las
  aplicaciones que elijas. El live va en memoria, asi que esto no toca nada
  del disco hasta que lo confirmes mas abajo.

  ${C_GRIS}Consejo: si el equipo tiene menos de 8 GB de RAM, elige un
  escritorio ligero (niri, Sway o 'solo terminal').${C_RESET}" 20 70
  # Sin este 'return 0', la funcion devuelve el codigo de la ventana, y el
  # instalador (que va con 'set -e') se muere si el usuario pulsa Esc.
  return 0
}

# --- 3. tipo de uso ---------------------------------------------------------
# Esta es la pantalla que decide que se instala. En vez de una lista enorme de
# programas, se pregunta para que va a servir el equipo y se ofrecen las
# aplicaciones de ese uso ya elegidas. Luego el usuario puede quitar o anadir
# lo que quiera en la pantalla siguiente.
menu_tipo_uso() {
  preguntar_multiple "usos" "Para que lo vas a usar" \
"Marca para que vas a usar Titan Linux.

Con eso ya tenemos la lista de programas. En la siguiente pantalla podras
quitar o anadir los que quieras." \
    "$(opciones_uso)" "${E[tipos_uso]:-${USO_POR_DEFECTO}}"

  if [[ -z "${E[usos]}" ]]; then
    E[usos]="${USO_POR_DEFECTO}"
    info "sin tipos de uso marcados: se usa '${USO_POR_DEFECTO}'"
  fi
  E[tipos_uso]="${E[usos]}"
  E[apps]="$(app_recomendadas "${E[usos]}")"
  guardar_estado
}

# --- 4. escritorio ----------------------------------------------------------

menu_escritorio() {
  preguntar_lista "escritorio" "Escritorio" \
"¿Que escritorio quieres?

Es lo que ves al iniciar sesion. Todo lo demas (archivos, navegador,
programas) funciona igual con cualquiera de ellos." \
    "$(opciones_escritorio)" 24 "$(escritorio_por_defecto)"
  E[escritorio]="${E[escritorio]:-$(escritorio_por_defecto)}"
  guardar_estado
}

# --- 5. aplicaciones --------------------------------------------------------

menu_apps() {
  local titulo_apps
  titulo_apps="$(apps_titulo "${E[usos]}")"
  preguntar_multiple "apps" "Aplicaciones" \
"Estas son las aplicaciones para '${titulo_apps}'.

SPACE marca o quita. Las que vienen marcadas son las tipicas de ese uso.
Tambien puedes anadir las de los demas usos, o quitar lo que no uses: la
tienda de apps (flatpak) viene marcada porque es la forma de instalar mas
programas sin tocar el sistema." \
    "$(opciones_app)" "${E[apps]}"

  if [[ -z "${E[apps]}" ]]; then
    E[apps]="${E[apps_recomendadas]:-}"
    info "sin apps marcadas: se instala solo el sistema"
  fi
  guardar_estado
}

apps_titulo() {
  local usos="$1" id out=""
  for id in ${usos}; do out+="$(nombre_uso "${id}") "; done
  printf '%s' "${out% }"
}

# --- 7. cuentas -------------------------------------------------------------

elegir_zona() {
  # OJO con el ':-' y con 'set -u'. 'zona' no es una clave del fichero de
  # respuestas (ahi va 'zona_horaria', y 'zona' se calcula a partir de ella), asi
  # que en la primera llamada la clave NO existe. Y con 'set -u', leer un
  # elemento que no existe de un array asociativo para el shell: "E[zona]:
  # unbound variable". Como esta linea es la PRIMERA de la funcion y el
  # instalador va con 'set -euo pipefail', el instalador se moria ahi, en
  # silencio y con codigo 1, a mitad de las preguntas.
  if [[ -n "${E[zona]:-}" ]]; then return 0; fi
  local opciones="Europe/Madrid:Europa (Madrid)|Europe/Lisbon:Europa (Lisboa)|Europe/London:Europa (Londres)|Europe/Paris:Europa (Paris)|America/Mexico_City:America (Ciudad de Mexico)|America/Bogota:America (Bogota)|America/Lima:America (Lima)|America/Santiago:America (Santiago)|America/Argentina/Buenos_Aires:America (Buenos Aires)|America/New_York:America (Nueva York)|America/Los_Angeles:America (Los Angeles)|otra:Otra (elegir en la lista del sistema)"
  preguntar_lista "zona_horaria" "Zona horaria" "¿Que hora es donde estas?" "${opciones}" 20 "Europe/Madrid"
  if [[ "${E[zona_horaria]}" == "otra" ]]; then
    if [[ "${AUTO}" == "1" ]]; then E[zona]="Europe/Madrid"; return 0; fi
    titulo "Zona horaria"
    tzselect || true
    E[zona]="$(readlink -f /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')"
    [[ -n "${E[zona]}" ]] || E[zona]="Europe/Madrid"
  else
    E[zona]="${E[zona_horaria]}"
  fi
}

menu_cuentas() {
  preguntar_texto "hostname" "Nombre del equipo" \
"Nombre del equipo. Es como aparecera en la red y en la terminal:" "titan"
  E[hostname]="${E[hostname]:-titan}"

  elegir_zona

  preguntar_lista "locale" "Idioma" \
"¿En que idioma quieres el sistema?

Los mensajes de los programas saldran en ese idioma. Los archivos que
crees tu, en el que tu decidas." \
    "es_ES.UTF-8:espanol (Espana)|ca_ES.UTF-8:catalan|gl_ES.UTF-8:gallego|en_US.UTF-8:ingles (Estados Unidos)|pt_PT.UTF-8:portugues (Portugal)|C.UTF-8:sin traducir (ingles)" 18 "es_ES.UTF-8"
  E[locale]="${E[locale]:-es_ES.UTF-8}"

  preguntar_lista "teclado" "Teclado" \
"¿Que teclado tienes?

Se usa tanto en la consola como en el escritorio, para que se escriban
bien las tildes y la enye." \
    "es:espanol|es_dvorak:espanol (Dvorak)|us:ingles (Estados Unidos)|gb:ingles (Reino Unido)|de:aleman|fr:frances|pt:portugues" 16 "es"
  case "${E[teclado]}" in
    es)     E[keymap]="es";     E[teclado_grafico]="es" ;;
    es_dvorak) E[keymap]="es-dvorak"; E[teclado_grafico]="es" ;;
    *)      E[keymap]="${E[teclado]}"; E[teclado_grafico]="${E[teclado]}" ;;
  esac

  # Usuario. Un nombre de usuario de verdad: sin espacios, en minusculas y
  # empezando por letra, que es lo que luego admiten los servicios.
  while :; do
    preguntar_texto "usuario" "Usuario" \
"Nombre del usuario que vas a usar a diario.

En minusculas, sin espacios. Este usuario puede instalar programas con
sudo." "titan"
    if [[ "${E[usuario]}" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then break; fi
    menu_error "Nombre no valido" \
"El nombre '${E[usuario]}' no vale.

Empieza por una letra, y solo minusculas, numeros, guion y guion bajo."
    E[usuario]="titan"
  done

  # Contrasena del usuario: dos veces, y se comprueba que coinciden.
  #
  # En autopilot el bucle se pide a si mismo lo mismo para siempre: no hay
  # nadie delante para corregirlo y el 'while' no se acaba nunca. Ahi, en vez
  # de repetir, se sale con un error que dice que falta que, que es lo que
  # hace falta para que la comprobacion automatica se pare y se pueda arreglar.
  while :; do
    preguntar_password "clave" "Contrasena" \
"Escribe la contrasena de ${E[usuario]}.

Minimo 6 caracteres. No se puede recuperar si se olvida."
    preguntar_password "clave2" "Contrasena" "Escribela otra vez para confirmar:"
    if [[ "${E[clave]}" == "${E[clave2]}" && ${#E[clave]} -ge 6 ]]; then break; fi
    if [[ "${AUTO}" == "1" ]]; then
      sale 2 "Las contrasenas del fichero de respuestas no valen.

'clave' y 'clave2' tienen que ser iguales y de 6 caracteres o mas. Sin
comillas para que el valor no lleve comillas dentro."
    fi
    menu_error "No coinciden" "Las dos contrasenas no son iguales, o son demasiado cortas. Minimo 6 caracteres."
    E[clave]=""; E[clave2]=""
  done

  # root SI existe en el sistema instalado. Se ofrece usar la misma contrasena
  # que el usuario, que es lo mas comodo, o poner otra.
  if [[ "${AUTO}" == "1" ]]; then
    E[clave_root]="${E[clave_root]:-${E[clave]}}"
  else
    local quien
    # Ojo: las opciones van SOLO como pares tag/item. Puestas tambien dentro del
    # texto salen duplicadas en pantalla (una como texto y otra como lista), y
    # con 'root sin contrasena' de oferta da bastante mas pena de la que da.
    quien="$(ventana --title "Contrasena de root" --backtitle "Titan Linux  -  Instalador" \
      --menu "El administrador del sistema (root) tambien tiene contrasena.

Si algo se rompe, con esta contrasena se arregla desde una consola." 12 70 3 \
        "misma" "usar la misma que ${E[usuario]}" \
        "otra" "poner una distinta" \
        "ninguna" "dejar root sin contrasena" 3>&1 1>&2 2>&3)" || quien="misma"
    case "${quien}" in
      otra)
        while :; do
          preguntar_password "clave_root" "root" "Contrasena de root:"
          preguntar_password "clave_root2" "root" "Escribela otra vez:"
          if [[ "${E[clave_root]}" == "${E[clave_root2]}" && ${#E[clave_root]} -ge 6 ]]; then break; fi
          if [[ "${AUTO}" == "1" ]]; then
            sale 2 "'clave_root' y 'clave_root2' tienen que ser iguales y de 6 caracteres o mas."
          fi
          menu_error "No coinciden" "Las dos contrasenas no son iguales, o son demasiado cortas."
          E[clave_root]=""; E[clave_root2]=""
        done
        ;;
      ninguna) E[clave_root]="" ;;
      *) E[clave_root]="${E[clave]}" ;;
    esac
  fi

  preguntar_si "bluetooth" "Bluetooth" \
"¿Quieres que funcione el bluetooth?

Se usa para los auriculares, el teclado y el raton inalambricos." "si"
  guardar_estado
  return 0
}

# --- 8. arranque ------------------------------------------------------------

menu_arranque() {
  # Decision ya cerrada con el usuario: GRUB, por compatibilidad. Se explica
  # por que se elige en lugar de systemd-boot, y se da la opcion de no
  # instalarlo (equipo que ya arranca con otro cargador).
  E[arranque]="grub"
  if [[ "${AUTO}" == "1" ]]; then info "[autopiloto] arranque = grub"; return 0; fi
  ventana --title "Arranque" --backtitle "Titan Linux  -  Instalador" --msgbox "
Va a instalarse GRUB, el arrancador.

Es el que mas maquinas entiende (Linux, Windows, otros sistemas), y es el
que usa Titan Linux en su ISO en vivo.

  ${C_GRIS}Si este equipo ya arranca con otro cargador y quieres
  conservarlo, dilo al salir de la instalacion y no se tocara.$C_RESET}" 15 70
  return 0
}

# --- 9. resumen -------------------------------------------------------------

menu_resumen() {
  # La lista de flatpak se guarda AQUI, en este shell, no dentro de un $( ):
  # dentro de una subshell la asignacion se pierde al terminar, y el resumen
  # diria 'sin flatpak' justo cuando si lo hay, que es cuando mas engaña.
  E[flatpaks]="$(flatpaks_elegidos)"
  # Y los paquetes se cuentan aqui (no en el paso de instalar) para que el
  # resumen diga la cifra real antes de que empiece a descargar. 'wc -w' y no
  # 'wc -l' porque paquetes_instalar los escupe todos en una sola linea.
  E[total_paquetes]="$(paquetes_instalar | wc -w)"

  local d gestor grafico
  d="$(datos_escritorio "${E[escritorio]}")"
  # Las cinco columnas, todas con nombre: si la ultima se deja como '_', se
  # lleva el resto de la linea y 'grafico' acaba valiendo 'si|evince|12', con
  # lo que el resumen diria 'solo consola' para un escritorio grafico.
  local paquetes gestor2 visor espacio
  IFS='|' read -r paquetes gestor2 grafico visor espacio <<<"${d}"
  # El modo de arranque lo detecta el particionado (/sys/firmware/efi), asi que
  # todavia no se sabe. Aqui no se decide: solo se enseña lo que habra.
  local como_arranca="UEFI"
  [[ "${E[modo_arranque]:-0}" == "1" ]] || como_arranca="BIOS"
  # El cortafuegos: E[ufw] solo se rellena al FINAL de la instalacion, asi que
  # aqui se mira si esta en la lista de apps, que es lo que hay a mano.
  local cortafuegos="sin cortafuegos"
  [[ " ${E[apps]:-}" == *" ufw "* ]] && \
    cortafuegos="instalado, pero NO activado (la pantalla final lo explica)"
  # OJO con los ':-' de toda la pantalla. 'cifrado' y 'total_paquetes' los
  # rellenan el particionado y la lista de apps, y esta pantalla solo ENSEÑA
  # cosas: si le falta alguna, lo correcto es que se enseñe en blanco, no que
  # el instalador se muera. Y se moria: con 'set -u', un '${E[cifrado]}' sin
  # valor es un error que para el instalador entero, sin decir nada, y justo en
  # la ultima pantalla antes de empezar a instalar (con el disco ya
  # particionado, que es lo peor que puede pasar).
  local lineas="Resumen de la instalacion
===================================================================

  Equipo      ${E[hostname]:-}    Usuario ${E[usuario]:-}
  Idioma      ${E[locale]:-}      Teclado ${E[teclado]:-}
  Hora        ${E[zona]:-}

  Disco       ${E[disco]:-}
  Archivos    ${E[fs]:-}$( [[ "${E[swap]:-}" == "zram" ]] && echo ", swap en la memoria" )
  Cifrado     ${E[cifrado]:-}
  Arranque    ${como_arranca} con ${E[arranque]:-}

  Escritorio  $(nombre_escritorio "${E[escritorio]:-}")
              $( [[ "${grafico}" == "si" ]] && echo "con terminal kitty" || echo "solo consola" )

  Uso         $(apps_titulo "${E[usos]:-}")

  Aplicaciones
$(lista_apps_resumen)

  Paquetes    ${E[total_paquetes]:-0} en total
  Cortafuegos ${cortafuegos}
  Tienda      $( [[ -n "${E[flatpaks]:-}" ]] && echo "flatpak: ${E[flatpaks]}" || echo "sin flatpak" )

===================================================================

  ${C_AVISO}Se va a BORRAR ${E[disco]:-} entero.${C_RESET}
  ${C_GRIS}Log de la instalacion: ${LOG}${C_RESET}"

  if [[ "${AUTO}" == "1" ]]; then
    info "[autopiloto] resumen aceptado"
    return 0
  fi
  # El TIPO de ventana va antes que las opciones de los botones, y sin el
  # '--yesno' dialog no abre nada: se limita a imprimir su ayuda y sale con
  # codigo 0, o sea que el instalador seguiria como si el usuario hubiera
  # dicho que si. Es el fallo mas caro que puede tener este fichero.
  #
  # El boton de cancelar no vuelve atras: el resumen es el final del recorrido
  # de preguntas y no hay a donde volver. Lo que hace es salir sin instalar, y
  # el disco intacto.
  # El codigo se guarda en una variable en vez de leer el '$?' justo despues:
  # el 'set -e' del instalador no perdona una llamada cuyo codigo no se mira, y
  # ademas asi se lee de donde se decide.
  local codigo=0
  # Las opciones, antes del '--yesno': dialog deja de leerlas en cuanto ve el
  # tipo de ventana, y si van detras las ignora sin decir nada (se ve con
  # 'dialog --yesno t 12 50 --defaultno --yes-label X': pinta < Yes > < No > y
  # se queja por la salida de error, que aqui no se ve). Con el orden bueno la
  # ventana sale con <Instalar> y <Cancelar>, y marcada la de cancelar.
  ventana --title "Todo listo" --backtitle "Titan Linux  -  Instalador" \
    --defaultno --yes-label "Instalar" --no-label "Cancelar" \
    --yesno "${lineas}" 26 76 || codigo=$?
  # 0 = instalar. 1 = el boton de cancelar. 255 = Esc.
  [[ "${codigo}" -eq 0 ]] && return 0
  return 3
}

lista_apps_resumen() {
  local app nombre total=0
  if [[ -z "${E[apps]}" ]]; then
    printf '    (ninguna)\n'
    return 0
  fi
  local salida=""
  for app in ${E[apps]}; do
    nombre="$(field_app "${app}" 1 2>/dev/null)" || continue
    salida+="    - ${nombre}\n"
    total=$(( total + 1 ))
  done
  printf '%s' "${salida}"
  printf '    %s en total\n' "${total}"
}
