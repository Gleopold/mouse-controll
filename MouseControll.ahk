#Requires AutoHotkey v2.0
; Ignore, not Force: a second launch exits and leaves the running one alone
#SingleInstance Ignore
#MaxThreadsPerHotkey 1

; ============================================================
;  Mouse Controll - keyboard driven pointer with one precision
;  slider.  Settings live in %APPDATA%\mouse-controll\config.ini
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

; ---------- config location ----------
CfgDir  := A_AppData "\mouse-controll"
CfgFile := CfgDir "\config.ini"

; ---------- the one tunable ----------
; 1   = fastest, coarsest
; 100 = slowest, finest
Precision := 50

; ---------- derived from Precision by ApplyPrecision() ----------
fastSpeed := 0      ; pixels per second at full tilt
accelTime := 0      ; ms to ramp up to full speed
minFactor := 0      ; starting fraction of fastSpeed

; ---------- fixed feel ----------
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

TrayTip("Mouse Controll loaded", "Ctrl+Shift+arrows = move`nCtrl+Shift+F12 = settings", 1)

; ============================================================
;  config
; ============================================================

LoadConfig() {
    global CfgFile, Precision

    if FileExist(CfgFile) {
        try Precision := Integer(IniRead(CfgFile, "MouseKeys", "Precision", "50"))
    }
    Precision := Clamp(Precision, 1, 100)
    ApplyPrecision()
}

SaveConfig() {
    global CfgDir, CfgFile, Precision

    if !DirExist(CfgDir)
        DirCreate(CfgDir)
    IniWrite(Precision, CfgFile, "MouseKeys", "Precision")
}

; One slider, three knobs.  Higher precision means a lower top speed,
; a gentler ramp and a smaller first step, so a short tap nudges the
; pointer a few pixels instead of throwing it across the screen.
ApplyPrecision() {
    global Precision, fastSpeed, accelTime, minFactor

    t := (Precision - 1) / 99.0          ; 0.0 .. 1.0

    fastSpeed := 4000 * (0.1 ** t)       ; 4000 -> 400 px/s, logarithmic
    accelTime := 120 + 280 * t           ;  120 -> 400 ms
    minFactor := 0.45 - 0.25 * t         ; 0.45 -> 0.20
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
    global g, gSlider, gInfo, gStartup, Precision

    g := Gui("+AlwaysOnTop -MinimizeBox", "Mouse Controll")
    g.MarginX := 16
    g.MarginY := 14

    g.SetFont("s11 w600", "Segoe UI")
    g.Add("Text", "xm w360", "Precision")

    g.SetFont("s9 w400", "Segoe UI")
    g.Add("Text", "xm w360 cGray", "Drag left for speed, right for control.")

    gSlider := g.Add("Slider", "xm w360 Range1-100 TickInterval10 ToolTip", Precision)
    gSlider.OnEvent("Change", SliderChanged)

    g.Add("Text", "xm w175 cGray", "fast")
    g.Add("Text", "x+10 w175 Right cGray", "fine")

    g.SetFont("s9 w400", "Consolas")
    gInfo := g.Add("Text", "xm w360 h34", "")

    g.SetFont("s9 w400", "Segoe UI")
    gStartup := g.Add("CheckBox", "xm w360", "Run when Windows starts")
    gStartup.OnEvent("Click", StartupToggled)

    g.Add("Button", "xm w110 Default", "Close").OnEvent("Click", CloseSettings)

    g.OnEvent("Close", CloseSettings)
    g.OnEvent("Escape", CloseSettings)

    UpdateInfo()
}

ShowSettings(*) {
    global g, gSlider, gStartup, Precision

    gSlider.Value := Precision
    gStartup.Value := FileExist(StartupLink()) ? 1 : 0
    UpdateInfo()
    g.Show()
}

CloseSettings(*) {
    global g

    SaveConfig()
    g.Hide()
}

SliderChanged(ctrl, *) {
    global Precision

    Precision := ctrl.Value
    ApplyPrecision()
    UpdateInfo()

    ; the slider fires on every pixel of the drag, so settle before writing
    SetTimer(SaveConfig, -600)
}

UpdateInfo() {
    global gInfo, Precision, fastSpeed, slowFactor, minFactor

    ; how far a short tap of roughly 60 ms carries the pointer
    tap := Round(fastSpeed * minFactor * 0.06)

    gInfo.Value := Format("level {1:3}   top {2:4} px/s   fine {3:4} px/s`ntap moves about {4} px"
        , Precision, Round(fastSpeed), Round(fastSpeed * slowFactor), tap)
}

StartupToggled(ctrl, *) {
    SetStartup(ctrl.Value)
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
