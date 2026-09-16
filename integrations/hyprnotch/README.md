# HyprNotch integration

An extra tab for **HyprNotch** showing the note you pinned to it — rendered
with the same light markup as the app, and tickable in place. Useful when the
note is a to-do list you want at the top of the screen.

This is one half of a pair. The other half is the notch itself:

> **[HyprNotch](https://github.com/Peralban/Rice-Linux-nux-nux)** —
> `config/hypr/scripts/hyprnotch/` in my Hyprland rice.

## How the two halves talk

Through the notes folder, and nothing else. Both sides open the same
`~/.local/share/hyprnotes/` and watch it with `Gio.FileMonitor`. Tick a box in
the notch and a file moves; the window sees it and refreshes. Edit in the
window and the notch follows. No daemon, no socket, no IPC — the filesystem is
the bus.

Which note appears is the second pin, set from the app's sidebar. Only one note
at a time can hold it, because the panel is narrow.

## Install

`notes.py` expects the `hyprnotes` package to sit **beside** the `hyprnotch`
one, since it walks three directories up to find it. With the layout of the
rice, that means both under `~/.config/hypr/scripts/`:

```
~/.config/hypr/scripts/
├── hyprnotes/          ← this repository
│   ├── store.py
│   ├── markup.py
│   └── window.py
└── hyprnotch/
    └── widgets/
        └── notes.py    ← this file
```

Then register the tab in `hyprnotch/ui/notch.py`:

```python
from ..widgets.notes import NotesWidget

PAGES = (
    ...,
    ("notes", "view-list-bullet-symbolic"),
)

self.w_notes = NotesWidget(self.lang, on_edit=self.pin_open)
self.page_stack.add_named(self.w_notes, "notes")
```

and have `_set_live` and `show_page` drive it like the other tabs.

## The keyboard trap

A notch opened on hover sits in `KeyboardMode.NONE` and receives no keys at
all. Waiting for the text view to take focus therefore never fires — **the
click is what has to claim both the pin and the keyboard**, through the
`on_edit` callback. Ticking a box works either way, since a click always gets
through.

The other side of that: once the notch holds the keyboard, the compositor will
hand it to the next window you click. The notch must notice
(`notify::is-active`), save, release the keyboard and unpin — otherwise it
stays open on screen, looking alive, listening to nothing.
