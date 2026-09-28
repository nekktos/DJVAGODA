extends Node3D
##
## Старейшина эльфов: даёт задания (GDD 9a, 28.09.2026). Пара командиру стражи
## (`commander.gd`), устроен так же: тело — боец-чемпион, логика — на хосте,
## состояние задания — на игроке.
##
## Убить старейшину можно, и это налёт с последствиями: пока он лежит, эльфы не
## получают заданий. Смерть не окончательная — через RESPAWN_DELAY он снова в
## поселении.
##

const TASKS := preload("res://scripts/elf_tasks.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")

## Где стоит: в поселении, в стороне от точки появления и от лавки.
const POSITION := Vector3(-286.0, 0.0, -316.0)
const RESPAWN_DELAY := 180.0
const LEASH := 40.0

var _body: Node3D = null
var _respawn_left := 0.0


func _ready() -> void:
	position = POSITION


func on_duty() -> bool:
	return _body != null and is_instance_valid(_body)


func in_range(point: Vector3) -> bool:
	if not on_duty():
		return false
	return _flat(point, _body.global_position) <= TASKS.TALK_RANGE


func _physics_process(delta: float) -> void:
	if not Net.hosting():
		return
	_tick_body(delta)
	for elf in _elves():
		_tick_task(elf, delta)


func _tick_body(delta: float) -> void:
	if on_duty():
		return
	if _body != null:
		_body = null
		_respawn_left = RESPAWN_DELAY
		_announce("Старейшина эльфов пал. Заданий не будет, пока он не вернётся.")
		return
	if _respawn_left > 0.0:
		_respawn_left -= delta
		if _respawn_left > 0.0:
			return
	var world := get_parent()
	if world == null or not world.has_method("spawn_garrison_unit"):
		return
	_body = world.spawn_garrison_unit(FACTIONS.Kind.ELVES, 3, POSITION, POSITION, LEASH, true)


func _elves() -> Array:
	var found := []
	var players := get_parent().get_node_or_null("Players")
	if players == null:
		return found
	for child in players.get_children():
		if "faction" in child and "order_kind" in child and int(child.faction) == FACTIONS.Kind.ELVES:
			found.append(child)
	return found


func _tick_task(elf: Node3D, delta: float) -> void:
	if elf.order_kind < 0 or not elf.health.alive:
		return
	match int(elf.order_kind):
		TASKS.Kind.MINE:
			var world := get_parent()
			var mine: Node3D = world.mine_near(elf.global_position)
			if mine != null and _flat(elf.global_position, mine.global_position) <= TASKS.HOLD_RADIUS + 20.0:
				_hold(elf, mine.global_position, delta)
		TASKS.Kind.RECLAIM:
			for spot in WORLD_BUILDER.HAMLETS:
				var at := Vector3(spot.x, 0.0, spot.y)
				if _flat(elf.global_position, at) <= TASKS.HOLD_RADIUS:
					_hold(elf, at, delta)
					break
		TASKS.Kind.HORSE:
			if elf.riding() != null and _flat(elf.global_position,
					FACTIONS.SPAWN[FACTIONS.Kind.ELVES]) <= TASKS.VILLAGE_RADIUS:
				elf.order_progress = TASKS.target_of(TASKS.Kind.HORSE)


## Держать место: секунды идут, пока рядом нет чужих.
func _hold(elf: Node3D, at: Vector3, delta: float) -> void:
	if _hostiles_near(at, TASKS.HOLD_RADIUS) > 0:
		return
	elf.set_meta("task_seconds", float(elf.get_meta("task_seconds", 0.0)) + delta)
	var whole := int(elf.get_meta("task_seconds", 0.0))
	if whole != elf.order_progress:
		elf.order_progress = whole


## Эльф остановил чужой обоз: увёл лошадей, разграбил или разбил повозку.
func report_caravan_hit(peer: int, cart_faction: int) -> void:
	if not Net.hosting() or cart_faction == FACTIONS.Kind.ELVES:
		return
	for elf in _elves():
		if int(elf.peer_id) == peer and int(elf.order_kind) == TASKS.Kind.AMBUSH:
			elf.order_progress = TASKS.target_of(TASKS.Kind.AMBUSH)


## Кого-то убили: батраков чужих — «подрубить хозяйство», вожака — «охота».
func report_victim(killer_id: int, victim: Node3D) -> void:
	if not Net.hosting() or victim == null or not ("faction" in victim):
		return
	if not FACTIONS.hostile(FACTIONS.Kind.ELVES, int(victim.faction)):
		return
	for elf in _elves():
		if int(elf.peer_id) != killer_id:
			continue
		if int(elf.order_kind) == TASKS.Kind.LABOURERS and "sync_role" in victim:
			elf.order_progress += 1
		if int(elf.order_kind) == TASKS.Kind.HEAD and "is_leader" in victim and bool(victim.is_leader):
			elf.order_progress = TASKS.target_of(TASKS.Kind.HEAD)


## Доклад: выдать первое, принять выполненное и заплатить, выдать следующее.
func report(elf: Node3D) -> String:
	if not Net.hosting() or not in_range(elf.global_position):
		return ""
	if elf.order_kind < 0:
		return _issue_next(elf)
	if elf.order_progress < TASKS.target_of(elf.order_kind):
		return "Задание не выполнено: %s" % TASKS.progress_text(elf.order_kind, elf.order_progress)
	var reward: Array = TASKS.reward_of(elf.order_kind)
	for i in reward.size():
		if int(reward[i]) > 0:
			elf.stock.add(i, int(reward[i]))
	elf.orders_done += 1
	var done_name := TASKS.name_of(elf.order_kind)
	elf.order_kind = -1
	elf.order_progress = 0
	return "Задание «%s» выполнено. %s" % [done_name, _issue_next(elf)]


func _issue_next(elf: Node3D) -> String:
	var kind := _next_kind(elf)
	elf.order_kind = kind
	elf.order_progress = 0
	elf.set_meta("task_seconds", 0.0)
	var text := "Новое задание: %s" % TASKS.name_of(kind)
	_notify(elf, text)
	return text


## Следующее выполнимое задание. После HEAD_AFTER сданных — охота за головой,
## если есть за кем охотиться.
func _next_kind(elf: Node3D) -> int:
	if int(elf.orders_done) >= TASKS.HEAD_AFTER and _heads_alive():
		return TASKS.Kind.HEAD
	var start := int(elf.orders_done) % TASKS.ROTATION.size()
	for step in TASKS.ROTATION.size():
		var kind: int = TASKS.ROTATION[(start + step) % TASKS.ROTATION.size()]
		if kind == TASKS.Kind.LABOURERS and not _enemy_labourers():
			continue
		return kind
	return TASKS.Kind.AMBUSH


func _enemy_labourers() -> bool:
	for unit in get_tree().get_nodes_in_group("unit"):
		if "sync_role" in unit and FACTIONS.hostile(FACTIONS.Kind.ELVES, int(unit.faction)):
			return true
	return false


func _heads_alive() -> bool:
	var objective: Node = get_parent().get_node_or_null("Objective")
	if objective == null:
		return false
	return not objective.leader_is_down(FACTIONS.Kind.VILLAIN) or not objective.leader_is_down(FACTIONS.Kind.GUARD)


func _hostiles_near(point: Vector3, radius: float) -> int:
	var count := 0
	var world := get_parent()
	var players: Node = world.get_node_or_null("Players")
	if players != null:
		for child in players.get_children():
			if "faction" in child and FACTIONS.hostile(FACTIONS.Kind.ELVES, int(child.faction)) \
					and child.health.alive and _flat(child.global_position, point) <= radius:
				count += 1
	for unit in get_tree().get_nodes_in_group("unit"):
		if not ("faction" in unit) or not FACTIONS.hostile(FACTIONS.Kind.ELVES, int(unit.faction)):
			continue
		if float(unit.health) > 0.0 and _flat(unit.global_position, point) <= radius:
			count += 1
	return count


func _notify(elf: Node3D, text: String) -> void:
	print("[старейшина] игроку %d: %s" % [int(elf.peer_id), text])
	var objective: Node3D = get_parent().get_node_or_null("Objective")
	if objective == null:
		return
	if int(elf.peer_id) == 1:
		objective.announced.emit(text)
	else:
		objective.announce.rpc_id(int(elf.peer_id), text)


func _announce(text: String) -> void:
	var objective: Node3D = get_parent().get_node_or_null("Objective")
	if objective != null:
		objective.announce.rpc(text)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
