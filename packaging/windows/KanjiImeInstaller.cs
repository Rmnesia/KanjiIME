using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;
using Microsoft.Win32;

namespace KanjiImeInstaller
{
    internal static class Program
    {
        private const string ResourceName = "payload.zip";

        [STAThread]
        private static int Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            string logPath = Path.Combine(Path.GetTempPath(), "KanjiIME-Setup.log");
            try
            {
                File.WriteAllText(logPath, "KanjiIME setup started at " + DateTime.Now + Environment.NewLine);
                DialogResult answer = MessageBox.Show(
                    "Install KanjiIME for Windows?\n\nThis will install or update Rime Weasel, copy KanjiIME dictionaries, and deploy JP/ZH/HK modes.",
                    "KanjiIME Setup",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Question,
                    MessageBoxDefaultButton.Button1);

                if (answer != DialogResult.Yes)
                {
                    AppendLog(logPath, "User cancelled.");
                    return 1;
                }

                string tempDir = Path.Combine(Path.GetTempPath(), "KanjiIME-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(tempDir);
                ExtractPayload(tempDir);

                string payloadWeaselDir = Path.Combine(tempDir, "weasel");
                string payloadRimeDir = Path.Combine(tempDir, "rime");
                string installRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Rime");
                string installDir = Path.Combine(installRoot, "weasel-kanjiime");
                string rimeDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                    "Rime");

                if (!File.Exists(Path.Combine(payloadWeaselDir, "WeaselSetup.exe")) ||
                    !File.Exists(Path.Combine(payloadWeaselDir, "WeaselDeployer.exe")))
                {
                    throw new FileNotFoundException("Bundled Weasel program files were not found.");
                }

                AppendLog(logPath, "Installing bundled Weasel files to " + installDir);
                CopyDirectory(payloadWeaselDir, installDir, logPath);

                string deployer = Path.Combine(installDir, "WeaselDeployer.exe");
                string setup = Path.Combine(installDir, "WeaselSetup.exe");
                string server = Path.Combine(installDir, "WeaselServer.exe");

                Directory.CreateDirectory(rimeDir);
                foreach (string file in Directory.GetFiles(payloadRimeDir, "*", SearchOption.AllDirectories))
                {
                    string relative = file.Substring(payloadRimeDir.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                    string destination = Path.Combine(rimeDir, relative);
                    Directory.CreateDirectory(Path.GetDirectoryName(destination));
                    File.Copy(file, destination, true);
                    AppendLog(logPath, "Copied " + destination);
                }

                if (!File.Exists(deployer))
                {
                    throw new FileNotFoundException("WeaselDeployer.exe was not found after installation.");
                }

                if (!File.Exists(setup))
                {
                    throw new FileNotFoundException("WeaselSetup.exe was not found after installation.");
                }

                AppendLog(logPath, "Registering Weasel input profile with " + setup);
                Run(setup, "/s", logPath);
                RenameWeaselProfiles(logPath);

                AppendLog(logPath, "Deploying with " + deployer);
                Run(deployer, "/deploy", logPath);

                if (File.Exists(server))
                {
                    AppendLog(logPath, "Starting Weasel server with " + server);
                    StartNoWait(server, "", logPath);
                }

                MessageBox.Show(
                    "KanjiIME is installed.\n\nDefault mode: KanjiIME JP\nCtrl+1: Japanese\nCtrl+2: Simplified Chinese\nCtrl+3: Traditional Chinese / Hong Kong\n\nPress Win+Space and choose KanjiIME if Windows does not switch automatically.",
                    "KanjiIME Setup",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);

                return 0;
            }
            catch (Exception ex)
            {
                AppendLog(logPath, ex.ToString());
                MessageBox.Show(
                    "KanjiIME setup failed.\n\n" + ex.Message + "\n\nLog: " + logPath,
                    "KanjiIME Setup",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }
        }

        private static void ExtractPayload(string tempDir)
        {
            Assembly assembly = Assembly.GetExecutingAssembly();
            using (Stream stream = assembly.GetManifestResourceStream(ResourceName))
            {
                if (stream == null)
                {
                    throw new InvalidOperationException("Embedded installer payload was not found.");
                }

                using (ZipArchive archive = new ZipArchive(stream, ZipArchiveMode.Read))
                {
                    archive.ExtractToDirectory(tempDir);
                }
            }
        }

        private static void CopyDirectory(string sourceDir, string destinationDir, string logPath)
        {
            foreach (string directory in Directory.GetDirectories(sourceDir, "*", SearchOption.AllDirectories))
            {
                string relative = directory.Substring(sourceDir.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                Directory.CreateDirectory(Path.Combine(destinationDir, relative));
            }

            Directory.CreateDirectory(destinationDir);
            foreach (string file in Directory.GetFiles(sourceDir, "*", SearchOption.AllDirectories))
            {
                string relative = file.Substring(sourceDir.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                string destination = Path.Combine(destinationDir, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(destination));
                File.Copy(file, destination, true);
            }

            AppendLog(logPath, "Copied Weasel program files.");
        }

        private static void Run(string fileName, string arguments, string logPath)
        {
            using (Process process = new Process())
            {
                process.StartInfo.FileName = fileName;
                process.StartInfo.Arguments = arguments;
                process.StartInfo.UseShellExecute = false;
                process.StartInfo.CreateNoWindow = true;
                process.Start();
                process.WaitForExit();

                AppendLog(logPath, fileName + " " + arguments + " exited with " + process.ExitCode);
                if (process.ExitCode != 0)
                {
                    throw new InvalidOperationException(Path.GetFileName(fileName) + " failed with exit code " + process.ExitCode + ".");
                }
            }
        }

        private static void StartNoWait(string fileName, string arguments, string logPath)
        {
            using (Process process = new Process())
            {
                process.StartInfo.FileName = fileName;
                process.StartInfo.Arguments = arguments;
                process.StartInfo.UseShellExecute = false;
                process.StartInfo.CreateNoWindow = true;
                process.Start();
                AppendLog(logPath, "Started " + fileName + " " + arguments);
            }
        }

        private static void RenameWeaselProfiles(string logPath)
        {
            const string tipPath = @"SOFTWARE\Microsoft\CTF\TIP\{A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A}\LanguageProfile";
            using (RegistryKey languageProfile = Registry.LocalMachine.OpenSubKey(tipPath, true))
            {
                if (languageProfile == null)
                {
                    AppendLog(logPath, "Weasel language profile registry key was not found.");
                    return;
                }

                foreach (string language in languageProfile.GetSubKeyNames())
                {
                    using (RegistryKey languageKey = languageProfile.OpenSubKey(language, true))
                    {
                        if (languageKey == null)
                        {
                            continue;
                        }

                        foreach (string profile in languageKey.GetSubKeyNames())
                        {
                            using (RegistryKey profileKey = languageKey.OpenSubKey(profile, true))
                            {
                                if (profileKey == null)
                                {
                                    continue;
                                }

                                object icon = profileKey.GetValue("IconFile");
                                if (icon != null && icon.ToString().IndexOf("weasel", StringComparison.OrdinalIgnoreCase) >= 0)
                                {
                                    profileKey.SetValue("Description", "KanjiIME", RegistryValueKind.String);
                                    AppendLog(logPath, "Renamed Weasel profile " + language + "\\" + profile + " to KanjiIME.");
                                }
                            }
                        }
                    }
                }
            }
        }

        private static void AppendLog(string logPath, string message)
        {
            File.AppendAllText(logPath, "[" + DateTime.Now + "] " + message + Environment.NewLine);
        }
    }
}
