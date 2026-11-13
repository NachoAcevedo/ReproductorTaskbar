using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media.Imaging;
using Windows.Media.Control;

namespace ReproductorTaskbar;

public sealed record TrackInfo(string Title, string Artist, string Album, bool HasSession);

/// <summary>
/// Sigue la sesión multimedia actual de Windows (la misma que muestra el panel de volumen).
/// Todo es asíncrono y por eventos: no hay polling ni esperas que bloqueen la ventana.
/// Los eventos de WinRT llegan en otros hilos, así que se pasan al hilo de la UI.
/// </summary>
public sealed class MediaWatcher : IDisposable
{
    private GlobalSystemMediaTransportControlsSessionManager? _manager;
    private GlobalSystemMediaTransportControlsSession? _session;
    private string? _coverKey;
    private int _propertiesVersion;

    public TrackInfo Track { get; private set; } = new("Sin reproductor activo", "", "", false);
    public bool IsPlaying { get; private set; }
    public BitmapSource? Cover { get; private set; }

    /// <summary>Cambió el título, artista o álbum.</summary>
    public event Action? TrackChanged;
    /// <summary>Cambió play/pausa.</summary>
    public event Action? PlaybackChanged;
    /// <summary>Cambió la carátula (puede ser null).</summary>
    public event Action? CoverChanged;

    public async Task StartAsync()
    {
        try
        {
            _manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            _manager.CurrentSessionChanged += OnCurrentSessionChanged;
            Attach(_manager.GetCurrentSession());
        }
        catch
        {
            Track = new TrackInfo("Controles multimedia", "Metadata no disponible", "", false);
            TrackChanged?.Invoke();
        }
    }

    private void OnCurrentSessionChanged(GlobalSystemMediaTransportControlsSessionManager sender, CurrentSessionChangedEventArgs args) =>
        OnUi(() => Attach(sender.GetCurrentSession()));

    private void Attach(GlobalSystemMediaTransportControlsSession? session)
    {
        // Soltar la sesión anterior: si no, sus eventos siguen llegando y se acumulan.
        if (_session != null)
        {
            _session.MediaPropertiesChanged -= OnMediaPropertiesChanged;
            _session.PlaybackInfoChanged -= OnPlaybackInfoChanged;
        }

        _session = session;

        if (_session == null)
        {
            _propertiesVersion++;
            Track = new TrackInfo("Sin reproductor activo", "", "", false);
            IsPlaying = false;
            SetCover(null, null);
            TrackChanged?.Invoke();
            PlaybackChanged?.Invoke();
            return;
        }

        _session.MediaPropertiesChanged += OnMediaPropertiesChanged;
        _session.PlaybackInfoChanged += OnPlaybackInfoChanged;
        UpdatePlayback();
        _ = UpdatePropertiesAsync();
    }

    private void OnMediaPropertiesChanged(GlobalSystemMediaTransportControlsSession sender, MediaPropertiesChangedEventArgs args) =>
        OnUi(() => { if (sender == _session) _ = UpdatePropertiesAsync(); });

    private void OnPlaybackInfoChanged(GlobalSystemMediaTransportControlsSession sender, PlaybackInfoChangedEventArgs args) =>
        OnUi(() => { if (sender == _session) UpdatePlayback(); });

    private void UpdatePlayback()
    {
        try
        {
            bool playing = _session?.GetPlaybackInfo()?.PlaybackStatus ==
                GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
            if (playing == IsPlaying) return;
            IsPlaying = playing;
            PlaybackChanged?.Invoke();
        }
        catch { }
    }

    private async Task UpdatePropertiesAsync()
    {
        var session = _session;
        if (session == null) return;
        int version = ++_propertiesVersion;

        try
        {
            var props = await session.TryGetMediaPropertiesAsync();
            // Si mientras tanto cambió la sesión o llegó otro evento, este resultado ya es viejo.
            if (props == null || version != _propertiesVersion) return;

            string title = string.IsNullOrWhiteSpace(props.Title) ? "Reproducción multimedia" : props.Title;
            var track = new TrackInfo(title, props.Artist ?? "", props.AlbumTitle ?? "", true);
            if (track != Track)
            {
                Track = track;
                TrackChanged?.Invoke();
            }

            // La carátula solo se decodifica cuando cambia la canción (o llega por primera vez).
            string coverKey = $"{session.SourceAppUserModelId}|{track.Title}|{track.Artist}|{track.Album}";
            if (coverKey == _coverKey && Cover != null) return;

            var cover = await LoadCoverAsync(props.Thumbnail, session.SourceAppUserModelId);
            if (version != _propertiesVersion) return;
            SetCover(cover, cover == null ? null : coverKey);
        }
        catch { }
    }

    private void SetCover(BitmapSource? cover, string? key)
    {
        _coverKey = key;
        if (ReferenceEquals(cover, Cover)) return;
        Cover = cover;
        CoverChanged?.Invoke();
    }

    private static async Task<BitmapSource?> LoadCoverAsync(Windows.Storage.Streams.IRandomAccessStreamReference? thumbnail, string? sourceApp)
    {
        if (thumbnail == null) return null;
        try
        {
            using var stream = await thumbnail.OpenReadAsync();
            if (stream.Size == 0) return null;

            using var memory = new MemoryStream();
            await stream.AsStreamForRead().CopyToAsync(memory);
            memory.Position = 0;

            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.StreamSource = memory;
            bitmap.EndInit();
            bitmap.Freeze();

            return CropSpotifyBorders(bitmap, sourceApp);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Spotify publica la carátula dentro de un lienzo con márgenes: la imagen útil es
    /// 234x234 a partir de x=33, y=0. Mismo recorte que hacía el script original.
    /// </summary>
    private static BitmapSource CropSpotifyBorders(BitmapSource bitmap, string? sourceApp)
    {
        bool spotify = sourceApp != null && sourceApp.Contains("Spotify", StringComparison.OrdinalIgnoreCase);
        if (!spotify || bitmap.PixelWidth < 267 || bitmap.PixelHeight < 234) return bitmap;

        var cropped = new CroppedBitmap(bitmap, new Int32Rect(33, 0, 234, 234));
        cropped.Freeze();
        return cropped;
    }

    // Controles: se mandan a la sesión actual; sin sesión, se usan las teclas multimedia.
    public Task PreviousAsync() => Send(s => s.TrySkipPreviousAsync().AsTask(), MediaKeys.Previous);
    public Task PlayPauseAsync() => Send(s => s.TryTogglePlayPauseAsync().AsTask(), MediaKeys.PlayPause);
    public Task NextAsync() => Send(s => s.TrySkipNextAsync().AsTask(), MediaKeys.Next);

    private async Task Send(Func<GlobalSystemMediaTransportControlsSession, Task<bool>> command, byte fallbackKey)
    {
        try
        {
            if (_session != null && await command(_session)) return;
        }
        catch { }
        MediaKeys.Press(fallbackKey);
    }

    private static void OnUi(Action action) =>
        Application.Current?.Dispatcher.BeginInvoke(action);

    public void Dispose()
    {
        if (_session != null)
        {
            _session.MediaPropertiesChanged -= OnMediaPropertiesChanged;
            _session.PlaybackInfoChanged -= OnPlaybackInfoChanged;
        }
        if (_manager != null)
            _manager.CurrentSessionChanged -= OnCurrentSessionChanged;
    }
}
