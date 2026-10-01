// Мост MCP for Unity для этого проекта: путь к uvx (его нет в PATH), автозапуск
// сервера при открытии редактора, телеметрия выключена. Claude Code ходит в
// редактор через этот мост (решение автора: «с Unity работать через MCP»);
// со стороны Claude Code сервер описан в .mcp.json в корне репозитория.
using System;
using System.IO;
using UnityEditor;

namespace DjvaGoda.EditorTools
{
    [InitializeOnLoad]
    static class McpSetup
    {
        static McpSetup()
        {
            string uvx = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "Python", "Python314", "Scripts", "uvx.exe");
            if (File.Exists(uvx) && string.IsNullOrEmpty(EditorPrefs.GetString("MCPForUnity.UvxPath", "")))
                EditorPrefs.SetString("MCPForUnity.UvxPath", uvx);
            EditorPrefs.SetBool("MCPForUnity.UseHttpTransport", true);
            EditorPrefs.SetBool("MCPForUnity.AutoStartOnLoad", true);
            EditorPrefs.SetBool("MCPForUnity.TelemetryDisabled", true);
        }
    }
}
