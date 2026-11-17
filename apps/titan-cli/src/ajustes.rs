//! Comandos de escritorio de `titan`: tema, acento, fondo, apps y update.
//!
//! El tema, el acento y el fondo se guardan en `~/.config/titan/theme.conf`
//! (grupo `[Theme]`), el mismo fichero que lee y vigila `ThemeManager` en todas
//! las apps Qt de Inti OS: al escribirlo, el cambio se aplica al momento en el
//! escritorio abierto, sin reiniciar nada.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Colores de acento: los mismos que ofrece Ajustes > Apariencia.
pub const ACENTOS: &[(&str, &str)] = &[
    ("azul", "#0071e3"),
    ("morado", "#af52de"),
    ("rosa", "#ff2d55"),
    ("rojo", "#ff3b30"),
    ("naranja", "#ff9500"),
    ("amarillo", "#ffcc00"),
    ("verde", "#34c759"),
    ("grafito", "#8e8e93"),
];

const FONDOS_SISTEMA: &str = "/usr/share/titan/wallpapers";
const EXT_IMAGEN: &[&str] = &["jpg", "jpeg", "png", "webp"];

fn config_dir() -> Result<PathBuf, String> {
    let home = std::env::var("HOME").map_err(|_| "no está definida la variable HOME".to_string())?;
    Ok(Path::new(&home).join(".config/titan"))
}

fn theme_conf() -> Result<PathBuf, String> {
    Ok(config_dir()?.join("theme.conf"))
}

/// Fichero INI como lista ordenada de grupos -> (clave, valor). Conserva los
/// grupos y claves que no son nuestros para no pisar nada de las apps.
type Ini = Vec<(String, Vec<(String, String)>)>;

fn leer_ini(ruta: &Path) -> Ini {
    let mut ini: Ini = Vec::new();
    let Ok(texto) = fs::read_to_string(ruta) else { return ini };
    let mut actual = String::from("General");
    for linea in texto.lines() {
        let l = linea.trim();
        if l.is_empty() || l.starts_with(';') || l.starts_with('#') {
            continue;
        }
        if l.starts_with('[') && l.ends_with(']') {
            actual = l[1..l.len() - 1].to_string();
            if !ini.iter().any(|(g, _)| *g == actual) {
                ini.push((actual.clone(), Vec::new()));
            }
            continue;
        }
        if let Some((k, v)) = l.split_once('=') {
            if !ini.iter().any(|(g, _)| *g == actual) {
                ini.push((actual.clone(), Vec::new()));
            }
            let grupo = &mut ini.iter_mut().find(|(g, _)| *g == actual).unwrap().1;
            grupo.push((k.trim().to_string(), v.trim().to_string()));
        }
    }
    ini
}

fn escribir_ini(ruta: &Path, ini: &Ini) -> Result<(), String> {
    if let Some(dir) = ruta.parent() {
        fs::create_dir_all(dir).map_err(|e| format!("no se puede crear {}: {e}", dir.display()))?;
    }
    let mut out = String::new();
    for (grupo, claves) in ini {
        out.push_str(&format!("[{grupo}]\n"));
        for (k, v) in claves {
            out.push_str(&format!("{k}={v}\n"));
        }
        out.push('\n');
    }
    // Escritura atómica: las apps vigilan el fichero y no deben leerlo a medias.
    let tmp = ruta.with_extension("conf.tmp");
    fs::write(&tmp, out).map_err(|e| format!("no se puede escribir {}: {e}", tmp.display()))?;
    fs::rename(&tmp, ruta).map_err(|e| format!("no se puede guardar {}: {e}", ruta.display()))
}

/// Valor tal como lo devuelve QSettings: sin las comillas que pone Qt.
fn sin_comillas(v: &str) -> String {
    let v = v.trim();
    if v.len() >= 2 && v.starts_with('"') && v.ends_with('"') {
        v[1..v.len() - 1].replace("\\\"", "\"").replace("\\\\", "\\")
    } else {
        v.to_string()
    }
}

/// Con comillas, como hace Qt con los valores que llevan '#', espacios o comas.
fn con_comillas(v: &str) -> String {
    format!("\"{}\"", v.replace('\\', "\\\\").replace('"', "\\\""))
}

fn leer_tema(clave: &str) -> Option<String> {
    let ini = leer_ini(&theme_conf().ok()?);
    ini.iter()
        .find(|(g, _)| g == "Theme")
        .and_then(|(_, c)| c.iter().find(|(k, _)| k == clave))
        .map(|(_, v)| sin_comillas(v))
}

fn guardar_tema(cambios: &[(&str, String)]) -> Result<(), String> {
    let ruta = theme_conf()?;
    let mut ini = leer_ini(&ruta);
    if !ini.iter().any(|(g, _)| g == "Theme") {
        ini.push(("Theme".to_string(), Vec::new()));
    }
    let grupo = &mut ini.iter_mut().find(|(g, _)| g == "Theme").unwrap().1;
    for (clave, valor) in cambios {
        match grupo.iter_mut().find(|(k, _)| k == clave) {
            Some(par) => par.1 = valor.clone(),
            None => grupo.push((clave.to_string(), valor.clone())),
        }
    }
    escribir_ini(&ruta, &ini)
}

// ------------------------------------------------------------------- tema

pub fn cmd_tema(modo: Option<String>) -> Result<(), String> {
    let oscuro_ahora = leer_tema("isDark").map(|v| v == "true").unwrap_or(false);
    let Some(modo) = modo else {
        println!("Tema actual: {}", if oscuro_ahora { "oscuro" } else { "claro" });
        println!("Uso: titan tema claro | oscuro | alternar");
        return Ok(());
    };
    let oscuro = match modo.to_lowercase().as_str() {
        "claro" | "light" => false,
        "oscuro" | "dark" => true,
        "alternar" | "toggle" => !oscuro_ahora,
        otro => return Err(format!("tema desconocido '{otro}' (usa claro, oscuro o alternar)")),
    };
    guardar_tema(&[("isDark", oscuro.to_string())])?;
    println!("Tema {} aplicado.", if oscuro { "oscuro" } else { "claro" });
    Ok(())
}

// ----------------------------------------------------------------- acento

pub fn cmd_acento(color: Option<String>) -> Result<(), String> {
    let Some(color) = color else {
        let actual = leer_tema("accent").unwrap_or_else(|| "#0071e3".to_string());
        let nombre = ACENTOS
            .iter()
            .find(|(_, hex)| hex.eq_ignore_ascii_case(&actual))
            .map(|(n, _)| *n)
            .unwrap_or("personalizado");
        println!("Acento actual: {nombre} ({actual})");
        println!("Disponibles: {}", ACENTOS.iter().map(|(n, _)| *n).collect::<Vec<_>>().join(", "));
        println!("También vale un color #rrggbb.");
        return Ok(());
    };
    let c = color.to_lowercase();
    let hex = if let Some((_, h)) = ACENTOS.iter().find(|(n, _)| *n == c) {
        h.to_string()
    } else if c.len() == 7 && c.starts_with('#') && c[1..].chars().all(|ch| ch.is_ascii_hexdigit()) {
        c.clone()
    } else {
        return Err(format!(
            "color desconocido '{color}' (usa {} o #rrggbb)",
            ACENTOS.iter().map(|(n, _)| *n).collect::<Vec<_>>().join(", ")
        ));
    };
    guardar_tema(&[("accent", con_comillas(&hex))])?;
    println!("Acento {hex} aplicado.");
    Ok(())
}

// ------------------------------------------------------------------ fondo

fn es_imagen(p: &Path) -> bool {
    p.extension()
        .and_then(|e| e.to_str())
        .map(|e| EXT_IMAGEN.contains(&e.to_lowercase().as_str()))
        .unwrap_or(false)
}

fn fondos_disponibles() -> Vec<PathBuf> {
    let mut dirs = vec![PathBuf::from(FONDOS_SISTEMA)];
    if let Ok(home) = std::env::var("HOME") {
        dirs.push(Path::new(&home).join("Imágenes/Fondos"));
        dirs.push(Path::new(&home).join("Pictures/Wallpapers"));
    }
    let mut out = Vec::new();
    for d in dirs {
        if let Ok(rd) = fs::read_dir(&d) {
            let mut v: Vec<PathBuf> = rd.flatten().map(|e| e.path()).filter(|p| es_imagen(p)).collect();
            v.sort();
            out.extend(v);
        }
    }
    out
}

pub fn cmd_fondo(arg: Option<String>) -> Result<(), String> {
    let fondos = fondos_disponibles();
    let Some(arg) = arg else {
        let actual = leer_tema("wallpaper").unwrap_or_default();
        println!("Fondo actual: {}", if actual.is_empty() { "(por defecto)" } else { &actual });
        println!();
        for (i, f) in fondos.iter().enumerate() {
            let marca = if f.display().to_string() == actual { "*" } else { " " };
            println!(" {marca}{:>2}. {}", i + 1, f.file_name().unwrap_or_default().to_string_lossy());
        }
        println!();
        println!("Uso: titan fondo <número | nombre | ruta de imagen>");
        return Ok(());
    };

    // Número de la lista, nombre (o parte) de un fondo del sistema, o ruta.
    let ruta: PathBuf = if let Ok(n) = arg.parse::<usize>() {
        fondos.get(n.wrapping_sub(1)).cloned().ok_or_else(|| format!("no hay fondo número {n}"))?
    } else if Path::new(&arg).is_file() {
        fs::canonicalize(&arg).map_err(|e| format!("{arg}: {e}"))?
    } else {
        let a = arg.to_lowercase();
        let encontrados: Vec<&PathBuf> = fondos
            .iter()
            .filter(|p| p.file_name().map(|f| f.to_string_lossy().to_lowercase().contains(&a)).unwrap_or(false))
            .collect();
        match encontrados.as_slice() {
            [uno] => (*uno).clone(),
            [] => return Err(format!("no existe '{arg}' ni hay un fondo con ese nombre (mira: titan fondo)")),
            _ => return Err(format!("'{arg}' coincide con varios fondos; sé más concreto (mira: titan fondo)")),
        }
    };
    if !es_imagen(&ruta) {
        return Err(format!("{} no parece una imagen (jpg, png o webp)", ruta.display()));
    }
    let ruta_s = ruta.display().to_string();
    guardar_tema(&[("wallpaper", con_comillas(&ruta_s))])?;
    // Compatibilidad con titan-desktop, que también mira este fichero.
    let _ = fs::write(config_dir()?.join("wallpaper"), format!("{ruta_s}\n"));
    // Con la sesión gráfica abierta, avisar al escritorio para que cambie ya.
    if std::env::var_os("WAYLAND_DISPLAY").is_some() {
        let _ = Command::new("titan-desktop").args(["--wallpaper", &ruta_s]).spawn();
    }
    println!("Fondo cambiado a {ruta_s}");
    Ok(())
}

// ------------------------------------------------------------------- apps

fn leer_desktop(ruta: &Path) -> BTreeMap<String, String> {
    let mut m = BTreeMap::new();
    let Ok(t) = fs::read_to_string(ruta) else { return m };
    let mut dentro = false;
    for l in t.lines() {
        let l = l.trim();
        if l.starts_with('[') {
            dentro = l == "[Desktop Entry]";
            continue;
        }
        if dentro {
            if let Some((k, v)) = l.split_once('=') {
                m.entry(k.trim().to_string()).or_insert_with(|| v.trim().to_string());
            }
        }
    }
    m
}

pub fn cmd_apps(filtro: Option<String>) -> Result<(), String> {
    let mut dirs = vec![
        PathBuf::from("/usr/share/applications"),
        PathBuf::from("/usr/local/share/applications"),
        PathBuf::from("/var/lib/flatpak/exports/share/applications"),
    ];
    if let Ok(home) = std::env::var("HOME") {
        dirs.push(Path::new(&home).join(".local/share/applications"));
    }
    let filtro = filtro.map(|f| f.to_lowercase());
    let mut apps: BTreeMap<String, String> = BTreeMap::new();
    for d in dirs {
        let Ok(rd) = fs::read_dir(&d) else { continue };
        for e in rd.flatten() {
            let p = e.path();
            if p.extension().and_then(|x| x.to_str()) != Some("desktop") {
                continue;
            }
            let m = leer_desktop(&p);
            let si = |k: &str| m.get(k).map(|v| v.eq_ignore_ascii_case("true")).unwrap_or(false);
            if si("NoDisplay") || si("Hidden") || m.get("Type").map(|t| t != "Application").unwrap_or(false) {
                continue;
            }
            let nombre = m.get("Name[es]").or_else(|| m.get("Name")).cloned().unwrap_or_default();
            let exec = m.get("Exec").cloned().unwrap_or_default();
            let exec: String = exec
                .split_whitespace()
                .filter(|w| !(w.starts_with('%') && w.len() == 2))
                .collect::<Vec<_>>()
                .join(" ");
            if nombre.is_empty() || exec.is_empty() {
                continue;
            }
            if let Some(f) = &filtro {
                if !nombre.to_lowercase().contains(f) && !exec.to_lowercase().contains(f) {
                    continue;
                }
            }
            apps.entry(nombre).or_insert(exec);
        }
    }
    if apps.is_empty() {
        println!("No se ha encontrado ninguna aplicación.");
        return Ok(());
    }
    let ancho = apps.keys().map(|k| k.chars().count()).max().unwrap_or(10).min(32);
    for (n, e) in &apps {
        println!("  {n:<ancho$}  {e}");
    }
    println!("\n{} aplicaciones", apps.len());
    Ok(())
}

// ----------------------------------------------------------------- update

fn existe(programa: &str) -> bool {
    std::env::var("PATH")
        .unwrap_or_default()
        .split(':')
        .any(|d| !d.is_empty() && Path::new(d).join(programa).is_file())
}

pub fn cmd_update(solo_comprobar: bool) -> Result<(), String> {
    if !existe("pacman") {
        return Err("no se encuentra pacman".into());
    }
    if solo_comprobar {
        // checkupdates (pacman-contrib) mira sin tocar la base de datos del sistema.
        if existe("checkupdates") {
            let st = Command::new("checkupdates").status().map_err(|e| e.to_string())?;
            // 2 = no hay actualizaciones
            if st.code() == Some(2) {
                println!("El sistema está al día.");
            }
        } else {
            println!("Para comprobar sin actualizar hace falta 'checkupdates' (paquete pacman-contrib).");
        }
        if existe("flatpak") {
            let _ = Command::new("flatpak").args(["remote-ls", "--updates"]).status();
        }
        return Ok(());
    }

    println!("\x1b[1;36m==> Paquetes del sistema (pacman)\x1b[0m");
    let es_root = std::env::var("USER").map(|u| u == "root").unwrap_or(false);
    let st = if es_root {
        Command::new("pacman").arg("-Syu").status()
    } else {
        Command::new("sudo").args(["pacman", "-Syu"]).status()
    }
    .map_err(|e| format!("no se pudo lanzar pacman: {e}"))?;
    if !st.success() {
        return Err("la actualización de pacman no terminó bien".into());
    }
    if existe("flatpak") {
        println!("\x1b[1;36m==> Aplicaciones Flatpak\x1b[0m");
        let _ = Command::new("flatpak").args(["update", "-y"]).status();
    }
    println!("\x1b[1;32mSistema actualizado.\x1b[0m");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn comillas_ida_y_vuelta() {
        let v = "/home/a b/\"x\".jpg";
        assert_eq!(sin_comillas(&con_comillas(v)), v);
        assert_eq!(sin_comillas("#0071e3"), "#0071e3");
    }

    #[test]
    fn ini_conserva_lo_ajeno() {
        let dir = std::env::temp_dir().join(format!("titan-cli-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let f = dir.join("theme.conf");
        fs::write(&f, "[Otro]\nx=1\n\n[Theme]\nisDark=false\naccent=\"#0071e3\"\n").unwrap();
        let mut ini = leer_ini(&f);
        ini.iter_mut().find(|(g, _)| g == "Theme").unwrap().1[0].1 = "true".into();
        escribir_ini(&f, &ini).unwrap();
        let t = fs::read_to_string(&f).unwrap();
        assert!(t.contains("[Otro]\nx=1"));
        assert!(t.contains("isDark=true"));
        assert!(t.contains("accent=\"#0071e3\""));
        fs::remove_dir_all(&dir).unwrap();
    }
}
