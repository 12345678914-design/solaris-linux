#!/usr/bin/env bash
#
# kernel/bump.sh - track the upstream 6.x LTS kernel for Titan Linux.
#
# Titan Linux does not patch drivers. Instead, the kernel package is kept
# current by re-syncing Arch Linux's official linux-lts recipe whenever a new
# longterm release appears on kernel.org, then re-applying Titan's small config
# delta and regenerating checksums.
#
# Usage:
#   ./bump.sh            # check for a new LTS, offer to bump, then stop
#   ./bump.sh --check    # report only, never modify anything (exit 0 = up to date)
#   ./bump.sh --apply    # bump without asking
#
# Exit codes: 0 up to date / done, 1 error, 2 update available (with --check)

set -euo pipefail

PKGDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/linux-titanlinux"
PKGBUILD="$PKGDIR/PKGBUILD"
ARCH_REPO="https://gitlab.archlinux.org/archlinux/packaging/packages/linux-lts/-/raw/main"
KERNEL_RELEASES="https://www.kernel.org/releases.json"
KERNEL_SUMS="https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc"

# The 6.x major track Titan Linux follows.
TRACK="6"

MODE="${1:-}"
red()  { printf '\033[1;31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
yel()  { printf '\033[1;33m%s\033[0m\n' "$*"; }
info() { printf '\033[0;36m==>\033[0m %s\n' "$*"; }

command -v curl >/dev/null || { red "curl is required"; exit 1; }

current_ver() {
  # pkgver= from the PKGBUILD, without sourcing it.
  sed -n "s/^pkgver=\(.*\)\$/\1/p" "$PKGBUILD" | head -1
}

latest_ver() {
  # Highest 6.x "longterm" version currently published by kernel.org.
  #
  # kernel.org's releases.json puts "moniker" and "version" on separate lines,
  # and grep cannot match across a line boundary. So the document is flattened
  # to a single line first, then the moniker/version pairs are pulled out with
  # plain BRE (no PCRE dependency) and the version is extracted with sed.
  #
  # sort -V is mandatory here: lexicographically "6.6.157" sorts above
  # "6.18.54", which would silently pick the wrong (older) kernel.
  curl -fsSL "$KERNEL_RELEASES" \
    | tr '\n\t' '  ' \
    | tr -s ' ' \
    | grep -o '"moniker" *: *"longterm" *, *"version" *: *"[^"]*"' \
    | sed 's/.*"version" *: *"\([^"]*\)".*/\1/' \
    | grep "^${TRACK}\." \
    | sort -V \
    | tail -1
}

tarball_sha256() {
  local ver="$1"
  curl -fsSL "$KERNEL_SUMS" | awk -v f="linux-$ver.tar.xz" '$2 == f { print $1 }'
}

require_cmd() {
  command -v "$1" >/dev/null || { red "'$1' is required but not installed"; exit 1; }
}

sync_from_arch() {
  local ver="$1"
  local patchfile
  local -a patches=()

  # Re-download Arch's recipe, config and every patch for the new version.
  info "Fetching Arch recipe for linux $ver"
  curl -fsSL -o "$PKGBUILD.tmp" "$ARCH_REPO/PKGBUILD"
  curl -fsSL -o "$PKGDIR/config.x86_64.tmp" "$ARCH_REPO/config.x86_64"

  # Collect the patch names the new upstream recipe expects.
  mapfile -t patches < <(
    sed -n 's/^  \([0-9].*\.patch\)$/\1/p' "$PKGBUILD.tmp"
  )

  local p
  for p in "${patches[@]}"; do
    info "Fetching patch $p"
    curl -fsSL -o "$PKGDIR/$p.tmp" "$ARCH_REPO/$p"
  done

  mv -f "$PKGBUILD.tmp" "$PKGBUILD"
  mv -f "$PKGDIR/config.x86_64.tmp" "$PKGDIR/config.x86_64"
  for p in "${patches[@]}"; do
    mv -f "$PKGDIR/$p.tmp" "$PKGDIR/$p"
  done

  # Drop patches that upstream no longer references.
  find "$PKGDIR" -maxdepth 1 -name '*.patch' -print0 \
    | while IFS= read -r -d '' stale; do
        base="$(basename "$stale")"
        if [[ -n "${patches[*]:-}" && ! " ${patches[*]} " =~ " $base " ]]; then
          info "Removing stale patch $base"
          rm -f "$stale"
        fi
      done

  patchfile="$PKGDIR/config.x86_64"
  [[ -f "$patchfile" ]] || { red "config.x86_64 missing after sync"; exit 1; }
}

apply_titan_deltas() {
  # 1. pkgbase -> linux-titanlinux (drives the -titanlinux kernelrelease suffix
  #    through Arch's own localversion.20-pkgname mechanism).
  if grep -q '^pkgbase=linux-lts$' "$PKGBUILD"; then
    info "Re-applying Titan delta: pkgbase"
    sed -i 's/^pkgbase=linux-lts$/pkgbase=linux-titanlinux/' "$PKGBUILD"
  fi

  # 2. Branding.
  sed -i "s/^pkgdesc='LTS Linux'$/pkgdesc='Titan Linux kernel (LTS $TRACK track)'/" "$PKGBUILD"
  sed -i 's/^# Maintainer: Andreas Radke.*/# Maintainer: Titan Linux <titan@titanos.local>/' "$PKGBUILD"
  sed -i 's/^export KBUILD_BUILD_HOST=archlinux$/export KBUILD_BUILD_HOST=titanos/' "$PKGBUILD"
  sed -i 's/^export KBUILD_BUILD_USER=\$pkgbase$/export KBUILD_BUILD_USER=titanlinux/' "$PKGBUILD"

  # 3. Drop 'replaces=(wireguard-lts)': that conflict belongs to Arch's
  #    linux-lts, and a fork must not claim it.
  sed -i '/^  replaces=$/,/^  )$/d' "$PKGBUILD"

  # 4. Titan config delta: disable CONFIG_LOCALVERSION_AUTO.
  info "Re-applying Titan delta: CONFIG_LOCALVERSION_AUTO"
  sed -i 's/^CONFIG_LOCALVERSION_AUTO=y$/# CONFIG_LOCALVERSION_AUTO is not set/' \
    "$PKGDIR/config.x86_64"

  # 5. The config changed, so its sha256 (and b2sum) from upstream are stale.
  #    Remove them; refresh_sums() puts correct values back.
  sed -i '/^sha256sums_x86_64=/d' "$PKGBUILD"
  sed -i '/^b2sums_x86_64=/d'   "$PKGBUILD"
}

refresh_sums() {
  require_cmd updpkgsums
  info "Regenerating checksums (sha256 + b2sum) for every source"
  ( cd "$PKGDIR" && updpkgsums )
}

verify_tarball_hash() {
  local ver="$1" want got
  want="$(tarball_sha256 "$ver")"
  [[ -n "$want" ]] || { yel "Warning: kernel.org has no sha256 entry for $ver"; return 0; }
  got="$(sed -n "/linux-$ver\.tar\.xz/ { s/^\(\S*\).*/\1/p; }" "$PKGBUILD" | head -1)"
  if [[ "$want" == "$got" ]]; then
    grn "Tarball sha256 for $ver matches kernel.org"
  else
    yel "Tarball sha256 mismatch for $ver (upstream recipe is authoritative)"
  fi
}

show_summary() {
  local ver; ver="$(current_ver)"
  info "Titan Linux kernel is pinned to 6.x longterm $ver"
  echo
  echo "  Files:  $PKGDIR"
  echo "  Build:  cd $PKGDIR && makepkg -s"
  echo "  Install: sudo pacman -U linux-titanlinux-*.pkg.tar.zst"
  echo
  echo "  Boot it:  sudo grub-mkconfig -o /boot/grub/grub.cfg"
  echo "  Verify:   uname -r   # expect: 6.x.y-titanlinux"
}

main() {
  local cur latest
  cur="$(current_ver)"
  [[ -n "$cur" ]] || { red "Could not read pkgver from $PKGBUILD"; exit 1; }

  info "Current pinned version: $cur"
  info "Querying kernel.org for the latest 6.x longterm"
  latest="$(latest_ver)"

  if [[ -z "$latest" ]]; then
    red "Could not determine the latest 6.x longterm release from kernel.org"
    exit 1
  fi
  info "Latest 6.x longterm:     $latest"

  if [[ "$latest" == "$cur" ]]; then
    grn "Already up to date ($cur)"
    [[ "$MODE" == "--check" ]] && exit 0
    show_summary
    return 0
  fi

  yel "Update available: $cur -> $latest"

  if [[ "$MODE" == "--check" ]]; then
    exit 2
  fi

  if [[ "$MODE" != "--apply" ]]; then
    read -r -p "Bump Titan Linux kernel to $latest? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { info "Aborted. Nothing was modified."; exit 0; }
  fi

  sync_from_arch  "$latest"
  apply_titan_deltas
  refresh_sums
  verify_tarball_hash "$latest"

  grn "Bumped to $latest"
  echo
  echo "Review the diff before building:"
  echo "  cd $(dirname "$(dirname "$PKGBUILD")") && git diff"
  echo
  show_summary
}

main "$@"
