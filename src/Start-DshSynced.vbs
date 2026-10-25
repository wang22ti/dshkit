Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
If WScript.Arguments.Named.Exists("CompileTest") Then WScript.Quit 0

root = fso.GetParentFolderName(WScript.ScriptFullName)
script = root & "\Start-DshSynced.ps1"
stateDir = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\DshKit"
If Not fso.FolderExists(stateDir) Then fso.CreateFolder(stateDir)
logPath = stateDir & "\managed-launch-last.log"
visibleLauncher = root & "\Start-DshSynced.cmd"
inner = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & script & Chr(34) & " > " & Chr(34) & logPath & Chr(34) & " 2>&1"
command = "cmd.exe /d /s /c " & Chr(34) & inner & Chr(34)
exitCode = shell.Run(command, 0, True)
If exitCode <> 0 Then
    message = "DSH sync launch failed (exit code " & exitCode & ")." & vbCrLf & vbCrLf & _
        "Log: " & logPath & vbCrLf & _
        "Run this launcher for visible diagnostics:" & vbCrLf & visibleLauncher
    shell.Popup message, 0, "DshKit managed startup failed", 16
End If
