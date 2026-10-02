// Сборки для тестеров (шаг 12 плана): Windows и macOS одним заходом, в
// архивы вместе с инструкцией и анкетой (перенос build_playtest.ps1).
//
// «ДжваГода → Собрать для тестеров» или из командной строки:
//   Unity.exe -batchmode -quit -projectPath unity_project
//             -executeMethod DjvaGoda.EditorTools.PlaytestBuild.BuildMain [-release]
//
// Сборка НЕ подписана. macOS: архив собран с правами на запуск (иначе
// приложение «повреждено» и не стартует вовсе), рядом с .app лежит
// DzhvaGoda.command — снимает карантин, ставит локальную (ad-hoc) подпись,
// без которой маки на процессорах Apple не запускают программу, и
// запускает игру. Права в архиве ставятся явно: zip, собранный на Windows,
// иначе их теряет.
using System;
using System.IO;
using System.IO.Compression;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace DjvaGoda.EditorTools
{
    public static class PlaytestBuild
    {
        public const string Product = "DzhvaGoda";
        const string Scene = "Assets/DjvaGoda/Scenes/Main.unity";

        static string Root { get { return Path.GetFullPath(Path.Combine(Application.dataPath, "..", "..")); } }
        static string BuildDir { get { return Path.Combine(Root, "build"); } }

        [MenuItem("ДжваГода/Собрать для тестеров")]
        public static void BuildMenu() { Build(false); }

        /// Для командной строки: -executeMethod DjvaGoda.EditorTools.PlaytestBuild.BuildMain [-release]
        public static void BuildMain()
        {
            bool release = Array.IndexOf(Environment.GetCommandLineArgs(), "-release") >= 0;
            if (!Build(release)) EditorApplication.Exit(1);
        }

        public static bool Build(bool release)
        {
            string version = PlayerSettings.bundleVersion;
            Debug.Log("[тестерам] версия " + version + (release ? ", релиз" : ", отладка"));
            var options = release ? BuildOptions.None : BuildOptions.Development;
            bool ok = true;

            string winDir = Path.Combine(BuildDir, "unity_windows");
            ok &= Player(BuildTarget.StandaloneWindows64, Path.Combine(winDir, Product + ".exe"), options);
            string macDir = Path.Combine(BuildDir, "unity_macos");
            ok &= Player(BuildTarget.StandaloneOSX, Path.Combine(macDir, Product + ".app"), options);
            if (!ok) return false;

            File.WriteAllText(Path.Combine(macDir, Product + ".command"), MacLauncher().Replace("\r\n", "\n"));
            string tag = Product + "-unity-" + version;
            Pack(winDir, Path.Combine(BuildDir, tag + "-windows.zip"), false);
            Pack(macDir, Path.Combine(BuildDir, tag + "-macos.zip"), true);
            Debug.Log("[тестерам] готово: build/" + tag + "-windows.zip, build/" + tag + "-macos.zip");
            return true;
        }

        static bool Player(BuildTarget target, string path, BuildOptions options)
        {
            string dir = Path.GetDirectoryName(path);
            if (Directory.Exists(dir)) Directory.Delete(dir, true);
            Directory.CreateDirectory(dir);
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { Scene },
                locationPathName = path,
                target = target,
                options = options,
            });
            bool ok = report.summary.result == BuildResult.Succeeded;
            Debug.Log("[тестерам] " + target + ": " + report.summary.result + ", " + report.summary.totalSize / (1024 * 1024) + " МБ, ошибок "
                + report.summary.totalErrors);
            return ok;
        }

        /// Запуск на macOS в обход проверок: карантин прочь, локальная подпись, старт.
        static string MacLauncher()
        {
            return "#!/bin/bash\n"
                + "# ДжваГода: запуск неподписанной сборки на macOS.\n"
                + "cd \"$(dirname \"$0\")\"\n"
                + "APP=\"" + Product + ".app\"\n"
                + "if [ ! -d \"$APP\" ]; then echo \"Рядом нет $APP — держите их в одной папке.\"; read -n 1; exit 1; fi\n"
                + "xattr -dr com.apple.quarantine \"$APP\" 2>/dev/null\n"
                + "chmod +x \"$APP/Contents/MacOS/\"* 2>/dev/null\n"
                + "codesign --force --deep --sign - \"$APP\" 2>/dev/null\n"
                + "open \"$APP\"\n";
        }

        /// Архив: папка сборки, инструкция и анкета. Для macOS — права unix:
        /// исполняемым (Contents/MacOS, .command, .dylib) — 755, прочим — 644.
        static void Pack(string dir, string zip, bool mac)
        {
            if (File.Exists(zip)) File.Delete(zip);
            using (var archive = ZipFile.Open(zip, ZipArchiveMode.Create))
            {
                foreach (var file in Directory.GetFiles(dir, "*", SearchOption.AllDirectories))
                {
                    string rel = file.Substring(dir.Length + 1).Replace('\\', '/');
                    // Отладочные символы и папки «не отправлять» тестерам не нужны.
                    if (rel.Contains("_BackUpThisFolder_") || rel.Contains("_DoNotShip")) continue;
                    var entry = archive.CreateEntryFromFile(file, rel, System.IO.Compression.CompressionLevel.Optimal);
                    if (mac)
                    {
                        bool exec = rel.Contains("/Contents/MacOS/") || rel.EndsWith(".command") || rel.EndsWith(".dylib");
                        int mode = exec ? Convert.ToInt32("100755", 8) : Convert.ToInt32("100644", 8);
                        entry.ExternalAttributes = mode << 16;
                    }
                }
                foreach (var doc in new[] { "PLAYTEST_UNITY.md", "PLAYTEST_FORM.md" })
                {
                    string path = Path.Combine(Root, doc);
                    if (File.Exists(path)) archive.CreateEntryFromFile(path, doc);
                }
            }
            Debug.Log("[тестерам] архив " + zip + ", " + new FileInfo(zip).Length / (1024 * 1024) + " МБ");
        }
    }
}
