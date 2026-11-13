using System;
using System.Threading;
using System.Windows;
using System.Windows.Threading;

namespace ReproductorTaskbar;

public static class Program
{
    private static MainWindow? _window;
    private static bool _exiting;

    [STAThread]
    public static void Main()
    {
        using var mutex = new Mutex(true, @"Global\NachoTaskbarMusicWidget", out bool createdNew);
        if (!createdNew) return;

        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var settings = Settings.Load();
        var media = new MediaWatcher();

        using var tray = new TrayIcon(settings,
            onCoverChanged: () => _window?.ApplyCoverVisibility(),
            onExit: () => { _exiting = true; app.Shutdown(); });

        app.Startup += async (_, _) =>
        {
            ShowWindow(media, settings);
            await media.StartAsync();
        };
        app.Exit += (_, _) => media.Dispose();
        app.Run();
    }

    /// <summary>
    /// La ventana vive dentro de la taskbar: si Explorer se reinicia, se destruye junto con ella.
    /// En ese caso se vuelve a crear cuando la taskbar nueva ya está disponible.
    /// </summary>
    private static void ShowWindow(MediaWatcher media, Settings settings)
    {
        _window = new MainWindow(media, settings);
        _window.Closed += (_, _) =>
        {
            _window = null;
            if (_exiting) return;

            var retry = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
            retry.Tick += (_, _) =>
            {
                if (TaskbarPin.FindTaskbar() == IntPtr.Zero) return;
                retry.Stop();
                ShowWindow(media, settings);
            };
            retry.Start();
        };
        _window.Show();
    }
}
