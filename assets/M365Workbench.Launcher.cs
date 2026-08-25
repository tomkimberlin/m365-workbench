using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

namespace M365Workbench
{
    internal static class Launcher
    {
        [STAThread]
        private static int Main(string[] args)
        {
            try
            {
                if (args == null || args.Length != 1)
                {
                    throw new InvalidOperationException("The M365 Workbench script path was not supplied.");
                }

                string scriptPath = Path.GetFullPath(args[0]);
                if (!File.Exists(scriptPath))
                {
                    throw new FileNotFoundException("M365 Workbench could not be found.", scriptPath);
                }

                string powerShellPath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Microsoft",
                    "WindowsApps",
                    "pwsh.exe");
                if (!File.Exists(powerShellPath))
                {
                    throw new FileNotFoundException("PowerShell 7 was not found in the Windows app execution aliases.", powerShellPath);
                }

                var startInfo = new ProcessStartInfo
                {
                    FileName = powerShellPath,
                    Arguments = "-NoLogo -NoProfile -STA -WindowStyle Hidden -File " + Quote(scriptPath),
                    WorkingDirectory = Path.GetDirectoryName(scriptPath),
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };

                Process.Start(startInfo);
                return 0;
            }
            catch (Exception exception)
            {
                MessageBox.Show(
                    exception.Message,
                    "M365 Workbench",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }
        }

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }
    }
}
