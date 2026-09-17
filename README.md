# Mouse Controll

Move the mouse pointer from the keyboard, with one slider that decides how
precise it feels. AutoHotkey v2, Windows only.

## Install

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Double click `MouseControll.ahk`.
3. Press `Ctrl+Shift+F12`, drag the slider, tick **Run when Windows starts**.

## Keys

| Keys | Action |
| --- | --- |
| `Ctrl+Shift` + arrows | move the pointer |
| `Ctrl+Shift+X` + arrows | scroll the wheel |
| hold `Z` during either | fine mode |
| tap `RCtrl` | left click |
| hold `RCtrl` | hold the left button (drag, select text) |
| `RShift` | right click |
| `Ctrl+Shift+F12` | settings |

The tray icon opens the same settings window.

Only one instance runs at a time. Launching it again while it is already
running does nothing: the second copy exits immediately and the first keeps
going, hotkeys and all. Use **Reload** in the tray menu to pick up edits to
the script.

## The slider

One value, `1` to `100`, drives three things at once:

| | 1 (fast) | 100 (fine) |
| --- | --- | --- |
| top speed | 4000 px/s | 400 px/s |
| ramp to top speed | 120 ms | 400 ms |
| speed of the first step | 45% | 20% |

Top speed moves on a log curve, so every part of the slider changes the feel
by a similar amount. Raising precision also shortens the first step, which is
what stops a quick tap from throwing the pointer across the screen. Fine mode
(`Z`) is always 30% of the current top speed, so it stays useful at any
setting.

## Config

Saved to `%APPDATA%\mouse-controll\config.ini` about half a second after you
stop dragging:

```ini
[MouseKeys]
Precision=50
```

**Run when Windows starts** puts a shortcut in the Startup folder
(`shell:startup`) pointing at the interpreter and this script; unticking it
removes the shortcut. Nothing is written to the registry.
