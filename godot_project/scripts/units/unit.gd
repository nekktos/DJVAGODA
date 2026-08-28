extends CharacterBody3D
##
## Боец отряда (Этап 6, GDD раздел 2.3): мечник из казармы.
##
## Ведёт себя просто и намеренно: держит свой слот в построении, а если рядом
## оказался враг — бьёт его и возвращается в строй. GDD прямо ограничивает
## объём этого этапа: «не полноценный ИИ-пафайндинг для сложных манёвров, а
## заранее заданные формации». Обхода препятствий тут нет, движение прямое.
##
## Всё считает ТОЛЬКО хост: движение, выбор цели, урон. Клиенты получают
## позицию и здоровье и просто рисуют.
##

const FORMATIONS := preload("res://scripts/units/formations.gd")
const HIT_ZONE := preload("res://scripts/combat/hit_zone.gd")
const WEAPON_VISUAL := preload("res://scripts/combat/weapon_visual.gd")
const MODEL_ANIM := preload("res://scripts/model_anim.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")
const RES := preload("res://scripts/economy/resources.gd")
const ABILITIES := preload("res://scripts/combat/abilities.gd")
const EFFECTS := preload("res://scripts/combat/effects.gd")

const MODELS := [
	"res://assets/characters/character-d.glb",
	"res://assets/characters/character-e.glb",
	"res://assets/characters/character-f.glb",
]
const MODEL_SCALE := 0.68

const PART_ZONES := {
	"head": "head",
	"torso": "torso",
	"arm-left": "arm_l",
	"arm-right": "arm_r",
	"leg-left": "leg_l",
	"leg-right": "leg_r",
}
const ZONE_MULTIPLIERS := {
	"head": 2.0, "torso": 1.0,
	"arm_l": 0.7, "arm_r": 0.7, "leg_l": 0.7, "leg_r": 0.7,
}

const MAX_HEALTH := 90.0
const BASE_SPEED := 5.2
## Дальше этого боец врага не замечает и держит строй.
const ENGAGE_RANGE := 14.0
## Ближе этого можно бить.
const STRIKE_RANGE := 2.4
const STRIKE_DAMAGE := 22.0
const STRIKE_COOLDOWN := 1.1
## Насколько точно надо встать в свой слот, чтобы считать себя в строю.
const SLOT_TOLERANCE := 1.2

## Расталкивание соседей: радиус действия и сила. Без него бойцы в плотном
## строю упираются друг в друга и марш встаёт.
const SEPARATION_RADIUS := 1.7
const SEPARATION_FORCE := 5.0
## Потолок горизонтальной скорости, чтобы расталкивание никого не разгоняло.
const MAX_FLAT_SPEED := 9.0

## Призванный волк (Этап 8). Тот же боец, но зверь: быстрее, кусает чаще и
## слабее, живёт минуту и растворяется. Бессрочный призыв дал бы эльфам
## бесплатный вечный отряд, а отряд по GDD — механика злодея.
const BEAST_HEALTH := 55.0
const BEAST_SPEED := 7.4
const BEAST_DAMAGE := 14.0
const BEAST_COOLDOWN := 0.8
const BEAST_SCALE := 0.55
const BEAST_COLOR := Color(0.32, 0.30, 0.36)

## Распорядитель стражи (Этап 10). Тот же боец, но чемпион: убить его можно, и
## это осмысленная цель — пока он лежит, стража не получает приказов и не может
## повысить своего до командира. Но убивать его в одиночку не следует.
##
## Числа взяты от существующего баланса, а не с потолка. Игрок — 100 HP и около
## 50 dps мечом; рядовой боец — 90 HP и 20 dps. Чемпион бьёт втрое сильнее
## рядового: у игрока с полным здоровьем есть примерно четыре его удара, то есть
## размен «в лоб» злодей проигрывает всегда. Запас в 700 — это тридцать секунд
## непрерывной рубки мечом, которых у одиночки не будет; впятером отряд сносит
## его за семь секунд, потеряв двоих. Чемпион чуть быстрее игрока, поэтому
## бегать вокруг и клевать его бесполезно — а вот отойти, перевязаться и
## вернуться можно: за поводок он не пойдёт.
const CHAMPION_HEALTH := 700.0
const CHAMPION_SPEED := 6.6
const CHAMPION_DAMAGE := 32.0
const CHAMPION_COOLDOWN := 1.0
const CHAMPION_ENGAGE := 20.0
const CHAMPION_SCALE := 1.18
const CHAMPION_COLOR := Color(0.78, 0.20, 0.18)

## Путь по карте (Этап 10). Раньше боец шёл к цели ПО ПРЯМОЙ и о препятствиях
## не знал вовсе: для отряда живого игрока это терпели с Этапа 6, потому что
## командир обходит стены сам. Отряду ИИ вести некому — он упирался в стену и
## стоял там до конца партии.
##
## Ближе DIRECT_RANGE боец идёт НАПРЯМУЮ, не спрашивая пути. Порог намеренно
## большой, и вот почему.
##
## Точки пути лежат на рёбрах полигонов сетки, и у четверых бойцов, идущих
## рядом, они получаются почти одинаковыми. Если каждый пойдёт по своему пути,
## строй схлопнется: все четверо двинутся в одну точку, упрутся друг в друга, а
## расталкивание погасит остаток скорости. Так и вышло в первом прогоне с
## навигацией — отряд встал в шестидесяти метрах от цели с нулевой скоростью и
## простоял так до конца.
##
## Строй держится ОТНОСИТЕЛЬНО ЯКОРЯ, а путь по карте прокладывает якорь
## (`warband.gd`) — или живой командир своими глазами. Бойцу сетка нужна только
## когда он отстал и догоняет в одиночку: место в строю в двадцати пяти метрах —
## это уже не строй.
const DIRECT_RANGE := 25.0

## Сколько секунд боец должен упираться, чтобы перестать верить прямой дороге.
##
## Строй держится относительно якоря, а якорь идёт по сетке — и обходит то, что
## боец, срезающий угол к своему месту в строю, встречает лбом. Так отряд и встал
## у восточной стены полосы препятствий на перекрёстке: якорь обогнул её с
## севера, а четверо шли прямо в неё и стояли там до конца прогона.
##
## Поэтому прямая дорога — это предположение, а не правило. Не сработало за
## полсекунды — идём по сетке, даже если место в строю в двух шагах.
const BLOCKED_SECONDS := 0.5

## Насколько надо приблизиться к цели, чтобы это считалось продвижением. Меньше
## этого — топтание: боец качается на месте или скользит вдоль препятствия.
const PROGRESS_STEP := 0.6
## Насколько цель должна уехать, чтобы перекладывать путь.
const REPATH_DISTANCE := 6.0
## Ближе этого точка пути считается пройденной.
const WAYPOINT_RADIUS := 2.5

## Лучник (Этап 10). Тот же боец, но бьёт издали и почти беспомощен вблизи.
##
## Числа берутся у ЛУКА из `weapons.gd` — того самого, которым стреляет игрок.
## Отдельного «урона лучника» нет намеренно: два набора чисел на одно и то же
## оружие разошлись бы при первой же правке баланса.
##
## Дальность боя вчетверо больше мечницкой: в этом весь смысл рода войск.
## Здоровья меньше — лучник, до которого добежали, должен умирать быстро, иначе
## он просто лучший мечник.
const ARCHER_HEALTH := 65.0
const ARCHER_ENGAGE := 32.0
## На каком расстоянии лучник останавливается и стреляет. Ближе не подходит.
const ARCHER_RANGE := 24.0
const ARCHER_COLOR := Color(0.36, 0.46, 0.28)

## Насколько лучник стоит ПОЗАДИ своего места в строю.
##
## Без этого он вставал в первую шеренгу наравне с мечниками и умирал первым —
## притом что вся его ценность в том, чтобы стрелять с двадцати четырёх метров.
## Строй при этом не переделываем: место в нём остаётся его местом, лучник просто
## держится за спинами. Так же это работает и у отряда живого игрока, и у ИИ —
## одним числом, а не двумя разными правилами.
const ARCHER_REAR := 7.0

const BODY_LAYER := 2
const HITBOX_LAYER := 4

signal died_on_server(unit: Node3D)

## Реплицируемое состояние.
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var health: float = MAX_HEALTH
@export var sync_moving: bool = false

var owner_id := 1
var slot := 0
## Сторона бойца. Раньше «свой-чужой» определялось по ВЛАДЕЛЬЦУ, и это было
## верно ровно до тех пор, пока на сторону приходился один игрок. Теперь у
## эльфов и стражи по пять слотов, и отряды двух союзников резали бы друг друга.
##
## Гарнизонам ИИ владельца нет вовсе, у них есть только сторона.
var faction := 0
## Куда возвращаться, если врага рядом нет. Ноль — значит боец служит игроку и
## ходит за ним, а не сторожит точку.
var home := Vector3.ZERO
## Дальше этого от дома гарнизон не гонится за целью: он обороняет зону, а не
## воюет по всей карте. У бойцов игрока поводка нет.
var leash := 0.0
## Зверь ли это. Приезжает в пакете спавна и потому одинаков на всех пирах —
## реплицировать отдельно не нужно, как owner_id и slot.
var is_beast := false

## Распорядитель стражи: боец с многократным запасом, см. CHAMPION_*.
var is_champion := false

## Лучник: стреляет вместо удара, см. ARCHER_*.
var is_archer := false

## Приказ ИИ свободной стороны (Этап 10, шаг 8, ступень «б»).
##
## Боец не знает, кто им командует, — игрок или `ai/warband.gd`. Он получает
## якорь строя, разворот и вид построения, и дальше идёт тем же кодом, что и
## отряд живого игрока. Это не экономия строк: если бы у ИИ был свой путь
## движения, у него был бы и свой набор ошибок, которого не видно в игре за
## людей.
var ai_led := false
var ai_anchor := Vector3.ZERO
var ai_yaw := 0.0
var ai_formation := 0
## Сколько зверю осталось жить. Считает и обнуляет только хост.
var life_left := 0.0

var _model: Node3D
var _anim: AnimationPlayer
var _parts := {}
var _cooldown := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _current_anim := ""
## Путь до цели и место в нём. Только у хоста: клиент получает готовые позиции.
var _path := PackedVector3Array()
var _path_index := 0
var _path_goal := Vector3.INF
## Сколько времени боец упирается, никуда не двигаясь.
var _blocked_t := 0.0
## Лучшее расстояние до цели, которого удалось добиться, и когда это было.
## По ним видно, что боец не продвигается, даже если он бодро скользит вдоль
## скалы на полной скорости.
var _best_gap := INF
var _best_goal := Vector3.INF
## Куда бойца ведут прямо сейчас. Нужна сторожу продвижения.
var _last_goal := Vector3.INF
var _alive := true
## Перевербовка: сколько осталось и куда вернуть сторону.
var _charm_left := 0.0
var _charm_home := -1


## Вызывается спавнером на всех пирах с одинаковыми данными.
func setup(data: Dictionary) -> void:
	owner_id = int(data["owner"])
	slot = int(data["slot"])
	position = data["point"]
	sync_position = position
	faction = int(data.get("faction", 0))
	home = data.get("home", Vector3.ZERO)
	leash = float(data.get("leash", 0.0))
	is_beast = bool(data.get("beast", false))
	is_champion = bool(data.get("champion", false))
	is_archer = bool(data.get("archer", false))
	if is_beast:
		health = BEAST_HEALTH
		life_left = ABILITIES.SUMMON_LIFETIME
	elif is_champion:
		health = CHAMPION_HEALTH
	elif is_archer:
		health = ARCHER_HEALTH


func _ready() -> void:
	add_to_group("unit")
	collision_layer = BODY_LAYER
	# Сталкиваемся и с миром, и с телами. Раньше взаимные столкновения были
	# отключены, потому что бойцы упирались друг в друга и марш замедлялся
	# втрое — но это лечило симптом не с той стороны, и бойцы проникали друг в
	# друга. Теперь коллизии на месте, а от заклинивания спасает расталкивание
	# (_separation): бойцы мягко разъезжаются, а не толкаются лбами.
	collision_mask = 1 | 2
	_build_model()


## Волк из примитивов.
##
## Не модель из набора, и вот почему: хороших бесплатных волков хватает, но все
## они лежат либо за кликом руками (itch, poly.pizza с проверкой «я не робот»),
## либо в формате Blender, которого на машине сборки нет. Тащить в проект
## случайный файл сомнительного происхождения ради силуэта — плохой размен.
##
## Из коробок собирается узнаваемо: низкое вытянутое тело, вытянутая морда,
## четыре ноги, хвост. Читается как зверь с первого взгляда — а именно это от
## него и требуется, пока не появится художник.
func _build_beast() -> void:
	_model = Node3D.new()
	_model.name = "Model"

	var hide := StandardMaterial3D.new()
	hide.albedo_color = BEAST_COLOR

	# Туловище низкое и длинное: главный признак четвероногого.
	_beast_box(hide, Vector3(0.0, 0.62, 0.0), Vector3(0.52, 0.44, 1.20))
	# Грудь чуть выше и шире крупа — силуэт перестаёт быть коробкой.
	_beast_box(hide, Vector3(0.0, 0.70, -0.42), Vector3(0.58, 0.46, 0.44))
	# Шея и голова вынесены ВПЕРЁД и ВНИЗ: волк держит голову на уровне спины,
	# и именно это отличает его от собаки, задранной вверх.
	_beast_box(hide, Vector3(0.0, 0.72, -0.78), Vector3(0.30, 0.30, 0.34))
	_beast_box(hide, Vector3(0.0, 0.66, -1.02), Vector3(0.22, 0.20, 0.30))
	# Уши.
	_beast_box(hide, Vector3(-0.11, 0.92, -0.74), Vector3(0.09, 0.16, 0.06))
	_beast_box(hide, Vector3(0.11, 0.92, -0.74), Vector3(0.09, 0.16, 0.06))
	# Хвост поленом назад и вниз.
	_beast_box(hide, Vector3(0.0, 0.60, 0.72), Vector3(0.16, 0.16, 0.46))
	# Четыре ноги.
	for leg in 4:
		var side: float = -0.20 if leg % 2 == 0 else 0.20
		var fore: float = -0.42 if leg < 2 else 0.42
		_beast_box(hide, Vector3(side, 0.20, fore), Vector3(0.15, 0.40, 0.15))

	add_child(_model)


func _beast_box(mat: Material, at: Vector3, size: Vector3) -> void:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	part.mesh = box
	part.material_override = mat
	part.position = at
	_model.add_child(part)


func _build_model() -> void:
	# Зверь собирается отдельно: он не человек, и человеческой моделью его не
	# изобразить никак. Раньше это была та же модель, сплющенная и затемнённая, —
	# в инструкции тестерам так и написано: «призванный волк выглядит как
	# приземистый тёмный человек». Теперь это четвероногое.
	if is_beast:
		_build_beast()
		return
	var packed: PackedScene = load(MODELS[slot % MODELS.size()])
	_model = packed.instantiate()
	_model.name = "Model"
	# Волка среди бесплатных ассетов нет, поэтому зверь — приземистая и тёмная
	# версия той же модели. Заглушка ровно того же сорта, что и grey-box карты:
	# силуэт читается как «не человек», остальное подождёт художника.
	var model_scale := MODEL_SCALE
	if is_beast:
		model_scale *= BEAST_SCALE
	elif is_champion:
		model_scale *= CHAMPION_SCALE
	_model.scale = Vector3(model_scale, model_scale * 0.7, model_scale * 1.5) if is_beast else Vector3.ONE * model_scale
	# Модель смотрит в +Z, игра считает передом -Z — см. player.gd::_build_model.
	_model.rotation.y = PI
	add_child(_model)
	if is_beast:
		_tint(_model, BEAST_COLOR)
	elif is_champion:
		# Крупнее и в красном: в толпе стражи он должен читаться с первого
		# взгляда, иначе нападать на него будут по незнанию.
		_tint(_model, CHAMPION_COLOR)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	var body_scale := 1.0
	if is_beast:
		body_scale = BEAST_SCALE
	elif is_champion:
		body_scale = CHAMPION_SCALE
	capsule.radius = 0.35 * body_scale
	capsule.height = 1.8 * body_scale
	shape.shape = capsule
	shape.position = Vector3(0.0, capsule.height * 0.5, 0.0)
	add_child(shape)

	_anim = _find_anim(_model)
	# Ходьба должна зацикливаться — см. model_anim.gd.
	MODEL_ANIM.make_looping(_anim)
	for part_name in PART_ZONES.keys():
		var mesh := _find_by_name(_model, part_name) as MeshInstance3D
		if mesh == null:
			continue
		var key: String = PART_ZONES[part_name]
		_parts[key] = mesh
		HIT_ZONE.attach(mesh, key, ZONE_MULTIPLIERS.get(key, 1.0), HITBOX_LAYER)
	# Мечник — с мечом в руке, точка хвата считается по габаритам руки.
	# Зверь дерётся зубами: меч в лапе выглядел бы нелепо.
	if not is_beast:
		WEAPON_VISUAL.attach(_parts.get("arm_r"), WEAPONS.Kind.SWORD, null, 0)
	_play("idle")


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null


func _find_by_name(node: Node, wanted: String) -> Node:
	if String(node.name) == wanted:
		return node
	for child in node.get_children():
		var found := _find_by_name(child, wanted)
		if found != null:
			return found
	return null


func _play(anim_name: String) -> void:
	if _anim == null or anim_name == _current_anim:
		return
	if not _anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	_anim.play(anim_name)


func _physics_process(delta: float) -> void:
	if not Net.hosting():
		var t := clampf(delta * 14.0, 0.0, 1.0)
		global_position = global_position.lerp(sync_position, t)
		rotation.y = lerp_angle(rotation.y, sync_yaw, t)
		_play("walk" if sync_moving else "idle")
		return

	if not _alive:
		return

	# Призванный зверь живёт отмеренное время и растворяется.
	if is_beast:
		life_left -= delta
		if life_left <= 0.0:
			_alive = false
			print("[призыв] волк игрока %d растворился" % owner_id)
			died_on_server.emit(self)
			queue_free()
			return

	_cooldown = maxf(0.0, _cooldown - delta)
	if _charm_left > 0.0:
		_charm_left -= delta
		if _charm_left <= 0.0 and _charm_home >= 0:
			faction = _charm_home
			_charm_home = -1

	var target: Node3D = _find_target() if _wants_fight() else null
	var destination: Vector3
	var facing_target := false

	# Гарнизон не гонится за целью дальше поводка: он обороняет зону, а не воюет
	# по всей карте. Без этого первый же пробегающий мимо эльф уводил бы весь
	# гарнизон дворца за собой.
	if target != null and not _within_leash(target.global_position):
		target = null

	if target != null and global_position.distance_to(target.global_position) <= _engage_range():
		destination = target.global_position
		facing_target = true
	else:
		destination = _idle_destination(delta)

	if not destination.is_finite():
		# Неконечная точка расползается по всему отряду: NaN попадает в позицию,
		# оттуда в расталкивание соседей, и через кадр весь строй перестаёт
		# существовать. Так однажды и вышло — ИИ выдал якорь, которого не было.
		# Дешевле не пустить, чем потом искать источник в мегабайтах лога.
		push_error("Бойцу назначена неконечная точка — приказ отброшен")
		destination = global_position
	# Приход считаем по НАСТОЯЩЕЙ цели, а шагаем по пути к ней. Если считать
	# приход по точке пути, боец начнёт бить воздух на первом же повороте.
	_last_goal = destination
	var step_to := _next_step(destination)
	var to_dest := destination - global_position
	to_dest.y = 0.0
	var distance := to_dest.length()
	var stop_at: float = _reach_of(target) if facing_target else SLOT_TOLERANCE

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	var desired := Vector3.ZERO
	if distance > stop_at:
		var to_step := step_to - global_position
		to_step.y = 0.0
		var dir := to_step.normalized() if to_step.length() > 0.01 else to_dest.normalized()
		var speed := _move_speed()
		desired = dir * speed
		rotation.y = atan2(-dir.x, -dir.z)
		sync_moving = true
	else:
		sync_moving = false
		if facing_target:
			_strike(target)

	# Расталкивание работает всегда, в том числе на месте: иначе бойцы, пришедшие
	# в соседние слоты, стоят внахлёст.
	#
	# Но гасить ХОД оно не должно. Убираем встречную составляющую: пусть разводит
	# бойцов боками, а не останавливает идущего сзади тем, кто идёт впереди.
	# Без этого четвёрка, сходящаяся к соседним местам в строю, запирала себя
	# намертво — каждый упирался в переднего, сумма скоростей выходила нулевой, и
	# отряд стоял так до конца партии в шестидесяти метрах от цели. Снаружи это
	# не отличить от препятствия, и я честно искал стену, которой там не было.
	var push := _separation()
	if desired.length() > 0.01:
		var forward := desired.normalized()
		var against := push.dot(forward)
		if against < 0.0:
			push -= forward * against
	var flat := Vector3(desired.x + push.x, 0.0, desired.z + push.z)
	if flat.length() > MAX_FLAT_SPEED:
		flat = flat.normalized() * MAX_FLAT_SPEED
	velocity.x = flat.x
	velocity.z = flat.z

	move_and_slide()
	_note_blocked(delta)
	sync_position = global_position
	sync_yaw = rotation.y
	_play("walk" if sync_moving else "idle")


## Куда идти, когда драться не с кем.
##
## Развилка вынесена отдельно, потому что у батрака (`labourer.gd`) на этом
## месте своё дело: он идёт работать, а не стоять в строю. Мечник и гарнизон
## ведут себя как раньше.
func _idle_destination(_delta: float) -> Vector3:
	var commander := _commander()
	if commander != null:
		return _slot_point(commander)
	if ai_led:
		# Место в строю, назначенном ИИ. Тот же расчёт, что и у отряда игрока.
		return ai_anchor + Basis(Vector3.UP, ai_yaw) * _formation_offset()
	if leash > 0.0:
		# Врага рядом нет — возвращаемся на пост.
		return home
	return global_position


## Смещение от якоря строя: место по построению плюс отставание для лучника.
func _formation_offset() -> Vector3:
	var offset: Vector3 = FORMATIONS.slot_offset(_formation(), slot, 0)
	if is_archer:
		# +z в местных осях строя — это «назад» (см. formations.gd::slot_offset).
		offset.z += ARCHER_REAR
	return offset


## Ищет ли этот боец, кого ударить. Батрак на работе — нет.
func _wants_fight() -> bool:
	return true


## Перевербовать на время. Паралич воли по НАЁМНОМУ существу — это буквальный
## контроль разума (GDD 3.2), и он уместен именно потому, что боец не человек.
##
## Меняем СТОРОНУ и ничего больше: весь «свой-чужой» в игре считается по ней, и
## перевербованный сам собой начинает драться за нового хозяина, идти в его
## строю и не трогать его бойцов. Отдельного состояния «под контролем» заводить
## не нужно — нужно только помнить, куда возвращать.
func charm(new_faction: int, seconds: float) -> void:
	if not Net.hosting() or not _alive:
		return
	if _charm_left <= 0.0:
		_charm_home = faction
	faction = new_faction
	_charm_left = maxf(_charm_left, seconds)
	# Под чужой рукой боец не держит прежний пост: иначе он побежит домой к тем,
	# против кого его только что развернули.
	ai_led = false
	home = global_position
	leash = 0.0


func charmed() -> bool:
	return _charm_left > 0.0


## Внутри ли точка зоны, которую этот боец обороняет. Без поводка (бойцы
## игрока) верно всегда.
func _within_leash(point: Vector3) -> bool:
	if leash <= 0.0:
		return true
	# Под приказом ИИ поводок считается от ЯКОРЯ ОТРЯДА, а не от базы: отряд в
	# походе должен драться с тем, что встретил по дороге. От базы поводок
	# означал бы, что вышедший в набег отряд перестаёт замечать врагов.
	var centre: Vector3 = ai_anchor if ai_led else home
	return centre.distance_to(point) <= leash


## Куда встать по построению. Якорь и разворот берём у командира или у точки,
## которую он назначил приказом.
func _slot_point(commander: Node3D) -> Vector3:
	var anchor: Vector3 = commander.squad_anchor()
	var yaw: float = commander.squad_facing()
	return anchor + Basis(Vector3.UP, yaw) * _formation_offset()


func _formation() -> int:
	var commander := _commander()
	if commander != null:
		return int(commander.squad_formation)
	return ai_formation if ai_led else 0


## Командир бойца. У гарнизона ИИ его нет: он стоит дома, а не ходит за кем-то.
func _commander() -> Node3D:
	var world := get_parent().get_parent()
	if world == null:
		return null
	var boss := world.get_node_or_null("Players/%d" % owner_id)
	# Командиром считаем только ЖИВОГО своей стороны: погибший вожак не водит
	# отряд, а чужой не имеет на него права.
	if boss == null or not ("faction" in boss) or int(boss.faction) != faction:
		return null
	return boss


## Ближайший враг: игрок, боец или караван ЧУЖОЙ СТОРОНЫ.
func _find_target() -> Node3D:
	var best: Node3D = null
	var best_distance := _engage_range()
	var world := get_parent().get_parent()
	if world == null:
		return null

	for player in world.get_node("Players").get_children():
		# В Players может лежать не только персонаж, поэтому проверяем, а не верим.
		if not ("peer_id" in player) or not player.has_method("take_damage"):
			continue
		if not ("faction" in player) or int(player.faction) == faction:
			continue
		if not player.health.alive:
			continue
		var d: float = global_position.distance_to(player.global_position)
		if d < best_distance:
			best_distance = d
			best = player

	for other in get_parent().get_children():
		if other == self or not other.has_method("take_damage"):
			continue
		# У каравана стороны нет, поэтому спрашиваем её у мира по владельцу.
		var other_faction := _faction_of(other)
		if other_faction < 0 or other_faction == faction:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d < best_distance:
			best_distance = d
			best = other
	return best


## Сторона произвольного объекта в Spawned. У бойцов она своя, у каравана
## только владелец — его сторону знает мир.
func _faction_of(node: Node) -> int:
	if "faction" in node:
		return int(node.faction)
	if not ("owner_id" in node):
		return -1
	var world := get_parent().get_parent()
	if world == null or not world.has_method("faction_of"):
		return -1
	return int(world.faction_of(int(node.owner_id)))


## Боевые числа зависят от вида бойца. Вынесено в методы: видов стало три, и
## цепочки тернарников по месту вызова перестали читаться.
func _engage_range() -> float:
	if is_champion:
		return CHAMPION_ENGAGE
	if is_archer:
		return ARCHER_ENGAGE
	return ENGAGE_RANGE


func _move_speed() -> float:
	if is_beast:
		return BEAST_SPEED
	if is_champion:
		return CHAMPION_SPEED
	return BASE_SPEED * FORMATIONS.speed_scale(_formation())


func _strike_damage() -> float:
	if is_beast:
		return BEAST_DAMAGE
	if is_champion:
		return CHAMPION_DAMAGE
	if is_archer:
		return WEAPONS.DAMAGE[WEAPONS.Kind.BOW]
	return STRIKE_DAMAGE


func _strike_cooldown() -> float:
	if is_beast:
		return BEAST_COOLDOWN
	if is_champion:
		return CHAMPION_COOLDOWN
	if is_archer:
		return WEAPONS.COOLDOWN[WEAPONS.Kind.BOW]
	return STRIKE_COOLDOWN


## Куда шагать прямо сейчас, чтобы прийти к цели.
##
## Возвращает саму цель, если она рядом или навигации нет: пусть лучше боец
## пойдёт напрямую, чем встанет.
func _next_step(goal: Vector3) -> Vector3:
	if global_position.distance_to(goal) <= DIRECT_RANGE and _blocked_t < BLOCKED_SECONDS:
		_path.clear()
		_path_goal = Vector3.INF
		return goal

	var nav := _navigation()
	if nav == null or not nav.is_ready():
		return goal

	if _path.is_empty() or _path_index >= _path.size() \
			or _path_goal.distance_to(goal) > REPATH_DISTANCE:
		# Цель может стоять внутри постройки — туда пути нет по определению.
		# Спрашиваем ближайшее проходимое место рядом с ней.
		_path = nav.path_between(global_position, nav.closest_point(goal))
		_path_index = 0
		_path_goal = goal

	while _path_index < _path.size():
		var point: Vector3 = _path[_path_index]
		if Vector2(point.x, point.z).distance_to(Vector2(global_position.x, global_position.z)) \
				> WAYPOINT_RADIUS:
			return point
		_path_index += 1
	return goal


## Заметить, что боец упёрся: хотел идти, но не сдвинулся. Отпускаем вдвое
## быстрее, чем копим, — освободившийся боец должен вернуться в строй сразу, а
## не идти по сетке ещё секунду.
## Заметить, что боец не продвигается к цели.
##
## Прежняя версия ловила только удар в стену НА МЕСТЕ: `is_on_wall()` и скорость
## меньше полуметра. Вдоль скалы боец скользит с полной скоростью, стена под
## этим условием не считается препятствием, счётчик не копится — и путь по карте
## не запрашивается никогда. В живой игре это выглядело так: двое батраков
## вжались в скалу и стоят там, пока смотришь.
##
## Мерить надо не касание, а ПРОДВИЖЕНИЕ: сокращается ли расстояние до цели.
## Скользящий вдоль скалы боец расстояние не сокращает, и это видно сразу.
func _note_blocked(delta: float) -> void:
	if not sync_moving:
		_blocked_t = maxf(0.0, _blocked_t - delta * 2.0)
		return

	var goal: Vector3 = _last_goal
	if not goal.is_finite():
		return
	# Цель сменилась — начинаем мерить заново.
	if not _best_goal.is_finite() or _best_goal.distance_to(goal) > REPATH_DISTANCE:
		_best_goal = goal
		_best_gap = INF

	var gap: float = Vector2(global_position.x, global_position.z).distance_to(
		Vector2(goal.x, goal.z))
	if gap < _best_gap - PROGRESS_STEP:
		_best_gap = gap
		_blocked_t = maxf(0.0, _blocked_t - delta * 2.0)
	else:
		_blocked_t += delta


func _navigation() -> Node:
	var world := get_parent().get_parent()
	if world == null or not ("navigation" in world):
		return null
	return world.navigation


## Физические RID капсулы и своих зон попадания. Нужны стреле, чтобы только что
## выпущенный лучником снаряд не воткнулся в него самого.
func own_collision_rids() -> Array[RID]:
	var rids: Array[RID] = [get_rid()]
	for key in _parts.keys():
		var mesh: Node = _parts[key]
		if mesh == null:
			continue
		for child in mesh.get_children():
			if child is Area3D:
				rids.append((child as Area3D).get_rid())
	return rids


## На каком расстоянии боец достаёт до цели.
##
## Для бойца и игрока это просто длина замаха. Для ПОСТРОЙКИ — плюс её половина:
## расстояние считается до центра, а склад имеет 12 на 10 метров. Боец упирался
## в стену за шесть метров от центра, до замаха ему не хватало трёх с половиной,
## и он стоял так вечно. Отряды не могли разрушить НИ ОДНО здание — ни ИИ, ни
## игрока, — и по коду это не видно: и цель находится, и путь к ней есть.
## Поймал трёхминутный прогон: ИИ раз за разом объявлял набег на склад, который
## не мог сломать.
func _reach_of(target: Node3D) -> float:
	if target == null:
		return STRIKE_RANGE
	if is_archer:
		# Лучник останавливается на дистанции выстрела и дальше не идёт: подойти
		# вплотную для него значит умереть.
		return ARCHER_RANGE

	if target.is_in_group("building") and "kind" in target:
		var size: Vector3 = RES.BUILDING_SIZE.get(int(target.kind), Vector3.ZERO)
		return STRIKE_RANGE + maxf(size.x, size.z) * 0.5
	return STRIKE_RANGE


func _strike(target: Node3D) -> void:
	if _cooldown > 0.0 or target == null:
		return
	_cooldown = _strike_cooldown()
	var point := target.global_position + Vector3.UP * 1.1
	var dir := (target.global_position - global_position).normalized()
	if is_archer:
		_shoot(dir)
		return
	target.take_damage(_strike_damage(), owner_id, "torso", point, dir)


## Выстрел лучника. Стреляем НАСТОЯЩИМ снарядом, тем же, что у игрока: стрела
## летит по дуге, её видно, её можно не догнать — и она может промахнуться.
## Мгновенное попадание было бы дешевле в коде и хуже во всём остальном.
func _shoot(dir: Vector3) -> void:
	var world := get_parent().get_parent()
	if world == null or not world.has_method("spawn_unit_arrow"):
		return
	world.spawn_unit_arrow(global_position + Vector3.UP * 1.4, dir, self)


## Во сколько раз построение режет входящий урон. Единица — защиты нет.
##
## Наружу это нужно арбалету: он «пробивает строй» (GDD 3.1). Защитного
## множителя от снаряжения в игре нет вовсе — снаряжение усиливает бьющего, а не
## защищает битого, — а построение есть, и стена щитов даёт ровно ту защиту,
## против которой болт и задуман.
func defensive_scale(aoe: bool = false) -> float:
	return FORMATIONS.damage_scale(_formation(), aoe)


## Принять урон. Только на хосте. Построение режет или усиливает входящий урон
## (DESIGN_ANSWERS.md, пункт 16).
func take_damage(amount: float, attacker_id: int, _zone: String, point: Vector3, dir: Vector3, aoe := false) -> void:
	if not Net.hosting() or not _alive:
		return
	var scaled: float = amount * FORMATIONS.damage_scale(_formation(), aoe)
	health = maxf(0.0, health - scaled)
	show_hit.rpc(point, dir, scaled)
	if health > 0.0:
		return
	_alive = false
	show_death.rpc(global_position)
	if is_champion:
		print("[распорядитель] пал от руки игрока %d" % attacker_id)
	else:
		print("[отряд] боец игрока %d убит игроком %d" % [owner_id, attacker_id])
	var world := get_parent().get_parent()
	if world != null and world.has_method("report_unit_kill"):
		# Докладываем СВОЮ сторону, а не владельца. У гарнизона и распорядителя
		# владельца нет вовсе (owner_id = 0), и по нему сторона считалась как -1:
		# приказ «убить бойцов злодея» не засчитывал убитых из его гарнизона.
		world.report_unit_kill(attacker_id, faction)
	died_on_server.emit(self)
	queue_free()


## Гибель бойца слышна у всех. Отдельное оповещение нужно потому, что своей
## репликации у смерти нет: боец просто исчезает из дерева, и клиенту не с чем
## связать звук.
@rpc("any_peer", "call_local", "unreliable")
func show_death(point: Vector3) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	Sfx.at(Sfx.Kind.DEATH, point, -2.0)


@rpc("any_peer", "call_local", "unreliable")
func show_hit(point: Vector3, dir: Vector3, amount: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	# В мир, а не в Spawned: за той нодой следит MultiplayerSpawner.
	EFFECTS.blood(get_parent().get_parent(), point, dir, amount)


## Мягкое расталкивание соседей. Чем ближе боец, тем сильнее толчок в сторону.
## Считает хост — как и всё остальное движение юнитов.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in get_parent().get_children():
		if other == self or not other.is_in_group("unit"):
			continue
		var away: Vector3 = global_position - (other as Node3D).global_position
		away.y = 0.0
		var distance := away.length()
		if distance <= 0.01 or distance >= SEPARATION_RADIUS:
			continue
		push += away.normalized() * (1.0 - distance / SEPARATION_RADIUS)
	return push * SEPARATION_FORCE


## Для автопроверок: что сейчас играет и зациклено ли оно.
func animation_state() -> Dictionary:
	if _anim == null:
		return {}
	var current: String = _anim.current_animation
	var anim: Animation = _anim.get_animation(current) if current != "" else null
	return {
		"name": current,
		"playing": _anim.is_playing(),
		"looping": anim != null and anim.loop_mode != Animation.LOOP_NONE,
	}


## Перекрасить модель целиком: зверя в тёмное, распорядителя в красное.
## Идём по дереву — у ассетов Kenney меши лежат на разной глубине.
func _tint(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.95
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_tint(child, color)
