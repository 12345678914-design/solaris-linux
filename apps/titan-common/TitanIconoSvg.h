#ifndef TITAN_ICONO_SVG_H
#define TITAN_ICONO_SVG_H

// Iconos de respaldo generados en SVG.
//
// Cuando una app no trae icono (Icon= vacio, nombre que no existe en ningun
// tema, ruta absoluta a un fichero que no esta), en vez de una imagen vacia o
// el mismo engranaje para todo, se dibuja un icono propio con el estilo de
// Inti OS: squircle con degradado del color de su categoria y un simbolo
// (terminal, ajustes, musica, web...) o sus iniciales si no encaja en
// ninguna. Se guarda en ~/.cache/titan/iconos y se reutiliza.
//
// Uso:
//   QString url = titan::iconoGenerado(nombreVisible, exec + " " + iconName);
//   if (!titan::iconoExiste(url)) url = titan::iconoGenerado(...);

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSaveFile>
#include <QString>
#include <QStringList>
#include <QUrl>

namespace titan {

struct CategoriaIcono {
    const char *nombre;
    const char *palabras;   // separadas por '|', se buscan en minusculas
    const char *color1;
    const char *color2;
    const char *simbolo;    // SVG en un lienzo de 1024, blanco
};

// Simbolos: trazos blancos de 56-64 px sobre 1024, centrados.
inline const CategoriaIcono *categoriasIcono(int *n)
{
    static const CategoriaIcono cats[] = {
        {"terminal", "terminal|console|consola|shell|kitty|alacritty|foot|konsole|xterm|tty",
         "#3a3a3c", "#1c1c1e",
         "<path d='M300 380 L450 512 L300 644' fill='none' stroke='#30d158' stroke-width='64' stroke-linecap='round' stroke-linejoin='round'/>"
         "<path d='M500 660 H720' stroke='#ffffff' stroke-width='64' stroke-linecap='round'/>"},
        {"ajustes", "setting|ajuste|config|control|preferenc|tweak|panel de",
         "#8e8e93", "#48484a",
         "<g fill='#ffffff'>"
         "<rect x='472' y='236' width='80' height='120' rx='24'/><rect x='472' y='236' width='80' height='120' rx='24' transform='rotate(45 512 512)'/>"
         "<rect x='472' y='236' width='80' height='120' rx='24' transform='rotate(90 512 512)'/><rect x='472' y='236' width='80' height='120' rx='24' transform='rotate(135 512 512)'/>"
         "<rect x='472' y='236' width='80' height='120' rx='24' transform='rotate(180 512 512)'/><rect x='472' y='236' width='80' height='120' rx='24' transform='rotate(225 512 512)'/>"
         "<rect x='472' y='236' width='80' height='120' rx='24' transform='rotate(270 512 512)'/><rect x='472' y='236' width='80' height='120' rx='24' transform='rotate(315 512 512)'/>"
         "<circle cx='512' cy='512' r='200'/></g><circle cx='512' cy='512' r='86' fill='#636366'/>"},
        {"musica", "music|musica|música|audio|spotify|rhythmbox|player|sound|sonido|podcast|radio",
         "#ff6482", "#e0204a",
         "<path d='M440 300 L700 250 V620' fill='none' stroke='#ffffff' stroke-width='60' stroke-linejoin='round'/>"
         "<path d='M440 300 V680' stroke='#ffffff' stroke-width='60'/>"
         "<ellipse cx='370' cy='690' rx='96' ry='76' fill='#ffffff'/><ellipse cx='630' cy='630' rx='96' ry='76' fill='#ffffff'/>"},
        {"video", "video|vídeo|movie|pelicula|película|mpv|vlc|film|celluloid|stream|obs-studio",
         "#ffb340", "#ff6b00",
         "<path d='M420 340 L700 512 L420 684 Z' fill='#ffffff' stroke='#ffffff' stroke-width='40' stroke-linejoin='round'/>"},
        {"imagen", "image|imagen|photo|foto|gimp|krita|inkscape|paint|draw|dibujo|picture|darktable|camera",
         "#4cd964", "#0a9d3c",
         "<rect x='250' y='300' width='524' height='424' rx='56' fill='none' stroke='#ffffff' stroke-width='52'/>"
         "<path d='M290 680 L450 500 L560 610 L640 530 L740 640' fill='none' stroke='#ffffff' stroke-width='52' stroke-linejoin='round' stroke-linecap='round'/>"
         "<circle cx='630' cy='410' r='52' fill='#ffffff'/>"},
        {"web", "browser|navegador|web|firefox|chrom|brave|vivaldi|opera|internet|epiphany",
         "#4aa8ff", "#0040dd",
         "<circle cx='512' cy='512' r='250' fill='none' stroke='#ffffff' stroke-width='48'/>"
         "<ellipse cx='512' cy='512' rx='110' ry='250' fill='none' stroke='#ffffff' stroke-width='40'/>"
         "<path d='M270 440 H754 M270 584 H754' stroke='#ffffff' stroke-width='40'/>"},
        {"codigo", "code|código|codigo|develop|idea|studio|git|python|java|rust|program|sublime|kate|neovim|vim|emacs",
         "#7d7aff", "#3634a3",
         "<path d='M400 350 L250 512 L400 674 M624 350 L774 512 L624 674' fill='none' stroke='#ffffff' stroke-width='60' stroke-linecap='round' stroke-linejoin='round'/>"
         "<path d='M560 300 L464 724' stroke='#ffffff' stroke-width='52' stroke-linecap='round'/>"},
        {"juego", "game|juego|steam|lutris|heroic|retroarch|emulat|minecraft|playonlinux",
         "#da8fff", "#8944ab",
         "<path d='M330 380 H694 C800 380 840 520 820 620 C800 700 730 700 690 640 L650 590 H374 L334 640 C294 700 224 700 204 620 C184 520 224 380 330 380 Z' fill='#ffffff'/>"
         "<path d='M360 470 V560 M315 515 H405' stroke='#8944ab' stroke-width='36' stroke-linecap='round'/>"
         "<circle cx='640' cy='480' r='26' fill='#8944ab'/><circle cx='700' cy='540' r='26' fill='#8944ab'/>"},
        {"correo", "mail|correo|thunderbird|evolution|geary",
         "#70d7ff", "#0a84ff",
         "<rect x='240' y='320' width='544' height='384' rx='48' fill='#ffffff'/>"
         "<path d='M270 350 L512 540 L754 350' fill='none' stroke='#0a84ff' stroke-width='44' stroke-linejoin='round'/>"},
        {"chat", "chat|discord|telegram|signal|message|mensaje|slack|whatsapp|element|irc",
         "#5de07a", "#1f9d45",
         "<path d='M512 270 C680 270 790 370 790 495 C790 620 680 720 512 720 C470 720 430 714 395 702 L270 760 L300 650 C255 610 234 556 234 495 C234 370 344 270 512 270 Z' fill='#ffffff'/>"},
        {"documento", "office|oficina|writer|document|documento|text|texto|notes|notas|word|libre|pdf|okular|evince|reader",
         "#ffd60a", "#ff9500",
         "<path d='M340 240 H590 L700 350 V784 H340 Z' fill='#ffffff'/>"
         "<path d='M410 470 H630 M410 560 H630 M410 650 H560' stroke='#ff9500' stroke-width='40' stroke-linecap='round'/>"},
        {"descargas", "download|descarga|torrent|transmission|qbittorrent|uget",
         "#40e0d0", "#008b8b",
         "<path d='M512 260 V620 M370 480 L512 622 L654 480' fill='none' stroke='#ffffff' stroke-width='60' stroke-linecap='round' stroke-linejoin='round'/>"
         "<path d='M300 740 H724' stroke='#ffffff' stroke-width='60' stroke-linecap='round'/>"},
        {"sistema", "monitor|htop|btop|system|sistema|task|tarea|disk|disco|gparted|hardware|cpu",
         "#5ac8fa", "#1c6ea4",
         "<path d='M300 720 V560 M430 720 V420 M560 720 V500 M690 720 V320' stroke='#ffffff' stroke-width='72' stroke-linecap='round'/>"},
        {"reloj", "clock|reloj|alarm|alarma|timer|temporizador|cronometro|cronómetro",
         "#3a3a3c", "#1c1c1e",
         "<circle cx='512' cy='512' r='260' fill='#ffffff'/>"
         "<path d='M512 340 V512 L630 590' fill='none' stroke='#1c1c1e' stroke-width='44' stroke-linecap='round' stroke-linejoin='round'/>"},
        {"seguridad", "password|contraseña|keyring|clave|candado|vpn|security|seguridad|keepass|bitwarden|firewall",
         "#a2a2a7", "#3a3a3c",
         "<rect x='320' y='470' width='384' height='300' rx='48' fill='#ffffff'/>"
         "<path d='M400 480 V390 C400 250 624 250 624 390 V480' fill='none' stroke='#ffffff' stroke-width='56'/>"
         "<circle cx='512' cy='600' r='40' fill='#3a3a3c'/>"},
        {"archivos", "file|archivo|folder|carpeta|manager|explorer|nautilus|dolphin|thunar|nemo",
         "#5ac8fa", "#0a84ff",
         "<path d='M240 330 C240 300 260 280 290 280 H440 L500 340 H734 C764 340 784 360 784 390 V700 C784 730 764 750 734 750 H290 C260 750 240 730 240 700 Z' fill='#ffffff'/>"},
    };
    *n = int(sizeof(cats) / sizeof(cats[0]));
    return cats;
}

// true si la URL (file:// o ruta) apunta a un fichero que existe y no esta
// vacio. Las qrc:/ se dan por buenas (las comprueba la auditoria de iconos).
inline bool iconoExiste(const QString &urlORuta)
{
    if (urlORuta.isEmpty())
        return false;
    if (urlORuta.startsWith(QLatin1String("qrc:/")) || urlORuta.startsWith(QLatin1String("image://")))
        return true;
    const QString ruta = urlORuta.startsWith(QLatin1String("file:")) ? QUrl(urlORuta).toLocalFile() : urlORuta;
    QFileInfo fi(ruta);
    return fi.isFile() && fi.size() > 0;
}

inline QString iniciales(const QString &nombre)
{
    QString limpio = nombre;
    limpio.replace(QRegularExpression(QStringLiteral("[^\\p{L}\\p{N} ]")), QStringLiteral(" "));
    const QStringList partes = limpio.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    QString r;
    if (partes.size() >= 2)
        r = partes[0].left(1) + partes[1].left(1);
    else if (!partes.isEmpty())
        r = partes[0].left(2);
    if (r.isEmpty())
        r = QStringLiteral("?");
    return r.size() > 1 ? r.left(1).toUpper() + r.mid(1, 1).toLower() : r.toUpper();
}

inline QString escaparXml(QString s)
{
    s.replace(QLatin1Char('&'), QStringLiteral("&amp;"));
    s.replace(QLatin1Char('<'), QStringLiteral("&lt;"));
    s.replace(QLatin1Char('>'), QStringLiteral("&gt;"));
    s.replace(QLatin1Char('\''), QStringLiteral("&apos;"));
    s.replace(QLatin1Char('"'), QStringLiteral("&quot;"));
    return s;
}

// Devuelve el SVG del icono para una app (sin escribirlo).
inline QString svgIcono(const QString &nombre, const QString &pistas)
{
    const QString texto = (nombre + QLatin1Char(' ') + pistas).toLower();
    int n = 0;
    const CategoriaIcono *cats = categoriasIcono(&n);
    const CategoriaIcono *cat = nullptr;
    for (int i = 0; i < n && !cat; ++i) {
        const QStringList palabras = QString::fromUtf8(cats[i].palabras).split(QLatin1Char('|'));
        for (const QString &p : palabras) {
            if (!p.isEmpty() && texto.contains(p)) {
                cat = &cats[i];
                break;
            }
        }
    }

    QString c1, c2, simbolo;
    if (cat) {
        c1 = QString::fromLatin1(cat->color1);
        c2 = QString::fromLatin1(cat->color2);
        simbolo = QString::fromUtf8(cat->simbolo);
    } else {
        // Sin categoria: iniciales sobre un color estable para ese nombre.
        static const char *const paleta[][2] = {
            {"#4aa8ff", "#0040dd"}, {"#5de07a", "#1f9d45"}, {"#ffb340", "#ff6b00"},
            {"#da8fff", "#8944ab"}, {"#ff6482", "#e0204a"}, {"#70d7ff", "#0a84ff"},
            {"#ffd60a", "#ff9500"}, {"#7d7aff", "#3634a3"},
        };
        const QByteArray h = QCryptographicHash::hash(nombre.toUtf8(), QCryptographicHash::Md5);
        const int idx = static_cast<unsigned char>(h.at(0)) % 8;
        c1 = QString::fromLatin1(paleta[idx][0]);
        c2 = QString::fromLatin1(paleta[idx][1]);
        const QString ini = escaparXml(iniciales(nombre));
        simbolo = QStringLiteral("<text x='512' y='512' dy='0.35em' text-anchor='middle' "
                                 "font-family='Inter, DejaVu Sans, sans-serif' font-weight='700' "
                                 "font-size='%1' fill='#ffffff'>%2</text>")
                      .arg(ini.size() > 1 ? 380 : 460)
                      .arg(ini);
    }

    return QStringLiteral(
               "<svg xmlns='http://www.w3.org/2000/svg' width='1024' height='1024' viewBox='0 0 1024 1024'>"
               "<defs><linearGradient id='f' x1='0' y1='0' x2='0' y2='1'>"
               "<stop offset='0' stop-color='%1'/><stop offset='1' stop-color='%2'/></linearGradient>"
               "<linearGradient id='b' x1='0' y1='0' x2='0' y2='1'>"
               "<stop offset='0' stop-color='#ffffff' stop-opacity='0.35'/>"
               "<stop offset='1' stop-color='#ffffff' stop-opacity='0'/></linearGradient></defs>"
               "<rect x='64' y='64' width='896' height='896' rx='200' fill='url(#f)'/>"
               "<rect x='64' y='64' width='896' height='448' rx='200' fill='url(#b)' opacity='0.5'/>"
               "<rect x='66' y='66' width='892' height='892' rx='198' fill='none' stroke='#ffffff' stroke-opacity='0.25' stroke-width='4'/>"
               "%3</svg>\n")
        .arg(c1, c2, simbolo);
}

// Escribe (si hace falta) y devuelve la URL file:// del icono generado.
inline QString iconoGenerado(const QString &nombre, const QString &pistas = QString())
{
    QString base = qEnvironmentVariable("XDG_CACHE_HOME");
    if (base.isEmpty())
        base = QDir::homePath() + QStringLiteral("/.cache");
    const QString dir = base + QStringLiteral("/titan/iconos");
    QDir().mkpath(dir);

    const QString clave = QString::fromLatin1(
        QCryptographicHash::hash((nombre + QLatin1Char('\n') + pistas).toUtf8(), QCryptographicHash::Sha1).toHex().left(16));
    QString legible = nombre.toLower();
    legible.replace(QRegularExpression(QStringLiteral("[^a-z0-9]+")), QStringLiteral("-"));
    const QString ruta = dir + QLatin1Char('/') + legible.left(32) + QLatin1Char('-') + clave + QStringLiteral("-v1.svg");

    if (!QFile::exists(ruta)) {
        QSaveFile f(ruta);
        if (f.open(QIODevice::WriteOnly)) {
            f.write(svgIcono(nombre, pistas).toUtf8());
            f.commit();
        }
    }
    return QFile::exists(ruta) ? QUrl::fromLocalFile(ruta).toString()
                               : QStringLiteral("qrc:/icons/apps-folder.png");
}

} // namespace titan

#endif
