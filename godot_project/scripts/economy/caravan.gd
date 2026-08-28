extends Node3D
##
## Караван (Этап 5, GDD раздел 2.3 и 8.2).
##
## Маршрут игрок рисует сам — жёстко зашитой дороги нет. Караван едет по
## нарисованным точкам до шахты, грузится и возвращается тем же путём на склад.
##
## Всё считает ТОЛЬКО хост: движение, погрузку, разгрузку и урон. Клиенты
## получают позицию, состояние и здоровье и просто рисуют. Караван по GDD —
## «уязвимая цель для эльфов-партизан», поэтому у него есть зона попадания и
## здоровье, а разбитый караван высыпает груз на землю (DESIGN_ANSWERS, п. 15).
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const HIT_ZONE := preload("res://scripts/combat/hit_zone.gd")
const EFFECTS := preload("res://scripts/combat/effects.gd")

enum State { TO_MINE, LOADING, TO_HOME, UNLOADING, FINISHED }

## Скорость ПУСТОЙ упряжки в одну лошадь. Настоящая скорость считается от числа
## лошадей: `speed_now()`.
const SPEED := 8.0

## Сколько лошадей можно запрячь. Одна тянет медленно, шесть — предел упряжки.
const HORSES_MIN := 1
const HORSES_MAX := 6

## Прибавка за каждую лошадь сверх первой. Не линейно к числу: шестёрка втрое
## быстрее одиночки, а не вшестеро — иначе обоз с полной упряжкой обгоняет
## всадника, и догнать его нельзя в принципе.
const HORSE_SPEED_STEP := 0.4

## Здоровье одной лошади в упряжке. Убить всех — обоз встал.
const HORSE_HEALTH := 60.0

## Насколько близко должен подойти враг, чтобы возница остановил обоз.
##
## Обоз, который продолжает ехать, пока за ним бегут, догнать нельзя вовсе: он
## быстрее пешего. Раньше так и было — пять минут погони и ни одного перехвата.
## Теперь враг рядом означает остановку: дальше решают оружием.
const HALT_RANGE := 18.0
const MAX_HEALTH := 220.0
## Сколько единиц каждого ресурса увозит за раз.
const CAPACITY := 120
const LOAD_SECONDS := 3.0
## На каком расстоянии считаем точку маршрута пройденной.
const WAYPOINT_REACH := 3.0
## Насколько близко надо подъехать к шахте и складу.
const DOCK_RANGE := 14.0

## Поводок охраны вокруг повозки.
const GUARD_LEASH := 16.0

signal destroyed(point: Vector3, cargo: PackedInt32Array, killer_id: int)
## Обоз доехал целым: столько лошадей вернулось в конюшню.
##
## Отдельно от `destroyed`: разбитый обоз лошадей не возвращает — их либо убили,
## либо увели, и это решается на месте, а не при разгрузке.
signal came_home(horses: int)

## Реплицируемое состояние.
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var state: int = State.TO_MINE
@export var health: float = MAX_HEALTH
@export var cargo: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## Сколько лошадей в упряжке и сколько здоровья у них осталось общим счётом.
@export var horses := 2
@export var horse_pool := 120.0
## Обоз стоит: лошадей нет или рядом враг.
@export var halted := false

var owner_id := 1
## Сторона каравана. Владельца может не быть вовсе — караван ИИ принадлежит
## СТОРОНЕ, как батраки и гарнизон, — а разгружаться и портить отношения он
## обязан одинаково с игроцким.
var faction := 0
var route: PackedVector3Array = PackedVector3Array()

## Охрана: кто едет вместе с повозкой (GDD, решение по ходу шага 8).
##
## Второй системы командования не заводим. У бойца уже есть ДОМ и поводок вокруг
## него: пока он никого не бьёт, он возвращается домой, а врага в пределах
## поводка принимает. Значит охране достаточно двигать её дом вместе с повозкой —
## и она сама идёт рядом, сама вступает в бой и сама возвращается в строй.
var escort: Array[Node3D] = []

var _leg := 0
var _timer := 0.0
var _zone: Area3D
var _alive := true
## Кладь поверх телеги: по ней снаружи видно, полон обоз или пуст.
var _load_mesh: MeshInstance3D = null
## Нарисованные лошади упряжки: их число меняется, когда лошадей убивают.
var _harness: Array[MeshInstance3D] = []


## Вызывается спавнером на всех пирах с одинаковыми данными.
func setup(data: Dictionary) -> void:
	owner_id = int(data["owner"])
	faction = int(data.get("faction", 0))
	route = data["route"]
	horses = clampi(int(data.get("horses", 2)), HORSES_MIN, HORSES_MAX)
	horse_pool = HORSE_HEALTH * float(horses)
	position = route[0] if route.size() > 0 else Vector3.ZERO
	sync_position = position


func _ready() -> void:
	_build_visual()
	_build_hit_zone()
	_build_harness_zone()


## Модель телеги: Kenney Fantasy Town Kit, лицензия CC0 (LICENSE.txt рядом).
const CART_MODEL := preload("res://assets/props/cart.glb")

## Модель длиной около полутора метров — приводим к нашей телеге в четыре с
## лишним.
const CART_SCALE := 2.6


func _build_visual() -> void:
	# Телега — модель, а не коробка. Коллизия и зоны попадания остаются своими:
	# брать их из модели значит получить форму со спицами колёс, вокруг которой
	# бойцы будут ходить кругами.
	var cart: Node3D = CART_MODEL.instantiate()
	cart.scale = Vector3(CART_SCALE, CART_SCALE, CART_SCALE)
	cart.position = Vector3(0.0, 0.0, 0.0)
	add_child(cart)

	# ГРУЗ ВИДЕН СНАРУЖИ. Пустой и полный обоз выглядели одинаково, и понять,
	# стоит ли на него нападать, было нельзя ничем, кроме подхода вплотную.
	# Теперь поверх телеги растёт кладь: чем больше везёт, тем выше.
	_load_mesh = MeshInstance3D.new()
	var load_box := BoxMesh.new()
	load_box.size = Vector3(2.2, 1.0, 3.8)
	_load_mesh.mesh = load_box
	var load_mat := StandardMaterial3D.new()
	load_mat.albedo_color = Color(0.55, 0.44, 0.26)
	_load_mesh.mesh.material = load_mat
	_load_mesh.position = Vector3(0.0, 2.2, 0.0)
	_load_mesh.visible = false
	add_child(_load_mesh)

	# УПРЯЖКА. Телега не катится сама: её тянет пара лошадей. Пока обоз цел, они
	# нарисованы прямо на нём — отдельными телами их пришлось бы вести по карте
	# вместе с повозкой, то есть завести четвёртую систему движения. Настоящими
	# лошадьми они становятся ровно тогда, когда телегу разбили.
	_rebuild_harness()


## Зона попадания, чтобы по каравану можно было бить тем же оружием, что и по
## людям. hit_zone ищет владельца по методу take_damage — он ниже.
## Две зоны попадания, а не одна: телега и упряжка.
##
## Это два разных способа остановить обоз, и стоить они должны разного. Выбить
## лошадей проще — у них меньше здоровья, — но груз остаётся в целой телеге, и
## его надо ещё забрать. Разбить телегу дороже, зато груз сразу сыплется на
## землю. Без раздельных зон выбора нет вовсе: бьёшь «в обоз» и получаешь одно.
func _build_hit_zone() -> void:
	_zone = Area3D.new()
	_zone.set_script(HIT_ZONE)
	_zone.zone = "cargo"
	_zone.damage_multiplier = 1.0
	_zone.collision_layer = 4
	_zone.collision_mask = 0
	_zone.monitoring = false
	_zone.position = Vector3(0.0, 1.4, 0.0)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.8, 2.8, 4.6)
	shape.shape = box
	_zone.add_child(shape)
	add_child(_zone)


## Зона упряжки: по ней бьют, чтобы выбить лошадей.
func _build_harness_zone() -> void:
	var zone := HIT_ZONE.new()
	zone.zone = "harness"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Накрывает все шесть возможных мест упряжки: рисуется столько лошадей,
	# сколько их есть, а зона одна и не перестраивается.
	box.size = Vector3(3.0, 2.4, 9.0)
	shape.shape = box
	shape.position = Vector3(0.0, 1.3, -6.0)
	zone.add_child(shape)
	add_child(zone)


func _physics_process(delta: float) -> void:
	if not Net.hosting():
		# Клиент только сглаживает присланное.
		position = position.lerp(sync_position, clampf(delta * 12.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, sync_yaw, clampf(delta * 8.0, 0.0, 1.0))
		return

	match state:
		State.TO_MINE:
			if _advance(delta, false):
				state = State.LOADING
				_timer = LOAD_SECONDS
		State.LOADING:
			_timer -= delta
			if _timer <= 0.0:
				_load_at_mine()
				state = State.TO_HOME
		State.TO_HOME:
			if _advance(delta, true):
				state = State.UNLOADING
				_timer = LOAD_SECONDS
		State.UNLOADING:
			_timer -= delta
			if _timer <= 0.0:
				_unload_at_home()
				state = State.FINISHED
		State.FINISHED:
			_release_escort()
			# Лошади возвращаются в конюшню и снова считаются свободными: их можно
			# запрячь в следующий обоз или оседлать.
			if horses > 0:
				came_home.emit(horses)
			queue_free()

	_lead_escort()
	_show_cargo()
	_update_halt()
	sync_position = position
	sync_yaw = rotation.y


## Проехать очередной отрезок маршрута. true — маршрут пройден до конца.
## backwards: обратный путь идёт по тем же точкам в обратном порядке.
func _advance(delta: float, backwards: bool) -> bool:
	if route.size() < 2:
		return true
	# Стоящий обоз никуда не едет и точку маршрута не проходит.
	if halted:
		return false
	var index: int = (route.size() - 1 - _leg) if backwards else _leg
	index = clampi(index, 0, route.size() - 1)
	var target: Vector3 = route[index]

	# Расстояние до точки меряем ПО ГОРИЗОНТАЛИ, а идём в трёх измерениях: точки
	# маршрута теперь лежат на земле (их даёт навигация), и караван обязан за ней
	# следовать, а не висеть на высоте, с которой выехал.
	var flat_target := Vector3(target.x, position.y, target.z)
	var to_target := flat_target - position
	if to_target.length() <= WAYPOINT_REACH:
		_leg += 1
		if _leg >= route.size():
			_leg = 0
			return true
		return false

	var dir := to_target.normalized()
	position += dir * speed_now() * delta
	# Высоту подтягиваем плавно: резкий скачок на спуске выглядит как телепорт.
	position.y = lerpf(position.y, target.y, clampf(delta * 4.0, 0.0, 1.0))
	rotation.y = atan2(-dir.x, -dir.z)
	return false


## Скорость обоза сейчас: от числа живых лошадей.
##
## Не линейно к их числу. Шестёрка втрое быстрее одиночки, а не вшестеро: иначе
## полная упряжка обгоняет всадника, и перехватить обоз нельзя в принципе,
## сколько ни считай точку встречи.
func speed_now() -> float:
	if horses <= 0:
		return 0.0
	return SPEED * (1.0 + HORSE_SPEED_STEP * float(horses - 1))


## Стоит ли обоз. Стоит, если лошадей не осталось или рядом враг.
##
## Возница, который продолжает ехать, пока за ним бегут, — это обоз, который
## нельзя догнать: он быстрее пешего. Пять минут варки и ни одного перехвата
## были ровно про это. Теперь враг рядом означает остановку, а дальше решают
## оружием: убить лошадей или захватить их живыми.
func _update_halt() -> void:
	if horses <= 0:
		halted = true
		return
	halted = _enemy_near()


func _enemy_near() -> bool:
	var world := _world()
	if world == null:
		return false
	var diplomacy: Node = world.get_node_or_null("Diplomacy")
	var players: Node = world.get_node_or_null("Players")
	if players != null:
		for child in players.get_children():
			if _hostile_to(child, diplomacy) and _flat_gap(child) <= HALT_RANGE:
				return true
	for unit in get_tree().get_nodes_in_group("unit"):
		if _hostile_to(unit, diplomacy) and _flat_gap(unit) <= HALT_RANGE:
			return true
	return false


## Чужой ли. Своя охрана рядом стоять обязана, и останавливаться из-за неё обоз
## не должен — иначе он не тронется с места вовсе.
func _hostile_to(node: Node, diplomacy: Node) -> bool:
	if node == null or not is_instance_valid(node) or not ("faction" in node):
		return false
	var other := int(node.faction)
	if other == faction:
		return false
	if "health" in node:
		var hp = node.health
		if hp is float or hp is int:
			if float(hp) <= 0.0:
				return false
		elif hp != null and not hp.alive:
			return false
	if diplomacy != null and diplomacy.has_method("value_of"):
		# Перемирие уважаем: с кем не воюем, от того и не убегаем.
		return float(diplomacy.value_of(faction, other)) <= 20.0
	return true


func _flat_gap(node: Node) -> float:
	var body := node as Node3D
	if body == null:
		return INF
	return Vector2(position.x, position.z).distance_to(
		Vector2(body.global_position.x, body.global_position.z))


## Показать груз снаружи: чем полнее обоз, тем выше кладь.
##
## Обновляем на каждом пире по значению `cargo` — оно реплицируется само, и
## отдельной синхронизации ради внешнего вида заводить незачем.
func _show_cargo() -> void:
	if _load_mesh == null:
		return
	var total := 0
	for kind in RES.COUNT:
		total += cargo[kind]
	var share: float = clampf(float(total) / float(CAPACITY), 0.0, 1.0)
	_load_mesh.visible = share > 0.02
	# Растёт вверх от дна телеги: иначе полупустой обоз выглядит как ящик,
	# утопленный в повозку.
	_load_mesh.scale = Vector3(1.0, maxf(0.08, share), 1.0)
	_load_mesh.position = Vector3(0.0, 1.9 + share * 0.5, 0.0)


## Приставить бойца к повозке. Возвращает false, если приставлять некого.
func add_guard(unit: Node3D) -> bool:
	if unit == null or not is_instance_valid(unit) or not ("home" in unit):
		return false
	if escort.has(unit):
		return false
	escort.append(unit)
	unit.home = position
	# Метка нужна хозяйству: батрака в охране нельзя переставлять обратно на
	# добычу, иначе он уходит рубить лес прямо из-под обоза. Первый прогон это и
	# показал: охрана назначалась, а через такт её роль откатывали.
	unit.set_meta("escorting", true)
	# Поводок делаем коротким: охрана обязана держаться повозки, а не убегать за
	# первым встречным. Длинный поводок превращает охрану в отдельный отряд,
	# который уходит драться и оставляет груз без прикрытия.
	unit.leash = GUARD_LEASH
	return true


## Сколько живых охранников осталось.
func guards() -> int:
	var alive := 0
	for unit in escort:
		if is_instance_valid(unit):
			alive += 1
	return alive


## Вести охрану за собой: двигаем её дом вместе с повозкой.
## Отпустить охрану: повозка доехала или разбита.
func _release_escort() -> void:
	for unit in escort:
		if is_instance_valid(unit):
			unit.remove_meta("escorting")
	escort.clear()


func _lead_escort() -> void:
	if escort.is_empty():
		return
	var kept: Array[Node3D] = []
	for unit in escort:
		if not is_instance_valid(unit):
			continue
		unit.home = position
		kept.append(unit)
	escort = kept


## Куда караван поедет ДАЛЬШЕ: оставшиеся точки в порядке движения, вместе с
## обратной дорогой домой.
##
## Нужно перехватчику. Гнаться за текущим положением каравана бесполезно: он
## быстрее пешего отряда (8 против 5.2) и просто уезжает — пять минут варки,
## три набега эльфов в зону злодея и ни одного перехвата. Догнать нельзя, а
## ВСТРЕТИТЬ можно, и для этого надо знать, где он будет.
##
## Обратную дорогу включаем не для полноты: именно она и перехватывается. Пока
## отряд идёт наперерез, караван успевает добраться до шахты, и единственное
## место, где его реально встретить, — на пути домой.
func path_ahead() -> PackedVector3Array:
	var ahead := PackedVector3Array()
	if route.size() < 2:
		return ahead
	match state:
		State.TO_MINE:
			for i in range(clampi(_leg, 0, route.size() - 1), route.size()):
				ahead.append(route[i])
			for i in range(route.size() - 2, -1, -1):
				ahead.append(route[i])
		State.LOADING:
			# Стоит на шахте: дальше только домой.
			for i in range(route.size() - 1, -1, -1):
				ahead.append(route[i])
		State.TO_HOME:
			for i in range(clampi(route.size() - 1 - _leg, 0, route.size() - 1), -1, -1):
				ahead.append(route[i])
		_:
			pass
	return ahead


func _load_at_mine() -> void:
	var mine := _world().get_node_or_null("Mine")
	if mine == null:
		return
	cargo = mine.take(CAPACITY)
	print("[караван] загружен на шахте: %s" % _cargo_text())


func _unload_at_home() -> void:
	# Разгружаемся в казну СТОРОНЫ, а не владельцу-персонажу. Искать владельца
	# среди игроков значит не заметить караван ИИ: у него владельца нет вовсе, и
	# он привозил груз в никуда — молча, как когда-то батраки и склад ИИ.
	var treasury: Node = _world().get_node_or_null("Treasury")
	if treasury == null:
		return
	var wallet: Node = treasury.of(faction)
	if wallet == null:
		return
	var delivered := 0
	for kind in RES.COUNT:
		# Караван разгружается СРАЗУ В СКЛАД: он для того и едет, а не чтобы
		# набить карманы игроку (GDD раздел 2.3).
		delivered += wallet.add_stored(kind, cargo[kind])
	print("[караван] доставлено стороне «%s»: %d единиц"
		% [FACTIONS.name_of(faction), delivered])
	cargo = PackedInt32Array([0, 0, 0, 0])


## Принять урон. Вызывается ТОЛЬКО хостом — так же, как у персонажей.
## Ударить по УПРЯЖКЕ. Лошади гибнут поштучно, и с каждой обоз едет медленнее.
##
## Отдельно от урона по телеге: разбить повозку и выбить лошадей — два разных
## способа остановить обоз, и они должны стоить разного. Убить лошадей проще
## (у них меньше здоровья), но груз при этом остаётся в целой телеге и его надо
## ещё забрать; разбить телегу дороже, зато груз сразу сыплется на землю.
func hurt_harness(amount: float, point: Vector3, dir: Vector3) -> void:
	if not Net.hosting() or horses <= 0:
		return
	horse_pool = maxf(0.0, horse_pool - amount)
	show_hit.rpc(point, dir, amount)
	var left: int = int(ceil(horse_pool / HORSE_HEALTH))
	if left < horses:
		horses = maxi(0, left)
		print("[караван] лошадей в упряжке осталось %d" % horses)
		_rebuild_harness()
	if horses <= 0:
		halted = true


## Захватить лошадей ЖИВЫМИ.
##
## Второй способ остановить обоз и единственный, после которого лошади кому-то
## достаются. Возвращает, сколько увели; ноль — брать нечего.
##
## Захват возможен только у СТОЯЩЕГО обоза: на ходу лошадей не выпрягают.
func capture_horses() -> int:
	if not Net.hosting() or horses <= 0 or not halted:
		return 0
	var taken := horses
	horses = 0
	horse_pool = 0.0
	halted = true
	_rebuild_harness()
	print("[караван] лошадей уведено: %d" % taken)
	return taken


## Перерисовать упряжку под текущее число лошадей.
func _rebuild_harness() -> void:
	for node in _harness:
		if is_instance_valid(node):
			node.queue_free()
	_harness.clear()
	for i in horses:
		var horse := MeshInstance3D.new()
		var hbox := BoxMesh.new()
		hbox.size = Vector3(1.0, 1.2, 2.4)
		horse.mesh = hbox
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color(0.36, 0.26, 0.18)
		horse.mesh.material = hmat
		# Пары в ряд, ряды вперёд: шестёрка встаёт тремя парами, как в жизни.
		var pair: int = i / 2
		var side: float = 1.0 if i % 2 == 0 else -1.0
		horse.position = Vector3(side * 1.0, 1.3, -3.6 - float(pair) * 2.6)
		add_child(horse)
		_harness.append(horse)


func take_damage(amount: float, attacker_id: int, _zone_name: String, point: Vector3, dir: Vector3, _aoe := false) -> void:
	# Попали в упряжку — страдают лошади, телега цела.
	if _zone_name == "harness":
		hurt_harness(amount, point, dir)
		return
	if not Net.hosting() or not _alive:
		return
	health = maxf(0.0, health - amount)
	show_hit.rpc(point, dir, amount)
	if health > 0.0:
		return
	_alive = false
	print("[караван] разбит игроком %d, груз высыпан: %s" % [attacker_id, _cargo_text()])
	destroyed.emit(global_position, cargo, attacker_id)
	queue_free()


@rpc("any_peer", "call_local", "unreliable")
func show_hit(point: Vector3, dir: Vector3, amount: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	EFFECTS.chips(_world(), point, RES.Kind.IRON)


func _world() -> Node3D:
	# Караван лежит в Spawned, а тот — в World.
	return get_parent().get_parent() as Node3D


func _cargo_text() -> String:
	var parts := PackedStringArray()
	for i in RES.COUNT:
		if cargo[i] > 0:
			parts.append("%s %d" % [RES.SHORT[i], cargo[i]])
	return ", ".join(parts) if parts.size() > 0 else "пусто"


func state_text() -> String:
	match state:
		State.TO_MINE: return "едет на шахту"
		State.LOADING: return "грузится"
		State.TO_HOME: return "везёт груз"
		State.UNLOADING: return "разгружается"
	return "прибыл"
