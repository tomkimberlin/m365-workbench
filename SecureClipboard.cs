using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace M365Workbench.Security
{
    /// <summary>
    /// Places sensitive text on the Windows clipboard while explicitly excluding
    /// it from Clipboard History and Cloud Clipboard synchronization.
    /// </summary>
    public static class SecureClipboard
    {
        private const uint CfUnicodeText = 13;
        private const uint GmemMoveable = 0x0002;
        private const string ExcludeFormatName = "ExcludeClipboardContentFromMonitorProcessing";
        private const string HistoryFormatName = "CanIncludeInClipboardHistory";
        private const string CloudFormatName = "CanUploadToCloudClipboard";

        private static readonly object Gate = new object();
        private static uint _ownedSequence;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool OpenClipboard(IntPtr hWndNewOwner);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool CloseClipboard();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool EmptyClipboard();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint RegisterClipboardFormat(string lpszFormat);

        [DllImport("user32.dll")]
        private static extern uint GetClipboardSequenceNumber();

        [DllImport("user32.dll")]
        private static extern bool IsWindow(IntPtr hWnd);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GlobalLock(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GlobalUnlock(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GlobalFree(IntPtr hMem);

        public static bool ProtectionFormatsAvailable()
        {
            return RegisterClipboardFormat(ExcludeFormatName) != 0
                && RegisterClipboardFormat(HistoryFormatName) != 0
                && RegisterClipboardFormat(CloudFormatName) != 0;
        }

        public static void SetSensitiveText(string text, IntPtr ownerWindow)
        {
            if (string.IsNullOrEmpty(text))
            {
                throw new ArgumentException("Clipboard text cannot be empty.", nameof(text));
            }
            if (ownerWindow == IntPtr.Zero || !IsWindow(ownerWindow))
            {
                throw new ArgumentException("A valid clipboard owner window is required.", nameof(ownerWindow));
            }

            byte[] textBytes = null;
            lock (Gate)
            {
                OpenClipboardWithRetry(ownerWindow);
                try
                {
                    if (!EmptyClipboard())
                    {
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to clear the clipboard.");
                    }

                    uint excludeFormat = RegisterRequiredFormat(ExcludeFormatName);
                    uint historyFormat = RegisterRequiredFormat(HistoryFormatName);
                    uint cloudFormat = RegisterRequiredFormat(CloudFormatName);

                    // Any payload in ExcludeClipboardContentFromMonitorProcessing opts the
                    // entire clipboard item out. The DWORD zero markers provide a second,
                    // explicit opt-out for history and cloud synchronization.
                    SetClipboardBytes(excludeFormat, new byte[] { 0 });
                    SetClipboardBytes(historyFormat, new byte[] { 0, 0, 0, 0 });
                    SetClipboardBytes(cloudFormat, new byte[] { 0, 0, 0, 0 });

                    textBytes = Encoding.Unicode.GetBytes(text + '\0');
                    SetClipboardBytes(CfUnicodeText, textBytes);
                    // Capture ownership while the native clipboard lock still excludes
                    // other writers. Capturing after CloseClipboard can claim their data.
                    _ownedSequence = GetClipboardSequenceNumber();
                }
                catch
                {
                    // Fail closed if Windows cannot attach the protection formats.
                    EmptyClipboard();
                    _ownedSequence = 0;
                    throw;
                }
                finally
                {
                    CloseClipboard();
                    if (textBytes != null)
                    {
                        CryptographicOperations.ZeroMemory(textBytes);
                    }
                }
            }
        }

        /// <summary>
        /// Clears the clipboard only if it still contains the item most recently
        /// written by this process. A user's newer clipboard content is never erased.
        /// </summary>
        public static bool ClearIfUnchanged()
        {
            lock (Gate)
            {
                if (_ownedSequence == 0 || GetClipboardSequenceNumber() != _ownedSequence)
                {
                    _ownedSequence = 0;
                    return false;
                }

                OpenClipboardWithRetry(IntPtr.Zero);
                try
                {
                    if (GetClipboardSequenceNumber() != _ownedSequence)
                    {
                        _ownedSequence = 0;
                        return false;
                    }

                    if (!EmptyClipboard())
                    {
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to clear the clipboard.");
                    }

                    _ownedSequence = 0;
                    return true;
                }
                finally
                {
                    CloseClipboard();
                }
            }
        }

        private static uint RegisterRequiredFormat(string name)
        {
            uint format = RegisterClipboardFormat(name);
            if (format == 0)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to register a secure clipboard format.");
            }

            return format;
        }

        private static void SetClipboardBytes(uint format, byte[] bytes)
        {
            IntPtr handle = IntPtr.Zero;
            IntPtr pointer = IntPtr.Zero;
            try
            {
                handle = GlobalAlloc(GmemMoveable, (UIntPtr)bytes.Length);
                if (handle == IntPtr.Zero)
                {
                    throw new OutOfMemoryException("Unable to allocate clipboard memory.");
                }

                pointer = GlobalLock(handle);
                if (pointer == IntPtr.Zero)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to lock clipboard memory.");
                }

                Marshal.Copy(bytes, 0, pointer, bytes.Length);
                GlobalUnlock(handle);
                pointer = IntPtr.Zero;

                if (SetClipboardData(format, handle) == IntPtr.Zero)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to place protected data on the clipboard.");
                }

                // Windows owns this memory after SetClipboardData succeeds.
                handle = IntPtr.Zero;
            }
            finally
            {
                if (pointer != IntPtr.Zero)
                {
                    GlobalUnlock(handle);
                }
                if (handle != IntPtr.Zero)
                {
                    GlobalFree(handle);
                }
            }
        }

        private static void OpenClipboardWithRetry(IntPtr ownerWindow)
        {
            for (int attempt = 0; attempt < 8; attempt++)
            {
                if (OpenClipboard(ownerWindow))
                {
                    return;
                }

                Thread.Sleep(20 + (attempt * 15));
            }

            throw new Win32Exception(Marshal.GetLastWin32Error(), "The clipboard is busy. Please try again.");
        }
    }
}
