extends Node3D
##
## Постройка форта (Этап 4, GDD раздел 2.3): склад и казарма.
##
## Стройку ведёт ТОЛЬКО хост: он же принял решение, что место годное и ресурсы
## списаны. Клиенты получают тип, владельца и прогресс и просто рисуют.
##
## Склад по GDD — «главное здание, оно же склад и пункт приёма ресурсов»:
## достроившись, он поднимает потолок хранения владельцу. Приём от каравана
## встанет сюда же на Этапе 5.
##

const RES := preload("res://scripts/economy/resources.gd")
const HIT_ZONE := preload("res://scripts/combat/hit_zone.gd")
const EFFECTS := preload("res://scripts/combat/effects.gd")

## Запас прочности постройки. Разрушить её должно быть заметным делом, а не
## случайным попаданием: казарма стражи — условие её поражения (GDD раздел 7).
const MAX_HEALTH := 600.0
const HITBOX_LAYER := 4

## Достроено (на любом пире, после репликации).
signal completed
## Разрушено. Эмитится ТОЛЬКО на хосте — он решает судьбу постройки.
signal destroyed_on_server(building: Node3D, killer_id: int)

## Реплицируемое состояние.
@export var progress: float = 0.0
@export var health: float = MAX_HEALTH

var kind := 0
var owner_id := 1
var faction := 0

var _mesh: MeshInstance3D
var _done := false


## Вызывается спавнером на всех пирах с одинаковыми данными.
func setup(data: Dictionary) -> void:
	kind = int(data["kind"])
	owner_id = int(data["owner"])
	# Постройка принадлежит СТОРОНЕ, а не человеку: казарма стражи во дворце
	# стоит с начала партии и переживает уход любого конкретного игрока.
	faction = int(data.get("faction", 0))
	if bool(data.get("prebuilt", false)):
		progress = 1.0
	position = data["point"]
	rotation.y = float(data.get("yaw", 0.0))


func _ready() -> void:
	var size: Vector3 = RES.BUILDING_SIZE[kind]

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(shape)
	add_child(body)
	add_to_group("building")

	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	_mesh.mesh = box
	_mesh.material_override = _material()
	add_child(_mesh)
	_build_hit_zone(size)
	_apply_progress()


## Зона попадания на всю коробку: по постройке бьют мечом, стрелой и шаром так
## же, как по бойцу, отдельного режима осады нет.
func _build_hit_zone(size: Vector3) -> void:
	var zone := Area3D.new()
	zone.set_script(HIT_ZONE)
	zone.zone = "building"
	zone.damage_multiplier = 1.0
	zone.collision_layer = HITBOX_LAYER
	zone.collision_mask = 0
	zone.monitoring = false
	zone.position = Vector3(0.0, size.y * 0.5, 0.0)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	zone.add_child(shape)
	add_child(zone)


## Принять урон. Только на хосте — как и весь остальной урон в игре.
##
## Недостроенное здание бьётся так же: это и есть способ сорвать стройку.
func take_damage(amount: float, attacker_id: int, _zone: String, point: Vector3, dir: Vector3, _aoe := false) -> void:
	if not Net.hosting() or health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	show_hit.rpc(point, dir, amount)
	if health > 0.0:
		return
	print("[стройка] %s игрока %d разрушена игроком %d" % [label(), owner_id, attacker_id])
	destroyed_on_server.emit(self, attacker_id)
	queue_free()


@rpc("any_peer", "call_local", "unreliable")
func show_hit(point: Vector3, _dir: Vector3, _amount: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	# Щепки цветом дерева: крови у постройки нет.
	EFFECTS.chips(get_parent().get_parent(), point, RES.Kind.WOOD)


func _material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.30, 0.19) if kind == RES.Building.STORAGE else Color(0.34, 0.33, 0.36)
	mat.roughness = 0.9
	return mat


func _process(delta: float) -> void:
	if Net.hosting() and progress < 1.0:
		progress = minf(1.0, progress + delta * _build_rate() / float(RES.BUILD_TIME[kind]))
	_apply_progress()
	if progress >= 1.0 and not _done:
		_done = true
		Sfx.at(Sfx.Kind.BUILD_DONE, global_position, 3.0)
		completed.emit()


## Во сколько раз быстрее идёт стройка. Каждый приставленный строитель добавляет
## свою долю к базовой скорости.
##
## Базовая единица — это сам хозяин стройки: постройка возводится и без батраков,
## иначе первая же партия вставала бы намертво (батраков нанимают за золото, а
## золото добывают батраки). Строители не заменяют её, а ускоряют: двое дают
## тройную скорость.
func _build_rate() -> float:
	var rate := 1.0
	for node in get_tree().get_nodes_in_group("unit"):
		if not is_instance_valid(node) or not node.has_method("builds"):
			continue
		if int(node.faction) != faction:
			continue
		if node.builds(self):
			rate += 1.0
	return rate


## Пока строится — коробка растёт из земли и просвечивает.
func _apply_progress() -> void:
	if _mesh == null:
		return
	var size: Vector3 = RES.BUILDING_SIZE[kind]
	var grown: float = maxf(0.05, progress)
	_mesh.scale = Vector3(1.0, grown, 1.0)
	_mesh.position = Vector3(0.0, size.y * grown * 0.5, 0.0)

	var mat: StandardMaterial3D = _mesh.material_override
	if mat == null:
		return
	if progress < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.55
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color.a = 1.0


func label() -> String:
	return RES.BUILDING_NAMES[clampi(kind, 0, RES.BUILDING_NAMES.size() - 1)]
