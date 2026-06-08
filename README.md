# shell-env

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
  (`┌──(user)-[dir]` / `└─$`) that always shows branch + ahead/behind + dirty state.
- **zsh plugins:** `zsh-autosuggestions`, `fast-syntax-highlighting`, `fzf-tab`,
  and the oh-my-zsh `sudo` plugin.
- **CLI tools:** `fzf` (fuzzy finder), `zoxide` (smart `cd`), `atuin` (shell
  history), `bat` (`cat`), `eza` (`ls`), `fd` (`find`), `ripgrep` (`grep`),
  `delta` (git pager), plus `tmux`, `vim`, `git`, and `curl`.
- **Dotfiles:** `~/.zshrc`, `~/.config/starship.toml`, `~/.tmux.conf`, `~/.vimrc`
  (with the afterglow colorscheme), all written from the script itself.
- **Font:** Hack Nerd Font (so prompt/glyphs render correctly).

It is a **CLI-only** setup — it never touches GUI/desktop settings. Dark theme
throughout.

## Supported systems

- **Distros:** Debian/Ubuntu (`apt`), Fedora/RHEL (`dnf`), Arch (`pacman`),
  openSUSE (`zypper`), Alpine (`apk`).
- **Architectures:** `x86_64` and `aarch64`/`armv7` (e.g. Raspberry Pi).
- **No root?** No problem. If neither root nor `sudo` is available, tools are
  installed user-locally into `~/.local/bin` and the script proceeds.

The script is **idempotent** (safe to re-run) and **pipe-safe** (never blocks on
a prompt when run via `curl … | bash`). Any existing dotfile is backed up to
`<file>.bak` once before being overwritten.

## Inspect before you run

Piping a script straight into a shell is convenient but you should read it first.
Download and review it, then run it:

```sh
curl -fsSL sh.pgj11.com -o install.sh
less install.sh        # read it
bash install.sh        # run it once you're happy
```

## How deployment works

This repository is **private**, so a fresh box can't clone it and
`raw.githubusercontent.com` won't work without credentials. To keep
`curl sh.pgj11.com | bash` credential-free, `install.sh` is fully
**self-contained** — every dotfile is embedded in the script itself.

Deployment is just publishing that one file: the contents of `install.sh` are
served at `sh.pgj11.com` as plain text. This repo is the editing/source home;
whenever `install.sh` changes, it gets re-published to that endpoint.
