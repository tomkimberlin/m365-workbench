using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace M365Workbench
{
    public static class WindowsShellIdentity
    {
        private const ushort VtLpWStr = 31;
        private const int SharingViolationHResult = unchecked((int)0x80070020);
        private const uint ShcneUpdateItem = 0x00002000;
        private const uint ShcnfPathW = 0x0005;
        private const uint ShcnfFlush = 0x1000;

        private static readonly PropertyKey AppUserModelIdKey = new PropertyKey(
            new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
            5);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(
            [MarshalAs(UnmanagedType.LPWStr)] string appId);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int SHGetPropertyStoreFromParsingName(
            [MarshalAs(UnmanagedType.LPWStr)] string path,
            IntPtr bindContext,
            GetPropertyStoreFlags flags,
            ref Guid interfaceId,
            [MarshalAs(UnmanagedType.Interface)] out IPropertyStore propertyStore);

        [DllImport("shell32.dll", PreserveSig = true)]
        private static extern int SHGetPropertyStoreForWindow(
            IntPtr windowHandle,
            ref Guid interfaceId,
            [MarshalAs(UnmanagedType.Interface)] out IPropertyStore propertyStore);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern void SHChangeNotify(
            uint eventId,
            uint flags,
            IntPtr item1,
            IntPtr item2);

        public static void SetCurrentProcessAppId(string appId)
        {
            ValidateAppId(appId);
            ThrowIfFailed(SetCurrentProcessExplicitAppUserModelID(appId));
        }

        public static void SetShortcutAppId(string shortcutPath, string appId)
        {
            ValidateAppId(appId);
            string resolvedPath = Path.GetFullPath(shortcutPath);
            if (!File.Exists(resolvedPath))
            {
                throw new FileNotFoundException("The Windows shortcut was not found.", resolvedPath);
            }

            IPropertyStore propertyStore = OpenPropertyStore(resolvedPath, GetPropertyStoreFlags.ReadWrite);
            try
            {
                SetAppIdProperty(propertyStore, appId);
            }
            finally
            {
                ReleaseComObject(propertyStore);
            }
        }

        public static void SetWindowAppId(IntPtr windowHandle, string appId)
        {
            ValidateAppId(appId);
            if (windowHandle == IntPtr.Zero)
            {
                throw new ArgumentException("A valid WPF window handle is required.", "windowHandle");
            }

            Guid interfaceId = typeof(IPropertyStore).GUID;
            IPropertyStore propertyStore;
            ThrowIfFailed(SHGetPropertyStoreForWindow(windowHandle, ref interfaceId, out propertyStore));
            try
            {
                SetAppIdProperty(propertyStore, appId);
            }
            finally
            {
                ReleaseComObject(propertyStore);
            }
        }

        public static string GetShortcutAppId(string shortcutPath)
        {
            string resolvedPath = Path.GetFullPath(shortcutPath);
            if (!File.Exists(resolvedPath))
            {
                throw new FileNotFoundException("The Windows shortcut was not found.", resolvedPath);
            }

            IPropertyStore propertyStore = OpenPropertyStore(resolvedPath, GetPropertyStoreFlags.Default);
            PropVariant value = new PropVariant();
            try
            {
                PropertyKey key = AppUserModelIdKey;
                ThrowIfFailed(propertyStore.GetValue(ref key, out value));
                return value.AsString();
            }
            finally
            {
                value.Clear();
                ReleaseComObject(propertyStore);
            }
        }

        private static IPropertyStore OpenPropertyStore(string path, GetPropertyStoreFlags flags)
        {
            Guid interfaceId = typeof(IPropertyStore).GUID;
            for (int attempt = 0; attempt < 20; attempt++)
            {
                IPropertyStore propertyStore;
                int result = SHGetPropertyStoreFromParsingName(
                    path,
                    IntPtr.Zero,
                    flags,
                    ref interfaceId,
                    out propertyStore);
                if (result >= 0)
                {
                    return propertyStore;
                }

                if (result != SharingViolationHResult || attempt == 19)
                {
                    ThrowIfFailed(result);
                }

                Thread.Sleep(50);
            }

            throw new InvalidOperationException("The Windows shortcut property store could not be opened.");
        }

        public static void NotifyShortcutChanged(string shortcutPath)
        {
            string resolvedPath = Path.GetFullPath(shortcutPath);
            if (!File.Exists(resolvedPath))
            {
                throw new FileNotFoundException("The Windows shortcut was not found.", resolvedPath);
            }

            IntPtr pathPointer = Marshal.StringToCoTaskMemUni(resolvedPath);
            try
            {
                SHChangeNotify(ShcneUpdateItem, ShcnfPathW | ShcnfFlush, pathPointer, IntPtr.Zero);
            }
            finally
            {
                Marshal.FreeCoTaskMem(pathPointer);
            }
        }

        private static void SetAppIdProperty(IPropertyStore propertyStore, string appId)
        {
            PropVariant value = PropVariant.FromString(appId);
            try
            {
                PropertyKey key = AppUserModelIdKey;
                ThrowIfFailed(propertyStore.SetValue(ref key, ref value));
                ThrowIfFailed(propertyStore.Commit());
            }
            finally
            {
                value.Clear();
            }
        }

        private static void ValidateAppId(string appId)
        {
            if (string.IsNullOrWhiteSpace(appId))
            {
                throw new ArgumentException("A Windows AppUserModelID is required.", "appId");
            }

            if (appId.Length > 128)
            {
                throw new ArgumentOutOfRangeException("appId", "A Windows AppUserModelID cannot exceed 128 characters.");
            }
        }

        private static void ThrowIfFailed(int result)
        {
            if (result < 0)
            {
                Marshal.ThrowExceptionForHR(result);
            }
        }

        private static void ReleaseComObject(object value)
        {
            if (value != null && Marshal.IsComObject(value))
            {
                Marshal.FinalReleaseComObject(value);
            }
        }

        [Flags]
        private enum GetPropertyStoreFlags : uint
        {
            Default = 0x00000000,
            ReadWrite = 0x00000002
        }

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        private struct PropertyKey
        {
            public Guid FormatId;
            public uint PropertyId;

            public PropertyKey(Guid formatId, uint propertyId)
            {
                FormatId = formatId;
                PropertyId = propertyId;
            }
        }

        [StructLayout(LayoutKind.Explicit, Size = 24)]
        private struct PropVariant
        {
            [FieldOffset(0)]
            public ushort VariantType;

            [FieldOffset(8)]
            public IntPtr PointerValue;

            public static PropVariant FromString(string value)
            {
                PropVariant variant = new PropVariant();
                variant.VariantType = VtLpWStr;
                variant.PointerValue = Marshal.StringToCoTaskMemUni(value);
                return variant;
            }

            public string AsString()
            {
                if (VariantType == 0 || PointerValue == IntPtr.Zero)
                {
                    return string.Empty;
                }

                if (VariantType != VtLpWStr)
                {
                    throw new InvalidOperationException("The shortcut AppUserModelID is not stored as a Unicode string.");
                }

                return Marshal.PtrToStringUni(PointerValue) ?? string.Empty;
            }

            public void Clear()
            {
                if (VariantType == VtLpWStr && PointerValue != IntPtr.Zero)
                {
                    Marshal.FreeCoTaskMem(PointerValue);
                }

                VariantType = 0;
                PointerValue = IntPtr.Zero;
            }
        }

        [ComImport]
        [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IPropertyStore
        {
            [PreserveSig]
            int GetCount(out uint propertyCount);

            [PreserveSig]
            int GetAt(uint propertyIndex, out PropertyKey key);

            [PreserveSig]
            int GetValue(ref PropertyKey key, out PropVariant value);

            [PreserveSig]
            int SetValue(ref PropertyKey key, ref PropVariant value);

            [PreserveSig]
            int Commit();
        }
    }
}
