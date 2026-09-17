# Mouse Controll

One slider for the Windows pointer speed, saved to a file and reapplied at
login. AutoHotkey v2, Windows only.

## Install

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Double click `MouseControll.ahk`.
3. Press `Ctrl+Shift+F12`, drag the slider, tick **Run when Windows starts**.

## The slider

Sets the Windows pointer speed for your physical mouse, system wide, live as
you drag. This is the same value as the Control Panel pointer speed slider,
set through `SPI_SETMOUSESPEED`.

| slider | meaning |
| --- | --- |
| 1 | a tenth of default, slowest and most precise |
| 10 | Windows default, the only value that applies no scaling at all |
| 20 | double default |

Windows only accepts these 20 steps, so that is the resolution the slider
has. The readout shows the multiplier (`x0.60 of default`) so you can see
where you are between the ends.

**Enhance pointer precision** is the OS acceleration curve
(`SPI_SETMOUSE`). Off means the same hand movement always moves the pointer
the same distance, which is usually what you want when aiming for precision.

On first run the script adopts whatever Windows is already set to and changes
nothing, so installing it never surprises you.

## Keyboard pointer

The old keyboard layer is still here, and rides on the same slider so both
pointers agree about what slow means (400 px/s at slider 1, 4000 at 20).

| Keys | Action |
| --- | --- |
| `Ctrl+Shift` + arrows | move the pointer |
| `Ctrl+Shift+X` + arrows | scroll the wheel |
| hold `Z` during either | fine mode, 30% speed |
| tap `RCtrl` | left click |
| hold `RCtrl` | hold the left button (drag, select text) |
| `RShift` | right click |
| `Ctrl+Shift+F12` | settings |

The tray icon opens the same settings window.

Only one instance runs at a time. Launching it again while it is already
running does nothing: the second copy exits immediately and the first keeps
going, hotkeys and all. Use **Reload** in the tray menu to pick up edits to
the script.

## Config

Saved to `%APPDATA%\mouse-controll\config.ini` about half a second after you
stop dragging, and reapplied to Windows at launch:

```ini
[Mouse]
Speed=6
Accel=0
```

**Run when Windows starts** puts a shortcut in the Startup folder
(`shell:startup`) pointing at the interpreter and this script; unticking it
removes the shortcut. Nothing is written to the registry.
