Set FSO = CreateObject("Scripting.FileSystemObject")
ScriptDir = FSO.GetParentFolderName(WScript.ScriptFullName)

Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = ScriptDir
psPath = WshShell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
cmd = """" & psPath & """ -NoProfile -ExecutionPolicy Bypass -STA -File """ & ScriptDir & "\KryptexOverlay.ps1"""
WshShell.Run cmd, 0, False
