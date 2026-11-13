using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ReproductorTaskbar;

/// <summary>Ícono en la bandeja del sistema con las opciones del widget.</summary>
public sealed class TrayIcon : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly Icon _image;

    public TrayIcon(Settings settings, Action onCoverChanged, Action onExit)
    {
        _image = CreateIcon();

        var cover = new ToolStripMenuItem("Carátula") { Checked = settings.ShowCover };
        cover.Click += (_, _) =>
        {
            settings.ShowCover = !settings.ShowCover;
            cover.Checked = settings.ShowCover;
            settings.Save();
            onCoverChanged();
        };

        var startup = new ToolStripMenuItem("Iniciar con Windows");
        startup.Click += (_, _) => Settings.StartWithWindows = !Settings.StartWithWindows;

        var menu = new ContextMenuStrip();
        menu.Opening += (_, _) => startup.Checked = Settings.StartWithWindows;
        menu.Items.Add(cover);
        menu.Items.Add(startup);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Salir", null, (_, _) => onExit());

        _icon = new NotifyIcon
        {
            Icon = _image,
            Text = "Reproductor Taskbar",
            ContextMenuStrip = menu,
            Visible = true
        };
    }

    /// <summary>Tres barras verdes sobre un círculo oscuro, igual que la versión anterior.</summary>
    private static Icon CreateIcon()
    {
        using var bitmap = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bitmap))
        using (var background = new SolidBrush(Color.FromArgb(20, 24, 28)))
        using (var rim = new Pen(Color.FromArgb(72, 82, 90), 1))
        using (var bar = new SolidBrush(Color.FromArgb(72, 238, 174)))
        using (var dimBar = new SolidBrush(Color.FromArgb(39, 165, 125)))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.Clear(Color.Transparent);
            g.FillEllipse(background, -2, -2, 36, 36);
            g.DrawEllipse(rim, -1, -1, 33, 33);
            g.FillRectangle(dimBar, 6, 14, 5, 11);
            g.FillRectangle(bar, 13, 6, 5, 19);
            g.FillRectangle(bar, 21, 10, 5, 15);
        }

        IntPtr handle = bitmap.GetHicon();
        try { return (Icon)Icon.FromHandle(handle).Clone(); }
        finally { DestroyIcon(handle); }
    }

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr handle);

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
        _image.Dispose();
    }
}
