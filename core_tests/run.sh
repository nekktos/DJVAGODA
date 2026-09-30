#!/usr/bin/env bash
# Собрать и прогнать проверки ядра правил без Unity.
#
#   ./core_tests/run.sh
#
# Компилятор — системный csc .NET Framework 4 (C# 5): ядро намеренно пишется
# в подмножестве C# 5, чтобы проверяться без редактора и без .NET SDK.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CSC="/c/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe"
OUT="${TMPDIR:-/c/Temp/claude}/core_tests.exe"
mkdir -p "$(dirname "$OUT")"
SOURCES=$(find "$ROOT/unity_project/Assets/DjvaGoda/Core" -name "*.cs" | tr '\n' ' ')
"$CSC" -nologo -codepage:65001 -warnaserror- -out:"$(cygpath -w "$OUT")" \
	$(for f in $SOURCES "$ROOT/core_tests/CoreTests.cs"; do printf '%s ' "$(cygpath -w "$f")"; done)
"$OUT"
