//! `titan` - Titan Linux system CLI.
//!
//! Small, dependency-light front end that gives a freshly booted Titan Linux
//! a single entry point for: the branded fastfetch view, release information,
//! a hardware/kernel summary, a self check and a listing of the base command
//! set that ships with the system.

use std::fs;
use std::path::Path;
use std::process::{Command, ExitCode};

use clap::{Parser, Subcommand};

const RELEASE_FILE: &str = "/etc/titan-release";
const OS_RELEASE: &str = "/usr/lib/os-release";
const LOGO_FILE: &str = "/usr/share/titan/titan.logo";
const FASTFETCH_PRESET: &str = "titan";

/// Fallback logo, used when the installed one is missing (for example when the
/// binary is run from a build directory instead of the live system).
const FALLBACK_LOGO: &str = r#"
    ██████  ██   ██ ████████ █████  ███    ██
       ██  ██   ██    ██    ██   ██ ████   ██
       ██  ██   ██    ██    ███████ ██ ██  ██
       ██  ██   ██    ██    ██  ██ ██  ██ ██
    ██████   █████     ██    ██   ██ ██   ████

          L I N U X
"#;

#[derive(Parser)]
#[command(
    name = "titan",
    version,
    about = "Titan Linux system CLI",
    long_about = "Titan Linux system CLI.\n\nRun without arguments to get the branded system summary (fastfetch).",
    subcommand_required = false,
    arg_required_else_help = false
)]
struct Cli {
    #[command(subcommand)]
    command: Option<Command_>,
}

#[derive(Subcommand)]
enum Command_ {
    /// Branded system summary (this is what plain `titan` runs).
    Fetch {
        /// Extra arguments forwarded to fastfetch.
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },

    /// Release information: version, codename, build date.
    Version,

    /// Key/value summary of the running system.
    Info,

    /// Self check: kernel, init system, command set, disk space.
    Doctor,

    /// List the basic Linux command set that ships with Titan Linux.
    Commands,

    /// Print the Titan Linux logo.
    Logo,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let result = match cli.command {
        None => cmd_fetch(Vec::new()),
        Some(Command_::Fetch { args }) => cmd_fetch(args),
        Some(Command_::Version) => cmd_version(),
        Some(Command_::Info) => cmd_info(),
        Some(Command_::Doctor) => cmd_doctor(),
        Some(Command_::Commands) => cmd_commands(),
        Some(Command_::Logo) => cmd_logo(),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("titan: {err}");
            ExitCode::FAILURE
        }
    }
}

// ------------------------------------------------------------------ branding

fn cmd_logo() -> Result<(), String> {
    match fs::read_to_string(LOGO_FILE) {
        Ok(text) => print!("{text}"),
        Err(_) => print!("{FALLBACK_LOGO}"),
    }
    Ok(())
}

// -------------------------------------------------------------------- fetch

fn cmd_fetch(args: Vec<String>) -> Result<(), String> {
    let status = Command::new("fastfetch")
        .arg("--config")
        .arg(FASTFETCH_PRESET)
        .args(&args)
        .status()
        .map_err(|_| {
            "fastfetch is not installed. On Titan Linux run: pacman -S fastfetch".to_string()
        })?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("fastfetch exited with {status}"))
    }
}

// ------------------------------------------------------------------ version

fn read_key_value_file(path: &str) -> Vec<(String, String)> {
    let Ok(text) = fs::read_to_string(path) else {
        return Vec::new();
    };
    text.lines()
        .filter(|line| !line.trim().is_empty() && !line.trim_start().starts_with('#'))
        .filter_map(|line| {
            let (key, value) = line.split_once('=')?;
            Some((
                key.trim().to_string(),
                value.trim().trim_matches('"').to_string(),
            ))
        })
        .collect()
}

fn field(fields: &[(String, String)], key: &str) -> Option<String> {
    fields
        .iter()
        .find(|(k, _)| k.eq_ignore_ascii_case(key))
        .map(|(_, v)| v.clone())
}

fn cmd_version() -> Result<(), String> {
    let release = read_key_value_file(RELEASE_FILE);
    let os = read_key_value_file(OS_RELEASE);

    let name = field(&release, "NAME")
        .or_else(|| field(&os, "NAME"))
        .unwrap_or_else(|| "Titan Linux".to_string());
    let version = field(&release, "VERSION").unwrap_or_else(|| "desarrollo".to_string());
    let codename = field(&release, "CODENAME").unwrap_or_default();
    let build = field(&release, "BUILD_DATE").unwrap_or_default();
    let variant = field(&release, "VARIANT").unwrap_or_else(|| "live".to_string());

    println!("{name} {version}");
    if !codename.is_empty() {
        println!("apodo: {codename}");
    }
    println!("variante: {variant}");
    if !build.is_empty() {
        println!("compilada: {build}");
    }
    println!("kernel: {}", kernel_release());
    println!("titan: {}", env!("CARGO_PKG_VERSION"));
    Ok(())
}

fn kernel_release() -> String {
    fs::read_to_string("/proc/sys/kernel/osrelease")
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|_| "desconocido".to_string())
}

// --------------------------------------------------------------------- info

fn output_of(program: &str, args: &[&str]) -> Option<String> {
    let out = Command::new(program).args(args).output().ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

fn cmd_info() -> Result<(), String> {
    let os = read_key_value_file(OS_RELEASE);
    let mut rows: Vec<(String, String)> = Vec::new();

    rows.push((
        "distribucion".into(),
        field(&os, "PRETTY_NAME").unwrap_or_else(|| "Titan Linux".into()),
    ));
    rows.push(("kernel".into(), kernel_release()));
    if let Some(v) = fs::read_to_string("/proc/sys/kernel/ostype")
        .ok()
        .map(|s| s.trim().to_string())
    {
        rows.push(("tipo".into(), v));
    }
    if let Some(host) = fs::read_to_string("/proc/sys/kernel/hostname")
        .ok()
        .map(|s| s.trim().to_string())
    {
        rows.push(("host".into(), host));
    }
    if let Some(v) = output_of("uname", &["-m"]) {
        rows.push(("arquitectura".into(), v));
    }
    if let Some(v) = output_of("nproc", &[]) {
        rows.push(("cpus".into(), v));
    }
    if let Some(v) = output_of("systemd-detect-virt", &[]) {
        rows.push(("virtualizacion".into(), v));
    }
    if let Some(v) = output_of("uptime", &["-p"]) {
        rows.push(("uptime".into(), v));
    }
    if let Some(v) = output_of("free", &["-h", "--si"]) {
        // only the Mem: line is interesting here
        let line = v
            .lines()
            .find(|l| l.starts_with("Mem:"))
            .unwrap_or("")
            .to_string();
        if !line.is_empty() {
            rows.push(("memoria".into(), line));
        }
    }
    if let Some(v) = output_of("df", &["-h", "/"]) {
        if let Some(line) = v.lines().nth(1) {
            rows.push(("raiz".into(), line.to_string()));
        }
    }
    if let Some(v) = output_of("pacman", &["-Qq"]) {
        let n = v.lines().count();
        rows.push(("paquetes".into(), n.to_string()));
    }
    if let Some(v) = fs::read_to_string("/etc/hostname")
        .ok()
        .map(|s| s.trim().to_string())
    {
        rows.push(("hostname".into(), v));
    }

    let width = rows.iter().map(|(k, _)| k.len()).max().unwrap_or(0);
    for (key, value) in &rows {
        println!("{key:<width$}  {value}", width = width);
    }
    Ok(())
}

// ------------------------------------------------------------------- doctor

struct Check {
    name: &'static str,
    ok: bool,
    detail: String,
}

fn which(program: &str) -> Option<String> {
    let path = std::env::var("PATH").unwrap_or_default();
    for dir in path.split(':').filter(|d| !d.is_empty()) {
        let candidate = Path::new(dir).join(program);
        if candidate.is_file() {
            return Some(candidate.display().to_string());
        }
    }
    None
}

fn cmd_doctor() -> Result<(), String> {
    let mut checks: Vec<Check> = Vec::new();

    // Kernel
    let krel = kernel_release();
    let custom = krel.contains("titanlinux");
    checks.push(Check {
        name: "kernel",
        ok: true,
        detail: if custom {
            format!("{krel} (kernel propio de Titan Linux)")
        } else {
            format!("{krel} (kernel de Arch, entrada de respaldo)")
        },
    });

    // Init system
    let init = output_of("ps", &["-p", "1", "-o", "comm="]).unwrap_or_else(|| "?".into());
    checks.push(Check {
        name: "init",
        ok: true,
        detail: init,
    });

    // Distribution identity
    let os = read_key_value_file(OS_RELEASE);
    let os_name = field(&os, "PRETTY_NAME").unwrap_or_default();
    checks.push(Check {
        name: "os-release",
        ok: os_name.contains("Titan"),
        detail: os_name,
    });

    // Basic command set (from the same table `titan commands` prints)
    let mut required: Vec<&str> = COMMAND_SET
        .iter()
        .flat_map(|(_, items)| items.iter().copied())
        .filter(|c| !SHELL_BUILTINS.contains(c))
        .collect();
    required.sort_unstable();
    required.dedup();
    let missing: Vec<&str> = required
        .iter()
        .copied()
        .filter(|c| which(c).is_none())
        .collect();
    checks.push(Check {
        name: "comandos basicos",
        ok: missing.is_empty(),
        detail: if missing.is_empty() {
            format!("{} comandos presentes", required.len())
        } else {
            format!("faltan: {}", missing.join(", "))
        },
    });

    // Titan tooling
    let self_exe = std::env::current_exe().ok();
    for tool in ["titan", "fastfetch"] {
        let found = which(tool).or_else(|| {
            if tool == "titan" {
                self_exe.as_ref().map(|p| p.display().to_string())
            } else {
                None
            }
        });
        let ok = found.is_some();
        checks.push(Check {
            name: tool,
            ok,
            detail: found.unwrap_or_else(|| "no encontrado".into()),
        });
    }

    // Writable root
    let writable = Path::new("/tmp").metadata().map(|m| !m.permissions().readonly()).unwrap_or(false);
    checks.push(Check {
        name: "escritura",
        ok: writable,
        detail: "/tmp escribible".into(),
    });

    // Historial de la salida en la consola de texto.
    //
    // Esto no lo da el kernel: la consola del live la dibuja fbcon, que no
    // tiene scrollback (en el codigo del kernel esta descartado con
    // pr_warn("Ignoring scrollback size option")). El historial lo aporta tmux,
    // que envuelve la shell de tty1. Se comprueban por separado las tres cosas
    // que pueden fallar: que este el programa, que este la configuracion y que
    // el envoltorio siga apuntando a tty1 y no se lleve por delante la consola
    // por serie, que es la que usan las pruebas automaticas y el instalador.
    let tmux_which = which("tmux");
    let conf = Path::new("/etc/tmux.conf");
    let wrapper = Path::new("/etc/profile.d/20-titan-scrollback.sh");
    let wrapper_text = std::fs::read_to_string(wrapper).unwrap_or_default();
    // El envoltorio tiene que existir y seguir hablando de tty1. Si el nombre
    // del fichero se cambia en un sitio y no en el otro, esto es lo que avisa.
    let solo_tty1 = !wrapper_text.is_empty() && wrapper_text.contains("/dev/tty1");
    // Y que el config enganche la tecla correcta. Esto parece un detalle pero no
    // lo es: el kernel se come RePag Y Shift+RePag pulsada, asi que la unica que
    // llega a la tty es RePag a secas, que tmux llama 'PPage'. Y si el enlace se
    // pone con otro nombre, 'PageUp' o 'S-PageUp', tmux no da ningun error: lo
    // ignora en silencio y la tecla se queda muerta sin que se note. Ademas, una
    // vez dentro del historial mandan las teclas las tablas de copy-mode, no la
    // de root, asi que los dos sitios tienen que estar enganchados.
    //
    // Los enlaces se comparan con los espacios normalizados (el config los lleva
    // alineados en columnas) y solo se miran las lineas que enlazan, no los
    // comentarios: el fichero explica en la cabecera por que S-PPage no vale, y
    // mencionarlo ahi seria justo lo que haria fallar este chequeo.
    let enlaces: Vec<String> = std::fs::read_to_string(conf)
        .unwrap_or_default()
        .lines()
        .map(str::trim)
        .filter(|l| l.starts_with("bind"))
        .map(|l| l.split_whitespace().collect::<Vec<_>>().join(" "))
        .collect();
    let enlace_raiz = enlaces.iter().any(|e| e == "bind -n PPage copy-mode -u");
    let enlace_hist = enlaces.iter().any(|e| e.starts_with("bind -T copy-mode PPage "));
    let enlace_malo = enlaces.iter().any(|e| {
        e.contains("S-PPage") || e.contains("S-NPage") || e.contains("PageUp")
            || e.contains("PageDown")
    });
    let teclas_ok = enlace_raiz && enlace_hist && !enlace_malo;
    let teclas_detail = if !enlace_raiz {
        "falta 'bind -n PPage copy-mode -u': RePag no entra en el historial"
    } else if !enlace_hist {
        "falta 'bind -T copy-mode PPage': dentro del historial RePag no hace nada"
    } else if enlace_malo {
        "el config usa nombres de tecla que tmux ignora en silencio (S-PPage, PageUp...)"
    } else {
        "RePag entra al historial y dentro sube una pantalla"
    };

    let hist_ok = tmux_which.is_some() && conf.is_file() && solo_tty1 && teclas_ok;
    let hist_detail = match (&tmux_which, conf.is_file(), solo_tty1, teclas_ok) {
        (Some(t), true, true, true) => {
            if std::env::var("TMUX").is_ok() {
                format!("tmux en {} (esta shell va dentro, RePag relee la salida)", t)
            } else {
                format!("tmux en {} (esta shell no va dentro: no es tty1)", t)
            }
        }
        (None, _, _, _) => {
            "tmux no esta instalado: la consola de texto no tendra historial".into()
        }
        (_, false, _, _) => "/etc/tmux.conf no esta".into(),
        (_, _, false, _) => {
            "el envoltorio de tty1 no esta o no menciona /dev/tty1".into()
        }
        (_, _, _, false) => teclas_detail.into(),
    };
    checks.push(Check {
        name: "historial consola",
        ok: hist_ok,
        detail: hist_detail,
    });

    let failed = checks.iter().filter(|c| !c.ok).count();
    for check in &checks {
        println!(
            "[{}] {:<17} {}",
            if check.ok { " OK " } else { "FALLO" },
            check.name,
            check.detail
        );
    }
    println!();
    if failed == 0 {
        println!("titan doctor: todo correcto ({}/{})", checks.len(), checks.len());
        Ok(())
    } else {
        Err(format!(
            "titan doctor: {failed} comprobacion(es) fallida(s) de {}",
            checks.len()
        ))
    }
}

// ----------------------------------------------------------------- commands

/// The basic command set that ships with Titan Linux 0.1.
///
/// Single source of truth for both `titan commands` (documentation) and the
/// `comandos basicos` check of `titan doctor` (verification). If a command is
/// listed here it must be provided by a package in iso/titan/packages.x86_64.
const COMMAND_SET: &[(&str, &[&str])] = &[
    (
        "Ficheros y directorios",
        &[
            "ls", "cd", "pwd", "mkdir", "rmdir", "rm", "cp", "mv", "ln", "touch", "stat", "file",
            "tree", "realpath", "basename", "dirname", "readlink",
        ],
    ),
    (
        "Leer y filtrar texto",
        &[
            "cat", "less", "head", "tail", "wc", "grep", "cut", "tr", "sort", "uniq", "tee", "diff",
            "column", "fold", "nl", "rev", "paste", "join",
        ],
    ),
    (
        "Transformar texto",
        &["sed", "awk", "gawk", "expr", "seq", "xargs", "tr", "fmt", "pr"],
    ),
    (
        "Buscar",
        &["find", "grep", "rg", "fd", "fzf", "bat", "which", "jq"],
    ),
    (
        "Procesos y sistema",
        &[
            "ps", "top", "htop", "free", "vmstat", "uptime", "uname", "hostname", "id", "whoami",
            "date", "cal", "env", "lscpu", "lspci", "lsusb", "lsblk", "dmesg", "sysctl", "lsof",
            "strace",
        ],
    ),
    (
        "Disco y archivos",
        &[
            "df", "du", "mount", "umount", "fdisk", "mkfs.ext4", "fsck", "blkid", "dd", "file",
        ],
    ),
    (
        "Red",
        &["ip", "ss", "ping", "curl", "wget", "dig", "host", "ethtool"],
    ),
    (
        "Compresion y paquetes",
        &[
            "tar", "gzip", "gunzip", "bzip2", "xz", "zstd", "unzip", "pacman", "makepkg", "base64",
        ],
    ),
    (
        "Editores y ayuda",
        &["nano", "vim", "less", "man", "git", "bc", "titan", "fastfetch"],
    ),
];

/// Shell builtins: they exist inside bash even though there is no binary in
/// $PATH, so they must be skipped by the binary presence check.
const SHELL_BUILTINS: &[&str] = &[
    "cd", "exit", "export", "umask", "eval", "exec", "read", "set", "unset", "source", "alias",
];

fn cmd_commands() -> Result<(), String> {
    for (title, items) in COMMAND_SET {
        println!("\x1b[1;36m{title}\x1b[0m");
        let mut line = String::new();
        for item in *items {
            if !line.is_empty() {
                line.push_str("  ");
            }
            line.push_str(item);
        }
        println!("  {line}");
    }
    println!();
    println!("\x1b[1;36mTitan\x1b[0m");
    println!("  titan  |  titan info  |  titan doctor  |  titan commands  |  titan logo");
    Ok(())
}
