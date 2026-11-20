# Omabar

A floating glass bar for [Omarchy](https://omarchy.org) 4. It sits over your desktop as a flattened glass oval, follows whichever Omarchy theme you switch to, and keeps everything that already works on the Omarchy bar: panels, drag and drop, `omarchy bar` commands, and plugins.

**Left:** the Omarchy logo on a bright tile in your theme's accent color, then workspace dots. The workspace you're on stretches into an accent pill, and switching sends a drop of water across that sheds droplets and splashes into the new one.

![Workspace switch](preview/workspaces-drop.gif)

**Center:** status indicators, a Spotify player that bulges out of the bar while a track is loaded (previous, play/pause, next, large round album art that turns while music plays, the song and artist, and a progress line), and a split-flap clock in the accent color whose digits flip like an old departures board. Click the clock for a calendar drop-down (with your Google Calendar), right-click to flip it to the date. Omarchy's world clock (Elsewhen) stays beside it, restyled with the same split-flap tiles. [Omaplug](https://github.com/fross100/omaplug) sits beside the clock when installed, so you can add and remove plugins from the bar.

![Split-flap clock](preview/split-flap-clock.gif)

The player's chevron opens a playlist menu: one-click **Lofi Beats**, **Discover Weekly**, any playlists you pin, and every playlist on your Spotify account once you connect it. With Spotify closed the player rests as a small disc and chevron, so a playlist is still one click away.

**Right:** only five things stay in view: AI usage (Omarchy's agents panel, plus [ai-usagebar](https://github.com/akitaonrails/ai-usagebar) when installed), notifications, Thunderbird mail (it turns the accent color when new mail arrives in any inbox), Omarchy settings, and battery. Everything else is folded into a drawer behind the chevron at the far left of the group. Hover it (or click to keep it open) and a glass panel drops below the bar with a tile for each control, [Omaland](https://github.com/bobby-nicholas/omaland) when installed, Bluetooth, network, sound, display and keyboard layout, plus your apps' tray icons. A tile opens that control's own Omarchy panel; a tray app opens on click and shows its menu on right-click. **Edit** in the panel hides anything you don't want there. The bar itself never widens, so nothing spills over the clock.

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

`omabar-setup` builds the bar from the Omarchy you have installed, backs up `~/.config/omarchy/shell.json` the first time it runs, switches the shell to Omabar, lays out the widgets above, and sets the bar to glassy so Hyprland blurs what's behind it. Setup reads which plugins you have installed and places each plugin's widget exactly once: ai-usagebar beside the agents icon, Omaplug beside the clock, and every other plugin widget in the drawer panel. Nothing from your old layout is carried over, so nothing doubles up. Run it again after installing a companion plugin to add it to the bar, and after an Omarchy update so the bar matches the new shell.

Setup checks that the shell actually loaded Omabar. If it didn't, it prints what the shell logged instead of leaving you with the built-in bar and no explanation.

### If it doesn't work

```bash
~/.config/omarchy/plugins/goehringcory.omabar/bin/omabar-setup --doctor
```

prints your Omarchy version, what Omabar built, your bar layout, and the shell's log lines about plugins. `journalctl -t omarchy-shell -b` has the full shell log.

### Spotify playlists

Lofi Beats and your pinned playlists work right away. To list every playlist on your account, open the player's menu and choose **Connect Spotify** (or run `~/.config/omarchy/plugins/goehringcory.omabar/bin/omabar-spotify login`). It walks you through making a free Spotify developer app, since Spotify requires one per user, and stores the login token in `~/.config/omabar/`, readable only by you.

Discover Weekly is a different playlist for every account, so the menu asks for your link the first time you click it.

### Google Calendar

The clock's drop-down shows the month, colored dots for days with events, and the agenda for the day you pick. To fill it from your Google Calendar, open it and choose **Connect Google Calendar** (or run `~/.config/omarchy/plugins/goehringcory.omabar/bin/omabar-gcal login`). Like Spotify, Google needs a client of your own, once:

1. In [Google Cloud Console](https://console.cloud.google.com/), make a project, enable the **Google Calendar API**, and set up the OAuth consent screen (External, add yourself as a test user).
2. Under **Credentials**, create an **OAuth client ID** of type **Desktop app** and download its JSON.
3. Run the login command and paste the path to that JSON (or the client ID and secret) when asked. A browser opens to sign in.

Omabar only asks for read-only calendar access. The token is stored in `~/.config/omabar/`, readable only by you.

**Calendars** at the bottom of the drop-down lists every calendar you own and every calendar shared with you, each in its Google color. Tick the ones to show. Events keep the colors you set in Google.

### Thunderbird

The mail button notices new mail from Thunderbird's own new-mail notifications, so leave Thunderbird running (it can sit in the background) with new-mail alerts on, which is its default. Clicking opens Thunderbird and clears the accent; so does switching to its window. Right-click marks it seen.

## Undo

```bash
~/.config/omarchy/plugins/goehringcory.omabar/bin/omabar-setup --restore   # your old layout
omarchy bar reset                                                          # or just the built-in bar
```

## Customize

Everything is normal Omarchy bar configuration, so you can drag widgets around, move things in and out of the drawer (the layout's `tray` section), and use `omarchy bar move`, `omarchy bar set`, `omarchy plugin add`, and `omarchy plugin remove` as usual.

- **Look:** double-click empty bar space, or run `omarchy bar background opaque|glassy|none`, to switch between solid glass, frosted glass, and clear.
- **Player:** `omarchy bar set omabar-player player <name>` follows a different MPRIS player, `anyPlayer true` falls back to whatever is playing, `maxWidth 260` gives the track more room, `lofi <link>` points the Lofi button at another playlist, `showIdle false` hides the player while Spotify is closed, and `bulge false` keeps it flat inside the bar. Pin playlists with `omarchy bar set omabar-player playlists '[{"name":"Focus","uri":"spotify:playlist:…"}]' --json`.
- **Clock:** the clock shows 12-hour time with AM/PM; `omarchy bar set omabar-clock twelveHour false` for 24-hour, `showDate false` for just the tiles.
- **Motion:** animations follow Omarchy's reduce-motion setting. Everything is drawn by the GPU at your display's refresh rate, antialiased and scaled with mipmaps, so it stays sharp on HiDPI screens.
- **Workspace dots:** `omarchy bar set omabar-workspaces persistent 7` changes how many dots always show.
- **Size:** the bar height follows `[bar] size-horizontal` in `~/.config/omarchy/shell.toml`, with a 34px floor.

## How it works

Omabar is Omarchy's own bar engine with a different body. `tools/omabar-patch.py` takes the built-in `shell/plugins/bar/Bar.qml` and makes a few anchored edits: the strip floats off the screen edge, it's drawn as a rounded glass pill with a soft shadow and sheen, and it reserves room for the gap so windows, panels and notifications clear it. The plugin manifest marks it as a clone of `omarchy.bar`, the same way `omarchy plugin clone omarchy.bar` does, so it gets the built-in bar's capabilities.

Omarchy's bar changes between releases, so the engine isn't shipped ready-made. `omabar-setup` runs the patch against `$OMARCHY_PATH/shell/plugins/bar` on your machine and writes the result to `engine/`, which `Bar.qml` loads. `engine/` is ignored by git, so `omarchy plugin update` keeps working. If an edit no longer matches your Omarchy's bar, setup says so and uses `prebuilt/`, a copy built from Omarchy 4.5.0.

The menu tile, workspace dots, player, playlist menu, clock, calendar and mail button are custom bar modules in `modules/`. `bin/omabar-gcal` reads Google Calendar. `tools/omabar-elsewhen-patch.py` swaps the world clock's times for split-flap tiles in a clone of `omarchy.elsewhen`, which `omabar-setup` makes for you, so the built-in plugin is never touched. The notification button is a command module backed by `bin/omabar-notifications`, and `bin/omabar-spotify` plays playlists through Spotify's MPRIS interface and lists them through the Spotify Web API.

`preview/` holds recordings (GIF and MP4) of the workspace and clock animations, rendered from the real module code with stand-ins for the Omarchy shell.

## Credits

The bar engine (`engine/`, `prebuilt/`) is generated from [Omarchy](https://github.com/omacom/omarchy) (MIT, Copyright (c) David Heinemeier Hansson), and the workspace numbering follows its workspaces widget. See `NOTICE`.
