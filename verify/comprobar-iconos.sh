#!/bin/bash
# Comprueba que ningun icono de las apps queda "null" (imagen vacia):
#   1. cada qrc:/icons/... usado en QML o C++ esta en el .qrc de su app,
#   2. cada fichero que lista un .qrc existe,
#   3. los PNG/SVG de iconos no estan vacios ni rotos,
#   4. los file:///usr/share/titan/icons/... que se usan existen en la ISO,
#   5. el generador de iconos SVG (TitanIconoSvg.h) produce SVG valido.
#
# Uso: ./verify/comprobar-iconos.sh

set -u
raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "${raiz}" <<'PY'
import glob, os, re, sys
raiz = sys.argv[1]
apps = os.path.join(raiz, "apps")
airootfs = os.path.join(raiz, "iso/titan/airootfs")
fallos = 0
def fallo(msg):
    global fallos
    fallos += 1
    print("FALLO", msg)

def valido(ruta):
    try:
        d = open(ruta, "rb").read()
    except OSError:
        return False
    if ruta.endswith(".png"):
        return d[:8] == b"\x89PNG\r\n\x1a\n" and len(d) > 100
    if ruta.endswith(".svg"):
        return b"<svg" in d
    if ruta.endswith((".jpg", ".jpeg")):
        return d[:2] == b"\xff\xd8"
    return len(d) > 0

usados_titan = set()
for app in sorted(glob.glob(os.path.join(apps, "titan-*"))):
    nombre = os.path.basename(app)
    disponibles = set()
    for q in glob.glob(os.path.join(app, "*.qrc")):
        base = os.path.dirname(q)
        for alias, f in re.findall(r'<file(?: alias="([^"]+)")?>([^<]+)</file>', open(q).read()):
            ruta = os.path.normpath(os.path.join(base, f))
            disponibles.add(alias or f)
            if not os.path.exists(ruta):
                fallo(f"[{nombre}] el .qrc lista {f}, que no existe")
            elif re.search(r"\.(png|svg|jpe?g)$", ruta) and not valido(ruta):
                fallo(f"[{nombre}] icono vacio o roto: {f}")
    fuentes = glob.glob(os.path.join(app, "qml", "*.qml")) + glob.glob(os.path.join(app, "src", "*.cpp"))
    for f in fuentes:
        texto = open(f, encoding="utf-8", errors="ignore").read()
        for r in re.findall(r"qrc:/((?:icons|images)/[A-Za-z0-9_/-]+\.(?:png|svg|jpe?g))", texto):
            if disponibles and r not in disponibles:
                fallo(f"[{nombre}] {os.path.basename(f)} usa qrc:/{r}, que no esta en su .qrc")
        usados_titan.update(re.findall(r"file:///usr/share/titan/icons/([A-Za-z0-9_.-]+)", texto))

for icono in sorted(usados_titan):
    ruta = os.path.join(airootfs, "usr/share/titan/icons", icono)
    if not valido(ruta):
        fallo(f"se usa file:///usr/share/titan/icons/{icono}, que no esta (o esta roto) en la ISO")

print("---")
print(f"comprobar-iconos: {fallos} FALLO")
sys.exit(1 if fallos else 0)
PY
estado=$?

# Generador SVG: compila un programa minimo y valida la salida con rsvg-convert si esta.
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
cat >"${tmp}/g.cpp" <<'CPP'
#include <QCoreApplication>
#include <cstdio>
#include "TitanIconoSvg.h"
int main(int a, char **v) {
    QCoreApplication app(a, v);
    const char *casos[][2] = {{"Alacritty", "alacritty"}, {"Spotify", "spotify"}, {"Zeal", "zeal"}, {"<&'\">", ""}};
    for (auto &c : casos)
        std::printf("%s\x1e", titan::svgIcono(QString::fromUtf8(c[0]), QString::fromUtf8(c[1])).toUtf8().constData());
    return 0;
}
CPP
if command -v pkg-config >/dev/null && pkg-config --exists Qt6Core; then
  if g++ -std=c++17 -fPIC -I"${raiz}/apps/titan-common" $(pkg-config --cflags Qt6Core) \
       "${tmp}/g.cpp" -o "${tmp}/g" $(pkg-config --libs Qt6Core) 2>"${tmp}/err"; then
    "${tmp}/g" | python3 -c '
import sys, xml.dom.minidom
partes = [p for p in sys.stdin.read().split("\x1e") if p]
ok = True
for i, p in enumerate(partes):
    try:
        xml.dom.minidom.parseString(p)
    except Exception as e:
        ok = False; print("FALLO generador SVG caso", i, e)
print("OK    generador SVG:", len(partes), "iconos bien formados" if ok else "con errores")
sys.exit(0 if ok else 1)' || estado=1
  else
    echo "FALLO no compila TitanIconoSvg.h"; cat "${tmp}/err"; estado=1
  fi
else
  echo "AVISO: sin Qt6Core no se prueba el generador SVG"
fi
exit "${estado}"
