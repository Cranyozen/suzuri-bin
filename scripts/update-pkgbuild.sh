#!/usr/bin/env bash
#
# Refresh pkgver and sha256sums in PKGBUILD from an upstream suzuri release.
#
# This script is deliberately self-contained so it can be run by hand:
#
#   ./scripts/update-pkgbuild.sh              # latest upstream release
#   ./scripts/update-pkgbuild.sh --force 0.5.4
#
# It writes "changed" and "version" to $GITHUB_OUTPUT when that is set (so the
# workflow can consume them) and always echoes them to stdout.
#
set -euo pipefail

REPO='harrywang/suzuri'
TAG_PREFIX='suzuri-v'
ASSET_PREFIX='suzuri-linux'
ARCHES=(x86_64 aarch64)

pkgbuild=${PKGBUILD_FILE:-PKGBUILD}

log() { printf '%s\n' "$*" >&2; }

set_output() {
  printf '%s=%s\n' "$1" "$2"
  if [[ -n ${GITHUB_OUTPUT:-} ]]; then
    printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
  fi
}

force=''
if [[ ${1:-} == --force ]]; then
  force=${2:-}
  [[ -n $force ]] || { log 'error: --force requires a version argument'; exit 2; }
elif [[ $# -gt 0 ]]; then
  log "error: unknown argument '$1'"; exit 2
fi

[[ -f $pkgbuild ]] || { log "error: $pkgbuild not found"; exit 1; }

current=$(sed -n 's/^pkgver=//p' "$pkgbuild" | head -1)
[[ -n $current ]] || { log "error: could not read pkgver from $pkgbuild"; exit 1; }

if [[ -n $force ]]; then
  target=$force
else
  # Follow the /releases/latest redirect instead of calling the API: no token
  # needed and it cannot hit the unauthenticated rate limit.
  effective=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/${REPO}/releases/latest")
  target=${effective##*/}
  target=${target#"$TAG_PREFIX"}
fi

# Guard against the redirect handing back an HTML page or an unexpected tag.
if [[ ! $target =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  log "error: resolved version '$target' does not look like a version"
  exit 1
fi

log "current pkgver: $current"
log "upstream target: $target"

if [[ $target == "$current" ]]; then
  log 'already up to date, nothing to do'
  set_output changed false
  set_output version "$current"
  exit 0
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

base="https://github.com/${REPO}/releases/download/${TAG_PREFIX}${target}"
declare -A sums
for arch in "${ARCHES[@]}"; do
  asset="${ASSET_PREFIX}-${arch}.tar.gz"
  log "downloading $asset"
  # A typo'd tag or a missing asset must fail loudly rather than produce a
  # PKGBUILD with a bogus checksum.
  curl -fsSL --retry 3 --retry-all-errors -o "$workdir/$arch.tar.gz" "$base/$asset"
  sums[$arch]=$(sha256sum "$workdir/$arch.tar.gz" | cut -d' ' -f1)
  log "  sha256 ${sums[$arch]}"
done

sed -i \
  -e "s|^pkgver=.*|pkgver=${target}|" \
  -e "s|^pkgrel=.*|pkgrel=1|" \
  -e "s|^sha256sums_x86_64=.*|sha256sums_x86_64=('${sums[x86_64]}')|" \
  -e "s|^sha256sums_aarch64=.*|sha256sums_aarch64=('${sums[aarch64]}')|" \
  "$pkgbuild"

log "updated $current -> $target"
set_output changed true
set_output version "$target"
