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
## РАСПОРЯДИТЕЛЬ УБИВАЕМ. Раньше он был голой сеткой без коллизии: удары и
## огненные шары пролетали насквозь, и живой тестер разумно решил, что это баг.
## Теперь его тело — обычный боец (`unit.gd`) в варианте «чемпион»: у него есть
## здоровье, зоны попадания, кровь и смерть, и дерётся он тем же кодом, что все
## остальные. Отдельной боевой логики здесь нет намеренно — дублировать бой
## ради одного NPC значило бы завести вторую, непроверенную его версию.
##
## Убить его — осмысленная цель для злодея и эльфов: пока он лежит, стража не
## получает приказов и не может повысить своего до командира. Но в одиночку
## это не размен, а самоубийство, см. CHAMPION_* в `unit.gd`.
##
## Смерть у него НЕ окончательная: через RESPAWN_DELAY он снова встаёт на пост.
## Окончательно гибнут только вожаки — злодей и командир стражи, — а
## распорядитель вожаком не является: через него идёт вся арка кампании стражи,
## и вырезав его насовсем, злодей на первой минуте закрывал бы чужой стороне
## всю ветку до конца партии.
##

const ORDERS := preload("res://scripts/orders.gd")
const FACTIONS := preload("res://scripts/factions.gd")
## Где стоит: во дворе дворца, в стороне от точки спавна стражи.
const POSITION := Vector3(270.0, 6.0, -235.0)

## Через сколько секунд после гибели распорядитель снова встаёт на пост.
## Три минуты — это налёт с последствиями, а не выключенная сторона: за это
## время стража успевает заметить потерю, но партию она не ломает.
const RESPAWN_DELAY := 180.0

## Зона, которую он обороняет. За неё за целью не идёт: он охраняет двор, а не
## воюет по карте, и стража должна знать, где его искать.
const LEASH := 45.0

## Живое тело распорядителя. Пока его нет — он пал и ещё не вернулся.
var _body: Node3D = null
var _respawn_left := 0.0


func _ready() -> void:
	position = POSITION
	_build_stand()


## Помост на посту. Он остаётся на месте, даже когда распорядитель пал или
## отошёл драться: по нему видно, куда он вернётся.
func _build_stand() -> void:
	var stand := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.0, 0.4, 3.0)
	stand.mesh = box
	stand.position = Vector3(0.0, 0.2, 0.0)
	var stand_mat := StandardMaterial3D.new()
	stand_mat.albedo_color = Color(0.72, 0.24, 0.22)
	stand.material_override = stand_mat
	add_child(stand)


## Поставить распорядителя на пост. Тело — обычный боец в варианте «чемпион»,
## поэтому спавнит его мир, а не мы: так оно реплицируется тем же каналом, что
## все остальные бойцы, и клиенту ничего специально знать не нужно.
func _spawn_body() -> void:
	if not Net.hosting():
		return
	var world := get_parent()
	if world == null or not world.has_method("spawn_garrison_unit"):
		return
	_body = world.spawn_garrison_unit(FACTIONS.Kind.GUARD, 2, POSITION, POSITION, LEASH, true)
	if _body != null and _body.has_signal("died_on_server"):
		_body.died_on_server.connect(_on_body_died)


func _on_body_died(_unit: Node3D) -> void:
	_body = null
	_respawn_left = RESPAWN_DELAY
	print("[распорядитель] пал, вернётся через %d с" % int(RESPAWN_DELAY))
	_announce("Распорядитель стражи пал. Приказы и повышение недоступны.")


## Стоит ли распорядитель на посту. Пока он лежит, говорить не с кем.
func on_duty() -> bool:
	return _body != null and is_instance_valid(_body)


## Сколько секунд до его возвращения. Ноль — если он на посту.
func respawn_left() -> float:
	return 0.0 if on_duty() else _respawn_left


## Стоит ли игрок достаточно близко, чтобы говорить. Клиент считает это же
## значение для подсказки, но решает всё равно хост.
func in_range(point: Vector3) -> bool:
	# Считаем до ЖИВОГО тела, а не до поста: распорядитель отходит драться и
	# возвращается, и говорить надо с ним, а не с пустым помостом.
	if not on_duty():
		return false
	var here: Vector3 = _body.global_position
	var flat := Vector3(point.x, here.y, point.z)
	return flat.distance_to(here) <= ORDERS.TALK_RANGE


# --- логика хоста ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not Net.hosting():
		return
	_tick_body(delta)
	for guard in _guards():
		_tick_order(guard, delta)


## Поставить распорядителя на пост, если его там нет. Первый раз — на старте
## партии, дальше — после гибели, выждав RESPAWN_DELAY.
func _tick_body(delta: float) -> void:
	if on_duty():
		return
	if _body != null:
		# Ссылка есть, но нода уже уничтожена: считаем это гибелью.
		_on_body_died(null)
		return
	if _respawn_left > 0.0:
		_respawn_left -= delta
		if _respawn_left > 0.0:
			return
		_announce("Распорядитель стражи вернулся на пост.")
	_spawn_body()


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
	if not Net.hosting():
		return
	if victim_faction != FACTIONS.Kind.VILLAIN:
		return
	for guard in _guards():
		if int(guard.peer_id) != killer_id:
			continue
		if guard.order_kind == ORDERS.Kind.SLAY:
			guard.order_progress += 1


## Решающий удар засчитывается только за ЛИЧНОЕ убийство самого злодея, а не за
## любого убитого на его стороне: в этом весь смысл «убей его сам».
func report_leader_kill(killer_id: int, victim_faction: int) -> void:
	if not Net.hosting():
		return
	if victim_faction != FACTIONS.Kind.VILLAIN:
		return
	for guard in _guards():
		if int(guard.peer_id) != killer_id:
			continue
		if guard.order_kind == ORDERS.Kind.FINAL:
			guard.order_progress = ORDERS.target_of(ORDERS.Kind.FINAL)


## Страж погиб. Решающий удар при этом проваливается: приказ снимается, а порог
## поднимается — служи дальше и заслужи снова (GDD раздел 8).
##
## Обычные приказы гибель не отменяет: провалить дежурство смертью было бы
## наказанием на пустом месте.
func report_guard_death(guard: Node3D) -> void:
	if not Net.hosting() or guard == null:
		return
	if guard.order_kind != ORDERS.Kind.FINAL:
		return
	if guard.order_progress >= ORDERS.target_of(ORDERS.Kind.FINAL):
		return
	guard.final_threshold = int(guard.orders_done) + ORDERS.ORDERS_FOR_FINAL
	_clear_order(guard)
	_notify(guard, "Последний бой провален. Служи дальше и заслужи снова.")


func report_caravan_destroyed(killer_id: int, owner_faction: int) -> void:
	if not Net.hosting():
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
	if not Net.hosting():
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


## Обычные приказы идут по кругу; когда служба дослужена до порога — вместо
## очередного выдаётся РЕШАЮЩИЙ УДАР (GDD раздел 8).
##
## Это и есть вся «арка»: служи → заслужи право на последний бой → финал.
## Сюжета и диалогов здесь нет намеренно — форма кампании выражена через то,
## что уже работает, тем же принципом, что и сами приказы.
func _issue_next(guard: Node3D) -> String:
	var kind: int = ORDERS.Kind.FINAL if _final_available(guard) else int(guard.orders_done) % ORDERS.COUNT
	guard.order_kind = kind
	guard.order_progress = 0
	guard.set_meta("hold_seconds", 0.0)
	var text := "Новый приказ: %s" % ORDERS.name_of(kind)
	_notify(guard, text)
	return text


## Готов ли страж к решающему удару.
##
## Предлагать его после гибели злодея бессмысленно — убивать уже некого, и
## служба возвращается в обычный круг.
func _final_available(guard: Node3D) -> bool:
	if int(guard.orders_done) < int(guard.final_threshold):
		return false
	var objective: Node3D = get_parent().get_node_or_null("Objective")
	if objective == null:
		return false
	return not objective.leader_is_down(FACTIONS.Kind.VILLAIN)


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


## Объявить всем. Гибель распорядителя и его возвращение касаются не только
## стражи: для злодея и эльфов это результат налёта, и знать о нём они должны.
func _announce(text: String) -> void:
	var objective: Node3D = get_parent().get_node_or_null("Objective")
	if objective == null:
		return
	objective.announce.rpc(text)


# --- повышение до командира стражи -----------------------------------------

## Есть ли у стражи живой командир прямо сейчас.
## Мёртвый не считается: его смерть окончательна, и место освобождается.
func guard_has_leader() -> bool:
	for guard in _guards():
		if guard.is_leader and guard.health.alive:
			return true
	return false


## Можно ли этому стражу принять командование.
## Клиент считает то же самое для кнопки, решает всё равно хост.
func can_promote(guard: Node3D) -> bool:
	if guard == null or int(guard.faction) != FACTIONS.Kind.GUARD:
		return false
	if not on_duty():
		return false
	if not guard.health.alive or guard.is_leader:
		return false
	return not guard_has_leader()


## Принять командование. Пока это простое согласие NPC; по замыслу здесь будет
## цепочка квестов, и повышение станет её наградой.
##
## Вместе с командованием страж получает стратегический режим, стройку и наём
## (GDD раздел 2.2) — и окончательную смерть: командир не возрождается.
func promote(guard: Node3D) -> String:
	if not Net.hosting():
		return ""
	if not in_range(guard.global_position):
		return ""
	if not can_promote(guard):
		return "Командовать сейчас некому и незачем."
	guard.is_leader = true
	var text := "Страж %d принял командование" % int(guard.peer_id)
	print("[командир] %s" % text)
	var objective: Node3D = get_parent().get_node_or_null("Objective")
	if objective != null:
		objective.announce.rpc(text)
	return text
