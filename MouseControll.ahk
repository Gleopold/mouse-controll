#Requires AutoHotkey v2.0
; Ignore, not Force: a second launch exits and leaves the running one alone
#SingleInstance Ignore
#MaxThreadsPerHotkey 1

; ============================================================
;  Mouse Controll
;
;  Windows only offers 20 pointer speed steps, and near the low
;  end each one is a 50% jump (1/8, 1/4, 3/8 of default).  This
;  pins Windows at its neutral step and scales the movement
;  itself in a low level mouse hook, so the slider moves in
;  hundredths instead.
;
;  Settings live in %APPDATA%\mouse-controll\config.ini and are
;  reapplied at launch.
;
;  Ctrl+Shift + arrows      move the pointer
;  Ctrl+Shift + X + arrows  scroll the wheel
;  hold Z during either     fine mode
;  tap RCtrl                left click   (hold = drag)
;  RShift                   right click
;  Ctrl+Shift+F12           open settings
;  Ctrl+Shift+F11           panic switch, drop the scaler
; ============================================================

InstallKeybdHook(true)
SendMode("Input")
SetMouseDelay(-1)
CoordMode("Mouse", "Screen")
DllCall("winmm\timeBeginPeriod", "UInt", 1)

; ---------- config location ----------
CfgDir  := A_AppData "\mouse-controll"
CfgFile := CfgDir "\config.ini"

; Profiles live in the same file, one section each.  This has to be set
; here, not down beside the profile code: the auto-execute section stops
; at the first hotkey, and BuildGui() runs long before that point.
PROFILE_PREFIX := "Profile "

; ---------- the one tunable ----------
; Sensitivity as a multiple of the Windows neutral speed (step 10).
; Continuous in steps of 0.01, from 0.05 to 3.00.
Scale := 1.00

; Enhance pointer precision: the OS acceleration curve.  It runs before
; our scaling, so leaving it off is what makes the slider mean one thing.
Accel := false

; The pointer speed the user had before we took over, restored on exit.
BaseSpeed := 10

; ---------- the scaler ----------
NEUTRAL_SPEED := 10     ; the only step that neither shrinks nor stretches
hHook     := 0
hCallback := 0
sAccX     := 0.0        ; sub-pixel remainder carried between events
sAccY     := 0.0

; Windows pointer speed steps as multiples of step 10, measured on a real
; machine and matching the documented table.  Used once, to carry an old
; 1-to-20 setting over to the continuous slider.
SPEED_TABLE := [0.03125, 0.0625, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0
              , 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0, 3.25, 3.5]

; ---------- keyboard layer ----------
fastSpeed := 0      ; pixels per second at full tilt, derived from Scale
accelTime := 300    ; ms to ramp up to full speed
minFactor := 0.30   ; starting fraction of fastSpeed

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

TrayTip("Mouse Controll loaded", "Sensitivity x" Format("{:.2f}", Scale) "`nCtrl+Shift+F12 = settings", 1)

; ============================================================
;  the scaler
;
;  Windows sits at its neutral step, so what arrives here is the
;  raw count.  We swallow the real move, scale it, and place the
;  cursor ourselves, keeping the fraction we could not spend.
;  Our own SetCursorPos comes back flagged as injected, which is
;  how this avoids chasing its own tail.
; ============================================================

MouseProc(nCode, wParam, lParam) {
    global Scale, sAccX, sAccY
    static pt := Buffer(8, 0)

    if (nCode >= 0 && wParam = 0x0200) {                   ; WM_MOUSEMOVE
        if !(NumGet(lParam, 12, "UInt") & 1) {             ; LLMHF_INJECTED
            DllCall("GetCursorPos", "Ptr", pt)
            cx := NumGet(pt, 0, "Int")
            cy := NumGet(pt, 4, "Int")

            sAccX += (NumGet(lParam, 0, "Int") - cx) * Scale
            sAccY += (NumGet(lParam, 4, "Int") - cy) * Scale

            mx := Round(sAccX)
            my := Round(sAccY)
            sAccX -= mx
            sAccY -= my

            if (mx != 0 || my != 0)
                DllCall("SetCursorPos", "Int", cx + mx, "Int", cy + my)

            return 1                                        ; swallow the original
        }
    }
    return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

ScalerOn() {
    global hHook, hCallback, sAccX, sAccY

    if hHook
        return
    sAccX := 0.0
    sAccY := 0.0
    hCallback := CallbackCreate(MouseProc, "Fast", 3)
    hHook := DllCall("SetWindowsHookEx"
        , "Int", 14                                          ; WH_MOUSE_LL
        , "Ptr", hCallback
        , "Ptr", DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
        , "UInt", 0
        , "Ptr")
}

ScalerOff() {
    global hHook, hCallback

    if hHook {
        DllCall("UnhookWindowsHookEx", "Ptr", hHook)
        hHook := 0
    }
    if hCallback {
        CallbackFree(hCallback)
        hCallback := 0
    }
}

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
    global NEUTRAL_SPEED, Accel

    SysSetSpeed(NEUTRAL_SPEED)
    SysSetAccel(Accel)
    ApplyKeyboardSpeed()
    ScalerOn()
}

; The keyboard layer tracks the same slider, so both pointers agree
; about what slow means.
ApplyKeyboardSpeed() {
    global Scale, fastSpeed

    fastSpeed := Clamp(2000 * Scale, 300, 4000)
}

; ============================================================
;  config
; ============================================================

LoadConfig() {
    global CfgFile, Scale, Accel, BaseSpeed, SPEED_TABLE

    raw := FileExist(CfgFile) ? IniRead(CfgFile, "Mouse", "Scale", "") : ""
    old := FileExist(CfgFile) ? IniRead(CfgFile, "Mouse", "Speed", "") : ""

    if (raw != "") {
        try Scale := Number(raw)
        try Accel := Integer(IniRead(CfgFile, "Mouse", "Accel", "0")) != 0
        try BaseSpeed := Integer(IniRead(CfgFile, "Mouse", "BaseSpeed", "10"))
    } else if (old != "") {
        ; carry a 1-to-20 setting from the previous version over unchanged
        try BaseSpeed := Clamp(Integer(old), 1, 20)
        try Accel := Integer(IniRead(CfgFile, "Mouse", "Accel", "0")) != 0
        Scale := SPEED_TABLE[BaseSpeed]
    } else {
        ; first run: match what Windows is set to now, so nothing changes feel
        BaseSpeed := Clamp(SysGetSpeed(), 1, 20)
        Accel := SysGetAccel()
        Scale := SPEED_TABLE[BaseSpeed]
    }

    Scale := Clamp(Round(Scale, 2), 0.05, 3.00)
    BaseSpeed := Clamp(BaseSpeed, 1, 20)
    ApplyToSystem()
    SaveConfig()
}

SaveConfig() {
    global CfgDir, CfgFile, Scale, Accel, BaseSpeed

    if !DirExist(CfgDir)
        DirCreate(CfgDir)
    IniWrite(Format("{:.2f}", Scale), CfgFile, "Mouse", "Scale")
    IniWrite(Accel ? 1 : 0, CfgFile, "Mouse", "Accel")
    IniWrite(BaseSpeed, CfgFile, "Mouse", "BaseSpeed")
    ; Speed belonged to the previous version and would be read back on load
    try IniDelete(CfgFile, "Mouse", "Speed")
}

Clamp(v, lo, hi) {
    return v < lo ? lo : (v > hi ? hi : v)
}

; ============================================================
;  profiles
;
;  Named settings kept in the same file, one section each, so a
;  slow one for drawing and a fast one for everything else are a
;  dropdown apart.  [Mouse] stays the live setting.
;  PROFILE_PREFIX is set up at the top, with the config paths.
; ============================================================

ProfileNames() {
    global CfgFile, PROFILE_PREFIX

    names := []
    if !FileExist(CfgFile)
        return names

    for _, sec in StrSplit(IniRead(CfgFile), "`n", "`r") {
        if (SubStr(sec, 1, StrLen(PROFILE_PREFIX)) = PROFILE_PREFIX)
            names.Push(SubStr(sec, StrLen(PROFILE_PREFIX) + 1))
    }
    return names
}

RefreshProfiles(select := "") {
    global gProfiles

    names := ProfileNames()
    gProfiles.Delete()
    if names.Length
        gProfiles.Add(names)

    if (select != "")
        gProfiles.Text := select
    else if names.Length
        gProfiles.Value := 1
}

SaveProfile(*) {
    global CfgDir, CfgFile, PROFILE_PREFIX, Scale, Accel, gProfiles

    ib := InputBox("Name for the current setting", "Save profile", "w320 h130", gProfiles.Text)
    if (ib.Result != "OK")
        return

    name := Trim(ib.Value)
    if (name = "")
        return
    ; section names cannot carry these and still be readable back
    name := RegExReplace(name, "[\[\]=`r`n]", "")
    if (name = "")
        return

    if !DirExist(CfgDir)
        DirCreate(CfgDir)
    IniWrite(Format("{:.2f}", Scale), CfgFile, PROFILE_PREFIX name, "Scale")
    IniWrite(Accel ? 1 : 0, CfgFile, PROFILE_PREFIX name, "Accel")
    RefreshProfiles(name)
    UpdateInfo()
}

LoadProfile(*) {
    global CfgFile, PROFILE_PREFIX, Scale, Accel, gProfiles, gSlider, gAccel

    name := gProfiles.Text
    if (name = "")
        return

    raw := IniRead(CfgFile, PROFILE_PREFIX name, "Scale", "")
    if (raw = "")
        return

    try Scale := Clamp(Round(Number(raw), 2), 0.05, 3.00)
    try Accel := Integer(IniRead(CfgFile, PROFILE_PREFIX name, "Accel", "0")) != 0

    SysSetAccel(Accel)
    ApplyKeyboardSpeed()

    gSlider.Value := Round(Scale * 100)
    gAccel.Value := Accel ? 1 : 0
    UpdateInfo()
    SaveConfig()
}

DeleteProfile(*) {
    global CfgFile, PROFILE_PREFIX, gProfiles

    name := gProfiles.Text
    if (name = "")
        return
    if (MsgBox("Delete the profile " name "?", "Mouse Controll", "YesNo Icon?") != "Yes")
        return

    try IniDelete(CfgFile, PROFILE_PREFIX name)
    RefreshProfiles()
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
    global g, gSlider, gInfo, gAccel, gStartup, gProfiles, Scale, Accel

    g := Gui("+AlwaysOnTop -MinimizeBox", "Mouse Controll")
    g.MarginX := 16
    g.MarginY := 14

    g.SetFont("s11 w600", "Segoe UI")
    g.Add("Text", "xm w380", "Sensitivity")

    g.SetFont("s9 w400", "Segoe UI")
    g.Add("Text", "xm w380 cGray", "Your mouse, every app. Arrow keys nudge by 0.01.")

    gSlider := g.Add("Slider", "xm w380 Range5-300 Page10 TickInterval25 ToolTip", Round(Scale * 100))
    gSlider.OnEvent("Change", SliderChanged)

    g.Add("Text", "xm w185 cGray", "0.05  slow, precise")
    g.Add("Text", "x+10 w185 Right cGray", "fast  3.00")

    g.SetFont("s9 w400", "Consolas")
    gInfo := g.Add("Text", "xm w380 h34", "")

    g.SetFont("s9 w400", "Segoe UI")
    gAccel := g.Add("CheckBox", "xm w380", "Enhance pointer precision (acceleration)")
    gAccel.Value := Accel ? 1 : 0
    gAccel.OnEvent("Click", AccelToggled)

    gStartup := g.Add("CheckBox", "xm w380", "Run when Windows starts")
    gStartup.OnEvent("Click", StartupToggled)

    g.SetFont("s11 w600", "Segoe UI")
    g.Add("Text", "xm w380 Section", "Profiles")

    g.SetFont("s9 w400", "Segoe UI")
    ; an empty array is not a valid control list, so fill it after the fact
    gProfiles := g.Add("DropDownList", "xm w164")
    RefreshProfiles()
    g.Add("Button", "x+8 w64", "Save").OnEvent("Click", SaveProfile)
    g.Add("Button", "x+8 w64", "Load").OnEvent("Click", LoadProfile)
    g.Add("Button", "x+8 w64", "Delete").OnEvent("Click", DeleteProfile)

    g.Add("Button", "xm w110 Default", "Close").OnEvent("Click", CloseSettings)

    g.OnEvent("Close", CloseSettings)
    g.OnEvent("Escape", CloseSettings)

    UpdateInfo()
}

ShowSettings(*) {
    global g, gSlider, gAccel, gStartup, Scale, Accel

    Accel := SysGetAccel()
    gSlider.Value := Round(Scale * 100)
    gAccel.Value := Accel ? 1 : 0
    gStartup.Value := FileExist(StartupLink()) ? 1 : 0
    RefreshProfiles()
    UpdateInfo()
    g.Show()
}

CloseSettings(*) {
    global g

    Settle()
    g.Hide()
}

SliderChanged(ctrl, *) {
    global Scale

    Scale := ctrl.Value / 100.0
    ApplyKeyboardSpeed()
    UpdateInfo()

    ; the slider fires on every pixel of the drag, so settle before writing
    SetTimer(Settle, -400)
}

; A fast drag can outrun the Change event and drop the last one, leaving the
; slider a notch ahead of what we actually applied.  Trust the control, not
; the event, once the dust settles.
Settle() {
    global Scale, gSlider

    if (gSlider.Value != Round(Scale * 100)) {
        Scale := gSlider.Value / 100.0
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
    SetTimer(Settle, -400)
}

StartupToggled(ctrl, *) {
    SetStartup(ctrl.Value)
}

UpdateInfo() {
    global gInfo, Scale, fastSpeed, hHook

    step := Round(100 / (Scale * 100), 1)     ; one notch as a percentage of here
    gInfo.Value := Format("x{1:.2f} of Windows default   one notch = {2}%`nscaler {3}   keyboard arrows {4} px/s"
        , Scale, step, hHook ? "on " : "OFF", Round(fastSpeed))
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

; Panic switch: drop the scaler and hand the mouse back to Windows
^+F11:: {
    global hHook, BaseSpeed, Scale

    if hHook {
        ScalerOff()
        SysSetSpeed(BaseSpeed)
        TrayTip("Scaler off", "Windows pointer speed back to " BaseSpeed, 1)
    } else {
        ApplyToSystem()
        TrayTip("Scaler on", "Sensitivity x" Format("{:.2f}", Scale), 1)
    }
    UpdateInfo()
}

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

; Hand the mouse back exactly as we found it.  Also fires on logoff and
; shutdown; a hard kill is the one case that leaves Windows on the
; neutral step, which the next launch puts right.
CleanUp(*) {
    global BaseSpeed

    ScalerOff()
    SysSetSpeed(BaseSpeed)
    Click("Left Up")
    DllCall("winmm\timeEndPeriod", "UInt", 1)
}
OnExit(CleanUp)
