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
}

main "$@"
