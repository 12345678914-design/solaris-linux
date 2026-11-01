# Titan Linux

An Arch Linux derivative built for development, with the `niri` desktop
preconfigured, a custom LTS kernel, and first-party applications.

> **Status: the first bootable version is verified.** The kernel package builds,
> the branded live ISO boots in QEMU **on both UEFI and BIOS with 40/40 checks
> passing**, and the first-party `titan` CLI is in place. The installer, the
> desktop configuration and the GUI apps are not written yet.

---

## What this is

Titan Linux is a **derivative** of Arch Linux, not a from-scratch build. That is
a deliberate choice:

- **Drivers stay current from upstream.** Arch is a rolling release, so AMDGPU,
  i915, NVMe, USB and EXT4 arrive from upstream without Titan maintaining a
  single patch.
- **The kernel tracks the 6.x LTS line**, currently `6.18`, supported until
  **December 2028**.
- **A real development base.** Arch's repositories plus the AUR are the largest
  package set available for Linux, which is what "productive for developers"
  actually requires in practice.

What Titan Linux adds on top is a distribution layer: an installer, a branded
ISO, a package repository, a preconfigured desktop, and first-party apps.

## Layout

```
distro/
├── setup.sh                      Arch host bootstrap (Phase 1)
├── kernel/
│   ├── bump.sh                   tracks upstream LTS, refreshes the package
│   └── linux-titanlinux/         the custom kernel package
│       ├── PKGBUILD              derived from Arch's linux-lts recipe
│       ├── config.x86_64         Arch's config + Titan's delta
│       ├── 000{1,2,3}-*.patch    Arch's patches, applied unchanged
│       └── 0004-modfinal-strip-module-debug-info.patch
│                                 Titan's own: strips module DWARF at link
│                                 time, which is what makes the build fit
│                                 on a normal disk
├── iso/titan/                    the branded live ISO profile (Phase 5)
│   ├── profiledef.sh             archiso profile definition
│   ├── pacman.conf               Arch's repos + the local 'titan' repo
│   ├── packages.x86_64           the package list (= the command set)
│   ├── grub/grub.cfg              UEFI boot menu (custom kernel + rescue)
│   ├── syslinux/                  BIOS boot menu (same two entries)
│   └── airootfs/                  everything that makes it *Titan*
│       ├── root/customize_airootfs.sh   runs in the chroot after pacstrap
│       ├── etc/profile.d/10-titan.sh    prompt, aliases, banner
│       ├── etc/mkinitcpio.d/linux-titanlinux.preset
│       ├── etc/mkinitcpio.conf.d/archiso.conf
│       ├── usr/share/titan/titan.logo    the fastfetch logo
│       └── usr/share/fastfetch/presets/titan.jsonc
├── apps/titan-cli/               first-party Rust CLI (Phase 6)
├── scripts/
│   ├── build-iso.sh               builds the ISO with mkarchiso
│   ├── run-qemu.sh                boots the ISO interactively
│   ├── verify-qemu.sh             automated in-guest test suite
│   └── titan-verify.py            the test driver (drives the serial console)
├── install.sh                    the installer              (Phase 3, pending)
└── firstboot.sh                  first-boot provisioning    (Phase 6, pending)
```

## The kernel package

`linux-titanlinux` produces a kernel whose release string is
**`6.18.54-1-titanlinux`**, and it coexists with Arch's `linux-lts` so that
Arch's kernel remains in GRUB as a rescue entry.

It is derived from Arch's official `linux-lts` recipe with a deliberately
small set of changes. Full rationale is documented in the header of
`kernel/linux-titanlinux/PKGBUILD`; in summary:

| Change | Reason |
| --- | --- |
| `pkgbase=linux-titanlinux` | Yields the `-titanlinux` suffix through Arch's own `localversion` mechanism |
| `replaces=(wireguard-lts)` removed | That conflict belongs to `linux-lts`; a fork must not claim it |
| No `conflicts=('linux-lts')` | The two kernels must coexist for rescue |
| `CONFIG_LOCALVERSION_AUTO` disabled | The version is pinned by the package, not by git tags |
| `KBUILD_BUILD_HOST/USER` | Shows as Titan Linux in `uname -v` |
| `TITAN_NO_HTMLDOCS=1` opt-in | Skips `htmldocs` and its multi-GB `texlive-latexextra` chain on tight disks |

Everything else is inherited from Arch on purpose, notably `WERROR` off,
`IKCONFIG` enabled, and **`MODVERSIONS` unset** so out-of-tree modules stay
broadly compatible.

### Verified

- Tarball `linux-6.18.54.tar.xz` downloaded and its SHA256 confirmed against
  `sha256sums.asc` from kernel.org: `9df30b02…3eacac`
- That hash matches the value Arch's own recipe declares
- `config.x86_64` and the three patches match Arch's upstream files bit for bit
  (only `config.x86_64` differs, by Titan's single documented delta)
- `bump.sh` version discovery tested against the live kernel.org feed
- The package builds (163 MB, 6407 modules) and the resulting ISO boots its own
  kernel in QEMU (`uname -r` → `6.18.54-1-titanlinux`)
- Inside the live session: the 32-command catalogue, `fastfetch` with the Titan
  logo, the `titan` CLI (5 subcommands) and `titan doctor` (7/7) all pass, over
  UEFI **and** BIOS — 42/42 checks each way, transcripts in `out/verify/`
- `sudo pacman -S cowsay` works in the live session: passwordless sudo,
  repositories synchronise over the network, the package downloads, installs and
  runs (check 9 of the report)
- Output longer than the screen can be read back with RePag, and the last line
  stays in view; measured against the text console's own buffer, no OCR (check 10
  of the report, both boot paths)

## Building

### 1. The kernel (once)

On a native Arch install:

```sh
./setup.sh                          # build deps + checksum verification
cd kernel/linux-titanlinux
TITAN_NO_HTMLDOCS=1 makepkg -j"$(nproc)"   # 30-60 min on 8 threads
```

Add `sudo pacman -U ./linux-titanlinux-*.pkg.tar.zst` to boot it natively. Keep
`linux-lts` installed; if the custom kernel fails, select `linux-lts` in GRUB
and debug from there.

### 2. The ISO

```sh
./scripts/build-iso.sh
```

That script compiles the `titan` CLI, publishes `linux-titanlinux` into the
profile's local repository, resolves the pacman config, and runs `mkarchiso`.
The result lands in `out/titan-linux-<version>-x86_64.iso` with a `.sha256`
next to it.

It **always** wipes `build/archiso` first, and that is not housekeeping: mkarchiso
marks each step with a witness file (`base._make_packages`, `iso._build_iso_image`,
…) and skips the ones already marked. A `build/` directory that survives from a
previous build therefore makes the next build do **nothing**, exit 0 in twenty
seconds and cheerfully print the sha256 of the *old* ISO. The stale ISO is
deleted before starting for the same reason: a build that fails must fail, not
report last week's image. `mkarchiso` prints nothing until the end unless you
pass `-v`, so the script prints a heartbeat every 30 s.

The profile is written so the kernel is optional: if no
`linux-titanlinux-*.pkg.tar.zst` exists yet, the ISO is still built and boots
with Arch's kernel as the only entry. Use `--no-kernel` to force that path while
iterating on the ISO.

### 3. Run it

```sh
./scripts/run-qemu.sh                 # UEFI (OVMF), graphical window
./scripts/run-qemu.sh --bios          # BIOS (syslinux)
./scripts/run-qemu.sh --headless      # no window, serial console at 115200
./scripts/run-qemu.sh --disk 20G      # attach a disk to install onto
./scripts/run-qemu.sh --serial-log boot.log   # keep a transcript either way
```

### The window follows the host screen

The live ISO does **not** carry a fixed `video=` mode. It uses the native mode
that the firmware gives it, as an installed system does. When you start it with
`scripts/run-qemu.sh`, the helper `scripts/detectar-resolucion.sh` reads the
host output (niri, wlr-randr, xrandr or DRM) and puts that size in QEMU's
`virtio-vga` (`xres`/`yres`). A 1366x768 monitor therefore gets a 1366x768
guest, and a 1920x1080 monitor gets 1920x1080: no fixed 1920x1080, no black
bars. If detection is impossible it falls back to 1280x720. `--resolution
1366x768` or `TITAN_QEMU_RESOLUCION=1366x768` overrides it.

`build-iso.sh` fails if a live boot line goes back to carrying `video=`. The
old 1280x720 workaround was needed when QEMU's window was always the size of
the guest and the firmware handed over 1280x800; detecting the host and
setting the virtual card's EDID solves both problems without a static mode.

## Verifying it

`verify-qemu.sh` is not "does QEMU start": it boots the ISO headless, waits for
the shell over the serial console, then runs the command catalogue, `fastfetch`,
`titan`, `titan doctor` and a real `pacman` install **inside the guest** and
checks the output of each one.

```sh
./scripts/verify-qemu.sh
./scripts/verify-qemu.sh --bios --timeout 1200
```

It leaves a console transcript, a JSON report and screenshots in `out/verify/`,
and exits non-zero if any check fails. This is the acceptance test for the
"basic Linux commands + fastfetch" requirement. 42 checks; the last two are the
interesting ones:

- **9** `sudo` gives root without a password, the repositories synchronise,
  `cowsay` (not shipped in the ISO) installs and runs.
- **10** output longer than the screen can be read again, with the bottom of it
  still in view. This one is measured **without OCR**: the test asks the guest
  for the text currently in the text-console buffer
  (`sudo sh -c 'fold -w 80 < /dev/vcs1'`), scrolls back with the real key
  presses through QEMU's monitor, and checks that what is on screen is a
  contiguous run of numbered lines, that 40-odd presses move hundreds of lines
  back, and that `q` returns to the last line. It also leaves a screenshot
  (`historial-*.png`).
- The same check first asserts that **the prompt is on the last row of the
  console**, which is the other half of "the bottom is visible": with a
  framebuffer taller than the window the prompt is drawn just below the visible
  area and every other assertion still passes.

## Inside the live session

The live user is `titan`, with no password, and `sudo` needs none either:

```sh
sudo pacman -Sy
sudo pacman -S cowsay
```

Two details make that work, and both are easy to get wrong:

- **The sudoers rule is a drop-in**, `/etc/sudoers.d/10-titan` (mode 0440). Arch
  ships the `%wheel` rule *commented out*, so without the drop-in `sudo` answers
  "titan is not in the sudoers file" — and since the live user has no password,
  even an enabled rule would ask for one that does not exist.
- **The mirrorlist has to be activated.** The `pacman` package ships
  `/etc/pacman.d/mirrorlist` with every mirror commented out (a normal install
  uncomments one; a live ISO has no installer), so without the fix `pacman -Sy`
  fails with `no servers configured for repository`. The build writes the geo
  mirror plus two fallbacks and keeps the original list in
  `/etc/pacman.d/mirrorlist.commented`.

Writes go to a tmpfs overlay: 1 GB, set with `cow_spacesize=1G` on the kernel
command line (archiso defaults to 256 MB, which fills up quickly once pacman
downloads its databases). It is RAM, so it disappears at shutdown, together with
any package you installed.

### Scrolling back through the output

When a command writes more than one screen, the last line stays in view and the
earlier output can be read again with **RePag** (or the mouse wheel). **q** or
**Esc** leaves the history and the view snaps back to the end, so the bottom of
the output — the one with the prompt — is always where you come back to.

| key | what it does |
| --- | --- |
| RePag | back one screen through the output that scrolled away |
| wheel | same, and **Ctrl+b** then wheel scrolls by line |
| AvPag | forward again, towards the end |
| Home / End | jump to the very start / back to the end |
| q or Esc | back to the end of the output |
| Ctrl+b d | detach the session without closing it |

Two details are not obvious and both were measured, not guessed:

- **It is RePag, never Shift+RePag.** The kernel's console keymap eats *shifted*
  variants of PageUp/PageDown/F9 at the VT layer: `sendkey shift-pgup` produces
  no bytes at all, and a *modified* key that does arrive is delivered as the
  *plain* sequence, so no user-space program can tell them apart. Plain RePag
  arrives as `ESC [ 5 ~`, which tmux calls `PPage`. The bindings therefore live
  on `PPage`/`NPage`, and the `titan` banner and `titan doctor` both say RePag.
- **Inside the history, one press is one screen** — `page-up`, not `scroll-up`.
  On tmux 3.7c a 24-row pane, measured: `scroll-up` scrolls **1** line and
  `scroll-up 10` scrolls **0** (the number is silently ignored), while `page-up`
  scrolls 22. So the copy-mode table binds `page-up`/`page-down`, and
  `history-top`/`history-bottom` for Home/End.

This is **not** a feature of the kernel, and it is worth knowing why, because
the obvious fixes do not work:

- The Linux text console can only scroll back inside the VGA text buffer
  (hardware scrollback), and only in the VGA text mode. In this ISO the console
  is drawn by `fbcon` on a DRM framebuffer: in UEFI on `simple-framebuffer` /
  `simpledrm`, and in BIOS because `bochs-drm` takes the VGA console away
  (`bochs-drm: vgaarb: deactivate vga console`). Both boot paths end up as
  `Console: colour dummy device 80x25`.
- `fbcon` has no scrollback at all. Its one software-scrollback option is
  discarded on purpose inside the kernel, with `pr_warn("Ignoring scrollback size
  option")`, and `console_scrollback` never existed in mainline: putting it on
  the kernel command line only earns an "unknown parameter" warning in `dmesg`.
- The key *is* wired: the default console keymap maps Shift+PageUp to the VT's
  scroll handler, but that handler calls `con_scrolldelta`, which `fbcon` does
  not implement. Measured on both boot paths, the screen changes 0.00 %.

So the history comes from a terminal in user space. The tty1 login shell runs
inside a `tmux` session (`/etc/tmux.conf`: 50000 lines per pane, status bar off
so the console still looks like a console), started by
`/etc/profile.d/20-titan-scrollback.sh`. That wrapper is deliberately narrow:

- **tty1 only.** The serial console (`ttyS0`), which the automated tests and
  the installer use, stays a plain shell with nothing in between.
- **Interactive login shells only**, and never twice (`$TMUX` is set inside).
- **If `tmux` is missing, the shell starts normally** instead of dropping the
  user back at a login prompt.

Both the profile banner and the history hint are printed by
`/etc/profile.d/10-titan.sh`, which runs **before** the tmux wrapper (lower file
number) and so cannot know for certain whether this shell is the one that tmux is
about to replace — and the shell inside tmux re-reads that same file. So the
banner script repeats the wrapper's condition (no `$TMUX`, tty is `/dev/tty1`,
`tmux` exists) and, when it is *about to* be replaced, sets
`TITAN_SHELL_VISIBLE=0` and prints nothing. The shell that is actually visible —
the one inside tmux — has `$TMUX` set, so it prints. The banner and the hint
therefore appear **once**, not twice.

## The first-party `titan` CLI

```
titan            # branded system summary (fastfetch + Titan logo)
titan version    # release, codename, build date, kernel
titan info       # key=value summary of the running system
titan doctor     # self check: kernel, init, command set, tooling
titan commands   # the catalogue of basic Linux commands Titan ships
titan logo       # the logo, for scripts
```

`titan commands` and `titan doctor` share one table, so the documentation and the
verification cannot drift apart.

## Keeping the kernel current

Titan Linux patches no drivers, so tracking upstream is a single command:

```sh
./kernel/bump.sh --check     # exit 2 means an update is available
./kernel/bump.sh             # interactive bump
```

This re-syncs Arch's recipe, config and patches for the new LTS release,
re-applies Titan's config delta, regenerates every checksum, and reports the
diff for review before you build.

## Requirements

- Native Arch Linux x86-64. Titan Linux cannot be built on Windows; the kernel
  build requires a Linux host. (WSL2 is technically a Hyper-V VM, and WSL1's
  I/O is too slow for a kernel build.)
- **Secure Boot must be disabled**, or the unsigned kernel will not boot.
- Build hosts: ~15 GB free for the kernel tree, plus ~6 GB for the ISO.
- To test the ISO: `qemu-system-x86_64`; `edk2-ovmf` for UEFI (optional, BIOS
  works without it).

## Roadmap

- [x] **Phase 1** — Arch host bootstrap, kernel package, version tracking
- [x] **Phase 2** — kernel boots, with Arch's kernel kept as a rescue entry
- [ ] **Phase 3** — `install.sh`: partitioning, `pacstrap`, repo, GRUB
- [ ] **Phase 4** — niri preconfigured, theme, keybindings, `/etc/skeleton`
- [x] **Phase 5** — branded ISO via `archiso`
- [x] **Phase 6** — first-party Rust CLI, branded shell, live-session
      provisioning (`customize_airootfs.sh`)
- [ ] **Phase 6** — GUI apps (GTK4) and `install.sh` first-boot provisioning
- [ ] **Phase 7** — documentation and CI building the ISO per commit

## Naming

"Titan Linux" already exists as an Ubuntu-based distribution. There is no
technical conflict, but pick a distinct name before registering a domain or
publishing a public repository.
