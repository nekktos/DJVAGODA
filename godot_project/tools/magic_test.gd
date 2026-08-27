extends "res://tools/test_base.gd"
##
## Автопроверка магии злодея (Этап 10, шаг 9, GDD раздел 3.2). Работает headless.
##
## Запуск:
##   godot --headless --path godot_project -- --host --faction=0 --magictest
##   godot --headless --path godot_project -- --join=127.0.0.1 --faction=1 --magictest
##
## Хост — злодей, клиент — эльф: заклинаниям нужна живая цель другой стороны.
##
## ГЛАВНОЕ, ЧТО ЗДЕСЬ ПРОВЕРЯЕТСЯ, — не то, что заклинания работают, а то, что
## работает КОНТРПЛЕЙ. Паралич без контрплея ощущается читерским, и это прямо
## записано в GDD: каст прерывается уроном, после снятия есть окно неуязвимости,
## любой урон снимает эффект досрочно. Каждый из трёх — отдельная проверка,
## потому что каждый можно сломать по отдельности и не заметить.
##
## И отдельно: над живым игроком НЕТ буквального перехвата управления. Проверяем
## прямо — сторона цели после паралича обязана остаться прежней.
##

const FACTIONS := preload("res://scripts/factions.gd")
const ABILITIES := preload("res://scripts/combat/abilities.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "магия"
	expected_host = 25
	expected_client = 2
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	if not Net.hosting():
		await _run_client(me)
		finish()
		return

	_test_sets()
	var victim: Node3D = _enemy_player(me)
	if victim == null:
		fail("второго игрока в сессии нет — проверять магию не на ком")
		finish()
		return
	victim.teleport.rpc(me.global_position + Vector3(4.0, 0.0, 0.0))
	await get_tree().create_timer(0.6).timeout

	# Порядок не случайный. Проверки, которым нужна ЖИВАЯ цель, идут первыми, а
	# те, что её калечат, — последними. Иначе эльф умирает от наложенного
	# кровотечения посреди прогона, уходит на возрождение, и следующая проверка
	# падает на ссылке, которой уже нет. Дважды подряд так и вышло.
	# Цель берём ЗАНОВО перед каждым шагом. Она живой персонаж на другом конце
	# провода: может умереть от наложенного кровотечения, уйти на возрождение, а
	# в конце и вовсе исчезнуть вместе с клиентом. Ссылка, взятая один раз,
	# протухает молча — а следом молча обрывается вся корутина, и набор не
	# заканчивается никогда. Один раз он так и висел, пока его не убил сторож.
	for step in ["blind", "reach", "hold", "immunity", "wither", "break", "interrupt"]:
		victim = _live_victim(me)
		if victim == null:
			fail("цель исчезла на шаге «%s»" % step)
			break
		match step:
			"blind": await _test_blind(me, victim)
			"reach": await _test_reaches_target(me, victim)
			"hold": await _test_paralysis_holds(me, victim)
			"immunity": await _test_paralysis_immunity(me, victim)
			"wither": await _test_wither(me, victim)
			"break": await _test_damage_breaks_paralysis(me, victim)
			"interrupt": await _test_cast_interrupt(me, victim)
	await _test_charm(me)

	if not multiplayer.get_peers().is_empty():
		await get_tree().create_timer(4.0).timeout
	finish()


## Заклинания у злодея, поддержка у эльфов, у стражи ничего.
func _test_sets() -> void:
	check(FACTIONS.ability_on_slot(FACTIONS.Kind.VILLAIN, 0) == ABILITIES.Kind.PARALYSIS,
		"у злодея на четвёртой клавише паралич", "да")
	check(FACTIONS.ability_on_slot(FACTIONS.Kind.ELVES, 0) == ABILITIES.Kind.HEAL,
		"у эльфа на той же клавише лечение", "да")
	check(FACTIONS.ability_on_slot(FACTIONS.Kind.GUARD, 0) < 0,
		"у стражи магии нет вовсе", "клавиша пустая")
	check(not FACTIONS.allows_ability(FACTIONS.Kind.ELVES, ABILITIES.Kind.PARALYSIS),
		"чужое заклинание стороне недоступно", "эльфу паралич не наложить")


## Паралич держит цель, но НЕ отбирает её у неё самой.
func _test_paralysis_holds(me: Node3D, victim: Node3D) -> void:
	var faction_before: int = int(victim.faction)
	var ok: bool = victim.apply_paralysis(ABILITIES.PARALYSIS_HOLD)
	check(ok and victim.sync_paralysis > 0.0, "паралич наложен",
		"на %.1f с" % victim.sync_paralysis)
	check(int(victim.faction) == faction_before,
		"сторона цели НЕ меняется — перехвата управления над игроком нет",
		FACTIONS.name_of(int(victim.faction)))
	check(ABILITIES.PARALYSIS_HOLD < ABILITIES.RALLY_DURATION,
		"паралич короче эльфийского баффа — тяжёлый контроль обязан быть коротким",
		"%.0f с против %.0f" % [ABILITIES.PARALYSIS_HOLD, ABILITIES.RALLY_DURATION])

	# Парализованный не двигается, даже если ему дать ввод.
	var where: Vector3 = victim.global_position
	victim.apply_input({"move": Vector2(0.0, -1.0), "jump": false}, 0.2)
	check(victim.global_position.distance_to(where) < 0.5,
		"парализованный не идёт даже с вводом",
		"сдвинулся на %.2f м" % victim.global_position.distance_to(where))


## После снятия — окно неуязвимости. Без него цепочка кастов держала бы игрока
## в вечном контроле.
func _test_paralysis_immunity(_me: Node3D, victim: Node3D) -> void:
	victim.sync_paralysis = 0.0
	await get_tree().create_timer(0.4).timeout
	var again: bool = victim.apply_paralysis(ABILITIES.PARALYSIS_HOLD)
	check(not again, "повторный паралич сразу после снятия не проходит",
		"отказано")
	check(ABILITIES.PARALYSIS_IMMUNITY > ABILITIES.PARALYSIS_HOLD * 3.0,
		"окно неуязвимости заметно длиннее самого паралича",
		"%.0f с против %.0f" % [ABILITIES.PARALYSIS_IMMUNITY, ABILITIES.PARALYSIS_HOLD])


## Любой урон снимает паралич досрочно.
func _test_damage_breaks_paralysis(me: Node3D, victim: Node3D) -> void:
	victim._paralysis_immunity = 0.0
	victim._was_paralysed = false
	var ok: bool = victim.apply_paralysis(ABILITIES.PARALYSIS_HOLD)
	check(ok, "паралич наложен повторно после окна", "да")
	victim.take_damage(5.0, int(me.peer_id), "torso", victim.global_position, Vector3.UP)
	check(victim.sync_paralysis <= 0.0, "урон снимает паралич досрочно",
		"осталось %.1f с" % victim.sync_paralysis)
	victim._paralysis_immunity = 0.0
	victim._was_paralysed = false
	await get_tree().process_frame


## Каст видимый и прерывается уроном по кастующему. Это и есть повод, ради
## которого у злодея молот сбивает с ног.
func _test_cast_interrupt(me: Node3D, victim: Node3D) -> void:
	me.sync_ability_cd[ABILITIES.Kind.PARALYSIS] = 0.0
	victim.sync_paralysis = 0.0
	victim._paralysis_immunity = 0.0
	me.request_ability(ABILITIES.Kind.PARALYSIS)
	await get_tree().physics_frame
	check(me.casting(), "паралич не срабатывает мгновенно — идёт каст",
		"каст идёт")

	me.take_damage(3.0, int(victim.peer_id), "torso", me.global_position, Vector3.UP)
	check(not me.casting(), "удар по кастующему срывает каст", "каст сорван")
	check(me.sync_ability_cd[ABILITIES.Kind.PARALYSIS] <= 0.0,
		"сорванный каст не съедает откат — иначе это двойное наказание",
		"откат %.1f с" % me.sync_ability_cd[ABILITIES.Kind.PARALYSIS])
	await get_tree().create_timer(ABILITIES.PARALYSIS_CAST + 0.5).timeout
	check(victim.sync_paralysis <= 0.0, "и заклинание не срабатывает потом само",
		"паралича нет")


## Увядание: кровотечение плюс ослабление наносимого урона.
func _test_wither(me: Node3D, victim: Node3D) -> void:
	victim.body.bleeding = false
	victim.sync_wither = 0.0
	check(is_equal_approx(victim.curse_damage_scale(), 1.0), "до проклятия урон обычный",
		"x%.2f" % victim.curse_damage_scale())

	victim.apply_wither(ABILITIES.WITHER_DURATION)
	check(victim.body.bleeding, "увядание открывает кровотечение", "кровит")
	check(victim.curse_damage_scale() < 1.0, "и ослабляет наносимый урон",
		"x%.2f" % victim.curse_damage_scale())
	check(victim.curse_damage_scale() > 0.0, "но не обнуляет его",
		"проклятый дерётся хуже, а не перестаёт")
	victim.sync_wither = 0.0
	victim.body.bleeding = false
	await get_tree().process_frame


## Наложенное должно ДОЕХАТЬ до самой цели, а не только числиться у хоста.
##
## Отдельная проверка нужна потому, что все прочие ставят состояние и снимают
## его в пределах одного кадра — для другой стороны его как не было. Клиентская
## половина набора именно на этом и проваливалась: репликация работала, а видеть
## было нечего. Здесь держим проклятие несколько секунд специально.
func _test_reaches_target(_me: Node3D, victim: Node3D) -> void:
	if not is_instance_valid(victim):
		fail("цели нет")
		return
	victim.apply_wither(4.0)
	check(victim.sync_wither > 0.0, "проклятие держится на цели, а не гаснет сразу",
		"%.1f с" % victim.sync_wither)
	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(victim):
		victim.sync_wither = 0.0
		victim.body.bleeding = false


## Слепота ставится на срок и сама сходит.
##
## Цель спрашиваем ЗАНОВО: к этому моменту по ней уже прошлись уроном и
## кровотечением от увядания, и она могла умереть — а после смерти нода прежнего
## персонажа уничтожается, и ссылка, взятая в начале, протухает молча.
func _test_blind(me: Node3D, stale: Node3D) -> void:
	var victim: Node3D = stale if is_instance_valid(stale) else _enemy_player(me)
	if victim == null:
		fail("цели для слепоты не осталось")
		return
	# Подлечиваем: к этому моменту по цели прошлись уроном и кровотечением, и
	# она умрёт прямо посреди проверки. Здесь проверяется срок действия слепоты,
	# а не живучесть эльфа.
	victim.body.bleeding = false
	victim.health.revive()

	victim.sync_blind = 0.0
	victim.apply_blind(0.6)
	check(victim.sync_blind > 0.0, "слепота наложена", "%.1f с" % victim.sync_blind)
	await get_tree().create_timer(1.2).timeout
	if not is_instance_valid(victim):
		victim = _enemy_player(me)
	if victim == null:
		fail("цель исчезла, пока шёл срок слепоты")
		return
	check(victim.sync_blind <= 0.0, "и сходит сама по сроку", "прошла")


## По наёмному существу паралич — буквальный контроль: боец переходит на сторону
## кастующего и возвращается назад по сроку.
func _test_charm(me: Node3D) -> void:
	var elf_side: int = FACTIONS.Kind.ELVES
	var beast: Node3D = _world.spawn_garrison_unit(elf_side, 4,
		me.global_position + Vector3(3.0, 0.5, 0.0), me.global_position, 40.0)
	await get_tree().physics_frame
	if beast == null:
		fail("бойца для перевербовки создать не удалось")
		return

	beast.charm(int(me.faction), 0.8)
	check(int(beast.faction) == int(me.faction), "боец перешёл под контроль",
		FACTIONS.name_of(int(beast.faction)))
	await get_tree().create_timer(1.4).timeout
	check(not is_instance_valid(beast) or int(beast.faction) == elf_side,
		"и вернулся своим по сроку",
		FACTIONS.name_of(int(beast.faction)) if is_instance_valid(beast) else "погиб")
	if is_instance_valid(beast):
		beast.queue_free()


## Живая цель другой стороны прямо сейчас, или null.
func _live_victim(me: Node3D) -> Node3D:
	var victim: Node3D = _enemy_player(me)
	if victim == null or not is_instance_valid(victim) or not victim.health.alive:
		return null
	return victim


func _enemy_player(me: Node3D) -> Node3D:
	for other in _world.get_node("Players").get_children():
		if other != me and "faction" in other and int(other.faction) != int(me.faction):
			return other
	return null


## Клиент: состояния доезжают до него. Это не мелочь — цель обязана видеть, что
## с ней происходит, иначе паралич выглядит как зависшая игра.
func _run_client(_me: Node3D) -> void:
	var seen := false
	for i in 40:
		await get_tree().create_timer(0.5).timeout
		# Персонажа спрашиваем ЗАНОВО каждый раз: увядание открывает
		# кровотечение, от него можно умереть, а после смерти нода прежнего
		# персонажа уничтожается. Ссылка, взятая один раз, протухает молча.
		var now: Node3D = _world.local_player()
		if now == null:
			continue
		if now.sync_paralysis > 0.0 or now.sync_wither > 0.0 or now.sync_blind > 0.0:
			seen = true
			break
	check(seen, "состояние от чужой магии доехало до цели", "видно у себя")
	var now: Node3D = _world.local_player()
	check(now != null and int(now.faction) == FACTIONS.Kind.ELVES,
		"и сторона цели осталась своей",
		FACTIONS.name_of(int(now.faction)) if now != null else "персонажа нет")

	# Досиживаем до конца половины хоста. Уйдя раньше, клиент уносит с собой
	# цель, на которой хост проверяет остальные заклинания.
	await get_tree().create_timer(30.0).timeout
