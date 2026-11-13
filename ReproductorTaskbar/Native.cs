using System;
using System.Runtime.InteropServices;

namespace ReproductorTaskbar;

internal static class MediaKeys
{
    public const byte Previous = 0xB1;
    public const byte Next = 0xB0;
    public const byte PlayPause = 0xB3;

    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public static void Press(byte key)
    {
        keybd_event(key, 0, 0, UIntPtr.Zero);
        keybd_event(key, 0, 0x0002, UIntPtr.Zero);
    }
}

/// <summary>Incrusta la ventana dentro de la taskbar (Shell_TrayWnd) como ventana hija.</summary>
internal static class TaskbarPin
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr FindWindow(string lpClassName, string? lpWindowName);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern uint RegisterWindowMessage(string lpString);

    private const int GWL_STYLE = -16;
    private const int GWL_EXSTYLE = -20;
    private const int WS_CHILD = 0x40000000;
    private const int WS_POPUP = unchecked((int)0x80000000);
    private const int WS_EX_APPWINDOW = 0x00040000;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOMOVE = 0x0002;
    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint SWP_FRAMECHANGED = 0x0020;
    private const uint SWP_SHOWWINDOW = 0x0040;
    private static readonly IntPtr HWND_TOP = IntPtr.Zero;
    private static readonly IntPtr HWND_TOPMOST = new(-1);

    public static IntPtr FindTaskbar() => FindWindow("Shell_TrayWnd", null);

    public static bool TryGetRect(IntPtr hWnd, out RECT rect) => GetWindowRect(hWnd, out rect);

    public static bool IsChildOf(IntPtr hWnd, IntPtr parent) => GetParent(hWnd) == parent;

    public static void HideFromAltTab(IntPtr hWnd)
    {
        int ex = GetWindowLong(hWnd, GWL_EXSTYLE);
        SetWindowLong(hWnd, GWL_EXSTYLE, (ex | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW);
    }

    /// <summary>La mete dentro de la taskbar, a la izquierda y centrada en alto. Tamaño en píxeles físicos.</summary>
    public static bool Attach(IntPtr hWnd, IntPtr taskbar, int width, int height, int left)
    {
        if (taskbar == IntPtr.Zero || !GetWindowRect(taskbar, out var bar)) return false;

        int style = GetWindowLong(hWnd, GWL_STYLE);
        SetWindowLong(hWnd, GWL_STYLE, (style | WS_CHILD) & ~WS_POPUP);
        HideFromAltTab(hWnd);
        SetParent(hWnd, taskbar);

        int y = Math.Max(0, (bar.Bottom - bar.Top - height) / 2);
        SetWindowPos(hWnd, HWND_TOP, left, y, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
        return true;
    }

    public static void KeepTopMost(IntPtr hWnd) =>
        SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
}
