#!/bin/bash
# Проверка компиляции Unity-сборок без редактора: тем же Roslyn, что везёт
# Unity, против уже собранных Library/ScriptAssemblies. Нужна, когда
# редактор недоступен (MCP-мост отвалился): ловит ошибки C# за секунды.
# Кодогенерацию Netcode (ILPP) не выполняет — только синтаксис и типы.
#   tools/unity_compile_check.sh
set -e
cd "$(dirname "$0")/../unity_project"
E="C:/Program Files/Unity/Hub/Editor/6000.3.25f1/Editor/Data"
OUT="${TMP:-/tmp}/djvagoda_compile_check"
mkdir -p "$OUT"
rm -f "$OUT"/*.dll
CSC() { "$E/NetCoreRuntime/dotnet.exe" "$E/DotNetSdkRoslyn/csc.dll" "$@"; }
base() {
  echo "-target:library -nologo -nowarn:CS0618,CS0649,CS0414,CS0169 -langversion:9"
  echo "-r:\"$E/NetStandard/ref/2.1.0/netstandard.dll\""
  echo "-r:\"$E/NetStandard/compat/2.1.0/shims/netfx/mscorlib.dll\""
  for f in "$E"/Managed/UnityEngine/*.dll; do echo "-r:\"$f\""; done
  for f in DjvaGoda.Core Unity.InputSystem Unity.Netcode.Runtime Unity.Networking.Transport Unity.AI.Navigation Unity.Collections UnityEngine.TestRunner Unity.RenderPipelines.Universal.Runtime Unity.RenderPipelines.Core.Runtime; do
    echo "-r:\"$(pwd -W)/Library/ScriptAssemblies/$f.dll\""
  done
}
src() { find "$1" -name "*.cs" | while read f; do echo "\"$(pwd -W)/$f\""; done; }

{ base; echo "-out:$OUT/Game.dll"; src Assets/DjvaGoda/Game; } > "$OUT/game.rsp"
CSC "@$OUT/game.rsp" | grep -v "warning" || true
[ -f "$OUT/Game.dll" ] || { echo "Game: ошибки компиляции"; exit 1; }

NUNIT=$(find Library/PackageCache -path "*unity-custom/nunit.framework.dll" | head -1)
{ base; echo "-out:$OUT/PlayTests.dll"; echo "-r:\"$OUT/Game.dll\""; echo "-r:\"$(pwd -W)/$NUNIT\""; src Assets/DjvaGoda/Tests/PlayMode; } > "$OUT/tests.rsp"
CSC "@$OUT/tests.rsp" | grep -v "warning" || true
echo "проверка компиляции: готово"
