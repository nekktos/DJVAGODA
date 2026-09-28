extends "res://tools/test_base.gd"
##
## Задания старейшины эльфов (GDD 9a, 28.09.2026).
##
## Запуск: godot --headless --path godot_project -- --host --faction=1 --eldertest
##
## Автор поручил придумать эльфам интересные задачи. Задания засчитываются
## ДЕЛОМ: увёл лошадей из чужого обоза, простоял у шахты, убил батрака,
## удержал хутор, приехал в поселение верхом, убил вожака.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const TASKS := preload("res://scripts/elf_tasks.gd")
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")
const LABOURER := preload("res://scripts/units/labourer.gd")

var _world: Node3D
var _elder: Node3D


func start(world: Node3D) -> void:
	tag = "старейшина"
	expected_host = 8
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(2.0).timeout
	var me: Node3D = _world.local_player()
	if me == null or int(me.faction) != FACTIONS.Kind.ELVES:
		fail("набор должен идти за эльфов")
		finish()
		return
	_elder = _world.elder

	await _test_first_task(me)
	await _test_ambush(me)
	await _test_mine(me)
	await _test_labourers(me)
	await _test_reclaim(me)
	await _test_horse(me)
	await _test_head(me)
	finish()


func _give(me: Node3D, kind: int) -> void:
	me.order_kind = kind
	me.order_progress = 0
	me.set_meta("task_seconds", 0.0)


func _go_to_elder(me: Node3D) -> void:
	me.teleport.rpc(_elder.POSITION + Vector3(0.0, 1.0, 3.0))
	await get_tree().create_timer(0.4).timeout


## У старейшины дают первое задание; сданное — оплачивается.
func _test_first_task(me: Node3D) -> void:
	await _go_to_elder(me)
	me.request_report()
	check(_elder.on_duty() and me.at_elder() and int(me.order_kind) == TASKS.Kind.AMBUSH,
		"у старейшины эльф получает первое задание — засаду",
		"на посту %s, рядом %s, задание %d" % [_elder.on_duty(), me.at_elder(), int(me.order_kind)])


## Засада: увёл лошадей из чужого обоза — выполнено; сдал — заплатили.
func _test_ambush(me: Node3D) -> void:
	var spot: Vector3 = me.global_position + Vector3(0.0, 0.0, 30.0)
	var cart: Node3D = _world.spawn_caravan(PackedVector3Array([spot, spot + Vector3(0.0, 0.0, 200.0)]),
		0, FACTIONS.Kind.VILLAIN, 2)
	await get_tree().physics_frame
	me.teleport.rpc(cart.global_position + Vector3(2.5, 1.0, 0.0))
	await get_tree().create_timer(0.8).timeout
	me.request_rob_caravan()
	await get_tree().physics_frame
	var done: bool = int(me.order_progress) >= 1
	var gold: int = int(me.stock.get_amount(RES.Kind.GOLD))
	await _go_to_elder(me)
	me.request_report()
	check(done and int(me.orders_done) == 1 and int(me.stock.get_amount(RES.Kind.GOLD)) > gold,
		"увёл лошадей из чужого обоза — засада выполнена и оплачена",
		"выполнено %s, сдано %d, золото %d -> %d" % [done, int(me.orders_done), gold,
			int(me.stock.get_amount(RES.Kind.GOLD))])
	if is_instance_valid(cart):
		cart.queue_free()


func _test_mine(me: Node3D) -> void:
	_give(me, TASKS.Kind.MINE)
	var mine: Node3D = _world.mine_of(RES.Kind.IRON)
	me.teleport.rpc(_world.mine_dock(mine) + Vector3(0.0, 2.0, 0.0))
	await get_tree().create_timer(3.5).timeout
	check(int(me.order_progress) >= 2, "у шахты без чужих время идёт",
		"%d с" % int(me.order_progress))


## Батраки: засчитывается чужой батрак, а свой боец — нет.
func _test_labourers(me: Node3D) -> void:
	_give(me, TASKS.Kind.LABOURERS)
	var at: Vector3 = me.global_position + Vector3(4.0, 0.0, 0.0)
	var worker: Node3D = _world.spawn_labourer(FACTIONS.Kind.VILLAIN, at, at, LABOURER.Role.LUMBERJACK)
	var own: Node3D = _world.spawn_garrison_unit(FACTIONS.Kind.ELVES, 0, at, at, 5.0)
	await get_tree().physics_frame
	own.take_damage(99999.0, int(me.peer_id), "torso", own.global_position, Vector3.FORWARD)
	var after_own: int = int(me.order_progress)
	worker.take_damage(99999.0, int(me.peer_id), "torso", worker.global_position, Vector3.FORWARD)
	await get_tree().physics_frame
	check(after_own == 0 and int(me.order_progress) == 1,
		"засчитан убитый батрак злодея, а не свой эльф",
		"за своего %d, за батрака %d" % [after_own, int(me.order_progress)])


func _test_reclaim(me: Node3D) -> void:
	_give(me, TASKS.Kind.RECLAIM)
	var hamlet: Vector2 = WORLD_BUILDER.HAMLETS[3]
	me.teleport.rpc(Vector3(hamlet.x, 2.0, hamlet.y))
	await get_tree().create_timer(3.5).timeout
	check(int(me.order_progress) >= 2, "на хуторе без чужих время идёт",
		"%d с" % int(me.order_progress))


## Коня приводят в поселение верхом: пешком не считается.
func _test_horse(me: Node3D) -> void:
	_give(me, TASKS.Kind.HORSE)
	var village: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.ELVES]
	me.teleport.rpc(village + Vector3(10.0, 1.0, 10.0))
	await get_tree().create_timer(0.5).timeout
	var on_foot: int = int(me.order_progress)
	var horse: Node3D = _world.spawn_horse(me.global_position + Vector3(1.5, 0.0, 0.0))
	await get_tree().create_timer(0.5).timeout
	me.request_mount()
	await get_tree().create_timer(0.8).timeout
	check(on_foot == 0 and me.riding() != null and int(me.order_progress) == 1,
		"конь пригнан в поселение верхом, пешком не считается",
		"пешком %d, верхом %s, прогресс %d" % [on_foot, me.riding() != null, int(me.order_progress)])
	if me.riding() != null:
		me.request_mount()
	await get_tree().physics_frame


## Охота за головой — после пяти заданий, и засчитывается смерть вожака.
func _test_head(me: Node3D) -> void:
	me.orders_done = TASKS.HEAD_AFTER - 1
	_give(me, -1)
	var early: int = _elder._next_kind(me)
	me.orders_done = TASKS.HEAD_AFTER
	var late: int = _elder._next_kind(me)
	check(early != TASKS.Kind.HEAD and late == TASKS.Kind.HEAD,
		"охоту за головой дают только после пяти заданий",
		"за 4 — %d, за 5 — %d" % [early, late])
	_give(me, TASKS.Kind.HEAD)
	var villain: Node3D = _world.ai_hero_of(FACTIONS.Kind.VILLAIN)
	if villain == null:
		fail("ИИ-вожака злодея нет")
		return
	villain.take_damage(99999.0, int(me.peer_id), "torso", villain.global_position, Vector3.FORWARD)
	await get_tree().create_timer(0.5).timeout
	check(int(me.order_progress) == 1, "вожак злодея убит своими руками — охота выполнена",
		"прогресс %d" % int(me.order_progress))
