' Launch snapshot.ps1 fully hidden, so the scheduled task never flashes a
' PowerShell console window. wscript starts powershell with SW_HIDE from the
' start (0 = hidden, False = do not wait), which avoids the conhost flash that
' "powershell -WindowStyle Hidden" still shows when run by Task Scheduler.
Dim shell, fso, scriptDir, ps1, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = scriptDir & "\snapshot.ps1"
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """"
shell.Run cmd, 0, False
