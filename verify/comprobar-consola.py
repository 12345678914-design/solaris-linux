#!/usr/bin/env python3
"""Comprueba la clase que habla con la consola serie de QEMU.

Esta clase es la que decide si una orden ha terminado, asi que sus fallos son
pequenos de escribir y muy caros: un marcador que no se encuentra no da error,
solo un silencio, y en medio de una instalacion de cuarenta minutos ese silencio
se come la prueba entera. Los fallos que ya han pasado por aqui estan todos
como comprobaciones:

  1. El prompt de titan mete hipervinculos (OSC 8) y el reset de color (CSI),
     y el cierre de la secuencia se queda pegado AL PRINCIPIO de la linea
     siguiente. La marca llegaba como '\\x1b\\__TITAN_DONE_11__' y el ancla '^'
     no la encontraba nunca.
  2. El tty esta en ONLCR, asi que cada linea termina en '\\r\\n', y hay veces
     que el '\\r' cae al principio de la linea que sigue. La marca llegaba como
     '\\r__TITAN_DONE_11__' y '__TITAN_DONE_11__' no estaba en la columna 0.
  3. La consola hace eco de lo que se escribe. La marca se manda partida
     ('echo __TITAN_DONE_""11__') para que lo que se ve escrito no coincida con
     lo que imprime la shell. Si se pierde ese cuidado, el eco hace pasar la
     orden antes de tiempo.
  4. Una instalacion entera escurre decenas de megas. Recorrer el buffer
     entero en cada comprobacion consume la CPU del proceso y lo ralentiza
     hasta que parece colgado.

No hace falta QEMU para nada de esto: se le da un socket de mentira que
devuelve los bytes por trozos, como los devuelve de verdad un puerto serie.

    python3 verify/comprobar-consola.py
"""

from __future__ import annotations

import importlib.util
import io
import pathlib
import re
import sys

AQUI = pathlib.Path(__file__).resolve().parent
TV = AQUI.parent / "scripts" / "titan-verify.py"

spec = importlib.util.spec_from_file_location("titan_verify", TV)
assert spec and spec.loader
tv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tv)


class SockFalso:
    """Socket de mentira: entrega bytes a trozos, como un puerto serie de verdad.

    Cada trozo es lo que hay en la tuberia en ese momento. 'tras' son las
    llamadas a recv que se quedan sin datos: hace falta porque 'run' vacia la
    tuberia antes de mandar la orden, y lo interesante es lo que llega DESPUES
    de mandarla, que es lo unico que puede ser la salida. Cuando se acaba la
    lista devuelve b'' (fin de fichero), que es lo que hace que '_drain' pare.
    """

    def __init__(self, trozos: list[bytes], tras: int = 0) -> None:
        self.trozos = list(trozos)
        self.espera = tras

    def setblocking(self, _activo: bool) -> None:
        pass

    def recv(self, _n: int) -> bytes:
        if self.espera > 0:
            self.espera -= 1
            return b""
        if not self.trozos:
            return b""
        return self.trozos.pop(0)

    def sendall(self, datos: bytes) -> None:
        self.enviados = getattr(self, "enviados", b"") + datos


def consola(trozos: list[bytes], tras: int = 0) -> tuple[tv.Serial, io.StringIO]:
    """Una consola serie conectada al socket de mentira, con su log en memoria."""
    log = io.StringIO()
    ser = tv.Serial("/no/existe", log)
    ser.sock = SockFalso(trozos, tras)  # type: ignore[assignment]
    return ser, log


fallos = 0


def ok(nombre: str) -> None:
    print(f"  OK    {nombre}")


def falla(nombre: str, porque: str = "") -> None:
    global fallos
    fallos += 1
    print(f"  FALLO {nombre}" + (f"\n         {porque}" if porque else ""))


def comprueba(nombre: str, condicion: bool, porque: str = "") -> None:
    ok(nombre) if condicion else falla(nombre, porque)


# El mismo filtro que usa la clase: si se probase con una copia, el
# comprobador no estaria midiendo lo que se usa.
PROMPT = tv.PROMPT


# --- lo que hay que quitar del texto -----------------------------------------
print()
print("== 1. plano() quita los tres tipos de escapes ==")
# CSI: el color del prompt.
comprueba("quita los escapes de color (CSI)",
          tv.plano("\x1b[38;2;120;132;150mtitan\x1b[0m@titan") == "titan@titan")
# OSC 8: el hipervinculo entero, con su secuencia de cierre.
comprueba("quita los hipervinculos (OSC 8)",
          tv.plano("\x1b]8;;https://x.example\x1b\\titan\x1b]8;;\x1b\\") == "titan")
# CR: el retorno de carro del tty, al final de linea y (peor) al principio.
comprueba("quita el retorno de carro", tv.plano("uno\r\ndos\rdos") == "uno\ndosdos")
# Y los tres a la vez, que es como llega de verdad.
crudo = ("\x1b[?2004l\r\x1b]3008;start=abc;type=command;cwd=/home/titan\x1b\\"
         "__TITAN_DONE_11__\r\n"
         "\x1b]3008;end=abc;exit=success\x1b\\"
         "\x1b[38;2;56;214;255mtitan\x1b[0m@$ ")
comprueba("la marca queda sola en su linea",
          bool(re.search(r"(?m)^__TITAN_DONE_11__$", tv.plano(crudo))),
          repr(tv.plano(crudo)))


# --- la marca se encuentra con todo ese ruido delante ------------------------
print()
print("== 2. la marca se encuentra aunque venga con ruido delante ==")
ECO = 'rm -f /tmp/x ; echo __TITAN_DONE_7__""'   # el eco de lo escrito
LIMPIO = "__TITAN_DONE_7__\r\n"
# La MISMA expresion que usa 'run' para buscar su marca, no una copia: si el
# codigo cambia el patron y el comprobador se queda con el viejo, no estaria
# comprobando nada de lo que de verdad se usa.
MARCA = tv.patron_marca("__TITAN_DONE_7__")

casos = {
    "marca sola": LIMPIO.encode(),
    "con el cierre de OSC pegado": (b"cwd=/home/titan\x1b\\" + LIMPIO.encode()),
    "con el cierre de CSI pegado": (b"\x1b[0m" + LIMPIO.encode()),
    "con un CR al principio de linea": (b"\r" + LIMPIO.encode()),
    "con las tres cosas": (b"\x1b[0m\r\x1b]3008;x;cwd=/home\x1b\\" + LIMPIO.encode()),
    "con el prompt entero pegado en la misma linea": (
        b"\x1b]3008;start=a;type=shell;cwd=/home/titan\x1b\\"
        b"\x1b[?2004h\x1b[38;2;56;214;255mtitan\x1b[0m@\x1b[0m:~$ " + LIMPIO.encode()),
    "con la marca partida entre dos lecturas": (
        b"salida previa\n__TITAN_DONE_7_" + b"_\r\n"),
}
for nombre, dato in casos.items():
    ser, _ = consola([dato])
    ser.buf = ""
    ser.mirado = 0
    # El buffer se llena antes de buscar, como si los bytes hubiesen llegado
    # mientras se esperaba.
    ser._drain()
    encontrado = ser.expect(MARCA, 0.2)
    comprueba(f"encuentra la marca: {nombre}", encontrado,
              f"buffer={ser.buf!r}")


# --- el eco NO puede hacer pasar la orden ------------------------------------
print()
print("== 3. el eco de lo escrito no hace pasar la orden ==")
# El eco lleva la marca partida, que es lo que se manda de verdad, y detras
# quedan las comillas del corte. Con eso, ninguna de las dos formas de la
# expresion puede dar por terminada una orden que no ha terminado.
ser, _ = consola([b'rm -f /tmp/x ; echo __TITAN_DONE_1__""\r\n'])
ser._drain()
comprueba("con el eco entero (y las comillas) no hay marca",
          not ser.expect(MARCA, 0.2), f"buffer={ser.buf!r}")
ser, _ = consola([b'echo __TITAN_DONE_""1__\r\n'])
ser._drain()
comprueba("con la marca partida no hay marca en el eco",
          not ser.expect(MARCA, 0.2))
# Una linea que tenga el texto de la marca pero siga escribiendo despues, tampoco.
ser, _ = consola([b"__TITAN_DONE_1__ y algo mas\n"])
ser._drain()
comprueba("una linea con la marca y texto detras no vale",
          not ser.expect(MARCA, 0.2))
# El caso bueno de verdad: eco con la marca partida, salida con la marca entera.
# La salida que devuelve 'run' no incluye ni el eco ni la marca: solo la salida
# del comando.
ser, log = consola([b'echo __TITAN_DONE_""1__\r\nhola\r\n__TITAN_DONE_1__\r\n'],
                   tras=1)
ok_, salida = ser.run("rm -f /tmp/x", timeout=0.5)
comprueba("con eco y salida, la orden termina y solo devuelve la salida",
          ok_ and salida == "hola", f"ok={ok_} salida={salida!r}")


# --- una orden larga: buffer enorme ------------------------------------------
print()
print("== 4. una orden larga no se come la CPU ==")
RUIDO = ("linea de relleno de la instalacion\n" * 4000)     # ~150 KiB
marca = b"\n__TITAN_DONE_5__\r\n"
# Todo el ruido llega primero, y la marca despues: el recorrido incremental
# tiene que mirar lo nuevo, no solo lo ya visto.
ser, _ = consola([RUIDO.encode()])
ser.n = 5
ser.buf = ""
ser.mirado = 0
ser._drain()                      # se traga el ruido entero
ser.sock.trozos.append(marca)      # y luego llega la marca
comprueba("encuentra la marca al final de un buffer de 150 KiB",
          ser.expect(r"(?m)^__TITAN_DONE_5__\s*$", 0.5),
          f"mirado={ser.mirado} len={len(ser.buf)}")
comprueba("el buffer pequeno si se revisa entero (asi no se pierde nada)",
          ser.mirado == len(ser.buf))
# Y que de verdad solo se revisa lo nuevo: con el buffer ya grande, la marca que
# llega justo despues de la costura tiene que salir igual.
ser, _ = consola([RUIDO.encode()])
ser.n = 5
ser._drain()
ser.mirado = len(ser.buf)
ser.sock.trozos.append(b"\n__TITAN_DONE_5__\r\n" + b"x" * 1000)
comprueba("marca justo despues de la costura (con 4 KiB de solape)",
          ser.expect(r"(?m)^[^\n]*__TITAN_DONE_5__\s*$", 0.5))
# El caso que obliga al solape: la marca llega PARTIDA justo en la costura, con
# la mitad antes de donde se empezo a mirar esta vez y la mitad despues. Sin
# mirar el solape, la marca no aparece nunca y la orden se cuelga.
ser, _ = consola([(RUIDO + "algo __TITAN_DO").encode()])
ser.n = 5
ser._drain()
ser.mirado = len(ser.buf)
ser.sock.trozos.append(b"NE_5__\r\n")
comprueba("marca partida justo en la costura (esto obliga al solape)",
          ser.expect(r"(?m)^[^\n]*__TITAN_DONE_5__\s*$", 0.5),
          f"mirado={ser.mirado} len={len(ser.buf)}")

# --- cuando algo falla, que el log lo diga -----------------------------------
print()
print("== 5. una orden sin marca deja rastro en el log ==")
ser, log = consola([b"esto no es la marca\n"], tras=1)
_, salida = ser.run("orden_larga", timeout=0.3)
texto = log.getvalue()
comprueba("avisa de que no llego la marca", "[[aviso]] sin marca" in texto)
comprueba("vuelca el buffer recibido", "[[buffer]]" in texto and "esto no es la marca" in texto)
comprueba("el volcado va al log, no a la salida de la orden",
          salida == "esto no es la marca", f"salida={salida!r}")


# --- el prompt de la shell tampoco es salida ---------------------------------
# Lo que sale despues, cuando la orden ya ha terminado, es el prompt pidiendo
# la siguiente. Se cuela en la salida igual que el eco y rompe las
# comprobaciones que comparan con algo exacto. Pasaba con
# 'sudo ls /root/instalador | wc -l': la orden devolvia 9, el filtro devolvia
# '9 titan@titan:~$' y la comprobacion decia que el live no traia el
# instalador. Un fallo de prueba que accuse al producto.
print()
print("== 6. el prompt de la shell no sale como salida ==")
PROMPT_LINEA = "\x1b[38;2;56;214;255mtitan\x1b[0m@/root\x1b[0m:\x1b[0m/root$ "
ser, _ = consola([b'echo __TITAN_DONE_""1__\r\n9\r\n__TITAN_DONE_1__\r\n'
                  + PROMPT_LINEA.encode() + b" "], tras=1)
ok_, salida = ser.run("sudo ls /root/instalador | wc -l", timeout=0.5)
comprueba("'wc -l' devuelve solo el numero, sin el prompt detras",
          ok_ and salida == "9", f"ok={ok_} salida={salida!r}")

# El prompt con codigos de color, que es como llega de verdad (ya sin escapes al
# pasar por plano(), pero el prompt en si sigue ahi).
ser, _ = consola([b'echo __TITAN_DONE_""1__\r\nSI-OK\r\n__TITAN_DONE_1__\r\n'
                  b"titan@titan:~$ "], tras=1)
_, salida = ser.run("echo SI-OK", timeout=0.5)
comprueba("tampoco se cuela el prompt con usuario@maquina:ruta$",
          salida == "SI-OK", f"salida={salida!r}")

# Y lo que NO es un prompt tiene que quedarse: una linea de salida que tenga un
# '$' o un '@' por dentro no se puede borrar. Se comparan las dos cosas por
# separado, porque "la salida es exactamente esta" y "el prompt no sale" son dos
# afirmaciones distintas: si fallan las dos a la vez, el mensaje de una sola
# linea senalaria a la mitad equivocada.
for linea in [b"precio: 5$ cada uno\n", b"correo: a@b.example\n",
              b"#!/bin/sh\necho hola\n", b"total: 9\n"]:
    ser, _ = consola([b'echo __TITAN_DONE_""1__\r\n' + linea
                      + b"__TITAN_DONE_1__\r\n" + PROMPT_LINEA.encode()], tras=1)
    _, salida = ser.run("orden", timeout=0.5)
    lineas = salida.splitlines()
    comprueba(f"la linea de salida se queda entera: {linea.decode().strip()!r}",
              salida.splitlines()[:len(linea.decode().strip().splitlines())]
              == linea.decode().strip().splitlines(),
              f"salida={salida!r}")
    comprueba(f"y el prompt no sale con ella: {linea.decode().strip()!r}",
              not PROMPT.match(lineas[-1].rstrip()) if lineas else False,
              f"salida={salida!r}")

# --- los escapes que no son ni colores ni hipervinculos -----------------------
# Todo lo de arriba es lo que se busca a proposito. Lo de esta seccion son los
# escapes que aparecieron SIN querer en la consola y que nadie habia puesto en
# ninguna regla: en los logs del 28 de septiembre, la linea de arranque de
# systemd traia esto, entero:
#
#   ESC 7  ESC[32766;32766H  ESC[6n  ESC 8  ESC]3008;start=1a16...;c7c[
#   ESC[0;32m  OK  ESC[0m] Finished ...
#
# Lo que se ve ahi:
#   * ESC 7 y ESC 8 son escapes de UN SOLO caracter (guardar y recuperar la
#     posicion del cursor). Los escribe el tty al limpiar la pantalla, que es
#     justo lo que hace systemd al arrancar. No son colores ni hipervinculos, y
#     ninguna de las reglas de arriba los tocaba.
#   * La cadena ESC]3008 (la que marca donde empieza una orden) llega SIN
#     terminar: no hay BEL ni ESC barra invertida cerrandola. Se perdio una
#     parte, o todavia no ha llegado.
#
# Las dos cosas juntas se comeian el texto de la cadena: la consola decia
# "...;machineid=2fa9e53defb54ac096ba9fc14d88910e;invocationid=35580bb1..." en
# mitad de la salida. Eso no es lo que habia escrito ningun programa, pero
# parece texto de programa, y una comprobacion que lo encuentre se da por
# contenta con el. Es el mismo fallo que el del prompt, con un disfraz mejor.
print()
print("== 7. los escapes que nobody habia puesto en ninguna regla ==")

# El caso exacto, copiado del log, con la parte de la cadena que se perdio
# incluida. Lo que tiene que quedar es la linea de systemd de verdad: la del
# 'OK' y el 'Finished', y nada de la cadena.
REAL = ("\x1b7\x1b[32766;32766H\x1b[6n\x1b8\x1b]3008;start=1a16ced1afdd4b3781a8ff4c"
        "656682f1;user=root;hostname=titan;machineid=2fa9e53defb54ac096ba9fc14d"
        "88910e;bootid=2628dc06f2cc4724a265d234d60d9888;pid=480;pidfdid=481;comm"
        "=(temd-firstboot);servicename=systemd-firstboot.service;invocationid="
        "35580bb1d67e4ed7a71941c5de27ac7c[\x1b[0;32m  OK  \x1b[0m] Finished "
        "\x1b[0;1;39mInitial Setup\x1b[0m.\r\r\n")
limpio = tv.plano(REAL)
# Ojo al corchete de apertura: systemd escribe '[  OK  ] Finished', y aqui sale
# '  OK  ] Finished'. El corchete de apertura no se pierde por culpa de las
# reglas, se perdio EN LA CONSOLA: forma parte del trozo de la cadena que se
# corto, y con el se fue. No se puede recuperar, y no tiene sentido fingir que
# si: lo que se comprueba es que no queda el texto de la cadena, que es lo
# unico que estaba haciendo ruido.
comprueba("de la linea de systemd no queda mas que la linea de systemd",
          limpio == "  OK  ] Finished Initial Setup.\n",
          f"salida={limpio!r}")
comprueba("y no queda ni rastro de la cadena sin terminar",
          not re.search(r"machineid=|invocationid=|3008|start=", limpio),
          f"salida={limpio!r}")
comprueba("ni del ESC suelto del cursor",
          "\x1b" not in limpio, f"salida={limpio!r}")

# Y por separado, cada regla con su caso, para que cuando falle una se sepa
# cual de las dos es: si esto se juntara en un solo 'comprueba', un fallo
# diria 'queda basura' y no dira cual.
comprueba("un escape de un solo caracter se quita (ESC 7, ESC 8)",
          tv.plano("\x1b7hola\x1b8") == "hola",
          f"salida={tv.plano(chr(27) + '7hola' + chr(27) + '8')!r}")
comprueba("una cadena sin terminar se quita entera",
          tv.plano("\x1b]3008;start=abc;machineid=xyz\nsalida") == "\nsalida",
          f"salida={tv.plano(chr(27) + ']3008;start=abc;machineid=xyz')!r}")
# Y que la regla de la cadena sin terminar NO se pase de lista: se come hasta
# el siguiente escape, y lo que hay despues se queda. Si se comiera hasta el
# fin de linea, se llevaria por delante la salida de verdad que viene detras.
sigue = tv.plano("\x1b]3008;start=abc;c7c[\x1b[0;32mOK\x1b[0m salida")
comprueba("la cadena sin terminar para en el escape siguiente, no mas alla",
          sigue == "OK salida", f"salida={sigue!r}")
# Y que una cadena bien cerrada no se toque de mas, que es el error al reves:
# un '.*' demasiado gloton se lleva la linea entera.
bien = tv.plano("\x1b]8;;https://x.example\x1b\\texto\x1b]8;;\x1b\\ mas")
comprueba("una cadena bien cerrada se quita solo a si misma",
          bien == "texto mas", f"salida={bien!r}")

print()
if fallos:
    print(f"RESULTADO: {fallos} fallo(s)")
    sys.exit(1)
print("RESULTADO: todo correcto")
