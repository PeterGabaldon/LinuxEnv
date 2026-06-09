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
#   - Self-contained: every dotfile is embedded below, so a fresh box needs
#     nothing but this single file. sh.pgj11.com redirects to its raw contents
#     on GitHub.
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
ZSH_PLUGIN_DIR="$HOME/.config/zsh/plugins"

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
    xz:apt)                       echo xz-utils ;;
    xz:*)                         echo xz ;;
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

# GNU tar's -J shells out to the external `xz` binary, which minimal images
# (e.g. the ubuntu Docker image) omit — without it `tar -xJf` fails. Make sure
# it is present, installing xz-utils when we can.
ensure_xz() {
  have xz && return 0
  if can_sys_install; then pkg_install "$(pkg_for xz)" >/dev/null 2>&1 || true; fi
  have xz
}

# Extract <archive> into <dir>, picking the right decompressor by extension.
extract_archive() {
  local f="$1" d="$2"
  case "$f" in
    *.tar.gz|*.tgz) tar -xzf "$f" -C "$d" ;;
    *.tar.xz)       ensure_xz && tar -xJf "$f" -C "$d" ;;
    *.tar.bz2)      tar -xjf "$f" -C "$d" ;;
    *.tar)          tar -xf  "$f" -C "$d" ;;
    *.zip)          unzip_to "$f" "$d" ;;
    *)              return 1 ;;
  esac
}

# Extract a zip without assuming unzip is installed.
unzip_to() {
  local f="$1" d="$2"
  # Minimal images (e.g. the ubuntu Docker image) ship none of these; install
  # unzip when we have package-manager access so .zip assets still extract.
  if ! have unzip && ! have bsdtar && ! have python3 && can_sys_install; then
    pkg_install unzip >/dev/null 2>&1 || true
  fi
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
# zsh plugins (git-cloned into ~/.config/zsh/plugins, sourced from ~/.zshrc)
# ---------------------------------------------------------------------------
clone_or_update() {
  local url="$1" dest="$2" name; name="$(basename "$dest")"
  if [ -d "$dest/.git" ]; then
    git -C "$dest" pull --ff-only --quiet 2>/dev/null || true
    skip "$name (already cloned)"
  elif git clone --depth 1 --quiet "$url" "$dest" 2>/dev/null; then
    ok "$name"
  else
    warn "could not clone $name from $url"
    return 1
  fi
}

# The oh-my-zsh sudo plugin is a single self-contained file.
ensure_sudo_plugin() {
  local f="$ZSH_PLUGIN_DIR/sudo/sudo.plugin.zsh"
  if [ -f "$f" ]; then skip "sudo plugin"; return 0; fi
  mkdir -p "$(dirname "$f")"
  if dl https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/plugins/sudo/sudo.plugin.zsh -o "$f"; then
    ok "sudo plugin"
  else
    rm -f "$f"
    warn "could not download oh-my-zsh sudo plugin"
    return 1
  fi
}

install_plugins() {
  step "Installing zsh plugins"
  if ! have git; then
    warn "git is unavailable; skipping zsh plugins"
    return 0
  fi
  mkdir -p "$ZSH_PLUGIN_DIR"
  clone_or_update https://github.com/zsh-users/zsh-autosuggestions             "$ZSH_PLUGIN_DIR/zsh-autosuggestions"      || true
  clone_or_update https://github.com/zdharma-continuum/fast-syntax-highlighting "$ZSH_PLUGIN_DIR/fast-syntax-highlighting" || true
  clone_or_update https://github.com/Aloxaf/fzf-tab                             "$ZSH_PLUGIN_DIR/fzf-tab"                  || true
  ensure_sudo_plugin || true
}

# ---------------------------------------------------------------------------
# Dotfiles (written from the heredocs below; existing files backed up once)
# ---------------------------------------------------------------------------
# Display a path with $HOME collapsed to ~.
tilde() { printf '%s' "${1/#$HOME/~}"; }

# Back up <file> to <file>.bak, but only the first time (so re-runs never
# overwrite the user's original backup with our generated content).
backup_once() {
  local f="$1"
  if [ -e "$f" ] && [ ! -e "$f.bak" ]; then
    cp -p "$f" "$f.bak"
    info "backed up $(tilde "$f") -> $(tilde "$f").bak"
  fi
}

# Write stdin to <file>, creating parent dirs and backing up any existing file.
put_file() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  backup_once "$dest"
  cat > "$dest"
  ok "wrote $(tilde "$dest")"
}

write_zshrc() {
  put_file "$HOME/.zshrc" <<'ZSHRC'
# ~/.zshrc — generated by shell-env (https://sh.pgj11.com)
# Modern, git-aware zsh environment. Dark theme, CLI-focused.

# --- PATH -------------------------------------------------------------------
# User-local binaries (where shell-env installs tools when there is no root).
export PATH="$HOME/.local/bin:$PATH"

# --- Environment ------------------------------------------------------------
export EDITOR="vim"
export VISUAL="vim"
# Dark themes for tools that support theming.
# Afterglow matches the Vim colorscheme (installed into bat's themes dir).
export BAT_THEME="Afterglow"
export FZF_DEFAULT_OPTS="--color=dark --height=40% --layout=reverse --border"

# --- History ----------------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY          # share history across running sessions
setopt HIST_IGNORE_ALL_DUPS   # drop older duplicate entries
setopt HIST_IGNORE_SPACE      # don't record commands starting with a space
setopt HIST_REDUCE_BLANKS     # trim superfluous blanks
setopt EXTENDED_HISTORY       # record timestamps
setopt APPEND_HISTORY INC_APPEND_HISTORY

# --- Completion -------------------------------------------------------------
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'   # case-insensitive
zstyle ':completion:*' menu no                              # let fzf-tab take over
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# --- Key bindings -----------------------------------------------------------
bindkey -e                                  # emacs-style keymap
# Plain Left/Right move one character. zle may switch the terminal into
# application cursor mode (common in WSL/tmux), where the arrows send ^[O{C,D}
# instead of ^[[{C,D}, so bind both forms — otherwise the plain arrows would
# fall through to the word-movement binding below.
bindkey '^[[C'    forward-char              # Right
bindkey '^[[D'    backward-char             # Left
bindkey '^[OC'    forward-char
bindkey '^[OD'    backward-char
bindkey '^[[1;5C' forward-word              # Ctrl-Right: next word
bindkey '^[[1;5D' backward-word             # Ctrl-Left:  previous word
bindkey '^[[H'    beginning-of-line         # Home
bindkey '^[[F'    end-of-line               # End
bindkey '^[[3~'   delete-char               # Delete

# --- Prompt & tool initialisation ------------------------------------------
command -v starship >/dev/null && eval "$(starship init zsh)"
command -v zoxide   >/dev/null && eval "$(zoxide init zsh)"

# fzf key bindings & completion (modern fzf supports `fzf --zsh`).
if command -v fzf >/dev/null; then
  if fzf --zsh >/dev/null 2>&1; then
    source <(fzf --zsh)
  else
    for _f in /usr/share/fzf/key-bindings.zsh /usr/share/doc/fzf/examples/key-bindings.zsh \
              /usr/share/fzf/completion.zsh   /usr/share/doc/fzf/examples/completion.zsh \
              "$HOME/.fzf.zsh"; do
      [ -r "$_f" ] && source "$_f"
    done
    unset _f
  fi
fi

# atuin (shell history) — Ctrl-R only; --disable-up-arrow leaves the Up arrow
# on zsh's normal per-line history instead of atuin's full-screen search.
command -v atuin >/dev/null && eval "$(atuin init zsh --disable-up-arrow)"

# --- Plugins (order matters; fast-syntax-highlighting MUST be sourced last) -
ZSH_PLUGINS="$HOME/.config/zsh/plugins"
_src() { [ -r "$1" ] && source "$1"; }
_src "$ZSH_PLUGINS/zsh-autosuggestions/zsh-autosuggestions.zsh"
_src "$ZSH_PLUGINS/sudo/sudo.plugin.zsh"
_src "$ZSH_PLUGINS/fzf-tab/fzf-tab.plugin.zsh"
_src "$ZSH_PLUGINS/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"
unset -f _src

# fast-syntax-highlighting tints existing-path arguments (e.g. the /etc/passwd
# in `vim /etc/passwd`) magenta by default — `path` for files, `path-to-dir`
# for directories. Recolour both to a neutral light grey that matches the
# prompt's path colour, underlined so a valid path is still obvious while you
# type. F-Sy-H reads styles under the active theme prefix (FAST_THEME_NAME,
# "default" out of the box), so the live keys are `default…`; set both the
# prefixed and bare forms so the override always applies.
typeset -gA FAST_HIGHLIGHT_STYLES
FAST_HIGHLIGHT_STYLES[path]='fg=#d3d7cf,underline'
FAST_HIGHLIGHT_STYLES[defaultpath]='fg=#d3d7cf,underline'
FAST_HIGHLIGHT_STYLES[path-to-dir]='fg=#d3d7cf,underline'
FAST_HIGHLIGHT_STYLES[defaultpath-to-dir]='fg=#d3d7cf,underline'

# --- Aliases ----------------------------------------------------------------
# Safety: prompt before clobbering existing files.
alias cp='cp -i'
alias rm='rm -i'
alias mv='mv -i'

# eza replaces ls (icons require the installed Nerd Font).
if command -v eza >/dev/null; then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -lh  --group-directories-first --icons=auto --git'
  alias la='eza -lah --group-directories-first --icons=auto --git'
  alias lt='eza --tree --level=2 --icons=auto'
  alias tree='eza --tree --icons=auto'
fi

# bat replaces cat; bat-extras replace man/diff (only if present).
command -v bat       >/dev/null && alias cat='bat'
command -v batman    >/dev/null && alias man='batman'
command -v batdiff   >/dev/null && alias diff='batdiff'
command -v prettybat >/dev/null && alias pretty='prettybat'
ZSHRC
}

write_starship() {
  put_file "$HOME/.config/starship.toml" <<'STARSHIP'
"$schema" = 'https://starship.rs/config-schema.json'

# Gruvbox Rainbow segments wrapped in a two-line, Kali-style frame:
#   ┌──  <os user>  <dir>  <git>  <langs>  <docker/conda>  <time>
#   └─$
# The powerline glyphs and the `└─$` pointer (instead of the usual arrow)
# require a Nerd Font — the installer sets up UbuntuMono Nerd Font for this.

format = """
[┌──](bold color_path)\
[](color_id)\
[󰌽](bold fg:#ffffff bg:color_id)\
$username\
$hostname\
[](bg:color_path fg:color_id)\
$directory\
[](fg:color_path bg:color_aqua)\
$git_branch\
$git_status\
[](fg:color_aqua bg:color_blue)\
$c\
$cpp\
$rust\
$golang\
$nodejs\
$bun\
$php\
$java\
$kotlin\
$haskell\
$python\
[](fg:color_blue bg:color_bg3)\
$docker_context\
$conda\
$pixi\
[](fg:color_bg3 bg:color_bg1)\
$time\
[ ](fg:color_bg1)\
$line_break\
[└─](bold color_path)$character"""

palette = 'gruvbox_dark'

[palettes.gruvbox_dark]
color_fg0 = '#fbf1c7'
color_bg1 = '#3c3836'
color_bg3 = '#665c54'
color_blue = '#458588'
color_aqua = '#689d6a'
color_green = '#98971a'
color_orange = '#d65d0e'
color_purple = '#b16286'
color_red = '#cc241d'
color_yellow = '#d79921'
color_id = '#3465a4'      # username@host box + $ prompt (Tango sky blue)
color_path = '#d3d7cf'    # path box + frame lines (Tango aluminium)

[username]
show_always = true
style_user = "bold fg:#ffffff bg:color_id"
style_root = "bold fg:#ffffff bg:color_id"
format = '[ $user]($style)'

[hostname]
ssh_only = false
style = "bold fg:#ffffff bg:color_id"
format = '[@$hostname ]($style)'

[directory]
style = "fg:color_bg1 bg:color_path"
format = "[ $path ]($style)"
truncation_length = 0      # 0 = show the full working-directory path
truncate_to_repo = false

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = "󰝚 "
"Pictures" = " "
"Developer" = "󰲋 "

[git_branch]
symbol = ""
style = "bg:color_aqua"
format = '[[ $symbol $branch ](fg:color_fg0 bg:color_aqua)]($style)'

[git_status]
style = "bg:color_aqua"
format = '[[($all_status$ahead_behind )](fg:color_fg0 bg:color_aqua)]($style)'

[nodejs]
symbol = ""
style = "bg:color_blue"
format = '[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)'

[bun]
symbol = ""
style = "bg:color_blue"
format = '[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)'

[c]
symbol = " "
style = "bg:color_blue"
format = '[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)'

[cpp]
symbol = " "
style = "bg:color_blue"
format = '[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)'

[rust]
symbol = ""
style = "bg:color_blue"
format = '[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)'

[golang]
symbol = ""
style = "bg:color_blue"
format = '[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)'

[php]
symbol = ""
style = "bg:color_blue"
format = '[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)'

[java]
symbol = ""
style = "bg:color_blue"
format = '[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)'

[kotlin]
symbol = ""
style = "bg:color_blue"
format = '[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)'

[haskell]
symbol = ""
style = "bg:color_blue"
format = '[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)'

[python]
symbol = ""
style = "bg:color_blue"
format = '[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)'

[docker_context]
symbol = ""
style = "bg:color_bg3"
format = '[[ $symbol( $context) ](fg:#83a598 bg:color_bg3)]($style)'

[conda]
style = "bg:color_bg3"
format = '[[ $symbol( $environment) ](fg:#83a598 bg:color_bg3)]($style)'

[pixi]
style = "bg:color_bg3"
format = '[[ $symbol( $version)( $environment) ](fg:color_fg0 bg:color_bg3)]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:color_bg1"
format = '[[  $time ](fg:color_fg0 bg:color_bg1)]($style)'

[line_break]
disabled = false

# `$` instead of the usual arrow, on the `└─` line (Kali-style).
[character]
disabled = false
success_symbol = '[\$](bold fg:color_id)'
error_symbol = '[\$](bold fg:color_red)'
vimcmd_symbol = '[\$](bold fg:color_id)'
vimcmd_replace_one_symbol = '[\$](bold fg:color_purple)'
vimcmd_replace_symbol = '[\$](bold fg:color_purple)'
vimcmd_visual_symbol = '[\$](bold fg:color_yellow)'
STARSHIP
}

write_tmux() {
  put_file "$HOME/.tmux.conf" <<'TMUXCONF'
# remap prefix to Control + a
set -g prefix C-a
bind C-a send-prefix
unbind C-b
setw -g mode-keys vi

# Use a 256-colour terminal and force 24-bit "true colour" through to it for any
# outer $TERM (under WSL it can be a bare "xterm", so a name-specific override
# misses it — use the "*" wildcard). Without this the gruvbox theme's hex colours
# get crushed to a few ANSI colours and render red/orange instead of gruvbox.
set -g default-terminal "screen-256color"
set -ag terminal-overrides ",*:RGB"
# NOTE: no manual status-bg/status-fg here — the gruvbox theme styles the whole
# status line itself; overriding them left a grey gap in the bar.

# tpm
# List of plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'egel/tmux-gruvbox'
set -g @tmux-gruvbox 'dark'

# Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
run '~/.tmux/plugins/tpm/tpm'
TMUXCONF
  # tpm + the listed plugins, pre-cloned so they load without a manual prefix+I.
  if have git; then
    clone_or_update https://github.com/tmux-plugins/tpm           "$HOME/.tmux/plugins/tpm"           || true
    clone_or_update https://github.com/tmux-plugins/tmux-sensible "$HOME/.tmux/plugins/tmux-sensible" || true
    clone_or_update https://github.com/egel/tmux-gruvbox          "$HOME/.tmux/plugins/tmux-gruvbox"  || true
  fi
}

write_vim() {
  put_file "$HOME/.vimrc" <<'VIMRC'
syntax on
set tabstop=4
set nolist
set hlsearch
set incsearch
set number

" --- afterglow colorscheme --------------------------------------------------
" afterglow only defines its palette inside a `has('gui_running') ||
" &t_Co == 88 || &t_Co == 256` guard, so a terminal that doesn't advertise 256
" colours (common under tmux/WSL) leaves Vim unthemed. Force 256 colours, and
" switch on 24-bit true colour when the terminal reports it for the full range.
set t_Co=256
if has('termguicolors') && ($COLORTERM ==# 'truecolor' || $COLORTERM ==# '24bit')
  set termguicolors
endif
" Must be set BEFORE `colorscheme` or it is ignored (lets the terminal
" background show through instead of afterglow's own dark background).
let g:afterglow_inherit_background=1
colorscheme afterglow
VIMRC
  mkdir -p "$HOME/.vim/colors"
  if [ -f "$HOME/.vim/colors/afterglow.vim" ]; then
    skip "afterglow colorscheme"
  elif dl https://raw.githubusercontent.com/danilo-augusto/vim-afterglow/master/colors/afterglow.vim \
        -o "$HOME/.vim/colors/afterglow.vim"; then
    ok "afterglow colorscheme"
  else
    rm -f "$HOME/.vim/colors/afterglow.vim"
    warn "could not download afterglow colorscheme"
  fi
}

# Afterglow theme for bat — the Sublime .tmTheme the Vim colorscheme is based
# on, so `cat` (bat) shares Vim's palette. Dropped into bat's themes dir and
# compiled into its cache; selected via BAT_THEME="Afterglow" in ~/.zshrc.
install_bat_theme() {
  local bat_cmd themes_dir f
  bat_cmd="$(command -v bat || command -v batcat || true)"
  if [ -z "$bat_cmd" ]; then
    warn "bat is unavailable; skipping Afterglow bat theme"
    return 1
  fi
  themes_dir="$("$bat_cmd" --config-dir 2>/dev/null)/themes" || true
  case "$themes_dir" in /themes) themes_dir="$HOME/.config/bat/themes" ;; esac
  f="$themes_dir/Afterglow.tmTheme"
  mkdir -p "$themes_dir"
  if [ -f "$f" ]; then
    skip "Afterglow bat theme"
  elif dl https://raw.githubusercontent.com/YabataDesign/afterglow-theme/master/Afterglow.tmTheme -o "$f"; then
    ok "Afterglow bat theme"
  else
    rm -f "$f"
    warn "could not download Afterglow bat theme"
    return 1
  fi
  # Rebuild bat's theme cache so BAT_THEME="Afterglow" resolves.
  "$bat_cmd" cache --build >/dev/null 2>&1 || true
}

# UbuntuMono Nerd Font — provides the glyphs the prompt and eza icons expect.
install_font() {
  local fdir="$HOME/.local/share/fonts" url tmp
  if find "$fdir" -iname 'UbuntuMonoNerdFont*Regular*.ttf' 2>/dev/null | grep -q .; then
    skip "UbuntuMono Nerd Font"; return 0
  fi
  url="$(gh_api https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest \
        | grep -oE '"browser_download_url"[: ]+"[^"]+/UbuntuMono\.tar\.xz"' \
        | sed -E 's/.*"(https[^"]+)".*/\1/' | head -n1)" || true
  if [ -z "$url" ]; then warn "could not find UbuntuMono Nerd Font release asset"; return 1; fi
  if ! ensure_xz; then
    warn "could not install UbuntuMono Nerd Font (xz is unavailable to extract .tar.xz)"
    return 1
  fi
  mkdir -p "$fdir"
  tmp="$(mktemp -d)"
  if dl "$url" -o "$tmp/UbuntuMono.tar.xz" && tar -xJf "$tmp/UbuntuMono.tar.xz" -C "$fdir" 2>/dev/null; then
    ok "UbuntuMono Nerd Font"
    if have fc-cache; then fc-cache -f "$fdir" >/dev/null 2>&1 || true; fi
  else
    warn "could not install UbuntuMono Nerd Font"
  fi
  rm -rf "$tmp"
}

install_dotfiles() {
  step "Writing dotfiles"
  write_zshrc
  write_starship
  write_tmux
  write_vim
  install_bat_theme
  install_font
}

# ---------------------------------------------------------------------------
# Default shell
# ---------------------------------------------------------------------------
# The login shell currently recorded for this user in the passwd database.
current_login_shell() {
  local u; u="${USER:-$(id -un)}"
  if have getent; then
    getent passwd "$u" 2>/dev/null | awk -F: '{print $NF}'
  else
    awk -F: -v u="$u" '$1==u {print $NF}' /etc/passwd 2>/dev/null
  fi
}

# chsh refuses shells that are not listed in /etc/shells; add it if we can.
ensure_in_etc_shells() {
  local sh="$1"
  [ -r /etc/shells ] || return 0
  grep -qxF "$sh" /etc/shells 2>/dev/null && return 0
  if [ "$PRIV" = root ]; then
    printf '%s\n' "$sh" >> /etc/shells
  elif [ -n "$SUDO" ]; then
    printf '%s\n' "$sh" | sudo tee -a /etc/shells >/dev/null 2>&1 || true
  fi
}

# Try to change the login shell without ever blocking when piped.
try_chsh() {
  local sh="$1" u; u="${USER:-$(id -un)}"
  if [ "$PRIV" = root ]; then
    chsh -s "$sh" "$u" >/dev/null 2>&1
  elif [ -n "$SUDO" ] && sudo -n true 2>/dev/null; then
    sudo chsh -s "$sh" "$u" >/dev/null 2>&1
  elif [ "$INTERACTIVE" -eq 1 ]; then
    chsh -s "$sh" >/dev/null 2>&1
  else
    return 1
  fi
}

# Fallback when chsh is unavailable: hand off to zsh from the bash startup files
# for interactive shells only (guarded, idempotent, harmless to scripts).
add_exec_zsh_guard() {
  local marker="# >>> shell-env: launch zsh >>>" f
  for f in "$HOME/.bashrc" "$HOME/.profile"; do
    if [ -f "$f" ] && grep -qF "$marker" "$f" 2>/dev/null; then
      skip "zsh launcher already present in $(tilde "$f")"; continue
    fi
    backup_once "$f"
    # The single-quoted lines are written verbatim into the rc file on purpose.
    # shellcheck disable=SC2016
    {
      printf '\n%s\n' "$marker"
      printf '%s\n' 'if [ -z "$ZSH_VERSION" ] && command -v zsh >/dev/null 2>&1; then'
      printf '%s\n' '  case $- in *i*) exec zsh ;; esac'
      printf '%s\n' 'fi'
      printf '%s\n' "# <<< shell-env: launch zsh <<<"
    } >> "$f"
    ok "added zsh launcher to $(tilde "$f")"
  done
}

DEFAULT_SHELL_NOTE=""   # message appended to the final summary
set_default_shell() {
  step "Setting zsh as the default shell"
  local zsh_path; zsh_path="$(command -v zsh 2>/dev/null || true)"
  if [ -z "$zsh_path" ]; then
    warn "zsh is not installed; skipping default-shell change"
    return 0
  fi
  if [ "$(current_login_shell)" = "$zsh_path" ]; then
    skip "zsh is already the default shell"
    return 0
  fi
  ensure_in_etc_shells "$zsh_path"
  if try_chsh "$zsh_path"; then
    ok "default shell changed to $zsh_path"
    DEFAULT_SHELL_NOTE="Your default shell is now zsh (takes effect on next login)."
  else
    warn "couldn't run chsh here; using a startup-file launcher instead"
    add_exec_zsh_guard "$zsh_path"
    DEFAULT_SHELL_NOTE="zsh will start automatically from your existing shell (chsh was unavailable)."
  fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
  step "All done — no reboot needed"
  info "Start your new shell now with:  ${C_BOLD}exec zsh${C_RESET}"
  info "…or simply open a new terminal."
  [ -n "$DEFAULT_SHELL_NOTE" ] && info "$DEFAULT_SHELL_NOTE"
  info "Tip: terminal glyphs need a Nerd Font — set your terminal to \"UbuntuMono Nerd Font Mono\"."
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

  local mode="non-interactive (piped)" priv="$PRIV"
  if [ "$INTERACTIVE" -eq 1 ]; then mode="interactive"; fi
  if [ -n "$SUDO" ]; then priv="$priv (via sudo)"; fi

  step "LinuxEnv installer"
  info "OS:           $OS_NAME ($OS_ID)"
  info "Package mgr:  ${PKG:-none detected}"
  info "Architecture: $ARCH (uname -m: $(uname -m))"
  info "Privilege:    $priv"
  info "Mode:         $mode"
  if can_sys_install; then
    info "Install path: system packages via $PKG${SUDO:+ (sudo)}, user-local fallback"
  else
    info "Install path: user-local (~/.local/bin) — no root/sudo or no package manager"
  fi

  install_tools
  install_plugins
  install_dotfiles
  set_default_shell
  print_summary
}

main "$@"
