Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

projectFolder = fso.GetParentFolderName(WScript.ScriptFullName)
launcherPath = fso.BuildPath(projectFolder, "Reproductor Taskbar.vbs")
startupFolder = shell.SpecialFolders("Startup")
shortcutPath = fso.BuildPath(startupFolder, "Reproductor Taskbar.lnk")

Set shortcut = shell.CreateShortcut(shortcutPath)
shortcut.TargetPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\wscript.exe")
shortcut.Arguments = Chr(34) & launcherPath & Chr(34)
shortcut.WorkingDirectory = projectFolder
shortcut.Description = "Reproductor Taskbar"
shortcut.Save

shell.Popup "Reproductor Taskbar se iniciara con Windows.", 4, "Reproductor Taskbar", 64
