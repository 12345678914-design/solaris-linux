#!/usr/bin/env python3
"""Abre el live de Titan Linux con un disco encima y ejecuta ordenes dentro.

Es para DIAGNOSTICAR, no para comprobar: no sabe si lo que ve esta bien ni mal,
solo lo mira y lo enseña. La diferencia con titan-instala.py y titan-verify.py
es que aquellos arrancan la maquina virtual ellos mismos y contestan con un
veredicto; este no juzga nada. Aqui se arranca con un disco ya existente (el de
una instalacion que ha fallado, por ejemplo) y se le pregunta al live que ve,
sin instalar nada.

    # mirar como quedo el disco de la ultima instalacion
    python3 scripts/titan-mira.py --disco run/instalacion-20G.qcow2 \\
        'ls -l /mnt/tmp' 'findmnt /mnt'

    # montar a mano lo que hizo el instalador y mirar dentro
    python3 scripts/titan-mira.py --disco run/instalacion-20G.qcow2 \\
        'sudo mount /dev/vda2 /mnt' 'ls /mnt'

Y con '--sin-iso' arranca SIN el live, que es lo unico que puede mirar el
sistema ya instalado de verdad (con el live delante siempre se mira el live):
entra con '--usuario' y '--clave' y pregunta lo que haga falta.

    # preguntar al sistema instalado si el zram esta en pie
    python3 scripts/titan-mira.py --disco run/instalacion-20G.qcow2 --sin-iso \\
        --usuario isai --clave isai 'swapon --show' 'locale -a'

Lo unico que hace es arrancar QEMU, conectarse a la consola serie y mandar lo
que se le pase, en el mismo orden. La consola se guarda entera en un log, asi
que si algo sale raro esta todo lo que llego.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

AQUI = pathlib.Path(__file__).resolve().parent
DISTRO = AQUI.parent
sys.path.insert(0, str(AQUI))
os.chdir(DISTRO)

OVMF_CODE = "/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS = "/usr/share/edk2/x64/OVMF_VARS.4m.fd"
ISO_POR_DEFECTO = "out/titan-linux-0.1.0-x86_64.iso"


def cargar_serial():
    """Toma la clase Serial de titan-verify.py (el codigo, no una copia)."""
    ruta = AQUI / "titan-verify.py"
    spec = importlib.util.spec_from_file_location("titan_verify", ruta)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.Serial, mod.wait_for_shell


def cargar_instaladora():
    """Toma 'entrar()' de titan-instala.py: entrar en el sistema instalado es
    una cosa sola y no puede estar escrita dos veces (una de las dos se
    quedaria vieja y nadie se enteraria hasta que la otra cambiara)."""
    ruta = AQUI / "titan-instala.py"
    spec = importlib.util.spec_from_file_location("titan_instala", ruta)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ordenes", nargs="+",
                    help="ordenes a ejecutar en el live, en orden")
    ap.add_argument("--disco", required=True,
                    help="fichero qcow2 para enchufar como /dev/vda (rw)")
    ap.add_argument("--iso", default=ISO_POR_DEFECTO)
    ap.add_argument("--bios", action="store_true",
                    help="arrancar en BIOS en vez de UEFI")
    ap.add_argument("--memory", default="4096")
    ap.add_argument("--cpus", default="2")
    ap.add_argument("--timeout", type=float, default=900,
                    help="segundos de espera por orden (por defecto 900)")
    ap.add_argument("--solo-live", action="store_true",
                    help="arrancar sin disco, para probar el live pelado")
    ap.add_argument("--sin-iso", action="store_true",
                    help="arrancar SOLO el disco: es la unica forma de mirar el "
                         "sistema ya instalado de verdad (con el live delante se "
                         "mira el live, y las dos cosas se parecen)")
    ap.add_argument("--usuario", default="",
                    help="con --sin-iso: usuario para entrar en el sistema instalado")
    ap.add_argument("--clave", default="",
                    help="con --sin-iso: contrasena de ese usuario")
    args = ap.parse_args()

    iso = os.path.abspath(args.iso)
    disco = None if args.solo_live else os.path.abspath(args.disco)
    if not args.solo_live and not os.path.exists(disco):
        print(f"no existe el disco {disco}", file=sys.stderr)
        return 2
    if args.sin_iso and args.solo_live:
        print("--sin-iso y --solo-live a la vez no tienen sentido", file=sys.stderr)
        return 2

    tmp = tempfile.mkdtemp(prefix="titan-mira-")
    ser_path = os.path.join(tmp, "serial.sock")
    log_path = os.path.join(tmp, "consola.log")
    vars_copy = os.path.join(tmp, "OVMF_VARS.fd")
    if not args.bios:
        shutil.copy(OVMF_VARS, vars_copy)

    cmd = [
        "qemu-system-x86_64",
        "-machine", "q35,accel=kvm:tcg",
        "-cpu", "max",
        "-m", args.memory,
        "-smp", args.cpus,
        "-boot", "order=dc" if args.solo_live else "order=c",
        "-nic", "user,model=virtio-net-pci",
        "-audiodev", "none,id=snd0",
        "-display", "none",
        "-chardev", f"socket,id=ser0,path={ser_path},server=on,wait=off",
        "-serial", "chardev:ser0",
    ]
    if disco:
        cmd += ["-drive", f"if=virtio,format=qcow2,file={disco}"]
    if not args.solo_live and not args.sin_iso:
        cmd += ["-drive", f"file={iso},media=cdrom,readonly=on"]
    if not args.bios:
        cmd += [
            "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={OVMF_CODE}",
            "-drive", f"if=pflash,format=raw,unit=1,file={vars_copy}",
        ]

    print(f"==> disco    : {disco or '(ninguno)'}")
    print(f"==> live     : {'no (se arranca el disco)' if args.sin_iso else 'si'}")
    print(f"==> consola  : {log_path}")
    print(f"==> ordenes  : {len(args.ordenes)}")
    print(f"==> qemu     : {' '.join(cmd)}\n", flush=True)

    Serial, wait_for_shell = cargar_serial()
    log = open(log_path, "w", encoding="utf-8", errors="replace")
    ser = Serial(ser_path, log)
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        if not ser.connect(time.time() + 30):
            print("no se pudo conectar a la consola serie", file=sys.stderr)
            return 1
        if args.sin_iso:
            # El sistema instalado no tiene autologin (eso es solo del live),
            # asi que hay que entrar de verdad, escribiendo la contrasena. Y eso
            # es ademas una comprobacion: si la clave que puso el instalador no
            # llego a /etc/shadow, aqui no se entra y se dice por que.
            print("==> conectando; esperando el login del sistema instalado", flush=True)
            if not args.usuario or not args.clave:
                print("con --sin-iso hacen falta --usuario y --clave", file=sys.stderr)
                return 2
            mod = cargar_instaladora()
            ok, sal = mod.entrar(ser, args.usuario, args.clave, tmo=int(args.timeout))
            if not ok:
                print(f"no se ha podido entrar en el sistema instalado: {sal}",
                      file=sys.stderr)
                return 1
            print(f"==> dentro como {args.usuario}\n", flush=True)
        else:
            print("==> conectando; esperando la shell", flush=True)
            if not wait_for_shell(ser, 600):
                print("el live no llego a la shell", file=sys.stderr)
                return 1
            print("==> shell lista\n", flush=True)
        for orden in args.ordenes:
            print(f"==> {orden}", flush=True)
            ok, salida = ser.run(orden, timeout=args.timeout)
            print(f"--- codigo: {'bien' if ok else 'SIN MARCA (se agotaron los %d s)' % int(args.timeout)}")
            print(salida if salida.strip() else "(sin salida)")
            print("", flush=True)
    finally:
        # OJO con lo de 'sync' antes de apagar: este guion monta el disco en
        # blanco y a veces se escribe en el (un 'locale-gen', un 'remote-add').
        # Si el guion se acaba con el disco montado y QEMU se lleva por delante
        # lo que el guest tiene en memoria, ESAS ESCRITURAS NO LLEGAN NUNCA al
        # fichero del disco, y la sesion siguiente ve un disco que parece que
        # nunca se toco. Con 'sync' lo que se ha escrito esta en el fichero.
        try:
            ser.run("sync", timeout=60)
        except Exception:       # pragma: no cover - si ya no hay consola
            pass
        # QEMU se apaga como se apaga un equipo: por el monitor, que es lo
        # limpio. Si el monitor no esta, a lo bruto.
        try:
            subprocess.run(["pkill", "-TERM", "-f", f"titan-mira-{os.path.basename(tmp)}"],
                           capture_output=True)
        except OSError:
            pass
        proc.terminate()
        try:
            proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            proc.kill()
        log.close()
        print(f"(consola completa en {log_path})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
