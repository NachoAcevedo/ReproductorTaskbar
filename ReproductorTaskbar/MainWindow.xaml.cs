using System;
using System.Linq;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace ReproductorTaskbar;

public partial class MainWindow : Window
{
    private const int LeftMarginPx = 10;

    private readonly MediaWatcher _media;
    private readonly Settings _settings;
    private readonly DispatcherTimer _placementTimer = new() { Interval = TimeSpan.FromSeconds(2) };
    private IntPtr _hwnd;
    private IntPtr _taskbar;
    private TaskbarPin.RECT _taskbarRect;
    private bool _attached;

    public MainWindow(MediaWatcher media, Settings settings)
    {
        InitializeComponent();
        _media = media;
        _settings = settings;

        _media.TrackChanged += ShowTrack;
        _media.PlaybackChanged += ShowPlayback;
        _media.CoverChanged += ShowCover;

        SourceInitialized += (_, _) =>
        {
            _hwnd = new WindowInteropHelper(this).Handle;
            TaskbarPin.HideFromAltTab(_hwnd);
            Place();
        };

        // Chequeo liviano: solo actúa si la taskbar cambió (se reinició Explorer, cambió de
        // alto o de escala). Mientras está incrustada no hace falta reforzar nada más.
        _placementTimer.Tick += (_, _) => KeepPlaced();
        _placementTimer.Start();

        Closed += (_, _) =>
        {
            _placementTimer.Stop();
            _media.TrackChanged -= ShowTrack;
            _media.PlaybackChanged -= ShowPlayback;
            _media.CoverChanged -= ShowCover;
        };

        ApplyCoverVisibility();
        ShowTrack();
        ShowPlayback();
        ShowCover();
    }

    public void ApplyCoverVisibility()
    {
        bool show = _settings.ShowCover;
        CoverColumn.Width = new GridLength(show ? 34 : 0);
        CoverBox.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
    }

    private void ShowTrack()
    {
        var track = _media.Track;
        TitleText.Text = track.Title;
        MetaText.Text = string.Join(" - ", new[] { track.Artist, track.Album }.Where(s => !string.IsNullOrWhiteSpace(s)));
    }

    private void ShowPlayback() =>
        PlayIcon.Text = _media.IsPlaying ? "" : "";

    private void ShowCover()
    {
        CoverImage.Source = _media.Cover;
        CoverFallback.Visibility = _media.Cover == null ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void OnPrevious(object sender, RoutedEventArgs e) => await _media.PreviousAsync();
    private async void OnPlayPause(object sender, RoutedEventArgs e) => await _media.PlayPauseAsync();
    private async void OnNext(object sender, RoutedEventArgs e) => await _media.NextAsync();

    private void KeepPlaced()
    {
        if (_hwnd == IntPtr.Zero) return;

        var taskbar = TaskbarPin.FindTaskbar();
        bool changed = taskbar != _taskbar
            || (_attached && !TaskbarPin.IsChildOf(_hwnd, taskbar))
            || (TaskbarPin.TryGetRect(taskbar, out var rect) && !SameRect(rect, _taskbarRect));

        if (changed) Place();
        else if (!_attached) TaskbarPin.KeepTopMost(_hwnd);
    }

    private void Place()
    {
        _taskbar = TaskbarPin.FindTaskbar();
        TaskbarPin.TryGetRect(_taskbar, out _taskbarRect);

        var dpi = VisualTreeHelper.GetDpi(this);
        int widthPx = (int)Math.Ceiling(Width * dpi.DpiScaleX);
        int heightPx = (int)Math.Ceiling(Height * dpi.DpiScaleY);

        _attached = TaskbarPin.Attach(_hwnd, _taskbar, widthPx, heightPx, LeftMarginPx);
        if (_attached) return;

        // Sin taskbar a la que engancharse: se superpone sobre esa zona, siempre visible.
        var work = SystemParameters.WorkArea;
        double taskbarHeight = SystemParameters.PrimaryScreenHeight - work.Bottom;
        Left = work.Left + LeftMarginPx / dpi.DpiScaleX;
        Top = taskbarHeight > 20
            ? work.Bottom + Math.Max(2, (taskbarHeight - Height) / 2)
            : work.Bottom - Height - 8;
        TaskbarPin.KeepTopMost(_hwnd);
    }

    private static bool SameRect(TaskbarPin.RECT a, TaskbarPin.RECT b) =>
        a.Left == b.Left && a.Top == b.Top && a.Right == b.Right && a.Bottom == b.Bottom;
}
