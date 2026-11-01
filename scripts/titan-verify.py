#!/usr/bin/env python3
"""Arranca la ISO de Titan Linux en QEMU y comprueba que el sistema funciona.

Que hace, en orden:
  1. levanta QEMU sin ventana, con la consola serie en un socket unix
     (la entrada por defecto del menu de GRUB ya trae console=ttyS0)
  2. espera a que el sistema llegue a la shell de titan
  3. ejecuta una bateria de comandos y comprueba la salida de cada uno
  4. ejecuta fastfetch y el CLI titan, incluido 'titan doctor'
  5. guarda una captura de la consola grafica y el registro completo

Uso:
    scripts/titan-verify.py --iso out/titan-linux-0.1.0-x86_64.iso
    scripts/titan-verify.py --iso ... --bios --timeout 1200

Codigo de salida: 0 si todo pasa, 1 si algo falla.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time

OVMF_CODE = "/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS = "/usr/share/edk2/x64/OVMF_VARS.4m.fd"

# Dos familias de escapes, y quitarlas las dos importa. Los CSI son los de
# color: '\x1b[38;2;120;132;150m'. Los OSC son de otro tipo: el prompt del live
# emite hipervinculos '\x1b]8;;url\x1b\\texto\x1b]8;;\x1b\\', y su secuencia de
# cierre se queda pegada AL PRINCIPIO de la linea siguiente, con lo que la linea
# del marcador acaba siendo '\x1b\__TITAN_DONE_11__' y el ancla de fin de linea
# de 'expect' no la encuentra nunca. Pasa solo en algunas ordenes (depende de
# donde caiga el salto de linea), que es lo que lo hace tan dificil de ver.
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
OSC = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
# El cierre de una secuencia OSC puede quedarse solo: si la apertura y el
# cierre llegan en dos lecturas distintas y la de en medio se pierde, lo que
# sobra es un ESC seguido de barra invertida. Es un caracter de control, nunca
# texto, asi que se quita tambien.
OSC_HUERFANO = re.compile(r"\x1b\\")
# Los escapes que son UN SOLO caracter despues del ESC, y que no son ni CSI ni
# OSC. De estos solo aparecian dos en la consola, pero no casualmente: los
# escribe el tty al restaurar la posicion del cursor, y lo hace al limpiar la
# pantalla, que es justo lo que hace systemd al arrancar. Son ESC 7 (guardar
# cursor) y ESC 8 (recuperarlo), y salian en la linea de 'Initial Setup':
#
#   ESC 7  ESC[32766;32766H  ESC[6n  ESC 8  ESC]3008;start=...;invocationid=...
#
# Con ellos sin quitar, el ESC suelto hacia que la cadena OSC de al lado ya no
# se reconociera, y su texto entero se quedaba a la vista en la salida.
ESC_SIMPLE = re.compile(r"\x1b[ -/]*[0-~]")
# Una cadena de control CON TEXTO DENTRO que llega sin terminar. El caso real,
# en los logs del 28 de septiembre:
#
#   ESC]3008;start=1a16...;invocationid=35580bb1...c7c[  ESC[0;32m  OK
#
# La cadena empieza pero su cierre (BEL o ESC barra invertida) no esta: se
# perdio, o todavia no ha llegado. Asi que todo lo que sigue, hasta el proximo
# escape, es el payload de la cadena y no salida de ningun programa. Se quita.
#
# Por que se quita en vez de dejar el texto a la vista: al reves que la regla
# de los '\\r', aqui el texto que sobra PODRIA parecer salida (tiene dos
# puntos, tiene '=', tiene comas), y una comprobacion que lo encuentre se
# poneContento con algo que no ha escrito ningun programa. Entre comerse texto
# de mas y ensenar texto de mas, la segunda es la que hace mentir a los
# comprobadores, que es el fallo que se ha estado cazando todo este tiempo.
CADENA_COLGADA = re.compile(r"\x1b[\]P^_][^\x07\x1b\n]*")


def plano(texto: str) -> str:
    """El texto de la consola sin escapes de ningun tipo.

    Los '\\r' tambien se quitan. La consola serie los pone al final de cada
    linea (el tty esta en ONLCR), y hay veces que caen AL PRINCIPIO de la linea
    siguiente: la linea del marcador llega como '\\r__TITAN_DONE_11__', y el
    ancla de principio de linea de la expresion ya no la encuentra. Con los
    '\\r' fuera, cada linea es una linea.

    El orden importa mas de lo que parece, y se ha descubierto rompiendolo:

        texto = OSC.sub("", texto)
        texto = CADENA_COLGADA.sub("", texto)
        texto = ANSI.sub("", texto)
        texto = ESC_SIMPLE.sub("", texto)
        texto = OSC_HUERFANO.sub("", texto)

    La regla de la cadena sin terminar va ANTES de la de los colores a proposito.
    Se come lo que hay hasta el siguiente escape, y si los colores se quitan
    antes, ese escape ya no esta: la regla se come entonces hasta el final de la
    linea, y con ella se lleva la salida de verdad que venia detras. En el log
    real eso era la linea de arranque de systemd entera:

        ...invocationid=...c7c[  OK  ] Finished Initial Setup.

    Con el orden equivocado, de esa linea no quedaba NADA: ni la cadena, ni el
    'OK', ni el 'Finished'. Un comprobador al que se le borra la salida entera
    no mide que se haya instalado el sistema: mide que el texto no tenga
    comillas, y siempre daria verde.

    Lo que aqui NO se arregla, y conviene saberlo: un escape partido en dos por
    el ancho de la linea. A 80 columnas un 'ESC[0;27;158H' largo se parte, y
    queda un ESC al final de una linea y el resto al principio de la siguiente.
    Ninguna regla lo coge, porque ya no hay una secuencia entera sino dos
    trozos. En los logs se ve en los menus de dialog (los cuadritos del marco).
    Es ruido de dibujo, no texto de programa, asi que no ha roto ninguna
    comprobacion; y no se arregla aqui porque la unica manera seria no dibujar
    la interfaz por la consola serie, que es lo contrario de lo que se quiere.
    """
    texto = OSC.sub("", texto)
    texto = CADENA_COLGADA.sub("", texto)
    texto = ANSI.sub("", texto)
    texto = ESC_SIMPLE.sub("", texto)
    texto = OSC_HUERFANO.sub("", texto)
    return texto.replace("\r", "")


# El prompt de la shell. No es salida de la orden: es lo que aparece DESPUES,
# cuando la orden ya ha terminado y la shell vuelve a pedir algo. Se cuela en
# el filtro igual que el eco, y rompe cualquier comprobacion que compare la
# salida con algo exacto ('sudo ls ... | wc -l' devolvia "9 titan@...:~$").
#
# Se reconoce por su forma y no por su texto: algo, una '@', algo, dos puntos,
# y el signo de fin de orden al final de la linea. Las tres cosas juntas son lo
# que lo hace un prompt y no una linea de salida: casi ninguna linea de
#(programa) tiene una '@', dos puntos y un '$' al final a la vez.
#
# Se exige que sea la linea ENTERA (por eso el ancla final), para no comerse
# media linea de salida que acabe en '$'.
PROMPT = re.compile(r"^\S*@\S*:\S*[$#] ?$")


def patron_marca(marker: str) -> str:
    """La expresion con la que se busca la marca que cierra una orden.

    Lo que se admite ANTES de la marca es cualquier cosa de la misma linea
    (`^[^\\n]*`), y lo que se exige es que la linea TERMINE en la marca. Las dos
    mitades estan puestas por motivos distintos y los dos importan:

    - El principio de linea no puede exigirse: el prompt, con sus colores y sus
      hipervinculos, se queda pegado a la salida cuando el comando no imprime
      nada antes, y con el ancla estricta la orden pareciese no terminar nunca.
    - El final de linea si tiene que exigirse, porque si no, el eco de lo
      escrito haria pasar la orden antes de tiempo. Para eso esta que la marca
      se mande partida: el eco lleva las comillas del corte detras, y con ellas
      ya no es el final de la linea.

    Vive en su propia funcion para que la comprobacion de la consola use
    exactamente la misma expresion que 'run' y no una copia que se pueda
    quedar vieja sin que nadie se entere.
    """
    return rf"(?m)^[^\n]*{marker}\s*$"


class Serial:
    """Console serie de QEMU, con ejecucion de comandos por marcadores.

    Para saber cuando un comando ha terminado no se intenta adivinar el
    prompt (el prompt de titan lleva secuencias de escape y puede partirse
    entre lineas): se anade al comando un `echo __DONE_n__` y se espera a esa
    cadena.
    """

    def __init__(self, path: str, log):
        self.path = path
        self.log = log
        self.buf = ""
        self.sock: socket.socket | None = None
        self.n = 0
        # Cuanto se ha revisado ya del buffer (ver 'expect').
        self.mirado = 0

    def connect(self, deadline: float) -> bool:
        while time.time() < deadline:
            if os.path.exists(self.path):
                try:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.connect(self.path)
                    s.setblocking(False)
                    self.sock = s
                    return True
                except OSError:
                    pass
            time.sleep(0.1)
        return False

    def _drain(self) -> None:
        if self.sock is None:
            return
        while True:
            try:
                data = self.sock.recv(65536)
            except (BlockingIOError, InterruptedError, OSError):
                return
            if not data:
                return
            text = data.decode("utf-8", errors="replace")
            self.buf += text
            self.log.write(text)
            self.log.flush()

    def expect(self, pattern: str, timeout: float) -> bool:
        """Espera a que `pattern` aparezca en lo recibido por la consola.

        Busca sobre el texto SIN escapes de ningun tipo: fastfetch, al
        terminar, deja el reset de color pegado al principio de la linea
        siguiente, asi que el marcador llega como `\\x1b[m__TITAN_DONE_38__` y un
        patron que exija estar en la columna 0 no lo encontraria nunca. Con el
        prompt de titan hay mas cosas pegadas: hipervinculos OSC 8 y el '\\r'
        que el tty pone al final de cada linea y a veces cae al principio de la
        siguiente (ver 'plano').

        Con el buffer pequeno se revisa entero, que es lo normal en una orden
        corta. En cuanto pasa de 64 KiB (una instalacion entera, que escurre
        linea a linea decenas de megas) solo se revisa lo nuevo, menos un trozo
        por delante por si el patron cae justo en la costura de dos lecturas.
        Sin esto el proceso se pasa la instalacion entera consumiendo CPU en
        expresiones regulares en vez de esperando.
        """
        rx = re.compile(pattern)
        deadline = time.time() + timeout
        while time.time() < deadline:
            self._drain()
            if len(self.buf) < 65536:
                trozo = self.buf
            else:
                trozo = self.buf[max(0, self.mirado - 4096):]
            if rx.search(plano(trozo)):
                self.mirado = len(self.buf)
                return True
            self.mirado = len(self.buf)
            time.sleep(0.1)
        return False

    def send(self, line: str) -> None:
        assert self.sock is not None
        self.sock.sendall((line + "\n").encode())
        self.log.write(f"\n[[consola]] {line}\n")
        self.log.flush()

    def run(self, cmd: str, timeout: float = 120) -> tuple[bool, str]:
        """Ejecuta `cmd` y devuelve (termino, salida limpia).

        Detalle que importa: la consola serie hace eco de lo que se escribe, asi
        que el marcador buscara aparece tambien en el eco de la orden, antes de
        que exista su salida. Por eso el marcador se envia partido
        (`echo __TITAN_DONE_""7__`): lo que se ve escrito es `""7__` y lo que
        imprime la shell es el marcador entero. Y se exige que la linea termine
        justo despues del marcador, no una linea que lo contenga.

        Lo que se admite ANTES del marcador, en cambio, es cualquier cosa de la
        misma linea (`^[^\\n]*`): el prompt con sus colores y sus hipervinculos
        puede acabar pegado a la salida cuando el comando no imprime nada
        antes, y exigir la columna 0 hacia que la orden pareciese no terminar
        nunca. El eco no puede provocar un falso positivo, porque la marca
        entera no sale nunca en el eco (va partida) y ademas detras del eco
        quedan las comillas del corte.
        """
        self.n += 1
        marker = f"__TITAN_DONE_{self.n}__"
        self._drain()
        self.buf = ""
        self.mirado = 0
        self.send(f'{cmd} ; echo {marker[:18]}""{marker[18:]}')
        ok = self.expect(patron_marca(marker), timeout)
        time.sleep(0.3)
        self._drain()
        if not ok:
            # Sin esto, una orden que no encuentra su marca solo deja un
            # silencio de 120 segundos en el log, sin ninguna pista de por que.
            # Con el volcado se ve el texto que llego de verdad.
            self.log.write(f"\n[[aviso]] sin marca {marker} en {timeout}s "
                           f"para: {cmd}\n[[buffer]] {self.buf!r}\n")
            self.log.flush()
        plain = plano(self.buf)
        lines = [
            line
            for line in plain.splitlines()
            if "echo __TITAN_DONE_" not in line   # eco de la orden enviada
            and line.strip() != marker           # linea del marcador
            and not PROMPT.match(line.rstrip())  # el prompt de la shell
        ]
        return ok, "\n".join(lines)


def wait_for_shell(ser: Serial, timeout: float) -> bool:
    """Espera a que haya una shell lista, probando con una orden real.

    No vale esperar a 'login:' ni al banner 'L I N U X': con el autologin de
    Titan no existe prompt de login, y el banner del nucleo aparece mucho antes
    de que systemd arranque. La unica senal fiable es que algo al otro extremo
    del cable llegue a ejecutar una orden.
    """
    deadline = time.time() + timeout
    attempt = 0
    while time.time() < deadline:
        attempt += 1
        ok, _ = ser.run(f"echo __TITAN_SHELL_{attempt}__", timeout=20)
        if ok:
            return True
        time.sleep(2)
    return False


class Check:
    def __init__(self, name: str):
        self.name = name
        self.ok = False
        self.detail = ""
        self.output = ""

    def pass_(self, detail: str = "ok") -> None:
        self.ok = True
        self.detail = detail

    def fail(self, detail: str) -> None:
        self.ok = False
        self.detail = detail


class Monitor:
    """Monitor de QEMU por socket unix: screendump y sendkey.

    OJO con type_text: 'sendkey' no acepta los caracteres tal cual, solo nombres
    de tecla, y cuando el nombre no existe contesta 'invalid parameter: X'.
    Como cmd() no lee la respuesta, ese error pasaba DESAPARECIDO y el texto
    tecleado salia con holes: 'clear; echo TITAN_VGA_OK' llegaba a la consola
    como 'clear echo TITAN VGA OK' (el ';' y los '_' desaparecian) y el check
    fallaba sin que se entendiera por que. Por eso el mapa de TECLAS esta
    completo para todo el ASCII imprimible (comprobado uno a uno contra el
    monitor de QEMU 11.1: 113 nombres, todos validos) y ademas type_text
    REVienta si le pides un caracter que no sepa, para que un hueco sea un
    error visible y no un fallo sin explicacion.
    """

    # Tecla base y tecla con shift. Lo que se envia es el nombre de tecla, no el
    # caracter: ';' es 'semicolon', '_' es 'shift-minus', '{' es
    # 'shift-bracket_left'. Verificado contra el monitor de QEMU.
    BASE = {
        " ": "spc", "\n": "ret", "\t": "tab",
        "(": "shift-9", ")": "shift-0", "*": "shift-asterisk", "+": "shift-equal",
        ",": "comma", "-": "minus", ".": "dot", "/": "slash",
        ";": "semicolon", "=": "equal",
        "[": "bracket_left", "\\": "backslash", "]": "bracket_right",
        "`": "grave_accent", "'": "apostrophe",
        "!": "shift-1", "@": "shift-2", "#": "shift-3", "$": "shift-4",
        "%": "shift-5", "^": "shift-6", "&": "shift-7", '"': "shift-apostrophe",
        "_": "shift-minus", "+": "shift-equal",
        "{": "shift-bracket_left", "}": "shift-bracket_right",
        "|": "shift-backslash", ":": "shift-semicolon",
        "<": "shift-comma", ">": "shift-dot", "?": "shift-slash",
        "~": "shift-grave_accent",
    }
    TECLAS = dict(BASE)
    for _d in "0123456789abcdefghijklmnopqrstuvwxyz":
        TECLAS[_d] = _d
        TECLAS[_d.upper()] = "shift-" + _d

    # Pausas entre teclas, en segundos. cmd() ya espera 0,2 s cada vez.
    #
    # La pausa larga despues de una tecla con shift sale de un problema medido
    # en el live: con 0,2 s entre teclas, los DIGITOS salen con shift pegado
    # ('clear; seq 1 2000' llegaba a la consola como 'clear; seq ! @)))' y
    # 'qa02.txt' como 'qa)@.txt'). Con 0,6 s el digito sale bien, medido tecla a
    # tecla sobre la tty3 con 'cat -v' (sendkey 1 -> '1', sendkey 0 -> '0',
    # sendkey 5 -> '5', y tambien justo despues de 'sendkey shift-a').
    PAUSA = 0.2
    PAUSA_TRAS_SHIFT = 0.6

    def __init__(self, path: str, log):
        self.path = path
        self.log = log
        self.sock: socket.socket | None = None

    def connect(self, deadline: float) -> bool:
        while time.time() < deadline:
            if os.path.exists(self.path):
                try:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.settimeout(15)
                    s.connect(self.path)
                    s.recv(65536)          # banner del monitor
                    self.sock = s
                    return True
                except OSError:
                    pass
            time.sleep(0.2)
        return False

    def cmd(self, line: str, pausa: float | None = None) -> bool:
        if self.sock is None:
            return False
        try:
            self.sock.sendall((line + "\n").encode())
        except OSError:
            return False
        self.log.write(f"[[monitor]] {line}\n")
        self.log.flush()
        time.sleep(self.PAUSA if pausa is None else pausa)
        return True

    def sendkey(self, nombre: str, veces: int = 1) -> None:
        """Manda una tecla a la consola, veces veces."""
        for _ in range(veces):
            self.cmd("sendkey " + nombre)
            time.sleep(0.1)

    def type_text(self, text: str) -> None:
        """Escribe texto en la consola de QEMU tecla a tecla.

        Si algun caracter no tiene nombre de tecla conocido, se lanza una
        excepcion en vez de teclear un hole: es mejor que el check se caiga
        con un mensaje claro que que la orden llegue incompleta.

        Despues de cada tecla con shift (las de '!@#$%^&*()_+{}|:"<>?~' y las
        mayusculas) se espera PAUSA_TRAS_SHIFT, porque si no los digitos
        siguientes salen tambien con shift pegado. Ver la nota de las pausas.
        """
        for ch in text:
            nombre = self.TECLAS.get(ch)
            if nombre is None:
                raise ValueError(
                    f"no se sabe teclear {ch!r} (0x{ord(ch):02x}): el mapa de "
                    f"teclas de QEMU no lo tiene, y mandarlo a pelo hace que "
                    f"QEMU lo ignore en silencio"
                )
            con_shift = nombre.startswith("shift-")
            self.cmd("sendkey " + nombre,
                     self.PAUSA_TRAS_SHIFT if con_shift else self.PAUSA)

    def screendump(self, ppm: str, timeout: float = 20.0) -> bool:
        if self.sock is None:
            return False
        if os.path.exists(ppm):
            os.unlink(ppm)
        if not self.cmd(f"screendump {ppm}"):
            return False
        deadline = time.time() + timeout
        while time.time() < deadline:
            if os.path.exists(ppm) and os.path.getsize(ppm) > 1000:
                return True
            time.sleep(0.3)
        return False


# --------------------------------------------------------------- consola VGA
# Para medir la consola de texto (tty1) sin OCR ni leer imagenes: se pide al
# guest el texto que hay escrito ahora mismo en su buffer de video y se
# comparan los numeros que se ven. Los tres detalles de esta receta salen de
# experimentacion, y los tres hacen que el check falle si se cambian:
#
#   - El nodo es /dev/vcs1, no /dev/vcs0. /dev/vcs apunta a la consola ACTIVA,
#     y en el live esa es ttyS0 (la de serie), que no tiene buffer de texto y
#     devuelve 0 bytes. tty1, la que ve una persona, es la 1.
#   - El nodo es 0600 y la redireccion la abre la shell, asi que tiene que ser
#     'sudo sh -c "... < /dev/vcs1 ..."'. Con 'sudo fold ... < /dev/vcs1' no funciona.
#   - La captura por serie tambien trae el eco del propio comando, asi que el
#     contenido va delimitado DENTRO de la tuberia del guest, entre dos
#     marcadores, y el test lee solo lo que hay entre ellos.
VCS_LECTURA = (
    'sudo sh -c "{ echo TITANVCSINI; fold -w 80 < /dev/vcs1 | cat -v; '
    'echo TITANVCSFIN; }" | sed -n \'/^TITANVCSINI$/,/^TITANVCSFIN$/p\''
)


def consola_video(ser: "Serial") -> list[str]:
    """Filas de texto visibles ahora mismo en tty1 (la consola de video)."""
    _, salida = ser.run(VCS_LECTURA, timeout=90)
    if "TITANVCSINI" not in salida or "TITANVCSFIN" not in salida:
        return []
    return salida.split("TITANVCSINI", 1)[1].split("TITANVCSFIN", 1)[0].splitlines()


# Fila que tmux dibuja ARRIBA de la ventana cuando se esta leyendo el historial:
# la hora y '[cuantas lineas atras/de quantas]', por ejemplo '22:32 [43/28322]'.
# No es salida del comando, y sus numeros no interesan: el 28322 de ahi es el
# numero de la ultima linea, asi que sin filtrarlo, esta comprobacion creeria
# que la ultima linea sigue a la vista despues de subir por el historial, que
# es justo lo que este check tiene que distinguir.
INDICADOR_TMUX = re.compile(r"\[\d+/\d+\]")


def numeros_pantalla(ser: "Serial") -> set[int]:
    """Numeros que se ven ahora mismo en la consola de video, sin los de tmux."""
    return {int(x) for f in consola_video(ser)
            if not INDICADOR_TMUX.search(f)
            for x in re.findall(r"\d+", f)}


def filas_consola(ser: "Serial") -> int:
    """Filas de texto que hay escritas en la consola de video.

    OJO con contar a lo bruto: la consola por serie va a 80 columnas, asi que una
    fila de 80 caracteres llena la pantalla y el salto de linea del shell anade
    OTRA fila vacia. Por eso el dump de /dev/vcs1 llega con el doble de lineas
    (101 por 50, medido en el live) y aqui se cuentan solo las que tienen algo.
    """
    return sum(1 for f in consola_video(ser) if f.strip())


# Orden que produce una salida larga de lineas numeradas, SIN TECLEAR UN DIGITO.
#
# Por que sin digitos: el teclado de QEMU manda las teclas de la fila de numeros
# con shift cuando van demasiado seguidas, y eso se comia los numeros de la
# orden ('clear; seq 1 2000' llegaba como 'clear; seq ! @))).' el numero sale de
# la longitud de unas cadenas de entorno, que la shell expande sola: ${#HOME} es
# la longitud de la ruta del home y ${#BASH_VERSION} la de la version de bash,
# asi que ${#BASH_VERSION} * ${#BASH_VERSION} * ${#PATH} da unos cuantos miles
# sin que haya ni un digito tecleado. Medido en el live: 28322 lineas.
ORDEN_LARGA = ("clear; seq ${#HOME} "
               "$(( ${#BASH_VERSION} * ${#BASH_VERSION} * ${#PATH} ))")


def run_consecutivo(ns: set[int], minimo: int = 5) -> tuple[int, int] | None:
    """(menor, mayor) del tramo de numeros consecutivos de la pantalla.

    Con la salida de 'seq' cada linea lleva un numero y van seguidos, asi que lo
    que se ve en pantalla es SIEMPRE un tramo contiguo. Esto evita el falso
    positivo clasico de este check: ver un numero suelto (por ejemplo el eco de
    la propia orden, o un '6.18.54' del banner) no demuestra nada, pero ver un
    tramo entero de 40 lineas consecutivas si.

    Los numeros pequenos se van descartando por tramos (suelo 0, 1, 2, ...), a
    que el prompt, el nombre del release y la version del kernel tambien traen
    cifras que se colarian en la misma lectura.
    """
    for suelo in (0, 1, 2, 3, 4, 5, 10, 20, 50, 100):
        ordenados = sorted(n for n in ns if n > suelo)
        if not ordenados:
            continue
        tramos: list[tuple[int, int]] = []
        ini = prev = ordenados[0]
        for n in ordenados[1:]:
            if n == prev + 1:
                prev = n
                continue
            tramos.append((ini, prev))
            ini = prev = n
        tramos.append((ini, prev))
        largos = [t for t in tramos if t[1] - t[0] + 1 >= minimo]
        if largos:
            return max(largos, key=lambda t: t[1] - t[0])
    return None


def vga_espera(ser: "Serial", marcador: str = "titan@titan", tmo: int = 150) -> bool:
    """Espera a que tty1 muestre la shell de titan.

    Hace falta porque el teclado solo llega a tty1 si hay una tty abierta donde
    encolarlo: si se mandan teclas antes de que el getty la abra, el kernel las
    tira y la orden se pierde. Por eso despues los intentos se verifican.
    """
    limite = time.time() + tmo
    while time.time() < limite:
        if any(marcador in f for f in consola_video(ser)):
            return True
        time.sleep(3)
    return False


def vga_orden(ser: "Serial", mon: "Monitor", orden: str, marcador: str,
              intentos: int = 5) -> bool:
    """Escribe una orden en tty1 y comprueba que llego a ejecutarse."""
    for _ in range(intentos):
        mon.type_text(orden)
        mon.cmd("sendkey ret")
        time.sleep(4)
        if any(marcador in f for f in consola_video(ser)):
            return True
    return False


# ------------------------------------------------------- estado interno de tmux
# Preguntar al propio tmux por la serie es lo que permite medir el historial sin
# OCR ni interpretacion de imagenes: el panel lleva la cuenta de cuantas lineas
# ha desplazado, y eso es exactamente "cuanto se ha salido de la pantalla".
def tmux_esta(ser: "Serial") -> bool:
    """Existe una sesion de tmux 'titan' en el live? (la de tty1)"""
    _, salida = ser.run("tmux has-session -t titan 2>&1; echo TITANHASTITAN$?",
                        timeout=60)
    return "TITANHASTITAN0" in salida


def tmux_dato(ser: "Serial", expr: str) -> str:
    """Valor de una expresion de formato de tmux ('#{pane_height}', etc.).

    Delimitado con un token propio porque la captura por serie trae tambien el
    eco de la orden, y devuelve la cadena tal cual (vacia si no se pudo leer).
    """
    _, salida = ser.run(
        f"tmux display-message -p -t titan 'TITANTMUX{expr}' 2>&1 "
        f"| tr -d '\\r' | tail -1 | sed 's/^/>> /'", timeout=60)
    for f in salida.splitlines():
        if ">> TITANTMUX" in f:
            return f.split(">> TITANTMUX", 1)[1].strip()
    return ""


def cmd_checks() -> list[tuple[str, str]]:
    """(orden, expresion regular que debe aparecer en su salida)."""
    return [
        ("pwd", r"/(?:home/)?titan"),
        ("ls /", r"usr"),
        ("echo hola mundo", r"hola mundo"),
        ("whoami", r"\btitan\b"),
        ("id -u", r"\b1000\b"),
        ("date +%Y", r"20\d\d"),
        ("uname -m", r"x86_64"),
        # df -h imprime "256M"/"1.9G" (coreutils >= 9 ya no usa "MiB"), asi que
        # se comprueba la cabecera en ingles y que la linea de datos acabe en la
        # raiz, en vez de una unidad concreta. El (?m) es necesario porque tras
        # la tabla llega el eco del prompt: sin anclar a fin de linea, el
        # patron no podria terminar donde termina la tabla.
        ("df -h /", r"(?m)Filesystem\s+Size\s+Used\s+Avail[^\n]*\n[^\n]*/\r?$"),
        ("free -h", r"Mem"),
        ("ps -e | wc -l", r"\d+"),
        ("cat /etc/hostname", r"\btitan\b"),
        ("ls -la /etc/os-release", r"os-release"),
        ("mkdir -p /tmp/demo && cd /tmp/demo && pwd", r"/tmp/demo"),
        ("echo linea1 > f.txt && echo linea2 >> f.txt && cat f.txt", r"linea1"),
        ("grep linea f.txt", r"linea2"),
        ("sed 's/linea/LINEA/' f.txt", r"LINEA1"),
        ("awk '{print $1}' f.txt", r"linea1"),
        ("cut -d' ' -f1 /etc/hostname", r"titan"),
        ("find /tmp/demo -name f.txt", r"f\.txt"),
        ("tar -cf a.tar f.txt && tar -tf a.tar", r"f\.txt"),
        ("gzip -c f.txt | gunzip", r"linea1"),
        ("printf 'b\\na\\nc\\n' | sort | head -1", r"a"),
        ("printf 'a\\na\\n' | uniq | wc -l", r"\b1\b"),
        ("seq 1 5 | paste -sd,", r"1,2,3,4,5"),
        ("wc -l < f.txt", r"\b2\b"),
        ("ls /usr/bin/bash >/dev/null && echo bash-ok", r"bash-ok"),
        ("ls /usr/bin/git >/dev/null && echo git-ok", r"git-ok"),
        ("ls /usr/bin/htop >/dev/null && echo htop-ok", r"htop-ok"),
        ("ip -br addr | head -2", r"lo|UP"),
        ("lscpu | head -2", r"Architecture|architecture"),
        ("lsblk", r"NAME|loop"),
        ("history 1 >/dev/null && echo shell-ok", r"shell-ok"),
    ]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--iso", required=True)
    ap.add_argument("--out", default=None, help="directorio de resultados")
    ap.add_argument("--timeout", type=int, default=900, help="espera maxima de arranque")
    ap.add_argument("--memory", default="2048")
    ap.add_argument("--cpus", default="2")
    ap.add_argument("--bios", action="store_true", help="arrancar por BIOS en vez de UEFI")
    ap.add_argument("--no-shot", action="store_true", help="no guardar captura")
    args = ap.parse_args()

    iso = os.path.abspath(args.iso)
    if not os.path.exists(iso):
        print(f"ERROR: no existe la ISO {iso}", file=sys.stderr)
        return 1

    out_dir = os.path.abspath(args.out or os.path.join(os.path.dirname(iso), "verify"))
    os.makedirs(out_dir, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    log_path = os.path.join(out_dir, f"consola-{stamp}.log")
    report_path = os.path.join(out_dir, f"informe-{stamp}.json")
    shot_ppm = os.path.join(out_dir, f"pantalla-{stamp}.ppm")
    shot_png = os.path.join(out_dir, f"pantalla-{stamp}.png")
    # Segunda captura: la consola leyendo el historial (check 10), para que en el
    # informe se vea que la salida que se salio de la pantalla se puede releer.
    historial_ppm = os.path.join(out_dir, f"historial-{stamp}.ppm")
    historial_png = os.path.join(out_dir, f"historial-{stamp}.png")

    tmp = tempfile.mkdtemp(prefix="titan-verify-")
    ser_path = os.path.join(tmp, "serial.sock")
    mon_path = os.path.join(tmp, "monitor.sock")
    vars_copy = os.path.join(tmp, "OVMF_VARS.fd")

    qemu = [
        "qemu-system-x86_64",
        "-machine", "q35,accel=kvm:tcg",
        "-cpu", "max",
        "-m", args.memory,
        "-smp", args.cpus,
        "-boot", "order=d",
        "-drive", f"file={iso},media=cdrom,readonly=on",
        "-nic", "user,model=virtio-net-pci",
        "-audiodev", "none,id=snd0",
        "-display", "none",
        "-chardev", f"socket,id=ser0,path={ser_path},server=on,wait=off",
        "-serial", "chardev:ser0",
        "-monitor", f"unix:{mon_path},server=on,wait=off",
    ]
    mode = "BIOS (syslinux)"
    if not args.bios:
        if not os.path.exists(OVMF_CODE):
            print(f"ERROR: falta {OVMF_CODE}; instala edk2-ovmf o usa --bios",
                  file=sys.stderr)
            return 1
        shutil.copy(OVMF_VARS, vars_copy)
        qemu += [
            "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={OVMF_CODE}",
            "-drive", f"if=pflash,format=raw,unit=1,file={vars_copy}",
        ]
        mode = "UEFI (OVMF)"

    log = open(log_path, "w", encoding="utf-8", errors="replace")
    log.write(f"# Titan Linux - verificacion automatica\n")
    log.write(f"# fecha   : {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
    log.write(f"# ISO     : {iso}\n")
    log.write(f"# arranque: {mode}\n")
    log.write(f"# qemu    : {' '.join(qemu)}\n\n")

    print(f"==> ISO      : {iso}")
    print(f"==> arranque : {mode}")
    proc = subprocess.Popen(qemu, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ser = Serial(ser_path, log)
    if not ser.connect(time.time() + 60):
        log.write("\n# ERROR: no se pudo conectar al socket de serie de QEMU\n")
        proc.kill()
        log.close()
        print("ERROR: QEMU no expuso el socket de serie", file=sys.stderr)
        return 1
    mon = Monitor(mon_path, log)
    mon.connect(time.time() + 30)

    checks: list[Check] = []

    try:
        # 1. Arranque completo: GRUB -> kernel -> initramfs archiso -> systemd -> shell
        print("==> esperando el arranque (GRUB, kernel, systemd, shell de titan)")
        boot = Check("1. arranque hasta la shell")
        if wait_for_shell(ser, args.timeout):
            boot.pass_("shell de titan respondiendo por la consola serie")
        else:
            boot.fail("no se alcanzo una shell en el tiempo previsto")
            log.write("\n# ERROR: la ISO no llego a la shell\n")
        checks.append(boot)

        if boot.ok:
            ser.send("clear")
            time.sleep(1.0)

        # 2. Kernel propio
        c = Check("2. kernel propio de Titan Linux")
        ok, out = ser.run("uname -r; uname -v")
        m = re.search(r"(6\.[0-9.]+-\d+-titanlinux)", out)
        if ok and m:
            c.pass_(m.group(1))
        elif ok:
            c.fail("arranca, pero el kernelrelease no lleva el sufijo -titanlinux: "
                   + " / ".join(l.strip() for l in out.splitlines() if "Linux" in l)[:120])
        else:
            c.fail("no respondio 'uname -r'")
        c.output = out[:800]
        checks.append(c)

        # 3. Identidad de la distribucion
        c = Check("3. identidad Titan Linux")
        ok, out = ser.run("cat /etc/titan-release; grep PRETTY /etc/os-release")
        if ok and "Titan Linux" in out:
            ver = re.search(r'VERSION="([^"]+)"', out)
            c.pass_(f"os-release: {ver.group(1)}" if ver else "Titan Linux")
        else:
            c.fail("/etc/titan-release no declara Titan Linux")
        c.output = out[:800]
        checks.append(c)

        # 4. Comando basico de Linux
        print("==> comprobando el catalogo de comandos basicos")
        results = []
        for cmd, pattern in cmd_checks():
            cc = Check(f"4. comando: {cmd}")
            # LC_ALL=C para que la salida no dependa del idioma del live: en
            # es_ES.UTF-8, 'lscpu' escribe "Arquitectura:" y no "Architecture",
            # y el catalogo esta comprobando que el comando funciona, no que el
            # idioma este en ingles.
            ok, out = ser.run(f"LC_ALL=C {cmd}", timeout=90)
            if ok and re.search(pattern, out):
                cc.pass_()
            elif not ok:
                cc.fail("el comando no termino (se quedo colgado o no hay shell)")
            else:
                cc.fail(f"la salida no contiene {pattern}")
                cc.output = out[-400:]
            results.append(cc)
        c = Check("4. catalogo de comandos basicos")
        bad = [r.name for r in results if not r.ok]
        if bad:
            c.fail(f"{len(bad)} de {len(results)} fallos: " + "; ".join(bad[:6]))
        else:
            c.pass_(f"{len(results)}/{len(results)} comandos correctos")
        checks.append(c)
        checks.extend(results)

        # 5. fastfetch
        print("==> ejecutando fastfetch")
        c = Check("5. fastfetch con logo de Titan")
        ok, out = ser.run("fastfetch", timeout=180)
        plain = ANSI.sub("", out)
        if ok and "█" in plain and re.search(r"Sistema|Kernel", plain):
            c.pass_("logo de Titan + modulos del sistema")
        else:
            c.fail("no imprime el logo de Titan")
        c.output = plain[:2500]
        checks.append(c)

        # 6. CLI titan
        print("==> ejecutando el CLI titan")
        titan_parts = [
            ("titan version", r"Titan Linux"),
            ("titan logo", r"█"),
            ("titan commands", r"Ficheros|directorios"),
            ("titan info", r"kernel|distribucion"),
            ("titan --help", r"(?i)fetch|doctor|commands"),
        ]
        titan_bad = []
        titan_out = ""
        for cmd, pattern in titan_parts:
            ok, out = ser.run(cmd, timeout=120)
            if not (ok and re.search(pattern, out)):
                titan_bad.append(cmd)
            titan_out += f"\n$ {cmd}\n{out}"
        c = Check("6. CLI titan")
        if titan_bad:
            c.fail("fallan: " + ", ".join(titan_bad))
        else:
            c.pass_(f"{len(titan_parts)} subcomandos")
        c.output = titan_out[:2500]
        checks.append(c)

        # 7. titan doctor
        c = Check("7. titan doctor")
        ok, out = ser.run("titan doctor", timeout=180)
        if ok and "FALLO" not in out and "todo correcto" in out:
            c.pass_("todas las comprobaciones internas pasan")
        else:
            fallos = re.findall(r"\[FALLO\][^\n]*", out)
            c.fail("; ".join(fallos) if fallos else "no confirma exito")
        c.output = out[:2500]
        checks.append(c)

        # 8. Captura de la consola grafica
        c = Check("8. captura de la consola")
        if args.no_shot:
            c.pass_("omitida por --no-shot")
        elif mon.sock is None:
            c.fail("sin monitor de QEMU no se puede ni escribir en tty1 ni capturar")
        # La consola de serie y la de video son sesiones distintas, asi que para
        # que la foto muestre el logo de Titan hay que escribir en la de video,
        # con sendkey del monitor.
        #
        # Antes se mandaba 'titan' a pelo, pero hay una carrera: el teclado no
        # entra en tty1 hasta que el getty la abre, y si las teclas llegan antes
        # las descarta el kernel. Se espera a ver la shell de titan en tty1 y se
        # comprueba con un marcador que la consola responde, que es ademas lo
        # que necesita el check 10.
        elif not vga_espera(ser):
            c.fail("tty1 no llego a mostrar la shell de titan")
        elif not vga_orden(ser, mon, "clear; echo TITAN_VGA_OK", "TITAN_VGA_OK"):
            c.fail("la consola de video no responde al teclado (sendkey)")
        else:
            mon.type_text("titan")
            mon.cmd("sendkey ret")
            time.sleep(12)
            if mon.screendump(shot_ppm):
                png = shutil.which("magick") or shutil.which("convert")
                if png:
                    subprocess.run([png, shot_ppm, shot_png], check=False)
                c.pass_(os.path.basename(shot_png if os.path.exists(shot_png) else shot_ppm))
            else:
                c.fail("screendump no genero ninguna imagen")
        checks.append(c)

        # 9. sudo sin contrasena, para poder instalar paquetes en el live
        print("==> comprobando sudo")
        c = Check("9. sudo sin contrasena para instalar paquetes")
        # Cada sub-comprobacion imprime un marcador unico y el test lo busca
        # como texto. No se parsea la salida ('sudo -n id -u' devuelve un '0'
        # que la consola de 80 columnas pega a las secuencias de escape del
        # prompt, y 'cowsay' escribe arte multibyte): buscar un token que solo
        # puede aparecer si todo elPipeline fue bien es a prueba de ruido.
        # 'sudo -n' evita ademas que un prompt de contrasena se cuelgue en el
        # test: si pidiera contrasena, -n falla y el marcador no aparece.
        pasos = [
            ("sudo da root sin contrasena",
             "sudo -n id -u | tr -d ' \\r\\n' | grep -qx 0 && echo TITAN_OK_SUDO_ROOT",
             60,
             "sudo responde que el usuario no esta en el sudoers, o pide contrasena: "
             "revisa /etc/sudoers.d/10-titan y que siga en modo 0440"),
            ("pacman responde a traves de sudo",
             "LC_ALL=C sudo -n pacman -Q fastfetch >/dev/null 2>&1 && echo TITAN_OK_PACMAN_Q",
             120, "pacman no se puede ejecutar como root en el live"),
            ("los repositorios se sincronizan",
             "LC_ALL=C sudo -n pacman -Sy --noconfirm >/tmp/titan-sy.log 2>&1 "
             "&& echo TITAN_OK_SYNC || tail -3 /tmp/titan-sy.log",
             600, "pacman no encuentra espejos: el mirrorlist de la ISO va "
             "todo comentado y no hay Red de donde elegir"),
            ("se instala un paquete que no venia en la ISO",
             "LC_ALL=C sudo -n pacman -S --noconfirm --needed cowsay "
             ">/tmp/titan-inst.log 2>&1 && echo TITAN_OK_INSTALL || tail -5 /tmp/titan-inst.log",
             900, "la instalacion falla (sin espacio en la capa escribible?)"),
            ("el paquete instalado se ejecuta",
             "cowsay titan 2>/dev/null | grep -q 'titan' && echo TITAN_OK_COWSAY",
             120, "cowsay quedo instalado pero no se puede ejecutar"),
        ]
        salidas = []
        for nombre, cmd, tmo, pista in pasos:
            ok, salida = ser.run(cmd, timeout=tmo)
            marcador = re.search(r"TITAN_OK_[A-Z_]+", salida)
            if marcador:
                print(f"    OK  {nombre} ({marcador.group(0)})")
            else:
                print(f"    FALLO  {nombre}")
            salidas.append(f"$ {cmd}\n{salida}")
            if not marcador:
                c.fail(nombre + ": " + pista + " | " + " ".join(salida.split())[-260:])
                break
        else:
            c.pass_("sudo da root, pacman sincroniza, instala cowsay y se ejecuta")
        c.output = "\n".join(salidas)[:1500]
        checks.append(c)

        # 10. Historial de la salida en la consola de texto
        # Lo que se pide es que, cuando la salida se sale de la pantalla, se
        # pueda volver a leer, y que la parte de abajo (la ultima linea) este
        # siempre a la vista. Se mide sin OCR: se lee el texto que hay escrito
        # en el buffer de video de tty1 (/dev/vcs1) y se mira que numeros se ven.
        # El kernel no puede hacerlo solo (en el live la consola la dibuja
        # fbcon, sin historial), asi que la shell de tty1 corre dentro de tmux
        # (/etc/tmux.conf): RePag va hacia atras, una pantalla por pulsacion, y
        # q vuelve al final.
        #
        # OJO con la tecla: es RePag a secas, NUNCA Shift+RePag. El keymap del
        # kernel se come las teclas de pagina pulsadas con shift antes de que
        # lleguen a la tty (medido: 'sendkey shift-pgup' no produce ni un byte),
        # asi que enlazar S-PPage en tmux no haria nada. Y dentro del historial
        # las teclas las resuelve la tabla copy-mode, no la de root, por eso
        # estan enlazadas las dos.
        print("==> comprobando el historial de la salida en la consola")
        c = Check("10. la salida que se sale de la pantalla se puede releer")
        pasos: list[str] = []
        if mon.sock is None:
            c.pass_("omitida: sin monitor de QEMU no hay sendkey")
        else:
            # La tty1 tiene que estar lista (el check 8 ya la espera, pero aqui
            # no se puede dar por hecho: si el 8 fallo, este tambien).
            if not vga_espera(ser, tmo=60):
                c.fail("tty1 no muestra la shell de titan")
                pasos.append("tty1 no llego a la shell")
            elif not tmux_esta(ser):
                c.fail("la shell de tty1 no corre dentro de tmux")
                pasos.append("no hay servidor de tmux en el live")
            else:
                # Tamano del panel de tmux. No es solo un dato para el informe:
                # si el panel fuese mas alto que la consola de texto, debajo del
                # prompt se quedaria el texto viejo de antes del 'clear' y se
                # veria fatal. El alto del panel esta en la primera linea.
                panel = tmux_dato(ser, "#{pane_height}x#{pane_width}")
                filas = filas_consola(ser)
                pasos.append(f"panel de tmux {panel}, "
                             f"{filas} filas escritas en la consola")

                # El prompt tiene que estar en la ULTIMA fila de la consola, y
                # no una por encima: si el framebuffer es mas alto que la
                # ventana del emulador (lo que pasaba sin video=1280x720, con
                # 1280x800 en un monitor de 1366x768), la fila de abajo se
                # queda fuera de la pantalla y el usuario no ve nunca el prompt.
                # Se lee el texto del buffer de video, sin depender de pixeles.
                # Si esto falla, el resto del check no dice nada util sobre el
                # historial (la pantalla ya no es comparable), asi que se corta.
                con_prompt = False
                if filas > 0:
                    ultima = [f for f in consola_video(ser) if f.strip()][-1]
                    con_prompt = re.search(r"titan@titan", ultima) is not None
                    pasos.append(f"ultima fila ({filas}): {ultima.strip()[:60]!r}"
                                 f" -> es el prompt? {con_prompt}")
                    if not con_prompt:
                        c.fail("el prompt no esta en la ultima fila de la consola "
                               f"(fila {filas}: {ultima.strip()[:60]!r})")
                else:
                    c.fail("la consola de video esta vacia")

                # 1. La salida larga. ORDEN_LARGA no teclea ni un digito (ver
                #    alli el porque) y produce miles de lineas, asi que obliga a
                #    salirse de la pantalla decenas de veces: si el historial no
                #    funciona se pierde casi todo.
                #
                #    No hace falta saber de antemano cuantas lineas son: la cola
                #    de la salida es justo lo que se ve, y por definicion su
                #    ultimo numero ES la ultima linea que ha impreso la orden.
                #    Ademas tiene que verse un tramo largo y seguido de lineas,
                #    que es lo que demuestra que hay scroll y no una pantalla
                #    suelta: un numero suelto (el eco de la orden, el 6.18.54 del
                #    banner) no prueba nada.
                tramo_cola: tuple[int, int] | None = None
                for _ in range(4 if con_prompt else 0):
                    mon.type_text(ORDEN_LARGA)
                    mon.cmd("sendkey ret")
                    time.sleep(6)
                    tramo = run_consecutivo(numeros_pantalla(ser))
                    if tramo and tramo[1] - tramo[0] + 1 >= 20:
                        tramo_cola = tramo
                        break
                if not con_prompt:
                    pasos.append("sin comprobar el historial: la ultima fila de "
                                 "la consola no es el prompt")
                elif tramo_cola is None:
                    c.fail(f"la salida larga no se ve en la consola: visibles "
                           f"{sorted(numeros_pantalla(ser))}")
                    pasos.append(f"{ORDEN_LARGA}: sin tramo de 20 lineas seguidas")
                else:
                    total = tramo_cola[1]
                    pasos.append(f"cola de la salida: {tramo_cola[0]}..{tramo_cola[1]}"
                                 f" ({tramo_cola[1] - tramo_cola[0] + 1} lineas)")
                    # Cuantas lineas se han salido ya de la pantalla. Es la
                    # prueba de que la salida es de verdad mas larga que esto.
                    hist = tmux_dato(ser, "#{history_size}")
                    pasos.append(f"historial de tmux: {hist} lineas desplazadas")
                    if not hist.isdigit() or int(hist) < 200:
                        c.fail("la salida no llego a salirse de la pantalla "
                               f"(historial de tmux: {hist!r} lineas)")
                    # 2. Una pulsacion de RePag: la vista sube una pantalla, asi
                    #    que el ultimo numero deja de verse y lo que se ve es un
                    #    tramo por encima del de antes.
                    else:
                        mon.sendkey("pgup")
                        time.sleep(2.5)
                        ns_arriba = numeros_pantalla(ser)
                        tramo_arriba = run_consecutivo(ns_arriba)
                        pasos.append(f"tras 1 RePag: {tramo_arriba}, "
                                     f"el ultimo sigue a la vista? {total in ns_arriba}")
                        if not tramo_arriba or total in ns_arriba:
                            c.fail("RePag no subio por el historial")
                        # 3. Cuarenta pulsaciones mas: cuarenta pantallas hacia
                        #    atras, o sea cientos de lineas, no tres en tres.
                        else:
                            mon.sendkey("pgup", veces=40)
                            time.sleep(6)
                            ns_lejos = numeros_pantalla(ser)
                            tramo_lejos = run_consecutivo(ns_lejos)
                            pasos.append(f"tras 41 RePag: {tramo_lejos}")
                            if not tramo_lejos:
                                c.fail("la pantalla se quedo en blanco al subir")
                            elif tramo_lejos[1] > tramo_arriba[1] - 200:
                                c.fail("el historial no llega mas atras que la "
                                       f"pantalla: con 41 pulsaciones se ve "
                                       f"{tramo_lejos} y con 1, {tramo_arriba}")
                            else:
                                # Captura del historial, para que se vea en el informe.
                                if mon.screendump(historial_ppm):
                                    png = (shutil.which("magick")
                                           or shutil.which("convert"))
                                    if png:
                                        subprocess.run([png, historial_ppm,
                                                        historial_png], check=False)
                                # 4. 'q' sale del historial y la vista vuelve sola
                                #    a la cola: la ultima linea se ve otra vez. Se
                                #    manda tambien Enter por si el 'q' hubiera
                                #    llegado a la shell (si el historial no hubiera
                                #    entrado), para no dejar la linea a medias.
                                mon.cmd("sendkey q")
                                mon.cmd("sendkey ret")
                                time.sleep(2.5)
                                ns_vuelta = numeros_pantalla(ser)
                                tramo_vuelta = run_consecutivo(ns_vuelta)
                                pasos.append(f"tras q: {tramo_vuelta}, "
                                             f"el ultimo vuelve? {total in ns_vuelta}")
                                if total not in ns_vuelta:
                                    c.fail("con q no se volvio al final de la salida")
                                else:
                                    c.pass_("la cola se ve, RePag relee lo salido "
                                            "y q vuelve al final")
        c.output = "\n".join(pasos)[:1500]
        checks.append(c)

        # 11. Apagado
        ser.send("sync; poweroff")
        time.sleep(6)

    except Exception as exc:  # noqa: BLE001 - el informe debe salir pase lo que pase
        log.write(f"\n# ERROR inesperado: {exc!r}\n")
        c = Check("0. la prueba no pudo terminarse")
        c.fail(repr(exc))
        checks.append(c)

    return finish(proc, checks, iso, report_path, log, log_path, shot_ppm, shot_png,
                  tmp, ser.sock, mon.sock, historial_ppm=historial_ppm,
                  historial_png=historial_png)


def finish(proc, checks, iso, report_path, log, log_path, shot_ppm, shot_png, tmp,
           *socks, historial_ppm="", historial_png="") -> int:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            proc.kill()
    for s in socks:
        if s is not None:
            try:
                s.close()
            except OSError:
                pass
    log.close()

    seen: dict[str, Check] = {}
    for c in checks:
        seen[c.name] = c
    ordered = list(seen.values())
    failed = [c for c in ordered if not c.ok]

    report = {
        "iso": iso,
        "fecha": time.strftime("%Y-%m-%d %H:%M:%S"),
        "resultado": "PASS" if not failed else "FAIL",
        "comprobaciones": [
            {"nombre": c.name, "ok": c.ok, "detalle": c.detail, "salida": c.output[:2000]}
            for c in ordered
        ],
    }
    with open(report_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, ensure_ascii=False)

    width = max((len(c.name) for c in ordered), default=20)
    for c in ordered:
        print(f"[{' OK ' if c.ok else 'FALLO'}] {c.name:<{width}}  {c.detail}")
    print()
    print(f"registro : {log_path}")
    print(f"informe  : {report_path}")
    for path in (shot_png, shot_ppm, historial_png, historial_ppm):
        if os.path.exists(path):
            print(f"captura  : {path}")
    shutil.rmtree(tmp, ignore_errors=True)

    if failed:
        print(f"\nRESULTADO: FAIL - {len(failed)} de {len(ordered)} comprobaciones fallidas")
        return 1
    print(f"\nRESULTADO: PASS - {len(ordered)}/{len(ordered)} comprobaciones")
    return 0


if __name__ == "__main__":
    sys.exit(main())
