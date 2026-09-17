# HyprNotes

Notes as plain text files, for GTK4 desktops. A sidebar that opens at the edge
of the screen, one note on screen, and a folder of `.md` files as the only
source of truth.

Written in Python + GTK4 / libadwaita. Bilingual French / English. No database,
no custom format, no daemon.

---

## Why files

One `.md` file per note in `~/.local/share/hyprnotes/`. That is the whole
storage layer. It means your notes stay greppable, editable in `nvim`,
syncable with whatever you already use — and **they outlive the app**. Delete
HyprNotes tomorrow and you still have a folder of text.

The pins are the one thing that cannot live in the text without polluting it,
so they sit in a small `state.json` beside the notes. Nothing else is hidden.

## What it does

**A sidebar that floats over the text** rather than pushing it
(`Adw.OverlaySplitView`, collapsed). It opens three ways — the mouse at the
left edge, `Ctrl + B`, or the header button. On hover it is transient and
closes when the mouse leaves; from the keyboard it stays until you close it.

**Light markup, applied in place.** The text stays plain, but three
conventions get dressed up:

| Written | Shown |
|---|---|
| `# Heading`, down to `###` | larger, bold |
| `**bold**` | bold |
| `- [ ]` / `- [x]` | a checkbox you tick by clicking the marker |

The markers stay visible, only dimmed. Hiding them inside an editable area
makes the cursor jump across characters you cannot see.

**Autosave** 500 ms after you stop typing, and on close. No Save button.

**Two independent pins per note.** One keeps it at the top of the list. The
other shows it in the notch — see below — and only one note at a time can hold
that second pin.

## Requirements

- Python 3 with `python-gobject`
- GTK 4 and libadwaita 1.4 or newer (`Adw.OverlaySplitView`)

On Arch: `pacman -S python-gobject gtk4 libadwaita`

## Install

```sh
git clone https://github.com/Peralban/HyprNotes.git
cd HyprNotes
./HyprNotes.py
```

Bind it to a key if you like. The app is single-instance: running the script
again wakes the instance already there and toggles the window, so the same key
opens and hides it.

```
# Hyprland
bind = SUPER, N, exec, /path/to/HyprNotes.py
```

Do **not** wrap it in `pkill -f HyprNotes.py || HyprNotes.py`. That shell line
contains the pattern in its own fallback, so `pkill` signals the shell running
it, kills it, and the fallback is never reached.

### AppImage

```sh
./packaging/build-appimage.sh
```

Builds `dist/HyprNotes-x86_64.AppImage`: a single portable executable. It
bundles the Python interpreter, PyGObject, and the GTK4 / libadwaita /
Pango / cairo / GLib shared libraries the build machine has installed —
found via `ldd` and copied by soname, with their `.typelib` files. Fonts,
the Wayland/X11 session and the Adwaita icon theme still come from the host
(libadwaita already requires that theme, so any machine that can display a
libadwaita app has it). Rebuild on the oldest distro you need to support if
exact portability matters — it isn't a fully static bundle like Flatpak.

## Keyboard

| | |
|---|---|
| `Ctrl + N` | new note |
| `Ctrl + B` | toggle the sidebar |
| `Ctrl + F` | search |
| `Ctrl + W`, `Escape` | hide the window |

## Theming

HyprNotes has no palette of its own. It inherits GTK's, so it follows whatever
your desktop already does. If you generate yours with
[matugen](https://github.com/InioX/matugen), have its GTK4 template signal the
app so it repaints without a restart:

```toml
[templates.gtk4]
input_path = '~/.config/matugen/templates/gtk-colors.css'
output_path = '~/.config/gtk-4.0/colors.css'
post_hook = 'pkill -SIGUSR1 -f "HyprNotes[.]py" || true'
```

GTK applications only pick up that file if `~/.config/gtk-4.0/gtk.css` imports
it — a one-line file that is easy to forget:

```css
@import url("colors.css");
```

## Signals

| | |
|---|---|
| `SIGUSR1` | reload the palette |
| `SIGUSR2` | show / hide the window |

## The notch integration

HyprNotes also renders and edits a pinned note **inside a notch**, which is
useful when the note is a to-do list. That part is optional and lives in
[`integrations/hyprnotch/`](integrations/hyprnotch/), because it needs the
other half of the pair:

> **[HyprNotch](https://github.com/Peralban/Rice-Linux-nux-nux)** — the notch
> itself, part of my Hyprland rice.

The two talk through the notes folder and nothing else. Both watch it with
`Gio.FileMonitor`, so ticking a box in the notch moves a file and the window
follows, and the other way round. No daemon, no socket, no IPC.

## Notes

Two traps worth writing down, since they decided how this is built.

**GTK4 destroys a window by default on `close-request`.** Intercepting it is
not optional for an app that hides instead of quitting: without it, clicking
the ✕ leaves the process alive holding the D-Bus name, while the shortcut has
nothing left to bring back.

**Decoding is slow enough to be felt.** Anything heavier than a repaint has to
leave the main loop and come back through `GLib.idle_add`.
