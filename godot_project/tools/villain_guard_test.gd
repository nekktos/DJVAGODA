extends "res://tools/test_base.gd"
##
## Стража берёт злодея снаряжением, а не числом (ответ автора от 29.09).
##
## Запуск: хост — злодей, клиент — страж (`run_tests.sh villaintough`).
##
## ЗАЧЕМ. «Долгая партия» показала: стража под ИИ приходит в пустой форт злодея
## на второй-четвёртой минуте, убивает вожака — а смерть его окончательна, — и
## злодей выбывает, не построив и конюшни. Автор оставил жёсткий старт, но
## решил: «стража с непрокачанным оружием и бронёй может только с огромным
## трудом убить злодея». Мера — снаряжённость ударившего: оружие плюс доспех.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")

const HIT := 20.0
## Больше этой доли удара непрокачанный стражник злодею не снимает.
const PLAIN_SHARE := 0.25
## Сколько злодей стоит посреди гарнизона дворца, не отвечая.
const STAND_SECONDS := 8.0

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "злодей и стража"
	expected_host = 5
	expected_client = 1
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
		check(int(me.faction) == FACTIONS.Kind.GUARD, "клиент играет стражем",
			FACTIONS.name_of(int(me.faction)))
		await get_tree().create_timer(STAND_SECONDS + 8.0).timeout
		finish()
		return

	var guards: Array = _world.characters_of(FACTIONS.Kind.GUARD)
	if guards.is_empty():
		fail("стража в сессии нет")
		finish()
		return
	var guard: Node3D = guards[0]

	guard.gear_tier = 0
	guard.armor_tier = 0
	var plain: float = _loss(me, guard)
	# Мерой — не таблица из кода (с ней проверка согласилась бы с любой
	# поломкой таблицы), а слова автора: «с огромным трудом». Четверть силы
	# и меньше.
	check(plain > 0.0 and plain <= HIT * PLAIN_SHARE,
		"непрокачанный стражник бьёт злодея в малую долю силы",
		"удар %.0f снял %.1f" % [HIT, plain])

	guard.gear_tier = 2
	guard.armor_tier = 2
	var kitted: float = _loss(me, guard)
	check(is_equal_approx(kitted, HIT), "снаряжённый до предела — в полную",
		"удар %.0f снял %.1f" % [HIT, kitted])
	guard.gear_tier = 0
	guard.armor_tier = 0

	var pawn: Node3D = null
	for unit in get_tree().get_nodes_in_group("unit"):
		if is_instance_valid(unit) and int(unit.faction) == FACTIONS.Kind.GUARD:
			pawn = unit
			break
	var by_pawn: float = _loss(me, pawn) if pawn != null else -1.0
	check(pawn != null and by_pawn > 0.0 and by_pawn <= HIT * PLAIN_SHARE,
		"пешка стражи — всегда непрокачанная", "снял %.1f" % by_pawn)

	# Живой бой: злодей посреди двора стражи и не отвечает.
	me.health.current = me.health.maximum()
	me.control_enabled = false
	# К самому гарнизону: ставим злодея рядом с его пешкой.
	var post: Vector3 = pawn.global_position if pawn != null else FACTIONS.SPAWN[FACTIONS.Kind.GUARD]
	me.teleport.rpc(post + Vector3(2.5, 1.0, 0.0))
	var before: float = me.health.current
	await get_tree().create_timer(STAND_SECONDS).timeout
	check(bool(me.health.alive), "злодей %d с стоит посреди гарнизона и жив" % int(STAND_SECONDS),
		"здоровье %.0f из %.0f" % [me.health.current, me.health.maximum()])
	check(me.health.current < before, "но его и правда бьют", "здоровье %.0f → %.0f"
		% [before, me.health.current])
	me.control_enabled = true
	await get_tree().create_timer(4.0).timeout
	finish()


## Сколько здоровья снял один удар этим источником.
func _loss(me: Node3D, source: Node) -> float:
	me.health.current = me.health.maximum()
	var before: float = me.health.current
	me.take_damage(HIT, int(source.get("peer_id")) if "peer_id" in source else 0, "torso",
		me.global_position + Vector3.UP, Vector3.FORWARD, false, WEAPONS.Kind.SWORD, source)
	var lost: float = before - me.health.current
	me.health.current = me.health.maximum()
	return lost
