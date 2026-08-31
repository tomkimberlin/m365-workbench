using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace M365Workbench.Security
{
    public enum UserConsentVerificationResult
    {
        Verified = 0,
        DeviceNotPresent = 1,
        NotConfiguredForUser = 2,
        DisabledByPolicy = 3,
        DeviceBusy = 4,
        RetriesExhausted = 5,
        Canceled = 6
    }

    public enum WindowsVerificationState
    {
        Verified,
        DeviceNotPresent,
        NotConfiguredForUser,
        DisabledByPolicy,
        DeviceBusy,
        RetriesExhausted,
        Canceled,
        TimedOut,
        PlatformUnavailable,
        Error
    }

    public sealed class WindowsVerificationOutcome
    {
        internal WindowsVerificationOutcome(WindowsVerificationState state, UserConsentVerificationResult? nativeResult, int hResult, string diagnosticMessage)
        {
            State = state;
            NativeResult = nativeResult;
            HResult = hResult;
            DiagnosticMessage = diagnosticMessage ?? string.Empty;
        }

        public WindowsVerificationState State { get; private set; }
        public UserConsentVerificationResult? NativeResult { get; private set; }
        public int HResult { get; private set; }
        public string DiagnosticMessage { get; private set; }
        public bool IsVerified { get { return State == WindowsVerificationState.Verified; } }
    }

    internal enum AsyncStatus
    {
        Started = 0,
        Completed = 1,
        Canceled = 2,
        Error = 3
    }

    internal enum TrustLevel
    {
        BaseTrust = 0,
        PartialTrust = 1,
        FullTrust = 2
    }

    // Modern .NET no longer projects IInspectable interfaces. Define them as
    // IUnknown and include the three IInspectable vtable slots explicitly.
    [ComImport]
    [Guid("39E050C3-4E74-441A-8DC0-B81104DF949C")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IUserConsentVerifierInterop
    {
        [PreserveSig] int GetIids(out uint count, out IntPtr iids);
        [PreserveSig] int GetRuntimeClassName(out IntPtr className);
        [PreserveSig] int GetTrustLevel(out TrustLevel trustLevel);
        [PreserveSig] int RequestVerificationForWindowAsync(IntPtr hwnd, IntPtr message, [In] ref Guid riid, out IntPtr operation);
    }

    [ComImport]
    [Guid("FD596FFD-2318-558F-9DBE-D21DF43764A5")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAsyncOperationConsentResult
    {
        [PreserveSig] int GetIids(out uint count, out IntPtr iids);
        [PreserveSig] int GetRuntimeClassName(out IntPtr className);
        [PreserveSig] int GetTrustLevel(out TrustLevel trustLevel);
        [PreserveSig] int put_Completed(IntPtr handler);
        [PreserveSig] int get_Completed(out IntPtr handler);
        [PreserveSig] int GetResults(out UserConsentVerificationResult result);
    }

    [ComImport]
    [Guid("00000036-0000-0000-C000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAsyncInfo
    {
        [PreserveSig] int GetIids(out uint count, out IntPtr iids);
        [PreserveSig] int GetRuntimeClassName(out IntPtr className);
        [PreserveSig] int GetTrustLevel(out TrustLevel trustLevel);
        [PreserveSig] int get_Id(out uint id);
        [PreserveSig] int get_Status(out AsyncStatus status);
        [PreserveSig] int get_ErrorCode(out int errorCode);
        [PreserveSig] int Cancel();
        [PreserveSig] int Close();
    }

    public static class WindowsHelloVerifier
    {
        public const int DefaultTimeoutMilliseconds = 120000;

        private const int RoInitMultithreaded = 1;
        private const int RpcEChangedMode = unchecked((int)0x80010106);
        private const int RegDbEClassNotRegistered = unchecked((int)0x80040154);
        private const int ENoInterface = unchecked((int)0x80004002);
        private const int ENotImplemented = unchecked((int)0x80004001);
        private const int HResultNotSupported = unchecked((int)0x80070032);
        private const string RuntimeClass = "Windows.Security.Credentials.UI.UserConsentVerifier";

        private static readonly Guid InteropIid = new Guid("39E050C3-4E74-441A-8DC0-B81104DF949C");
        private static readonly Guid OperationIid = new Guid("FD596FFD-2318-558F-9DBE-D21DF43764A5");

        [DllImport("combase.dll", ExactSpelling = true)]
        private static extern int RoInitialize(int type);

        [DllImport("combase.dll", ExactSpelling = true)]
        private static extern void RoUninitialize();

        [DllImport("combase.dll", ExactSpelling = true)]
        private static extern int RoGetActivationFactory(IntPtr classId, [In] ref Guid iid, out IntPtr factory);

        [DllImport("combase.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
        private static extern int WindowsCreateString(string source, uint length, out IntPtr hstring);

        [DllImport("combase.dll", ExactSpelling = true)]
        private static extern int WindowsDeleteString(IntPtr hstring);

        [DllImport("user32.dll", ExactSpelling = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindow(IntPtr hwnd);

        public static Task<WindowsVerificationOutcome> VerifyAsync(IntPtr hwnd, string message)
        {
            return VerifyAsync(hwnd, message, DefaultTimeoutMilliseconds, CancellationToken.None);
        }

        public static Task<WindowsVerificationOutcome> VerifyAsync(IntPtr hwnd, string message, int timeoutMilliseconds)
        {
            return VerifyAsync(hwnd, message, timeoutMilliseconds, CancellationToken.None);
        }

        public static Task<WindowsVerificationOutcome> VerifyAsync(IntPtr hwnd, string message, int timeoutMilliseconds, CancellationToken cancellationToken)
        {
            if (hwnd == IntPtr.Zero || !IsWindow(hwnd))
            {
                throw new ArgumentException("A valid owner window handle is required.", "hwnd");
            }
            if (string.IsNullOrWhiteSpace(message))
            {
                throw new ArgumentException("A user-facing verification message is required.", "message");
            }
            if (timeoutMilliseconds != Timeout.Infinite && timeoutMilliseconds <= 0)
            {
                throw new ArgumentOutOfRangeException("timeoutMilliseconds");
            }

            // Do not pass the token to Task.Run. Callers always receive a structured
            // fail-closed outcome instead of a faulted or canceled Task.
            return Task.Run(() => VerifyCore(hwnd, message, timeoutMilliseconds, cancellationToken));
        }

        private static WindowsVerificationOutcome VerifyCore(IntPtr hwnd, string message, int timeoutMilliseconds, CancellationToken cancellationToken)
        {
            if (cancellationToken.IsCancellationRequested)
            {
                return NewOutcome(WindowsVerificationState.Canceled, null, 0, "Canceled before verification started.");
            }

            bool uninitializeRuntime = false;
            IntPtr className = IntPtr.Zero;
            IntPtr messageString = IntPtr.Zero;
            IntPtr factoryPointer = IntPtr.Zero;
            IntPtr operationPointer = IntPtr.Zero;
            object factory = null;
            object operationObject = null;
            IAsyncInfo asyncInfo = null;

            try
            {
                int hResult = RoInitialize(RoInitMultithreaded);
                if (hResult >= 0)
                {
                    uninitializeRuntime = true;
                }
                else if (hResult != RpcEChangedMode)
                {
                    Check(hResult);
                }

                Check(WindowsCreateString(RuntimeClass, (uint)RuntimeClass.Length, out className));
                Guid interopIid = InteropIid;
                Check(RoGetActivationFactory(className, ref interopIid, out factoryPointer));
                factory = Marshal.GetObjectForIUnknown(factoryPointer);
                Marshal.Release(factoryPointer);
                factoryPointer = IntPtr.Zero;

                Check(WindowsCreateString(message, (uint)message.Length, out messageString));
                Guid operationIid = OperationIid;
                Check(((IUserConsentVerifierInterop)factory).RequestVerificationForWindowAsync(hwnd, messageString, ref operationIid, out operationPointer));
                operationObject = Marshal.GetObjectForIUnknown(operationPointer);
                Marshal.Release(operationPointer);
                operationPointer = IntPtr.Zero;

                asyncInfo = (IAsyncInfo)operationObject;
                IAsyncOperationConsentResult operation = (IAsyncOperationConsentResult)operationObject;
                Stopwatch stopwatch = Stopwatch.StartNew();

                while (true)
                {
                    if (cancellationToken.IsCancellationRequested)
                    {
                        CancelAndDrain(asyncInfo);
                        return NewOutcome(WindowsVerificationState.Canceled, null, 0, "Canceled by the application.");
                    }
                    if (timeoutMilliseconds != Timeout.Infinite && stopwatch.ElapsedMilliseconds >= timeoutMilliseconds)
                    {
                        CancelAndDrain(asyncInfo);
                        return NewOutcome(WindowsVerificationState.TimedOut, null, 0, "Windows verification timed out.");
                    }

                    AsyncStatus status;
                    Check(asyncInfo.get_Status(out status));
                    switch (status)
                    {
                        case AsyncStatus.Started:
                            Thread.Sleep(40);
                            continue;
                        case AsyncStatus.Completed:
                            UserConsentVerificationResult nativeResult;
                            Check(operation.GetResults(out nativeResult));
                            return FromNative(nativeResult);
                        case AsyncStatus.Canceled:
                            return NewOutcome(WindowsVerificationState.Canceled, UserConsentVerificationResult.Canceled, 0, "Windows canceled verification.");
                        case AsyncStatus.Error:
                            int operationError;
                            Check(asyncInfo.get_ErrorCode(out operationError));
                            return FromError(operationError, "The Windows verification operation failed.");
                        default:
                            return NewOutcome(WindowsVerificationState.Error, null, 0, "Unknown Windows verification state.");
                    }
                }
            }
            catch (COMException exception)
            {
                return FromError(exception.HResult, exception.Message);
            }
            catch (DllNotFoundException exception)
            {
                return NewOutcome(WindowsVerificationState.PlatformUnavailable, null, exception.HResult, exception.Message);
            }
            catch (EntryPointNotFoundException exception)
            {
                return NewOutcome(WindowsVerificationState.PlatformUnavailable, null, exception.HResult, exception.Message);
            }
            catch (PlatformNotSupportedException exception)
            {
                return NewOutcome(WindowsVerificationState.PlatformUnavailable, null, exception.HResult, exception.Message);
            }
            catch (Exception exception)
            {
                return NewOutcome(WindowsVerificationState.Error, null, exception.HResult, exception.Message);
            }
            finally
            {
                if (asyncInfo != null)
                {
                    try { asyncInfo.Close(); } catch { }
                }
                if (operationObject != null && Marshal.IsComObject(operationObject))
                {
                    try { Marshal.ReleaseComObject(operationObject); } catch { }
                }
                if (factory != null && Marshal.IsComObject(factory))
                {
                    try { Marshal.ReleaseComObject(factory); } catch { }
                }
                if (operationPointer != IntPtr.Zero)
                {
                    Marshal.Release(operationPointer);
                }
                if (factoryPointer != IntPtr.Zero)
                {
                    Marshal.Release(factoryPointer);
                }
                if (messageString != IntPtr.Zero)
                {
                    WindowsDeleteString(messageString);
                }
                if (className != IntPtr.Zero)
                {
                    WindowsDeleteString(className);
                }
                if (uninitializeRuntime)
                {
                    RoUninitialize();
                }
            }
        }

        private static void CancelAndDrain(IAsyncInfo asyncInfo)
        {
            try { asyncInfo.Cancel(); } catch { }
            for (int index = 0; index < 25; index++)
            {
                try
                {
                    AsyncStatus status;
                    if (asyncInfo.get_Status(out status) < 0 || status != AsyncStatus.Started)
                    {
                        return;
                    }
                }
                catch
                {
                    return;
                }
                Thread.Sleep(40);
            }
        }

        private static WindowsVerificationOutcome FromNative(UserConsentVerificationResult result)
        {
            switch (result)
            {
                case UserConsentVerificationResult.Verified:
                    return NewOutcome(WindowsVerificationState.Verified, result, 0, string.Empty);
                case UserConsentVerificationResult.DeviceNotPresent:
                    return NewOutcome(WindowsVerificationState.DeviceNotPresent, result, 0, string.Empty);
                case UserConsentVerificationResult.NotConfiguredForUser:
                    return NewOutcome(WindowsVerificationState.NotConfiguredForUser, result, 0, string.Empty);
                case UserConsentVerificationResult.DisabledByPolicy:
                    return NewOutcome(WindowsVerificationState.DisabledByPolicy, result, 0, string.Empty);
                case UserConsentVerificationResult.DeviceBusy:
                    return NewOutcome(WindowsVerificationState.DeviceBusy, result, 0, string.Empty);
                case UserConsentVerificationResult.RetriesExhausted:
                    return NewOutcome(WindowsVerificationState.RetriesExhausted, result, 0, string.Empty);
                case UserConsentVerificationResult.Canceled:
                    return NewOutcome(WindowsVerificationState.Canceled, result, 0, string.Empty);
                default:
                    return NewOutcome(WindowsVerificationState.Error, result, 0, "Unknown Windows verification result.");
            }
        }

        private static WindowsVerificationOutcome FromError(int hResult, string message)
        {
            bool unavailable = hResult == RegDbEClassNotRegistered ||
                hResult == ENoInterface ||
                hResult == ENotImplemented ||
                hResult == HResultNotSupported;
            return NewOutcome(unavailable ? WindowsVerificationState.PlatformUnavailable : WindowsVerificationState.Error, null, hResult, message);
        }

        private static WindowsVerificationOutcome NewOutcome(WindowsVerificationState state, UserConsentVerificationResult? nativeResult, int hResult, string message)
        {
            return new WindowsVerificationOutcome(state, nativeResult, hResult, message);
        }

        private static void Check(int hResult)
        {
            if (hResult < 0)
            {
                Marshal.ThrowExceptionForHR(hResult);
            }
        }
    }
}
