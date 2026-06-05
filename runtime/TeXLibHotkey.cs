// TeXLibHotkey.cs
// ===========================================================================
// A tiny resident process that gives File Explorer a "build the selected .tex"
// hotkey (Ctrl+B), without an editor open. It installs a low-level keyboard
// hook (WH_KEYBOARD_LL) and acts ONLY when a File Explorer window is in the
// foreground -- so Ctrl+B keeps meaning "bold" in every other application.
//
// On a matching Ctrl+B it swallows the keystroke and launches
// texlib-build-selected.ps1, passing the foreground window handle so the
// PowerShell side can read the right window's selection even after focus moves.
//
// Compiled at install time with the in-box .NET Framework C# compiler:
//   csc.exe /target:winexe /out:TeXLibHotkey.exe TeXLibHotkey.cs
// (winexe => no console window). Single-instance via a named mutex.
//
// Scope is intentionally narrow: it does not register a global hotkey (which
// would swallow Ctrl+B everywhere); the WH_KEYBOARD_LL hook passes every key
// through untouched unless Explorer is focused and the combo is exactly Ctrl+B.
// ===========================================================================

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class TeXLibHotkey
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int VK_B = 0x42;
    private const int VK_CONTROL = 0x11;
    private const int VK_MENU = 0x12;     // Alt
    private const int VK_LWIN = 0x5B;
    private const int VK_RWIN = 0x5C;

    // File Explorer window classes. CabinetWClass is the modern Explorer
    // file window; ExploreWClass is the legacy single-folder window.
    private static readonly string[] ExplorerClasses = { "CabinetWClass", "ExploreWClass" };

    private static LowLevelKeyboardProc _proc = HookCallback;
    private static IntPtr _hookId = IntPtr.Zero;

    [STAThread]
    private static int Main()
    {
        bool createdNew;
        using (var mutex = new Mutex(true, "TeXLibHotkey_SingleInstance", out createdNew))
        {
            if (!createdNew)
            {
                return 0; // already running
            }

            _hookId = SetHook(_proc);
            if (_hookId == IntPtr.Zero)
            {
                return 1;
            }

            // Standard message loop so the low-level hook is serviced.
            MSG msg;
            while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0)
            {
                TranslateMessage(ref msg);
                DispatchMessage(ref msg);
            }

            UnhookWindowsHookEx(_hookId);
            return 0;
        }
    }

    private static IntPtr SetHook(LowLevelKeyboardProc proc)
    {
        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule)
        {
            return SetWindowsHookEx(WH_KEYBOARD_LL, proc,
                GetModuleHandle(curModule.ModuleName), 0);
        }
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN))
        {
            int vk = Marshal.ReadInt32(lParam); // KBDLLHOOKSTRUCT.vkCode is first field
            if (vk == VK_B && IsControlOnly() && IsExplorerForeground())
            {
                IntPtr hwnd = GetForegroundWindow();
                LaunchBuild(hwnd);
                return (IntPtr)1; // swallow: don't let Explorer/anything see Ctrl+B
            }
        }
        return CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    // Ctrl held, but not Alt and not Win (so Ctrl+Alt+B / Win combos pass through).
    private static bool IsControlOnly()
    {
        bool ctrl = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
        bool alt = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
        bool win = ((GetAsyncKeyState(VK_LWIN) & 0x8000) != 0) ||
                   ((GetAsyncKeyState(VK_RWIN) & 0x8000) != 0);
        return ctrl && !alt && !win;
    }

    private static bool IsExplorerForeground()
    {
        IntPtr hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return false;
        var sb = new StringBuilder(256);
        GetClassName(hwnd, sb, sb.Capacity);
        string cls = sb.ToString();
        foreach (string c in ExplorerClasses)
        {
            if (string.Equals(cls, c, StringComparison.OrdinalIgnoreCase)) return true;
        }
        return false;
    }

    private static void LaunchBuild(IntPtr explorerHwnd)
    {
        try
        {
            string exeDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            string script = Path.Combine(exeDir, "texlib-build-selected.ps1");
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \""
                            + script + "\" -ExplorerHwnd " + explorerHwnd.ToInt64(),
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            Process.Start(psi);
        }
        catch
        {
            // Best-effort: a failed launch should never crash the resident hook.
        }
    }

    // --- P/Invoke ----------------------------------------------------------

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int x; public int y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG lpMsg);
}
