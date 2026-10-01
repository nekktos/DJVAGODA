#!/usr/bin/env bash
# Проверки Unity-версии без окна редактора.
#
#   ./unity_tests.sh                 — PlayMode, все
#   ./unity_tests.sh EditMode        — другая платформа
#   ./unity_tests.sh PlayMode Walk   — фильтр по имени
#
# Редактор с этим проектом должен быть ЗАКРЫТ: Unity не открывает проект дважды.
# Ядро правил — EditMode (./unity_tests.sh EditMode). При открытом редакторе —
# через MCP: run_tests (EditMode / PlayMode).
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
UNITY="${UNITY:-/c/Program Files/Unity/Hub/Editor/6000.6.3f1/Editor/Unity.exe}"
PLATFORM="${1:-PlayMode}"
FILTER="${2:-}"
OUT="${TMPDIR:-/c/Temp/claude}"
mkdir -p "$OUT"
RESULTS="$OUT/unity_${PLATFORM}.xml"
LOG="$OUT/unity_${PLATFORM}.log"
ARGS=(-batchmode -projectPath "$(cygpath -w "$ROOT/unity_project")" -runTests -testPlatform "$PLATFORM"
	-testResults "$(cygpath -w "$RESULTS")" -logFile "$(cygpath -w "$LOG")")
[ -n "$FILTER" ] && ARGS+=(-testFilter "$FILTER")
"$UNITY" "${ARGS[@]}"
CODE=$?
grep -oE '<test-case [^>]*result="[^"]*"' "$RESULTS" 2>/dev/null | sed -E 's/.*fullname="([^"]*)".*result="([^"]*)".*/\2 \1/'
grep -E "error CS" "$LOG" | sort -u
[ $CODE -eq 0 ] && echo "[unity] все проверки пройдены" || echo "[unity] ПРОВАЛ (код $CODE), лог: $LOG"
exit $CODE
