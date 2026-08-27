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

const SPEED := 8.0
const MAX_HEALTH := 220.0
## Сколько единиц каждого ресурса увозит за раз.
const CAPACITY := 120
const LOAD_SECONDS := 3.0
## На каком расстоянии считаем точку маршрута пройденной.
const WAYPOINT_REACH := 3.0
## Насколько близко надо подъехать к шахте и складу.
const DOCK_RANGE := 14.0

signal destroyed(point: Vector3, cargo: PackedInt32Array, killer_id: int)

## Реплицируемое состояние.
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var state: int = State.TO_MINE
@export var health: float = MAX_HEALTH
@export var cargo: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])

var owner_id := 1
## Сторона каравана. Владельца может не быть вовсе — караван ИИ принадлежит
## СТОРОНЕ, как батраки и гарнизон, — а разгружаться и портить отношения он
## обязан одинаково с игроцким.
var faction := 0
var route: PackedVector3Array = PackedVector3Array()

var _leg := 0
var _timer := 0.0
var _zone: Area3D
var _alive := true


## Вызывается спавнером на всех пирах с одинаковыми данными.
func setup(data: Dictionary) -> void:
	owner_id = int(data["owner"])
	faction = int(data.get("faction", 0))
	route = data["route"]
	position = route[0] if route.size() > 0 else Vector3.ZERO
	sync_position = position


func _ready() -> void:
	_build_visual()
	_build_hit_zone()


func _build_visual() -> void:
	var cart := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.6, 2.0, 4.4)
	cart.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.32, 0.20)
	cart.mesh.material = mat
	cart.position = Vector3(0.0, 1.2, 0.0)
	add_child(cart)

	var cover := MeshInstance3D.new()
	var top := BoxMesh.new()
	top.size = Vector3(2.8, 0.5, 4.6)
	cover.mesh = top
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = Color(0.72, 0.70, 0.62)
	cover.mesh.material = top_mat
	cover.position = Vector3(0.0, 2.4, 0.0)
	add_child(cover)


## Зона попадания, чтобы по каравану можно было бить тем же оружием, что и по
## людям. hit_zone ищет владельца по методу take_damage — он ниже.
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
			queue_free()

	sync_position = position
	sync_yaw = rotation.y


## Проехать очередной отрезок маршрута. true — маршрут пройден до конца.
## backwards: обратный путь идёт по тем же точкам в обратном порядке.
func _advance(delta: float, backwards: bool) -> bool:
	if route.size() < 2:
		return true
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
	position += dir * SPEED * delta
	# Высоту подтягиваем плавно: резкий скачок на спуске выглядит как телепорт.
	position.y = lerpf(position.y, target.y, clampf(delta * 4.0, 0.0, 1.0))
	rotation.y = atan2(-dir.x, -dir.z)
	return false


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
func take_damage(amount: float, attacker_id: int, _zone_name: String, point: Vector3, dir: Vector3, _aoe := false) -> void:
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
