Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

shortcutPath = fso.BuildPath(shell.SpecialFolders("Startup"), "Reproductor Taskbar.lnk")

If fso.FileExists(shortcutPath) Then
    fso.DeleteFile shortcutPath
    shell.Popup "Reproductor Taskbar ya no se iniciara con Windows.", 4, "Reproductor Taskbar", 64
Else
    shell.Popup "No habia inicio automatico configurado.", 4, "Reproductor Taskbar", 64
End If
