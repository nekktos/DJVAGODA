extends Node3D
##
## Командир стражи (Этап 9). NPC, который отдаёт приказы, — GDD раздел 2.2.
##
## Состояние приказа лежит НА ИГРОКЕ (player.gd: order_kind, order_progress,
## orders_done), а не здесь. Так оно едет тем же серверным синхронизатором, что
## здоровье и снаряжение, и не нужно заводить отдельный канал репликации ради
## трёх чисел. Командир — только логика на хосте плюс фигура в мире.
##
## Считает и выдаёт всё ТОЛЬКО хост. Клиент рисует панель по реплицированным
## числам и присылает заявку «доложить».
##

const ORDERS := preload("res://scripts/orders.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const MODEL_ANIM := preload("res://scripts/model_anim.gd")

## Модель командира. Отличается от солдатских, чтобы его было видно в толпе.
const MODEL_PATH := "res://assets/characters/character-f.glb"
const MODEL_SCALE := 0.78

## Где стоит: во дворе дворца, в стороне от точки спавна стражи.
const POSITION := Vector3(270.0, 6.0, -235.0)

var _model: Node3D


func _ready() -> void:
	position = POSITION
	_build_figure()


func _build_figure() -> void:
	# Помост, чтобы фигуру было видно и она не терялась на фоне мрамора.
	var stand := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.0, 0.4, 3.0)
	stand.mesh = box
	stand.position = Vector3(0.0, 0.2, 0.0)
	var stand_mat := StandardMaterial3D.new()
	stand_mat.albedo_color = Color(0.72, 0.24, 0.22)
	stand.material_override = stand_mat
	add_child(stand)

	var packed: PackedScene = load(MODEL_PATH)
	if packed == null:
		return
	_model = packed.instantiate()
	_model.name = "Model"
	_model.scale = Vector3.ONE * MODEL_SCALE
	_model.position = Vector3(0.0, 0.4, 0.0)
	# Модель смотрит в +Z, игра считает передом -Z — см. player.gd::_build_model.
	# Разворачиваем лицом к воротам, то есть на юг.
	_model.rotation.y = 0.0
	add_child(_model)
	var anim := _find_anim(_model)
	if anim != null:
		MODEL_ANIM.make_looping(anim)
		if anim.has_animation("idle"):
			anim.play("idle")


## Найти AnimationPlayer в дереве модели: у ассетов Kenney он лежит на разной
## глубине.
func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null


## Стоит ли игрок достаточно близко, чтобы говорить. Клиент считает это же
## значение для подсказки, но решает всё равно хост.
func in_range(point: Vector3) -> bool:
	var flat := Vector3(point.x, POSITION.y, point.z)
	return flat.distance_to(POSITION) <= ORDERS.TALK_RANGE


# --- логика хоста ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for guard in _guards():
		_tick_order(guard, delta)


## Все живые стражи в мире. Приказы получает только эта сторона (GDD 2.2).
func _guards() -> Array:
	var result := []
	var players := get_parent().get_node_or_null("Players")
	if players == null:
		return result
	for child in players.get_children():
		if not ("faction" in child) or not ("order_kind" in child):
			continue
		if int(child.faction) != FACTIONS.Kind.GUARD:
			continue
		result.append(child)
	return result


func _tick_order(guard: Node3D, delta: float) -> void:
	if guard.order_kind < 0:
		return
	match guard.order_kind:
		ORDERS.Kind.HOLD:
			_tick_hold(guard, delta)
		ORDERS.Kind.RAID:
			_tick_raid(guard)


## Держать дворец: секунды капают, только пока страж стоит в точке И дворец наш.
## Если дворец отбили — счётчик стоит, но не обнуляется: приказ не проваливается,
## его просто нельзя выполнить, пока не вернёшь точку.
func _tick_hold(guard: Node3D, delta: float) -> void:
	if not guard.health.alive:
		return
	var objective: Node3D = get_parent().get_node_or_null("Objective")
	if objective == null:
		return
	if int(objective.palace_owner) != FACTIONS.Kind.GUARD:
		return
	var flat := Vector3(guard.global_position.x, objective.PALACE.y, guard.global_position.z)
	if flat.distance_to(objective.PALACE) > objective.RADIUS:
		return

	guard.set_meta("hold_seconds", float(guard.get_meta("hold_seconds", 0.0)) + delta)
	var whole := int(guard.get_meta("hold_seconds", 0.0))
	if whole != guard.order_progress:
		guard.order_progress = whole


## Набег: сперва дойти до форта злодея, потом вернуться живым во дворец.
func _tick_raid(guard: Node3D) -> void:
	if not guard.health.alive:
		return
	if guard.order_progress <= 0:
		if guard.global_position.distance_to(ORDERS.RAID_POINT) <= ORDERS.RAID_RADIUS:
			guard.order_progress = 1
			_notify(guard, "Форт злодея достигнут. Возвращайся во дворец.")
	elif guard.order_progress == 1:
		if in_range(guard.global_position):
			guard.order_progress = 2


## Кто-то что-то убил или разбил. Зовёт мир, командир решает, засчитывать ли.
func report_kill(killer_id: int, victim_faction: int) -> void:
	if not multiplayer.is_server():
		return
	if victim_faction != FACTIONS.Kind.VILLAIN:
		return
	for guard in _guards():
		if int(guard.peer_id) != killer_id:
			continue
		if guard.order_kind == ORDERS.Kind.SLAY:
			guard.order_progress += 1


func report_caravan_destroyed(killer_id: int, owner_faction: int) -> void:
	if not multiplayer.is_server():
		return
	if owner_faction != FACTIONS.Kind.VILLAIN:
		return
	for guard in _guards():
		if int(guard.peer_id) != killer_id:
			continue
		if guard.order_kind == ORDERS.Kind.INTERCEPT:
			guard.order_progress += 1


## Доклад командиру. Выдаёт первый приказ, принимает выполненный и платит.
## Возвращает текст для лога — панель обновится по реплицированным числам.
func report(guard: Node3D) -> String:
	if not multiplayer.is_server():
		return ""
	if not in_range(guard.global_position):
		return ""

	if guard.order_kind < 0:
		return _issue_next(guard)

	if guard.order_progress < ORDERS.target_of(guard.order_kind):
		return "Приказ не выполнен: %s" % ORDERS.progress_text(guard.order_kind, guard.order_progress)

	var reward: Array = ORDERS.reward_of(guard.order_kind)
	for i in reward.size():
		if int(reward[i]) > 0:
			guard.stock.add(i, int(reward[i]))
	guard.orders_done += 1
	var done_name := ORDERS.name_of(guard.order_kind)
	_clear_order(guard)
	var next := _issue_next(guard)
	return "Приказ «%s» выполнен. %s" % [done_name, next]


## Приказы идут по кругу в фиксированном порядке. Сюжетной цепочки в GDD нет,
## а бесконечная выдача даёт страже занятие после обороны — см. открытый вопрос
## в README.
func _issue_next(guard: Node3D) -> String:
	var kind: int = int(guard.orders_done) % ORDERS.COUNT
	guard.order_kind = kind
	guard.order_progress = 0
	guard.set_meta("hold_seconds", 0.0)
	var text := "Новый приказ: %s" % ORDERS.name_of(kind)
	_notify(guard, text)
	return text


func _clear_order(guard: Node3D) -> void:
	guard.order_kind = -1
	guard.order_progress = 0
	guard.set_meta("hold_seconds", 0.0)


func _notify(guard: Node3D, text: String) -> void:
	print("[командир] игроку %d: %s" % [int(guard.peer_id), text])
	var objective: Node3D = get_parent().get_node_or_null("Objective")
	if objective == null:
		return
	# rpc_id самому себе Godot запрещает: если страж — это хост, объявляем
	# напрямую.
	if int(guard.peer_id) == 1:
		objective.announced.emit(text)
	else:
		objective.announce.rpc_id(int(guard.peer_id), text)
