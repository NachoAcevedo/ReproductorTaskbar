Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$createdNew = $false
$script:singleInstanceMutex = New-Object System.Threading.Mutex($true, 'Global\NachoTaskbarMusicWidget', [ref]$createdNew)
if (-not $createdNew) {
    $script:singleInstanceMutex.Dispose()
    exit
}

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class MediaKeys {
    [DllImport("user32.dll", SetLastError = true)]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    private const uint KEYEVENTF_KEYUP = 0x0002;

    public const byte VK_MEDIA_PREV_TRACK = 0xB1;
    public const byte VK_MEDIA_NEXT_TRACK = 0xB0;
    public const byte VK_MEDIA_PLAY_PAUSE = 0xB3;

    public static void Press(byte virtualKey) {
        keybd_event(virtualKey, 0, 0, UIntPtr.Zero);
        keybd_event(virtualKey, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
}

public static class WindowPin {
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    private static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    private static readonly IntPtr HWND_TOP = new IntPtr(0);
    private const int GWL_STYLE = -16;
    private const int GWL_EXSTYLE = -20;
    private const int WS_CHILD = 0x40000000;
    private const int WS_POPUP = unchecked((int)0x80000000);
    private const int WS_EX_APPWINDOW = 0x00040000;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOMOVE = 0x0002;
    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint SWP_SHOWWINDOW = 0x0040;
    private const uint SWP_FRAMECHANGED = 0x0020;

    private struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public static void KeepTopMost(IntPtr hWnd) {
        SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }

    public static void HideFromAltTab(IntPtr hWnd) {
        int exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
        exStyle = (exStyle | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
        SetWindowLong(hWnd, GWL_EXSTYLE, exStyle);
    }

    public static bool AttachToTaskbar(IntPtr hWnd, int width, int height) {
        IntPtr taskbar = FindWindow("Shell_TrayWnd", null);
        if (taskbar == IntPtr.Zero) {
            return false;
        }

        int style = GetWindowLong(hWnd, GWL_STYLE);
        style = (style | WS_CHILD) & ~WS_POPUP;
        SetWindowLong(hWnd, GWL_STYLE, style);

        int exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
        exStyle = (exStyle | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
        SetWindowLong(hWnd, GWL_EXSTYLE, exStyle);

        SetParent(hWnd, taskbar);

        RECT rect;
        int y = 2;
        if (GetWindowRect(taskbar, out rect)) {
            int taskbarHeight = rect.Bottom - rect.Top;
            y = Math.Max(2, (taskbarHeight - height) / 2);
        }

        SetWindowPos(hWnd, HWND_TOP, 10, y, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
        return true;
    }
}
"@

function Wait-WinRtOperation {
    param(
        [Parameter(Mandatory = $true)] $Operation,
        [Parameter(Mandatory = $true)] [Type] $ResultType
    )

    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.IsGenericMethodDefinition -and
            $_.GetParameters().Count -eq 1
        } |
        Select-Object -First 1

    $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $task.Wait()
    return $task.Result
}

function Get-MediaInfo {
    try {
        $null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
        $manager = Get-MediaSessionManager
        $session = $manager.GetCurrentSession()

        if ($null -eq $session) {
            return @{ Title = 'Sin reproductor activo'; Artist = ''; Album = ''; IsPlaying = $false; Thumbnail = $null }
        }

        $playbackInfo = $session.GetPlaybackInfo()
        $isPlaying = ($playbackInfo.PlaybackStatus.ToString() -eq 'Playing')
        $sourceApp = $session.SourceAppUserModelId

        $propsOperation = $session.TryGetMediaPropertiesAsync()
        $propsType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties]
        $props = Wait-WinRtOperation -Operation $propsOperation -ResultType $propsType

        $title = $props.Title
        $artist = $props.Artist
        $album = $props.AlbumTitle

        if ([string]::IsNullOrWhiteSpace($title)) {
            $title = 'Reproduccion multimedia'
        }

        return @{ Title = $title; Artist = $artist; Album = $album; IsPlaying = $isPlaying; Thumbnail = $props.Thumbnail; SourceApp = $sourceApp }
    } catch {
        return @{ Title = 'Controles multimedia'; Artist = 'Metadata no disponible'; Album = ''; IsPlaying = $false; Thumbnail = $null; SourceApp = '' }
    }
}

$script:mediaManager = $null
$script:lastIsPlaying = $false
$script:showThumbnail = $false
$script:attachedToTaskbar = $false
$script:managerEventsHooked = $false
$script:currentSessionEventsHooked = $null
$script:eventTokens = @()
$script:burstTimers = New-Object System.Collections.ArrayList

function Get-MediaSessionManager {
    if ($null -eq $script:mediaManager) {
        $managerOperation = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()
        $managerType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
        $script:mediaManager = Wait-WinRtOperation -Operation $managerOperation -ResultType $managerType
    }

    return $script:mediaManager
}

function Invoke-MediaRefreshOnUi {
    param(
        [int] $DelayMilliseconds = 150
    )

    try {
        if ($null -ne $script:window) {
            $script:window.Dispatcher.BeginInvoke([Action]{
                Request-MediaRefresh -DelayMilliseconds $DelayMilliseconds
            }) | Out-Null
        }
    } catch {
    }
}

function Hook-MediaEvents {
    try {
        $manager = Get-MediaSessionManager

        if (-not $script:managerEventsHooked) {
            try {
                $token = $manager.add_CurrentSessionChanged({
                    Invoke-MediaRefreshOnUi
                })
                $script:eventTokens += $token
            } catch {
            }

            try {
                $token = $manager.add_SessionsChanged({
                    Invoke-MediaRefreshOnUi
                })
                $script:eventTokens += $token
            } catch {
            }

            $script:managerEventsHooked = $true
        }

        $session = $manager.GetCurrentSession()
        if (($null -eq $session) -or [object]::ReferenceEquals($session, $script:currentSessionEventsHooked)) {
            return
        }

        $script:currentSessionEventsHooked = $session

        try {
            $token = $session.add_PlaybackInfoChanged({
                Invoke-MediaRefreshOnUi
            })
            $script:eventTokens += $token
        } catch {
        }

        try {
            $token = $session.add_MediaPropertiesChanged({
                Invoke-MediaRefreshOnUi
            })
            $script:eventTokens += $token
        } catch {
        }

        try {
            $token = $session.add_TimelinePropertiesChanged({
                Invoke-MediaRefreshOnUi -DelayMilliseconds 250
            })
            $script:eventTokens += $token
        } catch {
        }
    } catch {
    }
}

$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Width="318"
    Height="42"
    WindowStyle="None"
    ResizeMode="NoResize"
    Topmost="True"
    AllowsTransparency="True"
    Background="Transparent"
    ShowInTaskbar="False">
    <Window.Resources>
        <Style TargetType="{x:Type Button}">
            <Setter Property="Foreground" Value="#F5F7FA" />
            <Setter Property="Background" Value="Transparent" />
            <Setter Property="BorderBrush" Value="Transparent" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="Focusable" Value="False" />
            <Setter Property="FocusVisualStyle" Value="{x:Null}" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type Button}">
                        <Border
                            x:Name="ButtonSurface"
                            Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}"
                            CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonSurface" Property="Background" Value="#2A2A2A" />
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonSurface" Property="Background" Value="#343434" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.45" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border
        Background="Transparent"
        BorderBrush="Transparent"
        BorderThickness="0"
        CornerRadius="5"
        Padding="5">
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition x:Name="CoverColumn" Width="34" />
                <ColumnDefinition Width="164" />
                <ColumnDefinition Width="*" />
            </Grid.ColumnDefinitions>

            <Border x:Name="CoverBox" Grid.Column="0" Width="28" Height="28" CornerRadius="4" Background="#1C1C1C" VerticalAlignment="Center">
                <Grid>
                    <Image x:Name="CoverImage" Stretch="UniformToFill" Visibility="Collapsed" />
                    <TextBlock x:Name="CoverFallback" Text="&#xE768;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center" />
                </Grid>
            </Border>

            <StackPanel Grid.Column="1" Margin="5,0,4,0" VerticalAlignment="Center">
                <TextBlock x:Name="TitleText" Text="Cargando..." FontSize="11" FontWeight="SemiBold" Foreground="#F5F7FA" TextTrimming="CharacterEllipsis" />
                <TextBlock x:Name="MetaText" Text="" FontSize="9" Foreground="#B8C0CC" TextTrimming="CharacterEllipsis" />
            </StackPanel>

            <StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                <Button x:Name="PrevButton" Width="28" Height="28" Margin="1" Padding="0" ToolTip="Anterior">
                    <TextBlock Text="&#xE892;" FontFamily="Segoe MDL2 Assets" FontSize="11" />
                </Button>
                <Button x:Name="PlayButton" Width="32" Height="28" Margin="1" Padding="0" ToolTip="Reproducir / pausar">
                    <TextBlock x:Name="PlayIcon" Text="&#xE768;" FontFamily="Segoe MDL2 Assets" FontSize="12" />
                </Button>
                <Button x:Name="NextButton" Width="28" Height="28" Margin="1" Padding="0" ToolTip="Siguiente">
                    <TextBlock Text="&#xE893;" FontFamily="Segoe MDL2 Assets" FontSize="11" />
                </Button>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$script:window = $window

$coverColumn = $window.FindName('CoverColumn')
$coverBox = $window.FindName('CoverBox')
$coverImage = $window.FindName('CoverImage')
$coverFallback = $window.FindName('CoverFallback')
$titleText = $window.FindName('TitleText')
$metaText = $window.FindName('MetaText')
$prevButton = $window.FindName('PrevButton')
$playButton = $window.FindName('PlayButton')
$playIcon = $window.FindName('PlayIcon')
$nextButton = $window.FindName('NextButton')

$prevButton.Add_Click({
    [MediaKeys]::Press([MediaKeys]::VK_MEDIA_PREV_TRACK)
    Start-MediaRefreshBurst
})
$playButton.Add_Click({
    [MediaKeys]::Press([MediaKeys]::VK_MEDIA_PLAY_PAUSE)
    Start-MediaRefreshBurst
})
$nextButton.Add_Click({
    [MediaKeys]::Press([MediaKeys]::VK_MEDIA_NEXT_TRACK)
    Start-MediaRefreshBurst
})

function New-MusicTrayIcon {
    $bitmap = New-Object System.Drawing.Bitmap 32, 32
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $backgroundBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 20, 24, 28))
    $rimPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 72, 82, 90)), 1
    $barBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 72, 238, 174))
    $dimBarBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 39, 165, 125))

    $graphics.FillEllipse($backgroundBrush, -2, -2, 36, 36)
    $graphics.DrawEllipse($rimPen, -1, -1, 33, 33)
    $graphics.FillRectangle($dimBarBrush, 6, 14, 5, 11)
    $graphics.FillRectangle($barBrush, 13, 6, 5, 19)
    $graphics.FillRectangle($barBrush, 21, 10, 5, 15)

    $handle = $bitmap.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($handle).Clone()

    $graphics.Dispose()
    $backgroundBrush.Dispose()
    $rimPen.Dispose()
    $barBrush.Dispose()
    $dimBarBrush.Dispose()
    $bitmap.Dispose()

    return $icon
}

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = New-MusicTrayIcon
$notifyIcon.Text = 'Reproductor Taskbar'
$notifyIcon.Visible = $true

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$thumbnailMenuItem = $trayMenu.Items.Add('Thumbnail')
$thumbnailMenuItem.Checked = $script:showThumbnail
$closeMenuItem = $trayMenu.Items.Add('Salir')
$notifyIcon.ContextMenuStrip = $trayMenu

$thumbnailMenuItem.Add_Click({
    $script:showThumbnail = -not $script:showThumbnail
    $thumbnailMenuItem.Checked = $script:showThumbnail

    $window.Dispatcher.BeginInvoke([Action]{
        Apply-ThumbnailVisibility

        if ($script:showThumbnail) {
            Start-MediaRefreshBurst
        }
    }) | Out-Null
})
$closeMenuItem.Add_Click({
    $window.Dispatcher.BeginInvoke([Action]{
        $window.Close()
    }) | Out-Null
})

function Apply-ThumbnailVisibility {
    if ($script:showThumbnail) {
        $coverColumn.Width = New-Object System.Windows.GridLength 34
        $coverBox.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $coverColumn.Width = New-Object System.Windows.GridLength 0
        $coverBox.Visibility = [System.Windows.Visibility]::Collapsed
        $coverImage.Source = $null
        $coverImage.Visibility = [System.Windows.Visibility]::Collapsed
        $coverFallback.Visibility = [System.Windows.Visibility]::Visible
    }
}

function Set-CoverThumbnail {
    param(
        $Thumbnail,
        [string] $SourceApp = ''
    )

    if (-not $script:showThumbnail) {
        return
    }

    if ($null -eq $Thumbnail) {
        $coverImage.Source = $null
        $coverImage.Visibility = [System.Windows.Visibility]::Collapsed
        $coverFallback.Visibility = [System.Windows.Visibility]::Visible
        return
    }

    $randomAccessStream = $null
    $netStream = $null
    $memoryStream = $null

    try {
        $openOperation = $Thumbnail.OpenReadAsync()
        $streamType = [Windows.Storage.Streams.IRandomAccessStreamWithContentType]
        $randomAccessStream = Wait-WinRtOperation -Operation $openOperation -ResultType $streamType

        if (($null -eq $randomAccessStream) -or ($randomAccessStream.Size -le 0)) {
            throw 'Empty thumbnail stream'
        }

        $netStream = [System.WindowsRuntimeStreamExtensions]::AsStreamForRead($randomAccessStream)
        $memoryStream = New-Object System.IO.MemoryStream
        $netStream.CopyTo($memoryStream)
        $memoryStream.Position = 0

        $bitmap = [System.Windows.Media.Imaging.BitmapFrame]::Create(
            $memoryStream,
            [System.Windows.Media.Imaging.BitmapCreateOptions]::None,
            [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        )

        if (($SourceApp -eq 'Spotify.exe' -or $SourceApp -eq 'SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify') -and
            $bitmap.PixelWidth -ge 267 -and
            $bitmap.PixelHeight -ge 234) {
            $bitmap = New-Object System.Windows.Media.Imaging.CroppedBitmap $bitmap, (New-Object System.Windows.Int32Rect 33, 0, 234, 234)
        }

        if ($bitmap.CanFreeze) {
            $bitmap.Freeze()
        }

        $coverImage.Source = $bitmap
        $coverImage.Visibility = [System.Windows.Visibility]::Visible
        $coverFallback.Visibility = [System.Windows.Visibility]::Collapsed
    } catch {
        $coverImage.Source = $null
        $coverImage.Visibility = [System.Windows.Visibility]::Collapsed
        $coverFallback.Visibility = [System.Windows.Visibility]::Visible
    } finally {
        if ($null -ne $netStream) {
            $netStream.Dispose()
        }
        if ($null -ne $memoryStream) {
            $memoryStream.Dispose()
        }
        if ($null -ne $randomAccessStream) {
            $randomAccessStream.Dispose()
        }
    }
}

function Update-MediaText {
    $info = Get-MediaInfo

    $titleText.Text = $info.Title
    if ($info.IsPlaying) {
        $playIcon.Text = [string]([char]0xE769)
    } else {
        $playIcon.Text = [string]([char]0xE768)
    }

    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($info.Artist)) { $parts += $info.Artist }
    if (-not [string]::IsNullOrWhiteSpace($info.Album)) { $parts += $info.Album }

    if ($parts.Count -gt 0) {
        $metaText.Text = ($parts -join ' - ')
    } else {
        $metaText.Text = ''
    }

    $script:lastIsPlaying = $info.IsPlaying

    if ($script:showThumbnail) {
        Set-CoverThumbnail -Thumbnail $info.Thumbnail -SourceApp $info.SourceApp
    }
}

$mediaRefreshTimer = New-Object System.Windows.Threading.DispatcherTimer
$mediaRefreshTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$mediaRefreshTimer.Add_Tick({
    $mediaRefreshTimer.Stop()
    Hook-MediaEvents
    Update-MediaText
})

$mediaFallbackTimer = New-Object System.Windows.Threading.DispatcherTimer
$mediaFallbackTimer.Interval = [TimeSpan]::FromSeconds(30)
$mediaFallbackTimer.Add_Tick({
    Request-MediaRefresh -DelayMilliseconds 0
})

function Request-MediaRefresh {
    param(
        [int] $DelayMilliseconds = 150
    )

    if ($DelayMilliseconds -lt 0) {
        $DelayMilliseconds = 0
    }

    $mediaRefreshTimer.Stop()
    $mediaRefreshTimer.Interval = [TimeSpan]::FromMilliseconds($DelayMilliseconds)
    $mediaRefreshTimer.Start()
}

function Add-DelayedMediaRefresh {
    param(
        [int] $DelayMilliseconds
    )

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($DelayMilliseconds)
    [void]$script:burstTimers.Add($timer)
    $timer.Add_Tick({
        param($sender, $eventArgs)

        $sender.Stop()
        [void]$script:burstTimers.Remove($sender)
        Request-MediaRefresh -DelayMilliseconds 0
    })
    $timer.Start()
}

function Start-MediaRefreshBurst {
    Request-MediaRefresh -DelayMilliseconds 0
    Add-DelayedMediaRefresh -DelayMilliseconds 350
    Add-DelayedMediaRefresh -DelayMilliseconds 1000
}

function Set-WidgetPosition {
    if ($script:attachedToTaskbar) {
        try {
            $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
            if ($helper.Handle -ne [IntPtr]::Zero) {
                $script:attachedToTaskbar = [WindowPin]::AttachToTaskbar($helper.Handle, [int]$window.Width, [int]$window.Height)
            }
        } catch {
        }
        return
    }

    $workArea = [System.Windows.SystemParameters]::WorkArea
    $screenHeight = [System.Windows.SystemParameters]::PrimaryScreenHeight
    $taskbarHeight = $screenHeight - $workArea.Bottom

    $window.Left = $workArea.Left + 10

    if ($taskbarHeight -gt 20) {
        $window.Top = $workArea.Bottom + [Math]::Max(2, (($taskbarHeight - $window.Height) / 2))
    } else {
        $window.Top = $workArea.Bottom - $window.Height - 8
    }
}

function Set-WidgetTopMost {
    try {
        if ($script:attachedToTaskbar) {
            return
        }

        $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
        if ($helper.Handle -ne [IntPtr]::Zero) {
            [WindowPin]::KeepTopMost($helper.Handle)
        }
    } catch {
    }
}

function Set-WidgetWindowStyles {
    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
        if ($helper.Handle -ne [IntPtr]::Zero) {
            [WindowPin]::HideFromAltTab($helper.Handle)
            $script:attachedToTaskbar = [WindowPin]::AttachToTaskbar($helper.Handle, [int]$window.Width, [int]$window.Height)

            if (-not $script:attachedToTaskbar) {
                [WindowPin]::KeepTopMost($helper.Handle)
            }
        }
    } catch {
    }
}

$pinTimer = New-Object System.Windows.Threading.DispatcherTimer
$pinTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$pinTimer.Add_Tick({
    Set-WidgetTopMost
})

$positionTimer = New-Object System.Windows.Threading.DispatcherTimer
$positionTimer.Interval = [TimeSpan]::FromSeconds(1)
$positionTimer.Add_Tick({
    Set-WidgetPosition
})

$window.Add_SourceInitialized({
    Set-WidgetWindowStyles
    Set-WidgetPosition
    Set-WidgetTopMost
    Apply-ThumbnailVisibility
    Hook-MediaEvents
    Update-MediaText
    $pinTimer.Start()
    $positionTimer.Start()
    $mediaRefreshTimer.Start()
    $mediaFallbackTimer.Start()
})

$window.Add_Deactivated({
    Set-WidgetTopMost
})

$window.Add_Closed({
    $pinTimer.Stop()
    $positionTimer.Stop()
    $mediaRefreshTimer.Stop()
    $mediaFallbackTimer.Stop()
    foreach ($timer in @($script:burstTimers)) {
        try {
            $timer.Stop()
        } catch {
        }
    }
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
})
$window.ShowDialog() | Out-Null
