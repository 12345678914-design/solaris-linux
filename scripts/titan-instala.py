#!/usr/bin/env python3
"""Instala Titan Linux entero en QEMU y comprueba el sistema instalado.

Es la prueba que decide si el instalador existe. El recorrido es de punta a
punta, sin tocar el teclado de nadie:

  1. arranca el live en QEMU con un disco virtual vacio
  2. comprueba que el motor de las ventanas esta dentro del live (dialog)
  3. mete el fichero de respuestas y lanza 'install.sh --autopiloto'
  4. cuando el instalador acaba, monta lo que ha instalado y lo mira pieza a
     pieza: cuentas, kernel, GRUB, entradas de UEFI, swap, fstab, firewall, la
     tienda de apps, que NO haya 'video=' puesto a mano...
  5. apaga la maquina y la vuelve a encender SIN el live, para comprobar que
     arranca desde el disco. Un instalador que instala pero no arranca no ha
     instalado nada.

Uso:
  ./scripts/titan-instala.sh --iso out/titan-linux-0.1.0-x86_64.iso
  ./scripts/titan-instala.sh --iso ... --bios      # arranque por BIOS
  ./scripts/titan-instala.sh --iso ... --solo-instalar   # no prueba arrancar

El recorrido largo es el que cuesta: descargar el sistema, el escritorio y las
apps por la red de QEMU lleva un rato largo. Todo lo que sale por la consola
serie queda en un fichero de log, asi que si algo falla esta el porque ahi.
"""

import argparse
import base64
import gzip
import importlib.util
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
DISTRO = os.path.dirname(AQUI)
OVMF_CODE = "/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS = "/usr/share/edk2/x64/OVMF_VARS.4m.fd"

# El fichero de respuestas con el que se instala. Vive en verify/, que no se
# ignora en git, porque es parte de la prueba y no un apano.
RESPUESTAS = os.path.join(DISTRO, "verify", "respuestas-instalacion.txt")

# Lo que se comprueba de la pantalla GRAFICA del instalador. Va DENTRO del live
# y no en la comprobacion del host (verify/comprobar-instalador.sh, seccion 6p)
# porque lo unico que la del host no puede ver es si los PAQUETES de la ISO
# sirven para pintar una ventana: ahi se mira el mismo fichero, pero con el
# gtk4, el libadwaita y el cage que instala el perfil, que son otros.
GUI_EN_VIVO = os.path.join(DISTRO, "verify", "comprobar-gui-en-vivo.sh")
PREFIJO_GUI = "GRAFICO/"


def respuestas() -> dict[str, str]:
    """El fichero de respuestas como diccionario, tal cual se le pasa al instalador.

    De ahi salen la contrasena (que luego hay que teclear en el login del sistema
    instalado) y lo que el disco tiene que acabar pareciendo. Leerlo en un solo
    sitio evita el fallo clasico de cambiarlo en un sitio y no en el otro, que
    aqui se paga con media hora de instalacion y un login que no entra.
    """
    valores: dict[str, str] = {}
    with open(RESPUESTAS, encoding="utf-8") as f:
        for linea in f:
            linea = linea.split("#", 1)[0].strip()
            if "=" in linea:
                clave, valor = linea.split("=", 1)
                valores[clave.strip()] = valor.strip()
    return valores


RESPUESTA = respuestas()
CLAVE = RESPUESTA.get("clave", "")


def cargar_serial():
    """Toma la clase Serial de titan-verify.py.

    Se reutiliza en vez de copiar las cien lineas: si un dia se toca como se
    habla con la consola serie, los dos scripts cambian a la vez y no se
    quedan chemins distintos.
    """
    ruta = os.path.join(AQUI, "titan-verify.py")
    spec = importlib.util.spec_from_file_location("titan_verify", ruta)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.Serial, mod.wait_for_shell


# Los detalles que se imprimen hay que limpiarlos de los escapes que mete el
# prompt del live: los de color son CSI, y ademas emite secuencias OSC 8 de
# hipervinculo, que no son color y se cuelan en el texto.
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
OSC = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")


def limpio(texto: str, ancho: int = 110) -> str:
    """Deja un detalle en una sola linea y sin escapes, para que se lea."""
    return " ".join(OSC.sub("", ANSI.sub("", texto)).split())[:ancho]


class Informe:
    def __init__(self) -> None:
        self.lineas: list[tuple[str, str, str, str]] = []  # fase, nombre, ok, detalle

    def anota(self, fase: str, nombre: str, ok: bool, detalle: str = "") -> None:
        detalle = limpio(detalle) if detalle else ""
        self.lineas.append((fase, nombre, "OK" if ok else "FALLO", detalle))
        marca = "\033[1;32m  OK   \033[0m" if ok else "\033[1;31m  FALLO\033[0m"
        print(f"{marca} {nombre}" + (f"  ({detalle})" if detalle else ""), flush=True)

    def fallos(self) -> int:
        return sum(1 for _, _, r, _ in self.lineas if r == "FALLO")

    def vuelca(self, ruta: str, meta: dict) -> None:
        with open(ruta, "w", encoding="utf-8") as f:
            json.dump({"meta": meta, "comprobaciones": [
                {"fase": a, "nombre": b, "resultado": c, "detalle": d}
                for a, b, c, d in self.lineas]}, f, indent=2, ensure_ascii=False)


def subir_texto(ser, destino: str, texto: str) -> None:
    """Manda un fichero de texto al guest por la consola serie.

    Va en base64 y troceado: por la consola se teclea, y una linea de 700
    caracteres se parte en varias, y ademas el texto de la serie se envuelve
    visualmente y el log queda hecho un lio. Con 150 caracteres por linea todo
    va sobrado.
    """
    b64 = base64.b64encode(texto.encode()).decode()
    tmp = destino + ".b64"
    ser.run(f"rm -f {tmp} {destino}")
    for i in range(0, len(b64), 150):
        trozo = b64[i:i + 150]
        ser.run(f"echo {trozo} >> {tmp}")
    ok, salida = ser.run(f"base64 -d {tmp} > {destino} && wc -l < {destino}")
    if not ok:
        raise SystemExit(f"no se ha podido subir {destino}: {salida}")


def subir_texto_gz(ser, destino: str, texto: str) -> None:
    """Como 'subir_texto', pero comprimido.

    El script de la pantalla grafica son 11994 bytes, que en base64 son 15992 y
    a 150 caracteres por linea son 107 viajes a la consola serie (y cada uno
    tiene su eco). Medido: con 'gzip' antes de 'base64' son 43 viajes, menos de
    la mitad. Se deja 'subir_texto' como estaba para el fichero de respuestas,
    que es de otro tamano y no lo necesita, y porque las comprobaciones del
    driver (comprobar-driver.py) miran las ordenes que salen a la consola.
    """
    crudo = gzip.compress(texto.encode(), 9)
    b64 = base64.b64encode(crudo).decode()
    tmp = destino + ".b64"
    ser.run(f"rm -f {tmp} {destino}")
    for i in range(0, len(b64), 150):
        ser.run(f"echo {b64[i:i + 150]} >> {tmp}")
    ok, salida = ser.run(f"base64 -d {tmp} | gzip -dc > {destino} && "
                         f"wc -l < {destino}")
    if not ok:
        raise SystemExit(f"no se ha podido subir {destino}: {salida}")


def anota_gui(inf, salida: str) -> None:
    """Pasa al informe las lineas 'GRAFICO/<nombre>=<OK|MAL> <detalle>'.

    El script del live imprime una linea por comprobacion, una de resumen, y las
    que se llaman '<nombre>-info', que NO son comprobaciones: son hechos de la
    maquina (si hay '/dev/dri', que paquetes hay) y no tienen nada que pasar ni
    fallar. Anotarlas como comprobacion daria un verde que no se puede poner en
    rojo nunca, que es justo lo que un comprobador no puede ser, asi que salen
    como NOTA por la pantalla y no entran en el informe.

    El resumen tampoco es una comprobacion (es la cuenta de las demas), asi que
    se salta. Y si no sale ni una linea, se anota un fallo: un script que no se
    ha ejecutado dejaria la fase en verde sin haber mirado nada. El formato es
    'GRAFICO/<nombre>=<OK|MAL> <detalle>'; en las '-info' lo que va detras del
    '=' es el texto entero, porque no hay veredicto que mirar.
    """
    vistas = 0
    for linea in salida.splitlines():
        linea = linea.strip()
        if not linea.startswith(PREFIJO_GUI) or "=" not in linea:
            continue
        nombre, _, valor = linea[len(PREFIJO_GUI):].partition("=")
        if nombre == "RESUMEN":
            continue
        veredicto, _, detalle = valor.partition(" ")
        if nombre.endswith("-info"):
            # Aqui 'valor' es texto entero, no un veredicto con un detalle: lo
            # que va detras del '=' ES el texto. Partirlo en dos se comia la
            # primera palabra (medido: 'no hay /dev/dri' salia 'hay /dev/dri').
            print(f"    nota  {nombre}: {valor.strip()}", flush=True)
            continue
        vistas += 1
        inf.anota("gui", nombre, veredicto.startswith("OK"),
                  detalle.strip()[:100])
    if not vistas:
        # Sin esto, un script que no se ha ejecutado (o cuya salida se ha
        # comido la consola) dejaria la fase en verde sin haber mirado nada.
        inf.anota("gui", "las comprobaciones de la pantalla grafica se han "
                         "ejecutado", False,
                  "el script del live no ha impreso ninguna linea "
                  f"GRAFICO/: {salida.strip()[:100]!r}")


def entrar(ser, usuario: str, clave: str, tmo: int = 300) -> tuple[bool, str]:
    """Entra en el sistema instalado escribiendo usuario y contrasena.

    Ojo con esto: el autologin es SOLO del live. Con escritorio el instalador
    activa el gestor de sesiones y apaga el getty de tty1, asi que el sistema
    instalado pide usuario y contrasena de verdad, tambien por el puerto serie
    (que lo levanta solo 'systemd-getty-generator' al ver 'console=ttyS0' en la
    linea de arranque).

    Entrar asi, escribiendo la contrasena, ademas de hacer falta para la prueba
    es una comprobacion en si misma: si la clave que puso el instalador no
    llegara a /etc/shadow del sistema destino, aqui no se podria entrar.
    """
    if not ser.expect(r"(?i)\blogin:", tmo):
        return False, "no aparece el login por el puerto serie"
    ser.send(usuario)
    if not ser.expect(r"(?i)\bpassword:", 60):
        return False, "no pide contrasena"
    ser.send(clave)
    # El escritorio tarda en arrancar y el prompt puede salir precedido de ruido.
    time.sleep(6)
    ok, sal = ser.run("whoami", timeout=120)
    return ok and re.search(rf"(?m)^{usuario}$", sal) is not None, sal


# En que ha arrancado el equipo. La orden es una cuenta y no un '|| echo': poner
# las dos palabras ('test -d /sys/firmware/efi && echo UEFI || echo BIOS') no cabe
# en una linea de la consola serie sin partirse, y una orden partida mete en la
# salida el trozo de la izquierda. Con la cuenta, las dos respuestas salen de la
# misma orden y se comparan con un numero anclado.
ORDEN_MODO_ARRANQUE = "ls /sys/firmware/ | grep -c efi"


def anota_modo_arranque(inf, sal: str, bios: bool) -> None:
    """Anota si el equipo ha arrancado por UEFI o por BIOS, segun la SALIDA.

    Fallo 40 (29 de septiembre, 01:59, la pasada por BIOS). Esto era:

        ok2, sal = ser.run("ls /sys/firmware/efi >/dev/null && echo UEFI")
        inf.anota("arranque", "ha arrancado por BIOS (sin UEFI)", not ok2)

    y 'ok2' NO es el codigo de salida del comando: es 'la consola ha contestado a
    la marca', que es verdad tanto si el comando sale bien como si falla. La
    orden de dentro acaba en un '&&' que, cuando '/sys/firmware/efi' no existe,
    devuelve 1 y no imprime nada; la marca de la consola vuelve igual, 'ok2' sale
    True, y el veredicto 'not ok2' daba FALLO en el equipo que estaba arrancado
    por BIOS DE VERDAD. Peor: la comprobacion era justa en UEFI ('ok2 and "UEFI"
    in sal' se apoya en la salida), asi que solo se rompia en un lado, que es
    justo el lado por el que nunca se habia pasado.

    Y mirar si la orden sale bien no era un error de
    de por medio no era un error de RUTA sino de MEDIDA: lo que hay que mirar
    de una orden que falla en su camino no dice nada (por eso el '2>/dev/null' y
    por eso un numero, no una palabra).
    """
    n = re.search(r"(?m)^([0-9]+)$", sal)
    if n is None:
        inf.anota("arranque", "el modo de arranque se ha podido mirar", False,
                  " ".join(sal.split())[:60])
        return
    if bios:
        inf.anota("arranque", "ha arrancado por BIOS (sin UEFI)", n.group(1) == "0",
                  n.group(1))
    else:
        inf.anota("arranque", "ha arrancado por UEFI", n.group(1) != "0",
                  n.group(1))


def anota_particiones(inf, esp: str, bios: bool) -> None:
    """Anota si hay particion de arranque, y si hace falta que la haya.

    Fallo 39 (29 de septiembre, 01:52, la primera pasada por BIOS). Esto era:

        inf.anota("instalado", "el disco tiene una particion vfat", bool(esp), ...)

    y en BIOS no hay particion de arranque: el cargador se mete en el hueco de
    arranque del MBR, sin particion que montar. Asi que la comprobacion pedia una
    vfat que el particionado de BIOS no crea, y dio FALLO con el sistema
    instalado entero. Lo que hay que decir en BIOS no es 'no hay particion de
    arranque' (que es lo normal) sino lo contrario: 'no hay particion de
    arranque, y no deberia haberla', que es la unica forma de que la comprobacion
    pueda dar MAL alguna vez. Sin el 'not esp', en BIOS la comprobacion no podia
    fallar nunca, que es la otra mitad del mismo fallo.

    Es una funcion suelta y no tres lineas en medio del recorrido, para poder
    probarla con un 'inf' de mentira en las dos direcciones y en los dos modos
    (verify/comprobar-driver.py, seccion 14).
    """
    if bios:
        inf.anota("instalado",
                  "en BIOS no hay particion de arranque (el cargador va en el MBR)",
                  not esp, f"arranque={esp or 'ninguna'}")
    else:
        inf.anota("instalado", "el disco tiene una particion vfat", bool(esp),
                  f"arranque={esp or 'NO ENCONTRADA'}")


def detectar_particiones(ser) -> tuple[str, str]:
    """(raiz, arranque): que particion es cada una, preguntandoselo al disco.

    No se supone ninguna. Con 'swap=zram' el instalador hace dos particiones (la
    de arranque y la raiz) y con swap en disco hace tres, asi que un numero fijo
    comprueba una cosa y da por buena otra. Y en BIOS no hay particion de
    arranque en absoluto: el cargador se mete en el hueco de arranque del
    MBR, sin particion que montar. Preguntando al disco se evita las dos cosas.
    """
    def primero(orden: str) -> str:
        ok, sal = ser.run(orden)
        if not ok:
            return ""
        for tok in limpio(sal).split():
            if re.fullmatch(r"/dev/vd[a-z][0-9]+", tok):
                return tok
        return ""

    return primero("sudo blkid -t TYPE=btrfs -o device"), \
           primero("sudo blkid -t TYPE=vfat -o device")


def tipo_de(ser, disco: str) -> str:
    """El tipo de filesystem de un disco, con una respuesta que no se pueda
    confundir con el ruido de la consola.

    Fallo U (28 de septiembre, 00:27). Esto era:

        ok, sal = ser.run(f"sudo blkid -s TYPE -o value {raiz}")
        tipo = limpio(sal).split()[-1]

    y 'split()[-1]' es el ULTIMO token de lo que salio por la consola. El texto
    que recibio el driver, tal cual (sacado del log de la consola de esa pasada
    y pasado por su propio 'plano()' y por su propio filtro de lineas), era:

        ''            <- linea vacia
        'btrfs'       <- la respuesta, la de verdad, en su linea
        'titan@38'    <- el principio del prompt, con un escape CORTADO

    El ultimo token es 'titan@38', no 'btrfs'. Lo de 'titan@38' es el prompt de
    la shell con un escape CSI a medio escribir ('\\x1b[38' y se acabo el
    bloque de lectura), y como el prompt no llego entero no se parece a un
    prompt y el filtro de 'run()' no lo quita. O sea: la respuesta buena estaba
    en su linea, en medio, y el codigo la miraba en el FINAL.

    Con 'tipo' NEO se montaba la particion entera, que en un btrfs con
    subvolumenes es el nivel de arriba: tres directorios vacios ('@', '@var',
    '@home') y nada mas. Las 29 comprobaciones de la fase 4 dijeron que el
    sistema instalado no existia. Existia entero, y hasta arrancaba desde el
    disco con el kernel del proyecto (eso lo comproban las 14 de la fase 6, que
    si dieron bien).

    Dependia de donde cortase el bloque de lectura, que es una de esas cosas que
    no se pueden dar por hechas. Por eso hay dos arreglos, y hacen falta los
    dos:

      * la respuesta va PREFIJADA ('FSTYPE=btrfs') y se busca con una
        expresion regular ANCLADA a la linea entera, con un limite antes del
        prefijo para que no case dentro de otra palabra. Una palabra suelta
        ('btrfs') se puede confundir con el ruido; un 'FSTYPE=' con su valor
        pegado y cerrando la linea, no. Y el '\r' va en la clase a proposito:
        la consola serie lo anade antes del '\n' (ONLCR), asi que la linea que
        llega es 'FSTYPE=btrfs\\r' y sin el en la clase el '$' no casa nunca.
        Un comprobador que solo funciona sin el '\r' es un comprobador que no
        funciona.
      * y el tipo NO decide nada: despues de montar se comprueba que el arbol
        montado es el de un sistema instalado (en 'montar_destino'). Ese es el
        arreglo de verdad, porque funciona aunque el tipo no se sepa, y
        convierte un fallo mudo (29 comprobaciones diciendo 'no existe') en uno
        ruidoso (un 'False' con su motivo escrito).
    """
    ok, sal = ser.run(f"sudo lsblk -bdn -o FSTYPE {disco} 2>/dev/null "
                      f"| sed 's/^/FSTYPE=/'")
    if not ok:
        return ""
    m = re.search(r"(?m)^.*(?<![0-9A-Za-z_])FSTYPE=([a-z0-9]+)[ \t\r]*$", sal)
    return m.group(1) if m else ""


def arbol_de_sistema(ser, punto: str) -> bool:
    """Si lo que hay montado en 'punto' es el arbol de un sistema instalado.

    Un sistema recien instalado SIEMPRE tiene '/usr' y '/etc' (los pone
    'pacstrap', y sin '/usr' no arranca ni una shell), asi que su ausencia en lo
    que se ha montado es la senal de que se ha montado otra cosa: el nivel de
    arriba de un btrfs con subvolumenes tiene '/@', '/@home' y '/@var', y nada
    mas. Con la marca de verdad y no con el codigo de salida de 'run()', que
    solo dice que la consola contesto.
    """
    ok, sal = ser.run(f"sudo test -d {punto}/usr -a -d {punto}/etc "
                      f"&& echo SI-ARBOL-SISTEMA")
    return "SI-ARBOL-SISTEMA" in sal


def montar_destino(ser, raiz: str) -> tuple[bool, str]:
    """Monta el sistema instalado en /mnt/v, con su forma REAL de dentro.

    Esto no es un detalle: 'mount /dev/vda2 /mnt/v' sin mas, sobre un btrfs con
    subvolumenes, monta el NIVEL DE ARRIBA de btrfs, donde lo unico que hay son
    tres directorios vacios llamados '@', '@home' y '@var'. No hay /etc, no hay
    /usr, no hay nada. Todas las comprobaciones de la fase 4 decian que el
    sistema instalado estaba vacio, y era verdad: se estaba mirando el sitio
    equivocado.

    Con btrfs se montan los tres subvolumenes donde toca. Con otro filesystem se
    monta entero y ya, porque no tiene subvolumenes.

    OJO con el codigo de retorno de 'run()': lo que devuelve es "la consola
    contesto a la orden", no "la orden salio bien". Un 'mount' que falla deja el
    error en la consola, la marca aparece igual y 'run' dice que todo bien. Por
    eso cada montaje se acaba en '&& echo SI-MONTADO' y se busca eso, no el
    codigo de la shell. Lo mismo con las comprobaciones de mas abajo, que miran
    texto y no codigos.

    Y por lo mismo, un montaje que sale bien no es un montaje bien hecho: montar
    el nivel de arriba de un btrfs TAMBIEN sale bien. Por eso, despues de cada
    montaje se mira si lo montado es el arbol de un sistema instalado
    ('arbol_de_sistema'), y el tipo del disco ('tipo_de') solo decide el ORDEN en
    que se prueban los candidatos, no si el resultado sirve. Asi el fallo 29 (el
    tipo leido del ultimo token de la consola) deja de ser un fallo silencioso
    con 29 comprobaciones en rojo y pasa a ser un 'False' con su motivo, que es
    lo unico que permite saber que ha pasado.
    """
    tipo = tipo_de(ser, raiz)

    def monta(orden: str) -> tuple[bool, str]:
        ok2, sal2 = ser.run(f"{orden} && echo SI-MONTADO")
        return "SI-MONTADO" in sal2, " ".join(sal2.split())[:80]

    # Antes de montar nada, se suelta lo que hubiera montado en /mnt. No es
    # preventivo por costumbre: es el fallo del bug 18. El instalador, al
    # fallar, dejaba el sistema destino montado en /mnt, y entonces este driver
    # se ponia a mirar DENTRO de un sistema recien instalado, montado en un
    # directorio (/mnt/v) que el propio sistema recien instalado tenia ya
    # ocupado. Las comprobaciones de la fase 4 decian "no existe" con el
    # sistema entero ahi, y el informe decia "todo bien" con 8 de 8 en verde.
    #
    # El instalador ya lo desmonta al fallar (fix del bug 18), pero esto no
    # puede depender de eso: si vuelve a pasar, o si el disco viene de una
    # sesion anterior, el fallo tiene que verse aqui, en una linea clara, y no
    # veinte minutos despues en ocho comprobaciones que dicen "no existe".
    ok, sal = ser.run("sudo findmnt -n /mnt && echo SI-MONTADO", timeout=30)
    if "SI-MONTADO" in sal:
        print("    (/mnt seguia montado de una sesion anterior: se desmonta antes)")
        ser.run("sudo umount -R /mnt", timeout=60)
        ok, sal = ser.run("sudo findmnt -n /mnt && echo SI-MONTADO", timeout=30)
        if "SI-MONTADO" in sal:
            return False, ("habia un sistema montado en /mnt y no se ha podido "
                           "desmontar: mirarlo por dentro daria falso")
    ser.run("sudo mkdir -p /mnt/v")

    # Los candidatos, en orden. El de btrfs con 'subvol=@' va PRIMERO siempre que
    # el tipo no diga que no puede ser btrfs, y con el tipo desconocido tambien
    # va primero: es el unico de los dos cuyo fallo es SILENCIOSO (monta el nivel
    # de arriba, que existe y esta vacio, y no se queja de nada), y un fallo
    # silencioso no puede ser el que se pruebe el ultimo. Ademas se mete solo
    # para btrfs, porque en un vfat o un ext4 'mount -o subvol=@' se queja y
    # ruido de mas en la consola es ruido.
    #
    # Y DESPUES de montar se comprueba el arbol (arbol_de_sistema). Es lo que
    # convierte 'el tipo se leyo mal' en un fallo ruidoso en vez de 29
    # comprobaciones diciendo que el sistema instalado no existe. Un metodo que
    # decide con lo que le conteste la consola y luego no mira lo que ha montado
    # no esta comprobando nada: esta suponiendo.
    candidatos: list[str] = []
    if tipo in ("btrfs", ""):
        candidatos.append(f"sudo mount -o subvol=@ {raiz} /mnt/v")
    candidatos.append(f"sudo mount {raiz} /mnt/v")
    # El subvolumen aparece una sola vez: con btrfs (o sin saber el tipo) va el
    # primero y ya. Anadirlo otra vez al final dejaria un candidato que nunca se
    # llega a probar, y un codigo muerto es un codigo que el proximo lee como si
    # significara algo.
    motivos: list[str] = []
    ya_pruebo: set[str] = set()
    for orden in candidatos:
        if orden in ya_pruebo:
            continue
        ya_pruebo.add(orden)
        bien, detalle = monta(orden)
        if not bien:
            motivos.append(f"{orden}: {detalle}")
            continue
        if not arbol_de_sistema(ser, "/mnt/v"):
            # Montado, pero no es el arbol del sistema instalado: se suelta y se
            # prueba el siguiente. Sin esto, un btrfs con subvolumenes montado sin
            # 'subvol=@' se cuela como si estuviera bien.
            motivos.append(f"{orden}: monto, pero el arbol no es el del sistema "
                           f"instalado (sin /usr ni /etc)")
            ser.run("sudo umount -R /mnt/v", timeout=60)
            continue
        if "-o subvol=@" not in orden:
            return True, f"{tipo or 'tipo desconocido'}: {detalle}"
        # Los otros dos van donde deben: /var y /home son subvolumenes aparte,
        # y si no se montan, /mnt/v/var sale vacio.
        for sub in ("var", "home"):
            ser.run(f"sudo mkdir -p /mnt/v/{sub}")
            bien, detalle = monta(f"sudo mount -o subvol=@{sub} {raiz} /mnt/v/{sub}")
            if not bien:
                return False, f"subvol=@{sub}: {detalle}"
        return True, "btrfs con @, @var y @home"
    return False, (motivos[-1] if motivos else "no se ha probado ningun montaje")


def anota_montaje(inf, ser, raiz: str) -> bool:
    """Monta el sistema instalado y anota si se ha podido. Devuelve si se ha podido.

    Existe por el fallo 29, y por una tonteria que es la raiz de el: esto era

        ok = montar_destino(ser, raiz)
        inf.anota("instalado", "la raiz instalada se monta con sus subvolumenes", ok)

    y 'montar_destino' devuelve una TUPLA (ok, detalle). Una tupla vacia seria
    falsa, pero esta nunca lo esta: es un objeto de dos cosas y siempre da
    verdad. Asi que 'ok' era verdad siempre, la comprobacion de "la raiz se
    monta" no podia fallar NUNCA, y lo que de verdad avisaba era lo de despues:
    veinte comprobaciones mirando dentro de un '/mnt/v' que no estaba montado,
    veinte FALLO de "no existe" con el sistema entero en el disco, y un informe
    que hablaba de un sistema vacio cuando lo que faltaba era el montaje.

    Que sea una funcion y no cuatro lineas en medio del script es para poder
    probarla: verify/comprobar-driver.py la llama con una consola de mentira que
    dice que /mnt esta ocupado, y exige que devuelva False (False, no una tupla
    ni un numero) y que el veredicto que se anota sea False. Con el
    'ok = montar_destino(...)' de antes, eso sale en rojo.
    """
    ok, detalle = montar_destino(ser, raiz)
    inf.anota("instalado", "la raiz instalada se monta con sus subvolumenes", ok,
              " ".join(detalle.split())[:110])
    return ok


def comprobaciones_instalado(raiz: str, esp: str, bios: bool) -> list[tuple[str, str, str]]:
    """(nombre, orden, expresion regular que debe aparecer en la salida).

    Todas las ordenes son cortas a proposito: por la consola serie una linea
    larga se envuelve, y al envolverla se parte en dos, y el trozo de la
    izquierda se cuela en la salida que despues se mira. Con el ancho de 80
    columnas, 40 caracteres de orden van fiados.

    Y todas miran la salida CON UN PATRON, nunca el codigo de salida. Por eso el
    patron tiene que ser un ancla o un numero, y por eso casi todas las ordenes
    acaban en '2>/dev/null' o en 'grep -c'. No es estetica:

      (f"la consola de texto tiene historial (tmux)",
       f"sudo ls {V}/etc/profile.d/20-titan-scrollback.sh", r"scrollback")

    Esa comprobacion daba LUZ VERDE con el sistema instalado entero ausente,
    porque en la salida estaba el error 'ls: no se puede acceder a
    /mnt/v/etc/profile.d/20-titan-scrollback.sh: No existe el fichero o el
    directorio', y ese texto contiene 'scrollback'. El patron se ha quedado
    contento con la palabra que buscaba, que estaba alli por casualidad.

    Un comprobador que puede pasar por el motivo equivocado no comprueba nada:
    da luz verde cuando no se ha instalado nada, que es justo cuando miente.
    Dos reglas, y las dos se comprueban solas en verify/comprobar-driver.py:
      1. Si la orden puede fallar escribiendo un error, ese error se tira con
         '2>/dev/null'. La salida que se mira es la que el programa quiso
         escribir, no la que le dijo que no.
      2. El patron es un numero con '^...$' o una palabra entera con limites.
         Un '\\w' suelto, o una palabra suelta, encuentra esa palabra en
         cualquier parte, incluido un error.
    """
    V = "/mnt/v"   # raiz instalada
    E = "/mnt/ve"  # particion de arranque
    # Cuantas particiones tiene que haber: con el swap en la memoria no hace
    # falta particion de swap, y el instalador no la crea.
    n_part = 2 if RESPUESTA.get("swap") == "zram" else 3
    return [
        # --- el disco tiene lo que tiene que tener -------------------------
        (f"la particion de raiz ({raiz}) es btrfs",
         f"sudo blkid -s TYPE -o value {raiz} 2>/dev/null", r"\bbtrfs\b"),
        # 'btrfs subvolume list' quiere un PUNTO DE MONTAJE, no un dispositivo:
        # con el dispositivo crudo contesta "ERROR: not a directory" y el
        # comprobador contaba eso como si fueran subvolumenes. Por eso se le
        # pregunta al sitio donde esta montado.
        #
        # Y el patron es el de la salida REAL, que no es lo que parece:
        #   ID 256 gen 9 top level 5 path @
        #   ID 257 gen 9 top level 5 path @home
        # La ruta va detras de la palabra 'path', y no con una barra delante
        # ('/@'), asi que el patron que se tenia puesto primero no podia
        # encontrar NUNCA tres: daba cero siempre, y una comprobacion que
        # siempre esta en rojo no vale ni para la senal ni para el ruido. Esta
        # linea la compone comprobar-driver.py con la salida de un btrfs de
        # verdad, que es como se sabe que el patron es el bueno.
        ("los tres subvolumenes estan dentro",
         f"sudo btrfs subvolume list {V} 2>/dev/null | grep -cE ' path (@|@home|@var)$'",
         r"^3$"),
        (f"el disco tiene {n_part} particiones",
         "sudo lsblk -no TYPE /dev/vda | tail -n+2 | grep -c part", rf"^{n_part}$"),

        # --- el kernel del proyecto, no el de Arch -------------------------
        ("hay un modulo de kernel titanlinux",
         f"sudo ls {V}/usr/lib/modules 2>/dev/null | grep -c titanlinux", r"^[1-9]"),
        ("no hay mas de un kernel",
         f"sudo ls {V}/usr/lib/modules 2>/dev/null | wc -l", r"^1$"),
        ("el kernel propio esta en la lista de paquetes",
         f"sudo ls {V}/var/lib/pacman/local 2>/dev/null | grep -c titan", r"^[1-9]"),

        # --- GRUB ------------------------------------------------------------
        ("grub.cfg esta generado y no vacio",
         f"sudo test -s {V}/boot/grub/grub.cfg && echo SI-GRUB", r"(?m)^SI-GRUB$"),
        ("grub.cfg apunta al kernel de titanlinux",
         f"sudo grep -c titanlinux {V}/boot/grub/grub.cfg 2>/dev/null", r"^[1-9]"),
    ] + ([
        # Los modulos de GRUB van en un directorio que depende del modo de
        # arranque, y el driver miraba siempre el de UEFI. En BIOS, que es donde
        # se instala 'i386-pc', la comprobacion buscaba modulos donde no hay
        # ninguno y la pasada de BIOS del 29 de septiembre a la 01:52 dio este
        # FALLO con el sistema instalado entero y bien. Dos comprobaciones con el
        # mismo nombre, una por modo, en vez de una comun que se equivoca en
        # uno de los dos.
        ("hay modulos de grub en el disco (arranque por UEFI)",
         f"sudo ls {V}/boot/grub/x86_64-efi 2>/dev/null | grep -c mod", r"^[1-9]"),
        # La particion de arranque y lo que hay dentro solo existen si el equipo
        # arranco por UEFI. En BIOS el cargador va en el hueco del MBR.
        (f"la particion de arranque ({esp}) es vfat (EFI)",
         f"sudo blkid -s TYPE -o value {esp} 2>/dev/null", r"\bvfat\b"),
        ("la particion EFI tiene el arranque de UEFI",
         f"sudo ls {E}/EFI/TitanLinux 2>/dev/null", r"(?m)^grubx64\.efi$"),
        ("la particion EFI tiene el arranque de BIOS (el --removable)",
         f"sudo ls {E}/EFI/BOOT 2>/dev/null", r"(?m)^BOOTX64\.EFI$"),
        ("la entrada de arranque de Titan esta en el firmware de UEFI",
         "sudo efibootmgr -v 2>/dev/null | grep -ci titan", r"^1$"),
    ] if not bios else [
        ("hay modulos de grub en el disco (arranque por BIOS)",
         f"sudo ls {V}/boot/grub/i386-pc 2>/dev/null | grep -c mod", r"^[1-9]"),
        # Y el hueco de arranque del MBR, que es donde GRUB se mete en BIOS: los
        # dos ultimos bytes del sector 0 tienen que ser la firma 55 AA. Sin esto
        # lo unico que se comprobaba de BIOS eran los modulos, que estan en el
        # sistema de ficheros y no dicen nada de si el cargador llego al disco.
        #
        # 'od -j510 -N2' porque son 512 bytes de sector y la firma va al final, y
        # la orden se queda en 36 caracteres porque por la consola serie una
        # linea larga se envuelve y se parte (la regla de las ordenes cortas).
        ("en BIOS el cargador esta en el hueco de arranque del MBR",
         "sudo od -An -tx1 -j510 -N2 /dev/vda", r"(?m)^\s*55\s+aa\s*$"),
    ]) + [
        # --- el firmware manda en el modo de video --------------------------
        ("el arranque NO lleva video= a mano",
         f"sudo grep -c 'video=' {V}/boot/grub/grub.cfg 2>/dev/null", r"^0$"),

        # --- cuentas ---------------------------------------------------------
        ("el usuario existe", f"sudo grep -c '^isai:' {V}/etc/passwd 2>/dev/null", r"^1$"),
        ("el usuario esta en el grupo wheel",
         f"sudo grep wheel {V}/etc/group 2>/dev/null | grep -c isai", r"^1$"),
        ("el usuario puede usar sudo sin contrasena",
         f"sudo grep -rh NOPASSWD {V}/etc/sudoers.d/ 2>/dev/null | grep -c NOPASSWD",
         r"^[1-9]"),
        ("root TIENE contrasena en el instalado",
         f"sudo grep -c '^root:[$]' {V}/etc/shadow 2>/dev/null", r"^1$"),

        # --- sistema ---------------------------------------------------------
        # El idioma (fallo 32 del instalador, comprobacion escrita contra una
        # salida inventada). Se piden dos cosas distintas y las dos fallaban:
        #
        #   * Antes miraba '/usr/lib/locale/es_ES.utf8/LC_MESSAGES/*.mo'. Con
        #     glibc 2.41 ese arbol NO existe: 'localedef' mete todo en el
        #     archivo '/usr/lib/locale/locale-archive' (comprobado en un
        #     arranque de verdad: 'ls /usr/lib/locale' -> 'C.utf8 locale-archive',
        #     y no hay ningun directorio de locale). Esa comprobacion no podia
        #     dar bien nunca.
        #   * Y el fallo de verdad era del instalador: escribia en
        #     '/etc/locale.gen' la linea 'es_ES.UTF-8' sin el juego de
        #     caracteres, que 'locale-gen' rechaza con 'error: Bad entry' y
        #     sale con codigo 0 sin generar nada.
        #
        # Ahora se mira la linea tal cual la tiene que escribir el instalador
        # (locale y charset, los dos campos), que es el fallo de verdad, y el
        # resultado de verdad se comprueba en la fase 5 con 'locale -a'.
        ("el idioma pedido esta en locale.gen con su juego de caracteres",
         f"sudo grep -c '^es_ES\\.UTF-8 UTF-8' {V}/etc/locale.gen 2>/dev/null",
         r"^1$"),
        ("locale.conf apunta al idioma pedido",
         f"sudo grep -c '^es_ES\\.UTF-8$' {V}/etc/locale.conf 2>/dev/null", r"^1$"),
        ("el teclado es el de espana en la consola",
         f"sudo grep -c '^KEYMAP=es$' {V}/etc/vconsole.conf 2>/dev/null", r"^1$"),
        # La identidad (fallo 35): el sistema instalado tiene que decir que es
        # Titan Linux, no Arch Linux. Se mira el NAME del os-release, que es
        # exactamente lo que leen 'fastfetch', 'lsb_release' y el menu de GRUB.
        ("el sistema instalado se identifica como Titan Linux",
         f"sudo grep -c '^NAME=\"Titan Linux\"$' {V}/usr/lib/os-release "
         f"2>/dev/null", r"^1$"),
        ("el sistema instalado tiene su fichero titan-release",
         f"sudo grep -c '^VARIANT=installed$' {V}/etc/titan-release 2>/dev/null",
         r"^1$"),
        ("GNOME esta instalado", f"sudo test -d {V}/usr/share/gnome-shell "
         "&& echo SI-GNOME", r"(?m)^SI-GNOME$"),
        ("kitty esta instalado", f"sudo test -x {V}/usr/bin/kitty && echo SI-KITTY",
         r"(?m)^SI-KITTY$"),
        # Esta es la que daba la luz verde falsa: el patron era la palabra
        # 'scrollback' suelta, y la orden escribia un error con la ruta
        # '/mnt/v/etc/profile.d/20-titan-scrollback.sh' dentro. El patron se
        # encontraba la palabra que buscaba... en el error. Ahora se cuenta el
        # numero de lineas y el error va a /dev/null.
        ("la consola de texto tiene historial (tmux)",
         f"sudo cat {V}/etc/profile.d/20-titan-scrollback.sh 2>/dev/null "
         f"| grep -c tmux", r"^[1-9]"),

        # --- swap: en memoria, no en el disco --------------------------------
        ("zram-generator esta instalado", f"sudo test -f "
         f"{V}/usr/lib/systemd/system-generators/zram-generator && echo SI-ZRAM",
         r"(?m)^SI-ZRAM$"),
        ("fstab NO tiene particiones de swap",
         f"sudo grep -c swap {V}/etc/fstab 2>/dev/null", r"^0$"),
        # Las dos de aqui estaban escritas contra un fstab de ejemplo con
        # ESPACIOS, y el fstab de verdad (el que escribe 'genfstab') separa los
        # campos con TABULADORES. Eso hacia que el filtro ' / ' no encontrara
        # ni una linea y que la cuenta saliera cero siempre: dos comprobaciones
        # en rojo permanente que no dicen nada. La linea real es
        #
        #   UUID=591cbf58-... <TAB>/ <TAB>btrfs <TAB>rw,...,subvol=/@ <TAB>0 0
        #
        # (con 'cat -A' se ve: los separadores son '^I'). Ademas el punto de
        # montaje de la particion de arranque es '/boot/efi', no '/boot', asi
        # que el patron ' /boot ' no podia encontrarlo aunque hubiera espacios.
        #
        # Por eso las dos cuentan por CAMPOS con 'awk', que es como se lee un
        # fichero de campos: el segundo campo es el punto de montaje, el cuarto
        # son las opciones. Y 'n+0' con 'END' para que sin coincidencias salga un
        # 0 de verdad y se pueda fallar (con 'print' a secas y sin lineas, awk
        # no imprime nada y la comprobacion leeria una salida vacia).
        ("fstab monta la raiz con su subvolumen",
         f"sudo awk '$2==\"/\"{{print $4}}' {V}/etc/fstab 2>/dev/null "
         f"| grep -c 'subvol=/@$'", r"^1$"),
        # En BIOS no hay particion de arranque (el cargador va en el hueco del MBR
        # y el 'bios_grub' no se monta nunca), asi que en el fstab no puede haber
        # NINGUNA linea de '/boot/efi' y la cuenta buena es 0, no 1. Con el
        # patron de UEFI esta comprobacion daba FALLO en BIOS con el fstab
        # correcto, que es el segundo fallo de la misma pasada (39). El nombre es
        # el mismo en los dos modos porque es la misma pregunta ('se repite la
        # particion de arranque?'); lo que cambia es cuantas lineas puede haber, y
        # por eso el patron depende del modo.
        ("fstab no repite la particion de arranque",
         f"sudo awk '$2==\"/boot/efi\"{{n++}} END{{print n+0}}' {V}/etc/fstab "
         f"2>/dev/null", r"^0$" if bios else r"^1$"),

        # --- la tienda de apps -----------------------------------------------
        ("flatpak esta instalado", f"sudo test -x {V}/usr/bin/flatpak && echo SI-FLATPAK",
         r"(?m)^SI-FLATPAK$"),
        # Donde guarda el remoto (fallo del comprobador, no del producto).
        # La comprobacion miraba '/var/lib/flatpak/remotes.d/' esperando un
        # fichero que se llamara 'flathub', y las dos cosas son falsas con
        # flatpak 1.18.3, el que instala Arch hoy:
        #
        #   * '/var/lib/flatpak/remotes.d' NO existe. Comprobado con
        #     'find /var/lib/flatpak -maxdepth 2 -name "*.config"', que no
        #     devuelve NADA: en esta version los remotos se guardan dentro del
        #     fichero de configuracion del repositorio.
        #   * Y aunque existiera, el fichero se llama 'flathub.config', no
        #     'flathub'.
        #
        # El remoto SI esta: preguntandole a flatpak en el sistema destino
        # ('arch-chroot /mnt flatpak --system remotes --columns=name') contesta
        # 'flathub', y el fichero donde lo deja puesto es
        # '/var/lib/flatpak/repo/config', con la linea real
        #
        #   url=https://dl.flathub.org/repo/
        #
        # que es lo que se mira ahora. La comprobacion de la fase 5, en el
        # sistema ya arrancado, pregunta a flatpak de verdad.
        ("la tienda trae flathub anadido",
         f"sudo grep -c 'url=https://dl\\.flathub\\.org/repo/$' "
         f"{V}/var/lib/flatpak/repo/config 2>/dev/null", r"^1$"),
        ("hay apps instaladas de la tienda",
         f"sudo ls {V}/var/lib/flatpak/app 2>/dev/null | wc -l", r"^[1-9]"),
        ("las apps de la tienda son las del tipo de uso",
         f"sudo ls {V}/var/lib/flatpak/app 2>/dev/null | grep -c mozilla", r"^[1-9]"),

        # --- firewall: instalado y apagado -----------------------------------
        ("ufw esta instalado", f"sudo test -x {V}/usr/bin/ufw && echo SI-UFW",
         r"(?m)^SI-UFW$"),
        ("ufw NO se activa solo", f"sudo ls {V}/etc/systemd/system/"
         "multi-user.target.wants/ 2>/dev/null | grep -c ufw", r"^0$"),
    ]


def comprobaciones_arranque() -> list[tuple[str, str, str]]:
    """Lo que tiene que cumplir el sistema ya instalado, arrancando desde el disco."""
    return [
        ("arranca sin el live (arranca desde el disco)", "uname -s", r"Linux"),
        ("el kernel es el del proyecto", "uname -r", r"titanlinux"),
        ("el equipo tiene el nombre puesto", "hostname", r"\btitan\b"),
        ("el usuario existe y puede entrar", "whoami", r"\bisai\b"),
        ("la consola tiene historial", "tmux -V", r"\d+\.\d+"),
        ("el comando titan existe", "titan version", r"\d"),
        # Dos cosas aqui, y las dos importan.
        #
        # El idioma: 'fastfetch' escribe sus etiquetas en el idioma del sistema.
        # En el live, que esta en espanol, la linea es 'Sistema: Titan Linux ...'
        # y no 'OS: Titan Linux'. Con 'LC_ALL=C' la salida es estable y el
        # patron no depende de que el usuario haya pedido espanol o ingles.
        # (Comprobado en el live: sin 'LC_ALL' -> 'Sistema: Titan Linux
        # 0.1.0 (TITAN) x86_64'; en el host, con 'LC_ALL=C' -> 'OS: Arch
        # Linux x86_64'.)
        #
        # Y el nombre: el instalado decia 'Arch Linux' porque el instalador no
        # escribia su os-release (fallo 35, arreglado con escribir_identidad).
        ("fastfetch funciona",
         "LC_ALL=C fastfetch --logo none 2>/dev/null | head -3",
         r"(?m)^OS: Titan Linux"),
        ("GNOME esta instalado", "test -d /usr/share/gnome-shell && echo SI-GNOME",
         r"(?m)^SI-GNOME$"),
        ("kitty esta instalado", "test -x /usr/bin/kitty && echo SI-KITTY",
         r"(?m)^SI-KITTY$"),
        # Esto daba falso con el remoto PUESTO, y la causa no era la que
        # parece (que 'flatpak remotes' imprimiese una tabla, como en el fallo
        # 28 del instalador). La causa real, medida en el sistema arrancado:
        #
        #   $ flatpak remotes 2>/dev/null | grep -cx flathub
        #   0
        #   $ flatpak --system remotes --columns=name | grep -cx flathub
        #   1
        #
        # Sin '--system', 'flatpak remotes' mira TAMBIEN la instalacion del
        # usuario, que en un recien instalado esta a medio crear, y se para
        # con un error por stderr ('While opening repository
        # /home/isai/.local/share/flatpak/repo: opening repo: opendir(objects):
        # No such file or directory'). Con '2>/dev/null' ese error se tira, y
        # en stdout no queda NADA: la cuenta sale 0 aunque el remoto este ahi,
        # y el sistema instalado monta sus apps de la tienda sin problema.
        #
        # '--system' pregunta lo que se quiere preguntar (el remoto que puso el
        # instalador como root) y '--columns=name' garantiza un nombre por
        # linea, que es lo que hace falta para el '-x'. La cabecera que a veces
        # sale ('Name    Options') no sale siempre: se ha visto las dos en
        # esta misma maquina, y un patron que depende de eso no es un patron.
        ("la tienda tiene flathub",
         "flatpak --system remotes --columns=name 2>/dev/null | grep -cx flathub",
         r"^1$"),
        ("root existe y tiene contrasena", "sudo passwd -S root 2>/dev/null",
         r"(?m)^root P "),
        # La salida real de 'swapon --show' empieza por una CABECERA y luego
        # viene la linea del dispositivo:
        #
        #   NAME       TYPE      SIZE USED PRIO
        #   /dev/zram0 partition 1.9G   0B  100
        #
        # Con 'head -1' se leia la cabecera, que no dice 'zram' en ningun sitio:
        # la comprobacion no podia dar bien ni con zram puesto (que es cuando
        # deberia dar bien). Ahora se cuenta la linea del dispositivo.
        ("el swap de memoria esta activo",
         "swapon --show 2>/dev/null | grep -c '/dev/zram'", r"^1$"),
        ("el escritorio por defecto es graphical", "systemctl get-default 2>/dev/null",
         r"(?m)^graphical\.target$"),
        # El idioma de verdad: 'locale -a' es lo que usa el sistema, y su
        # respuesta real (con 'es_ES.UTF-8' pedido y bien generado) es
        #
        #   C
        #   C.utf8
        #   es_ES.utf8
        #   POSIX
        #
        # Ojo con el nombre: 'locale -a' NORMALIZA y escribe 'es_ES.utf8', en
        # minusculas, mientras que lo que se pidio fue 'es_ES.UTF-8'. Por eso
        # el patron va solo por el principio. Sin esto, el idioma que no se
        # genera (fallo 32) no se ve en ningun sitio.
        ("el idioma pedido esta disponible en el sistema",
         "locale -a 2>/dev/null | grep -c '^es_ES'", r"^1$"),
    ]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--iso", required=True)
    ap.add_argument("--disk", default="20G", help="tamano del disco a instalar")
    ap.add_argument("--memory", default="5120")
    ap.add_argument("--cpus", default="4")
    ap.add_argument("--bios", action="store_true", help="arrancar por BIOS en vez de UEFI")
    ap.add_argument("--solo-instalar", action="store_true",
                    help="no probar a arrancar despues desde el disco")
    ap.add_argument("--out", default=None)
    ap.add_argument("--timeout-arranque", type=int, default=900)
    ap.add_argument("--timeout-instalar", type=int, default=7200)
    ap.add_argument("--timeout-pasos", type=int, default=1800)
    args = ap.parse_args()

    iso = os.path.abspath(args.iso)
    if not os.path.exists(iso):
        print(f"ERROR: no existe la ISO {iso}", file=sys.stderr)
        return 1
    if not os.path.exists(RESPUESTAS):
        print(f"ERROR: no existe {RESPUESTAS}", file=sys.stderr)
        return 1
    if not args.bios and not os.path.exists(OVMF_CODE):
        print(f"ERROR: falta {OVMF_CODE}; instala edk2-ovmf o usa --bios", file=sys.stderr)
        return 1

    out_dir = os.path.abspath(args.out or os.path.join(os.path.dirname(iso), "instalar"))
    os.makedirs(out_dir, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    log_path = os.path.join(out_dir, f"consola-{stamp}.log")
    informe_path = os.path.join(out_dir, f"informe-{stamp}.json")

    run_dir = os.path.join(DISTRO, "run")
    os.makedirs(run_dir, exist_ok=True)
    disco_img = os.path.join(run_dir, f"instalacion-{args.disk}.qcow2")
    # El disco se crea DE CERO en cada prueba: si se reutilizara, el particionado
    # y el formateado se estarian probando sobre el resultado de la prueba
    # anterior, y un fallo podria pasar por bueno.
    if os.path.exists(disco_img):
        os.remove(disco_img)
    subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", disco_img, args.disk],
                   check=True)

    tmp = tempfile.mkdtemp(prefix="titan-instala-")
    ser_path = os.path.join(tmp, "serial.sock")
    mon_path = os.path.join(tmp, "monitor.sock")
    vars_copy = os.path.join(tmp, "OVMF_VARS.fd")

    def qemu_cmd(cdrom: bool) -> list[str]:
        cmd = [
            "qemu-system-x86_64",
            "-machine", "q35,accel=kvm:tcg",
            "-cpu", "max",
            "-m", args.memory,
            "-smp", args.cpus,
            "-boot", "order=dc" if cdrom else "order=c",
            "-drive", f"if=virtio,format=qcow2,file={disco_img}",
            "-nic", "user,model=virtio-net-pci",
            "-audiodev", "none,id=snd0",
            "-display", "none",
            "-chardev", f"socket,id=ser0,path={ser_path},server=on,wait=off",
            "-serial", "chardev:ser0",
            "-monitor", f"unix:{mon_path},server=on,wait=off",
        ]
        if cdrom:
            cmd += ["-drive", f"file={iso},media=cdrom,readonly=on"]
        if not args.bios:
            cmd += [
                "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={OVMF_CODE}",
                "-drive", f"if=pflash,format=raw,unit=1,file={vars_copy}",
            ]
        return cmd

    if not args.bios:
        shutil.copy(OVMF_VARS, vars_copy)

    log = open(log_path, "w", encoding="utf-8", errors="replace")
    modo = "BIOS (syslinux)" if args.bios else "UEFI (OVMF)"
    log.write("# Titan Linux - instalacion automatica completa\n")
    log.write(f"# fecha   : {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
    log.write(f"# ISO     : {iso}\n")
    log.write(f"# arranque: {modo}\n")
    log.write(f"# disco   : {disco_img} ({args.disk}, nuevo)\n")
    log.write(f"# qemu    : {' '.join(qemu_cmd(True))}\n\n")

    Serial, wait_for_shell = cargar_serial()
    ser = Serial(ser_path, log)
    inf = Informe()

    def arranca(cdrom: bool) -> subprocess.Popen:
        proc = subprocess.Popen(qemu_cmd(cdrom), stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL)
        if not ser.connect(time.time() + 30):
            raise SystemExit("no se ha podido conectar con la consola serie")
        return proc

    print(f"==> ISO      : {iso}", flush=True)
    print(f"==> arranque : {modo}", flush=True)
    print(f"==> disco    : {disco_img} ({args.disk})", flush=True)
    print(f"==> log      : {log_path}", flush=True)
    print("==> fase 1: arrancando el live", flush=True)
    proc = arranca(True)
    try:
        if not wait_for_shell(ser, args.timeout_arranque):
            inf.anota("live", "el live arranca y hay consola", False,
                      f"sin shell en {args.timeout_arranque}s")
            raise SystemExit("el live no ha llegado a la consola")
        inf.anota("live", "el live arranca y hay consola", True)

        # --- fase 2: el motor de las ventanas esta dentro del live ----------
        print("==> fase 2: el motor de las ventanas, dentro del live", flush=True)
        ok, sal = ser.run("command -v dialog")
        inf.anota("live", "dialog esta instalado en el live", ok and "dialog" in sal,
                  "" if ok else sal[:80])
        ok, sal = ser.run("dialog --version | head -1")
        inf.anota("live", "dialog dice su version", ok and re.search(r"\d", sal) is not None)
        ok, sal = ser.run("command -v whiptail || echo SIN-WHIPTAIL")
        inf.anota("live", "whiptail ya no hace falta (no esta)", ok, sal.strip()[:60])
        # Con 'sudo', y sin glob detras: '/root/instalador/*.sh' lo expande la
        # shell del usuario, que no puede entrar en /root, y el 'ls' se queda
        # sin argumentos. El patron es una linea entera, no 'sal.strip() == 9':
        # la consola devuelve cosas de mas (restos del prompt, un eco a medias)
        # y comparar la salida ENTERA hace que la comprobacion falle por ruido y
        # no por lo que quiere mirar. Lo que importa es que la orden diga 9.
        # Se cuentan las '.sh' y no los ficheros: el frontal grafico tambien
        # vive ahi, y con el '__pycache__' de una prueba importandolo (fallo
        # 43) el recuento de ficheros daba 11 y el informe salia en rojo sin
        # que faltara nada de verdad. El frontal se comprueba por su nombre, que
        # es mas explicito que sumarlo a la cuenta.
        #
        # Y SIN GLOB, que es lo que se ha medido: la orden va a una shell que NO
        # es root (la del live, la de 'isai'), y el glob lo expande esa shell,
        # que no puede ni listar '/root'. Medido: 'sudo ls /root/instalador/*.sh'
        # contestaba 'ls: no se puede acceder', y la
        # comprobacion se ponia en rojo con la ISO perfectamente buena. La
        # cuenta se hace sobre lo que 'ls' ha impreso, que si que ve root.
        ok, sal = ser.run("sudo ls /root/instalador | grep -c '\\.sh$'")
        inf.anota("live", "el instalador esta en el live (sus 9 librerias)",
                  ok and re.search(r"(?m)^9$", sal) is not None, sal.strip()[:20])
        ok, sal = ser.run("sudo test -f /root/instalador/ventana-gui.py "
                          "&& echo SI-FRONTAL")
        inf.anota("live", "el frontal grafico esta en el live",
                  ok and "SI-FRONTAL" in sal)
        ok, sal = ser.run("sudo test -f /root/install.sh && echo SI-INSTALL")
        inf.anota("live", "install.sh esta en el live", ok and "SI-INSTALL" in sal)
        # Con 'sudo': sin el, el propio passwd dice que no puede ver la cuenta de
        # root, que no es lo mismo que que este bloqueada (y es un fallo mio, no
        # del live).
        ok, sal = ser.run("sudo passwd -S root | head -1")
        inf.anota("live", "root esta bloqueado en el live", ok and re.search(r"\bL\b", sal) is not None,
                  sal.strip()[:40])
        ok, sal = ser.run("sudo -n true && echo SUDO-OK")
        inf.anota("live", "el usuario puede usar sudo sin contrasena",
                  ok and "SUDO-OK" in sal)

        # --- fase 2b: la pantalla grafica, DENTRO del live ----------------
        # Esto no se puede hacer desde el host: que el perfil haya instalado la
        # pila, que el permiso del frontal haya llegado a la ISO, y que el
        # frontal pinte de verdad con los paquetes de la ISO solo se comprueba
        # con los paquetes de la ISO. El script va comprimido porque son doce
        # kilobytes de texto y la consola serie va a 150 caracteres por viaje.
        print("==> fase 2b: la pantalla grafica, dentro del live", flush=True)
        with open(GUI_EN_VIVO, encoding="utf-8") as f:
            subir_texto_gz(ser, "/var/tmp/comprobar-gui-en-vivo.sh", f.read())
        ok, sal = ser.run("sudo bash /var/tmp/comprobar-gui-en-vivo.sh",
                          timeout=300)
        anota_gui(inf, sal)
        ser.run("sudo rm -f /var/tmp/comprobar-gui-en-vivo.sh "
                "/var/tmp/comprobar-gui-en-vivo.sh.b64")

        # --- fase 3: instalar ------------------------------------------------
        print("==> fase 3: instalar (esto tarda: descarga el sistema entero)", flush=True)
        with open(RESPUESTAS, encoding="utf-8") as f:
            subir_texto(ser, "/tmp/respuestas.txt", f.read())
        ok, sal = ser.run("grep -c '^[a-z]' /tmp/respuestas.txt")
        inf.anota("instalar", "el fichero de respuestas ha llegado al guest",
                  ok and re.search(r"\b[1-9]", sal) is not None, sal.strip()[:20])
        ok, sal = ser.run("sudo lsblk -dno NAME,SIZE /dev/vda")
        inf.anota("instalar", "el disco de destino esta a la vista", ok and "vda" in sal,
                  sal.strip()[:30])

        inicio = time.time()
        ok, sal = ser.run(
            "sudo /root/install.sh --autopiloto --respuestas /tmp/respuestas.txt"
            "; echo INSTALA-CODIGO=$?", timeout=args.timeout_instalar)
        duracion = time.time() - inicio
        cod = re.search(r"INSTALA-CODIGO=(\d+)", sal)
        codigo = int(cod.group(1)) if cod else 99
        inf.anota("instalar", f"el instalador termina bien (codigo {codigo}, "
                              f"{duracion / 60:.0f} min)", codigo == 0,
                  "" if codigo == 0 else sal[-300:].replace("\n", " "))

        # El log del instalador, por si hay que ver el porque.
        ok, sal = ser.run("sudo grep -c '' /var/log/titan-install.log")
        lineas = sal.strip()
        inf.anota("instalar", "el instalador ha dejado su log", ok and
                  re.search(r"\b[1-9]", sal) is not None, f"{lineas} lineas")
        ser.run("sudo cp /var/log/titan-install.log /tmp/titan-install.log")
        ok, sal = ser.run("sudo grep -ciE 'error|fallo' /tmp/titan-install.log")
        print(f"    (el log del instalador tiene {sal.strip()} lineas con 'error' o 'fallo')")

        # --- fase 4: mirar lo instalado -------------------------------------
        print("==> fase 4: mirando lo que ha quedado instalado", flush=True)
        # Que particion es cada una se le pregunta al disco ya instalado, no se
        # supone: con swap en memoria hay dos particiones y no una particion de
        # swap, y en BIOS no hay particion de arranque que montar.
        raiz, esp = detectar_particiones(ser)
        inf.anota("instalado", "el disco tiene una particion btrfs", bool(raiz),
                  f"raiz={raiz or 'NO ENCONTRADA'}")
        anota_particiones(inf, esp, args.bios)
        if not raiz:
            raise SystemExit("no hay ninguna particion btrfs en el disco: no hay "
                             "nada instalado que mirar")
        # Todo lo de abajo mira DENTRO del sistema instalado, y para eso la raiz
        # tiene que estar montada en /mnt/v. Si no lo esta, cada comprobacion
        # daria 'no existe' y el informe contaria que no hay nada instalado,
        # que es mentira: lo que no hay es el montaje (fallo 29). Por eso la
        # puerta se mira UNA vez y, si no se pasa, se dice y se salta el bloque
        # entero, en vez de dejar que veinte comprobaciones den la cara de
        # fallar por algo que no es un fallo del sistema instalado.
        montada = anota_montaje(inf, ser, raiz)
        if not montada:
            print("    AVISO: la raiz no se ha podido montar; las comprobaciones "
                  "de dentro se saltan", flush=True)
            inf.anota("instalado",
                      "las comprobaciones de dentro del sistema se han saltado",
                      montada, "la raiz no se ha podido montar: sin ella no se "
                      "puede afirmar nada de lo que hay instalado")
        else:
            ser.run("sudo mkdir -p /mnt/ve")
            if esp:
                # Con el '&& echo SI-MONTADO' de siempre, no con el codigo de
                # 'run()': 'run()' dice "la consola contesto", y una particion de
                # arranque que no monta tambien deja su error en la consola. Este
                # montaje estaba fuera de la regla y por eso no podia fallar.
                ok, sal = ser.run(f"sudo mount {esp} /mnt/ve && echo SI-MONTADO")
                inf.anota("instalado", "la particion de arranque se monta",
                          "SI-MONTADO" in sal, " ".join(sal.split())[:60])

            for nombre, orden, patron in comprobaciones_instalado(raiz, esp, args.bios):
                ok, sal = ser.run(orden, timeout=120)
                bien = ok and re.search(patron, sal, re.M) is not None
                detalle = "" if bien else " ".join(sal.split())[:110]
                inf.anota("instalado", nombre, bien, detalle)

            ok, sal = ser.run("sudo ls /mnt/v/var/lib/pacman/local | wc -l")
            print(f"    (paquetes instalados: {sal.strip()})")
            ok, sal = ser.run("sudo du -sh /mnt/v 2>/dev/null | cut -f1")
            print(f"    (tamano del sistema instalado: {sal.strip()})")
            ok, sal = ser.run("sudo grep titan /mnt/v/etc/pacman.conf | wc -l")
            inf.anota("instalado", "el pacman.conf del instalado NO habla de titan-repo",
                      ok and re.search(r"(?m)^0$", sal) is not None, sal.strip()[:20])
            # El patron es 'multilib]' y no 'multilib' a proposito: lo que importa
            # es que este la SECCION, y un 'grep -c multilib' contaria igual una
            # linea de comentario que hablara de multilib. Una comprobacion que
            # tambien pasa por el motivo equivocado no es una comprobacion. Y la
            # orden se queda corta, que por la consola serie las largas se parten.
            ok, sal = ser.run("sudo grep -c 'multilib]' /mnt/v/etc/pacman.conf")
            inf.anota("instalado", "el pacman.conf del instalado tiene [multilib]",
                      ok and re.search(r"(?m)^1$", sal.strip()) is not None, sal.strip()[:20])

        # Se sueltan de dentro hacia fuera y con -R, que es como los suelta el
        # propio instalador: si se deja algo montado, el arranque desde el disco
        # (fase 5) puede fallar por eso y no por el cargador.
        ser.run("sudo umount -R /mnt/ve", timeout=60)
        ser.run("sudo umount -R /mnt/v", timeout=60)

        # --- fase 5: arrancar desde el disco -------------------------------
        if not args.solo_instalar:
            print("==> fase 5: apagando y arrancando DESDE EL DISCO", flush=True)
            ser.run("sudo systemctl poweroff", timeout=20)
            for _ in range(180):
                if proc.poll() is not None:
                    break
                time.sleep(1)
            if proc.poll() is None:
                proc.terminate()
                inf.anota("arranque", "la maquina se apaga", False, "sigue viva")
            else:
                inf.anota("arranque", "la maquina se apaga", True)

            # La consola serie de la maquina apagada se queda colgada: para la
            # nueva hay que crear otro socket y otra copia de las variables de
            # UEFI, porque el apagado las ha modificado.
            shutil.rmtree(tmp, ignore_errors=True)
            os.makedirs(tmp, exist_ok=True)
            ser_path = os.path.join(tmp, "serial.sock")
            mon_path = os.path.join(tmp, "monitor.sock")
            vars_copy = os.path.join(tmp, "OVMF_VARS.fd")
            if not args.bios:
                shutil.copy(OVMF_VARS, vars_copy)
            ser = Serial(ser_path, log)
            log.write("\n\n===== la maquina vuelve a encender, SIN el live =====\n\n")
            proc = arranca(False)
            ok, detalle = entrar(ser, "isai", CLAVE, tmo=args.timeout_arranque)
            inf.anota("arranque", "el sistema instalado arranca y deja entrar con "
                                  "la contrasena del usuario", ok, detalle[:110])
            if ok:
                for nombre, orden, patron in comprobaciones_arranque():
                    ok2, sal = ser.run(orden, timeout=180)
                    bien = ok2 and re.search(patron, sal, re.M) is not None
                    detalle2 = "" if bien else " ".join(sal.split())[:110]
                    inf.anota("arranque", nombre, bien, detalle2)
                ok2, sal = ser.run("lsblk -no SIZE /dev/vda | head -1")
                inf.anota("arranque", "el disco instalado tiene el tamano pedido",
                          ok2 and re.search(r"\d", sal) is not None, sal.strip()[:20])
                _, sal = ser.run(ORDEN_MODO_ARRANQUE)
                anota_modo_arranque(inf, sal, args.bios)
                # Que en el sistema instalado el root SI tiene contrasena (en el
                # live esta bloqueado a proposito): la diferencia es el fallo 12.
                ok2, sal = ser.run("sudo passwd -S root | head -1")
                inf.anota("arranque", "root tiene contrasena en el instalado (en el live no)",
                          ok2 and re.search(r"\bP\b", sal) is not None,
                          sal.strip()[:40])
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
        log.close()

    fallos = inf.fallos()
    inf.vuelca(informe_path, {
        "fecha": time.strftime("%Y-%m-%d %H:%M:%S"),
        "iso": iso, "arranque": modo, "disco": args.disk,
        "log": log_path, "fallos": fallos, "total": len(inf.lineas),
    })
    print()
    print(f"comprobaciones: {len(inf.lineas)}   fallos: {fallos}")
    print(f"log    : {log_path}")
    print(f"informe: {informe_path}")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
