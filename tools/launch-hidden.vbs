' launch-hidden.vbs -- start install-gui.ps1 / uninstall-gui.ps1 with the
' PowerShell console hidden from the moment the process is created.
'
' Why this file exists: powershell.exe is a console-subsystem binary, so
' Windows allocates its console window BEFORE it runs a single line.
' -WindowStyle Hidden is honored only once PowerShell's own startup gets
' around to processing it, which is late enough that `start PowerShell
' -WindowStyle Hidden` -- what the root .bat files did through 1.0.1 --
' flashed a console at the user on every double-click (and on Windows 11,
' where Windows Terminal is the default host, that flash is a full terminal
' window, not a bare conhost). WshShell.Run's window-style argument
' (0 = SW_HIDE) goes into the child's STARTUPINFO instead, so the console
' is born hidden and nothing ever appears on screen.
'
' The root .bat files call this through `wscript //B` and fall back to the
' old visible launch when wscript cannot run it (Windows Script Host
' disabled by policy, this file missing from the bundle). A machine that
' cannot use this file still installs; it just sees the flash this file
' removes. Every deliberate exit below is therefore nonzero-on-failure:
' the exit code IS the fallback trigger.
'
' Usage: wscript //B launch-hidden.vbs install|uninstall [args...]
' Arguments after the first are forwarded to the .ps1 verbatim. cmd's
' quoting was stripped by wscript, so anything spaced or empty is requoted;
' Windows filenames cannot contain literal quotes, so wrapping suffices.
'
' ASCII-only, like the .ps1 files: nothing here should ever need more, and
' staying ASCII keeps every mis-decoding question from arising.
Option Explicit

Dim Shell, Fso, ScriptDir, Target, Ps1, Args, I, A

If WScript.Arguments.Count < 1 Then WScript.Quit 2
Target = LCase(WScript.Arguments(0))
If Target <> "install" And Target <> "uninstall" Then WScript.Quit 2

Set Shell = CreateObject("WScript.Shell")
Set Fso = CreateObject("Scripting.FileSystemObject")
ScriptDir = Fso.GetParentFolderName(WScript.ScriptFullName)
Ps1 = ScriptDir & "\" & Target & "-gui.ps1"

' A missing .ps1 must NOT be launched hidden: the child would die where
' nobody can see it and the double-click would appear to do nothing at all.
' Quit nonzero so the .bat falls back to the visible launch, which fails
' where the user can tell something is wrong (the flash-and-die that
' package-integrity exists to prevent from shipping).
If Not Fso.FileExists(Ps1) Then WScript.Quit 3

Args = ""
For I = 1 To WScript.Arguments.Count - 1
    A = WScript.Arguments(I)
    If A = "" Or InStr(A, " ") > 0 Then A = """" & A & """"
    Args = Args & " " & A
Next

' -STA: the GUIs are WPF, which requires a single-threaded apartment.
' -WindowStyle Hidden stays as belt and braces; the load-bearing hide is
' the trailing 0 (SW_HIDE at creation). False = do not wait, so wscript --
' and the .bat console behind it -- exits immediately, as `start` did.
Shell.Run "PowerShell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & Ps1 & """" & Args, 0, False
