#!/usr/bin/env bash
#
# shell-env — one-command zsh environment setup.
#
#     curl sh.pgj11.com | bash
#
# Turns a fresh Linux box into a modern, git-aware zsh CLI environment:
# zsh + Starship prompt + interactive plugins + a set of modern CLI tools,
# with dotfiles written from the heredocs embedded in this very file.
#
# Design notes:
#   - Self-contained: the source repo is private, so a fresh box cannot clone
#     it. Everything this script needs is baked in here; deployment is just
#     publishing this one file to sh.pgj11.com.
#   - Idempotent: safe to re-run; already-installed pieces are skipped.
#   - Pipe-safe: when run via `curl ... | bash` it never blocks on a prompt.
#   - Cross-distro (apt/dnf/pacman/zypper/apk) and cross-arch (x86_64/aarch64/
#     armv7). Falls back to user-local installs in ~/.local/bin without root.
#   - CLI-only: never touches GUI/desktop settings.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Output helpers (colour only on a real terminal, honouring NO_COLOR)
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
  C_RESET=''; C_BOLD=''; C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''
fi

info() { printf '%s\n' "${C_BLUE}::${C_RESET} $*"; }
step() { printf '\n%s\n' "${C_BOLD}${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
ok()   { printf '%s\n' "  ${C_GREEN}✓${C_RESET} $*"; }
skip() { printf '%s\n' "  ${C_GREEN}•${C_RESET} $*"; }
warn() { printf '%s\n' "  ${C_YELLOW}!${C_RESET} $*" >&2; }
err()  { printf '%s\n' "${C_RED}error:${C_RESET} $*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Environment detection
# ---------------------------------------------------------------------------
OS_ID="unknown"      # e.g. ubuntu, debian, fedora, arch, alpine, opensuse
OS_NAME="unknown"    # human-readable name
PKG=""               # apt|dnf|pacman|zypper|apk|yum  ("" = none detected)
ARCH=""              # x86_64|aarch64|armv7|armv6|<raw>
INTERACTIVE=0        # 1 if stdin is a terminal (so prompting is OK)
PRIV=none            # root|sudo|none
SUDO=""              # "" when root or unprivileged, "sudo" when escalating

detect_os() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
  fi
}

detect_pkg() {
  if   have apt-get; then PKG=apt
  elif have dnf;     then PKG=dnf
  elif have pacman;  then PKG=pacman
  elif have zypper;  then PKG=zypper
  elif have apk;     then PKG=apk
  elif have yum;     then PKG=yum
  else                    PKG=""
  fi
}

detect_arch() {
  local m; m="$(uname -m)"
  case "$m" in
    x86_64|amd64)       ARCH=x86_64 ;;
    aarch64|arm64)      ARCH=aarch64 ;;
    armv7l|armv7|armhf) ARCH=armv7 ;;
    armv6l)             ARCH=armv6 ;;
    *)                  ARCH="$m" ;;
  esac
}

detect_interactive() {
  if [ -t 0 ]; then INTERACTIVE=1; else INTERACTIVE=0; fi
}

# Decide whether we can install system packages. We only ever use sudo if it
# works without a password, or if we are interactive (so a single prompt is
# acceptable). When piped and non-root, we silently fall back to ~/.local/bin.
detect_privilege() {
  if [ "$(id -u)" -eq 0 ]; then
    PRIV=root; SUDO=""
  elif have sudo; then
    if sudo -n true 2>/dev/null; then
      PRIV=sudo; SUDO="sudo"
    elif [ "$INTERACTIVE" -eq 1 ]; then
      PRIV=sudo; SUDO="sudo"
    else
      PRIV=none; SUDO=""
    fi
  else
    PRIV=none; SUDO=""
  fi
}

# True when we have both a privilege path and a known package manager.
can_sys_install() { [ "$PRIV" != none ] && [ -n "$PKG" ]; }

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BIN_DIR="$HOME/.local/bin"

ensure_dirs() {
  mkdir -p "$BIN_DIR" "$HOME/.config"
  # Make sure user-local binaries are usable for the rest of this run.
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) PATH="$BIN_DIR:$PATH"; export PATH ;;
  esac
}

# ---------------------------------------------------------------------------
# Package manager helpers (only reached when can_sys_install is true)
# ---------------------------------------------------------------------------
# Run a command as root: directly when we already are root, via sudo otherwise.
as_root() {
  if [ -n "$SUDO" ]; then sudo "$@"; else "$@"; fi
}

PKG_REFRESHED=0
pkg_refresh() {
  [ "$PKG_REFRESHED" -eq 1 ] && return 0
  case "$PKG" in
    apt)     as_root env DEBIAN_FRONTEND=noninteractive apt-get update -y ;;
    pacman)  as_root pacman -Sy --noconfirm ;;
    zypper)  as_root zypper --non-interactive refresh ;;
    apk)     as_root apk update ;;
    dnf|yum) : ;;  # metadata is refreshed on demand
    *)       return 1 ;;
  esac
  PKG_REFRESHED=1
}

pkg_install() {
  pkg_refresh >/dev/null 2>&1 || true
  case "$PKG" in
    apt)    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" ;;
    dnf)    as_root dnf install -y "$@" ;;
    yum)    as_root yum install -y "$@" ;;
    pacman) as_root pacman -S --needed --noconfirm "$@" ;;
    zypper) as_root zypper --non-interactive install --no-recommends "$@" ;;
    apk)    as_root apk add "$@" ;;
    *)      return 1 ;;
  esac
}

# Map a logical tool name to the package name for the active package manager.
# An empty result means "not packaged here, use the download fallback instead".
pkg_for() {
  case "$1:$PKG" in
    vim:dnf|vim:yum)              echo vim-enhanced ;;
    vim:*)                        echo vim ;;
    fd:apt|fd:dnf|fd:yum)         echo fd-find ;;
    fd:*)                         echo fd ;;
    rg:*)                         echo ripgrep ;;
    delta:apk)                    echo delta ;;
    delta:*)                      echo git-delta ;;
    starship:apt|starship:dnf|starship:yum) echo "" ;;  # not packaged → download
    *)                            echo "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# Download helpers
# ---------------------------------------------------------------------------
dl() { curl -fsSL "$@"; }

# GitHub API GET, authenticated if GITHUB_TOKEN/GH_TOKEN is set (optional; only
# raises the anonymous 60-requests/hour rate limit on shared IPs).
gh_api() {
  local tok="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  if [ -n "$tok" ]; then
    curl -fsSL -H "Authorization: Bearer $tok" -H "X-GitHub-Api-Version: 2022-11-28" "$1"
  else
    curl -fsSL "$1"
  fi
}

# Asset-name fragments that identify the right Linux build for this arch.
arch_asset_regex() {
  case "$ARCH" in
    x86_64)  echo 'x86_64|amd64' ;;
    aarch64) echo 'aarch64|arm64' ;;
    armv7)   echo 'armv7|armhf|gnueabihf|musleabihf|arm-unknown-linux' ;;
    armv6)   echo 'armv6|gnueabi|arm-unknown-linux' ;;
    *)       echo "$ARCH" ;;
  esac
}

# Print the best matching Linux tarball URL from <repo>'s latest release.
# Prefers static musl builds; skips checksums, signatures, server/source,
# non-Linux, and no-libgit assets.
pick_release_tarball() {
  local repo="$1" arch_re cand musl
  arch_re="$(arch_asset_regex)"
  cand="$(gh_api "https://api.github.com/repos/$repo/releases/latest" \
          | grep -oE '"browser_download_url"[: ]+"[^"]+"' \
          | sed -E 's/.*"(https[^"]+)".*/\1/' \
          | grep -Ei 'linux' \
          | grep -Eiv 'android|\.sha[0-9]+|\.asc|\.sig|\.deb|\.rpm|\.msi|no_libgit|-server-|darwin|windows|\.zip$' \
          | grep -Ei "($arch_re)" \
          | grep -Ei '\.(tar\.(gz|xz|bz2)|tgz)$')" || true
  [ -z "$cand" ] && return 1
  musl="$(printf '%s\n' "$cand" | grep -i musl | head -n1)"
  if [ -n "$musl" ]; then printf '%s\n' "$musl"; else printf '%s\n' "$cand" | head -n1; fi
}

# Extract <archive> into <dir>, picking the right decompressor by extension.
extract_archive() {
  local f="$1" d="$2"
  case "$f" in
    *.tar.gz|*.tgz) tar -xzf "$f" -C "$d" ;;
    *.tar.xz)       tar -xJf "$f" -C "$d" ;;
    *.tar.bz2)      tar -xjf "$f" -C "$d" ;;
    *.tar)          tar -xf  "$f" -C "$d" ;;
    *.zip)          unzip_to "$f" "$d" ;;
    *)              return 1 ;;
  esac
}

# Extract a zip without assuming unzip is installed.
unzip_to() {
  local f="$1" d="$2"
  if   have unzip;   then unzip -qo "$f" -d "$d"
  elif have bsdtar;  then bsdtar -xf "$f" -C "$d"
  elif have python3; then ( cd "$d" && python3 -m zipfile -e "$f" . )
  else return 1
  fi
}

# Download a release tarball from <repo> and install binary <bin> into BIN_DIR.
install_from_github() {
  local repo="$1" bin="$2" url tmp file found
  url="$(pick_release_tarball "$repo")" || { warn "no $ARCH release asset for $repo"; return 1; }
  tmp="$(mktemp -d)" || return 1
  file="$tmp/${url##*/}"
  if ! dl "$url" -o "$file"; then rm -rf "$tmp"; return 1; fi
  if ! extract_archive "$file" "$tmp"; then rm -rf "$tmp"; warn "could not extract asset for $repo"; return 1; fi
  found="$(find "$tmp" -type f -name "$bin" -perm -100 2>/dev/null | head -n1)"
  [ -z "$found" ] && found="$(find "$tmp" -type f -name "$bin" 2>/dev/null | head -n1)"
  if [ -z "$found" ]; then rm -rf "$tmp"; warn "binary '$bin' not found in $repo asset"; return 1; fi
  install -m 0755 "$found" "$BIN_DIR/$bin"
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# Tool installation
# ---------------------------------------------------------------------------
# Package only (no usable single-binary fallback): zsh, git, curl, tmux, vim.
ensure_pkg_only() {
  local cmd="$1" tool="$2" p
  if have "$cmd"; then skip "$cmd"; return 0; fi
  if can_sys_install; then
    p="$(pkg_for "$tool")"
    if [ -n "$p" ] && pkg_install "$p" >/dev/null 2>&1 && have "$cmd"; then
      ok "$cmd (via $PKG)"; return 0
    fi
  fi
  warn "could not install $cmd (needs a package manager and privileges)"
  return 1
}

# Package first, GitHub release binary as fallback.
ensure_tool() {
  local cmd="$1" tool="$2" repo="$3" bin="$4" p
  if have "$cmd"; then skip "$cmd"; return 0; fi
  if can_sys_install; then
    p="$(pkg_for "$tool")"
    if [ -n "$p" ] && pkg_install "$p" >/dev/null 2>&1 && have "$cmd"; then
      ok "$cmd (via $PKG)"; return 0
    fi
  fi
  if install_from_github "$repo" "$bin" && have "$cmd"; then
    ok "$cmd (release binary)"; return 0
  fi
  warn "could not install $cmd"
  return 1
}

# bat: the Debian/Ubuntu package installs the binary as 'batcat'; link it to 'bat'.
ensure_bat() {
  if have bat; then skip "bat"; return 0; fi
  if can_sys_install; then pkg_install "$(pkg_for bat)" >/dev/null 2>&1 || true; fi
  if ! have bat && have batcat; then
    ln -sf "$(command -v batcat)" "$BIN_DIR/bat"; ok "bat (linked from batcat)"; return 0
  fi
  if have bat; then ok "bat (via $PKG)"; return 0; fi
  if install_from_github sharkdp/bat bat && have bat; then ok "bat (release binary)"; return 0; fi
  warn "could not install bat"; return 1
}

# fd: the Debian/Ubuntu package installs the binary as 'fdfind'; link it to 'fd'.
ensure_fd() {
  if have fd; then skip "fd"; return 0; fi
  if can_sys_install; then pkg_install "$(pkg_for fd)" >/dev/null 2>&1 || true; fi
  if ! have fd && have fdfind; then
    ln -sf "$(command -v fdfind)" "$BIN_DIR/fd"; ok "fd (linked from fdfind)"; return 0
  fi
  if have fd; then ok "fd (via $PKG)"; return 0; fi
  if install_from_github sharkdp/fd fd && have fd; then ok "fd (release binary)"; return 0; fi
  warn "could not install fd"; return 1
}

# bat-extras provides batman/batdiff/prettybat (used by the zsh aliases).
ensure_bat_extras() {
  if have batman && have batdiff && have prettybat; then skip "bat-extras"; return 0; fi
  if can_sys_install && [ "$PKG" = pacman ]; then pkg_install bat-extras >/dev/null 2>&1 || true; fi
  if have batman && have batdiff && have prettybat; then ok "bat-extras (via $PKG)"; return 0; fi
  local url tmp s f
  url="$(gh_api https://api.github.com/repos/eth-p/bat-extras/releases/latest \
        | grep -oE '"browser_download_url"[: ]+"[^"]+\.zip"' \
        | sed -E 's/.*"(https[^"]+)".*/\1/' | head -n1)" || true
  if [ -n "$url" ]; then
    tmp="$(mktemp -d)"
    if dl "$url" -o "$tmp/be.zip" && unzip_to "$tmp/be.zip" "$tmp"; then
      for s in batman batdiff prettybat batgrep batwatch batpipe; do
        f="$(find "$tmp" -type f -name "$s" 2>/dev/null | head -n1)"
        [ -n "$f" ] && install -m 0755 "$f" "$BIN_DIR/$s"
      done
    fi
    rm -rf "$tmp"
  fi
  if have batman || have batdiff || have prettybat; then ok "bat-extras (scripts)"; return 0; fi
  warn "bat-extras not installed (man/diff aliases will be skipped at runtime)"; return 1
}

install_tools() {
  step "Installing CLI tools"
  # Baseline (package manager only).
  ensure_pkg_only zsh  zsh  || true
  ensure_pkg_only git  git  || true
  ensure_pkg_only curl curl || true
  ensure_pkg_only tmux tmux || true
  ensure_pkg_only vim  vim  || true
  # Modern tools (package, else GitHub release binary).
  ensure_tool fzf      fzf      junegunn/fzf       fzf      || true
  ensure_tool zoxide   zoxide   ajeetdsouza/zoxide zoxide   || true
  ensure_tool atuin    atuin    atuinsh/atuin      atuin    || true
  ensure_tool rg       rg       BurntSushi/ripgrep rg       || true
  ensure_tool eza      eza      eza-community/eza  eza      || true
  ensure_tool delta    delta    dandavison/delta   delta    || true
  ensure_tool starship starship starship/starship  starship || true
  ensure_bat        || true
  ensure_fd         || true
  ensure_bat_extras || true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  detect_interactive
  detect_os
  detect_pkg
  detect_arch
  detect_privilege
  ensure_dirs

  step "shell-env installer"
  info "OS:           $OS_NAME ($OS_ID)"
  info "Package mgr:  ${PKG:-none detected}"
  info "Architecture: $ARCH (uname -m: $(uname -m))"
  info "Privilege:    $PRIV$([ -n "$SUDO" ] && echo " (via sudo)")"
  info "Mode:         $([ "$INTERACTIVE" -eq 1 ] && echo interactive || echo "non-interactive (piped)")"
  if can_sys_install; then
    info "Install path: system packages via $PKG${SUDO:+ (sudo)}, user-local fallback"
  else
    info "Install path: user-local (~/.local/bin) — no root/sudo or no package manager"
  fi

  install_tools
}

main "$@"
