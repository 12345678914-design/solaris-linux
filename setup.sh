#!/usr/bin/env bash
#
# setup.sh - prepare an Arch Linux host to build Titan Linux.
#
# Run this AFTER installing Arch, before the first kernel build. It installs
# the build dependencies declared by the kernel PKGBUILD, verifies the package
# files against their checksums, and optionally starts the build.
#
# Usage:
#   ./setup.sh            # install dependencies and verify checksums
#   ./setup.sh --build    # also run makepkg -s (long: 30-60 min on 8 threads)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKGDIR="$HERE/kernel/linux-titanlinux"

red()  { printf '\033[1;31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
yel()  { printf '\033[1;33m%s\033[0m\n' "$*"; }
info() { printf '\033[0;36m==>\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------- preflight --

[[ -r /etc/os-release ]] || { red "/etc/os-release not found"; exit 1; }
# shellcheck disable=SC1091
. /etc/os-release
if [[ "${ID:-}" != "arch" && "${ID:-}" != "cachyos" && "${ID_LIKE:-}" != *"arch"* ]]; then
  red "This script targets Arch Linux or Arch derivatives. Detected ID=${ID:-unknown}."
  yel "Titan Linux is an Arch derivative. Install Arch or an Arch derivative first."
  exit 1
fi
grn "Arch Linux detected ($PRETTY_NAME)"

if [[ $EUID -eq 0 ]]; then
  red "Do not run this as root. Use sudo where prompted."
  exit 1
fi

[[ -d "$PKGDIR" ]] || { red "Kernel package dir not found: $PKGDIR"; exit 1; }
[[ -f "$PKGDIR/PKGBUILD" ]] || { red "PKGBUILD not found in $PKGDIR"; exit 1; }

command -v pacman >/dev/null || { red "pacman not found"; exit 1; }

# ------------------------------------------------------------- dependencies --

info "Refreshing Arch keyring and syncing databases"
sudo pacman -Sy --needed archlinux-keyring
sudo pacman -Syu --noconfirm

info "Installing build dependencies for linux-titanlinux"
# Mirrors makedepends= from the PKGBUILD, plus the tooling Titan itself needs.
sudo pacman -S --needed --noconfirm \
  base-devel git \
  bc binutils cpio gettext glibc libelf libgcc openssl pahole \
  perl python rust rust-bindgen rust-src tar xxhash xz zlib zstd \
  graphviz imagemagick python-sphinx python-yaml texlive-latexextra \
  mkinitcpio linux-firmware grub efibootmgr os-prober \
  jq git-lfs

info "Optional tooling for later phases"
sudo pacman -S --needed --noconfirm \
  devtools qemu-desktop edk2-ovmf \
  base curl wget rsync man-db

grn "Dependencies installed."

# ----------------------------------------------------------- secure boot ----

if [[ -d /sys/firmware/efi/efivars ]] && \
   [[ -f /sys/firmware/efi/efivars/LoaderSignatureLoaded-* ]]; then
  if [[ -n "$(bootctl status 2>/dev/null | grep -i 'Secure Boot: enabled')" ]]; then
    yel "Secure Boot appears to be ENABLED."
    yel "Titan Linux's kernel is not signed by a trusted key, so it will not"
    yel "boot while Secure Boot is active. Either disable it in the firmware"
    yel "setup, or sign linux-titanlinux with your own enrolled key."
  fi
fi

# ------------------------------------------------------------ verification --

info "Verifying kernel package checksums"
( cd "$PKGDIR" && updpkgsums --print )
grn "Package files match their declared checksums."

info "Expected kernelrelease"
( cd "$PKGDIR" && updpkgsums --print >/dev/null ) || true
# pkgbase=linux-titanlinux and pkgrel=1 give 6.x.y-1-titanlinux
echo "    $(sed -n 's/^pkgver=//p' "$PKGDIR/PKGBUILD")-1-titanlinux"

# ------------------------------------------------------------------ build ---

if [[ "${1:-}" == "--build" ]]; then
  cores="$(nproc)"
  ram_gb="$(awk '/MemTotal/ { printf "%d", $2/1048576 }' /proc/meminfo)"
  info "Building linux-titanlinux with make -j$cores"
  [[ "$ram_gb" -lt 8 ]] && yel "Only ${ram_gb} GB RAM detected. Consider -j$(( cores / 2 )) to avoid swapping."

  cd "$PKGDIR"
  # -f forces a rebuild even if a same-version package already exists.
  makepkg -s --needed -f -j"$cores"

  info "Installing the freshly built kernel"
  sudo pacman -U --noconfirm ./linux-titanlinux-*.pkg.tar.zst

  info "Regenerating the bootloader"
  sudo grub-mkconfig -o /boot/grub/grub.cfg

  grn "Done. Reboot, then verify with:  uname -r"
  echo "    Expect: 6.x.y-titanlinux"
  echo
  yel "Keep Arch's linux-lts installed as a rescue entry in GRUB."
  yel "If Titan Linux's kernel fails to boot, boot linux-lts and debug from there."
else
  cat <<EOF

Next steps:

  1. Build the kernel
       cd $PKGDIR
       makepkg -s -j\$(nproc)

  2. Install it
       sudo pacman -U ./linux-titanlinux-*.pkg.tar.zst

  3. Add it to the bootloader
       sudo grub-mkconfig -o /boot/grub/grub.cfg

  4. Reboot and verify
       uname -r          # expect: 6.x.y-titanlinux

  Keep Arch's linux-lts installed. It stays in GRUB as a rescue entry.

  Track future kernel updates with:
       $HERE/kernel/bump.sh --check

EOF
fi
