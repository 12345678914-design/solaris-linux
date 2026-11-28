// Inti OS - notificaciones en la pantalla de bloqueo segura (modulo de gtklock 5).
//
// titan-shell escribe los avisos en $XDG_RUNTIME_DIR/titan-avisos-bloqueo
// (formato GKeyFile, solo los que permite Ajustes > Notificaciones > En la
// pantalla de bloqueo). Este modulo los pinta debajo del reloj y de la musica
// (playerctl-module), como Android: tarjetas con icono, app, hora, titulo y
// texto. Si llegan hasta la foto del perfil, las que no caben se acoplan en
// una fila de iconos.
//
// El fichero esta en la carpeta de ejecucion del usuario (solo el puede
// leerla y se borra al cerrar su sesion): al cambiar de usuario nadie ve estos
// avisos. Se vigila: si llega un aviso con la pantalla bloqueada, aparece.
//
// Uso: gtklock --modules /usr/lib/gtklock/titan-avisos-module.so
// Estilo: ids #titan-avisos, #titan-aviso, #titan-avisos-repisa (estilo.css).

#include <gio/gio.h>

#include "gtklock-module.h"

const gchar module_name[] = "titan-avisos";
const guint module_major_version = 5;
const guint module_minor_version = 0;

#define ALTO_TARJETA 66
#define HUECO 8
#define ALTO_REPISA 44
#define MARGEN_ARRIBA 22
#define MARGEN_PERFIL 24
#define MAX_ICONOS 8

struct aviso {
	char *app, *titulo, *texto, *icono, *hora;
};

struct datos {
	GtkWidget *rollo; // contenedor de alto minimo 0 (ver on_window_create)
	GtkWidget *caja;
	int mostradas;   // tarjetas enteras que se ven; -1 = sin construir
	guint pendiente; // reconstruccion en espera (g_idle)
};

static int self_id;
static struct GtkLock *bloqueo;
static GFileMonitor *vigia;
static GPtrArray *avisos;
static gboolean oculto;

#define DATOS(w) ((struct datos *)(w)->module_data[self_id])

static void aviso_libre(gpointer p) {
	struct aviso *a = p;
	g_free(a->app);
	g_free(a->titulo);
	g_free(a->texto);
	g_free(a->icono);
	g_free(a->hora);
	g_free(a);
}

static char *ruta_avisos(void) {
	return g_build_filename(g_get_user_runtime_dir(), "titan-avisos-bloqueo", NULL);
}

static void leer_avisos(void) {
	if(avisos) g_ptr_array_free(avisos, TRUE);
	avisos = g_ptr_array_new_with_free_func(aviso_libre);

	char *ruta = ruta_avisos();
	GKeyFile *kf = g_key_file_new();
	if(g_key_file_load_from_file(kf, ruta, G_KEY_FILE_NONE, NULL)) {
		gsize n = 0;
		gchar **grupos = g_key_file_get_groups(kf, &n);
		for(gsize i = 0; i < n; i++) {
			struct aviso *a = g_new0(struct aviso, 1);
			a->app = g_key_file_get_string(kf, grupos[i], "app", NULL);
			a->titulo = g_key_file_get_string(kf, grupos[i], "titulo", NULL);
			a->texto = g_key_file_get_string(kf, grupos[i], "texto", NULL);
			a->icono = g_key_file_get_string(kf, grupos[i], "icono", NULL);
			a->hora = g_key_file_get_string(kf, grupos[i], "hora", NULL);
			if(!a->app) a->app = g_strdup("Sistema");
			if(!a->titulo) a->titulo = g_strdup("");
			if(!a->texto) a->texto = g_strdup("");
			if(!a->hora) a->hora = g_strdup("");
			g_ptr_array_add(avisos, a);
		}
		g_strfreev(grupos);
	}
	g_key_file_free(kf);
	g_free(ruta);
}

static GtkWidget *icono_app(const char *ruta, int tam) {
	if(ruta && *ruta) {
		GdkPixbuf *pb = gdk_pixbuf_new_from_file_at_scale(ruta, tam, tam, TRUE, NULL);
		if(pb) {
			GtkWidget *img = gtk_image_new_from_pixbuf(pb);
			g_object_unref(pb);
			return img;
		}
	}
	// Sin icono propio (o el del shell, que esta dentro de su binario)
	static const char *nombres[] = { "preferences-system-notifications-symbolic", "dialog-information-symbolic", NULL };
	GIcon *gi = g_themed_icon_new_from_names((char **)nombres, -1);
	GtkWidget *img = gtk_image_new_from_gicon(gi, GTK_ICON_SIZE_DND);
	g_object_unref(gi);
	gtk_image_set_pixel_size(GTK_IMAGE(img), tam);
	return img;
}

static GtkWidget *etiqueta(const char *texto, const char *nombre, gboolean expandir) {
	GtkWidget *l = gtk_label_new(texto);
	gtk_widget_set_name(l, nombre);
	gtk_label_set_xalign(GTK_LABEL(l), 0.0);
	gtk_label_set_ellipsize(GTK_LABEL(l), PANGO_ELLIPSIZE_END);
	gtk_label_set_single_line_mode(GTK_LABEL(l), TRUE);
	gtk_label_set_max_width_chars(GTK_LABEL(l), 40);
	gtk_widget_set_hexpand(l, expandir);
	return l;
}

static GtkWidget *tarjeta(struct aviso *a) {
	GtkWidget *t = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
	gtk_widget_set_name(t, "titan-aviso");
	gtk_widget_set_size_request(t, 380, ALTO_TARJETA);
	gtk_widget_set_valign(t, GTK_ALIGN_START);

	GtkWidget *img = icono_app(a->icono, 32);
	gtk_widget_set_valign(img, GTK_ALIGN_CENTER);
	gtk_container_add(GTK_CONTAINER(t), img);

	GtkWidget *col = gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
	gtk_widget_set_valign(col, GTK_ALIGN_CENTER);
	gtk_widget_set_hexpand(col, TRUE);
	gtk_container_add(GTK_CONTAINER(t), col);

	GtkWidget *arriba = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
	gtk_container_add(GTK_CONTAINER(arriba), etiqueta(a->app, "titan-aviso-app", TRUE));
	gtk_container_add(GTK_CONTAINER(arriba), etiqueta(a->hora, "titan-aviso-hora", FALSE));
	gtk_container_add(GTK_CONTAINER(col), arriba);
	gtk_container_add(GTK_CONTAINER(col), etiqueta(a->titulo, "titan-aviso-titulo", TRUE));
	if(*a->texto) gtk_container_add(GTK_CONTAINER(col), etiqueta(a->texto, "titan-aviso-texto", TRUE));
	return t;
}

// Fila de iconos con las que no caben: uno por app y cuantas son.
static GtkWidget *repisa(guint desde) {
	GtkWidget *r = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
	gtk_widget_set_name(r, "titan-avisos-repisa");
	gtk_widget_set_halign(r, GTK_ALIGN_CENTER);
	gtk_widget_set_size_request(r, -1, ALTO_REPISA);

	GPtrArray *apps = g_ptr_array_new();
	GArray *cuentas = g_array_new(FALSE, TRUE, sizeof(int));
	for(guint i = desde; i < avisos->len; i++) {
		struct aviso *a = g_ptr_array_index(avisos, i);
		guint j = 0;
		for(; j < apps->len; j++)
			if(g_strcmp0(((struct aviso *)g_ptr_array_index(apps, j))->app, a->app) == 0) break;
		if(j == apps->len) {
			g_ptr_array_add(apps, a);
			int uno = 1;
			g_array_append_val(cuentas, uno);
		} else g_array_index(cuentas, int, j)++;
	}

	for(guint j = 0; j < apps->len && j < MAX_ICONOS; j++) {
		struct aviso *a = g_ptr_array_index(apps, j);
		GtkWidget *sobre = gtk_overlay_new();
		gtk_widget_set_valign(sobre, GTK_ALIGN_CENTER);
		gtk_widget_set_tooltip_text(sobre, a->app);
		gtk_container_add(GTK_CONTAINER(sobre), icono_app(a->icono, 26));
		int n = g_array_index(cuentas, int, j);
		if(n > 1) {
			char num[16];
			g_snprintf(num, sizeof num, "%d", n);
			GtkWidget *l = gtk_label_new(num);
			gtk_widget_set_name(l, "titan-avisos-cuenta");
			gtk_widget_set_halign(l, GTK_ALIGN_END);
			gtk_widget_set_valign(l, GTK_ALIGN_END);
			gtk_overlay_add_overlay(GTK_OVERLAY(sobre), l);
		}
		gtk_container_add(GTK_CONTAINER(r), sobre);
	}
	if(apps->len > MAX_ICONOS) {
		char mas[16];
		g_snprintf(mas, sizeof mas, "+%u", apps->len - MAX_ICONOS);
		gtk_container_add(GTK_CONTAINER(r), gtk_label_new(mas));
	}
	g_ptr_array_free(apps, TRUE);
	g_array_free(cuentas, TRUE);
	return r;
}

// Cuantas tarjetas enteras caben entre el reloj (con la musica) y el perfil.
static int caben(struct Window *w) {
	GtkAllocation reloj, perfil;
	gtk_widget_get_allocation(w->time_box, &reloj);
	gtk_widget_get_allocation(w->info_box, &perfil);
	int total = (int)avisos->len;
	if(perfil.height <= 1) return 0; // aun sin colocar: se rehace al colocarse
	int libre = perfil.y - (reloj.y + reloj.height) - MARGEN_ARRIBA - MARGEN_PERFIL;
	if(total * (ALTO_TARJETA + HUECO) <= libre) return total;
	int n = (libre - ALTO_REPISA) / (ALTO_TARJETA + HUECO);
	return CLAMP(n, 0, total);
}

static void construir(struct Window *w) {
	struct datos *d = DATOS(w);
	if(!d) return;
	GList *hijos = gtk_container_get_children(GTK_CONTAINER(d->caja));
	for(GList *h = hijos; h; h = h->next) gtk_widget_destroy(GTK_WIDGET(h->data));
	g_list_free(hijos);

	int n = caben(w);
	for(int i = 0; i < n; i++)
		gtk_container_add(GTK_CONTAINER(d->caja), tarjeta(g_ptr_array_index(avisos, i)));
	if(n < (int)avisos->len) gtk_container_add(GTK_CONTAINER(d->caja), repisa(n));
	d->mostradas = n;
	// El rollo es no_show_all (gtklock hace show_all de la ventana y no debe
	// ensenarlo vacio): show_all no entra en el, se muestra su contenido.
	gtk_widget_show_all(gtk_bin_get_child(GTK_BIN(d->rollo)));
	gtk_widget_set_visible(d->rollo, avisos->len > 0 && !oculto);
}

static gboolean construir_luego(gpointer p) {
	struct Window *w = p;
	DATOS(w)->pendiente = 0;
	construir(w);
	return G_SOURCE_REMOVE;
}

// La musica (playerctl-module, position=under-clock) se pone en info-box,
// que en el diseno de Inti OS esta abajo con el perfil. Como en Android va
// debajo del reloj y encima de las notificaciones: se pasa a time-box.
static gboolean mover_musica(struct Window *w) {
	GtkWidget *musica = NULL;
	GList *hijos = gtk_container_get_children(GTK_CONTAINER(w->info_box));
	for(GList *h = hijos; h; h = h->next)
		if(g_strcmp0(gtk_widget_get_name(GTK_WIDGET(h->data)), "playerctl-revealer") == 0) musica = h->data;
	g_list_free(hijos);
	if(!musica) return FALSE;
	g_object_ref(musica);
	gtk_container_remove(GTK_CONTAINER(w->info_box), musica);
	gtk_container_add(GTK_CONTAINER(w->time_box), musica);
	g_object_unref(musica);
	return TRUE;
}

// Al cambiar el tamano (otra pantalla, la musica aparece...) se recalcula.
static void al_colocar(GtkWidget *widget, GdkRectangle *r, gpointer p) {
	struct Window *w = p;
	struct datos *d = DATOS(w);
	if(!d || d->pendiente || !avisos) return;
	if(mover_musica(w) || caben(w) != d->mostradas) d->pendiente = g_idle_add(construir_luego, w);
}

static void reconstruir_todas(void) {
	if(!bloqueo) return;
	for(guint i = 0; i < bloqueo->windows->len; i++) {
		struct Window *w = g_array_index(bloqueo->windows, struct Window *, i);
		if(DATOS(w)) construir(w);
	}
}

static void fichero_cambiado(GFileMonitor *m, GFile *f, GFile *otro, GFileMonitorEvent ev, gpointer p) {
	if(ev != G_FILE_MONITOR_EVENT_CHANGES_DONE_HINT && ev != G_FILE_MONITOR_EVENT_CREATED &&
	   ev != G_FILE_MONITOR_EVENT_DELETED && ev != G_FILE_MONITOR_EVENT_RENAMED &&
	   ev != G_FILE_MONITOR_EVENT_MOVED_IN)
		return;
	leer_avisos();
	reconstruir_todas();
}

void on_activation(struct GtkLock *gtklock, int id) {
	self_id = id;
	bloqueo = gtklock;
	leer_avisos();

	// QSaveFile escribe aparte y renombra: se vigila la carpeta.
	GFile *dir = g_file_new_for_path(g_get_user_runtime_dir());
	vigia = g_file_monitor_directory(dir, G_FILE_MONITOR_WATCH_MOVES, NULL, NULL);
	g_object_unref(dir);
	if(vigia) g_signal_connect(vigia, "changed", G_CALLBACK(fichero_cambiado), NULL);
}

void on_window_create(struct GtkLock *gtklock, struct Window *w) {
	struct datos *d = g_new0(struct datos, 1);
	d->mostradas = -1;
	w->module_data[self_id] = d;

	// Con ext-session-lock la ventana mide lo que la pantalla: si su contenido
	// pidiera mas alto, el compositor corta la conexion (error de protocolo) y
	// la pantalla se queda con el aviso de fallo. Por eso las tarjetas van en
	// un rollo sin barras de alto minimo 0: como mucho se recortan.
	d->rollo = gtk_scrolled_window_new(NULL, NULL);
	gtk_widget_set_name(d->rollo, "titan-avisos-rollo");
	gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(d->rollo), GTK_POLICY_NEVER, GTK_POLICY_EXTERNAL);
	gtk_scrolled_window_set_propagate_natural_height(GTK_SCROLLED_WINDOW(d->rollo), TRUE);
	gtk_scrolled_window_set_propagate_natural_width(GTK_SCROLLED_WINDOW(d->rollo), TRUE);
	gtk_widget_set_halign(d->rollo, GTK_ALIGN_CENTER);
	gtk_widget_set_valign(d->rollo, GTK_ALIGN_START);
	gtk_widget_set_margin_top(d->rollo, MARGEN_ARRIBA);
	gtk_widget_set_no_show_all(d->rollo, TRUE);

	d->caja = gtk_box_new(GTK_ORIENTATION_VERTICAL, HUECO);
	gtk_widget_set_name(d->caja, "titan-avisos");
	gtk_container_add(GTK_CONTAINER(d->rollo), d->caja);

	gtk_container_add(GTK_CONTAINER(w->window_box), d->rollo);
	// Justo debajo del reloj (y de la musica, que va dentro de time-box)
	gtk_box_reorder_child(GTK_BOX(w->window_box), d->rollo, 1);

	g_signal_connect(w->window_box, "size-allocate", G_CALLBACK(al_colocar), w);
	mover_musica(w);
	construir(w);
}

// playerctl-module rehace su caja al cambiar el foco de pantalla; este modulo
// se carga despues, asi que aqui ya esta hecha y se puede mover.
void on_focus_change(struct GtkLock *gtklock, struct Window *w, struct Window *antes) {
	if(DATOS(w)) {
		mover_musica(w);
		construir(w);
	}
}

void on_window_destroy(struct GtkLock *gtklock, struct Window *w) {
	struct datos *d = DATOS(w);
	if(!d) return;
	g_signal_handlers_disconnect_by_func(w->window_box, al_colocar, w);
	if(d->pendiente) g_source_remove(d->pendiente);
	g_free(d);
	w->module_data[self_id] = NULL;
}

// Con --idle-hide la pantalla se queda solo con la hora: los avisos tambien
// se esconden, como el resto.
void on_idle_hide(struct GtkLock *gtklock) {
	oculto = TRUE;
	reconstruir_todas();
}

void on_idle_show(struct GtkLock *gtklock) {
	oculto = FALSE;
	reconstruir_todas();
}

void g_module_unload(GModule *m) {
	if(vigia) g_object_unref(vigia);
	if(avisos) g_ptr_array_free(avisos, TRUE);
}
