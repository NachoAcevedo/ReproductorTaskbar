using System;
using System.IO;
using System.Text.Json;
using Microsoft.Win32;

namespace ReproductorTaskbar;

/// <summary>Preferencias del usuario, en %AppData%\ReproductorTaskbar\settings.json.</summary>
public sealed class Settings
{
    private static readonly string Folder = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ReproductorTaskbar");
    private static readonly string FilePath = Path.Combine(Folder, "settings.json");

    private const string RunKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValue = "ReproductorTaskbar";

    public bool ShowCover { get; set; } = true;

    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings();
        }
        catch { }
        return new Settings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Folder);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }

    /// <summary>El inicio con Windows vive en el registro, no en el JSON.</summary>
    public static bool StartWithWindows
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(RunValue) is string;
        }
        set
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            if (key == null) return;
            if (value && Environment.ProcessPath is { } exe)
                key.SetValue(RunValue, $"\"{exe}\"");
            else
                key.DeleteValue(RunValue, throwOnMissingValue: false);
        }
    }
}
