extends "res://tools/test_base.gd"
##
## Автопроверка консольных команд (инструмент playtest). Работает headless.
##
## Запуск: godot --headless --path godot_project -- --host --consoletest
##
## Гоняем команды тем же путём, что и живая консоль: через ask_cheat, то есть
## через хост. Проверяем не текст ответа, а фактический эффект в мире.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")

var _world: Node3D
var _last_reply := ""


func start(world: Node3D) -> void:
	tag = "консоль-тест"
	expected_host = 11
	expected_client = 1
	_world = world
	_run.call_deferred()

func _say(me: Node3D, line: String) -> void:
	me.ask_cheat(line)
	await get_tree().create_timer(0.25).timeout


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return
	me.cheat_reply.connect(func(text: String) -> void: _last_reply = text)

	# res
	var wood_before: int = me.stock.get_amount(RES.Kind.WOOD)
	await _say(me, "res all 50")
	check(me.stock.get_amount(RES.Kind.WOOD) > wood_before, "res all выдаёт ресурсы",
		"дерево %d -> %d" % [wood_before, me.stock.get_amount(RES.Kind.WOOD)])

	# bandages
	await _say(me, "bandages 9")
	check(int(me.body.bandages) >= 9, "bandages выдаёт бинты", "бинтов %d" % int(me.body.bandages))

	# army
	await _say(me, "army 5")
	await get_tree().create_timer(0.5).timeout
	var squad: int = _world.units_of(int(me.peer_id)).size()
	check(squad >= 5, "army ставит бойцов", "в отряде %d" % squad)

	# limb + prosthetic + heal
	await _say(me, "limb arm_r")
	check(me.body.is_severed(1), "limb отрывает конечность", me.body.summary())

	await _say(me, "prosthetic 3")
	check(int(me.body.tier(1)) == 3, "prosthetic ставит протез", me.body.summary())

	await _say(me, "heal")
	check(me.body.severed_mask == 0 and me.health.current > 99.0,
		"heal снимает раны и лечит", "тело: %s, HP %d" % [me.body.summary(), int(me.health.current)])

	# hurt
	var hp_before: float = me.health.current
	await _say(me, "hurt torso 15")
	check(me.health.current < hp_before, "hurt наносит урон",
		"HP %.0f -> %.0f" % [hp_before, me.health.current])
	await _say(me, "heal")

	# goto
	await _say(me, "goto palace")
	await get_tree().create_timer(0.6).timeout
	var to_palace: float = Vector3(me.global_position.x, 0.0, me.global_position.z).distance_to(
		Vector3(_world.objective.PALACE.x, 0.0, _world.objective.PALACE.z)
	)
	check(to_palace < 20.0, "goto переносит к точке", "до дворца %.1f м" % to_palace)

	# capture
	await _say(me, "capture")
	check(int(_world.objective.palace_owner) == int(me.faction),
		"capture отдаёт дворец", _world.objective.status_text())

	# tp
	await _say(me, "tp 40 40")
	await get_tree().create_timer(0.6).timeout
	check(absf(me.global_position.x - 40.0) < 3.0, "tp переносит по координатам",
		"стоит %s" % me.global_position)

	# неизвестная команда не ломает игру
	await _say(me, "абракадабра")
	check(_last_reply.contains("неизвестная"), "неизвестная команда отбивается",
		"ответ: %s" % _last_reply)

	finish()
