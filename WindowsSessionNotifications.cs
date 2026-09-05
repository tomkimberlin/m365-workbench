using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace M365Workbench.Security
{
    public static class WindowsSessionNotifications
    {
        [DllImport("wtsapi32.dll", SetLastError = true)]
        private static extern bool WTSRegisterSessionNotification(IntPtr hWnd, uint flags);

        [DllImport("wtsapi32.dll", SetLastError = true)]
        private static extern bool WTSUnRegisterSessionNotification(IntPtr hWnd);

        public static void Register(IntPtr window)
        {
            if (window == IntPtr.Zero || !WTSRegisterSessionNotification(window, 0))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to monitor Windows session security changes.");
        }

        public static void Unregister(IntPtr window)
        {
            if (window != IntPtr.Zero) WTSUnRegisterSessionNotification(window);
        }
    }
}
