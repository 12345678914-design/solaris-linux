#!/usr/bin/env python3
"""Genera la animacion de carga de Inti OS (Plymouth, tema "titan"):
un circulo de cinco puntos que giran como en Windows, y el sol de Inti.

  python3 scripts/generar-animacion-arranque.py

Escribe iso/titan/airootfs/usr/share/titan/plymouth/{throbber-NNNN,watermark}.png.
Plymouth (two-step) reproduce los throbber-* en bucle cada 2 segundos.
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw

RAIZ = Path(__file__).resolve().parent.parent
DEST = RAIZ / "iso/titan/airootfs/usr/share/titan/plymouth"
LOGO = RAIZ / "apps/titan-shell/icons/solaris-logo.png"

FOTOGRAMAS = 60          # 2 s de bucle (Plymouth lo reparte en ese tiempo)
LIENZO = 64              # px; Plymouth lo escala en pantallas HiDPI
RADIO = 22               # radio del circulo de puntos
PUNTO = 3.2              # radio de cada punto
PUNTOS = 5
RETRASO = 0.075          # desfase entre puntos (fraccion del bucle)
SUPER = 4                # sobremuestreo para bordes suaves


def avance(u: float) -> float:
    """Vuelta completa con el ritmo de Windows: lento abajo, rapido arriba."""
    u %= 1.0
    return u - 0.85 * math.sin(2 * math.pi * u) / (2 * math.pi)


def fotograma(t: float) -> Image.Image:
    g = LIENZO * SUPER
    im = Image.new("RGBA", (g, g), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = g / 2
    for i in range(PUNTOS):
        a = 2 * math.pi * avance(t - i * RETRASO) + math.pi / 2   # empieza abajo
        x = c + RADIO * SUPER * math.cos(a)
        y = c + RADIO * SUPER * math.sin(a)
        r = PUNTO * SUPER
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, 255))
    return im.resize((LIENZO, LIENZO), Image.LANCZOS)


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    for viejo in DEST.glob("throbber-*.png"):
        viejo.unlink()
    for n in range(FOTOGRAMAS):
        fotograma(n / FOTOGRAMAS).save(DEST / f"throbber-{n + 1:04d}.png", optimize=True)
    # El sol de Inti, grande (sin el margen transparente del original)
    logo = Image.open(LOGO).convert("RGBA")
    logo = logo.crop(logo.getbbox()).resize((220, 220), Image.LANCZOS)
    logo.save(DEST / "watermark.png", optimize=True)
    print(f"{FOTOGRAMAS} fotogramas y watermark.png en {DEST}")


if __name__ == "__main__":
    main()
