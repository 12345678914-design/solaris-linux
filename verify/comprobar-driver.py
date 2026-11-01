#!/usr/bin/env python3
"""Comprueba que las comprobaciones del driver de instalacion NO pueden
 pasar por el motivo equivocado.

    python3 verify/comprobar-driver.py

Que va a comprobar
------------------

Las 36 comprobaciones de la fase 4 de scripts/titan-instala.py (33 en BIOS)
miran texto, no codigos de salida. Es lo que hay que hacer cuando se habla con una
maquina por la consola serie: el codigo de salida de una orden mandada a otra
shell no se puede leer, pero su texto si. El problema de mirar texto es que el TEXTO DE UN
ERROR tambien cuenta, y a veces hasta tiene la palabra que se busca dentro.

  El caso que ha pasado de verdad:

      ("la consola de texto tiene historial (tmux)",
       "sudo ls /mnt/v/etc/profile.d/20-titan-scrollback.sh", r"scrollback")

  Esa comprobacion dio LUZ VERDE con el sistema instalado entero ausente, con
  el disco sin particionar, porque lo unico que salia en la consola era:

      ls: no se puede acceder a '/mnt/v/etc/profile.d/20-titan-scrollback.sh':
      No existe el fichero o el directorio

  y ahi estaba la palabra 'scrollback', que el patron buscaba. El comprobador
  se quedaba contento con la coincidencia, y el sistema no estaba instalado.

Lo que se hace aqui, sin QEMU y en menos de un segundo:

  1. Se le pasa a CADA patron la salida de error tipica de su propia orden, y se
     exige que NO case. Si un patron se deja convencer por un error suyo, aqui
     sale.

  2. Se le pasa a CADA patron una salida de exito tipica, y se exige que SI
     case. Un patron que no casa con lo bueno, y tampoco con lo malo, esta mal
     escrito: no distingue nada.

Las dos mitades hacen falta. La primera es la que caza el fallo; la segunda es
la que dice que el patron sirve para algo y no es solo 'lo que hay'.

Y despues, las secciones 11 y 12, que hacen lo que las dos anteriores NO pueden
hacer: EJECUTAR las ordenes del driver de verdad. Resultado de la primera pasada
completa de la UEFI, con el informe en la mano: de los ocho FALLO, seis eran
comprobaciones cuya ORDEN no puede dar bien, con los patrones bien escritos. La
comprobacion del idioma miraba '/usr/lib/locale/es_ES.utf8/LC_MESSAGES' (glibc
2.41 mete los idiomas en un archivo, 'locale-archive', y no crea un directorio
por idioma); las dos del fstab buscaban ' / ' y ' /boot ' en un fichero hecho con
TABULADORES; la del remoto miraba 'remotes.d/', que el flatpak 1.18.3 no usa; la
del remoto en arranque hacia 'flatpak remotes' sin '--system', que va a por la
instalacion del USUARIO (rota en un arranque recien instalado: contesta por el
canal de error y no deja nada en la salida); la del swap usaba 'head -1' de
'swapon --show', que devuelve la cabecera con zram y sin zram; y la del nombre
del sistema pedia '^OS: Titan Linux' a un fastfetch que, en un sistema en
espanol, escribe 'Sistema:'.

Eso no lo puede ver un comprobador que se prueba con las salidas de las ordenes
que el mismo acaba de escribir, porque las dos mitades de la mentira son la
misma. Las secciones nuevas montan un arbol de ficheros con el contenido REAL de
un disco instalado, le pasan a cada comprobacion su orden tal cual (con el
'sudo' quitado y los caminos apuntando al arbol) y exigen el veredicto en las
DOS direcciones: bien con los datos buenos, MAL con los mismos datos rotos. Y al
final exigen que las ordenes y los patrones VIEJOS, tal cual estaban antes del
arreglo, den MAL con esos mismos datos: si alguno pasara, el arreglo habria sido
de mentira.

  11. las comprobaciones de FICHEROS, contra un arbol de verdad.
  12. las comprobaciones de ARRANQUE, con falseadores delante del PATH, y las
      siete ordenes viejas que tienen que seguir dando mal.
"""

from __future__ import annotations

import ast
import base64
import contextlib
import gzip
import io
import importlib.util
import os
import pathlib
import re
import subprocess
import sys
import tempfile

AQUI = pathlib.Path(__file__).resolve().parent
DISTRO = AQUI.parent
SCRIPTS = DISTRO / "scripts"

# Errores de verdad, no inventados: son los que sueltan estas ordenes. La clave
# es la orden, el valor lo que sale por la consola cuando algo va mal.
ERRORES = {
    # blkid no escribe nada en la salida normal cuando no identifica nada; el
    # error va al canal de error, que tambien acaba en el mismo sitio.
    r"blkid -s TYPE -o value /dev/vda2": "blkid: /dev/vda2: ambivalent result "
                                          "(probably more than one device has the "
                                          "same UUID)\n",
    r"btrfs subvolume list": "ERROR: not a directory: /dev/vda2\n",
    r"grep -c part$": "",
    r"grep -c titanlinux": "",
    r"ls .*/usr/lib/modules 2": "ls: no se puede acceder a "
                               "'/mnt/v/usr/lib/modules': No existe el "
                               "fichero o el directorio\n",
    r"grep -c titan$": "",
    r"test -s": "",
    r"grep -c titanlinux .*grub.cfg": "grep: /mnt/v/boot/grub/grub.cfg: No existe "
                                       "el fichero o el directorio\n",
    r"x86_64-efi": "ls: no se puede acceder a '/mnt/v/boot/grub/x86_64-efi': "
                   "No existe el fichero o el directorio\n",
    r"blkid -s TYPE -o value /dev/vda1": "",
    r"EFI/TitanLinux": "ls: no se puede acceder a '/mnt/ve/EFI/TitanLinux': No "
                       "existe el fichero o el directorio\n",
    r"EFI/BOOT": "ls: no se puede acceder a '/mnt/ve/EFI/BOOT': No existe el "
                 "fichero o el directorio\n",
    r"efibootmgr": "efibootmgr: not found\n",
    r"i386-pc": "ls: no se puede acceder a '/mnt/v/boot/grub/i386-pc': No existe "
                "el fichero o el directorio\n",
    # La firma del MBR: salida REAL de 'od -An -tx1 -j510 -N2' sobre un sector de
    # arranque de verdad (con su 55 AA al final) y sobre uno que no lo tiene. Sin
    # estos dos ejemplos, la comprobacion del MBR se mediria con el patron contra
    # una salida inventada, que es justo lo que.section 11 dice que no se haga.
    r"od -An -tx1 -j510": "od: /dev/vda: No existe el fichero o el "
                         "directorio\n",
    r"grep -c 'video='": "grep: /mnt/v/boot/grub/grub.cfg: No existe el fichero "
                         "o el directorio\n",
    r"/etc/passwd": "grep: /mnt/v/etc/passwd: No existe el fichero o el "
                    "directorio\n",
    r"/etc/group": "grep: /mnt/v/etc/group: No existe el fichero o el "
                   "directorio\n",
    r"sudoers.d": "grep: /mnt/v/etc/sudoers.d/: No existe el fichero o el "
                  "directorio\n",
    r"/etc/shadow": "grep: /mnt/v/etc/shadow: No existe el fichero o el "
                    "directorio\n",
    r"locale.gen": "grep: /mnt/v/etc/locale.gen: No existe el fichero o el "
                   "directorio\n",
    r"locale.conf": "grep: /mnt/v/etc/locale.conf: No existe el fichero o el "
                    "directorio\n",
    r"os-release": "grep: /mnt/v/usr/lib/os-release: No existe el fichero o el "
                   "directorio\n",
    r"titan-release": "grep: /mnt/v/etc/titan-release: No existe el fichero o el "
                      "directorio\n",
    r"vconsole.conf": "grep: /mnt/v/etc/vconsole.conf: No existe el fichero o el "
                      "directorio\n",
    r"gnome-shell": "",
    r"usr/bin/kitty": "",
    r"scrollback": "cat: /mnt/v/etc/profile.d/20-titan-scrollback.sh: No existe "
                   "el fichero o el directorio\n",
    r"zram-generator": "",
    r"grep -c swap": "grep: /mnt/v/etc/fstab: No existe el fichero o el "
                     "directorio\n",
    # El mensaje REAL de gawk con un fichero que no esta (con comillas invertidas
    # y todo):
    #     awk: fatal: cannot open file `/mnt/v/etc/fstab' for reading
    r"awk .*fstab": "awk: fatal: cannot open file `/mnt/v/etc/fstab' for reading: "
                    "No such file or directory\n",
    r"flatpak": "",
    r"repo/config": "grep: /mnt/v/var/lib/flatpak/repo/config: No existe el "
                    "fichero o el directorio\n",
    r"flatpak/app 2": "ls: no se puede acceder a '/mnt/v/var/lib/flatpak/app': "
                      "No existe el fichero o el directorio\n",
    r"mozilla": "",
    r"ufw": "",
    r"multi-user": "ls: no se puede acceder a '/mnt/v/etc/systemd/system/"
                   "multi-user.target.wants/': No existe el fichero o el "
                   "directorio\n",
}

# Y la salida de exito minima de cada una. Si un patron no casa con esto, esta
# mal escrito: no distingue el bien del mal, que no es lo mismo que no mirar.
#
# OJO: lo que se pone aqui es lo que IMPRIME LA ORDEN COMPLETA, con sus
# 'grep -c' y sus 'wc -l' puestos. La orden entera acaba contando lineas, asi
# que su salida es un numero, no el listado entero. Poner el listado era un
# error mio del comprobador (fallaba por el motivo equivocado), y justo por eso
# esta seccion 3 sirve: un patron que no casa con su propia salida buena
# significa que ese patron no puede pasar nunca.
EXITOS = {
    r"blkid -s TYPE -o value /dev/vda2": "btrfs\n",
    r"btrfs subvolume list": "3\n",
    r"grep -c part$": "2\n",
    r"ls .*/usr/lib/modules 2.*grep -c titanlinux": "1\n",
    r"ls .*/usr/lib/modules 2.*wc -l": "1\n",
    r"ls .*/usr/lib/modules 2": "6.18.54-1-titanlinux\n",
    r"grep -c titan$": "1\n",
    r"test -s": "SI-GRUB\n",
    r"grep -c titanlinux .*grub.cfg": "4\n",
    r"x86_64-efi": "2\n",
    r"blkid -s TYPE -o value /dev/vda1": "vfat\n",
    r"EFI/TitanLinux": "grubx64.efi\n",
    r"EFI/BOOT": "BOOTX64.EFI\n",
    r"efibootmgr": "1\n",
    r"i386-pc": "2\n",
    r"od -An -tx1 -j510": " 55 aa\n",
    r"grep -c 'video='": "0\n",
    r"/etc/passwd": "1\n",
    r"/etc/group": "1\n",
    r"sudoers.d": "1\n",
    r"/etc/shadow": "1\n",
    r"locale.gen": "1\n",
    r"locale.conf": "1\n",
    r"os-release": "1\n",
    r"titan-release": "1\n",
    r"vconsole.conf": "1\n",
    r"gnome-shell": "SI-GNOME\n",
    r"usr/bin/kitty": "SI-KITTY\n",
    r"scrollback": "3\n",
    r"zram-generator": "SI-ZRAM\n",
    r"grep -c swap": "0\n",
    # Las dos del fstab, cada una con su orden. Antes eran 'grep -c' sobre la
    # linea entera, que con un fstab de tabuladores no encuentra nada (0 en vez de
    # 1) y con el patron '^1$' no podia dar bien nunca.
    r"subvol=/@": "1\n",
    r"boot/efi": "1\n",
    r"repo/config": "1\n",
    r"flatpak/app 2.*wc -l": "4\n",
    r"flatpak/app 2.*grep -c mozilla": "2\n",
    r"usr/bin/flatpak": "SI-FLATPAK\n",
    r"usr/bin/ufw": "SI-UFW\n",
    r"multi-user": "0\n",
}

# Las de la fase 5: se ejecutan ya DENTRO del sistema instalado, en la shell
# del usuario, sin sudo. Aqui lo que se comprueba es mas simple: que el patron
# casa con la salida buena y que no casa con una salida cualquiera. Lo
# interesante de esta fase es que el sistema ya esta arrancando, asi que un
# patron flojo aqui no da luz verde sobre un disco vacio, sino sobre un equipo
# que funciona a medias.
# La salida de cada orden es la de la ORDEN COMPLETA, con su 'grep -c' puesto:
# la de 'swapon --show | grep -c' es un '1' a secas, no la tabla de 'swapon'. Con
# la tabla entera, el patron '^1$' no casa y el comprobador dira que la orden no
# casa con su patron, que es verdad pero no ayuda a nadie: lo que hay que mirar es
# si el patron distingue lo bueno de lo malo, y para eso la salida tiene que ser
# la de la orden.
BUENO_ARRANQUE = {
    r"uname -s": "Linux\n",
    r"uname -r": "6.18.54-1-titanlinux\n",
    r"^hostname": "titan\n",
    r"whoami": "isai\n",
    r"tmux -V": "3.4\n",
    r"titan version": "titan 0.1.0\n",
    # El fastfetch REAL con el idioma forzado a C (leido de un arranque de
    # verdad). Sin 'LC_ALL=C' el rotulo seria 'Sistema:' y no casaria.
    r"fastfetch": "OS: Titan Linux 0.1.0 (TIT\u00c1N) x86_64\nHost: titan\n"
                  "Kernel: 6.18.54-1-titanlinux\n",
    r"gnome-shell": "SI-GNOME\n",
    r"usr/bin/kitty": "SI-KITTY\n",
    # El remoto: la salida de 'flatpak --system remotes --columns=name | grep -cx
    # flathub', que es un '1'. Sin el '--system', el flatpak de verdad va a por la
    # instalacion del usuario (rota en el arranque recien instalado) y no imprime
    # NADA en stdout, con el error por stderr.
    r"flatpak --system remotes": "1\n",
    r"passwd -S root": "root P 09/28/2026 0 99999 7 -1\n",
    # El swap: la salida de 'swapon --show | grep -c /dev/zram'. La tabla REAL de
    # un arranque con zram es 'NAME TYPE SIZE USED PRIO' y '/dev/zram0 partition
    # 1.9G 0B 100'.
    r"swapon --show": "1\n",
    r"get-default": "graphical.target\n",
    # El idioma: la salida de 'locale -a | grep -c ^es_ES'. El 'locale -a' real del
    # disco instalado era 'C', 'C.utf8' y 'POSIX', y despues del arreglo
    # 'es_ES.utf8' tambien.
    r"locale -a": "1\n",
}

fallos = 0


def comprueba(nombre: str, condicion: bool, detalle: str = "") -> None:
    global fallos
    if condicion:
        print(f"  OK    {nombre}")
    else:
        print(f"  FALLO {nombre}")
        if detalle:
            print(f"        {detalle}")
        fallos += 1


def codigo_de(nombre_funcion: str) -> str | None:
    """El CODIGO de una funcion del driver, sin su docstring y sin comentarios.

    Se devuelve None si no esta. Mirar el fichero entero con un 'in' no sirve
    para nada aqui: las explicaciones de por que se hace esto estan escritas
    justo al lado del codigo, y un comprobador que las lee se da por satisfecho
    con ellas. Por eso se pasa por el arbol sintactico, que no distingue el
    comentario del codigo porque no lo guarda: el comentario no esta en el
    arbol.
    """
    fuente = (SCRIPTS / "titan-instala.py").read_text(encoding="utf-8")
    arbol = ast.parse(fuente)
    for nodo in ast.walk(arbol):
        if isinstance(nodo, (ast.FunctionDef, ast.AsyncFunctionDef)) \
                and nodo.name == nombre_funcion:
            cuerpo = nodo.body
            # El docstring es el primer 'Constant' de tipo str. Se quita para
            # que su prosa no cuente como codigo.
            if cuerpo and isinstance(cuerpo[0], ast.Expr) \
                    and isinstance(cuerpo[0].value, ast.Constant) \
                    and isinstance(cuerpo[0].value.value, str):
                cuerpo = cuerpo[1:]
            return "\n".join(ast.get_source_segment(fuente, c) or ""
                             for c in cuerpo)
    return None


def cargar():
    """Toma el driver de verdad, no una copia: si se midiera una copia, el
    comprobador no estaria midiendo lo que se usa."""
    ruta = SCRIPTS / "titan-instala.py"
    # El driver pide argumentos al importar; se le dan los minimos.
    sys.argv = [str(ruta), "--iso", "nada.iso", "--solo-instalar"]
    spec = importlib.util.spec_from_file_location("titan_instala", ruta)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def buscar(ordenes: dict[str, str], orden: str) -> str | None:
    """El ejemplo de salida que corresponde a esta orden.

    Se prueban las claves de la MAS larga a la MAS corta, y gana la primera que
    casa. Sin eso, una clave generica como 'fstab' se lleva por delante la de
    'fstab monta la raiz con su subvolumen' y las tres comprobaciones se
    miden con el mismo ejemplo. Y da igual el orden en que esten escritas: es
    la longitud de la clave la que decide, no el orden del diccionario.
    """
    for clave in sorted(ordenes, key=len, reverse=True):
        if re.search(clave, orden):
            return ordenes[clave]
    return None


def ordenes_por_consola(mod) -> list[str]:
    """Las ordenes que el driver manda a la consola del live.

    Se leen del ARBOL SINTACTICO y no de un 'grep': el driver tiene las ordenes
    en varios sitios (las de la consola serie, las de ejemplo de las pruebas de
    esta misma seccion, que son falsas, y las de los otros metodos) y solo
    cuentan las primeras. Un 'grep' de todo el fichero se llevaria por delante
    los ejemplos de las pruebas, que es el fallo que ya se cometio con las
    menciones a 'dialog' de 'lib-comun.sh' (la letra AA).
    """
    fuente = pathlib.Path(mod.__file__).read_text()
    arbol = ast.parse(fuente)
    ordenes = []
    for nodo in ast.walk(arbol):
        if not isinstance(nodo, ast.Call):
            continue
        func = nodo.func
        if not isinstance(func, ast.Attribute) or func.attr != "run":
            continue
        if not nodo.args or not isinstance(nodo.args[0], ast.Constant):
            continue
        valor = nodo.args[0].value
        if isinstance(valor, str):
            ordenes.append(valor)
    return ordenes


def globs_sin_comillas(orden: str) -> list[str]:
    """Los globs de una orden que NO van entre comillas.

    Todo lo que va entre comillas simples o dobles se quita antes de mirar, que
    es justo lo que hace la shell: lo comillado no se expande. Asi que un
    "'*.sh'" dentro de un 'find -name' no sale, y un '/root/instalador/*.sh' sin
    comillas si. La diferencia entre las dos es toda la diferencia entre que la
    orden funcione y que no, y por eso se mira en el sitio donde se decide.
    """
    limpio = re.sub(r"'[^']*'", " ", orden)
    limpio = re.sub(r'"[^"]*"', " ", limpio)
    # Ni el '?' ni el '*' de un '$?' se miran: el '$?' es el codigo de
    # salida y sale en la mitad de las ordenes del driver ('...; echo
    # CODIGO=$?'), asi que un filtro que lo cogiera pondria en rojo la
    # orden mas larga del driver, que es justo la que si tiene que estar
    # ahi. Del '?' se Renuncia: como glob es rarisimo y aqui seria un
    # falso positivo fijo.
    limpio = re.sub(r"\$\?", " ", limpio)
    return re.findall(r"\*|\[[^]]*\]", limpio)


def cargar_consola():
    """Toma el modulo de la consola de verdad, el que usa el driver.

    Para la seccion 13 hace falta su 'plano()' y su 'PROMPT', que son los que
    convierten el bloque de bytes de la consola en el texto que el driver recibe.
    Si la prueba usara una cuenta hecha aqui, el dia que el filtro cambie la
    prueba se quedaria probando un texto que ya no existe.
    """
    ruta = SCRIPTS / "titan-verify.py"
    spec = importlib.util.spec_from_file_location("titan_verify_prueba", ruta)
    assert spec and spec.loader
    tv = importlib.util.module_from_spec(spec)
    sys.argv = [str(ruta), "--iso", "nada.iso"]
    spec.loader.exec_module(tv)
    return tv


def respuesta_de_consola(tv, bloque: str, marcador: str) -> str:
    """El texto que 'Serial.run' devolveria para ese bloque de la consola."""
    lineas = [
        linea
        for linea in tv.plano(bloque).splitlines()
        if "echo __TITAN_DONE_" not in linea
        and linea.strip() != marcador
        and not tv.PROMPT.match(linea.rstrip())
    ]
    return "\n".join(lineas)


def viejo_tipo(mod, sal: str) -> str:
    """La forma VIEJA de leer el tipo de la particion: el ultimo token.

    Se deja escrita y se usa, porque el fallo 29 fue justo esta linea
    ('limpio(sal).split()[-1]') y porque la seccion tiene que poder DEMOSTRAR que
    la forma vieja da otra cosa con el mismo texto que la nueva da bien. Si no,
    'tipo_de' podria dar bien por un motivo que no tiene nada que ver con el
    fallo, que es el error mas caro que se puede cometer en una prueba.
    """
    partes = mod.limpio(sal).split()
    return partes[-1] if partes else ""


class ConsolaFalsa:
    """El doble de la consola del driver para 'montar_destino'.

    Contesta a lo que le preguntan y anota lo que le mandan. Lo que importa es que
    el texto que devuelve es TAL COMO lo devolveria el de verdad (con los '\\r', los
    marcadores OSC 8 y el ruido del prompt), porque el fallo 29 fue del texto, no
    de la orden.

    Los montajes se simulan con una tabla: cada orden de 'mount' se busca en la
    tabla por un trozo de texto, y se le dice (a) si monta y (b) si lo que queda
    montado es el arbol de un sistema instalado. Lo segundo es lo que de verdad
    prueba el arreglo, porque un montaje puede SALIR BIEN y no ser el arbol del
    sistema (el nivel de arriba de un btrfs con subvolumenes sale bien y esta
    vacio). Un doble que dijera 'si' a todo no probaria nada.

    Lo que no este en la tabla no se simula: el montaje se rechaza con un error.
    Asi, si el driver empieza a montar cosas nuevas sin que la prueba lo diga, la
    prueba se pone roja en vez de dar bien en silencio.
    """

    def __init__(self, texto_tipo: str, montajes: dict[str, tuple[bool, bool]]) -> None:
        self.texto_tipo = texto_tipo
        self.montajes = dict(montajes)
        self.montado: dict[str, bool] = {}   # punto de montaje -> es el arbol
        self.llamadas: list[str] = []

    def run(self, orden: str, timeout: int = 30) -> tuple[bool, str]:
        self.llamadas.append(orden)
        base = orden.split("&&")[0].strip()
        if "FSTYPE" in base:
            return True, self.texto_tipo
        if "findmnt -n /mnt" in base:
            return True, ""              # en la prueba, /mnt esta limpio
        if base.startswith("sudo mkdir"):
            return True, ""
        if base.startswith("sudo umount"):
            self.montado.pop(base.split()[-1], None)
            return True, ""
        if base.startswith("sudo test -d"):
            # 'sudo test -d /mnt/v/usr -a -d /mnt/v/etc && echo SI-ARBOL...'
            # OJO: el camino es la palabra CUARTA. En la tercera esta la opcion
            # '-d', y con la tercera el falso contestaba que en '/mnt/v' no habia
            # un arbol de sistema, que es la respuesta buena para el caso malo.
            punto = base.split()[3].rsplit("/", 1)[0]
            return True, "SI-ARBOL-SISTEMA" if self.montado.get(punto) else ""
        if " mount " in f" {base} ":
            punto = base.split()[-1]
            for clave, (monta, es_arbol) in self.montajes.items():
                if clave in base:
                    if monta:
                        self.montado[punto] = es_arbol
                    return True, "SI-MONTADO" if monta else "mount: wrong fs type"
            return True, "mount: nada simulado para esta orden"
        return True, ""


def main() -> int:
    mod = cargar()

    print("== 1. las comprobaciones del sistema instalado ==")
    checks = mod.comprobaciones_instalado("/dev/vda2", "/dev/vda1", False)
    checks_bios = mod.comprobaciones_instalado("/dev/vda2", "", True)
    arranque = mod.comprobaciones_arranque()
    print(f"  nota  {len(checks)} en UEFI, {len(checks_bios)} en BIOS, "
          f"{len(arranque)} arrancando desde el disco")

    print()
    # Los ejemplos de salida buena y de salida mala no son los mismos en los dos
    # modos, y antes habia un solo juego para los dos. El del fstab es el que se
    # nota: en BIOS el fstab no tiene ninguna linea de '/boot/efi' (no hay
    # particion de arranque), asi que su salida buena es '0' y no '1'. Con el
    # ejemplo de UEFI, el patron correcto de BIOS daba FALLO en el propio
    # comprobador del driver, que es el peor sitio para un falso positivo: hace
    # imposible saber si el rojo es del patron o del ejemplo.
    errores_bios = dict(ERRORES, **{r"awk '\$2==\"/boot/efi\"":
                                    "awk: no se puede abrir el fichero "
                                    "/mnt/v/etc/fstab\n"})
    exitos_bios = dict(EXITOS, **{r"awk '\$2==\"/boot/efi\"": "0\n"})

    print("== 2. ningun patron se deja convencer por su propio error ==")
    for lista, errores in ((checks, ERRORES), (checks_bios, errores_bios)):
        for nombre, orden, patron in lista:
            error = buscar(errores, orden)
            if error is None:
                # Sin ejemplo de error, esta comprobacion no se puede juzgar. Se
                # avisa en vez de dar verde por omision: dar verde por no mirar
                # es como fallar dando luz verde.
                print(f"  nota  sin ejemplo de error para: {nombre}")
                continue
            casa = re.search(patron, error, re.M) is not None
            comprueba(f"el error de '{nombre[:44]}' no lo hace pasar", not casa,
                      f"patron={patron!r} casa con {error.strip()!r}")

    print()
    print("== 3. y cada patron distingue el bien del mal ==")
    for lista, exitos in ((checks, EXITOS), (checks_bios, exitos_bios)):
        for nombre, orden, patron in lista:
            bueno = buscar(exitos, orden)
            if bueno is None:
                print(f"  nota  sin ejemplo de exito para: {nombre}")
                continue
            casa = re.search(patron, bueno, re.M) is not None
            comprueba(f"'{nombre[:44]}' pasa con lo bueno", casa,
                      f"patron={patron!r} NO casa con {bueno.strip()!r}")

    print()
    print("== 4. las del arranque, con el mismo criterio ==")
    # Aqui no hay 'error tipico' que poner: el equipo ya esta encendido y la
    # shell responde. Lo que se comprueba es que el patron distinga: casa con la
    # salida buena, y no casa con una linea cualquiera. Un patron como '\w' o
    # '\d' casa con las dos, y entonces no esta comprobando nada.
    CUALQUIER_COSA = "no se que responder a esto\n"
    for nombre, orden, patron in arranque:
        casa_malo = re.search(patron, CUALQUIER_COSA, re.M) is not None
        comprueba(f"'{nombre[:44]}' no pasa con cualquier cosa", not casa_malo,
                  f"patron={patron!r} casa con una linea cualquiera")
        bueno = buscar(BUENO_ARRANQUE, orden)
        if bueno is None:
            print(f"  nota  sin ejemplo de exito para: {nombre}")
            continue
        casa_bueno = re.search(patron, bueno, re.M) is not None
        comprueba(f"'{nombre[:44]}' pasa con su salida buena", casa_bueno,
                  f"patron={patron!r} NO casa con {bueno.strip()!r}")

    print()
    print("== 5. las ordenes que se pueden fallar tiran el error ==")
    # Regla de estilo que se ha seguido en el driver: si la orden puede
    # escribiendo un error, ese error no puede acabar en la salida que se mira.
    # Compruebo que se cumple, y no que se cumpla hoy: si manana alguien anade
    # un 'ls' sin el '2>/dev/null', esto lo dice.
    sospechosas = []
    for nombre, orden, _ in checks + checks_bios + arranque:
        # Solo las que IMPRIMEN el contenido de algo (ls, cat, grep -c sobre
        # fichero). Las que son 'test -x && echo SI-...' no pueden escribir nada
        # si no se cumple la condicion, y no hay nada que tapar.
        if re.search(r"\b(ls|cat)\b", orden) and "2>/dev/null" not in orden \
                and "/dev/null" not in orden:
            sospechosas.append((nombre, orden))
        if re.search(r"^\s*sudo? ?(grep|blkid|btrfs|efibootmgr|flatpak|swapon|"
                     r"systemctl|uname|hostname|whoami|tmux|fastfetch|titan)\b",
                     orden) and "2>/dev/null" not in orden \
                and "/dev/null" not in orden:
            sospechosas.append((nombre, orden))
    if sospechosas:
        for nombre, orden in sospechosas:
            comprueba(f"'{nombre[:40]}' manda el error a /dev/null", False,
                      f"orden: {orden}")
    else:
        ok = f"las {len(checks) + len(checks_bios) + len(arranque)} ordenes que "
        ok += "pueden fallar tiran su error a /dev/null"
        print(f"  OK    {ok}")

    print()
    print("== 6. los montajes se comprueban por el echo, no por run() ==")
    # El otro fallo de este driver, y es del mismo genero que los de arriba.
    #
    # 'run()' devuelve si la CONSOLA contesto a la orden, no si la orden salio
    # bien: un 'mount' que falla escribe su error, la marca aparece igual y
    # 'run' dice que todo bien. Con eso, montar el sistema instalado podia
    # fallar entero y la fase 4 seguia como si nada, con /mnt/v vacio y todas
    # las comprobaciones de memoria.
    #
    # El arreglo es que cada montaje se acabe en '&& echo SI-MONTADO' y se
    # busque eso.
    #
    # Y se busca en el CODIGO, no en el texto del fichero. La primera version
    # de esta comprobacion hacia 'if "&& echo SI-MONTADO" in fuente' y daba
    # verde con el arreglo quitado, porque la cadena seguia ahi escrita en el
    # comentario que explica el arreglo. Un comprobador que se puede satisfacer
    # con un comentario es un comprobador que no comprueba nada, y es
    # exactamente el mismo fallo que el que esta seccion persigue.
    cuerpo = codigo_de("montar_destino")
    if cuerpo is None:
        comprueba("montar_destino() existe y se le puede mirar dentro", False,
                  "no se encuentra def montar_destino() en el driver")
    else:
        comprueba("los montajes se confirman con un SI-MONTADO explicito",
                  "&& echo SI-MONTADO" in cuerpo,
                  "montar_destino() vuelve a fiarse de lo que devuelve run()")
        # Y no basta con que la cadena este: tiene que ser EL codigo que
        # monta, no una linea muerta. Se mira que la cadena este dentro del
        # cuerpo de la funcion, que es lo unico que se ha mirado.
        comprueba("y la cadena esta en el codigo de la funcion, no en un "
                  "comentario", "SI-MONTADO" in cuerpo)

    print()
    print()
    print("== 7. ningun montaje del driver se fia de run() ==")
    # La seccion 6 miraba una sola funcion, 'montar_destino'. El fallo de verdad
    # fue ese: mientras esa seccion daba verde, el montaje de la particion de
    # arranque (en el cuerpo de la fase 4) seguia con el patron viejo, el de
    # fiarse de lo que devuelve 'run()', y no podia fallar. O sea: la seccion 6
    # estaba en verde por lo que miraba, no por lo que hacia.
    #
    # Y esta seccion se escribio midiendo la SINTAXIS: buscaba cada texto de
    # 'mount' en el arbol y subia desde el hasta el 'run()' que lo mandaba, para
    # ver quien anadia la marca. Funciono hasta que el fallo 29 obligo a
    # arreglar 'montar_destino' y sus ordenes de montaje empezaron a guardarse en
    # una lista, para probarlas en orden. El camino desde el f-string hasta el
    # 'run' dejo de ser directo, el analisis no lo seguia, y la seccion se puso en
    # rojo SIN QUE HUBIESE NINGUN FALLO. La regla ("ningun montaje se fia del
    # codigo de salida de 'run()'") seguia cumpliendose a lo largo.
    #
    # Eso es una letra propia (la V): un comprobador que analiza la sintaxis acaba
    # midiendo la FORMA del codigo, y cuando la forma cambia sin que cambien las
    # reglas, se rompe el comprobador y no el producto. Y de ahi sale la otra
    # mitad de la leccion: para una regla sobre lo que se MANDA, lo que hay que
    # mirar es lo que se manda, no como esta escrito.
    #
    # Por eso la seccion mira las dos cosas de verdad. La primera es estatica (por
    # el arbol, no por el texto, para que los comentarios que explican el arreglo
    # no cuenten): NINGUN 'run()' del driver escribe su orden de montaje en la
    # propia llamada sin la marca de confirmacion. Asi, un montaje NUEVO pegado a
    # su 'run' no se puede colar por el mismo agujero.
    #
    # Y la segunda mira lo que sale de verdad: se hacen correr los caminos de
    # montaje de 'montar_destino' con una consola de mentira y se mira, orden a
    # orden, que TODA orden de 'mount' que llega lleva su '&& echo SI-MONTADO'.
    # (El camino de la particion de arranque, que va por 'anota_montaje', lo
    # comprueba la seccion 10 con su propio doble, para no tener dos dobles
    # distintos hablando con la misma consola.)
    fuente = (SCRIPTS / "titan-instala.py").read_text(encoding="utf-8")
    arbol = ast.parse(fuente)
    montajes_en_run: list[tuple[int, str, bool]] = []
    for nodo in ast.walk(arbol):
        if not isinstance(nodo, ast.Call):
            continue
        func = nodo.func
        nombre = func.attr if isinstance(func, ast.Attribute) \
            else (func.id if isinstance(func, ast.Name) else "")
        if nombre != "run" or not nodo.args:
            continue
        orden = " ".join((ast.get_source_segment(fuente, nodo.args[0]) or "").split())
        if not re.search(r"(?:^|sudo\s+)(?<!u)mount\b", orden):
            continue
        montajes_en_run.append((nodo.lineno, orden, "SI-MONTADO" in orden))
    for linea, orden, confirmado in montajes_en_run:
        comprueba(f"el montaje escrito en la linea {linea} lleva su confirmacion",
                  confirmado,
                  f"la orden es '{orden[:70]}' y va a 'run()' sin '&& echo "
                  f"SI-MONTADO': 'run()' contesta 'la consola contesto', no 'la "
                  f"orden salio bien'")
    # Y que la lista de arriba no este vacia por averia del comprobador: si no
    # aparece NINGUN montaje escrito en un 'run', o no hay montajes o todos pasan
    # por un ayudante, y en ese caso el peso de la seccion lo lleva la parte de
    # abajo, que mira lo que sale de verdad.
    comprueba("el reparto entre 'run' directo y ayudante se puede ver",
              bool(montajes_en_run) or not codigo_de("monta"),
              f"hay {len(montajes_en_run)} montajes escritos en un 'run()' y el "
              f"ayudante 'monta' existe: habria que mirar por que no aparece "
              f"ninguno, que puede ser que la forma haya cambiado otra vez")

    RUTAS: list[tuple[str, ConsolaFalsa]] = [
        ("btrfs con subvolumenes", ConsolaFalsa("\nFSTYPE=btrfs\n", {
            "subvol=@ /dev/vda2 /mnt/v": (True, True),
            "subvol=@var /dev/vda2 /mnt/v/var": (True, True),
            "subvol=@home /dev/vda2 /mnt/v/home": (True, True),
        })),
        ("btrfs sin subvolumenes", ConsolaFalsa("\nFSTYPE=btrfs\n", {
            "subvol=@ /dev/vda2 /mnt/v": (False, False),
            "mount /dev/vda2 /mnt/v": (True, True),
        })),
        ("un disco que no es btrfs", ConsolaFalsa("\nFSTYPE=ext4\n", {
            "mount /dev/vda2 /mnt/v": (True, True),
        })),
        ("sin saber el tipo", ConsolaFalsa("\ntitan@38\n", {
            "subvol=@ /dev/vda2 /mnt/v": (True, True),
            "subvol=@var /dev/vda2 /mnt/v/var": (True, True),
            "subvol=@home /dev/vda2 /mnt/v/home": (True, True),
        })),
    ]
    caminos: set[tuple[str, ...]] = set()
    for etiqueta, consola in RUTAS:
        mod.montar_destino(consola, "/dev/vda2")
        montajes = [c for c in consola.llamadas if " mount " in f" {c} "]
        sin_confirmar = [c for c in montajes if "SI-MONTADO" not in c]
        comprueba(f"por el camino de {etiqueta}, ningun montaje sale sin confirmar",
                  montajes and not sin_confirmar,
                  f"han salido sin marca: {[c[:70] for c in sin_confirmar]}, o no "
                  f"ha salido ningun montaje: el camino no se esta probando")
        caminos.add(tuple(montajes))
    comprueba("y los caminos de montaje probados son varios de verdad",
              len(caminos) >= 3,
              f"solo {len(caminos)} caminos de montaje distintos: con menos de "
              "tres, la parte dinamica de esta seccion no esta probando los "
              "montajes del driver, solo uno")

    print()
    print("== 8. montar_destino() no se monta dentro de si mismo ==")
    # El bug 18, y el peor de todos, porque el comprobador daba LUZ VERDE con el
    # sistema instalado entero ausente.
    #
    #   El instalador, al fallar, dejaba /mnt montado con el sistema destino.
    #   Este driver montaba entonces /mnt/v, que estaba DENTRO de /mnt, o sea
    #   dentro del sistema recien instalado. Las 34 comprobaciones de la fase 4
    #   decian "no existe" con el sistema entero ahi, y el informe decia "todo
    #   bien" con 8 de 8 en verde.
    #
    # El instalador ya lo arregla (desmonta tambien cuando falla), asi que esto
    # parece innecesario. No lo es: si vuelve a pasar, o si el disco viene de
    # una sesion anterior, tiene que verse aqui, en una linea que lo dice, y no
    # veinte minutos despues en ocho comprobaciones que dicen "no existe".
    cuerpo = codigo_de("montar_destino")
    if cuerpo is None:
        comprueba("montar_destino() existe y se le puede mirar dentro", False,
                  "no se encuentra def montar_destino() en el driver")
    else:
        i_mira = cuerpo.find("findmnt")
        i_suelta = cuerpo.find("umount")
        comprueba("antes de montar, mira si /mnt esta ya montado",
                  re.search(r"findmnt[^\n]*/mnt", cuerpo) is not None,
                  "montar_destino() monta sin mirar lo que hubiera montado antes")
        comprueba("y si lo esta, lo desmonta",
                  re.search(r"umount[^\n]*/mnt", cuerpo) is not None,
                  "no hay ningun umount de /mnt en montar_destino()")
        # Y que el desmontaje este ANTES del primer montaje y no despues: en el
        # otro orden monta el sistema dentro del otro sistema y luego lo
        # desmonta, que es peor que no desmontar nada.
        montajes_fc = [cuerpo.find(m) for m in
                       ("mount -o subvol", "monta(f\"sudo mount",
                        "mount {raiz} /mnt/v") if m in cuerpo]
        i_monta = min(montajes_fc) if montajes_fc else len(cuerpo)
        if i_mira < 0 or i_suelta < 0 or not montajes_fc:
            comprueba("el orden es: mirar, soltar y luego montar", False,
                      f"findmnt en {i_mira}, umount en {i_suelta}, "
                      f"montajes de subvolumen en {montajes_fc}")
        else:
            comprueba("el orden es: mirar, soltar y luego montar",
                      i_mira < i_suelta < i_monta,
                      f"findmnt en {i_mira}, umount en {i_suelta}, "
                      f"primer mount en {i_monta}")
        # Y que diga que no se ha podido soltar, en vez de seguir a lo suyo con
        # un /mnt que sigue montado: mirar dentro daria falso, que es
        # precisamente el bug.
        despues = cuerpo[i_mira:] if i_mira >= 0 else cuerpo
        comprueba("y si no se puede soltar, lo dice y para (no sigue mirando "
                  "dentro)", "return False" in despues[:900],
                  "sigue adelante aunque /mnt no se haya podido desmontar")

    # La salida REAL de 'btrfs subvolume list'. Copiada a mano, de un btrfs de
    # verdad: asi se decia, y era mentira, que el patron '/(@|@home|@var)$'
    # contaba los tres subvolumenes. No contaba ninguno, porque la ruta va
    # detras de la palabra 'path' y no con una barra delante. Y la seccion 3 no
    # lo cazo porque su ejemplo de salida bueno era "3", escrito a mano por el
    # mismo comprobador: un ejemplo inventado no puede encontrar un patron
    # equivocado, porque uno ya inventado y el otro tambien.
    #
    # Para volver a sacarla, en una maquina con btrfs-progs y root:
    #   truncate -s 300M /tmp/p.img && mkfs.btrfs /tmp/p.img
    #   mount -o loop /tmp/p.img /mnt
    #   for s in @ @home @var; do btrfs subvolume create /mnt/$s; done
    #   btrfs subvolume create /mnt/@var/lib      # uno anidado, a proposito
    #   btrfs subvolume list /mnt
    #   umount /mnt && losetup -d /tmp/p.img
    # Lo que sale es exactamente lo de BTRFS_DE_VERDAD, con los cuatro
    # subvolumenes: los tres del proyecto y el anidado, que NO tiene que contar.
    print()
    print("== 9. el patron de los subvolumenes, con la salida real de btrfs ==")
    BTRFS_DE_VERDAD = (
        "ID 256 gen 9 top level 5 path @\n"
        "ID 257 gen 9 top level 5 path @home\n"
        "ID 258 gen 9 top level 5 path @var\n"
        "ID 259 gen 11 top level 258 path @var/lib\n"
    )
    SIN_SUBVOLUMENES = "ID 256 gen 9 top level 5 path\n"
    OTRO_NOMBRE = "ID 256 gen 9 top level 5 path @datos\n"
    # El patron se saca de la orden del driver, no se reescribe aqui: si se
    # reescribiera, este comprobador estaria probando su propia copia del
    # patron, y el patron equivocado se colaria igual.
    orden_subvol = next((o for _, o, _ in checks if "btrfs subvolume list" in o), "")
    patron_subvol = re.search(r"grep -cE? '([^']+)'", orden_subvol)
    if not patron_subvol:
        comprueba("el patron de los subvolumenes se puede sacar de la orden", False,
                  f"no hay ningun 'grep' en la orden: {orden_subvol!r}")
    else:
        expr = patron_subvol.group(1)

        def cuenta(salida: str) -> str:
            """La salida REAL de la orden del driver, con la salida dada."""
            proc = subprocess.run(
                ["bash", "-c", f"printf '%s' \"$1\" | grep -cE '{expr}'",
                 "bash", salida],
                capture_output=True, text=True)
            return proc.stdout.strip()

        comprueba("con la salida real de un btrfs con los tres subvolumenes, "
                  "la orden cuenta 3", cuenta(BTRFS_DE_VERDAD) == "3",
                  f"patron={expr!r} conto {cuenta(BTRFS_DE_VERDAD)!r}")
        # Y que no cuente de mas: un subvolumen anidado y uno con otro nombre no
        # son de los del proyecto, y un 'grep' flojo ('path @') contaria los
        # cuatro.
        comprueba("y el anidado (@var/lib) no cuenta de mas", cuenta(BTRFS_DE_VERDAD) == "3")
        comprueba("y un subvolumen que no es del proyecto tampoco",
                  cuenta(OTRO_NOMBRE) == "0", f"patron={expr!r}")
        # Y que sin subvolumenes no invente ninguno.
        comprueba("y un btrfs sin subvolumenes da 0, que es lo que tiene que ver",
                  cuenta(SIN_SUBVOLUMENES) == "0", f"patron={expr!r}")
        # Y que el patron que hay en el driver acepte la salida buena de la
        # seccion 3 ('3'), para que las dos secciones no se contradigan.
        comprueba("y el patron del driver acepta la salida buena de la seccion 3",
                  re.search("^3$", cuenta(BTRFS_DE_VERDAD), re.M) is not None)

    print()
    print("== 10. si la raiz no se monta, se dice una vez y no se sigue mirando ==")
    # El fallo 29, que es del APARATO y no del instalador: con el sistema
    # instalado entero en el disco, pero sin montar, el driver hacia veinte
    # comprobaciones mirando dentro de un /mnt/v vacio. Las veinte decian "no
    # existe" y el informe decia que no habia nada instalado, que es falso: lo
    # que no habia era el montaje.
    #
    # Y lo que hacia que eso pasara es una linea:
    #
    #     ok = montar_destino(ser, raiz)
    #
    # 'montar_destino' devuelve (ok, detalle), o sea una TUPLA. Una tupla no
    # esta vacia nunca, asi que 'ok' era verdad siempre, y la comprobacion "la
    # raiz instalada se monta con sus subvolumenes" no podia fallar. El
    # comprobador tiene que poder darle la vuelta a eso, asi que se le da una
    # consola de mentira que dice que /mnt esta ocupado y se le exige que la
    # puerta devuelva False de verdad.

    class ConsolaOcupada:
        """Consola de mentira: contesta lo justo para llegar a montar_destino().

        Con 'ocupado' dice que /mnt sigue montado despues del umount, que es
        justo el caso que paso de verdad: el instalador dejo el destino
        montado y no se pudo soltar. Sin 'ocupado', monta bien.
        """

        def __init__(self, ocupado: bool):
            self.ocupado = ocupado
            self.ordenes: list[str] = []

        def run(self, orden: str, timeout: int = 30) -> tuple[bool, str]:
            self.ordenes.append(orden)
            if "FSTYPE" in orden:
                # La pregunta del tipo es la nueva, con el prefijo: una palabra
                # suelta ('btrfs') era justo lo que el fallo 29 leia mal.
                return True, "FSTYPE=btrfs"
            if "test -d" in orden:
                # Y el arbol montado: sin esto, 'montar_destino' no puede saber si
                # lo que ha montado es el sistema instalado o el nivel de arriba
                # del btrfs, y se pasa por los dos (el fallo 29, otra vez).
                return True, "SI-ARBOL-SISTEMA"
            if "findmnt -n /mnt" in orden:
                # 'findmnt' imprime el montaje, y despues el 'echo SI-MONTADO'
                # que el driver anade para no fiarse del codigo de salida.
                return True, ("/mnt\n/dev/vda2[/@]\nSI-MONTADO\n"
                              if self.ocupado else "")
            if orden.startswith("sudo umount -R /mnt"):
                if self.ocupado:
                    return True, "umount: /mnt: el destino esta ocupado."
                return True, ""
            if "&& echo SI-MONTADO" in orden:
                return True, "SI-MONTADO"
            return True, ""

    class InformeDeMentira:
        def __init__(self):
            self.notas: list[tuple] = []

        def anota(self, fase, nombre, ok, detalle="") -> None:
            self.notas.append((fase, nombre, ok, detalle))

    ser_limpio = ConsolaOcupada(ocupado=False)
    inf_limpio = InformeDeMentira()
    montada_ok = mod.anota_montaje(inf_limpio, ser_limpio, "/dev/vda2")
    comprueba("si el montaje va bien, la puerta dice que si",
              montada_ok is True,
              f"ha devuelto {montada_ok!r}, y tiene que ser True (no una tupla)")
    nota_ok = next((n for n in inf_limpio.notas
                    if "se monta con sus subvolumenes" in n[1]), None)
    comprueba("y el veredicto que se anota es un si de verdad",
              nota_ok is not None and nota_ok[2] is True,
              f"la nota es {nota_ok!r}")

    ser_ocupado = ConsolaOcupada(ocupado=True)
    inf_ocupado = InformeDeMentira()
    montada_mal = mod.anota_montaje(inf_ocupado, ser_ocupado, "/dev/vda2")
    comprueba("si /mnt esta ocupado, la puerta dice que NO (fallo 29)",
              montada_mal is False,
              f"ha devuelto {montada_mal!r}: con /mnt ocupado, montar_destino() "
              "devuelve (False, ...), y una tupla o un 0 darian por bueno un "
              "montaje que no esta")
    nota_mal = next((n for n in inf_ocupado.notas
                     if "se monta con sus subvolumenes" in n[1]), None)
    comprueba("y el veredicto que se anota entonces es un no de verdad",
              nota_mal is not None and nota_mal[2] is False,
              f"la nota es {nota_mal!r}")
    comprueba("y el motivo del aviso queda apuntado, no se pierde",
              nota_mal is not None
              and "no se ha podido desmontar" in nota_mal[3],
              f"la nota es {nota_mal!r}: si no se dice por que, el informe dice "
              "que no se monta y ya, que no ayuda a nadie")
    # Y que con /mnt ocupado NO se sigue mirando dentro: se sale antes de
    # preguntar por los subvolumenes, que es lo que costaba veinte FALLO.
    comprueba("y con /mnt ocupado no se intenta montar el sistema dentro",
              not any("subvol=@" in o for o in ser_ocupado.ordenes),
              f"ha seguido montando: {[o for o in ser_ocupado.ordenes][:4]}")
    comprueba("y con /mnt libre, en cambio, monta los tres subvolumenes",
              sum("subvol=@" in o for o in ser_limpio.ordenes) == 3,
              f"ordenes={[o for o in ser_limpio.ordenes if 'subvol' in o]}")

    # Y lo mismo por el arbol sintactico, que es lo que caza a quien escriba
    # otra vez 'ok = montar_destino(...)' o quite la puerta sin querer.
    fuente = (SCRIPTS / "titan-instala.py").read_text(encoding="utf-8")
    arbol = ast.parse(fuente)
    puerta = None
    for nodo in ast.walk(arbol):
        if isinstance(nodo, ast.Assign) and isinstance(nodo.value, ast.Call) \
                and getattr(nodo.value.func, "id", "") == "anota_montaje":
            for blanco in nodo.targets:
                if isinstance(blanco, ast.Name):
                    puerta = blanco.id
    bucle = None
    for nodo in ast.walk(arbol):
        if isinstance(nodo, ast.For) and isinstance(nodo.iter, ast.Call) \
                and getattr(nodo.iter.func, "id", "") == "comprobaciones_instalado":
            bucle = nodo
    comprueba("la fase 4 llama a la puerta y guarda su respuesta en una variable",
              puerta is not None,
              "no se encuentra 'algo = anota_montaje(...)' en el driver: o no se "
              "pregunta, o la respuesta se tira")
    # La forma del bug, buscada por todo el arbol: asignar a UN solo nombre una
    # llamada que devuelve dos cosas es lo que hacia que 'ok' fuera verdad
    # siempre. Se busca con el arbol, no con un 'in' sobre el texto, porque el
    # texto tiene la explicacion del fallo escrita al lado y un comprobador que
    # la lee se da por satisfecho con ella.
    tuplas_olvidadas = []
    for nodo in ast.walk(arbol):
        if isinstance(nodo, ast.Assign) and isinstance(nodo.value, ast.Call) \
                and getattr(nodo.value.func, "id", "") in ("montar_destino",):
            for blanco in nodo.targets:
                if isinstance(blanco, ast.Name):
                    tuplas_olvidadas.append(blanco.id)
    comprueba("en ninguna parte se guarda 'montar_destino(...)' en un solo nombre",
              not tuplas_olvidadas,
              f"en la linea {tuplas_olvidadas}: una tupla de dos cosas es "
              "verdad siempre, y con eso la comprobacion no puede fallar")
    if puerta is not None and bucle is not None:
        dentro = False
        for nodo in ast.walk(arbol):
            if isinstance(nodo, ast.If) and any(x is bucle for x in ast.walk(nodo)):
                if puerta in (ast.get_source_segment(fuente, nodo.test) or ""):
                    dentro = True
        comprueba("y las comprobaciones de dentro solo se hacen si la puerta dice que si",
                  dentro,
                  "el bucle de comprobaciones_instalado() no esta dentro de un "
                  f"'if' que mire '{puerta}': sin montar, cada comprobacion daria "
                  "'no existe' y el informe diria que no hay nada instalado")
    else:
        comprueba("y las comprobaciones de dentro solo se hacen si la puerta dice que si",
                  False, "no se encuentra el bucle de comprobaciones_instalado()")


    print()
    print("== 11. las comprobaciones de FICHEROS, contra un arbol de verdad ==")
    # Las secciones de arriba le dan a cada patron una salida buena y una mala de
    # su propia orden, escritas a mano. Eso caza al patron que no distingue, pero
    # no mira la ORDEN: si el 'grep' de la orden esta mal escrito (buscando
    # ' / ' en un fstab separado con tabuladores), la salida buena y la mala se
    # inventan tan de acuerdo con la orden que la orden llega a estar mal y no se
    # ve.
    #
    # Que fue justo lo que paso con ocho comprobaciones en la primera pasada
    # completa: los patrones estaban bien, las ordenes no. Asi que aqui se
    # EJECUTA la orden del driver de verdad --con el 'sudo' quitado y los caminos
    # apuntando a un arbol de ficheros-- contra un arbol montado con el contenido
    # REAL de un disco instalado, y se exige el veredicto en las dos direcciones:
    # con los datos buenos tiene que dar bien, y con los mismos datos rotos tiene
    # que dar MAL. Una comprobacion que da bien con lo bueno y con lo malo no
    # mide nada, por muy bien escrita que este.
    #
    # De donde sale cada piececita:
    #   * /etc/fstab: 'cat -A' del fstab de verdad, CON SUS TABULADORES (que es lo
    #     que hacia pasar todo: el instalador escribe con 'printf' y tabulador, no
    #     con un espacio).
    #   * locale.gen, locale.conf, vconsole.conf, passwd, group, shadow,
    #     sudoers.d/10-titan, profile.d/20-titan-scrollback.sh,
    #     var/lib/flatpak/repo/config y boot/grub/grub.cfg: leidos del disco
    #     instalado con el driver de diagnostico (scripts/titan-mira.py con las
    #     ordenes de /var/tmp/ordenes.txt).
    #   * usr/lib/os-release: el del LIVE (que es lo que el instalador copia al
    #     destino) y el del paquete 'pacman' de pacstrap, que es lo que decia el
    #     sistema instalado antes del fallo 35.
    #
    # Lo que NO esta aqui, y por que:
    #   * 'los tres subvolumenes estan dentro' necesita un btrfs de verdad. La
    #     seccion 9 lo cubre con la salida REAL de 'btrfs subvolume list', que
    #     sale igual de un disco real, y montar un btrfs aqui seria mas maquina de
    #     la que hace falta.
    #   * lo de '/dev/vda1' y '/dev/vda2' (blkid, lsblk) y el firmware
    #     (efibootmgr) no son ficheros de un arbol: son el disco. Se quedan en la
    #     QEMU, que es donde se miran de verdad.
    ARBOL: dict[str, str | None] = {
        "etc/fstab": (
            "# Static information about the filesystems.\n"
            "# See fstab(5) for details.\n"
            "\n"
            "# <file system> <dir> <type> <options> <dump> <pass>\n"
            "# Generado por el instalador de Titan Linux.\n"
            "# Los UUID son de verdad, para que el disco pueda cambiar de orden.\n"
            "# /dev/vda2 LABEL=titan\n"
            "UUID=591cbf58-cc79-4848-a98b-4b3bae257dc5\t/         \tbtrfs     "
            "\trw,relatime,compress=zstd:3,discard=async,space_cache=v2,subvol=/@\t0 0\n"
            "\n"
            "# /dev/vda2 LABEL=titan\n"
            "UUID=591cbf58-cc79-4848-a98b-4b3bae257dc5\t/home     \tbtrfs     "
            "\trw,relatime,compress=zstd:3,discard=async,space_cache=v2,subvol=/@home\t0 0\n"
            "\n"
            "# /dev/vda2 LABEL=titan\n"
            "UUID=591cbf58-cc79-4848-a98b-4b3bae257dc5\t/var      \tbtrfs     "
            "\trw,relatime,compress=zstd:3,discard=async,space_cache=v2,subvol=/@var\t0 0\n"
            "\n"
            "# /dev/vda1 LABEL=TITAN\n"
            "UUID=EE4C-C2C4      \t/boot/efi \tvfat      \trw,relatime,fmask=0022,"
            "dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,"
            "errors=remount-ro\t0 2\n"
        ),
        # El arbol bueno es lo que el instalador TIENE que dejar. Y el fichero
        # roto, 'locale-gen-roto', es el REAL del disco instalado, que es el
        # estado en que lo dejo el fallo 32: la linea 519 era 'es_ES.UTF-8' y ya,
        # sin el juego de caracteres, que es lo que hacia que 'locale-gen'
        # contestase 'error: Bad entry' y no generase nada.
        "etc/locale.gen": (
            "# This file lists locales one per line, with the charset on the\n"
            "# same line.  Uncommenting a line here should generate the locale\n"
            "# in the next run of locale-gen.\n"
            "#\n"
            "#es_ES ISO-8859-1  \n"
            "#es_ES@euro ISO-8859-15  \n"
            "es_ES.UTF-8 UTF-8\n"
        ),
        "etc/locale-gen-roto": (
            "# This file lists locales one per line, with the charset on the\n"
            "# same line.  Uncommenting a line here should generate the locale\n"
            "# in the next run of locale-gen.\n"
            "#\n"
            "#es_ES.UTF-8 UTF-8  \n"
            "#es_ES ISO-8859-1  \n"
            "#es_ES@euro ISO-8859-15  \n"
            "es_ES.UTF-8\n"
        ),
        "etc/locale.conf": "es_ES.UTF-8\n",
        "etc/vconsole.conf": "KEYMAP=es\n",
        "etc/passwd": (
            "root:x:0:0:root:/root:/bin/bash\n"
            "dbus:x:81:81:Dynamic System Bus User:/usr:/bin/false\n"
            "isai:x:1000:1000::/home/isai:/bin/bash\n"
        ),
        "etc/group": (
            "root:x:0:\n"
            "audio:x:906:\n"
            "video:x:904:\n"
            "storage:x:908:\n"
            "wheel:x:998:isai\n"
        ),
        "etc/shadow": (
            "root:$y$j9T$T6fSBbtjE.63AHwMSackO1$v5spHsq0QD1o6zXUwm6LLTgbSmZQUhm"
            "NvlLV0xr1wT/:20724::::::\n"
            "isai:$y$j9T$bQ0uMhnBQ7Uz7OzJ0eM0uRf9EMlXuS2E5GfqR8xNqjBBrHT1Qhu2"
            "QiKc8CTb2HJmE0J/0ZkQZ0wQ4J2yB9gQCmYhZ3xV6uE1B:20724:0:99999:7:::\n"
        ),
        "etc/sudoers.d/10-titan": (
            "# Escrito por el instalador de Titan Linux.\n"
            "# isai puede usar sudo sin escribir la clave, igual que en el live.\n"
            "# Para que la pida, cambia 'NOPASSWD' por 'PASSWD' y ejecuta "
            "'visudo -f' sobre\n"
            "# este fichero antes de reiniciar.\n"
            "isai ALL=(ALL:ALL) NOPASSWD: ALL\n"
        ),
        # El script REAL del disco instalado. Se comprueba con 'grep -c tmux' y
        # con 'grep -c scrollback': los dos salen del fichero de verdad, y el
        # segundo esta en el texto de los comentarios, no en una orden.
        "etc/profile.d/20-titan-scrollback.sh": (
            "# Titan Linux -- historial de la consola de texto.\n"
            "#\n"
            "# La consola de texto del kernel no puede hacer scroll (fbcon no\n"
            "# implementa con_scrolldelta), asi que el historial lo da un tmux por\n"
            "# encima. Solo envuelve las consolas de texto, nunca el puerto serie,\n"
            "# que es la via de rescate y la que usan las comprobaciones automaticas.\n"
            "#\n"
            "# En un equipo con escritorio grafico el gestor de sesion ocupa tty1,\n"
            "# asi que aqui se aplica a cualquier tty virtual que no sea la suya.\n"
            "\n"
            "[[ -z \"${TMUX:-}\" ]] || return 0\n"
            "[[ -t 1 ]] || return 0\n"
            "command -v tmux >/dev/null 2>&1 || return 0\n"
            "\n"
            "tty_actual=\"$(tty 2>/dev/null || true)\"\n"
            "[[ \"${tty_actual}\" == /dev/tty[0-9]* ]] || return 0\n"
            "\n"
            "exec tmux new-session -A -s titan\n"
        ),
        # El os-release del LIVE, que es lo que el instalador copia al destino. El
        # codename con tilde va con escapes porque este fichero va TODO en ASCII:
        # el os-release de verdad la lleva, pero aqui se compone.
        "usr/lib/os-release": (
            "NAME=\"Titan Linux\"\n"
            "PRETTY_NAME=\"Titan Linux 0.1.0 (TIT\u00c1N)\"\n"
            "VERSION_ID=\"0.1.0\"\n"
            "VERSION=\"0.1.0 (TIT\u00c1N)\"\n"
            "ID=arch\n"
            "ID_LIKE=arch\n"
            "ANSI_COLOR=\"38;2;56;214;255\"\n"
            "LOGO=titanlinux-logo\n"
        ),
        "etc/titan-release": (
            "NAME=Titan Linux\n"
            "PRETTY_NAME=Titan Linux 0.1.0 (TIT\u00c1N)\n"
            "VERSION=0.1.0 (TIT\u00c1N)\n"
            "VERSION_ID=0.1.0\n"
            "VARIANT=installed\n"
            "ID=arch\n"
            "ID_LIKE=arch\n"
        ),
        # El os-release que decia el sistema instalado: el del paquete 'pacman'
        # que deja pacstrap. Es el estado en el que estaba antes del fallo 35.
        "usr/lib/os-release-arch": (
            "NAME=\"Arch Linux\"\n"
            "PRETTY_NAME=\"Arch Linux\"\n"
            "ID=arch\n"
            "BUILD_ID=rolling\n"
            "ANSI_COLOR=\"38;2;60;110;180\"\n"
        ),
        "etc/titan-release-live": (
            "NAME=Titan Linux\n"
            "VARIANT=live\n"
            "ID=arch\n"
        ),
        "boot/grub/grub.cfg": (
            "#\n"
            "# DO NOT EDIT THIS FILE\n"
            "#\n"
            "# It is automatically generated by grub-mkconfig using templates\n"
            "# from /etc/grub.d and settings from /etc/default/grub\n"
            "#\n"
            "### BEGIN /etc/grub.d/10_linux ###\n"
            "menuentry 'Titan Linux Linux, with Linux linux-titanlinux' --class "
            "titan --class gnu-linux --class gnu --class os $menuentry_id_option "
            "'gnulinux-linux-titanlinux-advanced-591cbf58-cc79-4848-a98b-4b3bae257dc5' {\n"
            "\trecordfail\n"
            "\tload_video\n"
            "\tinsmod gfxterm\n"
            "\tinsmod part_gpt\n"
            "\tinsmod btrfs\n"
            "\techo\t'Loading Linux linux-titanlinux ...'\n"
            "\tlinux\t/@/boot/vmlinuz-linux-titanlinux "
            "root=UUID=591cbf58-cc79-4848-a98b-4b3bae257dc5 rw rootflags=subvol=@ "
            "console=tty0 console=ttyS0,115200n8 loglevel=3\n"
            "\tinitrd\t/@/boot/initramfs-linux-titanlinux.img\n"
            "}\n"
            "### END /etc/grub.d/10_linux ###\n"
        ),
        # El repo/config REAL del flatpak 1.18.3 del disco instalado. La clave: el
        # remoto de Flathub vive aqui, no en 'remotes.d/', que es lo que hacia
        # funcionar mal la comprobacion vieja.
        "var/lib/flatpak/repo/config": (
            "[core]\n"
            "repo_version=1\n"
            "mode=bare-user-only\n"
            "min-free-space-size=500MB\n"
            "xa.applied-remotes=flathub;\n"
            "\n"
            "[remote \"flathub\"]\n"
            "url=https://dl.flathub.org/repo/\n"
            "xa.title=Flathub\n"
            "gpg-verify=true\n"
            "gpg-verify-summary=true\n"
            "xa.comment=Central repository of Flatpak applications\n"
        ),
        "var/lib/flatpak/repo/config-otro": (
            "[core]\n"
            "repo_version=1\n"
            "mode=bare-user-only\n"
            "xa.applied-remotes=gnome;\n"
            "\n"
            "[remote \"gnome\"]\n"
            "url=https://dl.gnome.org/flatpak/stable/\n"
        ),
        "var/lib/flatpak/app/org.mozilla.firefox/current/x86_64": "datos\n",
        "var/lib/flatpak/app/org.mozilla.firefox/.removed": "\n",
        "usr/lib/modules/6.18.54-1-titanlinux": None,
        # Y el segundo, el de Arch ('7.2.7-arch1-1'), que es lo que habia en el
        # disco instalado y lo que hacia que el equipo llevara dos kernels. Solo
        # se usa en los casos rotos, no en el arbol bueno.
        "usr/lib/modules-arch": None,
        "var/lib/pacman/local/linux-titanlinux-6.18.54-1": None,
        "var/lib/pacman/local/otro-paquete-1.0-1": None,
        "usr/share/gnome-shell": None,
        "usr/lib/systemd/system-generators/zram-generator": "generador\n",
        "etc/systemd/system/multi-user.target.wants/iwd.service": "enlace\n",
        "etc/systemd/system/multi-user.target.wants/NetworkManager.service": "enlace\n",
        "etc/systemd/system/multi-user.target.wants/remote-fs.target": "enlace\n",
        "etc/systemd/system/multi-user.target.wants/ufw.service": "enlace\n",
        "usr/bin/kitty": "kitty\n",
        "usr/bin/flatpak": "flatpak\n",
        "usr/bin/ufw": "ufw\n",
        "boot/grub/x86_64-efi/moddep.lst": "mod\n",
    }

    def con_arbol(base: pathlib.Path, cambios: dict[str, str | None]) -> pathlib.Path:
        """Monta un arbol de ficheros con el contenido dado (None = directorio).

        Los ficheros que el caso rompe se ponen los ultimos, para que pisen a los
        buenos: un caso es 'esto bien, esto roto', no dos arboles a la vez.

        'BORRAR' como contenido borra lo que hubiera (fichero o directorio
        entero). Hace falta porque hay comprobaciones que se ROMPEN quitando: si
        el kernel de Arch esta en el arbol bueno, la de 'no hay mas de un kernel'
        daria bien con dos kernels, que es justo lo que hay que cazar; y si el
        fichero del historial roto dice 'sin tmux' en un comentario, el 'grep' de
        'tmux' lo cuenta igual y la comprobacion daria bien sin historial.
        """
        import shutil as _shutil
        for relativo, contenido in cambios.items():
            destino = base / relativo
            if contenido == "BORRAR":
                if destino.is_dir():
                    _shutil.rmtree(destino, ignore_errors=True)
                else:
                    destino.unlink(missing_ok=True)
            elif contenido is None:
                destino.mkdir(parents=True, exist_ok=True)
            else:
                destino.parent.mkdir(parents=True, exist_ok=True)
                destino.write_text(contenido, encoding="utf-8")
        return base

    def corre(orden: str, raiz: pathlib.Path, efi: pathlib.Path | None = None,
              patron: str = "") -> tuple[bool, str]:
        """La orden del driver, tal cual, apuntando al arbol de pruebas.

        Como el driver, la salida que se mira es stdout MAS stderr (por la consola
        serie no se puede separar) y se exige que el patron case. El 'sudo' fuera
        porque aqui no hace falta ser root para mirar un arbol de ficheros, y el
        'sudo' en un fichero que no existe solo anade ruido.

        '/mnt/ve' (la ESP) se cambia ANTES que '/mnt/v', porque '/mnt/ve' empieza
        por '/mnt/v': al reves, el arbol de la ESP se acabaria buscando en un
        sitio que no existe, y la comprobacion dariia bien por el motivo
        equivocado.
        """
        if efi is not None:
            orden = orden.replace("/mnt/ve", str(efi))
        orden = orden.replace("/mnt/v", str(raiz))
        orden = re.sub(r"^sudo\s+", "", orden)
        proc = subprocess.run(["bash", "-c", orden], capture_output=True, text=True)
        salida = proc.stdout + proc.stderr
        return re.search(patron, salida, re.M) is not None, salida

    def orden_por_nombre(clave: str) -> tuple[str, str]:
        for nombre, orden, patron in checks:
            if clave in nombre:
                return orden, patron
        return "", ""

    def caso(clave: str, rotos: dict[str, str | None]) -> None:
        """Ejecuta una comprobacion de ficheros con los datos buenos y los rotos.

        Los datos buenos son los del arbol real de arriba, que se pasa entero
        siempre; lo que cambia en el caso son los ficheros rotos, que se anaden
        encima. Asi lo que hay que escribir para cada comprobacion es solo lo que
        se separa del arbol bueno.
        """
        orden, patron = orden_por_nombre(clave)
        if not orden:
            comprueba(f"la comprobacion de '{clave}' existe en el driver", False,
                      "no hay ninguna comprobacion con ese nombre")
            return
        with tempfile.TemporaryDirectory() as tmp:
            raiz_ok = pathlib.Path(tmp) / "ok"
            raiz_mal = pathlib.Path(tmp) / "mal"
            con_arbol(raiz_ok, ARBOL)
            con_arbol(raiz_mal, ARBOL)
            con_arbol(raiz_mal, rotos)
            bien, salida_ok = corre(orden, raiz_ok, patron=patron)
            comprueba(f"con los datos de verdad, '{clave}' da bien", bien,
                      "la orden no casa con su propio patron, y el patron no es de "
                      f"la orden. salida: {' '.join(salida_ok.split())[:110]!r}")
            mal, salida_mal = corre(orden, raiz_mal, patron=patron)
            comprueba(f"y con esos mismos datos rotos, '{clave}' da MAL", not mal,
                      "da bien con los datos rotos, y una comprobacion que no puede "
                      f"fallar no mide nada. salida: {' '.join(salida_mal.split())[:110]!r}")

    # El fstab de verdad, con sus tabuladores, es el que no tiene nada roto: la
    # linea de swap es lo que se anade para el caso de 'fstab NO tiene particiones
    # de swap'.
    fstab_real = ARBOL["etc/fstab"] or ""
    linea_swap = ("\n/dev/vda3 LABEL=swap\nUUID=b1a2c3d4-0000-0000-0000-000000000001"
                  "\tswap     \tsw              \t0 0\n")
    caso("fstab NO tiene particiones de swap", {"etc/fstab": fstab_real + linea_swap})
    # Y la raiz sin 'subvol=/@', que es lo que hace que un btrfs con subvolumenes
    # monte el subvolumen equivocado (el de arriba) y no se pueda escribir en
    # /home.
    caso("fstab monta la raiz con su subvolumen",
         {"etc/fstab": fstab_real.replace(",subvol=/@", ",")})
    # Y la particion de arranque repetida, que es lo que hace que el montaje de la
    # ESP se quede colgado en el instalador.
    caso("fstab no repite la particion de arranque",
         {"etc/fstab": fstab_real + "\n" + fstab_real.splitlines()[-1] + "\n"})
    # Y el idioma con UN solo campo, que es el fallo 32 entero.
    caso("el idioma pedido esta en locale.gen",
         {"etc/locale.gen": ARBOL["etc/locale-gen-roto"]})
    caso("locale.conf apunta al idioma pedido", {"etc/locale.conf": "C.UTF-8\n"})
    caso("el teclado es el de espana en la consola",
         {"etc/vconsole.conf": "KEYMAP=us\n"})
    # Y la identidad que decia 'Arch Linux', que es el fallo 35 entero.
    caso("el sistema instalado se identifica como Titan Linux",
         {"usr/lib/os-release": ARBOL["usr/lib/os-release-arch"]})
    caso("el sistema instalado tiene su fichero titan-release",
         {"etc/titan-release": ARBOL["etc/titan-release-live"]})
    # Y el remoto de Flathub en otro sitio, que es lo que hacia dar error a la
    # comprobacion vieja de 'remotes.d/'.
    caso("la tienda trae flathub anadido",
         {"var/lib/flatpak/repo/config": ARBOL["var/lib/flatpak/repo/config-otro"]})
    # Y un 'video=' en el arranque, que es justo lo que el proyecto no quiere: la
    # tarjeta decide el modo de video.
    grub_real = ARBOL["boot/grub/grub.cfg"] or ""
    caso("el arranque NO lleva video=",
         {"boot/grub/grub.cfg": grub_real.replace("console=tty0",
                                                  "video=vesa:1920x1080 console=tty0")})
    caso("grub.cfg apunta al kernel de titanlinux",
         {"boot/grub/grub.cfg": grub_real.replace("linux-titanlinux", "linux")})
    caso("grub.cfg esta generado y no vacio", {"boot/grub/grub.cfg": ""})
    # Y el usuario que no existe, que no esta en wheel, que no puede usar sudo y un
    # root sin contrasena, que es como se queda el equipo si el instalador se para
    # a mitad de la fase de cuentas.
    caso("el usuario existe", {"etc/passwd": "root:x:0:0:root:/root:/bin/bash\n"})
    caso("el usuario esta en el grupo wheel", {"etc/group": "root:x:0:\nwheel:x:998:\n"})
    caso("el usuario puede usar sudo sin contrasena",
         {"etc/sudoers.d/10-titan": "isai ALL=(ALL:ALL) PASSWD: ALL\n"})
    caso("root TIENE contrasena", {"etc/shadow": "root:*:20724::::::\n"})
    # Y dos kernels (el del proyecto y el de Arch, que es lo que se vio en el
    # disco), o ninguno.
    # Y dos kernels, o ninguno. Para el segundo hace falta el kernel de Arch, que
    # se nombra aparte porque en el arbol bueno NO esta (si estuviera, la
    # comprobacion 'no hay mas de un kernel' daria bien con dos, que es el fallo).
    caso("no hay mas de un kernel", {"usr/lib/modules-arch": None,
                                     "usr/lib/modules/7.2.7-arch1-1": None})
    caso("hay un modulo de kernel titanlinux", {"usr/lib/modules/6.18.54-1-titanlinux":
                                                "BORRAR"})
    # Y sin el paquete del kernel en la lista de pacman, que es como se ve que
    # el kernel propio se instalo de verdad y no de rebote.
    caso("el kernel propio esta en la lista de paquetes",
         {"var/lib/pacman/local/linux-titanlinux-6.18.54-1": "BORRAR"})
    # Y el historial de la consola, que se comprueba con un 'grep' de una palabra
    # que sale en los comentarios del script: un fichero sin ella tiene que dar
    # mal.
    # OJO con el fichero roto: no puede ni de lejos llevar la palabra que se
    # busca, ni en un comentario, porque el 'grep' de la comprobacion la
    # contaria igual. Por eso aqui no hay ni una 't' suelta de alias.
    caso("la consola de texto tiene historial",
         {"etc/profile.d/20-titan-scrollback.sh":
          "# historial de la consola de texto\ntrue\n"})
    # Y la tienda sin apps, que es lo que pasa si el paso de flatpak falla. Y el
    # ufw que se activa solo, que es lo que el proyecto no quiere (va instalado,
    # pero apagado, y que lo active el usuario cuando quiera).
    caso("hay apps instaladas de la tienda",
         {"var/lib/flatpak/app": "BORRAR", "var/lib/flatpak/app/": None})
    caso("las apps de la tienda son las del tipo de uso",
         {"var/lib/flatpak/app/org.mozilla.firefox": "BORRAR",
          "var/lib/flatpak/app/org.kde.dolphin": None})
    # Y la particion EFI, que se mira en OTRO arbol (/mnt/ve), en el que /mnt/v no
    # aparece: con el '/mnt/v' cambiado antes que el '/mnt/ve', estas
    # comprobaciones darian bien mirando un sitio vacio.
    for clave, fichero in (("la particion EFI tiene el arranque de UEFI",
                             "EFI/TitanLinux/grubx64.efi"),
                            ("la particion EFI tiene el arranque de BIOS",
                             "EFI/BOOT/BOOTX64.EFI")):
        orden, patron = orden_por_nombre(clave)
        if not orden:
            comprueba(f"la comprobacion de '{clave}' existe en el driver", False,
                      "no hay ninguna comprobacion con ese nombre")
            continue
        with tempfile.TemporaryDirectory() as tmp:
            raiz_ok = pathlib.Path(tmp) / "ok"
            raiz_mal = pathlib.Path(tmp) / "mal"
            con_arbol(raiz_ok, ARBOL)
            con_arbol(raiz_mal, ARBOL)
            efi_ok = pathlib.Path(tmp) / "efi-ok"
            efi_mal = pathlib.Path(tmp) / "efi-mal"
            con_arbol(efi_ok, {fichero: "efi\n"})
            con_arbol(efi_mal, {"EFI": None})
            bien, _salida = corre(orden, raiz_ok, efi_ok, patron)
            comprueba(f"con la ESP de verdad, '{clave}' da bien", bien,
                      "la orden no casa con su propio patron")
            mal, salida_mal = corre(orden, raiz_mal, efi_mal, patron)
            comprueba(f"y con la ESP vacia, '{clave}' da MAL", not mal,
                      "da bien sin el arranque, y eso es mirar '/mnt/ve' en el sitio "
                      f"equivocado. salida: {' '.join(salida_mal.split())[:110]!r}")

    print()
    print("== 12. las comprobaciones del ARRANQUE, con ordenes de verdad ==")
    # Las 14 comprobaciones de la fase 5 no miran ficheros del disco instalado (el
    # sistema ya ha arrancado), sino ordenes ejecutadas DENTRO del sistema
    # arrancado. Para probarlas sin QEMU se les pone delante un directorio con
    # falseadores de 'swapon', 'locale', 'flatpak' y 'fastfetch' que sueltan la
    # salida REAL de un arranque de verdad, y se ejecutan de verdad.
    #
    # Y al final, la parte que mas importa: las ordenes y los patrones VIEJOS, los
    # que se llevaron un FALLO en la primera pasada completa, tienen que dar MAL
    # con estos mismos datos. Si alguna de las viejas pasara, el fallo no estaria
    # en la comprobacion nueva sino en que se habria arreglado de mentira, y eso
    # solo se ve mirando las dos.
    FALSOS: dict[str, str] = {
        # Salida REAL de 'swapon --show' del sistema instalado con zram (leida del
        # registro de un arranque de verdad: la cabecera, y '/dev/zram0' debajo).
        "swapon": r"""#!/bin/sh
case "${TITAN_ZRAM:-bien}" in
  sin-zram) printf 'NAME       TYPE      SIZE USED PRIO\n' ;;
  nada)     : ;;
  *)        printf 'NAME       TYPE      SIZE USED PRIO\n'
             printf '/dev/zram0 partition 1.9G   0B  100\n' ;;
esac
""",
        # 'locale -a' REAL del disco instalado: con el idioma, y sin el (que es lo
        # que contestaba antes del fallo 32: 'C.utf8' y nada mas).
        "locale": r"""#!/bin/sh
case "${TITAN_IDIOMA:-bien}" in
  sin-es) printf 'C\nC.utf8\nPOSIX\n' ;;
  *)      printf 'C\nC.utf8\nPOSIX\nes_ES.utf8\n' ;;
esac
""",
        # 'flatpak' REAL. Con '--system --columns=name' imprime una linea por
        # remoto. Sin '--system' (que es lo que hacia la comprobacion vieja) el
        # flatpak de verdad va a por la instalacion del USUARIO, que en el arranque
        # recien instalado esta rota, y contesta por stderr:
        #     error: While opening repository /home/isai/.local/share/flatpak/repo
        # y en stdout no queda NADA, que es lo que hace que la cuenta salga 0
        # aunque el remoto este ahi.
        "flatpak": r"""#!/bin/sh
# Con '--system' contesta la instalacion del SISTEMA, que es la que deja el
# instalador (con 'flatpak remote-add --system'). Sin '--system' contesta la del
# USUARIO, y en un arranque recien instalado esa esta rota: el instalador corrio
# flatpak como root dentro del chroot, la de 'isai' nunca llego a crearse bien, y
# el flatpak de verdad contesta por stderr
#     error: While opening repository /home/isai/.local/share/flatpak/repo
# sin dejar NADA en stdout. Con '2>/dev/null' eso es un cero, que es lo que hacia
# que la comprobacion vieja saliera en rojo teniendo el remoto puesto.
case "$*" in
  *--system*)
    case "${TITAN_PLAZA:-puesto}" in
      vacio)  exit 0 ;;
      tabla)  printf 'Name    Options\nflathub\n' ;;
      *)      printf 'flathub\n' ;;
    esac ;;
  *)
    case "${TITAN_USUARIO:-roto}" in
      bueno)  printf 'Name    Options\nflathub\n' ;;
      *)      echo "error: While opening repository /home/isai/.local/share/flatpak/repo: No such file or directory" >&2
               exit 1 ;;
    esac ;;
esac
""",
        # fastfetch REAL. Y el detalle que hizo fallar la comprobacion vieja: el
        # rotulo sale en el idioma del sistema, y en espanol es 'Sistema:', no
        # 'OS:'. Con LC_ALL=C sale 'OS:'. Leido de un arranque de verdad.
        "fastfetch": "#!/bin/sh\n"
        "if [ \"${LC_ALL:-}\" = \"C\" ]; then\n"
        r"  printf 'OS: Titan Linux 0.1.0 (TIT\303\211N) x86_64\n'" "\n"
        "  printf 'Host: titan\n'\n"
        "  printf 'Kernel: 6.18.54-1-titanlinux\n'\n"
        "else\n"
        r"  printf 'Sistema: Titan Linux 0.1.0 (TIT\303\211N) x86_64\n'" "\n"
        "  printf 'Anfitrion: titan\n'\n"
        "  printf 'Nucleo: 6.18.54-1-titanlinux\n'\n"
        "fi\n",
    }

    def con_falsos(orden: str, patron: str, falso_bin: pathlib.Path,
                   entorno: dict[str, str]) -> tuple[bool, str]:
        """Ejecuta la orden con los falseadores delante del PATH, como el driver."""
        env = dict(os.environ)
        env.update(entorno)
        env["PATH"] = f"{falso_bin}:{os.environ['PATH']}"
        proc = subprocess.run(["bash", "-c", orden], capture_output=True, text=True,
                              env=env)
        salida = proc.stdout + proc.stderr
        return re.search(patron, salida, re.M) is not None, salida

    def arranque_por_clave(clave: str) -> tuple[str, str]:
        for nombre, orden, patron in arranque:
            if clave in nombre:
                return orden, patron
        return "", ""

    with tempfile.TemporaryDirectory() as tmp:
        falso_bin = pathlib.Path(tmp) / "falsos"
        falso_bin.mkdir(parents=True, exist_ok=True)
        for nombre, cuerpo in FALSOS.items():
            destino = falso_bin / nombre
            destino.write_text(cuerpo, encoding="utf-8")
            destino.chmod(0o755)

        # --- las comprobaciones del arranque, con la salida real de verdad ----
        for clave, etiqueta, rompes in (
            ("el swap de memoria esta activo", "el swap de memoria", "TITAN_ZRAM"),
            ("el idioma pedido esta disponible", "el idioma disponible",
             "TITAN_IDIOMA"),
            ("la tienda tiene flathub", "el remoto de Flathub", "TITAN_PLAZA"),
        ):
            orden, patron = arranque_por_clave(clave)
            if not orden:
                comprueba(f"la comprobacion de '{clave}' existe", False,
                          "no esta en comprobaciones_arranque()")
                continue
            bien, salida = con_falsos(orden, patron, falso_bin, {rompes: "bien"})
            comprueba(f"con la salida REAL, {etiqueta} da bien", bien,
                      f"orden={orden!r} patron={patron!r} "
                      f"salida={salida.strip()[:80]!r}")
            if clave.startswith("la tienda"):
                # Y que el patron no dependa de la cabecera: hay versiones de
                # flatpak que la traen y otras que no, y el check tiene que dar
                # bien con las dos formas.
                bien_tabla, _s = con_falsos(orden, patron, falso_bin,
                                            {"TITAN_PLAZA": "tabla"})
                comprueba("y con flatpak imprimiendo una tabla con cabecera, "
                          "el remoto tambien da bien", bien_tabla,
                          "el patron no puede depender de que flatpak traiga o no la "
                          "cabecera: hay versiones que la traen y otras que no")
                # Y el caso que de verdad hacia fallar a la comprobacion vieja: el
                # remoto puesto en la instalacion del USUARIO (donde lo deja un
                # 'flatpak remote-add' sin '--system') y no en la del sistema. Ahi
                # el flatpak del usuario contesta bien, y aun asi el sistema
                # instalado no tiene el remoto: la comprobacion tiene que dar MAL
                # porque mira la del sistema.
                mal_usuario, _s = con_falsos(orden, patron, falso_bin,
                                              {"TITAN_PLAZA": "vacio",
                                               "TITAN_USUARIO": "bueno"})
                comprueba("y con el remoto solo en la instalacion del usuario, "
                          "da MAL (fallo 28)", not mal_usuario,
                          "da bien con el remoto en la del usuario, que es donde lo "
                          "pone un 'remote-add' sin '--system'")
                mal_vacio, _s = con_falsos(orden, patron, falso_bin,
                                           {"TITAN_PLAZA": "vacio"})
                comprueba("y si no hay remoto, da MAL", not mal_vacio,
                          "da bien sin ningun remoto")
            else:
                clave_mala = {"TITAN_ZRAM": "sin-zram", "TITAN_IDIOMA": "sin-es"}[rompes]
                mal, salida_mal = con_falsos(orden, patron, falso_bin, {rompes: clave_mala})
                comprueba(f"y sin lo que mira, {etiqueta} da MAL", not mal,
                          f"da bien sin nada. salida: {salida_mal.strip()[:80]!r}")

        orden, patron = arranque_por_clave("fastfetch funciona")
        if not orden:
            comprueba("la comprobacion de fastfetch existe", False,
                      "no esta en comprobaciones_arranque()")
        else:
            bien, salida = con_falsos(orden, patron, falso_bin, {})
            comprueba("con el fastfetch REAL en LC_ALL=C, da bien", bien,
                      f"orden={orden!r} patron={patron!r} salida={salida.strip()[:80]!r}")
            # Y que lo unico que lo hace dar bien sea el 'LC_ALL=C' de la orden, y
            # no que el patron sepa los dos idiomas. Sin ese prefijo, el fastfetch
            # de verdad rotula 'Sistema:' en un sistema en espanol (leido de un
            # arranque de verdad) y 'OS:' solo con el idioma forzado a C. Por eso
            # el 'LC_ALL=C' va en la ORDEN y no en el patron.
            sin_lc, salida_sin_lc = con_falsos(orden.replace("LC_ALL=C ", ""),
                                               patron, falso_bin, {})
            comprueba("y sin el 'LC_ALL=C' de la orden, el patron ya no casa", not sin_lc,
                      "da bien sin forzar el idioma, y entonces el rotulo en espanol "
                      f"('Sistema:') haria que la comprobacion fallara sola. "
                      f"salida: {salida_sin_lc.strip()[:80]!r}")

        # --- y las ordenes y patrones VIEJOS, que tienen que dar MAL ---------
        # Cada una con lo que de verdad tenia antes del arreglo. Todas salian en
        # rojo en la primera pasada completa, y el arreglo no vale si no es la
        # orden la que cambia.
        VIEJAS = [
            ("el idioma, mirando un directorio que no existe",
             "ls {raiz}/usr/lib/locale/es_ES.utf8/LC_MESSAGES 2>/dev/null "
             "| grep -c '\\.mo$'", r"^[1-9]", "",
             "el idioma generado esta en el archivo 'locale-archive' de glibc 2.41, "
             "no en un directorio: 'ls' no lo puede encontrar nunca"),
            ("el idioma, contando los '.mo' de un idioma equivocado",
             "ls {raiz}/usr/lib/locale/es_ES/LC_MESSAGES 2>/dev/null "
             "| grep -c '\\.mo$'", r"^[1-9]", "",
             "este si podria dar bien, pero con el idioma equivocado, que es peor que "
             "dar rojo"),
            ("fstab, buscando la raiz con un espacio alrededor",
             "grep ' / ' {raiz}/etc/fstab 2>/dev/null | grep -c 'subvol=/@$'",
             r"^1$", "",
             "el fstab del instalador separa con tabuladores, y ' / ' no aparece en "
             "ninguna linea"),
            ("fstab, buscando /boot con un espacio alrededor",
             "grep -c ' /boot ' {raiz}/etc/fstab 2>/dev/null", r"^1$", "",
             "la ESP se monta en '/boot/efi', no en '/boot'"),
            ("el remoto de Flathub, mirando 'remotes.d/'",
             "ls {raiz}/var/lib/flatpak/remotes.d/ 2>/dev/null", r"(?m)^flathub$", "",
             "el flatpak 1.18.3 no usa 'remotes.d/': el remoto esta en el 'config' "
             "del repositorio"),
            ("el remoto de Flathub, preguntando por la instalacion del usuario",
             "flatpak remotes 2>/dev/null | grep -cx flathub", r"^1$", {},
             "sin '--system' el flatpak va a por la instalacion del usuario, que en "
             "un arranque recien instalado esta rota: contesta por stderr y en stdout "
             "no queda nada, que es lo que hacia que la cuenta saliera 0"),
            ("el swap, con la cabecera de 'swapon --show'",
             "swapon --show 2>/dev/null | head -1", r"(?m)^\S+zram\S* ",
             {"TITAN_ZRAM": "bien"},
             "solo con 'head -1', que devuelve SIEMPRE la cabecera: con zram y sin "
             "zram da exactamente lo mismo, y el patron no la veria nunca"),
            ("el nombre del sistema, con fastfetch sin LC_ALL",
             "fastfetch --logo none 2>/dev/null | head -2", r"(?m)^OS: Titan Linux",
             {"TITAN_PLAZA": "puesto"},
             "sin 'LC_ALL=C' el rotulo sale como 'Sistema:' en un sistema en espanol, "
             "y 'OS: Titan Linux' no aparece"),
        ]
        for etiqueta, orden_vieja, patron_viejo, extra, por_que in VIEJAS:
            with tempfile.TemporaryDirectory() as arbol_tmp:
                raiz = pathlib.Path(arbol_tmp)
                con_arbol(raiz, ARBOL)
                # El 'locale-archive' es lo que hay de verdad en un sistema con
                # glibc 2.41, y es el motivo de que buscar un directorio por idioma
                # no pueda dar bien nunca.
                con_arbol(raiz, {"usr/lib/locale/locale-archive": "datos\n"})
                real = (orden_vieja.format(raiz=str(raiz)) if "{raiz}" in orden_vieja
                        else orden_vieja)
                ok_vieja, salida = con_falsos(real, patron_viejo, falso_bin, extra)
                comprueba(f"la comprobacion VIEJA '{etiqueta}' da MAL con datos reales",
                          not ok_vieja,
                          f"da bien con la salida {salida.strip()[:80]!r}: el fallo no "
                          f"estaba solo en el patron, y el arreglo no seria real. "
                          f"por que: {por_que}")

    print("== 13. el tipo del disco y el montaje, con la consola de verdad ==")
    # El fallo U: el driver leia el tipo de la particion con
    # 'limpio(sal).split()[-1]', es decir con el ULTIMO token de lo que salio por
    # la consola. En la pasada del 28 de septiembre eso no era 'btrfs' sino
    # 'titan@38', y el driver montaba la particion entera: el nivel de arriba de
    # un btrfs con subvolumenes, que esta vacio. Las 29 comprobaciones de la
    # fase 4 dijeron que el sistema instalado no existia cuando si que existia (y
    # arrancaba: las 14 de la fase 6 dieron bien todas).
    #
    # Aqui el bloque de la consola no esta inventado: es el que llego por el
    # socket de serie en esa pasada, byte a byte, con los '\\r' del ONLCR, los
    # marcadores OSC 8 de la integracion de la shell y el escape CSI que se
    # quedo A MEDIAS al final ('\\x1b[38' y se acabo la lectura). Lo que se le
    # pasa al codigo no se escribe a mano: sale de pasarlo por el 'plano()' y
    # por el filtro de lineas de 'run()' de verdad, que es lo que la hizo.
    BUF_REAL = (
        "sudo blkid -s TYPE -o value /dev/vda2 ; echo __TITAN_DONE_33__\"\"\n"
        "\x1b[?2004l\n"
        "\x1b]3008;start=9aaa782a-98b4-401c-af87-d35060a635d0;type=command;machineid=f9ce1126a5be4717a9163927b39d32b9;user=titan;hostname=titan;bootid=91577ea3-00e8-477b-bb6b-fe1a16590564;pid=566;cwd=/home/titan\x1b\\\x1b]3008;start=16c92162036f44ac8fa48098e8fad6ab;user=titan;hostname=titan;machineid=f9ce1126a5be4717a9163927b39d32b9;bootid=91577ea300e8477bbb6bfe1a16590564;pid=17073;pidfdid=17074;comm=sudo;targetuser=root;type=session\x1b\\btrfs\n"
        "\x1b]3008;end=16c92162036f44ac8fa48098e8fad6ab\x1b\\__TITAN_DONE_33__\n"
        "\x1b]3008;end=9aaa782a-98b4-401c-af87-d35060a635d0;exit=success\x1b\\\x1b]3008;start=e2252e58-dd91-4b41-8750-d8e037dac918;type=shell;machineid=f9ce1126a5be4717a9163927b39d32b9;user=titan;hostname=titan;bootid=91577ea3-00e8-477b-bb6b-fe1a16590564;pid=566;cwd=/home/titan\x1b\\\x1b[?2004h\x1b[38;2;56;214;255mtitan\x1b[38;2;120;132;150m@\x1b[38\n"
    )
    # La pregunta nueva es distinta ('lsblk' con un 'sed' delante), asi que la
    # respuesta que se le atribuye es la que daria ese 'sed'. Todo lo demas --el
    # eco, los marcadores, el escape a medias-- se queda igual, porque eso es lo
    # que estaba en la consola y es lo que rompia la lectura.
    BUF_NUEVO = BUF_REAL.replace("btrfs\n", "FSTYPE=btrfs\n", 1)
    tv = cargar_consola()
    sal_real = respuesta_de_consola(tv, BUF_NUEVO, "__TITAN_DONE_33__")
    sal_viejo = respuesta_de_consola(tv, BUF_REAL, "__TITAN_DONE_33__")

    # Lo primero, que el fixture es el que de verdad: con el texto REAL, la
    # forma vieja (el ultimo token) da otra cosa, y con la nueva da 'btrfs'.
    # Si esto no se cumple, el resto de la seccion estaria probando un caso que
    # no es el que fallo, que es el error mas caro que se puede cometer aqui.
    comprueba("el texto de la consola REAL trae 'btrfs' en su linea",
              any(line.strip() == "btrfs"
                  for line in sal_viejo.splitlines()),
              f"la respuesta real sale {sal_viejo!r}")
    comprueba("y con el ultimo token NO sale 'btrfs' (por eso el fallo 29)",
              viejo_tipo(mod, sal_viejo) != "btrfs",
              f"la forma vieja daria {viejo_tipo(mod, sal_viejo)!r}: con este texto "
              f"el fallo no se reproduce y la seccion no probaria nada")
    comprueba("el texto que recibe el driver lleva la respuesta EN MEDIO, no al final",
              sal_real.split() and sal_real.split()[0] == "FSTYPE=btrfs",
              f"la respuesta sale {sal_real!r}")

    # Y ya con el codigo de verdad.
    comprobable = mod.tipo_de(ConsolaFalsa(sal_real, {}), "/dev/vda2")
    comprueba("el tipo se lee con la respuesta real sucia", comprobable == "btrfs",
              f"tipo_de devuelve {comprobable!r} con el texto {sal_real!r}")
    comprobable = mod.tipo_de(ConsolaFalsa("\nFSTYPE=btrfs\n", {}), "/dev/vda2")
    comprueba("el tipo se lee con la respuesta limpia", comprobable == "btrfs",
              f"tipo_de devuelve {comprobable!r}")
    comprobable = mod.tipo_de(ConsolaFalsa("\ntitan@38\n", {}), "/dev/vda2")
    comprueba("y si la respuesta no esta, el tipo NO es cualquier cosa",
              comprobable == "", f"tipo_de devuelve {comprobable!r}")
    comprobable = mod.tipo_de(ConsolaFalsa("\nXFSTYPE=btrfs\n", {}), "/dev/vda2")
    comprueba("ni de otra palabra que acabe igual (el prefijo va pegado)",
              comprobable == "", f"tipo_de devuelve {comprobable!r}")

    # El arbol montado: la comprobacion que hace ruidoso el fallo mudo. Se
    # registrandolo a mano en el doble, que es como se ve de verdad (lo que hay
    # montado en un punto es cosa del 'mount', no del 'test').
    vacio = ConsolaFalsa("", {})
    vacio.montado["/mnt/v"] = False        # el nivel de arriba de btrfs
    comprueba("un arbol sin /usr ni /etc NO es el arbol de un sistema instalado",
              not mod.arbol_de_sistema(vacio, "/mnt/v"),
              "un arbol vacio se ha tomado por el sistema instalado")
    con_arbol = ConsolaFalsa("", {})
    con_arbol.montado["/mnt/v"] = True
    comprueba("un arbol con /usr y /etc SI lo es",
              mod.arbol_de_sistema(con_arbol, "/mnt/v"),
              "el arbol del sistema no se ha reconocido")
    # Y con un disco VACIO de verdad, que es lo que hay si el montaje se fue al
    # carajo: tampoco puede ser el arbol del sistema instalado.
    comprueba("y un punto de montaje sin nada tampoco",
              not mod.arbol_de_sistema(ConsolaFalsa("", {}), "/mnt/v"),
              "un punto de montaje vacio se ha tomado por el sistema instalado")

    # El montaje entero, con btrfs y subvolumenes (el caso de verdad).
    montajes_btrfs = {
        "subvol=@ /dev/vda2 /mnt/v": (True, True),
        "subvol=@var /dev/vda2 /mnt/v/var": (True, True),
        "subvol=@home /dev/vda2 /mnt/v/home": (True, True),
    }
    consola = ConsolaFalsa(sal_real, montajes_btrfs)
    bien, motivo = mod.montar_destino(consola, "/dev/vda2")
    montajes_enviados = [c for c in consola.llamadas if " mount " in f" {c} "]
    comprueba("con btrfs y la respuesta sucia, monta el arbol del sistema", bien,
              f"motivo: {motivo}")
    comprueba("y lo monta con subvol=@, que es lo que se estaba perdiendo",
              montajes_enviados and "subvol=@" in montajes_enviados[0],
              f"los montajes fueron {montajes_enviados}")
    comprueba("y monta tambien @var y @home, que son subvolumenes aparte",
              any("subvol=@var" in c for c in montajes_enviados)
              and any("subvol=@home" in c for c in montajes_enviados),
              f"los montajes fueron {montajes_enviados}")
    comprueba("y no monta la particion entera si no hace falta",
              not any(c.strip().startswith("sudo mount /dev/vda2 /mnt/v &&")
                      for c in montajes_enviados),
              f"los montajes fueron {montajes_enviados}")

    # Lo que mas importa: cuando el tipo NO se sabe, el driver tiene que
    # corregir solo. Antes, un tipo mal leido era un fallo silencioso; ahora es un
    # 'False' con su motivo, o un montaje bien.
    consola = ConsolaFalsa("\ntitan@38\n", montajes_btrfs)
    bien, motivo = mod.montar_destino(consola, "/dev/vda2")
    comprueba("sin saber el tipo, monta igualmente el arbol del sistema", bien,
              f"motivo: {motivo}")
    consola = ConsolaFalsa("\ntitan@38\n", montajes_btrfs)
    bien, motivo = mod.montar_destino(consola, "/dev/vda2")
    montajes_enviados = [c for c in consola.llamadas if " mount " in f" {c} "]
    comprueba("y prueba el subvolumen el primero, que es el que falla en silencio",
              montajes_enviados and "subvol=@" in montajes_enviados[0],
              f"los montajes fueron {montajes_enviados}")

    # El fallo mudo convertido en ruido: NINGUN montaje da el arbol del sistema
    # (el nivel de arriba de btrfs monta bien y esta vacio). El driver tiene que
    # decirlo, no devolver True y dejar que 29 comprobaciones digan 'no existe'.
    solo_el_nivel_de_arriba = {
        "subvol=@ /dev/vda2 /mnt/v": (True, False),
        "mount /dev/vda2 /mnt/v": (True, False),
        "subvol=@var /dev/vda2 /mnt/v/var": (True, False),
        "subvol=@home /dev/vda2 /mnt/v/home": (True, False),
    }
    consola = ConsolaFalsa(sal_real, solo_el_nivel_de_arriba)
    bien, motivo = mod.montar_destino(consola, "/dev/vda2")
    comprueba("si el arbol montado no es el del sistema, lo dice (no es un True)",
              not bien, f"ha devuelto True con el motivo {motivo!r}: el fallo "
                        f"silencioso del fallo 29 sigue que sigue aqui")
    comprueba("y el motivo explica que el arbol no es el del sistema instalado",
              "sistema instalado" in motivo, f"el motivo es {motivo!r}")
    comprueba("y suelta lo que habia montado antes de probar otra cosa",
              any("umount" in c for c in consola.llamadas),
              f"las ordenes fueron {consola.llamadas}")

    # Un btrfs SIN subvolumenes: 'subvol=@' se queja y el plano sirve. Es el caso
    # en el que el arbol bien esta y el primer candidato falla, al reves.
    btrfs_plano = {
        "subvol=@ /dev/vda2 /mnt/v": (False, False),
        "mount /dev/vda2 /mnt/v": (True, True),
    }
    consola = ConsolaFalsa(sal_real, btrfs_plano)
    bien, motivo = mod.montar_destino(consola, "/dev/vda2")
    comprueba("un btrfs sin subvolumenes se monta entero y se reconoce", bien,
              f"motivo: {motivo}")

    # Y un disco que no es btrfs: el subvolumen no se intenta siquiera, que en la
    # consola es ruido que no hace falta.
    consola = ConsolaFalsa("\nFSTYPE=ext4\n", {"mount /dev/vda2 /mnt/v": (True, True)})
    bien, motivo = mod.montar_destino(consola, "/dev/vda2")
    montajes_enviados = [c for c in consola.llamadas if " mount " in f" {c} "]
    comprueba("un disco normal se monta entero y bien", bien, f"motivo: {motivo}")
    comprueba("y sin intentar subvol=@, que en un ext4 solo da error",
              all("subvol" not in c for c in montajes_enviados),
              f"los montajes fueron {montajes_enviados}")

    print()
    print("== 14. lo que mira el disco, en UEFI y en BIOS, y en las dos direcciones ==")
    # Fallo 39 (29 de septiembre, 01:52, la primera pasada entera por BIOS). Tres
    # comprobaciones del driver dieron FALLO con el sistema instalado entero y
    # bien, y las tres por lo mismo: eran comprobaciones de UEFI que se
    # ejecutaban tambien en BIOS.
    #
    #   1. "el disco tiene una particion vfat": en BIOS NO hay particion de
    #      arranque (el cargador va en el hueco del MBR y el 'bios_grub' no se
    #      monta nunca), asi que pedia algo que el particionado de BIOS no crea.
    #   2. "hay modulos de grub en el disco" miraba siempre
    #      '/boot/grub/x86_64-efi', y en BIOS los modulos que instala GRUB son los
    #      de 'i386-pc'.
    #   3. "fstab no repite la particion de arranque" contaba las lineas de
    #      '/boot/efi' y exigia exactamente una; en BIOS el fstab no tiene
    #      ninguna.
    #
    # Lo que se mira aqui, con las dos listas REALES que devuelve
    # 'comprobaciones_instalado()' y no con el texto del codigo:
    #
    #   * que cada lista mire el directorio de modulos de SU modo, y que ninguna
    #     mire el del otro (el fallo 2 era justo eso: la de BIOS mirando el de
    #     UEFI);
    #   * que la comprobacion de los modulos este UNA vez en cada lista, y no dos
    #     veces en una;
    #   * que lo de la particion EFI (vfat, '/EFI', 'efibootmgr') este en UEFI y
    #     no aparezca en BIOS, y que el MBR sea al reves;
    #   * que el patron de la cuenta de '/boot/efi' valga 1 en UEFI y 0 en BIOS;
    #   * que las comprobaciones que estan en las DOS listas tengan la MISMA
    #     orden, porque una orden que cambia con el modo sin querer hace que la
    #     comprobacion mire otra cosa en uno de los dos, y el nombre es el mismo,
    #     que es lo que lo esconde;
    #   * y que 'anota_particiones()' de bien y mal en los DOS modos y con las
    #     DOS respuestas del disco, que es lo que la lista no puede ver (la
    #     particion de arranque se anota fuera de 'comprobaciones_instalado()').
    checks_uefi = mod.comprobaciones_instalado("/dev/vda2", "/dev/vda1", False)
    checks_bios = mod.comprobaciones_instalado("/dev/vda2", "", True)
    nombres_uefi = [n for n, _, _ in checks_uefi]
    nombres_bios = [n for n, _, _ in checks_bios]
    ordenes_uefi = [o for _, o, _ in checks_uefi]
    ordenes_bios = [o for _, o, _ in checks_bios]

    def con(lista: list, texto: str) -> list[str]:
        """Los NOMBRES de las comprobaciones cuya orden (o cuyo nombre) tiene el texto."""
        return [n for n, o, _ in lista if texto in o or texto in n]

    mod_uefi = con(checks_uefi, "x86_64-efi")
    mod_bios = con(checks_bios, "i386-pc")
    comprueba("en UEFI se miran los modulos de GRUB de UEFI", len(mod_uefi) == 1,
              f"los que la miran: {mod_uefi}")
    comprueba("en BIOS se miran los modulos de GRUB de BIOS", len(mod_bios) == 1,
              f"los que la miran: {mod_bios}")
    comprueba("en UEFI nadie mira los modulos de BIOS", not con(checks_uefi, "i386-pc"),
              f"y aparece en: {con(checks_uefi, 'i386-pc')}")
    comprueba("en BIOS nadie mira los modulos de UEFI", not con(checks_bios, "x86_64-efi"),
              f"y aparece en: {con(checks_bios, 'x86_64-efi')}")
    comprueba("los nombres de los modulos de GRUB dicen el modo",
              any("UEFI" in n for n in mod_uefi) and any("BIOS" in n for n in mod_bios),
              f"en UEFI: {mod_uefi}; en BIOS: {mod_bios}")

    # Lo de la particion EFI, que es de donde vino el primer FALLO de BIOS.
    efi_uefi = sorted(set(con(checks_uefi, "efibootmgr")) | set(con(checks_uefi, "/EFI/"))
                      | set(con(checks_uefi, "vfat (EFI)")))
    efi_bios = sorted(set(con(checks_bios, "efibootmgr")) | set(con(checks_bios, "/EFI/"))
                      | set(con(checks_bios, "vfat (EFI)")))
    comprueba("en UEFI se mira la particion EFI y lo que hay dentro", len(efi_uefi) == 4,
              f"son {efi_uefi}")
    comprueba("en BIOS no se mira ninguna particion EFI", not efi_bios,
              f"y aparecen: {efi_bios}")
    mbr_uefi = [n for n in nombres_uefi if "MBR" in n]
    mbr_bios = [n for n in nombres_bios if "MBR" in n]
    comprueba("en BIOS se mira el hueco de arranque del MBR", len(mbr_bios) == 1,
              f"son {mbr_bios}")
    comprueba("y en UEFI no se mira el MBR", not mbr_uefi, f"y aparece en {mbr_uefi}")

    # La cuenta de '/boot/efi' del fstab: una en UEFI, ninguna en BIOS.
    def patron_de(lista: list, nombre: str) -> str:
        for n, _, p in lista:
            if n == nombre:
                return p
        return ""

    NOMBRE_FSTAB = "fstab no repite la particion de arranque"
    comprueba("en UEFI el fstab tiene que traer una linea de /boot/efi",
              patron_de(checks_uefi, NOMBRE_FSTAB) == r"^1$",
              f"el patron es {patron_de(checks_uefi, NOMBRE_FSTAB)!r}")
    comprueba("en BIOS el fstab no puede traer ninguna linea de /boot/efi",
              patron_de(checks_bios, NOMBRE_FSTAB) == r"^0$",
              f"el patron es {patron_de(checks_bios, NOMBRE_FSTAB)!r}")

    # Las comprobaciones de los dos modos, con la misma orden.
    orden_por_nombre = {n: o for n, o, _ in checks_uefi}
    distintas = [(n, orden_por_nombre[n], o) for n, o, _ in checks_bios
                 if n in orden_por_nombre and orden_por_nombre[n] != o]
    comprueba("las comprobaciones de los dos modos miran lo mismo", not distintas,
              f"distintas: {distintas}")
    # Y que las de BIOS no se salgan de las de UEFI: si una comprobacion aparece
    # solo en BIOS es porque se ha anadido a la rama equivocada.
    solo_bios = [n for n in nombres_bios if n not in nombres_uefi]
    solo_bios_justos = [n for n in solo_bios
                        if "MBR" in n or "modulos de grub" in n]
    comprueba("lo unico que BIOS mira de mas es el MBR y sus modulos",
              solo_bios == solo_bios_justos,
              f"en BIOS y no en UEFI: {solo_bios}")

    # Y la particion de arranque, que se anota FUERA de la lista y por eso no la
    # cubren las comprobaciones de arriba. Con un 'inf' de mentira, en las cuatro
    # combinaciones, exigiendo el veredicto en las dos direcciones.
    class InfDeMentira:
        def __init__(self) -> None:
            self.anotaciones: list[tuple[str, str, bool, str]] = []

        def anota(self, seccion: str, nombre: str, bien: bool, detalle: str = "") -> None:
            self.anotaciones.append((seccion, nombre, bien, detalle))

    casos = (
        (False, "/dev/vda1", True),     # UEFI con particion de arranque: bien
        (False, "", False),             # UEFI sin particion de arranque: MAL
        (True, "", True),               # BIOS, que no la tiene: bien
        (True, "/dev/vda1", False),     # BIOS con una particion EFI ahi: MAL
    )
    for bios, esp, bien_esperado in casos:
        inf = InfDeMentira()
        mod.anota_particiones(inf, esp, bios)
        modo = "BIOS" if bios else "UEFI"
        sitio = f"con la particion de arranque {esp}" if esp else "SIN particion de arranque"
        comprueba(f"{modo}, {sitio}: la anotacion es "
                  f"{'bien' if bien_esperado else 'MAL'}",
                  len(inf.anotaciones) == 1 and inf.anotaciones[0][2] is bien_esperado,
                  f"anotaciones: {inf.anotaciones}")
    # Que el nombre de la anotacion diga el modo, que si no dos informes con
    # nombres parecidos se confunden al leerlos.
    nombres_anotados = []
    for bios, esp, _ in casos:
        inf = InfDeMentira()
        mod.anota_particiones(inf, esp, bios)
        nombres_anotados += [n for _, n, _, _ in inf.anotaciones]
    comprueba("la anotacion de la particion de arranque es distinta en cada modo",
              len(set(nombres_anotados)) == 2, f"son {sorted(set(nombres_anotados))}")
    # Y el MODO DE ARRANQUE, que tampoco esta en la lista (se anota en medio de
    # la fase de arranque) y que en BIOS se rompio el 29 de septiembre a la 01:59
    # con el equipo arrancado por BIOS de verdad: se preguntaba 'la consola ha
    # contestado?' (que siempre es que si) en vez de 'que dice la salida?'.
    #
    # Las cuatro combinaciones, y ademas el caso de una salida que no es un
    # numero, que tiene que decir que no se ha podido mirar en vez de quedarse
    # con el numero viejo.
    # (salida, bios, bien_esperado): en UEFI tiene que HABER '/sys/firmware/efi'
    # (cuenta distinta de cero) y en BIOS tiene que NO haberlo (cuenta cero).
    # Las dos mitades esta cambiadas adrede, para que un 'not' mal puesto se vea
    # en las dos.
    casos_modo = (
        ("0\n", False, False, "UEFI"),         # UEFI sin efi: MAL
        ("1\n", False, True, "UEFI"),
        ("12\n", False, True, "UEFI"),         # mas de uno da igual: hay EFI
        ("0\n", True, True, "BIOS"),           # BIOS sin efi: bien
        ("1\n", True, False, "BIOS"),          # el fallo 40, al reves
    )
    for sal, bios, bien_esperado, modo in casos_modo:
        inf = InfDeMentira()
        mod.anota_modo_arranque(inf, sal, bios)
        donde = "UEFI" if not bios else "BIOS"
        comprueba(f"la salida {sal.strip()!r} en {donde} es "
                  f"{'bien' if bien_esperado else 'MAL'} (modo pedido: {modo})",
                  len(inf.anotaciones) == 1 and inf.anotaciones[0][2] is bien_esperado,
                  f"anotaciones: {inf.anotaciones}")
    # Y la salida que no se puede mirar. Antes, con 'ok2' de por medio, esto
    # colaba: si la consola no contestaba, 'ok2' era False y en BIOS el veredicto
    # 'not ok2' salia bien sin haber mirado nada.
    for sal in ("", "ls: no se puede acceder a '/sys/firmware/':\n",
                "[isai@titan ~]$ \n", "efi\n"):
        inf = InfDeMentira()
        mod.anota_modo_arranque(inf, sal, True)
        comprueba(f"una salida que no es una cuenta se declara ilegible: {sal[:24]!r}",
                  len(inf.anotaciones) == 1
                  and inf.anotaciones[0][2] is False
                  and "se ha podido mirar" in inf.anotaciones[0][1],
                  f"anotaciones: {inf.anotaciones}")
    # La orden tiene que ser corta: por la consola serie una linea larga se
    # envuelve y se parte, y el trozo de la izquierda se cuela en la salida.
    comprueba("la orden del modo de arranque cabe en una linea",
              len(mod.ORDEN_MODO_ARRANQUE) <= 40,
              f"son {len(mod.ORDEN_MODO_ARRANQUE)}: {mod.ORDEN_MODO_ARRANQUE!r}")
    # Y que se mande DESPUES de entrar al sistema instalado, no antes (antes
    # mediria el modo de arranque del live, que es el del ISO).
    codigo = codigo_de("anota_modo_arranque") or ""
    # Con limites de palabra, que 'anotaciones' tambien tiene una 'ok' dentro y
    # haria dar FALLO a la comprobacion que vigila justo lo que no debe pasar.
    usa_ok = re.search(r"\bok\b|\bok2\b|\bok3\b", codigo) is not None
    usa_run = re.search(r"\.run\(", codigo) is not None
    comprueba("el modo de arranque se decide con la salida, no con la consola",
              not usa_ok and not usa_run,
              f"usa ok={usa_ok}, usa run={usa_run}")
    print()
    print("== 15. la pantalla grafica del live, que se lee linea a linea ==")
    # El driver sube un script al live (verify/comprobar-gui-en-vivo.sh), lo
    # ejecuta, y pasa su salida al informe. Lo que no puede ser es que esa
    # salida se lea mal: si el prefijo se cambia, o si se coge el nombre en vez
    # del resultado, la fase entera se queda en verde con ocho comprobaciones
    # que no se han mirado, que es la forma mas cara de no comprobar nada.
    #
    # Con datos: la salida buena (tal cual la imprime el script), una con un
    # fallo, y las tres que tienen que ser ignoradas (el resumen, el ruido de la
    # consola y una linea cortada).
    salida_buena = (
        "GRAFICO/frontal=OK 755 root\n"
        "GRAFICO/paquetes=MAL faltan: cage\n"
        "GRAFICO/pantalla-pintada=OK cage rc=0, la ventana respondio 'gnome'\n"
        "GRAFICO/dri-info=no hay /dev/dri: el instalador grafico cae a texto\n"
        "GRAFICO/RESUMEN=mal 6/8\n"
    )
    inf = InfDeMentira()
    with contextlib.redirect_stdout(io.StringIO()) as impreso:
        mod.anota_gui(inf, salida_buena)
    # Ni el resumen ni las '-info' son comprobaciones. El resumen es la cuenta
    # de las demas, y una '-info' es un hecho de la maquina que no puede ponerse
    # en rojo nunca: si se anotaran, el informe traeria un verde que no
    # comprueba nada, que es el peor sitio para un falso verde.
    nombres = [n for _, n, _, _ in inf.anotaciones]
    comprueba("del script del live salen solo las tres comprobaciones",
              nombres == ["frontal", "paquetes", "pantalla-pintada"],
              f"nombres: {nombres}")
    veredictos = [b for _, _, b, _ in inf.anotaciones]
    comprueba("el OK y el MAL van cada uno a su anotacion",
              veredictos == [True, False, True],
              f"veredictos: {veredictos}")
    detalles = [d for _, _, _, d in inf.anotaciones]
    comprueba("el detalle es lo que va detras del OK o del MAL",
              detalles[0] == "755 root" and detalles[1] == "faltan: cage"
              and detalles[2].startswith("cage rc=0,"),
              f"detalles: {detalles}")
    # Y la '-info' sale como nota por la pantalla, con su texto, que es lo unico
    # que se puede hacer con un hecho que no es comprobacion.
    notas = impreso.getvalue()
    comprueba("la linea '-info' se lee como una nota, y entera",
              "nota  dri-info: no hay /dev/dri" in notas,
              f"pantalla: {notas!r}")
    # Y la linea larga: el detalle se corta, porque va a un informe que se lee
    # en una terminal, y sin acortar sale la linea entera partida en dos.
    largo = "GRAFICO/frontal=OK " + "x" * 400 + "\n"
    inf = InfDeMentira()
    with contextlib.redirect_stdout(io.StringIO()):
        mod.anota_gui(inf, largo)
    comprueba("un detalle de 400 caracteres se corta a 100",
              len(inf.anotaciones) == 1 and len(inf.anotaciones[0][3]) == 100,
              f"de {len(inf.anotaciones[0][3]) if inf.anotaciones else 0}")

    # Y lo que NO puede ser: que una salida vacia (el script que no se ha
    # ejecutado, o cuya salida se ha comido la consola) se lea como "todo bien".
    for salida, donde in (("", "nada"),
                          ("[isai@titan ~]$ sudo bash /tmp/x.sh\n",
                           "solo el eco"),
                          ("", "nada otra vez")):
        inf = InfDeMentira()
        mod.anota_gui(inf, salida)
        comprueba(f"una salida con {donde} NO se lee como si todo "
                  f"estuviera bien",
                  len(inf.anotaciones) == 1
                  and inf.anotaciones[0][2] is False
                  and "se han ejecutado" in inf.anotaciones[0][1],
                  f"anotaciones: {inf.anotaciones}")
    # Y con una linea que no lleva el prefijo entero (por si el script cambia de
    # formato), que tambien tiene que salir en rojo y no pasar por alto.
    for salida in ("GRAFICO=OK algo\n", "GRAFICO/\n", "GRAFIC/frontal=OK\n"):
        inf = InfDeMentira()
        mod.anota_gui(inf, salida)
        comprueba(f"una linea de otro formato ({salida.strip()!r}) no cuenta",
                  len(inf.anotaciones) == 1 and inf.anotaciones[0][2] is False,
                  f"anotaciones: {inf.anotaciones}")
    # El orden de las anotaciones es el del script, que es el que se ha escrito
    # a proposito para que se lea de arriba abajo.
    inf = InfDeMentira()
    mod.anota_gui(inf, salida_buena)
    orden_esperado = ["frontal", "paquetes", "pantalla-pintada"]
    orden_anotado = [n for _, n, _, _ in inf.anotaciones]
    comprueba("las anotaciones van en el orden del script",
              orden_anotado == orden_esperado, f"anotadas: {orden_anotado}")

    # --- las ordenes que van a la consola -------------------------------------
    # La consola del live es la shell de 'isai', no la de root, asi que un glob
    # lo expande ELLA. Y de '/root' no puede listar nada, con lo que el glob no
    # se expande, se queda literal y la orden que sale es un error. Medido en la
    # pasada de UEFI del dia 29: 'sudo ls /root/instalador/*.sh | wc -l' salio
    # en rojo con la ISO buena, y el detalle era 'ls: no se puede acceder a
    # /root/instalador/*.sh'. O sea: una comprobacion que no puede dar bien, que
    # es lo peor que puede ser un comprobador, porque cuando algo este de verdad
    # mal no se va a notar.
    con_glob = [(o, globs_sin_comillas(o)) for o in ordenes_por_consola(mod)
                if "sudo" in o and globs_sin_comillas(o)]
    comprueba("ninguna orden con 'sudo' lleva un glob sin comillas",
              not con_glob,
              "con glob: " + "; ".join(f"{o} -> {g}" for o, g in con_glob[:3]))

    # Y que el filtro sirva: un glob entre comillas es de la familia, pero es
    # una orden CORRECTA ('find -name "*.sh"' lo decide el find, que corre como
    # root). Si esta comprobacion lo pusiera en rojo, dejaria de ser una regla
    # y seria una prohibicion, que es como se cuelan los comprobadores que
    # miden la forma en vez de lo que importa.
    comprueba("un glob entre comillas no se cuenta como globo",
              globs_sin_comillas("sudo find /r -name '*.sh' | wc -l") == []
              and globs_sin_comillas("sudo ls /r/*.sh | wc -l") == ["*"],
              "el filtro no distingue las dos formas")

    # --- y la subida del script, que son doce kilobytes de texto --------------
    # Por la consola serie, a 150 caracteres por viaje: sin comprimir son 107
    # viajes con su eco, y el script del live acaba breasto. Ademas el fichero
    # tiene que LLEGAR IGUAL, que si al descomprimir sale otra cosa, la prueba
    # de arriba se estaria haciendo con otro script.
    class ConsolaDeSubida:
        def __init__(self) -> None:
            self.llamadas: list[str] = []
            self.ficheros: dict[str, bytes] = {}

        def run(self, orden: str, timeout: int = 30) -> tuple[bool, str]:
            self.llamadas.append(orden)
            if orden.startswith("echo ") and orden.endswith(
                    ">> " + DESTINO_GUI + ".b64"):
                self.ficheros.setdefault("b64", b"")
                self.ficheros["b64"] += orden[5:].split(" >> ")[0].encode()
            if "gzip -dc" in orden:
                try:
                    crudo = base64.b64decode(self.ficheros.get("b64", b""))
                    self.ficheros["descomprimido"] = gzip.decompress(crudo)
                except Exception as error:  # noqa: BLE001 - aqui es que se ve
                    # Lo que se subio no se puede descomprimir (por ejemplo, si
                    # el paso del bucle y el corte del trozo no son el mismo
                    # numero, y las ventanas se solapan: el base64 llega
                    # troceado en vez de entero). Se guarda la marca y la de
                    # 'llega byte a byte' se pone en rojo, en vez de reventar.
                    self.ficheros["descomprimido"] = b"NO-SE-PUEDE"
                    self.ficheros["fallo"] = f"{type(error).__name__}"
                return True, "260\n"
            return True, ""

    DESTINO_GUI = "/var/tmp/comprobar-gui-en-vivo.sh"
    consola = ConsolaDeSubida()
    with open(mod.GUI_EN_VIVO, encoding="utf-8") as f:
        texto = f.read()
    mod.subir_texto_gz(consola, DESTINO_GUI, texto)
    viajes = [c for c in consola.llamadas if c.startswith("echo ")]
    sin_comprimir = -(-len(base64.b64encode(texto.encode())) // 150)
    comprueba("el script del live sube en menos de la mitad de viajes",
              0 < len(viajes) * 2 < sin_comprimir,
              f"son {len(viajes)} viajes de {len(texto)} caracteres, y sin "
              f"comprimir serian {sin_comprimir}")
    # Y el tamano del trozo, que es lo que decide cuantos viajes hay. Mirar solo
    # el numero de viajes no lo caza: con trozos de 1500 salen cuatro, y cuatro
    # por dos sigue siendo menos que los 107 sin comprimir, que es la cuenta que
    # hay aqui. Que un trozo mida lo que tiene que medir, eso si se ve.
    # La lista va ORDENADA, asi que el trozo que se queda corto (el ultimo) es
    # el mas pequeno: todos los demas tienen que medir lo mismo, y ese ultimo
    # menos. (Con la lista sin ordenar, mirarla al reves daba rojo siempre.)
    tam = sorted(len(c[5:].split(" >> ")[0]) for c in viajes)
    comprueba("los trozos van de 150 caracteres (y el ultimo, lo que falte)",
              len(tam) > 1 and 0 < tam[0] < 150
              and all(n == 150 for n in tam[1:]),
              f"van de {tam[0]} a {tam[-1]} en {len(tam)} trozos")
    motivo = consola.ficheros.get("fallo", "")
    comprueba("el script del live llega al guest byte a byte",
              consola.ficheros.get("descomprimido") == texto.encode(),
              f"han llegado {len(consola.ficheros.get('descomprimido', b''))} "
              f"de {len(texto.encode())} bytes"
              + (f" ({motivo})" if motivo else ""))
    # Y que la orden que descomprime sea la que se espera. Si alguien quita el
    # 'gzip -dc', el fichero llega con el base64 crudo y la prueba de arriba se
    # ejecuta sobre un script que no es el (y falla, pero por otro motivo).
    baja = [c for c in consola.llamadas if "gzip" in c]
    comprueba("la orden que reconstruye el script descomprime de verdad",
              len(baja) == 1 and baja[0] == f"base64 -d {DESTINO_GUI}.b64 "
              f"| gzip -dc > {DESTINO_GUI} && wc -l < {DESTINO_GUI}",
              f"orden: {baja}")
    # Y que borre el temporal antes de empezar, que si no se queda el base64 de
    # la subida anterior en un fichero de 16 KiB.
    primero = consola.llamadas[0]
    comprueba("la subida empieza borrando lo que hubiera",
              primero == f"rm -f {DESTINO_GUI}.b64 {DESTINO_GUI}",
              f"primera: {primero}")
    # Y que la ruta del script exista de verdad en el repositorio, que es donde
    # el driver la va a buscar (con un fichero que no esta, la fase 2b no
    # empezaria y el error seria del live).
    comprueba("el script del live esta donde el driver lo busca",
              os.path.isfile(mod.GUI_EN_VIVO) and "verify" in mod.GUI_EN_VIVO,
              mod.GUI_EN_VIVO)
    # Y que la fase 2b este de verdad en el cuerpo del driver, y no en un
    # comentario: el fallo tipico es dejar el codigo escrito y no llamarlo.
    cuerpo = pathlib.Path(mod.__file__).read_text()
    called = "anota_gui(inf, sal)" in cuerpo
    sube = "subir_texto_gz(ser," in cuerpo
    comprueba("la fase 2b sube el script y pasa su salida al informe",
              called and sube, f"anota_gui={called}, subir={sube}")
    # Con el script roto (que es lo que pasa si el live se construye sin el
    # frontal), la salida son lineas GRAFICO/... y por lo tanto el informe los
    # ve. Y con el script ausente, la fase 2b revienta con un error claro en vez
    # de seguir instalando como si nada.
    print()
    if fallos:
        print(f"RESULTADO: {fallos} fallo(s)")
        return 1
    print("RESULTADO: todo correcto")
    return 0


if __name__ == "__main__":
    sys.exit(main())
