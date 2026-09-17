#Requires AutoHotkey v2.0
; Ignore, not Force: a second launch exits and leaves the running one alone
#SingleInstance Ignore
#MaxThreadsPerHotkey 1

; ============================================================
;  Mouse Controll
;
;  One slider sets the Windows pointer speed for the physical
;  mouse, system wide.  The setting is saved to
;  %APPDATA%\mouse-controll\config.ini and reapplied at launch,
;  so putting this in Startup restores it at every login.
;
;  The keyboard pointer layer rides on the same slider:
;
;  Ctrl+Shift + arrows      move the pointer
;  Ctrl+Shift + X + arrows  scroll the wheel
;  hold Z during either     fine mode
;  tap RCtrl                left click   (hold = drag)
;  RShift                   right click
;  Ctrl+Shift+F12           open settings
; ============================================================

InstallKeybdHook(true)
SendMode("Input")
SetMouseDelay(-1)
CoordMode("Mouse", "Screen")
DllCall("winmm\timeBeginPeriod", "UInt", 1)

; ---------- SystemParametersInfo ----------
SPI_GETMOUSE      := 0x0003
SPI_SETMOUSE      := 0x0004
SPI_GETMOUSESPEED := 0x0070
SPI_SETMOUSESPEED := 0x0071
SPIF_UPDATEINIFILE := 0x01
SPIF_SENDCHANGE    := 0x02

; ---------- config location ----------
CfgDir  := A_AppData "\mouse-controll"
CfgFile := CfgDir "\config.ini"

; ---------- the one tunable ----------
; Windows pointer speed, 1 (slowest, most precise) to 20 (fastest).
; 10 is the Windows default and the only value that applies no scaling
; to what the mouse actually reports.
Speed := 10

; Enhance pointer precision: the OS acceleration curve.  Off means the
; pointer moves the same distance for the same hand movement every time.
Accel := false

; ---------- keyboard layer, derived from Speed ----------
fastSpeed := 0      ; pixels per second at full tilt
accelTime := 0      ; ms to ramp up to full speed
minFactor := 0      ; starting fraction of fastSpeed

slowFactor := 0.30  ; fine mode (Z held) as a fraction of fastSpeed
interval   := 4     ; ms per movement step

scrollStart := 90   ; ms between wheel ticks at start
scrollMin   := 18   ; ms between wheel ticks at full speed
scrollAccel := 400  ; ms to reach full scroll speed

moving    := false
scrolling := false

; ---------- virtual screen bounds ----------
vL := SysGet(76)
vT := SysGet(77)
vR := vL + SysGet(78) - 1
vB := vT + SysGet(79) - 1

LoadConfig()
BuildGui()
BuildTray()

TrayTip("Mouse Controll loaded", "Pointer speed " Speed " of 20`nCtrl+Shift+F12 = settings", 1)

; ============================================================
;  Windows pointer speed
; ============================================================

SysGetSpeed() {
    DllCall("SystemParametersInfo", "UInt", 0x0070, "UInt", 0, "UInt*", &spd := 0, "UInt", 0)
    return spd
}

SysSetSpeed(v) {
    ; pvParam carries the value itself here, not a pointer to it
    DllCall("SystemParametersInfo", "UInt", 0x0071, "UInt", 0, "Ptr", v, "UInt", 0x01 | 0x02)
}

; SPI_GETMOUSE fills three ints: threshold1, threshold2, acceleration
SysGetAccel() {
    buf := Buffer(12, 0)
    DllCall("SystemParametersInfo", "UInt", 0x0003, "UInt", 0, "Ptr", buf, "UInt", 0)
    return NumGet(buf, 8, "Int") != 0
}

SysSetAccel(on) {
    buf := Buffer(12, 0)
    if on {
        NumPut("Int", 6, buf, 0)      ; Windows defaults
        NumPut("Int", 10, buf, 4)
        NumPut("Int", 1, buf, 8)
    }                                  ; else leave all three at zero
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", buf, "UInt", 0x01 | 0x02)
}

ApplyToSystem() {
    global Speed, Accel

    SysSetSpeed(Speed)
    SysSetAccel(Accel)
    ApplyKeyboardSpeed()
}

; The keyboard layer tracks the same slider, so both pointers agree
; about what "slow" means.
ApplyKeyboardSpeed() {
    global Speed, fastSpeed, accelTime, minFactor

    t := (Speed - 1) / 19.0              ; 0.0 .. 1.0

    fastSpeed := 400 * (10 ** t)         ; 400 -> 4000 px/s, logarithmic
    accelTime := 400 - 280 * t           ; 400 -> 120 ms
    minFactor := 0.20 + 0.25 * t         ; 0.20 -> 0.45
}

; ============================================================
;  config
; ============================================================

LoadConfig() {
    global CfgFile, Speed, Accel

    ; an empty read also covers a config from an older version of this script
    raw := FileExist(CfgFile) ? IniRead(CfgFile, "Mouse", "Speed", "") : ""

    if (raw != "") {
        try Speed := Integer(raw)
        try Accel := Integer(IniRead(CfgFile, "Mouse", "Accel", "0")) != 0
        Speed := Clamp(Speed, 1, 20)
        ApplyToSystem()
    } else {
        ; first run: adopt whatever Windows is already set to, change nothing
        Speed := Clamp(SysGetSpeed(), 1, 20)
        Accel := SysGetAccel()
        ApplyKeyboardSpeed()
        SaveConfig()
    }
}

SaveConfig() {
    global CfgDir, CfgFile, Speed, Accel

    if !DirExist(CfgDir)
        DirCreate(CfgDir)
    IniWrite(Speed, CfgFile, "Mouse", "Speed")
    IniWrite(Accel ? 1 : 0, CfgFile, "Mouse", "Accel")
}

Clamp(v, lo, hi) {
    return v < lo ? lo : (v > hi ? hi : v)
}

; ============================================================
;  run at startup
; ============================================================

StartupLink() {
    return A_Startup "\Mouse Controll.lnk"
}

SetStartup(on) {
    lnk := StartupLink()

    if on {
        if A_IsCompiled
            FileCreateShortcut(A_ScriptFullPath, lnk, A_ScriptDir, , "Mouse Controll")
        else
            FileCreateShortcut(A_AhkPath, lnk, A_ScriptDir, '"' A_ScriptFullPath '"', "Mouse Controll")
    } else if FileExist(lnk) {
        FileDelete(lnk)
    }
}

; ============================================================
;  settings window
; ============================================================

BuildGui() {
    global g, gSlider, gInfo, gAccel, gStartup, Speed, Accel

    g := Gui("+AlwaysOnTop -MinimizeBox", "Mouse Controll")
    g.MarginX := 16
    g.MarginY := 14

    g.SetFont("s11 w600", "Segoe UI")
    g.Add("Text", "xm w360", "Pointer speed")

    g.SetFont("s9 w400", "Segoe UI")
    g.Add("Text", "xm w360 cGray", "Your mouse, every app. Takes effect as you drag.")

    gSlider := g.Add("Slider", "xm w360 Range1-20 TickInterval1 ToolTip", Speed)
    gSlider.OnEvent("Change", SliderChanged)

    g.Add("Text", "xm w175 cGray", "slow, precise")
    g.Add("Text", "x+10 w175 Right cGray", "fast")

    g.SetFont("s9 w400", "Consolas")
    gInfo := g.Add("Text", "xm w360 h34", "")

    g.SetFont("s9 w400", "Segoe UI")
    gAccel := g.Add("CheckBox", "xm w360", "Enhance pointer precision (acceleration)")
    gAccel.Value := Accel ? 1 : 0
    gAccel.OnEvent("Click", AccelToggled)

    gStartup := g.Add("CheckBox", "xm w360", "Run when Windows starts")
    gStartup.OnEvent("Click", StartupToggled)

    g.Add("Button", "xm w110 Default", "Close").OnEvent("Click", CloseSettings)

    g.OnEvent("Close", CloseSettings)
    g.OnEvent("Escape", CloseSettings)

    UpdateInfo()
}

ShowSettings(*) {
    global g, gSlider, gAccel, gStartup, Speed, Accel

    ; something else may have moved these since we last looked
    Speed := Clamp(SysGetSpeed(), 1, 20)
    Accel := SysGetAccel()
    ApplyKeyboardSpeed()

    gSlider.Value := Speed
    gAccel.Value := Accel ? 1 : 0
    gStartup.Value := FileExist(StartupLink()) ? 1 : 0
    UpdateInfo()
    g.Show()
}

CloseSettings(*) {
    global g

    Settle()
    g.Hide()
}

SliderChanged(ctrl, *) {
    global Speed

    Speed := ctrl.Value
    SysSetSpeed(Speed)
    ApplyKeyboardSpeed()
    UpdateInfo()

    ; the slider fires on every pixel of the drag, so settle before writing
    SetTimer(Settle, -400)
}

; A fast drag can outrun the Change event and drop the last one, leaving the
; slider a notch ahead of what we actually applied.  Trust the control, not
; the event, once the dust settles.
Settle() {
    global Speed, gSlider

    if (gSlider.Value != Speed) {
        Speed := gSlider.Value
        SysSetSpeed(Speed)
        ApplyKeyboardSpeed()
        UpdateInfo()
    }
    SaveConfig()
}

AccelToggled(ctrl, *) {
    global Accel

    Accel := ctrl.Value != 0
    SysSetAccel(Accel)
    UpdateInfo()
    SetTimer(SaveConfig, -600)
}

StartupToggled(ctrl, *) {
    SetStartup(ctrl.Value)
}

UpdateInfo() {
    global gInfo, Speed, Accel, fastSpeed

    scale := Round(Speed / 10.0, 2)      ; 10 is the 1:1 setting
    gInfo.Value := Format("speed {1:2} of 20   x{2} of default   accel {3}`nkeyboard arrows {4} px/s"
        , Speed, scale, Accel ? "on " : "off", Round(fastSpeed))
}

; ============================================================
;  tray
; ============================================================

BuildTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Settings", ShowSettings)
    A_TrayMenu.Add("Reload", (*) => Reload())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Settings"
    A_TrayMenu.ClickCount := 1
    A_IconTip := "Mouse Controll"
}

^+F12::ShowSettings()

; ============================================================
;  high resolution clock
; ============================================================

QPFreq() {
    DllCall("QueryPerformanceFrequency", "Int64*", &f := 0)
    return f
}

QPC() {
    static freq := QPFreq()
    DllCall("QueryPerformanceCounter", "Int64*", &c := 0)
    return c / freq
}

; ============================================================
;  LAYER: Ctrl + Shift
;
;  #HotIf tests the PHYSICAL modifier state, so the layer keeps
;  working even after the script releases Ctrl/Shift logically
;  (see ReleaseMods).
; ============================================================

#HotIf GetKeyState("Control", "P") && GetKeyState("Shift", "P")

*Up:: {
    Arrow("Up")
}

*Down:: {
    Arrow("Down")
}

*Left:: {
    Arrow("Left")
}

*Right:: {
    Arrow("Right")
}

*z:: {
    Sleep(1)
}

*x:: {
    Sleep(1)
}

#HotIf

; ---------- hide Ctrl/Shift from the foreground app while the layer is active ----------
ReleaseMods() {
    if GetKeyState("LControl", "P")
        Send("{LControl up}")
    if GetKeyState("LShift", "P")
        Send("{LShift up}")
}

RestoreMods() {
    if GetKeyState("LControl", "P")
        Send("{LControl down}")
    if GetKeyState("LShift", "P")
        Send("{LShift down}")
}

Arrow(key) {
    if GetKeyState("x", "P") {
        if (key = "Up")
            Scroll(key, "WheelUp")
        else if (key = "Down")
            Scroll(key, "WheelDown")
        else if (key = "Left")
            Scroll(key, "WheelLeft")
        else
            Scroll(key, "WheelRight")
    } else {
        MoveMouse()
    }
}

MoveMouse() {
    global fastSpeed, slowFactor, accelTime, minFactor, interval, moving
    global vL, vT, vR, vB

    if moving
        return
    moving := true

    ReleaseMods()

    accX  := 0.0
    accY  := 0.0
    start := QPC()
    prev  := start

    loop {
        if !GetKeyState("Control", "P")
            break
        if !GetKeyState("Shift", "P")
            break

        held := GetKeyState("Up", "P") || GetKeyState("Down", "P")
        held := held || GetKeyState("Left", "P") || GetKeyState("Right", "P")
        if !held
            break

        now  := QPC()
        dt   := now - prev
        prev := now
        if (dt > 0.05)
            dt := 0.05

        x := 0
        y := 0

        if GetKeyState("Left", "P")
            x -= 1
        if GetKeyState("Right", "P")
            x += 1
        if GetKeyState("Up", "P")
            y -= 1
        if GetKeyState("Down", "P")
            y += 1

        if GetKeyState("z", "P") {
            speed := fastSpeed * slowFactor
        } else {
            speed := fastSpeed
            t := ((now - start) * 1000) / accelTime
            if (t > 1)
                t := 1
            speed *= minFactor + (1 - minFactor) * t
        }

        if (x != 0 && y != 0)
            speed *= 0.7071

        accX += x * speed * dt
        accY += y * speed * dt

        mx := Round(accX)
        my := Round(accY)

        if (mx != 0 || my != 0) {
            accX -= mx
            accY -= my

            MouseGetPos(&cx, &cy)
            nx := Max(vL, Min(vR, cx + mx))
            ny := Max(vT, Min(vB, cy + my))

            if (nx != cx || ny != cy) {
                MouseMove(nx, ny, 0)
            } else {
                accX := 0.0
                accY := 0.0
            }
        }

        Sleep(interval)
    }

    RestoreMods()
    moving := false
}

Scroll(key, wheel) {
    global scrollStart, scrollMin, scrollAccel, scrolling

    if scrolling
        return
    scrolling := true

    ReleaseMods()

    start := A_TickCount

    loop {
        if !GetKeyState("Control", "P")
            break
        if !GetKeyState("Shift", "P")
            break
        if !GetKeyState("x", "P")
            break
        if !GetKeyState(key, "P")
            break

        Click(wheel)

        if GetKeyState("z", "P") {
            delay := scrollStart
        } else {
            t := (A_TickCount - start) / scrollAccel
            if (t > 1)
                t := 1
            delay := scrollStart - (scrollStart - scrollMin) * t
        }

        Sleep(Round(delay))
    }

    RestoreMods()
    scrolling := false
}

; ---------- mouse buttons ----------
; tap RCtrl  -> left click
; hold RCtrl -> left button held (drag / select text)
; RShift     -> right click
*RControl:: {
    Click("Left Down")
    KeyWait("RControl")
    Click("Left Up")
}

*RShift:: {
    Click("Right")
    KeyWait("RShift")
}

CleanUp(*) {
    Click("Left Up")
    DllCall("winmm\timeEndPeriod", "UInt", 1)
}
OnExit(CleanUp)
