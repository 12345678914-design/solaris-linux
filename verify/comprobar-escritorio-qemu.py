#!/usr/bin/env python3
"""Comprueba el escritorio Qt de la ISO en QEMU.

Arranca la ISO sin ventana (igual que titan-verify.py), espera la shell de
ttyS0, comprueba que labwc, titan-desktop y titan-panel estan vivos, captura
la pantalla por el monitor de QEMU y mide que lo pintado es el fondo del
escritorio y no una consola negra. Con --interactuar usa QMP para probar el
centro, la barra y las tareas. Guarda PPM, PNG y un informe JSON.

Uso:
  ./verify/comprobar-escritorio-qemu.py
  ./verify/comprobar-escritorio-qemu.py --bios
  ./verify/comprobar-escritorio-qemu.py --interactuar
  ./verify/comprobar-escritorio-qemu.py --cerrar   # prueba labwc --exit

Codigo de salida: 0 si pasa, 1 si falla.
"""

from __future__ import annotations

import argparse
import glob
import importlib.util
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
import zlib

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARNES = os.path.join(RAIZ, "scripts", "titan-verify.py")


def cargar_arnes():
    spec = importlib.util.spec_from_file_location("titan_verify", ARNES)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"no se puede cargar {ARNES}")
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


def leer_ppm(ruta: str) -> tuple[int, int, bytes]:
    with open(ruta, "rb") as f:
        if f.readline().strip() != b"P6":
            raise ValueError("la captura no es un PPM P6")
        datos: list[bytes] = []
        while len(datos) < 3:
            linea = f.readline()
            if not linea:
                raise ValueError("cabecera PPM incompleta")
            if linea.startswith(b"#"):
                continue
            datos.extend(linea.split())
        ancho, alto, maximo = (int(x) for x in datos[:3])
        if maximo != 255:
            raise ValueError(f"PPM con maximo {maximo}, se esperaba 255")
        pixeles = f.read()
    if len(pixeles) < ancho * alto * 3:
        raise ValueError("faltan pixeles en la captura")
    # QEMU alinea cada fila a 4 bytes al escribir el PPM. Con anchos como
    # 1366, 1366*3=4098 y la fila real ocupa 4100: leer el fichero como si
    # fuera continuo desplaza un byte cada fila y los colores acaban mal.
    if len(pixeles) % alto == 0:
        paso = len(pixeles) // alto
        if paso >= ancho * 3:
            if paso == ancho * 3:
                return ancho, alto, pixeles
            filas = b"".join(
                pixeles[y * paso:y * paso + ancho * 3]
                for y in range(alto)
            )
            return ancho, alto, filas
    return ancho, alto, pixeles


def analizar(ancho: int, alto: int, pixeles: bytes) -> dict:
    """Mide color medio y proporcion de pixeles de fondo."""
    total = 0
    no_negro = 0
    azulados = 0
    suma_r = suma_g = suma_b = 0
    for i in range(0, ancho * alto * 3, 3 * 2):
        r, g, b = pixeles[i], pixeles[i + 1], pixeles[i + 2]
        total += 1
        suma_r += r
        suma_g += g
        suma_b += b
        if r + g + b > 60:
            no_negro += 1
            if b > g and b >= r:
                azulados += 1
    return {
        "pixeles_muestreados": total,
        "no_negro": round(no_negro / total, 3) if total else 0.0,
        "azulados": round(azulados / total, 3) if total else 0.0,
        "media_rgb": (
            round(suma_r / total, 1) if total else 0,
            round(suma_g / total, 1) if total else 0,
            round(suma_b / total, 1) if total else 0,
        ),
    }


def analizar_barra(ancho: int, alto: int, pixeles: bytes) -> dict:
    """Mira la fila superior de la barra y su interior.

    La barra mide 56 px y pinta una linea de acento en su borde superior.
    Si layer-shell no la coloca abajo, o si ocupa toda la pantalla, esta
    comprobacion falla aunque el resto del escritorio se vea bien.
    """
    alto_barra = 56
    y_borde = alto - alto_barra
    y_interior = alto - 24
    if y_borde < 0 or y_interior < 0:
        return {"borde": 0.0, "interior": 0.0}

    acento = 0
    total_borde = 0
    for x in range(0, ancho, 2):
        i = (y_borde * ancho + x) * 3
        r, g, b = pixeles[i], pixeles[i + 1], pixeles[i + 2]
        total_borde += 1
        if g > 110 and b > 150 and b > g and r < 170:
            acento += 1

    oscuro = 0
    total_interior = 0
    for x in range(0, ancho, 2):
        i = (y_interior * ancho + x) * 3
        r, g, b = pixeles[i], pixeles[i + 1], pixeles[i + 2]
        total_interior += 1
        if r < 60 and g < 75 and b < 105:
            oscuro += 1

    return {
        "borde": round(acento / total_borde, 3) if total_borde else 0.0,
        "interior": (round(oscuro / total_interior, 3)
                     if total_interior else 0.0),
    }


def ppm_a_png(ppm: str, png: str) -> None:
    ancho, alto, pixeles = leer_ppm(ppm)
    filas = b"".join(
        b"\x00" + pixeles[y * ancho * 3:(y + 1) * ancho * 3]
        for y in range(alto)
    )

    def trozo(tipo: bytes, carga: bytes) -> bytes:
        crc = zlib.crc32(tipo + carga) & 0xFFFFFFFF
        return (struct.pack(">I", len(carga)) + tipo + carga +
                struct.pack(">I", crc))

    cabecera = struct.pack(">IIBBBBB", ancho, alto, 8, 2, 0, 0, 0)
    with open(png, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(trozo(b"IHDR", cabecera))
        f.write(trozo(b"IDAT", zlib.compress(filas, 6)))
        f.write(trozo(b"IEND", b""))


def detectar_tarjeta(ancho: int, alto: int, pixeles: bytes) -> dict:
    """Busca los bordes azulados de la tarjeta central del centro."""
    y = alto // 2
    puntos = []
    for x in range(ancho):
        i = (y * ancho + x) * 3
        r, g, b = pixeles[i], pixeles[i + 1], pixeles[i + 2]
        if b > 70 and g > 45 and b > r + 20:
            puntos.append(x)
    if not puntos:
        return {"izquierda": -1, "derecha": -1, "pixeles": 0}
    return {
        "izquierda": min(puntos),
        "derecha": max(puntos),
        "pixeles": len(puntos),
    }


class Qmp:
    """Cliente minimo de QMP para mover el raton de forma absoluta."""

    def __init__(self, ruta: str, log, timeout: float = 30.0):
        self.sock = None
        self.archivo = None
        self.log = log
        limite = time.time() + timeout
        while time.time() < limite:
            if os.path.exists(ruta):
                try:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.settimeout(10)
                    s.connect(ruta)
                    self.sock = s
                    self.archivo = s.makefile("rwb", buffering=0)
                    self._leer()
                    self.cmd("qmp_capabilities")
                    return
                except OSError:
                    pass
            time.sleep(0.2)
        raise RuntimeError("QMP no disponible")

    def _leer(self) -> dict:
        linea = self.archivo.readline()
        if not linea:
            raise RuntimeError("QMP cerro la conexion")
        return json.loads(linea.decode("utf-8", "replace"))

    def cmd(self, ejecutar: str, argumentos: dict | None = None) -> dict:
        mensaje = {"execute": ejecutar}
        if argumentos is not None:
            mensaje["arguments"] = argumentos
        self.archivo.write((json.dumps(mensaje) + "\n").encode())
        self.log.write(f"[[qmp]] {ejecutar}\n")
        self.log.flush()
        while True:
            respuesta = self._leer()
            if "return" in respuesta or "error" in respuesta:
                return respuesta

    def mover(self, x: int, y: int, ancho: int, alto: int) -> None:
        def absoluto(valor: int, tamano: int) -> int:
            return max(0, min(32767, int(valor * 32767 / max(1, tamano - 1))))

        self.cmd("input-send-event", {
            "events": [
                {"type": "abs",
                 "data": {"axis": "x", "value": absoluto(x, ancho)}},
                {"type": "abs",
                 "data": {"axis": "y", "value": absoluto(y, alto)}},
            ]
        })

    def clic(self, x: int, y: int, ancho: int, alto: int,
             boton: str = "left") -> None:
        self.mover(x, y, ancho, alto)
        time.sleep(0.3)
        self.cmd("input-send-event", {
            "events": [{"type": "btn",
                        "data": {"down": True, "button": boton}}]
        })
        time.sleep(0.15)
        self.cmd("input-send-event", {
            "events": [{"type": "btn",
                        "data": {"down": False, "button": boton}}]
        })
        time.sleep(0.5)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--iso", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--memory", default="2048")
    ap.add_argument("--cpus", default="2")
    ap.add_argument("--bios", action="store_true")
    ap.add_argument("--resolution", default=None,
                    help="fija la resolucion del guest (ANCHOxALTO)")
    ap.add_argument("--no-shot", action="store_true")
    ap.add_argument("--interactuar", action="store_true",
                    help="prueba el centro, el terminal y las tareas con raton")
    ap.add_argument("--cerrar", action="store_true",
                    help="prueba labwc --exit y la vuelta a tmux")
    args = ap.parse_args()

    tv = cargar_arnes()

    iso = args.iso
    if not iso:
        isos = sorted(glob.glob(os.path.join(RAIZ, "out", "*.iso")),
                      key=os.path.getmtime)
        if not isos:
            print("ERROR: no hay ISO en out/", file=sys.stderr)
            return 1
        iso = isos[-1]
    iso = os.path.abspath(iso)
    if not os.path.exists(iso):
        print(f"ERROR: no existe {iso}", file=sys.stderr)
        return 1

    out_dir = os.path.abspath(args.out or
                              os.path.join(RAIZ, "out", "escritorio"))
    os.makedirs(out_dir, exist_ok=True)
    sello = time.strftime("%Y%m%d-%H%M%S")
    log_path = os.path.join(out_dir, f"consola-{sello}.log")
    info_path = os.path.join(out_dir, f"informe-{sello}.json")
    ppm = os.path.join(out_dir, f"pantalla-{sello}.ppm")
    png = os.path.join(out_dir, f"pantalla-{sello}.png")
    centro_ppm = os.path.join(out_dir, f"centro-{sello}.ppm")
    centro_png = os.path.join(out_dir, f"centro-{sello}.png")
    cierre_ppm = os.path.join(out_dir, f"cierre-{sello}.ppm")
    cierre_png = os.path.join(out_dir, f"cierre-{sello}.png")
    tarea_ppm = os.path.join(out_dir, f"tarea-{sello}.ppm")
    tarea_png = os.path.join(out_dir, f"tarea-{sello}.png")
    fin_ppm = os.path.join(out_dir, f"cierre-tarea-{sello}.ppm")
    fin_png = os.path.join(out_dir, f"cierre-tarea-{sello}.png")

    tmp = tempfile.mkdtemp(prefix="titan-escritorio-")
    ser_path = os.path.join(tmp, "serial.sock")
    mon_path = os.path.join(tmp, "monitor.sock")
    qmp_path = os.path.join(tmp, "qmp.sock")
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
        "-qmp", f"unix:{qmp_path},server=on,wait=off",
        "-device", "virtio-tablet-pci",
    ]
    if args.resolution:
        try:
            res_ancho, res_alto = (
                int(valor) for valor in args.resolution.lower().split("x")
            )
            if res_ancho < 320 or res_alto < 240:
                raise ValueError
        except (TypeError, ValueError):
            print("ERROR: --resolution debe ser ANCHOxALTO",
                  file=sys.stderr)
            return 1
        qemu += [
            "-vga", "none",
            "-device",
            f"virtio-vga,xres={res_ancho},yres={res_alto},edid=on",
        ]
    modo = "BIOS (syslinux)"
    if not args.bios:
        if not os.path.exists(tv.OVMF_CODE):
            print(f"ERROR: falta {tv.OVMF_CODE}; usa --bios", file=sys.stderr)
            return 1
        vars_copy = os.path.join(tmp, "OVMF_VARS.fd")
        shutil.copy(tv.OVMF_VARS, vars_copy)
        qemu += [
            "-drive", f"if=pflash,format=raw,unit=0,readonly=on,"
                      f"file={tv.OVMF_CODE}",
            "-drive", f"if=pflash,format=raw,unit=1,file={vars_copy}",
        ]
        modo = "UEFI (OVMF)"

    log = open(log_path, "w", encoding="utf-8", errors="replace")
    qemu_log_path = os.path.join(out_dir, f"qemu-{sello}.log")
    qemu_log = open(qemu_log_path, "w", encoding="utf-8", errors="replace")
    print(f"==> ISO      : {iso}")
    print(f"==> arranque : {modo}")
    proc = subprocess.Popen(qemu, stdout=qemu_log, stderr=subprocess.STDOUT)
    ser = tv.Serial(ser_path, log)
    if not ser.connect(time.time() + 60):
        proc.kill()
        log.close()
        print("ERROR: QEMU no expuso la consola serie", file=sys.stderr)
        return 1
    mon = tv.Monitor(mon_path, log)
    mon.connect(time.time() + 30)
    qmp = Qmp(qmp_path, log) if args.interactuar else None

    checks: list[dict] = []
    metricas: dict = {}

    def anotar(nombre: str, ok: bool, detalle: str) -> None:
        checks.append({"nombre": nombre, "ok": ok, "detalle": detalle})
        print(f"{'OK   ' if ok else 'FALLO'} {nombre}: {detalle}")

    try:
        shell = tv.wait_for_shell(ser, args.timeout)
        anotar("shell de ttyS0", shell, "responde" if shell else "no llego")
        if not shell:
            return 1

        anotar("monitor de QEMU", mon.sock is not None,
               "conectado" if mon.sock is not None else "sin monitor")

        ok, salida = ser.run("pgrep -a labwc")
        anotar("labwc vivo", ok and "labwc" in salida,
               salida.strip()[:120] or "sin proceso")

        ok, salida = ser.run("pgrep -a titan-desktop")
        anotar("titan-desktop vivo", ok and "titan-desktop" in salida,
               salida.strip()[:120] or "sin proceso")

        ok, salida = ser.run("pgrep -a titan-shell || pgrep -a titan-panel")
        anotar("titan-shell / panel vivo",
               ok and ("titan-shell" in salida or "titan-panel" in salida),
               salida.strip()[:120] or "sin proceso")

        ok, salida = ser.run(
            "test -x /usr/local/bin/titan-acerca && "
            "test -f /usr/share/applications/titan-acerca.desktop && "
            "/usr/local/bin/titan-acerca --comprobar "
            "| grep -q '^ram=' && echo listo")
        anotar("Acerca ejecutable y en el catalogo del live",
               ok and "listo" in salida,
               salida.strip()[:120] or "sin salida")

        ok, salida = ser.run("cat /tmp/titan-panel.log 2>/dev/null")
        metricas["log_panel"] = salida.strip()[:1000]
        anotar("log de la barra", True,
               "vacio" if not salida.strip() else salida.strip()[:120])

        ok, salida = ser.run(
            "grep -q 'sin layer-shell' /tmp/titan-panel.log "
            "/tmp/titan-desktop.log 2>/dev/null "
            "&& echo encontrado || echo limpio")
        anotar("layer-shell activo", ok and "limpio" in salida,
               salida.strip()[:120] or "sin salida")

        # labwc exporta LABWC_PID a los procesos del autostart. Ya no hay
        # boton Salir, pero se conserva la comprobacion del entorno porque el
        # cierre ordenado de la sesion depende de esa variable.
        ok, salida = ser.run(
            "pid=$(pgrep -x titan-desktop | head -n1); "
            "tr '\\0' '\\n' < /proc/$pid/environ | grep '^LABWC_PID='")
        anotar("LABWC_PID en el escritorio",
               ok and "LABWC_PID=" in salida,
               salida.strip()[:120] or "no hereda LABWC_PID")

        ok, salida = ser.run("cat /tmp/titan-desktop.log 2>/dev/null")
        metricas["log_escritorio"] = salida.strip()[:1000]
        anotar("log del escritorio", True,
               "vacio" if not salida.strip() else salida.strip()[:120])

        if not args.no_shot:
            time.sleep(6)
            try:
                if not mon.screendump(ppm):
                    anotar("captura de pantalla", False, "screendump fallo")
                else:
                    ancho, alto, pixeles = leer_ppm(ppm)
                    metricas["pantalla"] = {"ancho": ancho, "alto": alto}
                    if args.resolution:
                        anotar("resolucion del guest",
                               (ancho, alto) == (res_ancho, res_alto),
                               f"{ancho}x{alto}, esperado {args.resolution}")
                    metricas.update(analizar(ancho, alto, pixeles))
                    barra = analizar_barra(ancho, alto, pixeles)
                    metricas["barra"] = barra
                    if shutil.which("magick"):
                        subprocess.run(["magick", ppm, png], check=False)
                    elif shutil.which("convert"):
                        subprocess.run(["convert", ppm, png], check=False)
                    else:
                        ppm_a_png(ppm, png)
                    bueno = (metricas["no_negro"] > 0.60
                             and metricas["azulados"] > 0.35)
                    anotar("fondo del escritorio", bueno,
                           f"no_negro={metricas['no_negro']} "
                           f"azulados={metricas['azulados']} "
                           f"rgb={metricas['media_rgb']}")
                    barra_ok = (barra["interior"] > 0.40 or barra["borde"] > 0.40)
                    anotar("barra / dock inferior visible",
                           barra_ok,
                           f"borde={barra['borde']} "
                           f"interior={barra['interior']}")
            except Exception as exc:  # noqa: BLE001 - se informa y se sigue
                anotar("captura de pantalla", False, f"error: {exc}")

        if args.interactuar and not args.no_shot:
            try:
                ancho = int(metricas["pantalla"]["ancho"])
                alto = int(metricas["pantalla"]["alto"])

                def guardar_png(ruta_ppm: str, ruta_png: str) -> None:
                    if shutil.which("magick"):
                        subprocess.run(["magick", ruta_ppm, ruta_png],
                                       check=False)
                    elif shutil.which("convert"):
                        subprocess.run(["convert", ruta_ppm, ruta_png],
                                       check=False)
                    else:
                        ppm_a_png(ruta_ppm, ruta_png)

                def capturar(ruta_ppm: str) -> tuple[int, int, bytes]:
                    if not mon.screendump(ruta_ppm):
                        raise RuntimeError(f"screendump fallo: {ruta_ppm}")
                    return leer_ppm(ruta_ppm)

                # La barra empieza por Inicio: centro en x=35. Las ancladas
                # van despues (Terminal en x=85, Archivos en x=133) y las
                # tareas empiezan en x=181.
                inicio_x = int(35 * ancho / 1280)
                barra_y = alto - 30
                qmp.clic(inicio_x, barra_y, ancho, alto)
                time.sleep(1.2)
                cancho, calto, cpixeles = capturar(centro_ppm)
                guardar_png(centro_ppm, centro_png)
                tarjeta = detectar_tarjeta(cancho, calto, cpixeles)
                barra_centro = analizar_barra(cancho, calto, cpixeles)
                metricas["centro"] = {
                    "tarjeta": tarjeta,
                    "barra": barra_centro,
                }
                ok, salida = ser.run(
                    "grep -q 'centro abierto' /tmp/titan-panel.log "
                    "&& echo si || echo no")
                anotar("centro abierto con Inicio",
                       ok and "si" in salida,
                       f"tarjeta={tarjeta} barra={barra_centro}")
                anotar("el centro oscurece la barra",
                       barra_centro["borde"] < 0.30,
                       f"borde={barra_centro['borde']}")
                anotar("tarjeta del centro visible",
                       tarjeta["pixeles"] >= 2
                       and tarjeta["izquierda"] < ancho * 0.30
                       and tarjeta["derecha"] > ancho * 0.70,
                       f"tarjeta={tarjeta}")

                mon.cmd("sendkey esc")
                time.sleep(1.5)
                _, _, epixeles = capturar(cierre_ppm)
                guardar_png(cierre_ppm, cierre_png)
                barra_cierre = analizar_barra(ancho, alto, epixeles)
                metricas["cierre_esc"] = barra_cierre
                ok, salida = ser.run(
                    "grep -q 'centro cerrado' /tmp/titan-panel.log "
                    "&& echo si || echo no")
                anotar("Escape cierra el centro",
                       ok and "si" in salida
                       and barra_cierre["borde"] > 0.50,
                       f"barra={barra_cierre} log={salida.strip()[:60]}")

                qmp.clic(inicio_x, barra_y, ancho, alto)
                time.sleep(1.0)
                qmp.clic(20, 20, ancho, alto)
                time.sleep(1.0)
                _, _, fpixeles = capturar(cierre_ppm)
                guardar_png(cierre_ppm, cierre_png)
                barra_fuera = analizar_barra(ancho, alto, fpixeles)
                metricas["cierre_fuera"] = barra_fuera
                ok, salida = ser.run(
                    "grep -c 'centro cerrado' /tmp/titan-panel.log")
                anotar("clic fuera cierra el centro",
                       barra_fuera["borde"] > 0.50 and "2" in salida,
                       f"barra={barra_fuera} cierres={salida.strip()[:40]}")

                qmp.clic(int(85 * ancho / 1280), barra_y, ancho, alto)
                time.sleep(5.0)
                _, _, tpixeles = capturar(tarea_ppm)
                guardar_png(tarea_ppm, tarea_png)
                barra_tarea = analizar_barra(ancho, alto, tpixeles)
                metricas["tarea"] = barra_tarea
                ok, salida = ser.run("pgrep -a -x kitty")
                anotar("el boton Terminal abre kitty",
                       ok and "kitty" in salida,
                       salida.strip()[:80] or "sin kitty")
                ok, salida = ser.run(
                    "grep -q 'titan-panel: ventanas:.*kitty' "
                    "/tmp/titan-panel.log && echo si || echo no")
                anotar("la barra anade la tarea de kitty",
                       ok and "si" in salida,
                       salida.strip()[:120] or "sin log")

                tarea_x = int(181 * ancho / 1280)
                qmp.clic(tarea_x, barra_y, ancho, alto)
                time.sleep(1.2)
                qmp.clic(tarea_x, barra_y, ancho, alto)
                time.sleep(1.2)
                ok_min, salida_min = ser.run(
                    "grep -q 'titan-panel: minimizar' "
                    "/tmp/titan-panel.log && echo si || echo no")
                ok_act, salida_act = ser.run(
                    "grep -q 'titan-panel: activar' "
                    "/tmp/titan-panel.log && echo si || echo no")
                anotar("la tarea minimiza y restaura",
                       ok_min and "si" in salida_min
                       and ok_act and "si" in salida_act,
                       f"minimizar={salida_min.strip()[:20]} "
                       f"activar={salida_act.strip()[:20]}")

                # El menu contextual de la tarea tambien debe cerrar la
                # ventana. Se navega con flechas para no depender del
                # tamano exacto del menu: ventana, minimizar y cerrar.
                qmp.clic(tarea_x, barra_y, ancho, alto, "right")
                time.sleep(0.8)
                for _ in range(3):
                    mon.cmd("sendkey down")
                    time.sleep(0.2)
                mon.cmd("sendkey ret")
                time.sleep(2.0)
                ok, salida = ser.run("pgrep -a -x kitty")
                anotar("Cerrar del menu cierra kitty",
                       not (ok and "kitty" in salida),
                       salida.strip()[:80] or "kitty cerrado")
                _, _, cpixeles2 = capturar(fin_ppm)
                guardar_png(fin_ppm, fin_png)
                puntos = [(tarea_x - 25, barra_y), (tarea_x + 25, barra_y)]
                fondo_i = (barra_y * ancho + min(ancho - 20,
                                                  tarea_x + 200)) * 3
                fondo = tuple(cpixeles2[fondo_i:fondo_i + 3])
                claros = []
                for px, py in puntos:
                    i = (py * ancho + px) * 3
                    claros.append(tuple(cpixeles2[i:i + 3]))
                vacios = all(
                    all(abs(p[canal] - fondo[canal]) <= 5
                        for canal in range(3))
                    for p in claros)
                anotar("la tarea desaparece al cerrar kitty",
                       vacios,
                       f"tarea={claros} fondo={fondo}")
            except Exception as exc:  # noqa: BLE001 - se informa y se sigue
                anotar("interaccion con la barra", False, f"error: {exc}")

        if args.cerrar:
            # El entorno Wayland se lee del cliente titan-desktop, no de
            # labwc: el compositor no lleva WAYLAND_DISPLAY en su propio
            # entorno, pero si se lo pasa a sus hijos. Es el mismo entorno que
            # hereda el boton Salir al ejecutar 'labwc --exit'.
            ok, salida = ser.run(
                "pid=$(pgrep -x titan-desktop | head -n1); "
                "tr '\\0' '\\n' < /proc/$pid/environ | "
                "grep -E '^(XDG_RUNTIME_DIR|WAYLAND_DISPLAY)='")
            entorno = {}
            for linea in salida.splitlines():
                if "=" in linea:
                    clave, valor = linea.split("=", 1)
                    entorno[clave] = valor
            runtime = entorno.get("XDG_RUNTIME_DIR", "")
            display = entorno.get("WAYLAND_DISPLAY", "")
            if not runtime or not display:
                anotar("cierre de labwc", False, "sin entorno Wayland")
            else:
                # 'labwc --exit' manda SIGTERM al PID de LABWC_PID; la shell
                # de ttyS0 no lo hereda (no es hija de labwc), asi que se lo
                # pasamos a mano. No hay boton Salir: el cierre ordenado se
                # prueba desde el arnes.
                ser.run(
                    f"LABWC_PID=$(pgrep -x labwc | head -n1) "
                    f"XDG_RUNTIME_DIR={runtime} "
                    f"WAYLAND_DISPLAY={display} labwc --exit", timeout=40)
                time.sleep(8)
                ok, salida = ser.run("tmux ls 2>&1")
                anotar("vuelta a tmux tras cerrar", ok and "titan" in salida,
                       salida.strip().splitlines()[0][:120] if salida.strip()
                       else "sin sesion")
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.kill()
        qemu_log.close()
        log.close()

    informe = {
        "iso": iso,
        "modo": modo,
        "checks": checks,
        "metricas": metricas,
        "pantalla": png if os.path.exists(png) else ppm,
        "qemu_log": qemu_log_path,
    }
    with open(info_path, "w", encoding="utf-8") as f:
        json.dump(informe, f, ensure_ascii=False, indent=2)

    fallos = sum(1 for c in checks if not c["ok"])
    print(f"---\ninforme: {info_path}")
    print(f"captura: {informe['pantalla']}")
    print(f"comprobar-escritorio-qemu: {len(checks)} comprobaciones, "
          f"{fallos} FALLO")
    return 0 if fallos == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
