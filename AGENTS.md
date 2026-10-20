# AGENTS.md

A Tailscale bar widget for [Omarchy](https://omarchy.org/): a third-party
plugin (`igor-alexandrov.tailscale`) loaded by `omarchy-shell`, the single
long-running Quickshell (Qt 6 / QML) process that hosts the Omarchy desktop.
It shells out to the `tailscale` CLI and renders the result; there is no
daemon, build step or package manager. Features, install, requirements and
keyboard shortcuts are in `README.md`: read it before changing behaviour.

## Layers

Each piece of logic has one home:

- `Model.js` is **pure**: it parses CLI output (`tailscale status --json`,
  `tailscale switch --list --json`, `tailscale exit-node list`) into plain
  objects. No QML imports, ES5 style (`var`, `function`), exported through the
  `module.exports` guard at the bottom so plain node can load it. Logic that
  can be pure goes here, with a case in `test/model-test.js`.
- `Service.qml` runs the CLI and holds state. Each command is its own `Process`
  with a `StdioCollector` pair and `_<name>Output` / `_<name>Error` properties.
  Actions end in `delayedRefresh.restart()`, so state is always re-read from the
  CLI; `_desired` is the only optimistic state (the on/off toggle). A new polling
  `Process` also joins `busy` and the `pollWatchdog` reap list: a poll is skipped
  while its process runs, so one hung `tailscale` call would stop refreshes.
- `Panel.qml` is all UI: bar button, `KeyboardPanel` popup, row components,
  key handling (`onTextKey`) and both `IpcHandler`s, built on `qs.Commons` and
  `qs.Ui` from the Omarchy shell.
- `TailscaleIcon.qml` draws the mark as native dots, because SVG renders poorly
  in tiny bar slots.
- `manifest.json` holds the plugin id, the entry point, and the widget's
  settings `schema` / `defaults`.

## Invariants

- **Plugin id.** The manifest `id`, the `target` of the first `IpcHandler` in
  `Panel.qml`, and the `ipc call <id>` commands in `README.md` are the same
  string; `test/manifest-test.js` enforces it. The `moduleName:
  "omarchy.tailscale"` literal is only a placeholder: the bar overwrites
  `moduleName`, `bar` and `settings` with the real entry's values when it loads
  the widget (`injectProps` in `/usr/share/omarchy/shell/plugins/bar/Bar.qml`),
  so `persistRecentMullvad` writes to this plugin's own entry. `ipcTarget` is
  not injected.
- **Settings** live only in the widget's bar entry in
  `~/.config/omarchy/shell.json`, written through `bar.shell.updateEntryInline`.
  The README promises the plugin writes nothing anywhere else, with one
  exception: the Taildrop *Receive automatically* switch runs `systemctl
  --user enable|disable --now omarchy-tailscale-receive.service`. It mirrors
  that Omarchy service and only changes it when flipped, never on its own,
  and it is not a setting. A new user
  setting is declared in the manifest `schema` and `defaults` and read in
  `Service.qml` through `setting()` / `intSetting()`.
- **Fixtures** in `test/fixtures/` are hand-written synthetic data: real
  `tailscale status --json` output carries node keys, account addresses and the
  tailnet name.
- **README mirrors the code**: the Features list, the Keyboard shortcuts table
  and the IPC commands change in the same commit as the code they describe.

## Verifying

`bin/check` is the gate; done is its final line, `All checks passed.` It skips
steps whose tooling is missing, so on a machine without Omarchy or Qt 6
`omarchy plugin validate` and `qmllint` never run: say so when reporting.
qmllint warnings are expected (hundreds, mostly inherited from upstream);
errors fail.

To see a UI change in the real shell, the checkout must be linked as
`~/.config/omarchy/plugins/igor-alexandrov.tailscale`. After every edit run
`omarchy restart shell` and reopen the panel: the shell's hot reload on save
keeps rendering the old panel and never registers new `IpcHandler`s.

## Reference

- `/usr/share/omarchy/shell/README.md` and `plugins/README.md` there: manifest
  format, plugin loading, the shell API.
- `/usr/share/omarchy/shell/Ui/` and `Commons/`: source of every `qs.Ui` /
  `qs.Commons` type this plugin uses (`Panel`, `KeyboardPanel`,
  `CursorSurface`, `Style`, `Color`, `Util`…).
- `/usr/share/omarchy/shell/plugins/panels/tailscale/`: the first-party widget
  this was derived from. Diff against it when porting upstream fixes.

## Commits

Imperative, sentence-case subjects with no type prefix, as in the history
(`Add checks, unit tests and CI`). Code comments explain why, not what.
