extends RefCounted
##
## Настройка анимаций импортированной модели.
##
## glTF из пака Kenney приезжает в Godot с режимом LOOP_NONE: анимация ходьбы
## проигрывается один раз и замирает, а персонаж дальше едет в позе последнего
## кадра. Циклические анимации надо помечать вручную.
##
## Разовыми оставляем те, что по смыслу играются один раз: смерть, удары,
## взаимодействия и эмоции. Всё остальное — цикл.
##

## Начала имён анимаций, которые НЕ зацикливаем.
## У Kenney смерть называется «die», у Quaternius «Death», прыжок в приземление
## «Jump_ToIdle» — сравниваем в нижнем регистре и держим оба словаря названий в
## одном списке. Зациклённая смерть выглядит как труп, который встаёт и умирает
## снова, и заметить это в бою некому: смотрят на живых.
## Имена Quaternius сюда пришлось дописать поимённо, и это не придирка к стилю:
## удар у них зовётся `Sword_Attack`, а слово «attack» стоит НЕ в начале — под
## старый список он не попадал и помечался циклом. Зациклённый удар — это боец,
## который машет мечом не переставая; в бою это выглядит как поломка анимации, а
## не как атака. `Idle_Attacking` и `Idle_Weapon` — наоборот стойки, они цикл, и
## поэтому сверяем не подстроку «attack», а начало имени.
const ONE_SHOT_PREFIXES := [
	"die", "death", "attack", "emote", "interact", "pick-up", "jump_toidle",
	"sword_attack", "staff_attack", "spell", "punch", "bow_", "recievehit",
	"roll", "pickup",
]


static func make_looping(player: AnimationPlayer) -> void:
	if player == null:
		return
	for anim_name in player.get_animation_list():
		var anim: Animation = player.get_animation(anim_name)
		if anim == null:
			continue
		anim.loop_mode = Animation.LOOP_NONE if is_one_shot(anim_name) else Animation.LOOP_LINEAR


static func is_one_shot(anim_name: String) -> bool:
	var lowered := anim_name.to_lower()
	for prefix in ONE_SHOT_PREFIXES:
		if lowered.begins_with(prefix):
			return true
	return false


## Чем игра называет движение и как это называется в паке.
##
## Игра говорит «walk», «die», «sit» — своими словами, не зная, чья сегодня
## модель. Пак называет то же самое по-своему, и словарей таких уже два: у
## Kenney строчными, у Quaternius с заглавной и другими словами вовсе. Держим
## перевод ЗДЕСЬ, а не разбрасываем `has_animation` по коду персонажа и бойца.
##
## Пустой список означает «в этом паке такого движения нет» — тогда `resolve`
## вернёт пустую строку, и вызывающий оставит то, что играется сейчас.
const SYNONYMS := {
	"idle": ["idle", "Idle"],
	"walk": ["walk", "Walk"],
	"run": ["run", "Run", "walk", "Walk"],
	"die": ["die", "Death"],
	# Ползания нет ни в одном паке: показываем безногого сидящим, а модель
	# опускаем к земле (см. player.gd::_refresh_posture). Отдельная анимация
	# ползания есть в Universal Animation Library, но это ещё один пак ради
	# одной позы.
	"sit": ["sit", "Idle"],
	"wheelchair-sit": ["wheelchair-sit", "sit", "Idle"],
	"wheelchair-move-forward": ["wheelchair-move-forward", "Walk"],
	# УДАР. Игра зовёт его кенниевскими словами («attack-melee-right»,
	# «holding-right-shoot») — так было написано при коробочных моделях, и после
	# переезда на Quaternius этих имён не стало ни в одной модели. `resolve`
	# честно возвращал пустую строку, `_play` молча выходил, и удар не рисовался
	# вовсе: оставалась только пауза `_swing_left` в позе стойки.
	#
	# Порядок важен — берётся ПЕРВОЕ существующее. Сначала родное имя пака, у
	# каждой стороны своё: у стража `Sword_Attack`, у злодея `Staff_Attack` и
	# `Spell1`, у эльфа-Ranger ближнего боя нет вовсе.
	#
	# `Punch` последним — это заглушка, и сознательная: у Ranger нет ни одной
	# анимации замаха оружием, а эльфу по GDD положены меч и топор. Замах рукой
	# с мечом в кисти читается как удар, пустая пауза — нет. Настоящий замах
	# эльфу придёт вместе с анимационным паком, точка вызова не изменится.
	"attack-melee-right": [
		"attack-melee-right", "Sword_Attack", "Staff_Attack", "Punch",
	],
	"holding-right-shoot": [
		"holding-right-shoot", "Bow_Shoot", "Spell1", "Staff_Attack", "Punch",
	],
}


## Как в этой модели называется движение. Пустая строка — такого в ней нет.
static func resolve(player: AnimationPlayer, wanted: String) -> String:
	if player == null:
		return ""
	for name in SYNONYMS.get(wanted, [wanted]):
		if player.has_animation(name):
			return name
	# Слова нет в словаре — пробуем как есть и с заглавной буквы.
	if player.has_animation(wanted):
		return wanted
	var capitalised := wanted.substr(0, 1).to_upper() + wanted.substr(1)
	return capitalised if player.has_animation(capitalised) else ""
