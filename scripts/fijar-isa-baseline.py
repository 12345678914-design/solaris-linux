#!/usr/bin/env python3
"""Baja a x86-64-baseline la marca "x86 ISA needed" de binarios ELF.

Por que existe: en un anfitrion CachyOS con repos v4, el Scrt1.o de su glibc
lleva la propiedad GNU_PROPERTY_X86_ISA_1_NEEDED = v4, y el enlazador la copia
a TODO lo que se compila ahi (hasta un "int main(){}"). El codigo de las apps
no usa AVX ni AVX-512, pero ld.so mira la marca y en CPUs sin AVX-512 se niega
a arrancarlas con "CPU ISA level is lower than required". El enlazador no deja
cambiarla (-z x86-64-baseline revienta binutils 2.47), asi que se corrige
despues de enlazar, tocando solo ese valor: las demas propiedades (IBT/SHSTK)
se quedan como estan.

Uso: fijar-isa-baseline.py [--comprobar] FICHERO...
  sin opciones  reescribe la marca en los ELF que pidan mas que baseline
  --comprobar   no toca nada; sale con 1 si alguno pide mas que baseline
"""
import struct
import sys

NT_GNU_PROPERTY_TYPE_0 = 5
ISA_1_NEEDED = 0xC0008002
BASELINE = 0x1
NIVELES = {0x1: "baseline", 0x2: "v2", 0x4: "v3", 0x8: "v4"}


def nombres(valor):
    return ",".join(n for b, n in NIVELES.items() if valor & b) or "ninguna"


def notas_de_propiedades(datos):
    """Rangos (inicio, tamano) de .note.gnu.property / PT_GNU_PROPERTY."""
    if datos[:4] != b"\x7fELF" or datos[4] != 2 or datos[5] != 1:
        return []  # solo ELF64 little-endian (x86_64)
    e_phoff, e_shoff = struct.unpack_from("<QQ", datos, 0x20)
    e_phentsize, e_phnum, e_shentsize, e_shnum = struct.unpack_from("<HHHH", datos, 0x36)
    rangos = set()
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from("<I", datos, off)[0]
        if p_type == 0x6474E553:  # PT_GNU_PROPERTY
            p_offset, _, _, p_filesz = struct.unpack_from("<QQQQ", datos, off + 8)
            rangos.add((p_offset, p_filesz))
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        sh_type = struct.unpack_from("<I", datos, off + 4)[0]
        if sh_type == 7:  # SHT_NOTE
            sh_offset, sh_size = struct.unpack_from("<QQ", datos, off + 24)
            rangos.add((sh_offset, sh_size))
    return sorted(rangos)


def posiciones_isa(datos):
    """Offsets del valor de cada ISA_1_NEEDED encontrado."""
    vistas = []
    for inicio, tam in notas_de_propiedades(datos):
        p, fin = inicio, inicio + tam
        while p + 12 <= fin:
            namesz, descsz, ntype = struct.unpack_from("<III", datos, p)
            nombre = datos[p + 12:p + 12 + namesz]
            desc = p + 12 + ((namesz + 3) & ~3)
            if ntype == NT_GNU_PROPERTY_TYPE_0 and nombre == b"GNU\x00":
                q, qfin = desc, desc + descsz
                while q + 8 <= qfin:
                    pr_type, pr_datasz = struct.unpack_from("<II", datos, q)
                    if pr_type == ISA_1_NEEDED and pr_datasz == 4:
                        vistas.append(q + 8)
                    q += 8 + ((pr_datasz + 7) & ~7)
            p = desc + ((descsz + 7) & ~7)  # ELF64: notas alineadas a 8
    return sorted(set(vistas))


def main(args):
    comprobar = "--comprobar" in args
    ficheros = [a for a in args if a != "--comprobar"]
    malos = 0
    for f in ficheros:
        try:
            with open(f, "rb") as h:
                datos = bytearray(h.read())
        except OSError as e:
            print(f"{f}: no se pudo leer ({e})", file=sys.stderr)
            malos += 1
            continue
        cambios = []
        for pos in posiciones_isa(datos):
            valor = struct.unpack_from("<I", datos, pos)[0]
            if valor & ~BASELINE:
                cambios.append((pos, valor))
        if not cambios:
            continue
        actual = nombres(cambios[0][1])
        if comprobar:
            print(f"{f}: pide {actual} (deberia ser baseline)")
            malos += 1
            continue
        for pos, _ in cambios:
            struct.pack_into("<I", datos, pos, BASELINE)
        with open(f, "r+b") as h:
            h.write(datos)
        print(f"{f}: {actual} -> baseline")
    return 1 if malos else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
