extends "res://tools/test_base.gd"
##
## Автопроверка боевой петли на двух пирах. Работает headless.
##
## Запуск (два процесса):
##   godot --headless --path godot_project -- --host --combattest
##   godot --headless --path godot_project -- --join=127.0.0.1 --combattest
##
## Роли расходятся сами: хост бьёт, клиент стоит и пытается смошенничать.
## Проверяем две вещи, ради которых Этап 2 вообще так устроен:
##   1. Урон доходит и одинаково виден обоим пирам.
##   2. Клиент НЕ может снять здоровье в обход хоста.
##

const WEAPONS := preload("res://scripts/combat/weapons.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "бой-тест"
	expected_host = 4
	expected_client = 2
	_world = world
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(4.0).timeout
	var mine: Node3D = _world.local_player()
	var other := _find_other(mine)
	if mine == null or other == null:
		fail("нужны два игрока в сессии")
		finish()
		return

	if Net.hosting():
		await _run_host(mine, other)
	else:
		await _run_client(mine, other)
	finish()


func _find_other(mine: Node3D) -> Node3D:
	for child in _world.get_node("Players").get_children():
		if child != mine:
			return child
	return null


# --- хост: бьёт и проверяет, что урон прошёл ------------------------------

func _run_host(mine: Node3D, other: Node3D) -> void:
	for kind in [WEAPONS.Kind.SWORD, WEAPONS.Kind.BOW, WEAPONS.Kind.SPELL]:
		# Ждём респавна, если предыдущее оружие цель добило.
		#
		# Респавн УНОСИТ цель на её базу, и делает это с задержкой: пока идёт
		# отсчёт, цель ещё лежит на месте, `_aim_at` наводится по ней — а через
		# секунду она оказывается за сотню метров, и следующий выстрел летит в
		# пустоту. Один раз это уже стоило получаса разбора: провалился огненный
		# шар, а виноват был меч, убивший цель тактом раньше.
		var waited := 0.0
		while not other.health.alive and waited < 12.0:
			await get_tree().create_timer(0.5).timeout
			waited += 0.5
		other.health.revive()
		await get_tree().process_frame

		var distance := 2.0 if kind == WEAPONS.Kind.SWORD else 20.0
		var before: float = other.health.current
		_aim_at(mine, other, distance)
		mine.sync_weapon = kind
		mine.scripted_input = {"move": Vector2.ZERO, "jump": false, "attack": true}
		await get_tree().create_timer(4.0).timeout
		mine.scripted_input = {}
		await get_tree().create_timer(0.6).timeout

		var after: float = other.health.current
		check(after < before, WEAPONS.NAMES[kind],
			"здоровье цели %.0f -> %.0f" % [before, after])

	# Убить цель и убедиться, что она вернулась в мир после респавна.
	if not is_instance_valid(other):
		fail("смерть и респавн: цель ушла из сессии")
		return
	other.health.revive()
	await get_tree().process_frame
	other.take_damage(999.0, 1, "torso", other.global_position, Vector3.FORWARD)
	await get_tree().create_timer(1.0).timeout
	var died: bool = not other.health.alive

	# Ловим МОМЕНТ возвращения, а не смотрим на здоровье через шесть секунд.
	#
	# Раненый истекает кровью — три очка в секунду, пока не перевяжется (см.
	# `body.gd::BLEED_PER_SECOND`), и раны респавн не лечит, это правило GDD 4.1.
	# Прежняя проверка ждала шесть секунд и требовала «больше 99»: она мерила не
	# респавн, а кровотечение, и падала, стоило цели дожить до конца боя с
	# распоротой рукой. Один раз так и вышло — и полчаса ушло на поиск поломки в
	# респавне, который работал безупречно.
	var revived := false
	var restored := 0.0
	for i in 20:
		await get_tree().create_timer(0.5).timeout
		if not is_instance_valid(other):
			fail("смерть и респавн: цель ушла из сессии")
			return
		if other.health.alive:
			revived = true
			restored = other.health.current
			break
	check(died and revived and restored > 99.0, "смерть и респавн",
		"умер=%s, вернулся=%s со здоровьем %.0f" % [died, revived, restored])


## Поставить себя на нужной дистанции от цели и повернуться к ней лицом.
func _aim_at(mine: Node3D, other: Node3D, distance: float) -> void:
	var target := other.global_position
	var point := target + Vector3(0.0, 0.0, 1.0) * distance
	mine.global_position = Vector3(point.x, target.y, point.z)
	mine.sync_position = mine.global_position
	var dir := (target - mine.global_position)
	dir.y = 0.0
	dir = dir.normalized()
	mine.rotation.y = atan2(-dir.x, -dir.z)
	mine.sync_yaw = mine.rotation.y
	mine.velocity = Vector3.ZERO


# --- клиент: стоит смирно и пробует смошенничать --------------------------

func _run_client(mine: Node3D, _other: Node3D) -> void:
	# Ждём, пока хост отработает свои сценарии, и следим за своим здоровьем.
	var seen_damage := false
	# Окно короче, чем сценарии хоста: иначе он закончит и порвёт сессию
	# раньше, чем клиент успеет проверить подделку.
	for i in 11:
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(mine):
			fail("клиент: сессия закончилась раньше проверки")
			return
		if mine.health.current < 100.0:
			seen_damage = true

	if not is_instance_valid(mine):
		return

	# Прямая попытка чита: выставляем себе заведомо невозможное здоровье.
	# Хост об этом не знает и знать не должен — но репликация обязана затереть
	# подделку, а все решения по урону хост и так принимает по своему значению.
	mine.health.current = 500.0
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(mine):
		return
	var after_cheat: float = mine.health.current
	var cheat_blocked := after_cheat <= 100.0

	check(seen_damage, "клиент видел урон", str(seen_damage))
	check(cheat_blocked, "подделка здоровья затёрта",
		"выставил 500, стало %.0f" % after_cheat)

	# Досиживаем до конца сценариев хоста, иначе его цель исчезнет из сессии
	# посреди проверки смерти и респавна.
	await get_tree().create_timer(20.0).timeout
