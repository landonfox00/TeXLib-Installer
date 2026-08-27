' THE installer. Double-click it; INSTALL.md documents this one. Its twin
' uninstall.vbs is BYTE-IDENTICAL on purpose: each derives install|uninstall
' from its own filename, and CI asserts the two files match so they cannot
' drift. Edit one, copy it over the other.
'
' The console/scriptable surface -- what CI drives, and what -Repair,
' -Doctor, -Verify, -Update and -Silent are documented against -- is
' tools\install-console.bat / tools\uninstall-console.bat. Same switches.
'
' Why a .vbs and not a .bat: a double-clicked .bat IS a console program, so
' Windows puts a console window on screen (a full Windows Terminal window on
' Windows 11) before the first line runs -- no content inside a .bat can
' prevent that flash. Through 1.0.1 a PowerShell console flashed too (`start
' PowerShell -WindowStyle Hidden` creates the console visible; PowerShell
' only hides it once its startup processes the switch); 1.0.2 fixed that
' half by launching PowerShell from a .vbs with SW_HIDE already in the
' child's STARTUPINFO, and this file finishes the job by removing the .bat
' from the chain entirely. wscript.exe, the interactive host that runs a
' double-clicked .vbs, is a GUI-subsystem binary: no console is ever
' allocated, so nothing appears on screen at any point.
'
' Known horizons, both with the same fallback (the console entry points in
' tools\, which involve no script host):
'   - Machines where Windows Script Host is disabled by policy show the
'     OS's own "access is disabled" message on double-click.
'   - VBScript is deprecated (an optional feature since Windows 11 24H2,
'     slated to be off by default around 2027); when a machine loses it,
'     double-click stops resolving to wscript and Windows asks how to open
'     the file.
' Neither fails silently, and INSTALL.md routes both to the console .bat.
'
' Failure notes below use WScript.Echo, which under wscript is a message
' box -- the right surface for a double-click audience. ASCII-only, like
' every script in this repo, so no decoding question ever arises.
Option Explicit

Dim Shell, Fso, ScriptDir, Target, Ps1, Args, I, A

Set Fso = CreateObject("Scripting.FileSystemObject")
Target = LCase(Fso.GetBaseName(WScript.ScriptFullName))
If Target <> "install" And Target <> "uninstall" Then
    WScript.Echo "This launcher derives its job from its filename and must be named install.vbs or uninstall.vbs; it is currently named " & Fso.GetFileName(WScript.ScriptFullName) & "."
    WScript.Quit 2
End If

ScriptDir = Fso.GetParentFolderName(WScript.ScriptFullName)
Ps1 = ScriptDir & "\tools\" & Target & "-gui.ps1"

' A missing .ps1 must NOT be launched hidden -- the child would die where
' nobody can see it and the double-click would appear to do nothing at all.
' Say what is wrong instead (the message install-gui.ps1 shows for ITS
' missing sibling, moved up one link in the chain).
If Not Fso.FileExists(Ps1) Then
    WScript.Echo "Could not find the installer script." & vbCrLf & vbCrLf & "Expected: " & Ps1 & vbCrLf & vbCrLf & "The release folder is incomplete -- re-extract the ZIP."
    WScript.Quit 3
End If

' Forward every argument verbatim. cmd/Explorer stripped the quoting, so
' anything spaced or empty is requoted; Windows filenames cannot contain
' literal quotes, so wrapping suffices.
Args = ""
For I = 0 To WScript.Arguments.Count - 1
    A = WScript.Arguments(I)
    If A = "" Or InStr(A, " ") > 0 Then A = """" & A & """"
    Args = Args & " " & A
Next

' -STA: the GUIs are WPF, which requires a single-threaded apartment.
' -WindowStyle Hidden stays as belt and braces; the load-bearing hide is
' the trailing 0 (SW_HIDE in the child's STARTUPINFO, honored from the
' first instant). False = do not wait: wscript exits immediately and the
' GUI owns the session from here.
Set Shell = CreateObject("WScript.Shell")
Shell.Run "PowerShell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & Ps1 & """" & Args, 0, False
