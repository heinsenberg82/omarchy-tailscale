# omarchy-tailscale

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Omarchy](https://img.shields.io/badge/Omarchy-4.x-8b5cf6.svg)](https://omarchy.org/)

A Tailscale widget for the [Omarchy](https://omarchy.org/) bar — the Linux
equivalent of the Tailscale menu bar icon on macOS.

Click the icon to see your account, this device, and every machine on your
tailnet with its Tailscale IP.

This is a fork of
[igor-alexandrov/omarchy-tailscale](https://github.com/igor-alexandrov/omarchy-tailscale)
that adds a **Taildrop** section for receiving files on your own terms:
automatic receiving becomes a switch, files can wait in the inbox until you
save them to a folder of your choice, and you are told when they arrive. The
plugin id is unchanged, `igor-alexandrov.tailscale`, so that is the name every
command below uses.

<img src="docs/panel.png" alt="The Tailscale panel open in the Omarchy bar, showing This device, Machines and Account sections" width="384">

*Addresses are blurred in the screenshot, which predates the Taildrop section.*

## Features

- Connection state in the bar, with a Tailscale mark drawn natively as a
  theme-coloured 3×3 dot grid
- **This device** — host name, OS, Tailscale IP and MagicDNS name, with
  one-click IP copy
- **Machines** — every peer on the tailnet with its IP and DNS name. Online
  first; offline machines are dimmed and tagged rather than hidden
- **Account** — the signed-in account, and a row that opens the admin console
- Copy a machine's Tailscale IP, host name, or DNS name
- Left click opens the panel, right click toggles Tailscale on/off
- Switch between Tailscale accounts when more than one is available
- Exit node selection, including Mullvad exit nodes
- Send files with Taildrop, when the tailnet allows file sharing
- **Taildrop** — save the files waiting in the inbox to a folder you pick, and
  switch Omarchy's automatic receiving on or off. With it off, a notification
  and a dot on the bar icon say when files are waiting

## Install

Omarchy's Tailscale install puts its own first-party widget,
`omarchy.tailscale`, in the bar. Disable it first so the bar does not show two:

```bash
omarchy plugin disable omarchy.tailscale
```

The first-party widget ships inside the Omarchy package, so it can be disabled
but not removed; `omarchy plugin remove` only handles plugins under
`~/.config/omarchy/plugins`. Then add this fork:

```bash
omarchy plugin add https://github.com/heinsenberg82/omarchy-tailscale.git --enable
```

- Use the HTTPS URL. `omarchy plugin add` runs ssh in batch mode, so an SSH
  URL fails with `Host key verification failed` unless `github.com` is already
  in `~/.ssh/known_hosts`. The repository is public, so HTTPS needs no
  credentials, for updates either.
- Without a terminal to ask in (a script, or a shell command run from another
  tool), add `--yes`, or it refuses to continue.

Then place it in the bar, for example where the first-party widget was:

```bash
omarchy bar move igor-alexandrov.tailscale --section right --before omarchy.tray
```

Any widget already in the bar works with `--before` or `--after`; `--index`
takes a position instead.

Update later with:

```bash
omarchy plugin update igor-alexandrov.tailscale
omarchy restart shell
```

The shell reloads the files on update but keeps rendering the panel it already
built, so the restart is what brings the new version up.

## Uninstall

```bash
omarchy plugin remove igor-alexandrov.tailscale
```

That disables the widget, takes it out of the bar, and deletes the plugin
directory. To keep the plugin installed but hide it, disable it instead:

```bash
omarchy plugin disable igor-alexandrov.tailscale
```

To go back to Omarchy's own widget, enable it again with
`omarchy plugin enable omarchy.tailscale`.

Widget settings are not stored in the plugin directory: the refresh interval and
your recently used Mullvad exit nodes live in the bar layout in
`~/.config/omarchy/shell.json`, the same place Omarchy keeps the settings of its
own widgets. Removing the plugin takes its entry out of the bar; edit that file
if you want to be sure nothing is left. The plugin writes nothing anywhere else;
the one exception is the *Receive automatically* switch, which enables or
disables Omarchy's `omarchy-tailscale-receive` user service when you flip it.

> Plugins run as unsandboxed code inside the long-lived `omarchy-shell`
> process. Read the source before enabling this, or any other plugin.

## Requirements

- Omarchy 4.x with the Quickshell-based `omarchy-shell`
- `tailscale` CLI on `PATH`
- `wl-copy` (`wl-clipboard`) for the copy actions
- `xdg-open` for opening the admin console
- Taildrop enabled on the tailnet, to send and receive files
- `omarchy-file-select` (part of Omarchy) for picking the folder to save into

## Keyboard shortcuts

With the panel open:

| Key | Action |
|-----|--------|
| `j` / `k` or arrows | Move the cursor |
| `enter` / `space` | Activate the current row |
| `c` | Copy the selected machine's IP |
| `n` | Copy the selected machine's name |
| `d` | Copy the selected machine's DNS name |
| `s` | Send files to the selected machine |
| `g` | Save the waiting Taildrop files to a folder |
| `a` | Open the Tailscale admin console |
| `t` | Toggle Tailscale |
| `r` | Refresh status |
| `esc` | Close |

## Opening the panel by command

Omarchy's own bar panels cannot be opened over IPC: they set
`manageIpc: false`, so the handler registered for their target does not drive
the panel and `ipc call <target> open` is accepted but does nothing. This plugin
registers an `IpcHandler` of its own, so it can be scripted or bound to a key:

```bash
qs -p /usr/share/omarchy/shell ipc call igor-alexandrov.tailscale toggle
qs -p /usr/share/omarchy/shell ipc call igor-alexandrov.tailscale open
qs -p /usr/share/omarchy/shell ipc call igor-alexandrov.tailscale adminConsole
qs -p /usr/share/omarchy/shell ipc call igor-alexandrov.tailscale saveFiles
```

`saveFiles` asks for a folder and saves the waiting Taildrop files there, the
same as `g` in the panel.

## Receiving files

Omarchy ships an `omarchy-tailscale-receive` user service, enabled by default,
that moves every incoming Taildrop file to `~/Downloads` the moment it lands
and announces it with a notification. While it runs, the inbox is always empty,
so there is nothing left for `tailscale file get` to pick up.

The **Taildrop** section of the panel puts that choice in your hands:

- **Receive automatically** shows whether the service is on, and flipping it
  runs `systemctl --user enable --now` or `disable --now` on it. The plugin
  never changes the service by itself, so the switch stays where you leave it,
  across reboots, and agrees with anything you do through `systemctl`.
- **Save waiting files…** shows what is in the inbox, asks for a folder, and
  moves the files there with `tailscale file get --conflict=rename`, so a
  same-named file gets a numbered name instead of being overwritten. A
  notification reports the result; click it to open the file or folder.

With automatic receiving off, files wait in the inbox until you save them from
the panel or with `tailscale file get <directory>` yourself. As files arrive, a
notification names them (click it to pick a folder and save them), and the bar
icon carries an accent dot for as long as anything is waiting. Arrivals are
picked up at once from tailscaled's message bus (`tailscale debug watch-ipn`),
with the regular refresh as a fallback; files already waiting are announced
again when the shell starts. The section only
appears when the tailnet allows Taildrop or files are already waiting. The
inbox is listed with `tailscale debug --file get`, the only way the CLI offers
to look without emptying it; if that ever fails, the save row stays usable and
`tailscale file get` reports for itself.

## Development

The plugin is plain QML plus one JavaScript module, loaded directly by
`omarchy-shell`:

| File | Role |
|------|------|
| `Panel.qml` | Bar widget and popup panel — all of the UI |
| `Service.qml` | Runs the `tailscale` CLI and holds state |
| `Model.js` | Pure parsing of `tailscale status --json`; node-loadable, so it can be unit tested outside the shell |
| `TailscaleIcon.qml` | The bar icon |
| `manifest.json` | Plugin id, kinds, entry point, bar widget settings |

To work on it, clone the fork and point the plugin directory at your checkout
instead of the copy `omarchy plugin add` made:

```bash
git clone https://github.com/heinsenberg82/omarchy-tailscale.git ~/path/to/omarchy-tailscale
omarchy plugin remove igor-alexandrov.tailscale --yes
ln -s ~/path/to/omarchy-tailscale ~/.config/omarchy/plugins/igor-alexandrov.tailscale
omarchy plugin enable igor-alexandrov.tailscale
```

**Saving a file is not enough to see UI changes.** The shell logs
`Local plugin changed, reloading`, but it does not re-create the already
instantiated bar panel, so the old UI keeps rendering and newly added
`IpcHandler` children never register. Run `omarchy restart shell` after editing,
then reopen the panel.

### Checks

```bash
bin/check
```

Runs everything, skipping any step whose tooling is missing rather than failing:

| Step | Needs | Covers |
|------|-------|--------|
| `node --check Model.js` | node | Syntax |
| `test/model-test.js` | node | `Model.js` parsing, against synthetic fixtures |
| `test/manifest-test.js` | node | The rules `omarchy plugin validate` enforces, plus entry points on disk and the IPC target matching the plugin id |
| `omarchy plugin validate .` | Omarchy | The authoritative manifest check |
| `qmllint` | Qt 6 | QML errors |

The last two steps only run on a machine with Omarchy and Qt 6, so run
`bin/check` on your Omarchy machine before releasing.

Two notes on qmllint, which cost some time to work out:

- Use **Qt 6's** binary at `/usr/lib/qt6/bin/qmllint`. On Arch, `/usr/bin/qmllint`
  is Qt 5's and exits 255 with no output on any Quickshell file.
- `import qs.Ui` only resolves if the shell tree is visible under a directory
  literally named `qs`, so `bin/check` builds a symlink farm for it.

Warnings are reported but do not fail the run: the upstream code this is derived
from carries ~157 of them, nearly all `unqualified` access and `missing-property`
against the `Style` singleton's nested objects, which qmllint cannot introspect.
Errors do fail.

The fixtures in `test/fixtures/` are hand-written. Keep them that way — real
`tailscale status --json` output carries node public keys, account addresses and
your tailnet name, none of which belong in a public repository.

## Credits

Forked from
[igor-alexandrov/omarchy-tailscale](https://github.com/igor-alexandrov/omarchy-tailscale)
by Igor Alexandrov, which is derived from the first-party `omarchy.tailscale`
widget in [Omarchy](https://github.com/basecamp/omarchy) by Basecamp, MIT
licensed. Igor's version adds the *This device* and *Account* sections, lists
offline machines instead of hiding them, and adds the `a` shortcut and the IPC
target. This fork adds the *Taildrop* section: the automatic receiving switch,
saving waiting files to a folder you pick, and the arrival notification and bar
icon dot.

MIT licensed — see [LICENSE](LICENSE).
