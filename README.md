# LinuxEnv

[![CI](https://github.com/PeterGabaldon/LinuxEnv/actions/workflows/ci.yml/badge.svg)](https://github.com/PeterGabaldon/LinuxEnv/actions/workflows/ci.yml)

[![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?logo=ubuntu&logoColor=white)](https://github.com/PeterGabaldon/LinuxEnv/actions/workflows/ci.yml)
[![Debian](https://img.shields.io/badge/Debian-A81D33?logo=debian&logoColor=white)](https://github.com/PeterGabaldon/LinuxEnv/actions/workflows/ci.yml)
[![Fedora](https://img.shields.io/badge/Fedora-51A2DA?logo=fedora&logoColor=white)](https://github.com/PeterGabaldon/LinuxEnv/actions/workflows/ci.yml)
[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?logo=archlinux&logoColor=white)](https://github.com/PeterGabaldon/LinuxEnv/actions/workflows/ci.yml)
[![Alpine](https://img.shields.io/badge/Alpine-0D597F?logo=alpinelinux&logoColor=white)](https://github.com/PeterGabaldon/LinuxEnv/actions/workflows/ci.yml)

One command turns a fresh Linux box into my preferred **zsh** command-line
environment: a modern git-aware prompt, handy interactive zsh plugins, and a set
of modern CLI tools — no reboot, no manual steps.

```sh
curl sh.pgj11.com | bash
```

That's it. When it finishes, run `exec zsh` (or open a new terminal) and you're done.

## What gets installed

- **Shell:** `zsh`, set as the default login shell.
- **Prompt:** [Starship](https://starship.rs) — a fast, git-aware two-line prompt
  (`┌──(user@host)-[dir]` / `└─$`) that always shows branch, ahead/behind, and
  dirty/staged/stash/rebase state inside a repo.
- **zsh plugins:** `zsh-autosuggestions`, `fast-syntax-highlighting`, `fzf-tab`,
  and the oh-my-zsh `sudo` plugin.
- **CLI tools:** `fzf` (fuzzy finder), `zoxide` (smart `cd`), `atuin` (shell
  history), `bat` (`cat`) + bat-extras (`batman`/`batdiff`), `eza` (`ls`),
  `fd` (`find`), `ripgrep` (`grep`), `delta` (git pager), plus `tmux`, `vim`,
  `git`, and `curl`.
- **Dotfiles:** `~/.zshrc`, `~/.config/starship.toml`, `~/.tmux.conf` (tpm +
  gruvbox), `~/.vimrc` (with the afterglow colorscheme), all written from the
  script itself. Handy aliases: `ls`→`eza`, `cat`→`bat`, `man`→`batman`,
  `diff`→`batdiff`, and `cp`/`rm`/`mv` made interactive (`-i`).
- **Font:** Hack Nerd Font (so prompt/glyphs render correctly).

It is a **CLI-only** setup — it never touches GUI/desktop settings. Dark theme
throughout.

## Supported systems

- **Distros:** Debian/Ubuntu (`apt`), Fedora/RHEL (`dnf`/`yum`), Arch (`pacman`),
  openSUSE (`zypper`), Alpine (`apk`).
- **Architectures:** `x86_64` and `aarch64`/`armv7` (e.g. Raspberry Pi).
- **No root?** No problem. The modern CLI tools fall back to prebuilt release
  binaries dropped into `~/.local/bin`, and `chsh` is replaced by a guarded
  launcher appended to `~/.bashrc`/`~/.profile`. (`zsh`, `tmux`, `vim` and `git`
  still need a package manager; if one isn't reachable they're skipped with a
  warning and everything else proceeds.)

The script is **idempotent** (safe to re-run) and **pipe-safe** (never blocks on
a prompt when run via `curl … | bash`). Any existing dotfile is backed up to
`<file>.bak` once before being overwritten. Set `GITHUB_TOKEN` (optional) to lift
GitHub's anonymous API rate limit if you hit it while downloading release
binaries.

## What each tool does (and how to use it)

A closer look at everything the script sets up — why it's worth having, and the
one thing you need to know to start using it.

### Shell & prompt

- **`zsh`** — the shell the whole setup is built around: smarter completion,
  globbing, and prompt theming than bash. *Why:* it's the foundation the plugins
  and prompt plug into. *Usage:* it becomes your default login shell, so new
  terminals open in it — run `exec zsh` to switch immediately after installing.
- **Starship prompt** — a fast, two-line prompt that, inside a repo, always shows
  the branch plus ahead/behind and dirty/staged/stash/rebase state. *Why:* you
  always know your git state at a glance without running `git status`. *Usage:*
  it just appears; tweak it in `~/.config/starship.toml`.

### Interactive zsh plugins

- **`zsh-autosuggestions`** — suggests the rest of a command from your history as
  you type. *Why:* frequent commands become a single keystroke. *Usage:* press
  `→` (Right arrow) or `End` to accept the greyed-out suggestion.
- **`fast-syntax-highlighting`** — colours the command line as you type. *Why:*
  typos and unknown commands turn red **before** you hit Enter. *Usage:*
  automatic — green means valid, red means not found.
- **`fzf-tab`** — replaces the tab-completion menu with an `fzf` fuzzy picker.
  *Why:* completing long paths and options becomes a quick search-and-pick.
  *Usage:* press `Tab`, then type to filter and `Enter` to select.
- **`sudo` plugin** — re-runs the current/previous command with `sudo`. *Why:* no
  retyping when a command needs root. *Usage:* press `Esc` twice to toggle `sudo`
  at the front of the line.

### Modern CLI tools

- **`fzf`** — a general-purpose fuzzy finder powering interactive search. *Why:*
  one fast picker for history, files, and directories. *Usage:* `Ctrl-R`
  (history), `Ctrl-T` (insert a file path), `Alt-C` (cd into a subdir); or pipe
  anything into `fzf`.
- **`zoxide`** — a smarter `cd` that learns the directories you visit. *Why:* jump
  to a directory by a fragment of its name instead of typing the full path.
  *Usage:* `z proj` jumps to your most-used `…/project`; `zi` picks interactively.
- **`atuin`** — replaces shell history with a searchable database that also records
  exit code, duration, and directory. *Why:* a far richer, fuzzy-searchable
  history. *Usage:* press `Ctrl-R` (or `Up`) for the full-screen history search.
- **`bat`** — `cat` with syntax highlighting, line numbers, and git change markers.
  *Why:* reading files in the terminal is much clearer. *Usage:* `bat file.py`
  (aliased to `cat`).
- **`bat-extras`** — wrappers that bring bat's highlighting to other commands:
  `batman`, `batdiff`, `prettybat`. *Why:* nicer man pages and diffs. *Usage:*
  `man ls` and `diff a b` are aliased to these.
- **`eza`** — a modern `ls` with colours, icons, a tree view, and inline git
  status. *Why:* far more readable directory listings. *Usage:* `ls`, `ll`
  (long), `la` (long + hidden), `lt`/`tree` (tree view) — all aliased to eza.
- **`fd`** — a faster, friendlier `find` with sane defaults. *Why:* simple syntax
  that skips `.gitignore`/hidden files automatically. *Usage:* `fd pattern`, or
  `fd -e py` to filter by extension.
- **`ripgrep` (`rg`)** — an extremely fast recursive grep that respects
  `.gitignore`. *Why:* search a whole tree in milliseconds. *Usage:* `rg "TODO"`,
  or `rg -t py foo` to limit to Python files.
- **`delta`** — a syntax-highlighting pager for git diffs. *Why:* readable,
  line-numbered (and side-by-side) diffs. *Usage:* configured as git's pager, so
  `git diff` and `git log -p` just look better.
- **`tmux`** — a terminal multiplexer: split panes, windows, and sessions that
  survive disconnects. *Why:* indispensable over SSH and for multitasking.
  *Usage:* prefix is `Ctrl-a`; start with `tmux`, then `Ctrl-a %` / `Ctrl-a "` to
  split. Ships with tpm + the gruvbox theme pre-loaded.
- **`vim`** — the editor, set as `$EDITOR`/`$VISUAL` with the afterglow dark
  colorscheme. *Usage:* `vim file`.
- **`git` / `curl`** — baseline tooling the rest relies on (cloning plugins,
  downloading release binaries).

### Quality-of-life extras

- **Safety aliases** — `cp`, `rm`, and `mv` run in interactive (`-i`) mode. *Why:*
  you're prompted before overwriting or deleting a file. *Usage:* automatic.
- **Hack Nerd Font** — supplies the glyphs the prompt and eza icons expect. *Why:*
  icons and prompt symbols render correctly. *Usage:* set your terminal font to
  "Hack Nerd Font".

## Continuous integration

Every push and pull request runs [`.github/workflows/ci.yml`](.github/workflows/ci.yml):

- **Lint:** `shellcheck` and a `bash -n` syntax check of `install.sh`.
- **Cross-distro install:** the installer runs to completion (as root) in fresh
  Ubuntu, Debian, Fedora, Arch, and Alpine containers, then the workflow asserts
  the dotfiles were written, the core tools are on `PATH`, and the generated
  `~/.zshrc` and `starship.toml` parse.

## How deployment works

`install.sh` is fully **self-contained** — every dotfile is embedded in the
script itself, so a fresh box needs nothing but this one file (no repo checkout,
no extra config downloads).

`sh.pgj11.com` is simply a redirect to the raw contents of `install.sh` on
GitHub, so `curl sh.pgj11.com | bash` always fetches the latest committed
version. This repo is the source of truth; pushing a change to `install.sh` is
the deploy.
