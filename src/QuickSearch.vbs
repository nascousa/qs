Option Explicit

Dim fileSystem
Dim shell
Dim scriptDirectory
Dim quickSearchScript
Dim command

Set fileSystem = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
quickSearchScript = fileSystem.BuildPath(scriptDirectory, "QuickSearch.ps1")

If Not fileSystem.FileExists(quickSearchScript) Then
    MsgBox "QuickSearch.ps1 was not found next to this launcher." & vbCrLf & "Expected: " & quickSearchScript, vbCritical, "QuickSearch"
    WScript.Quit 1
End If

command = "PowerShell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & QuoteArgument(quickSearchScript)
shell.Run command, 0, False
WScript.Quit 0

Function QuoteArgument(ByVal value)
    QuoteArgument = """" & Replace(value, """", """""") & """"
End Function