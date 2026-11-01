#!/bin/bash
# ---------------------------------------------------------------------------
# Titan Linux -- paso 1: conexion a internet
#
# El instalador NECESITA internet: los paquetes del escritorio y de las
# aplicaciones se descargan de los repos de Arch. Por eso esto va el primero,
# antes de tocar el disco: si se parte la conexion a mitad de una instalacion,
# no hay red de donde sacar los paquetes.
#
# El live usa systemd-networkd (no NetworkManager), asi que aqui no hay nmcli.
# Lo que se intenta, por orden:
#   1. ver si ya hay conexion (DHCP suele ser automatico en una VM)
#   2. reanimar cada interfaz con 'networkctl reconfigure'
#   3. si hay wifi, preguntar la red y la clave y usar wpa_supplicant
#   4. si es cable, ofrecer direccion IP a mano
# ---------------------------------------------------------------------------

RED_PROBADA=0

# --- comprobacion -----------------------------------------------------------

# prueba_https URL SEGUNDOS -> 0 si hay respuesta
prueba_https() {
  curl -sSf --connect-timeout 4 --max-time "${2:-8}" -o /dev/null "$1" 2>/dev/null
}

red_hay_internet() {
  # Sin DNS no hay instalacion: pacman no resuelve ni un solo nombre de
  # repositorio. Asi que aqui NO se acepta 'hay salida pero el DNS no funciona'.
  # Antes se probaba tambien una IP suelta (1.1.1.1) y, si respondia, se daba
  # la instalacion por buena: era un error, porque lo que fallaba era el DNS y
  # el error se-see al usuario veinte minutos despues, ya con el disco
  # particionado, cuando pacman no encontraba los paquetes. Lo que si se hace
  # es avisar del motivo (ver 'red_diagnostico'), que es lo que de verdad ayuda.
  getent hosts archlinux.org >/dev/null 2>&1 || return 1
  if   prueba_https "https://geo.mirror.pkgbuild.com/" 10; then return 0; fi
  if   prueba_https "https://archlinux.org/" 10; then return 0; fi
  return 1
}

# Hay salida a internet aunque el DNS no funcione. Solo sirve para DIAGNOSTICO:
# avisa de que el problema es el DNS y no el cable. La peticion va por http a
# proposito: con https, curl rechazaria el certificado de 1.1.1.1 (es autofirma)
# y la prueba fallaria siempre, cambiando el sintoma por el contrario.
red_hay_salida_sin_dns() {
  curl -sS --connect-timeout 4 --max-time 8 -o /dev/null "http://1.1.1.1/" 2>/dev/null
}

# Descripcion de lo que hay, para explicarle al usuario que ocurre.
red_diagnostico() {
  local texto="" iface direccion
  while read -r iface; do
    [[ "${iface}" == "lo" ]] && continue
    # Con 'ip -br' el estado de la interfaz va en la TERCERA columna
    # ('2: eth0 UP 192.168.1.5/24'), asi que cogiendola a mano se enseña 'UP'
    # en vez de la direccion. El formato '-o' (una linea por direccion) si es
    # estable, y la direccion es el cuarto campo.
    direccion="$(ip -4 -o addr show dev "${iface}" 2>/dev/null | awk '{print $4}' | paste -sd' ' -)"
    texto+="  ${iface}: ${direccion:-sin direccion}"
    [[ "$(cat "/sys/class/net/${iface}/carrier" 2>/dev/null)" == "1" ]] \
      && texto+=" (con cable)" || texto+=" (sin cable)"
    texto+=$'\n'
  done < <(ls /sys/class/net | grep -v '^lo$')
  # El caso que mas confunde: hay cable y hay salida, pero el DNS no resuelve.
  if red_hay_salida_sin_dns; then
    texto+="  Hay salida a internet, pero los nombres no se resuelven:"$'\n'
    texto+="  el problema es el DNS, no la conexion. Se arregla en la"$'n'
    texto+="  config del router, o poniendo las direcciones a mano en"$'n'
    texto+="  /etc/systemd/resolved.conf del live."$'\n'
  fi
  printf '%s' "${texto:-  (no hay ninguna interfaz de red)}"
}

red_mostrar_interfaces() {
  local iface tipo estado
  while read -r iface; do
    [[ "${iface}" == "lo" ]] && continue
    if   [[ -d "/sys/class/net/${iface}/wireless" ]]; then tipo="wifi"
    elif [[ -d "/sys/class/net/${iface}/bridge" ]]; then tipo="puente"
    else tipo="cable"; fi
    estado="$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null)"
    printf '%s|%s|%s\n' "${iface}" "${tipo}" "${estado}"
  done < <(ls /sys/class/net)
}

# --- dar vida a la red ------------------------------------------------------

red_reanimar() {
  local cambiada=0 iface
  while read -r iface; do
    [[ "${iface}" == "lo" ]] && continue
    info "reactivando ${iface}"
    networkctl reconfigure "${iface}" 2>/dev/null || true
    cambiada=1
  done < <(ls /sys/class/net | grep -v '^lo$')
  (( cambiada )) || return 1
  # El DHCP tarda un par de segundos. Se reintenta un poco antes de rendirse.
  local i
  for i in 1 2 3 4 5 6; do
    sleep 3
    if red_hay_internet; then
      info "conexion establecida en el intento ${i}"
      return 0
    fi
  done
  return 1
}

# --- wifi -------------------------------------------------------------------

red_wifi_lista() {
  local iface
  for iface in /sys/class/net/*/wireless; do
    [[ -d "${iface}" ]] || continue
    iface="${iface%/wireless}"; iface="${iface##*/}"
    # 'SSID:' a secas es una red oculta, que no se puede elegir todavia: se
    # quita, porque en el menu aparece como una linea en blanco que parece un
    # fallo.
    iw dev "${iface}" scan 2>/dev/null |
      awk '/^SSID:/ {sub(/^SSID:[ \t]*/, ""); if (length) print}' | sort -u
    return 0
  done
  return 1
}

red_conectar_wifi() {
  command -v iw >/dev/null 2>&1 || return 1
  command -v wpa_supplicant >/dev/null 2>&1 || return 1
  local iface=""
  for iface in /sys/class/net/*/wireless; do
    [[ -d "${iface}" ]] || continue
    iface="${iface%/wireless}"; iface="${iface##*/}"
    break
  done
  [[ -n "${iface}" ]] || return 1
  info "conectando por wifi en ${iface}"
  local ssid clave
  # El menu se construye con NUMEROS, no con el nombre de la red, porque el
  # separador de las opciones es '|' y el de id:texto es ':', y los nombres de
  # red pueden llevar cualquiera de los dos: una red que se llama 'Casa:5G'
  # partia el menu por la mitad y ensenaba la red como 'Casa'.
  # Los '|' del nombre se cambian por espacios, que es lo unico que hay que
  # tocar para que la linea se pueda enseñar.
  local -a ssids=()
  local -a opciones=()
  local i
  while IFS= read -r ssid; do
    [[ -n "${ssid}" ]] || continue
    ssids+=("${ssid}")
    opciones+=("$(( ${#ssids[@]} )):${ssid//|/ }")
  done < <(red_wifi_lista)
  if (( ${#ssids[@]} == 0 )); then
    menu_error "Sin redes wifi" \
      "La tarjeta ${iface} no ha encontrado ninguna red.
Puede que la antena este apagada con el interruptor del portatil o que
esteis lejos del router.

Si es un portatil, prueba a encender la wifi con la tecla o el interruptor
Fn+una de las de funcion, y vuelve a intentarlo."
    return 1
  fi
  preguntar_lista "ssid_num" "Wifi" "¿A que red te conectas?" \
    "$(printf '%s\n' "${opciones[@]}" | paste -sd'|' -)" 20 "1"
  i="${E[ssid_num]}"
  if [[ ! "${i}" =~ ^[0-9]+$ ]] || (( i < 1 || i > ${#ssids[@]} )); then
    error "opcion de wifi no valida: ${i}"
    return 1
  fi
  ssid="${ssids[$(( i - 1 ))]}"
  preguntar_password "clave_wifi" "Wifi" "Clave de '${ssid}' (dejala vacia si la red es abierta):"
  clave="${E[clave_wifi]}"
  local conf="/run/titan-wpa.conf"
  {
    printf 'ctrl_interface=DIR=/run/wpa_supplicant GROUP=wheel\n'
    printf 'update_config=1\nnetwork={\n  ssid="%s"\n' "${ssid}"
    if [[ -n "${clave}" ]]; then
      # La clave se pone entre comillas dobles. Un nombre de red o una clave
      # con comillas o barras de atras dentro romperian el fichero y
      # wpa_supplicant no arrancaria sin decir por que.
      printf '  psk="%s"\n' "${clave//\"/\\\"}"
    else
      printf '  key_mgmt=NONE\n'
    fi
    printf '}\n'
  } >"${conf}"
  chmod 0600 "${conf}"
  wpa_supplicant -B -i "${iface}" -c "${conf}" >/dev/null 2>&1 || {
    aviso "wpa_supplicant no arranco; revisa la clave"
    return 1
  }
  networkctl reconfigure "${iface}" 2>/dev/null || true
  local intento
  for intento in 1 2 3 4 5 6 7 8; do
    sleep 3
    if red_hay_internet; then
      info "wifi conectada a '${ssid}'"
      return 0
    fi
  done
  return 1
}

# --- cable a mano -----------------------------------------------------------

red_conectar_cable() {
  # Antes de preguntar nada, que haya de verdad una interfaz de cable. Sin
  # esto se le piden la IP y la mascara a alguien que tiene la wifi apagada, y
  # el error le dice que revise la mascara.
  local candidatas=() iface
  for iface in /sys/class/net/*; do
    iface="${iface##*/}"
    [[ "${iface}" == "lo" ]] && continue
    [[ -d "/sys/class/net/${iface}/wireless" ]] && continue
    candidatas+=("${iface}")
  done
  if (( ${#candidatas[@]} == 0 )); then
    menu_error "No hay interfaz de cable" \
"No se ha encontrado ningun puerto de red con cable.
Se ven estos dispositivos: $(ls /sys/class/net | grep -v '^lo$' | paste -sd' ' -)

En una maquina virtual, mira que tenga un adaptador de red conectado."
    return 1
  fi

  preguntar_texto "ip_manual" "Red por cable" \
    "Direccion IP de este equipo (por ejemplo 192.168.1.50):" ""
  local ip="${E[ip_manual]}"
  if ! [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
     ! IFS=. read -r o1 o2 o3 o4 <<<"${ip}" ||
     (( o1 > 255 || o2 > 255 || o3 > 255 || o4 > 255 )); then
    menu_error "Direccion IP no valida" \
"El formato de una direccion IPv4 es cuatro numeros separados por puntos,
por ejemplo 192.168.1.50.

Has escrito: ${ip:-(nada)}"
    return 1
  fi
  preguntar_texto "mascara_manual" "Red por cable" "Mascara de subred (255.255.255.0):" "255.255.255.0"
  preguntar_texto "puerta_manual" "Red por cable" "Puerta de enlace (la del router):" ""
  local mascara="${E[mascara_manual]}" puerta="${E[puerta_manual]}"
  if ! [[ "${mascara}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    menu_error "Mascara no valida" \
"Una mascara tambien son cuatro numeros separados por puntos.
Lo normal es 255.255.255.0 para una red de casa, o 255.255.255.252 en
una con solo cuatro direcciones.

Has escrito: ${mascara:-(nada)}"
    return 1
  fi

  for iface in "${candidatas[@]}"; do
    info "configurando ${iface} con ${ip}/${mascara}"
    # Un 'ip addr add' que falla (direccion repetida, mascara que no existe)
    # se nota aqui y no media hora despues, cuando pacman no baja nada.
    ip addr flush dev "${iface}" 2>/dev/null || true
    if ! ip addr add "${ip}/${mascara}" dev "${iface}" 2>/dev/null; then
      menu_error "No se ha podido configurar ${iface}" \
"El equipo ha rechazado la direccion ${ip}/${mascara}. Puede que ya este
en uso por otro equipo de la red, o que la mascara no corresponda a esta red."
      return 1
    fi
    [[ -n "${puerta}" ]] && ip route add default via "${puerta}" dev "${iface}" 2>/dev/null
    networkctl reconfigure "${iface}" 2>/dev/null || true
    break
  done
  local intento
  for intento in 1 2 3 4; do
    sleep 3
    if red_hay_internet; then return 0; fi
  done
  return 1
}

# --- paso completo ----------------------------------------------------------

# El bucle de verdad: preguntar, intentar, y no rendirse hasta que el usuario
# lo diga. Salir sin internet es posible (el usuario elige 'salir'), pero no se
# sigue adelante nunca.
paso_red() {
  if red_hay_internet; then
    info "ya hay conexion a internet"
    E[red]="si"
    return 0
  fi

  menu_informacion "Sin conexion a internet" \
"Este instalador necesita internet: de ahi descarga el sistema, el escritorio
y las aplicaciones que elijas.

Todavia no hay conexion. Vamos a intentarlo.

  ${C_GRIS}Lo que se ve ahora:${C_RESET}
$(red_diagnostico)

  - Si estas en una maquina virtual, mira que tenga un adaptador de red
    conectado.
  - Si es un portatil, comprueba que la wifi este encendida.
  - Si el cable esta enchufado, puede que el router tarde un poco en dar
    salida por DHCP."

  while :; do
    if red_reanimar; then
      E[red]="si"
      info "conexion establecida sin tocar nada"
      return 0
    fi
    aviso "sigue sin haber conexion"

    if [[ "${AUTO}" == "1" ]]; then
      # En autopilot no hay quien pulse teclas: se intenta todo y se falla.
      red_conectar_wifi && { E[red]="si"; return 0; }
      error "sin conexion a internet y no hay quien la establezca"
      return 1
    fi

    local opciones
    opciones="wifi:Conectarme a una red wifi|cable:Configurar el cable a mano|otra:Volver a buscar|Mas tarde:Salir del instalador"
    preguntar_lista "opcion_red" "Sin conexion" "¿Que hacemos?" "${opciones}" 16 "otra"
    case "${E[opcion_red]}" in
      wifi)
        if red_conectar_wifi; then E[red]="si"; return 0; fi
        menu_error "No se pudo conectar" "Revisa el nombre de la red y la clave, y vuelve a intentarlo."
        ;;
      cable)
        if red_conectar_cable; then E[red]="si"; return 0; fi
        menu_error "No se pudo conectar" "Comprueba que la mascara y la puerta de enlace sean correctas."
        ;;
      otra) : ;;
      *)
        sale 1 "Se sale del instalador sin instalar nada: no hay conexion y sin
conexion no se pueden descargar los paquetes del sistema.

Dentro del live puedes mirar la red a mano con 'ip a' e 'iw'. Cuando lo
tengas, vuelve a lanzar el instalador con:  sudo install.sh"
        ;;
    esac
  done
}
