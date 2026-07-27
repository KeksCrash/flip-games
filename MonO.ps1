Start-Sleep -Seconds 5

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class MonitorPower
{
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(
        IntPtr hWnd,
        uint Msg,
        IntPtr wParam,
        IntPtr lParam
    );
}
"@

[MonitorPower]::SendMessage(
    [IntPtr]0xFFFF,
    0x0112,
    [IntPtr]0xF170,
    [IntPtr]2
) | Out-Null
