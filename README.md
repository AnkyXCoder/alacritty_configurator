# alacritty-configure

A question-driven wizard for configuring [Alacritty](https://alacritty.org/).
Answer a series of single-keystroke questions — font, theme, opacity, cursor,
keybindings, and more — and get a clean, split `~/.config/alacritty/` config
tree written out for you.

## Usage

```sh
./tools/alacritty/alacritty-configure
```

- **Arrow keys / j/k** move the highlight in a menu, live-previewing each option.
- **Number keys** jump straight to that option.
- **Enter** accepts the highlighted/typed value.
- **b** goes back a step, **r** restarts the wizard, **q** quits (with confirmation).
- For numeric steps (font size), use **+/-** to adjust.

At the end you'll see a review screen summarizing every choice before anything
is written to disk.

### Live preview

If you run the wizard **from inside a running Alacritty window**, most
choices (font, size, theme, cursor, opacity, padding) are pushed live to that
window via `alacritty msg config` so you can see the real effect before
committing. Outside of Alacritty, the wizard falls back to static ANSI
preview panels (color swatches, a mock prompt/diff) for anything that can be
approximated that way. On exit, `alacritty msg config --reset` clears any
runtime overrides so your real config file is the only thing that determines
the final look.

## Flags

| Flag               | Effect                                                                  |
| ------------------ | ----------------------------------------------------------------------- |
| `--dry-run`        | Print the resulting configuration to stdout; write nothing.             |
| `--output-dir DIR` | Write the config tree to `DIR` instead of `$XDG_CONFIG_HOME/alacritty`. |
| `--no-preview`     | Disable live/mock previews.                                             |
| `--load-existing`  | (best-effort) Seed defaults from your existing config, if one is found. |
| `-h`, `--help`     | Show usage.                                                             |

## What gets written

```
~/.config/alacritty/
├── alacritty.toml        # core settings + [general].import list
├── keybindings.toml       # only written if you pick a non-minimal preset
├── hints.toml             # only written if URL hints are enabled
└── themes/<name>.toml     # your chosen color theme
```

Any file that would be overwritten is first copied to
`<name>.bak.<timestamp>`. If the newly generated `alacritty.toml` fails
Alacritty's own validation (`alacritty migrate --dry-run`), all backups are
restored automatically and nothing is left half-written.

## Re-running

The wizard is safe to re-run at any time — it will back up whatever is
currently in `~/.config/alacritty/` before writing new files. To revert
manually, just copy the relevant `*.bak.<timestamp>` file back over the
current one.

## Fonts

If no Nerd Font is detected on your system, the font step offers to download
one (JetBrainsMono Nerd Font) into `~/.local/share/fonts` — this requires
network access and is entirely optional; icon/powerline glyphs simply won't
render as symbols without one.

## Themes

Eight themes are embedded and work fully offline: Gruvbox Dark, Catppuccin
Mocha, Tokyo Night, Nord, Dracula, Solarized Dark, Solarized Light, and One
Dark. If `git` and network access are available, you can also browse the full
[alacritty/alacritty-theme](https://github.com/alacritty/alacritty-theme)
collection, which gets cloned into `~/.config/alacritty/themes-upstream`.

## Layout

```
tools/alacritty/
├── alacritty-configure   # entry point / question flow
├── lib/ui.sh              # menu, prompt, and key-reading primitives
├── lib/probe.sh           # environment/capability detection
├── lib/themes.sh          # embedded themes + upstream fetch/preview
└── lib/emit.sh            # TOML serialization, backup, validation
```

Each file is plain Bash with no dependencies beyond `alacritty` itself
(`git`, `curl`, and `unzip` are only needed for the optional theme-browsing
and font-download features).
