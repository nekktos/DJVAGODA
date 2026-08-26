extends "res://tools/test_base.gd"
##
## Автопроверка вертикального среза (Этап 7). Работает headless.
##
## Запуск (до трёх процессов, по одному на сторону):
##   godot --headless --path godot_project -- --host --slicetest --faction=0
##   godot --headless --path godot_project -- --join=127.0.0.1 --slicetest --faction=1
##   godot --headless --path godot_project -- --join=127.0.0.1 --slicetest --faction=2
##
## Проверяем связку целиком: стороны уникальны, у каждой своё место старта,
## своё оружие и свои права, дворец захватывается и оспаривается, а результат
## доезжает до всех пиров.
##

const FACTIONS := preload("res://scripts/factions.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")

var _world: Node3D
var _heard: PackedStringArray = PackedStringArray()


func start(world: Node3D) -> void:
	tag = "срез"
	expected_host = 10
	expected_client = 6
	_world = world
	_world.objective.announced.connect(func(text: String) -> void: _heard.append(text))
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(4.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	# Свой старт каждая сторона проверяет РАНО — до того, как хост начнёт
	# растаскивать всех по карте ради теста захвата.
	_test_own_faction(me)
	if Net.hosting():
		# Ждём, пока подтянутся все пиры и успеют проверить свой старт.
		await get_tree().create_timer(6.0).timeout
		await _test_host_side(me)
	else:
		await _test_client_side(me)

	finish()


## То, что каждая сторона проверяет про себя сама.
func _test_own_faction(me: Node3D) -> void:
	var faction: int = int(me.faction)
	var expected: Vector3 = FACTIONS.SPAWN[faction]
	var flat := Vector3(me.global_position.x, expected.y, me.global_position.z)
	check(flat.distance_to(expected) < 12.0,
		"%s стартует у себя" % FACTIONS.name_of(faction),
		"ожидалось %s, стоит %s" % [expected, me.global_position])

	# Магия только у злодея (DESIGN_ANSWERS.md, пункт 18).
	var has_spell: bool = FACTIONS.allows_weapon(faction, WEAPONS.Kind.SPELL)
	var should_have: bool = faction == FACTIONS.Kind.VILLAIN
	check(has_spell == should_have,
		"набор оружия по стороне", "%s: %s" % [FACTIONS.name_of(faction), FACTIONS.weapons_text(faction)])

	# Стратегический режим только у злодея (пункт 19).
	check(me.has_strategy() == should_have,
		"стратегический режим по стороне",
		"%s: %s" % [FACTIONS.name_of(faction), "есть" if me.has_strategy() else "нет"])

	_world.toggle_camera_mode()
	check(_world.strategy_mode == should_have,
		"переключение камеры уважает сторону",
		"после Tab режим %s" % ("стратегия" if _world.strategy_mode else "экшен"))
	if _world.strategy_mode:
		_world.set_strategy_mode(false)


func _players() -> Array:
	return _world.get_node("Players").get_children().filter(
		func(node: Node) -> bool: return "faction" in node
	)


func _test_host_side(me: Node3D) -> void:
	# Стороны в сессии уникальны.
	var seen := []
	var duplicates := 0
	for player in _players():
		var f: int = int(player.faction)
		if seen.has(f):
			duplicates += 1
		seen.append(f)
	check(duplicates == 0, "стороны в сессии уникальны",
		"игроков %d, повторов %d" % [seen.size(), duplicates])

	# Дворец изначально за стражей.
	check(int(_world.objective.palace_owner) == FACTIONS.Kind.GUARD,
		"дворец изначально за стражей", _world.objective.status_text())

	await _test_capture(me)


## Захват дворца: злодей встаёт в точку и удерживает её.
func _test_capture(me: Node3D) -> void:
	var villain: Node3D = null
	for player in _players():
		if int(player.faction) == FACTIONS.Kind.VILLAIN:
			villain = player
	if villain == null:
		check(false, "захват дворца", "злодея нет в сессии")
		return

	# Уводим всех остальных подальше, чтобы точка не считалась оспариваемой.
	# Двигаем чужих персонажей ТОЛЬКО через teleport.rpc: прямое присваивание
	# позиции с хоста не держится — движение клиент-авторитетное, и владелец
	# перезапишет её своей в ближайшем пакете.
	for player in _players():
		if player == villain:
			continue
		player.teleport.rpc(Vector3(0.0, 2.0, 300.0))

	villain.teleport.rpc(_world.objective.PALACE + Vector3(0.0, 4.0, 0.0))
	await get_tree().create_timer(1.5).timeout
	check(int(_world.objective.claimant) == FACTIONS.Kind.VILLAIN,
		"злодей в точке начинает захват", _world.objective.status_text())

	# Стража приходит оспаривать.
	var guard: Node3D = null
	for player in _players():
		if int(player.faction) == FACTIONS.Kind.GUARD:
			guard = player
	if guard != null:
		guard.teleport.rpc(_world.objective.PALACE + Vector3(6.0, 4.0, 0.0))
		await get_tree().create_timer(2.0).timeout
		check(_world.objective.contested, "приход стражи оспаривает точку",
			_world.objective.status_text())
		guard.teleport.rpc(Vector3(0.0, 2.0, 300.0))
		await get_tree().create_timer(1.5).timeout

	# Досиживаем захват.
	await get_tree().create_timer(_world.objective.CAPTURE_SECONDS + 3.0).timeout
	check(int(_world.objective.palace_owner) == FACTIONS.Kind.VILLAIN,
		"дворец захвачен злодеем", _world.objective.status_text())
	check(_heard.size() > 0, "результат объявлен",
		"объявлений %d: %s" % [_heard.size(), ", ".join(_heard)])


## Клиент только смотрит: доехало ли до него состояние дворца и объявление.
func _test_client_side(me: Node3D) -> void:
	var owner_changed := false
	for i in 60:
		await get_tree().create_timer(0.7).timeout
		if not is_instance_valid(me):
			break
		if int(_world.objective.palace_owner) != FACTIONS.Kind.GUARD:
			owner_changed = true
			break
	check(owner_changed, "смена владельца дворца доехала до клиента",
		"владелец: %s" % FACTIONS.name_of(int(_world.objective.palace_owner)))
	check(_heard.size() > 0, "объявление результата доехало до клиента",
		"объявлений %d: %s" % [_heard.size(), ", ".join(_heard)])
