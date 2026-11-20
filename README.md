# Omabar

A floating glass bar for [Omarchy](https://omarchy.org) 4. It sits over your desktop as a flattened glass oval, follows whichever Omarchy theme you switch to, and keeps everything that already works on the Omarchy bar: panels, drag and drop, `omarchy bar` commands, and plugins.

**Left:** the Omarchy menu and workspace dots. The workspace you're on stretches into an accent-colored pill.

**Center:** status indicators, a small Spotify player (previous, play/pause, next, round album art that turns while music plays, the track, and a progress line), and the clock. [Omaplug](https://github.com/fross100/omaplug) sits beside the clock when installed, so you can add and remove plugins from the bar.

**Right:** AI usage (Omarchy's agents panel, plus [ai-usagebar](https://github.com/akitaonrails/ai-usagebar) when installed), notifications, Omarchy settings, [Omaland](https://github.com/bobby-nicholas/omaland) when installed, and battery. Bluetooth, Wi-Fi, audio and display stay folded into a drawer that slides open when you hover it.

## Install

```bash
# Optional companions: install them first so setup puts them on the bar
omarchy plugin add https://github.com/akitaonrails/ai-usagebar.git --enable
omarchy plugin add https://github.com/bobby-nicholas/omaland.git --enable
omarchy plugin add https://github.com/fross100/omaplug.git --enable

# Omabar itself
omarchy plugin add https://github.com/goehringcory-lang/Omabar.git
~/.config/omarchy/plugins/goehringcory.omabar/bin/omabar-setup
```

`omabar-setup` backs up `~/.config/omarchy/shell.json` the first time it runs, switches the shell to Omabar, lays out the widgets above, and sets the bar to glassy so Hyprland blurs what's behind it. Widgets from other plugins that you already had on the bar stay where they were. Run it again after installing a companion plugin to add it to the bar.

The Spotify player needs Spotify running (desktop app or web app); it hides itself otherwise.

## Undo

```bash
~/.config/omarchy/plugins/goehringcory.omabar/bin/omabar-setup --restore   # your old layout
omarchy bar reset                                                          # or just the built-in bar
```

## Customize

Everything is normal Omarchy bar configuration, so you can drag widgets around, move things in and out of the hover drawer, and use `omarchy bar move`, `omarchy bar set`, `omarchy plugin add`, and `omarchy plugin remove` as usual.

- **Look:** double-click empty bar space, or run `omarchy bar background opaque|glassy|none`, to switch between solid glass, frosted glass, and clear.
- **Player:** `omarchy bar set omabar-player player <name>` follows a different MPRIS player, `anyPlayer true` falls back to whatever is playing, and `maxWidth 260` gives the track more room.
- **Workspace dots:** `omarchy bar set omabar-workspaces persistent 7` changes how many dots always show.
- **Size:** the bar height follows `[bar] size-horizontal` in `~/.config/omarchy/shell.toml`, with a 34px floor.

## How it works

Omabar is Omarchy's own bar engine with a different body. `tools/omabar-patch.py` takes the built-in `shell/plugins/bar/Bar.qml` and makes a few anchored edits: the strip floats off the screen edge, it's drawn as a rounded glass pill with a soft shadow and sheen, and it reserves room for the gap so windows, panels and notifications clear it. The plugin manifest marks it as a clone of `omarchy.bar`, the same way `omarchy plugin clone omarchy.bar` does, so it gets the built-in bar's capabilities.

When Omarchy updates its bar, regenerate Omabar from your installed copy:

```bash
cd ~/.config/omarchy/plugins/goehringcory.omabar
python3 tools/omabar-patch.py "$OMARCHY_PATH/shell/plugins/bar" .
```

The script refuses to write anything if an edit no longer matches, so an update can't leave you with a half-patched bar.

The workspace dots and the player are custom bar modules in `modules/`. The notification button is a command module backed by `bin/omabar-notifications`.

## Credits

`Bar.qml` and `BarModel.js` are generated from [Omarchy](https://github.com/omacom/omarchy) (MIT, Copyright (c) David Heinemeier Hansson), and the workspace numbering follows its workspaces widget. See `NOTICE`.
