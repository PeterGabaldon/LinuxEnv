# LinuxEnv

[![CI](https://github.com/PeterGabaldon/LinuxEnv/actions/workflows/ci.yml/badge.svg)](https://github.com/PeterGabaldon/LinuxEnv/actions/workflows/ci.yml)

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

## Inspect before you run

Piping a script straight into a shell is convenient but you should read it first.
Download and review it, then run it:

```sh
curl -fsSL sh.pgj11.com -o install.sh
less install.sh        # read it
bash install.sh        # run it once you're happy
```

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
