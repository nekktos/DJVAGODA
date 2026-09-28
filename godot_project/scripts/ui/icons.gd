extends Node
##
## Иконки интерфейса — СНИМКИ МОДЕЛЕЙ САМОЙ ИГРЫ.
##
## ЗАЧЕМ. Решение автора от 28.09.2026: «HUD, чтоб всё было не текстом, а
## интерактивными менюшками с картинками». Картинок в проекте нет, а качать
## наборы иконок — значит получить картинки чужого стиля, не похожие ни на одну
## модель в мире. Поэтому иконки снимаются с тех же моделей, что стоят в мире:
## склад на кнопке «склад» — это тот самый склад, который встанет на землю.
##
## КАК. Каждой иконке — невидимое окно (SubViewport) со своим миром, камерой и
## светом. Окно рисует кадр один раз, кадр забирается картинкой, окно
## удаляется. Всё это — один раз при запуске, на старте игры, пока открыто меню.
##
## БЕЗ ЭКРАНА (автопроверки, `--headless`) рисовать нечем: там вместо снимков
## цветные плашки по роду иконки. Интерфейс от этого не ломается — он не знает,
## снимок у него в руках или плашка.
##

const RES := preload("res://scripts/economy/resources.gd")
const LOOK := preload("res://scripts/economy/building_look.gd")
const LABOURER := preload("res://scripts/units/labourer.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")
const WEAPON_VISUAL := preload("res://scripts/combat/weapon_visual.gd")
const ABILITIES := preload("res://scripts/combat/abilities.gd")

## Мелочь для боевой полосы: стрелы, бинт, опыт, мана.
const TRINKETS := ["arrows", "bandage", "xp", "mana", "heart", "stamina",
	"armor", "potion_heal", "potion_mana"]

## Размер снимка. Иконки в меню от 24 до 80 пикселей, и 128 хватает с запасом:
## уменьшенная картинка читается лучше увеличенной.
const SIZE := 128

## Модели людей и прочего, с которых снимаются иконки.
const MODELS := {
	"unit_sword": "res://assets/people/Swordsman.glb",
	"unit_archer": "res://assets/people/Archer.glb",
	"labourer": "res://assets/people/Peasant.glb",
	"villain": "res://assets/people/Villain.glb",
	"elf": "res://assets/people/Elf.glb",
	"guard": "res://assets/people/Guard.glb",
	"horse": "res://assets/animals/Horse.glb",
	"cart": "res://assets/props/cart.glb",
	"wolf": "res://assets/animals/Wolf.glb",
}

## Плашки-заглушки: цвет по роду иконки. Пока снимков нет (первые кадры) и
## без экрана вовсе.
const FALLBACK := {
	"res": Color(0.55, 0.45, 0.30),
	"bld": Color(0.45, 0.35, 0.30),
	"role": Color(0.35, 0.45, 0.35),
	"unit": Color(0.50, 0.30, 0.30),
}

## Иконки обновились — снимки готовы. Меню перерисовывают картинки.
signal changed

var _icons := {}
## Готовы ли настоящие снимки. До этого в руках только плашки.
var rendered := false


func _ready() -> void:
	_fill_fallbacks()
	if DisplayServer.get_name() == "headless":
		return
	_render_all.call_deferred()


## Иконка по ключу. Неизвестный ключ — нейтральная плашка, а не пустота:
## пустое место в меню читается поломкой.
func icon(key: String) -> Texture2D:
	if _icons.has(key):
		return _icons[key]
	return _plate(Color(0.4, 0.4, 0.45))


## Все ключи, которые модуль умеет. Для проверок и для меню.
static func keys() -> PackedStringArray:
	var out := PackedStringArray()
	for kind in RES.COUNT:
		out.append("res_%d" % kind)
	for kind in RES.BUILDING_NAMES.size():
		out.append("bld_%d" % kind)
	for role in LABOURER.ROLE_NAMES.size():
		out.append("role_%d" % role)
	for key in MODELS:
		out.append(key)
	for kind in WEAPONS.NAMES.size():
		out.append("wpn_%d" % kind)
	for kind in ABILITIES.COUNT:
		out.append("abl_%d" % kind)
	for key in TRINKETS:
		out.append(key)
	return out


func _fill_fallbacks() -> void:
	for key in keys():
		var family := key.get_slice("_", 0)
		_icons[key] = _plate(FALLBACK.get(family, Color(0.45, 0.45, 0.50)))


static func _plate(color: Color) -> Texture2D:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


# --- съёмка ---------------------------------------------------------------

func _render_all() -> void:
	var jobs := []
	for key in keys():
		var subject := _subject(key)
		if subject == null:
			continue
		jobs.append([key, _stage(subject, key)])
	# Два кадра: в первом окно собирает сцену (скелеты встают в позу), во
	# втором рисует. Одного иногда не хватало — снимок выходил пустым.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for job in jobs:
		var viewport: SubViewport = job[1]
		var image: Image = viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			_icons[job[0]] = ImageTexture.create_from_image(image)
		viewport.queue_free()
	rendered = true
	changed.emit()


## Что снимать для ключа.
func _subject(key: String) -> Node3D:
	if key.begins_with("res_"):
		return _resource_pile(int(key.get_slice("_", 1)))
	if key.begins_with("bld_"):
		var kind := int(key.get_slice("_", 1))
		return LOOK.build(kind, RES.BUILDING_SIZE[kind])
	if key.begins_with("role_"):
		return _model(LABOURER.ROLE_MODELS[int(key.get_slice("_", 1))])
	if key.begins_with("wpn_"):
		# Оружие — тем же кодом, что в руках у персонажа (`weapon_visual.gd`).
		# Оно лежит вдоль оси Z; наклоняем, чтобы на снимке шло по диагонали.
		var holder := Node3D.new()
		var weapon := Node3D.new()
		weapon.rotation = Vector3(deg_to_rad(-45.0), 0.0, 0.0)
		holder.add_child(weapon)
		WEAPON_VISUAL._build(weapon, int(key.get_slice("_", 1)), 1)
		return holder
	if key.begins_with("abl_"):
		return _ability_sign(int(key.get_slice("_", 1)))
	if key in TRINKETS:
		return _trinket(key)
	if MODELS.has(key):
		return _model(MODELS[key])
	return null


func _model(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


## Сцена для одного снимка: своё окно, свой мир, свет, камера по размеру модели.
func _stage(subject: Node3D, key: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	environment.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.3
	viewport.add_child(sun)

	viewport.add_child(subject)
	_pose(subject)

	var bounds := _bounds(subject)
	var centre := bounds.get_center()
	var radius := maxf(0.5, bounds.size.length() * 0.5)
	# ЛЮДИ — ПОРТРЕТОМ, по пояс. Во весь рост человек в квадрате выходит
	# тонкой палочкой: на первом снимке лесоруба от шахтёра было не отличить.
	if key.begins_with("role_") or (MODELS.has(key) and key not in ["horse", "cart", "wolf"]):
		centre = Vector3(centre.x, bounds.position.y + bounds.size.y * 0.72, centre.z)
		radius = maxf(0.3, bounds.size.y * 0.32)
	# Люди и звери — спереди и чуть сверху, постройки и кучи — на три четверти
	# сверху: так дом читается домом, а не стеной.
	var looking := Vector3(0.9, 0.9, 1.3)
	if MODELS.has(key) or key.begins_with("role_"):
		looking = Vector3(0.35, 0.25, 1.0)
	if key.begins_with("wpn_"):
		# Сбоку: наклонённое оружие видно во всю длину.
		looking = Vector3(1.0, 0.1, 0.05)
	if key.begins_with("abl_") or key in TRINKETS:
		looking = Vector3(0.25, 0.35, 1.0)
	var camera := Camera3D.new()
	camera.fov = 30.0
	var distance := radius / sin(deg_to_rad(camera.fov * 0.5)) * 1.02
	viewport.add_child(camera)
	camera.look_at_from_position(centre + looking.normalized() * distance, centre)
	camera.current = true
	return viewport


## Поставить модель в позу покоя. Без этого люди на снимке стояли бы буквой Т.
func _pose(subject: Node) -> void:
	var player := _find_player(subject)
	if player == null:
		return
	for name in ["Idle", "idle"]:
		if player.has_animation(name):
			player.play(name)
			player.seek(0.3, true)
			return


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


## Размер модели по всем её сеткам — чтобы камера встала ровно по ней.
func _bounds(subject: Node3D) -> AABB:
	var total := AABB()
	var first := true
	for node in subject.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		if first:
			total = box
			first = false
		else:
			total = total.merge(box)
	if first:
		return AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	return total


# --- знаки заклинаний и мелочь ---------------------------------------------

## Знак заклинания. Моделей у заклинаний нет, кроме волка у призыва, и знаки
## собраны из простых тел, но СВЕТЯТСЯ цветом школы: зелёное — эльфийское
## лечение и клич, фиолетовое — проклятия злодея.
func _ability_sign(kind: int) -> Node3D:
	var root := Node3D.new()
	var green := Color(0.35, 0.95, 0.45)
	var violet := Color(0.70, 0.35, 0.95)
	match kind:
		ABILITIES.Kind.HEAL:
			root.add_child(_glow_box(Vector3(0.3, 1.0, 0.3), green))
			root.add_child(_glow_box(Vector3(1.0, 0.3, 0.3), green))
		ABILITIES.Kind.RALLY:
			# Рог: конус раструбом вверх.
			var horn := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.38
			cone.bottom_radius = 0.06
			cone.height = 1.0
			horn.mesh = cone
			horn.material_override = _glow(Color(0.95, 0.78, 0.30))
			horn.rotation = Vector3(0.0, 0.0, deg_to_rad(-30.0))
			root.add_child(horn)
		ABILITIES.Kind.SUMMON:
			var wolf := _model(MODELS["wolf"])
			if wolf != null:
				root.add_child(wolf)
		ABILITIES.Kind.PARALYSIS:
			# Путы: два сцепленных кольца.
			for i in 2:
				var ring := MeshInstance3D.new()
				var torus := TorusMesh.new()
				torus.inner_radius = 0.22
				torus.outer_radius = 0.34
				ring.mesh = torus
				ring.material_override = _glow(violet)
				ring.position = Vector3(-0.2 + 0.4 * i, 0.0, 0.0)
				ring.rotation = Vector3(deg_to_rad(90.0 * i), 0.0, 0.0)
				root.add_child(ring)
		ABILITIES.Kind.WITHER:
			# Череп: шар и два тёмных глаза.
			var skull := _sphere(0.5, Color(0.55, 0.45, 0.60))
			skull.material_override = _glow(Color(0.50, 0.30, 0.55))
			root.add_child(skull)
			for side in [-0.18, 0.18]:
				var eye := _sphere(0.11, Color(0.05, 0.02, 0.06))
				eye.position = Vector3(side, 0.05, 0.43)
				root.add_child(eye)
		ABILITIES.Kind.BLIND:
			# Глаз, перечёркнутый.
			var eye_white := _sphere(0.45, Color(0.92, 0.90, 0.86))
			eye_white.scale = Vector3(1.0, 0.6, 0.5)
			root.add_child(eye_white)
			var pupil := _sphere(0.16, Color(0.05, 0.05, 0.05))
			pupil.position = Vector3(0.0, 0.0, 0.2)
			root.add_child(pupil)
			var slash := _glow_box(Vector3(1.2, 0.12, 0.12), violet)
			slash.position = Vector3(0.0, 0.0, 0.3)
			slash.rotation = Vector3(0.0, 0.0, deg_to_rad(35.0))
			root.add_child(slash)
	return root


func _trinket(key: String) -> Node3D:
	var root := Node3D.new()
	match key:
		"arrows":
			for i in 3:
				var shaft := _cylinder(0.025, 1.0, Color(0.55, 0.40, 0.22))
				shaft.position = Vector3(-0.12 + 0.12 * i, 0.0, 0.0)
				shaft.rotation = Vector3(0.0, 0.0, deg_to_rad(20.0))
				root.add_child(shaft)
				var tip := _box(Vector3(0.07, 0.14, 0.07), Color(0.75, 0.76, 0.80), 0.6)
				tip.position = shaft.position + Vector3(-0.17, 0.47, 0.0)
				tip.rotation = shaft.rotation
				root.add_child(tip)
		"bandage":
			var roll := _cylinder(0.3, 0.4, Color(0.95, 0.93, 0.88))
			roll.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
			root.add_child(roll)
			var mark := _glow_box(Vector3(0.1, 0.34, 0.02), Color(0.85, 0.15, 0.15))
			mark.position = Vector3(0.0, 0.0, 0.21)
			root.add_child(mark)
			var mark2 := _glow_box(Vector3(0.34, 0.1, 0.02), Color(0.85, 0.15, 0.15))
			mark2.position = Vector3(0.0, 0.0, 0.21)
			root.add_child(mark2)
		"xp":
			var gem := _box(Vector3(0.5, 0.5, 0.5), Color(0.98, 0.80, 0.30), 0.7)
			gem.material_override = _glow(Color(0.98, 0.80, 0.30))
			gem.rotation = Vector3(deg_to_rad(45.0), deg_to_rad(45.0), 0.0)
			root.add_child(gem)
		"mana":
			var drop := _sphere(0.4, Color(0.35, 0.55, 1.0))
			drop.material_override = _glow(Color(0.35, 0.55, 1.0))
			root.add_child(drop)
		"heart":
			# Сердце: два шара и ромб под ними.
			var red := Color(0.90, 0.20, 0.22)
			for side in [-0.2, 0.2]:
				var lobe := _sphere(0.26, red)
				lobe.material_override = _glow(red)
				lobe.position = Vector3(side, 0.12, 0.0)
				root.add_child(lobe)
			var point := _glow_box(Vector3(0.42, 0.42, 0.3), red)
			point.position = Vector3(0.0, -0.14, 0.0)
			point.rotation = Vector3(0.0, 0.0, deg_to_rad(45.0))
			root.add_child(point)
		"armor":
			# Кираса: корпус и два наплечника.
			var steel := Color(0.55, 0.57, 0.62)
			var chest := _box(Vector3(0.7, 0.8, 0.35), steel, 0.8)
			root.add_child(chest)
			for side in [-0.48, 0.48]:
				var pad := _sphere(0.2, steel)
				pad.material_override = _material(steel, 0.8)
				pad.position = Vector3(side, 0.32, 0.0)
				pad.scale = Vector3(1.0, 0.7, 1.0)
				root.add_child(pad)
		"potion_heal", "potion_mana":
			# Склянка: пузо, горлышко, пробка. Цвет — что в ней.
			var tint := Color(0.90, 0.20, 0.25) if key == "potion_heal" else Color(0.35, 0.55, 1.0)
			var belly := _sphere(0.38, tint)
			belly.material_override = _glow(tint)
			root.add_child(belly)
			var neck := _cylinder(0.12, 0.35, Color(0.85, 0.90, 0.95))
			neck.position = Vector3(0.0, 0.45, 0.0)
			root.add_child(neck)
			var cork := _cylinder(0.14, 0.14, Color(0.55, 0.38, 0.22))
			cork.position = Vector3(0.0, 0.66, 0.0)
			root.add_child(cork)
		"stamina":
			# Молния: три наклонённых бруска зигзагом.
			var amber := Color(0.98, 0.78, 0.35)
			var parts := [[Vector3(0.1, 0.35, 0.0), 25.0], [Vector3(0.0, 0.0, 0.0), -55.0],
				[Vector3(-0.1, -0.35, 0.0), 25.0]]
			for part in parts:
				var bolt := _glow_box(Vector3(0.14, 0.5, 0.14), amber)
				bolt.position = part[0]
				bolt.rotation = Vector3(0.0, 0.0, deg_to_rad(part[1]))
				root.add_child(bolt)
	return root


func _glow(color: Color) -> StandardMaterial3D:
	var mat := _material(color)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	return mat


func _glow_box(size: Vector3, color: Color) -> MeshInstance3D:
	var out := _box(size, color)
	out.material_override = _glow(color)
	return out


# --- кучи ресурсов ----------------------------------------------------------

## Кучка ресурса. Те же приметы, что у кучи на земле (`loot.gd`): брёвна,
## камни, слитки, — плюс сноп для еды и чёрные комья для угля.
func _resource_pile(kind: int) -> Node3D:
	var root := Node3D.new()
	match kind:
		RES.Kind.WOOD:
			for at in [Vector3(-0.2, 0.16, 0.0), Vector3(0.2, 0.16, 0.0), Vector3(0.0, 0.45, 0.0)]:
				var log_mesh := _cylinder(0.17, 1.2, Color(0.45, 0.30, 0.17))
				log_mesh.position = at
				log_mesh.rotation = Vector3(0.0, 0.0, PI * 0.5)
				root.add_child(log_mesh)
		RES.Kind.STONE:
			for at in [Vector3(-0.3, 0.2, 0.0), Vector3(0.3, 0.18, 0.1), Vector3(0.0, 0.45, 0.0)]:
				var rock := _sphere(0.3, Color(0.58, 0.57, 0.55))
				rock.position = at
				rock.scale = Vector3(1.0, 0.75, 0.9)
				root.add_child(rock)
		RES.Kind.GOLD:
			_ingots(root, Color(0.95, 0.76, 0.22))
		RES.Kind.IRON:
			_ingots(root, Color(0.62, 0.64, 0.68))
		RES.Kind.FOOD:
			# Сноп: пучок стеблей, перехваченный посередине.
			for i in 9:
				var angle := TAU * float(i) / 9.0
				var stalk := _cylinder(0.05, 1.1, Color(0.90, 0.76, 0.32))
				stalk.position = Vector3(cos(angle) * 0.12, 0.55, sin(angle) * 0.12)
				stalk.rotation = Vector3(sin(angle) * 0.12, 0.0, cos(angle) * 0.12)
				root.add_child(stalk)
			var band := _cylinder(0.2, 0.08, Color(0.55, 0.35, 0.15))
			band.position = Vector3(0.0, 0.55, 0.0)
			root.add_child(band)
		RES.Kind.COAL:
			for at in [Vector3(-0.25, 0.17, 0.0), Vector3(0.25, 0.15, 0.1),
					Vector3(0.0, 0.38, -0.05), Vector3(0.05, 0.15, -0.3)]:
				# Не чёрный, а тёмно-серый с блеском: чисто чёрный уголь на тёмной
				# полосе запасов не был виден вовсе.
				var lump := _box(Vector3(0.36, 0.3, 0.32), Color(0.24, 0.24, 0.27), 0.5)
				lump.position = at
				lump.rotation = Vector3(0.4, float(at.x) * 3.0, 0.3)
				root.add_child(lump)
	return root


func _ingots(root: Node3D, color: Color) -> void:
	for at in [Vector3(-0.28, 0.1, 0.0), Vector3(0.28, 0.1, 0.0), Vector3(0.0, 0.3, 0.0)]:
		var bar := _box(Vector3(0.5, 0.2, 0.26), color, 0.6)
		bar.position = at
		root.add_child(bar)


func _material(color: Color, metal := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.45 if metal > 0.0 else 0.85
	return mat


func _cylinder(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var out := MeshInstance3D.new()
	out.mesh = mesh
	out.material_override = _material(color)
	return out


func _sphere(radius: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var out := MeshInstance3D.new()
	out.mesh = mesh
	out.material_override = _material(color)
	return out


func _box(size: Vector3, color: Color, metal := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var out := MeshInstance3D.new()
	out.mesh = mesh
	out.material_override = _material(color, metal)
	return out
