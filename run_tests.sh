#!/usr/bin/env bash
# Прогон всего набора автопроверок «ДжваГоды».
#
#   ./run_tests.sh              — весь набор
#   ./run_tests.sh caravan walk — только названные наборы
#
# Наборы гоняются по одному и почти все с --freshworld: автосейв хоста иначе
# протекает из набора в набор, и проверки перестают быть независимыми. Набору
# сохранений сейв нужен живым, поэтому он изолируется отдельным --world.
#
# Каждому пиру выдаётся СВОЙ --profile: все процессы на одной машине делят
# папку user://, значит и файл профиля. С общим профилем игра считает пиров
# одним человеком, и набор сохранений разваливается.
#
# Провал ЛЮБОЙ половины валит набор: половина клиента проверяет репликацию, и
# молчаливо терять её нельзя.
#
# Набор perf требует окна и в общий прогон не входит — его гоняют руками.
set -u

GODOT="${GODOT:-/c/Users/Noper/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
PROJECT="$(cd "$(dirname "$0")" && pwd)/godot_project"
LOGS="${LOGS:-/c/Temp/claude/dzhvagoda-tests}"

# Предел на один набор. Зависший набор — это не «долго идёт», это навсегда:
# процесс Godot переживает и прогонщик, и сам инструмент, который его запустил,
# и остаётся крутиться в фоне, съедая ядро. Однажды их накопилось шесть штук,
# старшему было сутки, и вместе они намотали больше десяти часов процессорного
# времени, пока это не заметили глазами.
#
# Семь минут с запасом: самый долгий набор — выдержка, три минуты варки плюс
# запуск. Не уложился — убиваем и считаем провалом.
SUITE_TIMEOUT="${SUITE_TIMEOUT:-900}"

# имя : флаг : стороны пиров через запятую (первый — хост) : общие доп. ключи
SUITES=(
	"nav:--navtest::"
	"lab:--labtest:0:"
	"steward:--stewardtest:1:"
	"sfx:--sfxtest::"
	"weapon:--weapontest:1:"
	"magic:--magictest:0,1:"
	"walk:--walktest::"
	"forest:--foresttest::"
	"econ:--econtest::"
	"caravan:--caravantest:0:"
	"squad:--squadtest::"
	"console:--consoletest::"
	"combat:--combattest:,0:"
	"wound:--woundtest:,1:"
	"elf:--elftest:1,0:"
	"trade:--tradetest:1,0:"
	"guard:--guardtest:2,0:"
	"death:--deathtest:1,2:"
	"victory:--victorytest:2,0:"
	"dip:--diptest:1,2:"
	"garrison:--garrisontest:0,1:"
	"warband:--warbandtest:0,1:"
	"soak:--soaktest::"
	"netsoak:--netsoaktest:0,1:"
	"hero:--herotest:2,1:"
	"horse:--horsetest:0:"
	"slice:--slicetest:0,1,2:"
	"onboarding:--onboardingtest:0:"
	"playable0:--playabletest:0:"
	"playable1:--playabletest:1:"
	"playable2:--playabletest:2:"
	"save:--savetest:2,1:--world=autotest-save"
	"newgame:--newgametest:0,1:--world=autotest-newgame"
	"reentry:--reentrytest:0:--world=autotest-reentry"
)

mkdir -p "$LOGS"
[ -x "$GODOT" ] || { echo "Не найден Godot: $GODOT (задай через GODOT=...)"; exit 1; }

# Чужой Godot в памяти — это почти наверняка недобитый прогон, и он держит порт
# 24545. Новый прогон в такой обстановке не падает, а ЗАВИСАЕТ: наборы один за
# другим не могут поднять сеть и ждут персонажа, которого не будет. Лучше
# отказаться сразу и сказать, почему.
running="$(ps -W 2>/dev/null | grep -ci 'Godot' || true)"
if [ "${running:-0}" -gt 0 ]; then
	echo "Уже запущено процессов Godot: $running."
	echo "Это либо идущий прогон, либо недобитый предыдущий — он держит порт 24545."
	echo "Закрой их и повтори (или задай FORCE=1, если знаешь, что делаешь)."
	[ "${FORCE:-0}" = "1" ] || exit 1
fi

wanted=("$@")
failed=()
passed=0

run_suite() {
	local name="$1" flag="$2" factions="$3" extra="$4"
	IFS=, read -ra sides <<<"$factions"
	[ ${#sides[@]} -eq 0 ] && sides=("")

	# Набору сохранений нужен работающий сейв, всем остальным — чистый мир.
	local fresh="--freshworld"
	[ -n "$extra" ] && fresh=""

	local pids=() rcs=() peer=0
	printf '%-10s ' "$name"
	for side in "${sides[@]}"; do
		local args=("$flag" "--profile=autotest-$name-$peer")
		[ -n "$side" ] && args+=("--faction=$side")
		[ -n "$extra" ] && args+=("$extra")
		if [ $peer -eq 0 ]; then
			args=(--host "${args[@]}")
		else
			args=(--join=127.0.0.1 "${args[@]}")
		fi
		local log="$LOGS/$name-$peer.log"
		# `--log-file` уводит лог ДВИЖКА в нашу папку.
		#
		# Без него каждый набор писал в `user://logs` — туда же, куда пишет игра
		# у тестера. Godot держит там всего пять файлов и ротирует их, а полный
		# прогон поднимает Godot тридцать три раза: все пять слотов забиваются
		# за первые секунды. Так и пропал лог playtest-6: тестер играл 21.09
		# утром, прогон в 10:39 стёр его подчистую, и к отчёту стало нечего
		# приложить.
		local elog="$LOGS/$name-$peer-engine.log"
		if [ ${#sides[@]} -eq 1 ]; then
			timeout -k 5 "$SUITE_TIMEOUT" "$GODOT" --headless --log-file "$elog" --path "$PROJECT" $fresh -- "${args[@]}" >"$log" 2>&1
			rcs+=($?)
		else
			timeout -k 5 "$SUITE_TIMEOUT" "$GODOT" --headless --log-file "$elog" --path "$PROJECT" $fresh -- "${args[@]}" >"$log" 2>&1 &
			pids+=($!)
			sleep 2
		fi
		peer=$((peer+1))
	done
	for pid in "${pids[@]:-}"; do
		[ -z "$pid" ] && continue
		wait "$pid"; rcs+=($?)
	done

	local bad=0
	for rc in "${rcs[@]}"; do [ "$rc" -ne 0 ] && bad=1; done

	# Ошибка движка в логе — тоже провал, даже если все проверки прошли.
	#
	# Набор «выдержка» однажды отчитался «все проверки пройдены» и оставил
	# после себя лог на шесть мегабайт: батраки несли груз к снесённому складу,
	# и каждый кадр каждого из них сыпал ошибкой обращения к освобождённому
	# объекту. Ни одна проверка её не видела — они спрашивают про правила, а не
	# про stderr, — и нашлась она только потому, что кто-то открыл лог глазами.
	local noisy=0
	noisy="$(grep -h "SCRIPT ERROR" "$LOGS/$name-"*.log 2>/dev/null | wc -l | tr -d ' ')"
	[ -z "$noisy" ] && noisy=0

	if [ $bad -eq 0 ] && [ "$noisy" -eq 0 ]; then
		echo "OK"; passed=$((passed+1))
	elif [ $bad -eq 0 ]; then
		echo "ПРОВАЛ: проверки прошли, но движок ругался ($noisy раз)"
		failed+=("$name")
		grep -hE "SCRIPT ERROR" "$LOGS/$name-"*.log | sort -u | head -5 | sed 's/^/           /'
	else
		var_timeout=0
		for rc in "${rcs[@]}"; do [ "$rc" -eq 124 ] && var_timeout=1; done
		if [ $var_timeout -eq 1 ]; then
			echo "ПРОВАЛ: не уложился в ${SUITE_TIMEOUT} с и был убит"
		else
			echo "ПРОВАЛ (коды: ${rcs[*]})"
		fi
		failed+=("$name")
		grep -hE "ПРОВАЛ" "$LOGS/$name-"*.log | sed 's/^/           /'
	fi
}

for entry in "${SUITES[@]}"; do
	IFS=: read -r name flag factions extra <<<"$entry"
	if [ ${#wanted[@]} -gt 0 ]; then
		skip=1
		for w in "${wanted[@]}"; do [ "$w" = "$name" ] && skip=0; done
		[ $skip -eq 1 ] && continue
	fi
	rm -f "$LOGS/$name-"*.log
	run_suite "$name" "$flag" "$factions" "$extra"
done

echo
if [ ${#failed[@]} -eq 0 ]; then
	echo "Пройдено наборов: $passed. Провалов нет."
else
	echo "Пройдено: $passed. Провалено: ${failed[*]}"
	echo "Логи: $LOGS"
	exit 1
fi
