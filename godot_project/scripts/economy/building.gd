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
const LOOK := preload("res://scripts/economy/building_look.gd")
const TEXTURES := preload("res://scripts/textures.gd")

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
## Дом из модулей. Пока стройка идёт, его нет вовсе: растёт котлован-коробка.
var _look: Node3D
var _done := false
## Опора под домом уже поставлена. Считается один раз: земля под постройкой не
## меняется, а лучи стоят дорого.
var _footed := false


## Вызывается спавнером на всех пирах с одинаковыми данными.
func setup(data: Dictionary) -> void:
	kind = int(data["kind"])
	owner_id = int(data["owner"])
	# Постройка принадлежит СТОРОНЕ, а не человеку: казарма стражи во дворце
	# стоит с начала партии и переживает уход любого конкретного игрока.
	faction = int(data.get("faction", 0))
	if bool(data.get("prebuilt", false)):
		progress = 1.0
		# «Уже стояла» значит и «уже достроена»: последствия достройки за ней
		# числятся с прошлого раза. Без этого восстановленный из сейва склад
		# поднимал стороне потолок хранения ВТОРОЙ раз — а потолок мы и так
		# сохраняем, — и на старте партии играл звук готовой стройки.
		_done = true
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

	# Пока строится — коробка-каркас, растущая из земли. Дом появляется
	# готовым: стены, которые вылезают из-под земли по пояс, читаются как
	# ошибка, а не как стройка.
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	_mesh.mesh = box
	_mesh.material_override = _material()
	add_child(_mesh)

	_look = LOOK.build(kind, size)
	_look.visible = false
	add_child(_look)
	_build_hit_zone(size)
	_apply_progress()
	# Опору ставим НА СЛЕДУЮЩЕМ кадре физики, а не сейчас: лучи вниз ищут землю,
	# а физическое пространство в момент `_ready` ещё не знает ни о нас, ни, при
	# старте партии, о самой земле.
	_apply_footing.call_deferred()


## СВАИ И ПОДМОСТКИ: как дом стоит на склоне.
##
## Правило простое: пол ложится на САМУЮ ВЫСОКУЮ точку земли под основанием.
## Не на среднюю и не на точку клика — на высокую. Иначе угол дома уходит в
## холм по окна, и починить это уже нечем: землю под ним не срыть.
##
## Из этого следует всё остальное. Под низкими углами между полом и землёй
## остаётся зазор — туда встают СВАИ, столбы от земли до пола. А ко входу
## приставляется ПАНДУС: дом, приподнятый на полтора метра, без пандуса
## недоступен, и построить его значит построить сарай, в который не войти.
## Пандус — с коллизией, по нему действительно поднимаются.
##
## Считаем лучами по земле, а не по функции рельефа: под домом может оказаться
## не только холм, но и плато дворца, и стена форта, и мост. Луч знает про всё,
## формула — только про холмы.
func _apply_footing() -> void:
	if _footed or not is_inside_tree():
		return
	_footed = true
	var size: Vector3 = RES.BUILDING_SIZE[kind]
	var half_x: float = size.x * 0.5
	var half_z: float = size.z * 0.5
	var space := get_world_3d().direct_space_state
	if space == null:
		return

	# Пять точек: четыре угла и середина. Середина нужна на гребне холма, где
	# все четыре угла ниже центра и дом иначе повис бы на бугре.
	var probes := [
		Vector2(-half_x, -half_z), Vector2(half_x, -half_z),
		Vector2(half_x, half_z), Vector2(-half_x, half_z), Vector2.ZERO,
	]
	var ground := {}
	var top := -INF
	for probe in probes:
		var at: Vector2 = probe
		var from := global_position + Vector3(at.x, 60.0, at.y)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 120.0)
		query.collision_mask = 1
		# Себя из луча исключаем: собственная коробка стоит ровно тут же, и без
		# этого дом «нашёл бы землю» на собственной крыше.
		query.exclude = [_body_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue
		var y: float = hit["position"].y
		ground[at] = y
		top = maxf(top, y)
	if ground.is_empty() or top == -INF:
		return

	# Поднимаем дом до самой высокой точки. Опускать не даём: постройка, севшая
	# ниже точки, где её поставили, выглядит провалившейся.
	var lift: float = top - global_position.y
	if lift > 0.01:
		position.y += lift

	var footing := Node3D.new()
	footing.name = "Footing"
	add_child(footing)
	var deepest := 0.0
	for key in ground.keys():
		var at: Vector2 = key
		var drop: float = top - float(ground[key])
		deepest = maxf(deepest, drop)
		if drop < 0.25:
			continue
		_pile(footing, at, drop)
	if deepest >= 0.35:
		_ramp(footing, size, deepest)


## Свая: столб от земли до пола. Чуть глубже земли, чтобы не висел над травой.
func _pile(parent: Node3D, at: Vector2, drop: float) -> void:
	var post := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, drop + 0.5, 0.9)
	post.mesh = box
	post.material_override = TEXTURES.of("wood")
	# Сваи стоят чуть ВНУТРИ основания: поставленные точно по углу, они торчат
	# из-под стен наружу и читаются как строительные леса, а не как опора.
	post.position = Vector3(at.x * 0.86, -drop * 0.5 - 0.25, at.y * 0.86)
	parent.add_child(post)


## Подмостки: пандус от земли до порога, со стороны фасада (+Z).
##
## И коллизия к нему обязательна. Пандус, по которому нельзя подняться, — это
## не подмостки, а нарисованная доска: дом на сваях остался бы недоступен, и
## заметил бы это только тот, кто попробовал войти.
func _ramp(parent: Node3D, size: Vector3, drop: float) -> void:
	var run: float = maxf(drop * 2.4, 2.5)
	var width: float = minf(size.x * 0.5, 6.0)
	var angle: float = atan2(drop, run)
	var at := Vector3(0.0, -drop * 0.5, size.z * 0.5 + run * 0.5)

	var deck := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.35, sqrt(run * run + drop * drop))
	deck.mesh = box
	deck.material_override = TEXTURES.of("wood")
	deck.transform = Transform3D(Basis(Vector3.RIGHT, angle), at)
	parent.add_child(deck)

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = box.size
	shape.shape = slab
	shape.transform = Transform3D(Basis(Vector3.RIGHT, angle), at)
	body.add_child(shape)
	parent.add_child(body)


## RID собственного тела: нужен, чтобы исключать себя из лучей.
func _body_rid() -> RID:
	for child in get_children():
		if child is StaticBody3D:
			return (child as StaticBody3D).get_rid()
	return RID()


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
func take_damage(amount: float, attacker_id: int, _zone: String, point: Vector3, dir: Vector3,
		_aoe := false, _weapon := -1) -> void:
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


## Материал растущей коробки. КОПИЯ, а не общий материал: у недостроенного
## дома он становится полупрозрачным и меняется каждый кадр по мере стройки, и
## общий покрасил бы разом все постройки мира.
func _material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = TEXTURES.copy_of(
		"wood" if kind == RES.Building.STORAGE else "dark_stone")
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
	# Достроенное показываем домом, недостроенное — коробкой. Переключаем
	# каждый кадр, а не по сигналу: прогресс приезжает репликацией, и сигнала
	# о нём у клиента нет.
	var done := progress >= 1.0
	if _look != null:
		_look.visible = done
	_mesh.visible = not done
	if done:
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
