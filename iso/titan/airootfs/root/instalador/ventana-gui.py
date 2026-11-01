#!/usr/bin/env python3
# Titan Linux -- la ventana del instalador, en GTK4 con libadwaita.
#
# El instalador tiene UN motor (install.sh + instalador/*.sh) y UNA pantalla: la
# funcion 'ventana()' de lib-comun.sh, que hoy habla 'dialog'. Este fichero es el
# otro lado de esa misma frontera: mismo contrato, otra biblioteca de dibujo. Por
# eso aqui NO hay logica de instalacion: no se particiona, no se descarga y no se
# escribe nada en el disco. Solo se pinta una ventana y se devuelve lo que el
# usuario ha elegido, exactamente igual que lo devuelve 'dialog'.
#
# EL CONTRATO, que es el de 'dialog' porque el motor esta escrito contra el:
#
#   - La RESPUESTA va a la SALIDA DE ERROR y el codigo de salida dice si el
#     usuario la acepto. El motor la lee asi:
#         valor="$(ventana ... 3>&1 1>&2 2>&3)"
#     o sea, lo que el usuario elige sale por el descriptor 3, que es el comando
#     sustitucion. Si esta respuesta se escribiera por la salida estandar se
#     comeria el texto que el motor pinta en pantalla, y el motor leeria una
#     respuesta vacia sin avisar.
#   - Codigo 0 = aceptado. Codigo 1 = cancelado (Esc o el boton de cancelar), y
#     el motor se queda con el valor por defecto, que no es un fallo. Codigo 2 =
#     ESTA VENTANA NO SE HA PODIDO ABRIR, que es lo unico que devuelve el motor y
#     lo unico que 'ventana()' traduce en una caida al modo de texto.
#   - '--menu' devuelve la ETIQUETA de la opcion elegida, no su texto: el motor
#     busca por etiqueta ('gnome', 'uso_oficina'...) y nunca por lo que se lee.
#   - '--checklist' devuelve SOLO las etiquetas marcadas, y con
#     '--separate-output' una por linea.
#   - '--yesno' y '--msgbox' no devuelven nada: se responden con el codigo.
#
# Y un detalle de 'dialog' que el motor EXPLOTA y que hay que respetar: en
# cuanto aparece el tipo de ventana, 'dialog' deja de leer opciones, y todo lo
# que se pone despues se pierde en silencio. Por eso aqui tambien se deja de
# leer. No es un capricho: es lo que hace que una diferencia entre este frontal y
# 'dialog' se vea como un sintoma raro, y no como un instalador que hace otra
# cosa sin avisar.
#
# Las funciones de arriba del todo NO importan GTK: son puras, se les puede dar
# una lista de argumentos y devuelven un diccionario. Asi se prueban con datos,
# sin pantalla, que es la unica manera de que la comprobacion del proyecto pueda
# cazar un fallo aqui. La parte de GTK entra mas abajo y se limita a pintar lo
# que el diccionario dice y a devolver lo que el usuario ha hecho.

import os
import re
import sys

# Los codigos de color que pinta el motor (ver lib-comun.sh) y su equivalente en
# Pango. Son los mismos seis: reset, titulo, ok, mal, aviso y gris.
COLORES = {
    "1;36": ('<span foreground="#26a6a1" weight="bold">', "</span>"),
    "1;32": ('<span foreground="#2ec27e" weight="bold">', "</span>"),
    "1;31": ('<span foreground="#e01b24" weight="bold">', "</span>"),
    "1;33": ('<span foreground="#e5a50a" weight="bold">', "</span>"),
    "2": ('<span alpha="60%">', "</span>"),
}

RE_SGR = re.compile(r"\033\[([0-9;]*)m")

# Las seis ventanas que el motor sabe pedir. Si el motor empieza a usar otra,
# esta lista tiene que crecer: es mejor que este programa se pare y lo diga que
# no abrir una ventana vacia y devolver un codigo cualquiera.
TIPOS = ("menu", "checklist", "yesno", "msgbox", "inputbox", "passwordbox")

# Las opciones que se pueden poner ANTES del tipo de ventana.
OPCIONES_CON_VALOR = ("--title", "--backtitle", "--default-item")
OPCIONES_SIN_VALOR = ("--defaultno", "--separate-output")
# Se aceptan y se ignoran, porque 'dialog' las tiene y el motor podria usarlas.
# '--exit-code' y las de etiqueta llevan valor; el resto, no.
OPCIONES_IGNORADAS_CON_VALOR = ("--yes-label", "--no-label", "--ok-label",
                                "--cancel-label", "--exit-code")
OPCIONES_IGNORADAS_SIN_VALOR = ("--insecure", "--no-collapse", "--cr-wrap",
                                "--scrollbar", "--autospace", "--inputfile")


def escapa(texto):
    """Lo de Pango: '<' empieza una etiqueta y '&' empieza una entidad."""
    return texto.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def a_markup(texto):
    """Convierte los codigos de color del motor en etiquetas de Pango.

    El motor pinta con '\\033[1;36m' y compania, porque en la consola eso es un
    color. En una etiqueta de GTK no lo es: es un caracter invisible, y sale en
    pantalla un '[1;36m' en mitad del texto. Ademas '&' y '<' hay que
    esconderlos o Pango se come el texto o da error.
    """
    limpio = escapa(texto)
    salida = []
    abierto = False
    pos = 0
    for salto in RE_SGR.finditer(limpio):
        salida.append(limpio[pos:salto.start()])
        pos = salto.end()
        if abierto:
            salida.append("</span>")
            abierto = False
        codigo = salto.group(1)
        if codigo in COLORES:
            salida.append(COLORES[codigo][0])
            abierto = True
    salida.append(limpio[pos:])
    if abierto:
        salida.append("</span>")
    return "".join(salida)


def partes_de(tipo, resto):
    """Parte lo que viene detras del tipo de ventana.

    Devuelve (texto, alto, ancho, items, inicial), donde 'items' es una lista de
    (etiqueta, texto) en los menus y de (etiqueta, texto, marcado) en los
    checklists. Se separa del 'parse_argsv' para poder probarla con las tres
    formas que hay: con cuenta inicial, con cuenta por defecto y sin cuenta.
    """
    if not resto:
        raise ValueError("falta el texto de la ventana '%s'" % tipo)
    texto = resto[0]
    numeros = []
    pos = 1
    while pos < len(resto) and len(numeros) < 3:
        if not re.match(r"^[0-9]+$", str(resto[pos])):
            break
        numeros.append(int(resto[pos]))
        pos += 1
    alto = numeros[0] if len(numeros) > 0 else 0
    ancho = numeros[1] if len(numeros) > 1 else 0
    cuenta = numeros[2] if len(numeros) > 2 else None
    cuerpo = resto[pos:]
    items = []
    if tipo == "menu":
        if cuenta is not None and cuenta != len(cuerpo) // 2:
            raise ValueError("la cuenta del menu (%s) no cuadra con sus %d pares"
                             % (cuenta, len(cuerpo) // 2))
        if len(cuerpo) % 2 != 0:
            raise ValueError("opciones impares en un menu: sobra un valor")
        for i in range(0, len(cuerpo), 2):
            items.append((cuerpo[i], cuerpo[i + 1]))
    elif tipo == "checklist":
        if cuenta is not None and cuenta != len(cuerpo) // 3:
            raise ValueError("la cuenta del checklist (%s) no cuadra con sus %d"
                             % (cuenta, len(cuerpo) // 3))
        if len(cuerpo) % 3 != 0:
            raise ValueError("opciones triples incompletas en un checklist")
        for i in range(0, len(cuerpo), 3):
            items.append((cuerpo[i], cuerpo[i + 1], cuerpo[i + 2]))
    elif tipo in ("inputbox", "passwordbox") and len(cuerpo) > 1:
        raise ValueError("sobran valores despues del texto de '%s'" % tipo)
    return texto, alto, ancho, items, (cuerpo[0] if cuerpo else "")


def parse_argsv(argv):
    """Convierte la lista de argumentos de 'dialog' en un diccionario.

    No mira la pantalla y no depende de GTK: con la misma lista sale SIEMPRE el
    mismo diccionario, y eso es lo que permite comprobarlo con datos.
    """
    desc = {"tipo": None, "titulo": "", "subtitulo": "", "texto": "",
            "items": [], "defecto": "", "por_defecto_no": False,
            "separado": False, "inicial": "", "alto": 0, "ancho": 0}
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in OPCIONES_CON_VALOR:
            if i + 1 >= len(argv):
                raise ValueError("falta el valor de '%s'" % arg)
            valor = argv[i + 1]
            if arg == "--title":
                desc["titulo"] = valor
            elif arg == "--backtitle":
                desc["subtitulo"] = valor
            else:
                desc["defecto"] = valor
            i += 2
            continue
        if arg in OPCIONES_SIN_VALOR:
            if arg == "--defaultno":
                desc["por_defecto_no"] = True
            else:
                desc["separado"] = True
            i += 1
            continue
        if arg in OPCIONES_IGNORADAS_CON_VALOR:
            i += 2
            continue
        if arg in OPCIONES_IGNORADAS_SIN_VALOR:
            i += 1
            continue
        # El tipo de ventana empieza por guion ('--menu'), asi que se mira
        # ANTES de rechazar las opciones desconocidas. A partir de aqui ya no
        # se leen opciones, que es lo que hace 'dialog'.
        if arg.startswith("--") and arg.lstrip("-") in TIPOS:
            tipo_ventana = arg.lstrip("-")
            if desc["tipo"] is not None:
                raise ValueError("dos ventanas en una llamada: '%s' y '%s'"
                                 % (desc["tipo"], tipo_ventana))
            desc["tipo"] = tipo_ventana
            (desc["texto"], desc["alto"], desc["ancho"], desc["items"],
             desc["inicial"]) = partes_de(tipo_ventana, argv[i + 1:])
            return desc
        if arg.startswith("-"):
            raise ValueError("opcion desconocida: '%s'" % arg)
        raise ValueError("tipo de ventana desconocido: '%s'" % arg)
    raise ValueError("no hay ninguna ventana que abrir")


def salida_de(desc, eleccion=None, marcadas=None, acepta=True, texto=""):
    """Lo que el motor se va a encontrar: (codigo, lo que va por stderr).

    Es la otra mitad del contrato, y la que mas fallos da si se cambia sin
    querer: 'eleccion' es la ETIQUETA del menu y no su texto; 'marcadas' son las
    etiquetas marcadas del checklist y solo esas; y cancelar NO escribe nada,
    porque el motor se queda con el valor por defecto cuando el codigo no es
    cero.
    """
    if not acepta:
        return 1, ""
    tipo = desc["tipo"]
    if tipo == "menu":
        etiquetas = [t for (t, _txt) in desc["items"]]
        if eleccion not in etiquetas:
            raise ValueError("la opcion elegida no existe en la ventana: %r"
                             % (eleccion,))
        return 0, eleccion
    if tipo == "checklist":
        validas = [t for (t, _txt, _es) in desc["items"]]
        elegidas = marcadas if marcadas is not None else []
        for etiqueta in elegidas:
            if etiqueta not in validas:
                raise ValueError("se ha marcado algo que no esta en la ventana:"
                                 " %r" % (etiqueta,))
        return 0, ("\n".join(elegidas) if desc["separado"]
                   else " ".join(elegidas))
    if tipo in ("inputbox", "passwordbox"):
        return 0, texto
    return 0, ""


def item_por_defecto(desc):
    """La fila que sale marcada al abrir la ventana, o la primera si no hay.

    'dialog' abre con la primera opcion marcada y con '--default-item' abre con
    esa. El motor lo usa para el escritorio y para el tipo de uso, asi que si
    esto devuelve otra cosa el instalador instala el escritorio equivocado y no
    hay ningun aviso en ninguna parte.
    """
    if not desc["items"]:
        return 0
    if desc["defecto"]:
        for indice, (etiqueta, _resto) in enumerate(desc["items"]):
            if etiqueta == desc["defecto"]:
                return indice
    return 0


# ----------------------------------------------------------------- la ventana --

# El gancho de las pruebas automaticas. Una ventana hay que VERLA y hay que
# CLICARLA, y un comprobador que solo sabe mirar codigo no puede hacer ni lo uno
# ni lo otro. Con 'TITAN_GUI_PRUEBA' la ventana se pinta de verdad y se cierra
# sola en el primer aviso del bucle de eventos, contestando como si el usuario
# hubiera pulsado: asi el programa entero (pintar, recoger y escribir la
# respuesta) se puede comprobar en un equipo sin pantalla y sin raton.
PRUEBAS = ("aceptar", "cancelar")


def mostrar(desc):
    """Pinta la ventana y devuelve (codigo, respuesta)."""
    import gi
    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, Gdk, Gio, GLib, Gtk

    # Que GTK pueda abrir una pantalla se comprueba ANTES de construir nada.
    # Sin esta comprobacion el error sale mas tarde, dentro del manejador de
    # 'activate', y ahi PyGObject se come la excepcion: la ventana no se abre,
    # 'mostrar()' devuelve el estado de partida, y ese estado es codigo 1, que
    # el motor lee como "el usuario ha cancelado". O sea: una pantalla que no
    # arranca haria que el instalador siguiera entero con todos los valores por
    # defecto, en silencio y con codigo de exito. Es el fallo mas caro que
    # puede tener este fichero, y por eso se mira aqui y no al final.
    if not Gtk.init_check():
        raise RuntimeError(
            "GTK no ha podido abrir la pantalla (DISPLAY=%r, WAYLAND_DISPLAY=%r)"
            % (os.environ.get("DISPLAY"), os.environ.get("WAYLAND_DISPLAY")))

    prueba = os.environ.get("TITAN_GUI_PRUEBA", "")
    if prueba and prueba not in PRUEBAS:
        raise ValueError("prueba de ventana desconocida: '%s'" % prueba)
    app = Adw.Application(application_id="org.titanlinux.instalador",
                          flags=Gio.ApplicationFlags.NON_UNIQUE)
    resultado = {"codigo": 1, "texto": ""}
    pintada = []
    tipo = desc["tipo"]

    def construye(ventana):
        cuerpo = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        cuerpo.set_margin_top(12)
        cuerpo.set_margin_bottom(12)
        cuerpo.set_margin_start(18)
        cuerpo.set_margin_end(18)
        arriba = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        arriba.set_vexpand(True)
        cuerpo.append(arriba)
        abajo = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        abajo.set_halign(Gtk.Align.END)
        cuerpo.append(abajo)

        estado = {}

        def acepta(eleccion=None, marcadas=None, texto=""):
            codigo, salida = salida_de(desc, eleccion, marcadas, True, texto)
            resultado["codigo"] = codigo
            resultado["texto"] = salida
            ventana.close()

        def cancela(_w=None):
            resultado["codigo"] = 1
            ventana.close()

        def boton(texto, accion, principal=False, peligro=False):
            b = Gtk.Button(label=texto)
            if principal:
                b.add_css_class("suggested-action")
            if peligro:
                b.add_css_class("destructive-action")
            b.connect("clicked", accion)
            return b

        if desc["texto"].strip():
            vista = Gtk.ScrolledWindow()
            vista.set_vexpand(True)
            etiqueta = Gtk.Label(label=a_markup(desc["texto"]), wrap=True,
                                 xalign=0.0, selectable=True,
                                 justify=Gtk.Justification.LEFT)
            etiqueta.add_css_class("dim-label")
            vista.set_child(etiqueta)
            arriba.append(vista)

        if tipo in ("menu", "checklist"):
            lista = Gtk.ListBox()
            lista.set_selection_mode(Gtk.SelectionMode.SINGLE)
            lista.add_css_class("boxed-list")
            if tipo == "menu":
                for etiqueta_menu, texto in desc["items"]:
                    fila = Adw.ActionRow(title=texto)
                    fila.set_name(etiqueta_menu)
                    fila.set_activatable(True)
                    fila.connect("activated",
                                 lambda _f, e=etiqueta_menu: acepta(e))
                    lista.append(fila)
                lista.select_row(lista.get_row_at_index(item_por_defecto(desc)))
                estado["elegida"] = desc["items"][item_por_defecto(desc)][0]
            else:
                casillas = {}
                for etiqueta_item, texto, marca in desc["items"]:
                    fila = Adw.ActionRow(title=texto)
                    fila.set_name(etiqueta_item)
                    fila.set_activatable(True)
                    casilla = Gtk.CheckButton(active=(marca == "on"))
                    casilla.set_valign(Gtk.Align.CENTER)
                    fila.add_prefix(casilla)
                    fila.connect("activated", lambda _f, c=casilla:
                                 c.set_active(not c.get_active()))
                    lista.append(fila)
                    casillas[etiqueta_item] = casilla
                estado["casillas"] = casillas
            grupo = Adw.PreferencesGroup()
            grupo.set_vexpand(True)
            grupo.add(lista)
            arriba.append(grupo)

            def acepta_lista(_w=None):
                if tipo == "menu":
                    fila = lista.get_selected_row()
                    if fila is None:
                        cancela()
                        return
                    acepta(fila.get_name())
                else:
                    marcadas = [etiqueta for (etiqueta, _t, _m) in desc["items"]
                                if casillas[etiqueta].get_active()]
                    acepta(marcadas=marcadas)

            abajo.append(boton("Cancelar", cancela))
            abajo.append(boton("Continuar", acepta_lista, principal=True))

        elif tipo in ("inputbox", "passwordbox"):
            grupo = Adw.PreferencesGroup()
            if tipo == "inputbox":
                entrada = Adw.EntryRow(text=desc["inicial"])
            else:
                entrada = Adw.PasswordEntryRow(text=desc["inicial"])
            entrada.set_show_apply_button(False)
            grupo.add(entrada)
            arriba.append(grupo)
            abajo.append(boton("Cancelar", cancela))
            abajo.append(boton("Aceptar",
                               lambda _w: acepta(texto=entrada.get_text()),
                               principal=True))
            ventana.set_focus(entrada)
            estado["entrada"] = entrada

        elif tipo == "yesno":
            abajo.append(boton("No", cancela, peligro=desc["por_defecto_no"]))
            abajo.append(boton("Si", lambda _w: acepta(),
                               principal=not desc["por_defecto_no"]))

        else:  # msgbox
            abajo.append(boton("Aceptar", lambda _w: acepta(),
                               principal=True))

        def al_teclar(_control, evento):
            tecla = evento.get_keyval()
            if tecla == Gdk.KEY_Escape:
                cancela()
                return True
            if tecla not in (Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_space):
                return False
            if tipo == "menu":
                fila = lista.get_selected_row()
                if fila is not None:
                    acepta(fila.get_name())
                    return True
            elif tipo == "checklist":
                marcadas = [etiqueta for (etiqueta, _t, _m) in desc["items"]
                            if casillas[etiqueta].get_active()]
                acepta(marcadas=marcadas)
                return True
            elif tipo in ("inputbox", "passwordbox"):
                acepta(texto=entrada.get_text())
                return True
            elif tipo == "msgbox":
                acepta()
                return True
            return False

        controlador = Gtk.EventControllerKey()
        controlador.connect("key-pressed", al_teclar)
        ventana.add_controller(controlador)

        envuelve = Adw.ToolbarView()
        cabecera = Adw.HeaderBar()
        cabecera.set_title_widget(Adw.WindowTitle(title=desc["titulo"],
                                                 subtitle=desc["subtitulo"]))
        envuelve.add_top_bar(cabecera)
        envuelve.set_content(cuerpo)
        ventana.set_content(envuelve)

        if not prueba:
            return
        # Un aviso al bucle de eventos: para cuando se ejecute, la ventana ya
        # esta construida y pintada, y se contesta como si el usuario hubiera
        # pulsado lo de siempre (la fila marcada, las casillas marcadas, el
        # texto de partida, el boton de aceptar). Se devuelve False para que el
        # aviso no se repita.
        def responde():
            if prueba == "cancelar":
                cancela()
            elif tipo == "menu":
                acepta(desc["items"][item_por_defecto(desc)][0])
            elif tipo == "checklist":
                acepta(marcadas=[etiqueta for (etiqueta, _t, _m) in desc["items"]
                                 if casillas[etiqueta].get_active()])
            elif tipo in ("inputbox", "passwordbox"):
                acepta(texto=entrada.get_text())
            else:
                acepta()
            return False

        GLib.idle_add(responde)

    def al_arrancar(aplicacion):
        # Todo lo que pueda fallar al pintar la ventana va aqui dentro. PyGObject
        # no deja subir una excepcion desde un manejador de senal (la imprime y
        # sigue como si nada), asi que sin este 'try' una ventana que no se
        # puede construir se convertiria en un cancelado silencioso.
        try:
            ventana = Adw.ApplicationWindow(application=aplicacion)
            construye(ventana)
            ventana.present()
            pintada.append(True)
        except Exception as error:  # noqa: BLE001 - aqui se atrapa de todo
            resultado["fallo"] = "%s: %s" % (type(error).__name__, error)
            aplicacion.quit()

    app.connect("activate", al_arrancar)
    app.run([])
    if "fallo" in resultado:
        raise RuntimeError("no se ha podido pintar la ventana: %s"
                           % resultado["fallo"])
    if not pintada:
        raise RuntimeError("la ventana nunca se llego a pintar")
    return resultado["codigo"], resultado["texto"]


def main(argv):
    # OJO, donde va cada cosa. El motor lee la RESPUESTA de la salida de error
    # ('valor="$(ventana ... 3>&1 1>&2 2>&3)"') y saca la salida estandar por
    # pantalla. Si un mensaje de error se escribiera por la salida de error, al
    # caer la ventana grafica en el modo de texto el motor leeria ese mensaje
    # como si fuera lo que el usuario habia elegido: se instalaria con el
    # escritorio de la primera linea de la excepcion. Por eso el diagnostico va
    # a la salida estandar, que es donde el motor no lee nada.
    try:
        desc = parse_argsv(argv[1:])
    except ValueError as error:
        sys.stdout.write("ventana-gui: %s\n" % error)
        return 2
    # Y lo mismo con los avisos que escriben GTK y PyGObject, que van por la
    # salida de error sin que nadie les pregunte ('Gtk-CRITICAL',
    # 'assertion GDK_IS_DISPLAY failed'...). Son ruidos de biblioteca y a la
    # ranura de la respuesta no tienen nada que ver: si uno se cuela ahi, el
    # motor lee 'Gtk-CRITICAL' como si fuera lo que el usuario ha elegido. Asi
    # que el descriptor 2 se aparta a un lado, se pone /dev/null en su lugar, y
    # la respuesta se escribe directamente en el descriptor apartado.
    sys.stdout.flush()
    sys.stderr.flush()
    guardado = os.dup(2)
    os.dup2(os.open(os.devnull, os.O_WRONLY), 2)
    codigo, texto = 2, ""
    try:
        codigo, texto = mostrar(desc)
    except Exception as error:  # el motor solo necesita un codigo, no un traceback
        sys.stdout.write("ventana-gui: %s\n" % error)
        return 2
    if texto:
        os.write(guardado, (texto + "\n").encode("utf-8", "replace"))
    return codigo


if __name__ == "__main__":
    sys.exit(main(sys.argv))
