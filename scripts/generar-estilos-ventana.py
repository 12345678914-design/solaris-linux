#!/usr/bin/env python3
"""Inti OS - genera los ficheros de cada estilo de botones de ventana para GTK
y labwc en iso/titan/airootfs/usr/share/titan/ventanas/<estilo>/.

Cada estilo tiene su carpeta y su logica, sin relacion con los demas:
  estilo.conf   lado y orden de los botones (GTK y labwc), medidas de labwc
  gtk3.css      Firefox y apps GTK 3        gtk4.css   apps GTK 4 / libadwaita
  labwc/{oscuro,claro}/*.svg  iconos de la barra de labwc (#ACENTO se cambia
                al instalarlos por el color de Ajustes)
titan-estilo-ventanas copia SOLO los del estilo elegido.
Uso: python3 scripts/generar-estilos-ventana.py"""
import os, shutil

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(RAIZ, "iso/titan/airootfs/usr/share/titan/ventanas")
TINTA = {"oscuro": "#f2f2f5", "claro": "#1d1d1f"}
GRIS = {"oscuro": "#4b4e58", "claro": "#cfcfd3"}
IZQ = ("izquierda", "close,minimize,maximize:", "close,iconify,max:")
DER = ("derecha", ":minimize,maximize,close", ":iconify,max,close")

def glifo(t, cx, cy, s, g, c, op=1):
    h = s / 2
    a = f'stroke="{c}" stroke-opacity="{op}" stroke-width="{g}" stroke-linecap="round" fill="none"'
    if t == "iconify":
        return f'<line x1="{cx-h}" y1="{cy}" x2="{cx+h}" y2="{cy}" {a}/>'
    if t in ("max", "max_toggled"):
        if t == "max_toggled":  # restaurar: dos cuadrados
            return (f'<rect x="{cx-h+2}" y="{cy-h}" width="{s-2}" height="{s-2}" rx="{s*0.15}" {a}/>'
                    f'<rect x="{cx-h}" y="{cy-h+2}" width="{s-2}" height="{s-2}" rx="{s*0.15}" {a} fill-opacity="1"/>')
        return f'<rect x="{cx-h}" y="{cy-h}" width="{s}" height="{s}" rx="{s*0.18}" {a}/>'
    return (f'<line x1="{cx-h}" y1="{cy-h}" x2="{cx+h}" y2="{cy+h}" {a}/>'
            f'<line x1="{cx+h}" y1="{cy-h}" x2="{cx-h}" y2="{cy+h}" {a}/>')

def svg(w, h, cuerpo):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{cuerpo}</svg>\n'

# ------------------------------------------------------------------ estilos
# Cada uno: dict con conf, gtk3, gtk4 y labwc(tipo, estado, modo) -> svg.
# estado: "active" | "inactive" | "hover"

def actual():
    W = H = 22
    col = {"close": "#ff5f57", "iconify": "#febc2e", "max": "#28c840", "max_toggled": "#28c840"}
    def lab(t, e, m):
        f = col[t] if e != "inactive" else GRIS[m]
        c = f'<circle cx="11" cy="11" r="6.5" fill="{f}" stroke="#000" stroke-opacity="0.18" stroke-width="0.6"/>'
        if e == "hover":
            c += glifo(t, 11, 11, 5.5, 1.3, "#000", 0.6)
        return svg(W, H, c)
    gtk3 = '''/* Inti OS - botones de ventana: Actual (semaforo a la izquierda). GTK 3. */
headerbar button.titlebutton,
.titlebar button.titlebutton {
  min-width: 14px; min-height: 14px; margin: 0 3px; padding: 0;
  border: none; border-radius: 100%; background-image: none;
  box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.14);
  color: transparent; -gtk-icon-shadow: none; -gtk-icon-transform: scale(0.62);
  transition: background-color 120ms ease-out, color 120ms ease-out;
}
headerbar button.titlebutton.close, .titlebar button.titlebutton.close { background-color: #ff5f57; }
headerbar button.titlebutton.minimize, .titlebar button.titlebutton.minimize { background-color: #febc2e; }
headerbar button.titlebutton.maximize, .titlebar button.titlebutton.maximize { background-color: #28c840; }
headerbar:hover button.titlebutton, .titlebar:hover button.titlebutton { color: rgba(0, 0, 0, 0.55); }
headerbar button.titlebutton:active, .titlebar button.titlebutton:active {
  background-image: linear-gradient(rgba(0, 0, 0, 0.18), rgba(0, 0, 0, 0.18));
}
headerbar:backdrop button.titlebutton, .titlebar:backdrop button.titlebutton {
  background-color: alpha(currentColor, 0.22); color: transparent;
}
'''
    gtk4 = '''/* Inti OS - botones de ventana: Actual (semaforo a la izquierda). GTK 4. */
windowcontrols > button { min-width: 14px; min-height: 14px; margin: 0; padding: 0 3px; background: none; box-shadow: none; }
windowcontrols > button > image {
  -gtk-icon-size: 9px; padding: 2px; border-radius: 100%; background-color: #ff5f57;
  box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.14); color: transparent;
  transition: background-color 120ms ease-out, color 120ms ease-out;
}
windowcontrols > button.minimize > image { background-color: #febc2e; }
windowcontrols > button.maximize > image { background-color: #28c840; }
windowcontrols:hover > button > image { color: rgba(0, 0, 0, 0.55); }
windowcontrols > button:active > image { background-image: linear-gradient(rgba(0, 0, 0, 0.18), rgba(0, 0, 0, 0.18)); }
windowcontrols > button:backdrop > image { background-color: alpha(currentColor, 0.22); color: transparent; }
'''
    return dict(lado=IZQ, ancho=22, sep=2, gtk3=gtk3, gtk4=gtk4, labwc=lab, W=W, H=H)

def plano(nombre, titulo, W, H, fondo_hover, radio, simbolo_hover, lado_glifo, grosor):
    """Estilos de boton 'plano' (windows, acento): fondo solo al pasar el raton."""
    def lab(t, e, m):
        c = ""
        cierre = t == "close"
        if e == "hover":
            bg = "#e5484d" if cierre and nombre == "acento" else "#c42b1c" if cierre else fondo_hover(m)
            op = "1" if cierre else ("0.2" if nombre == "acento" else "0.09")
            c += f'<rect x="1" y="{(H-24)/2 if nombre=="acento" else 0}" width="{W-2 if nombre=="acento" else W}" height="{24 if nombre=="acento" else H}" rx="{radio}" fill="{bg}" fill-opacity="{op}"/>'
        col = TINTA[m]
        op = 1 if e != "inactive" else 0.45
        if e == "hover":
            col = "#ffffff" if cierre else simbolo_hover(m)
        c += glifo(t, W / 2, H / 2, lado_glifo, grosor, col, op)
        return svg(W, H, c)
    return lab

def windows():
    W, H = 40, 28
    lab = plano("windows", "Estilo Windows", W, H, lambda m: TINTA[m], 0, lambda m: TINTA[m], 9, 1.0)
    gtk3 = '''/* Inti OS - botones de ventana: Estilo Windows. GTK 3. */
headerbar button.titlebutton,
.titlebar button.titlebutton {
  min-width: 34px; min-height: 26px; margin: 0; padding: 0 6px;
  border: none; border-radius: 0; background: none; box-shadow: none;
  -gtk-icon-shadow: none; transition: background-color 90ms ease-out;
}
headerbar button.titlebutton:hover, .titlebar button.titlebutton:hover { background-color: alpha(currentColor, 0.09); }
headerbar button.titlebutton:active, .titlebar button.titlebutton:active { background-color: alpha(currentColor, 0.05); }
headerbar button.titlebutton.close:hover, .titlebar button.titlebutton.close:hover { background-color: #c42b1c; color: #ffffff; }
headerbar button.titlebutton.close:active, .titlebar button.titlebutton.close:active { background-color: #b3261e; color: #ffffff; }
headerbar:backdrop button.titlebutton, .titlebar:backdrop button.titlebutton { color: alpha(currentColor, 0.45); }
'''
    gtk4 = '''/* Inti OS - botones de ventana: Estilo Windows. GTK 4. */
windowcontrols { border-spacing: 0; }
windowcontrols > button { min-width: 40px; min-height: 28px; margin: 0; padding: 0; border-radius: 0; background: none; box-shadow: none; transition: background-color 90ms ease-out; }
windowcontrols > button > image { background: none; box-shadow: none; padding: 0; -gtk-icon-size: 14px; }
windowcontrols > button:hover { background-color: alpha(currentColor, 0.09); }
windowcontrols > button:active { background-color: alpha(currentColor, 0.05); }
windowcontrols > button.close:hover { background-color: #c42b1c; color: #ffffff; }
windowcontrols > button.close:active { background-color: #b3261e; color: #ffffff; }
windowcontrols > button:backdrop { color: alpha(currentColor, 0.45); }
'''
    return dict(lado=DER, ancho=W, sep=0, gtk3=gtk3, gtk4=gtk4, labwc=lab, W=W, H=H)

def acento():
    W, H = 30, 26
    lab = plano("acento", "Inti acento", W, H, lambda m: "#ACENTO", 7, lambda m: "#ACENTO", 9, 1.4)
    gtk3 = '''/* Inti OS - botones de ventana: Inti acento. GTK 3. */
headerbar button.titlebutton,
.titlebar button.titlebutton {
  min-width: 26px; min-height: 22px; margin: 0 1px; padding: 0 2px;
  border: none; border-radius: 7px; background: none; box-shadow: none;
  -gtk-icon-shadow: none; transition: background-color 100ms ease-out, color 100ms ease-out;
}
headerbar button.titlebutton:hover, .titlebar button.titlebutton:hover { background-color: alpha(@accent_color, 0.2); color: @accent_color; }
headerbar button.titlebutton:active, .titlebar button.titlebutton:active { background-color: alpha(@accent_color, 0.32); color: @accent_color; }
headerbar button.titlebutton.close:hover, .titlebar button.titlebutton.close:hover { background-color: #e5484d; color: #ffffff; }
headerbar button.titlebutton.close:active, .titlebar button.titlebutton.close:active { background-color: #c93a3f; color: #ffffff; }
headerbar:backdrop button.titlebutton, .titlebar:backdrop button.titlebutton { color: alpha(currentColor, 0.45); }
'''
    gtk4 = '''/* Inti OS - botones de ventana: Inti acento. GTK 4. */
windowcontrols > button { min-width: 30px; min-height: 26px; margin: 0 1px; padding: 0; border-radius: 7px; background: none; box-shadow: none; transition: background-color 100ms ease-out, color 100ms ease-out; }
windowcontrols > button > image { background: none; box-shadow: none; padding: 0; }
windowcontrols > button:hover { background-color: alpha(@accent_color, 0.2); color: @accent_color; }
windowcontrols > button:active { background-color: alpha(@accent_color, 0.32); color: @accent_color; }
windowcontrols > button.close:hover { background-color: #e5484d; color: #ffffff; }
windowcontrols > button.close:active { background-color: #c93a3f; color: #ffffff; }
windowcontrols > button:backdrop { color: alpha(currentColor, 0.45); }
'''
    return dict(lado=DER, ancho=W, sep=3, gtk3=gtk3, gtk4=gtk4, labwc=lab, W=W, H=H)

def circulos():
    W = H = 24
    def lab(t, e, m):
        base = "#ffffff" if m == "oscuro" else "#000000"
        op = 0.17 if e == "hover" else 0.09
        c = f'<circle cx="12" cy="12" r="10" fill="{base}" fill-opacity="{op}"/>'
        c += glifo(t, 12, 12, 7, 1.5, TINTA[m], 0.5 if e == "inactive" else 1)
        return svg(W, H, c)
    gtk3 = '''/* Inti OS - botones de ventana: Circulos grises. GTK 3. */
headerbar button.titlebutton,
.titlebar button.titlebutton {
  min-width: 22px; min-height: 22px; margin: 0 3px; padding: 0;
  border: none; border-radius: 100%; background-image: none; box-shadow: none;
  background-color: alpha(currentColor, 0.10); -gtk-icon-shadow: none; -gtk-icon-transform: scale(0.8);
  transition: background-color 100ms ease-out;
}
headerbar button.titlebutton:hover, .titlebar button.titlebutton:hover { background-color: alpha(currentColor, 0.17); }
headerbar button.titlebutton:active, .titlebar button.titlebutton:active { background-color: alpha(currentColor, 0.25); }
headerbar:backdrop button.titlebutton, .titlebar:backdrop button.titlebutton { color: alpha(currentColor, 0.5); }
'''
    gtk4 = '''/* Inti OS - botones de ventana: Circulos grises. GTK 4. */
windowcontrols > button { min-width: 24px; min-height: 24px; margin: 0 2px; padding: 0; background: none; box-shadow: none; }
windowcontrols > button > image { padding: 4px; border-radius: 100%; background-color: alpha(currentColor, 0.10); box-shadow: none; transition: background-color 100ms ease-out; }
windowcontrols > button:hover > image { background-color: alpha(currentColor, 0.17); }
windowcontrols > button:active > image { background-color: alpha(currentColor, 0.25); }
windowcontrols > button:backdrop > image { color: alpha(currentColor, 0.5); }
'''
    return dict(lado=DER, ancho=W, sep=4, gtk3=gtk3, gtk4=gtk4, labwc=lab, W=W, H=H)

def capsula():
    W, H = 30, 26
    def lab(t, e, m):
        base = "#ffffff" if m == "oscuro" else "#000000"
        y, h, r = 2, 22, 11
        if t == "iconify":
            forma = f'M{r},{y} H{W} V{y+h} H{r} A{r},{r} 0 0 1 {r},{y} Z'
        elif t == "close":
            forma = f'M0,{y} H{W-r} A{r},{r} 0 0 1 {W-r},{y+h} H0 Z'
        else:
            forma = f'M0,{y} H{W} V{y+h} H0 Z'
        c = f'<path d="{forma}" fill="{base}" fill-opacity="0.08"/>'
        cierre = t == "close"
        if e == "hover":
            c += f'<path d="{forma}" fill="{"#e5484d" if cierre else base}" fill-opacity="{1 if cierre else 0.12}"/>'
        if t != "iconify":
            c += f'<line x1="0.5" y1="8" x2="0.5" y2="18" stroke="{base}" stroke-opacity="0.15"/>'
        col = "#ffffff" if (cierre and e == "hover") else TINTA[m]
        c += glifo(t, W / 2, H / 2, 8, 1.3, col, 0.45 if e == "inactive" else 1)
        return svg(W, H, c)
    gtk3 = '''/* Inti OS - botones de ventana: Capsula. GTK 3. */
headerbar button.titlebutton,
.titlebar button.titlebutton {
  min-width: 28px; min-height: 22px; margin: 0; padding: 0 2px;
  border: none; border-radius: 0; background-image: none; box-shadow: none;
  background-color: alpha(currentColor, 0.08); -gtk-icon-shadow: none;
  transition: background-color 100ms ease-out;
}
headerbar button.titlebutton.minimize, .titlebar button.titlebutton.minimize { border-radius: 99px 0 0 99px; padding-left: 6px; }
headerbar button.titlebutton.close, .titlebar button.titlebutton.close { border-radius: 0 99px 99px 0; padding-right: 6px; }
headerbar button.titlebutton:hover, .titlebar button.titlebutton:hover { background-color: alpha(currentColor, 0.18); }
headerbar button.titlebutton.close:hover, .titlebar button.titlebutton.close:hover { background-color: #e5484d; color: #ffffff; }
headerbar button.titlebutton.close:active, .titlebar button.titlebutton.close:active { background-color: #c93a3f; color: #ffffff; }
headerbar:backdrop button.titlebutton, .titlebar:backdrop button.titlebutton { color: alpha(currentColor, 0.45); }
'''
    gtk4 = '''/* Inti OS - botones de ventana: Capsula. GTK 4. */
windowcontrols { border-spacing: 0; }
windowcontrols > button { min-width: 32px; min-height: 26px; margin: 0; padding: 0; border-radius: 0; background-color: alpha(currentColor, 0.08); box-shadow: none; transition: background-color 100ms ease-out; }
windowcontrols > button > image { background: none; box-shadow: none; padding: 0; }
windowcontrols > button.minimize { border-radius: 99px 0 0 99px; }
windowcontrols > button.close { border-radius: 0 99px 99px 0; }
windowcontrols > button:hover { background-color: alpha(currentColor, 0.18); }
windowcontrols > button.close:hover { background-color: #e5484d; color: #ffffff; }
windowcontrols > button.close:active { background-color: #c93a3f; color: #ffffff; }
windowcontrols > button:backdrop { color: alpha(currentColor, 0.45); }
'''
    return dict(lado=DER, ancho=W, sep=0, gtk3=gtk3, gtk4=gtk4, labwc=lab, W=W, H=H)

def contorno():
    W = H = 24
    def lab(t, e, m):
        tinte = "#e5484d" if t == "close" else "#ACENTO"
        base = "#ffffff" if m == "oscuro" else "#000000"
        if e == "hover":
            c = f'<circle cx="12" cy="12" r="10" fill="{tinte}" fill-opacity="0.15" stroke="{tinte}" stroke-width="1.2"/>'
            c += glifo(t, 12, 12, 7, 1.4, tinte)
        else:
            c = f'<circle cx="12" cy="12" r="10" fill="none" stroke="{base}" stroke-opacity="{0.45 if e=="active" else 0.25}" stroke-width="1.2"/>'
            c += glifo(t, 12, 12, 7, 1.4, TINTA[m], 1 if e == "active" else 0.45)
        return svg(W, H, c)
    gtk3 = '''/* Inti OS - botones de ventana: Contorno fino. GTK 3. */
headerbar button.titlebutton,
.titlebar button.titlebutton {
  min-width: 20px; min-height: 20px; margin: 0 3px; padding: 0;
  border: none; border-radius: 100%; background: none;
  box-shadow: inset 0 0 0 1px alpha(currentColor, 0.45);
  -gtk-icon-shadow: none; -gtk-icon-transform: scale(0.75);
  transition: background-color 100ms ease-out, box-shadow 100ms ease-out, color 100ms ease-out;
}
headerbar button.titlebutton:hover, .titlebar button.titlebutton:hover {
  background-color: alpha(@accent_color, 0.15); color: @accent_color; box-shadow: inset 0 0 0 1px @accent_color;
}
headerbar button.titlebutton.close:hover, .titlebar button.titlebutton.close:hover {
  background-color: alpha(#e5484d, 0.15); color: #e5484d; box-shadow: inset 0 0 0 1px #e5484d;
}
headerbar:backdrop button.titlebutton, .titlebar:backdrop button.titlebutton { color: alpha(currentColor, 0.45); }
'''
    gtk4 = '''/* Inti OS - botones de ventana: Contorno fino. GTK 4. */
windowcontrols > button { min-width: 24px; min-height: 24px; margin: 0 2px; padding: 0; background: none; box-shadow: none; }
windowcontrols > button > image { padding: 4px; border-radius: 100%; background: none; box-shadow: inset 0 0 0 1px alpha(currentColor, 0.45); -gtk-icon-size: 12px; transition: all 100ms ease-out; }
windowcontrols > button:hover > image { background-color: alpha(@accent_color, 0.15); color: @accent_color; box-shadow: inset 0 0 0 1px @accent_color; }
windowcontrols > button.close:hover > image { background-color: alpha(#e5484d, 0.15); color: #e5484d; box-shadow: inset 0 0 0 1px #e5484d; }
windowcontrols > button:backdrop > image { color: alpha(currentColor, 0.45); }
'''
    return dict(lado=DER, ancho=W, sep=4, gtk3=gtk3, gtk4=gtk4, labwc=lab, W=W, H=H)

def color():
    W = H = 22
    col = {"close": "#ff5f57", "iconify": "#febc2e", "max": "#28c840", "max_toggled": "#28c840"}
    def lab(t, e, m):
        f = col[t] if e != "inactive" else GRIS[m]
        r = 8 if e == "hover" else 7.5
        c = f'<circle cx="11" cy="11" r="{r}" fill="{f}" stroke="#000" stroke-opacity="0.15" stroke-width="0.6"/>'
        c += glifo(t, 11, 11, 6, 1.4, "#000", 0.35 if e == "inactive" else 0.62)
        return svg(W, H, c)
    gtk3 = '''/* Inti OS - botones de ventana: Color a la derecha. GTK 3. */
headerbar button.titlebutton,
.titlebar button.titlebutton {
  min-width: 16px; min-height: 16px; margin: 0 3px; padding: 0;
  border: none; border-radius: 100%; background-image: none;
  box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.15);
  color: rgba(0, 0, 0, 0.62); -gtk-icon-shadow: none; -gtk-icon-transform: scale(0.7);
}
headerbar button.titlebutton.close, .titlebar button.titlebutton.close { background-color: #ff5f57; }
headerbar button.titlebutton.minimize, .titlebar button.titlebutton.minimize { background-color: #febc2e; }
headerbar button.titlebutton.maximize, .titlebar button.titlebutton.maximize { background-color: #28c840; }
headerbar button.titlebutton:active, .titlebar button.titlebutton:active { background-image: linear-gradient(rgba(0, 0, 0, 0.18), rgba(0, 0, 0, 0.18)); }
headerbar:backdrop button.titlebutton, .titlebar:backdrop button.titlebutton { background-color: alpha(currentColor, 0.22); color: rgba(0, 0, 0, 0.35); }
'''
    gtk4 = '''/* Inti OS - botones de ventana: Color a la derecha. GTK 4. */
windowcontrols > button { min-width: 18px; min-height: 18px; margin: 0; padding: 0 3px; background: none; box-shadow: none; }
windowcontrols > button > image { -gtk-icon-size: 10px; padding: 3px; border-radius: 100%; background-color: #ff5f57; box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.15); color: rgba(0, 0, 0, 0.62); }
windowcontrols > button.minimize > image { background-color: #febc2e; }
windowcontrols > button.maximize > image { background-color: #28c840; }
windowcontrols > button:active > image { background-image: linear-gradient(rgba(0, 0, 0, 0.18), rgba(0, 0, 0, 0.18)); }
windowcontrols > button:backdrop > image { background-color: alpha(currentColor, 0.22); color: rgba(0, 0, 0, 0.35); }
'''
    return dict(lado=DER, ancho=W, sep=4, gtk3=gtk3, gtk4=gtk4, labwc=lab, W=W, H=H)

ESTILOS = {"actual": actual, "windows": windows, "circulos": circulos, "acento": acento,
           "capsula": capsula, "contorno": contorno, "color": color}

def main():
    for nombre, f in ESTILOS.items():
        e = f()
        d = os.path.join(DEST, nombre)
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
        lado, gtk, labwc = e["lado"]
        open(os.path.join(d, "estilo.conf"), "w").write(
            f"# Inti OS - estilo de botones de ventana \"{nombre}\" (generado por\n"
            f"# scripts/generar-estilos-ventana.py; no editar a mano)\n"
            f"lado={lado}\ngtk={gtk}\nlabwc={labwc}\nlabwc_ancho={e['ancho']}\nlabwc_separacion={e['sep']}\n")
        open(os.path.join(d, "gtk3.css"), "w").write(e["gtk3"])
        open(os.path.join(d, "gtk4.css"), "w").write(e["gtk4"])
        for modo in ("oscuro", "claro"):
            md = os.path.join(d, "labwc", modo)
            os.makedirs(md)
            for t in ("close", "iconify", "max", "max_toggled"):
                open(os.path.join(md, f"{t}-active.svg"), "w").write(e["labwc"](t, "active", modo))
                open(os.path.join(md, f"{t}-inactive.svg"), "w").write(e["labwc"](t, "inactive", modo))
                open(os.path.join(md, f"{t}_hover-active.svg"), "w").write(e["labwc"](t, "hover", modo))
                open(os.path.join(md, f"{t}_hover-inactive.svg"), "w").write(e["labwc"](t, "hover", modo))
    print("Estilos generados en", DEST)

if __name__ == "__main__":
    main()
