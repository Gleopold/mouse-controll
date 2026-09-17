# Mouse Controll

A pointer sensitivity slider with hundredths instead of Windows' twenty
steps, saved to a file and reapplied at login. AutoHotkey v2, Windows only.

## Install

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Double click `MouseControll.ahk`.
3. Press `Ctrl+Shift+F12`, drag the slider, tick **Run when Windows starts**.

## Why

Windows offers 20 pointer speed steps, and they are multiples of the neutral
step 10 rather than even divisions. Measured on a real machine, with
acceleration off:

| step | 1 | 2 | 3 | 4 | 5 | 6 | 10 | 14 | 20 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| multiplier | 1/32 | 1/16 | 1/8 | 1/4 | 3/8 | 1/2 | 1 | 2 | 3.5 |

Down at the slow end, where you go looking for precision, one notch is a
50% change. There is no finer knob in the OS, so this script parks Windows
on the neutral step and scales the movement itself.

## How

A `WH_MOUSE_LL` hook swallows each real movement, multiplies it, and places
the cursor itself, carrying the fraction it could not spend into the next
event. The script's own `SetCursorPos` comes back flagged as injected,
which is how it avoids chasing its own tail.

Measured cost: **156 us per event without the hook, 141 us with it** — the
whole cost is the injection API and the hook's own share is below the noise
between runs. At a 1000 Hz polling rate there is no backlog.

Scaling is exact. Injecting 4000 counts at `x0.25` moved the cursor 1500 px,
the predicted value to the pixel, on a display at 150% scaling.

## The slider

Sensitivity as a multiple of the Windows neutral step, `0.05` to `3.00` in
steps of `0.01`. Drag it, or nudge with the arrow keys for one hundredth at
a time. At `x0.25` a notch is a 2.5% change, against the OS's 50%.

**Enhance pointer precision** is the OS acceleration curve. It runs *before*
this scaling, so with it on the effective multiplier moves with your hand
speed and the slider stops meaning one thing — measured as +15% on fast
movement and -4% on slow. Leave it off if you want the number on the slider
to be the number you get.

On first run the script reads your current Windows step and picks the
matching multiplier, so installing it does not change how anything feels.
A setting from an older version of this script is carried over the same way.

## Profiles

Save the current sensitivity under a name, load it back later, delete it
when done. Handy for one slow setting for drawing and a fast one for
everything else. Profiles live in the same config file, one section each.

## Keyboard pointer

Still here, and rides the same slider.

| Keys | Action |
| --- | --- |
| `Ctrl+Shift` + arrows | move the pointer |
| `Ctrl+Shift+X` + arrows | scroll the wheel |
| hold `Z` during either | fine mode, 30% speed |
| tap `RCtrl` | left click |
| hold `RCtrl` | hold the left button (drag, select text) |
| `RShift` | right click |
| `Ctrl+Shift+F12` | settings |
| `Ctrl+Shift+F11` | panic switch: drop the scaler, hand the mouse back |

The tray icon opens the same settings window.

Only one instance runs at a time. Launching it again while it is already
running does nothing: the second copy exits immediately and the first keeps
going. Use **Reload** in the tray menu to pick up edits to the script.

## Config

`%APPDATA%\mouse-controll\config.ini`, written about half a second after you
stop dragging and reapplied at launch:

```ini
[Mouse]
Scale=0.25
Accel=1
BaseSpeed=4

[Profile Drawing]
Scale=0.12
Accel=0
```

`BaseSpeed` is the Windows step you were on before the script took over. It
is restored when the script exits, including at logoff and shutdown. A hard
kill is the one case that leaves Windows parked on the neutral step, which
means a temporarily faster pointer until you start the script again, or set
the speed yourself in Settings.

Edit the file by hand only with an editor that writes plain ASCII or UTF-8
**without a BOM**. A BOM makes `IniRead` miss the first section header, and
the script will treat the config as empty.

## Limits

Games that read the mouse through raw input bypass both the Windows pointer
speed and this hook, so neither this nor the Control Panel slider changes
aim inside them. Use the game's own sensitivity setting for that.
