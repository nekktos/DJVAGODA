class_name Player
extends CharacterBody3D
##
## Персонаж игрока: передвижение (Этап 0), бой (Этап 2), ранения (Этап 3).
##
## Авторитетность — разная у разных вещей, и это главное в этом файле:
##   ДВИЖЕНИЕ  считает владелец персонажа и реплицирует трансформ остальным.
##   БОЙ       считает только ХОСТ: клиент шлёт заявку, хост проверяет её по
##             СВОЕЙ копии мира и сам снимает здоровье.
##   РАНЕНИЯ   тоже только хост (см. combat/body.gd).
##
## Модель — Kenney Blocky Characters 2.0 (CC0). Части тела в ней отдельные
## меши, поэтому отрыв конечности это буквально «спрятать ноду и выбросить
## копию», без скелетов и шейдеров. Зоны попадания строятся ИЗ РАЗМЕРОВ самих
## мешей и вешаются на них же — так они едут за анимацией и не зависят от
## захардкоженных чисел.
##

const WEAPONS := preload("res://scripts/combat/weapons.gd")
const ABILITIES := preload("res://scripts/combat/abilities.gd")
const EFFECTS := preload("res://scripts/combat/effects.gd")
const HIT_ZONE := preload("res://scripts/combat/hit_zone.gd")
const WEAPON_VISUAL := preload("res://scripts/combat/weapon_visual.gd")
const MODEL_ANIM := preload("res://scripts/model_anim.gd")
const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const SEVERED_LIMB := preload("res://scenes/SeveredLimb.tscn")

const MODELS := [
	"res://assets/characters/character-a.glb",
	"res://assets/characters/character-b.glb",
	"res://assets/characters/character-c.glb",
]
## Модель Kenney ростом 2.70 м — приводим к человеческим 1.84 м.
const MODEL_SCALE := 0.68

## Имя меша в модели -> ключ зоны попадания.
const PART_ZONES := {
	"head": "head",
	"torso": "torso",
	"arm-left": "arm_l",
	"arm-right": "arm_r",
	"leg-left": "leg_l",
	"leg-right": "leg_r",
}

const ZONE_MULTIPLIERS := {
	"head": 2.0,
	"torso": 1.0,
	"arm_l": 0.7,
	"arm_r": 0.7,
	"leg_l": 0.7,
	"leg_r": 0.7,
}

const SPEED := 6.0
const JUMP_VELOCITY := 5.5
const MOUSE_SENS := 0.0025
const PITCH_MIN := -1.2
const PITCH_MAX := 0.6
const REMOTE_LERP := 15.0

## Слои физики. Капсулы персонажей намеренно вынесены со слоя статичного мира:
## иначе луч стрелы утыкается в капсулу, у которой нет зоны попадания, и урон
## теряется. Снаряды ищут слой мира и слой зон, а капсулы не видят вовсе.
const WORLD_LAYER := 1
const BODY_LAYER := 2
const HITBOX_LAYER := 4

const MAX_ORIGIN_DRIFT := 4.0
const EYE_HEIGHT := 1.5
## Насколько опускаем модель, когда персонаж сидит на земле без ног.
const CRAWL_MODEL_DROP := -0.45

const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-14.0, 2.0, 14.0),
	Vector3(0.0, 2.0, 22.0),
	Vector3(14.0, 2.0, 14.0),
]

signal death_reported(player: Node3D, killer_id: int)
signal projectile_requested(kind: int, origin: Vector3, dir: Vector3, shooter_id: int, gear: int)

@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var sync_weapon: int = 0
## Сколько осталось действовать кличу леса, секунды. Считает и обнуляет хост,
## клиент только читает — и для подсказки в HUD, и чтобы применить прибавку к
## скорости у себя (движение персонажа клиент считает сам, Этап 0).
## Уровень снаряжения, куплен у торговца. Ведёт ХОСТ — иначе клиент выписал бы
## себе эльфийский клинок бесплатно. Действует на любое оружие в руках.
@export var gear_tier: int = 0
## Приказ командира (Этап 9). Ведёт ХОСТ, клиент только показывает.
## -1 — приказа нет.
@export var order_kind: int = -1
@export var order_progress: int = 0
@export var orders_done: int = 0
## Устойчивый идентификатор игрока, к которому привязан прогресс (Этап 10,
## шаг 5). Приезжает в пакете спавна, поэтому одинаков на всех пирах.
var profile_id := ""
## Сколько приказов надо сдать до СЛЕДУЮЩЕГО предложения решающего удара.
## Растёт при провале: погиб по дороге — служи дальше и заслужи снова
## (GDD раздел 8).
@export var final_threshold: int = 5
## Вожак стороны. У злодея это врождённое, страж становится им по повышению
## у NPC на базе (GDD раздел 2.2).
##
## Вожак не возрождается: его смерть окончательна. Обычные эльфы и стражники
## возвращаются в мир как раньше.
@export var is_leader: bool = false
@export var sync_buff_left: float = 0.0
## Остаток отката по каждой способности. Ведёт хост, клиент показывает.
@export var sync_ability_cd: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
## Нужен, чтобы чужие персонажи анимировались: движение у них не считается.
@export var sync_moving: bool = false

## Состояние отряда. Считает и меняет только хост, клиенты читают.
@export var squad_formation: int = 0
@export var squad_hold: bool = false
@export var squad_rally: Vector3 = Vector3.ZERO
@export var squad_rally_yaw: float = 0.0

var peer_id := 1
var spawn_slot := 0
## Сторона игрока. Приезжает данными спавна, поэтому одинакова на всех пирах.
var faction := 0
var control_enabled := true
var scripted_input := {}

static var _bot_mode := -1

var _pitch := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _cooldown_left := 0.0
var _server_cooldown := 0.0
var _swing_left := 0.0
var _bandage_progress := 0.0

@onready var _pivot: Node3D = $CamPivot
@onready var _spring: SpringArm3D = $CamPivot/SpringArm3D
@onready var _camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var _name_tag: Label3D = $NameTag
@onready var health: Node = $Health
@onready var body: Node = $Body
## Запас ресурсов принадлежит ФРАКЦИИ, а не персонажу (Этап 10, шаг 0,
## treasury.gd). Свойство оставлено, чтобы весь код, обращавшийся к
## player.stock, работал без правок: меняется владелец, а не интерфейс.
var stock: Node:
	get:
		var world := get_parent().get_parent() if get_parent() != null else null
		if world == null:
			return null
		var treasury: Node = world.get_node_or_null("Treasury")
		return treasury.of(faction) if treasury != null else null

var _model: Node3D
var _anim: AnimationPlayer
var _parts := {}
var _zones := {}
var _weapon_visual: Node3D
## Какое оружие сейчас показано. Нужно, чтобы перерисовывать при смене — в том
## числе у чужих персонажей, у которых sync_weapon приезжает по сети.
var _weapon_shown := -1
var _current_anim := ""


func _enter_tree() -> void:
	peer_id = str(name).to_int()
	# Рекурсивно — чтобы синхронизатор движения получил того же авторитета.
	set_multiplayer_authority(peer_id)
	# ...а здоровье и ранения возвращаем хосту: рекурсивный вызов забрал и их.
	get_node("ServerSync").set_multiplayer_authority(1)


func _ready() -> void:
	var spawn := faction_spawn()
	global_position = spawn
	sync_position = spawn
	sync_yaw = rotation.y
	sync_weapon = FACTIONS.default_weapon(faction)

	# Внешность выбираем по стороне, чтобы фракции различались в лицо.
	_build_model(clampi(faction, 0, MODELS.size() - 1))
	_spring.add_excluded_object(get_rid())
	_name_tag.text = "%s (%d)" % [FACTIONS.name_of(faction), peer_id]

	var mine := is_multiplayer_authority()
	_camera.current = mine
	_name_tag.visible = not mine
	set_process_unhandled_input(mine)

	body.limb_severed.connect(_on_limb_severed)
	body.state_changed.connect(_refresh_posture)

	if Net.hosting():
		health.died.connect(_on_died_on_server)


func _build_model(slot: int) -> void:
	var packed: PackedScene = load(MODELS[slot % MODELS.size()])
	_model = packed.instantiate()
	_model.name = "Model"
	_model.scale = Vector3.ONE * MODEL_SCALE
	# Модель Kenney смотрит в +Z, а игра считает передом -Z (движение, прицел и
	# разворот по atan2(-dir.x, -dir.z) — всё в -Z). Без этого разворота персонаж
	# бежит задом наперёд, а камера из-за спины смотрит ему в лицо.
	_model.rotation.y = PI
	add_child(_model)

	_anim = _find_node(_model, AnimationPlayer) as AnimationPlayer
	# Без этого ходьба играется один раз и персонаж дальше едет в позе
	# последнего кадра — glTF приезжает с LOOP_NONE.
	MODEL_ANIM.make_looping(_anim)
	for part_name in PART_ZONES.keys():
		var mesh := _find_by_name(_model, part_name) as MeshInstance3D
		if mesh == null:
			push_warning("В модели нет части «%s»" % part_name)
			continue
		var key: String = PART_ZONES[part_name]
		_parts[key] = mesh
		_zones[key] = _attach_zone(mesh, key)

	_refresh_weapon_visual()
	_play("idle")


## Зона попадания строится из размеров самого меша и вешается на него же —
## общий помощник с юнитами, см. hit_zone.gd::attach.
func _attach_zone(mesh: MeshInstance3D, key: String) -> Area3D:
	return HIT_ZONE.attach(mesh, key, ZONE_MULTIPLIERS.get(key, 1.0), HITBOX_LAYER)


func _find_node(node: Node, type) -> Node:
	if is_instance_of(node, type):
		return node
	for child in node.get_children():
		var found := _find_node(child, type)
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


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not control_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
		_pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if Net.hosting():
		_server_cooldown = maxf(0.0, _server_cooldown - delta)
		_tick_abilities(delta)

	_swing_left = maxf(0.0, _swing_left - delta)
	_refresh_weapon_visual()

	if is_multiplayer_authority():
		var inp := _gather_input()
		apply_input(inp, delta)
		_update_attack(delta)
		_update_abilities()
		_update_bandage(delta, inp)
		sync_position = global_position
		sync_yaw = rotation.y
		sync_moving = Vector2(velocity.x, velocity.z).length() > 0.4
	else:
		var t := clampf(delta * REMOTE_LERP, 0.0, 1.0)
		global_position = global_position.lerp(sync_position, t)
		rotation.y = lerp_angle(rotation.y, sync_yaw, t)

	_update_animation()


## Снимок ввода за кадр. Отдельный слой специально: когда авторитет над
## движением переедет на хост, сюда встанет отправка инпута по сети, а
## apply_input() будет вызываться на хосте без изменений.
func _gather_input() -> Dictionary:
	if not scripted_input.is_empty():
		return scripted_input
	if not control_enabled:
		return {"move": Vector2.ZERO, "jump": false}
	if _is_bot():
		var t := Time.get_ticks_msec() / 1000.0
		return {"move": Vector2(cos(t), sin(t)), "jump": false}
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return {"move": Vector2.ZERO, "jump": false}
	return {
		"move": Input.get_vector("move_left", "move_right", "move_forward", "move_back"),
		"jump": Input.is_action_just_pressed("jump"),
		"bandage": Input.is_action_pressed("bandage"),
	}


## Чистая симуляция персонажа от снимка ввода. Не читает Input напрямую.
## Скорость и прыжок берутся у тела: без ноги персонаж ползёт, с мастерским
## протезом прыгает выше живого (GDD раздел 4).
func apply_input(inp: Dictionary, delta: float) -> void:
	var move: Vector2 = inp.get("move", Vector2.ZERO)
	var jump: bool = inp.get("jump", false)

	var speed: float = body.move_speed(SPEED) * buff_speed_scale()
	var jump_power: float = body.jump_velocity(JUMP_VELOCITY)

	if is_on_floor():
		if jump and jump_power > 0.0:
			velocity.y = jump_power
	else:
		velocity.y -= _gravity * delta

	var dir := (transform.basis * Vector3(move.x, 0.0, move.y))
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	move_and_slide()


# --- анимация и поза -------------------------------------------------------

func _play(anim_name: String, force := false) -> void:
	if _anim == null or (anim_name == _current_anim and not force):
		return
	if not _anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	_anim.play(anim_name)


func _update_animation() -> void:
	if _anim == null:
		return
	if not health.alive:
		_play("die")
		return
	if _swing_left > 0.0:
		return
	var moving := sync_moving if not is_multiplayer_authority() else (
		Vector2(velocity.x, velocity.z).length() > 0.4
	)
	if body.in_wheelchair:
		_play("wheelchair-move-forward" if moving else "wheelchair-sit")
	elif body.is_crawling():
		_play("sit")
	else:
		_play("walk" if moving else "idle")


## Поза меняется вместе с состоянием тела.
##
## Отдельной анимации ползания в паке Kenney нет. Готовая CC0-библиотека с
## ползанием существует (Quaternius Universal Animation Library), но она сделана
## под скелетный гуманоидный риг, а у Kenney скелета нет — там анимируются
## трансформы отдельных нод. Взять её значит сменить персонажа и переделать
## расчленение на сжатие костей, то есть переписать интеграцию Этапа 3.
## Поэтому безногого показываем сидящим на земле — поза "sit" из того же пака.
func _refresh_posture() -> void:
	if _model == null:
		return
	if body.is_crawling() and not body.in_wheelchair:
		_model.position.y = CRAWL_MODEL_DROP
	else:
		_model.position.y = 0.0
	_play(_current_anim, true)


# --- бой: сторона клиента -------------------------------------------------

func _update_attack(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if not control_enabled or not health.alive:
		return

	# Оружие переключаем только среди разрешённого стороне: у эльфов и стражи
	# нет атакующей магии (DESIGN_ANSWERS.md, пункт 18).
	if Input.is_action_just_pressed("weapon_1"):
		_select_weapon(WEAPONS.Kind.SWORD)
	elif Input.is_action_just_pressed("weapon_2"):
		_select_weapon(WEAPONS.Kind.BOW)
	elif Input.is_action_just_pressed("weapon_3"):
		_select_weapon(WEAPONS.Kind.SPELL)

	var wants: bool = scripted_input.get("attack", false)
	if not wants and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		wants = Input.is_action_pressed("attack")
	if not wants or _cooldown_left > 0.0:
		return
	if not _weapon_allowed(sync_weapon):
		return

	_cooldown_left = (WEAPONS.COOLDOWN[sync_weapon] * body.attack_speed_scale()
		* buff_attack_scale() * WEAPONS.gear_cooldown(gear_tier))
	_swing_left = 0.45
	_play("attack-melee-right" if sync_weapon == WEAPONS.Kind.SWORD else "holding-right-shoot", true)

	# Замах рисуем сразу, чтобы удар ощущался мгновенным. Урон при этом
	# случится только когда его подтвердит хост.
	# Хост бьёт напрямую: rpc_id самому себе Godot запрещает, а делать RPC
	# call_local ради этого нельзя — тогда удар исполнялся бы и на клиенте.
	if Net.hosting():
		request_attack(sync_weapon, aim_origin(), aim_direction())
	else:
		request_attack.rpc_id(1, sync_weapon, aim_origin(), aim_direction())


## Деревянный протез руки годится только для ближнего боя: лук и заклинания
## требуют полноценной кисти (GDD раздел 4 — «ограничены действия»).
func _weapon_allowed(kind: int) -> bool:
	if not FACTIONS.allows_weapon(faction, kind):
		return false
	if kind == WEAPONS.Kind.SWORD:
		return body.can_attack_melee()
	return body.can_attack_ranged()


func aim_origin() -> Vector3:
	return global_position + Vector3.UP * EYE_HEIGHT


func aim_direction() -> Vector3:
	var b := Basis(Vector3.UP, rotation.y) * Basis(Vector3.RIGHT, _pitch)
	return -b.z


# --- способности поддержки (Этап 8) ---------------------------------------

## Множитель скорости от клича леса. Клиент считает движение сам, поэтому
## читает реплицированный остаток и применяет прибавку у себя.
func buff_speed_scale() -> float:
	return ABILITIES.RALLY_SPEED_SCALE if sync_buff_left > 0.0 else 1.0


## Множитель отката атак от клича: меньше единицы — бьют чаще.
func buff_attack_scale() -> float:
	return ABILITIES.RALLY_ATTACK_SCALE if sync_buff_left > 0.0 else 1.0


func ability_ready(kind: int) -> bool:
	if kind < 0 or kind >= sync_ability_cd.size():
		return false
	return sync_ability_cd[kind] <= 0.0


## Откаты и бафф тикают ТОЛЬКО на хосте, клиентам значения приезжают.
func _tick_abilities(delta: float) -> void:
	for i in sync_ability_cd.size():
		if sync_ability_cd[i] > 0.0:
			sync_ability_cd[i] = maxf(0.0, sync_ability_cd[i] - delta)
	if sync_buff_left > 0.0:
		sync_buff_left = maxf(0.0, sync_buff_left - delta)


## Ввод. Клиент только просит — применяет способность хост.
func _update_abilities() -> void:
	if not control_enabled or not health.alive:
		return

	var wanted := -1
	if Input.is_action_just_pressed("ability_1"):
		wanted = ABILITIES.Kind.HEAL
	elif Input.is_action_just_pressed("ability_2"):
		wanted = ABILITIES.Kind.RALLY
	elif Input.is_action_just_pressed("ability_3"):
		wanted = ABILITIES.Kind.SUMMON
	if wanted < 0 and scripted_input.has("ability"):
		# Автопроверки просят способность через сценарный ввод. Забираем сразу:
		# иначе она сработала бы каждый кадр, пока ключ лежит в словаре.
		wanted = int(scripted_input["ability"])
		scripted_input.erase("ability")
	if wanted < 0:
		return

	if not FACTIONS.allows_ability(faction, wanted) or not ability_ready(wanted):
		return

	if Net.hosting():
		request_ability(wanted)
	else:
		request_ability.rpc_id(1, wanted)


## Заявка на способность. Проверяет и исполняет ХОСТ — как и урон.
@rpc("any_peer", "reliable")
func request_ability(kind: int) -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner():
		push_warning("Пир пытался колдовать чужим персонажем %d" % peer_id)
		return
	if not health.alive or kind < 0 or kind >= ABILITIES.COUNT:
		return
	if not FACTIONS.allows_ability(faction, kind):
		return
	if sync_ability_cd[kind] > 0.0:
		return
	# Способности требуют полноценной руки — как лук (GDD раздел 4).
	if not body.can_attack_ranged():
		return

	var done := false
	match kind:
		ABILITIES.Kind.HEAL:
			done = _server_cast_heal()
		ABILITIES.Kind.RALLY:
			done = _server_cast_rally()
		ABILITIES.Kind.SUMMON:
			done = _server_cast_summon()
	if not done:
		return

	sync_ability_cd[kind] = ABILITIES.cooldown_of(kind)
	ability_cast.rpc(kind, global_position)


## Лечение: поднимает здоровье и останавливает кровотечение себе и своим рядом.
##
## Отрубленное НЕ отрастает — на то есть протезы (GDD раздел 4). Магия закрывает
## ровно то, что GDD называет «вылечат — жив».
func _server_cast_heal() -> bool:
	var healed := 0
	for target in _allies_in_range(ABILITIES.range_of(ABILITIES.Kind.HEAL)):
		var restored := false
		if target.health.current < target.health.MAX_HEALTH:
			target.health.current = minf(
				target.health.MAX_HEALTH,
				target.health.current + ABILITIES.HEAL_AMOUNT
			)
			restored = true
		if target.body.bleeding:
			target.body.bleeding = false
			restored = true
		if restored:
			healed += 1
	return healed > 0


## Клич леса: временно ускоряет своих в радиусе и учащает их удары.
func _server_cast_rally() -> bool:
	var touched := 0
	for target in _allies_in_range(ABILITIES.range_of(ABILITIES.Kind.RALLY)):
		target.sync_buff_left = ABILITIES.RALLY_DURATION
		touched += 1
	return touched > 0


## Призыв волка. Волк — тот же боец, что и мечник злодея, но зверь: быстрее,
## слабее и живёт минуту. Ходит за призвавшим и бьёт чужих — логика следования
## и поиска цели у бойцов уже есть, дублировать её незачем.
func _server_cast_summon() -> bool:
	var world := get_parent().get_parent()
	if not world.has_method("spawn_unit"):
		return false

	var pack: Array = world.units_of(peer_id)
	var beasts := 0
	for unit in pack:
		if "is_beast" in unit and unit.is_beast:
			beasts += 1
	if beasts >= ABILITIES.SUMMON_LIMIT:
		return false

	var offset := Basis(Vector3.UP, rotation.y) * Vector3(0.0, 0.0, -ABILITIES.range_of(ABILITIES.Kind.SUMMON))
	return world.spawn_unit(peer_id, pack.size(), global_position + offset, true) != null


## Свои рядом: сам эльф и игроки его стороны. Бойцы лечению не подлежат — у них
## нет ни ранений, ни кровотечения, только здоровье.
func _allies_in_range(radius: float) -> Array:
	var result := []
	for other in get_parent().get_children():
		if not ("faction" in other) or not ("health" in other):
			continue
		if int(other.faction) != faction or not other.health.alive:
			continue
		if global_position.distance_to(other.global_position) > radius:
			continue
		result.append(other)
	return result


## Показ вспышки. На игру не влияет — только картинка.
@rpc("any_peer", "call_local", "unreliable")
func ability_cast(kind: int, point: Vector3) -> void:
	if not _sender_is_host():
		return
	EFFECTS.druid(_effects_root(), point, kind)


## Перевязка: держать клавишу, стоя на месте. Расходует бинт (DESIGN_ANSWERS,
## пункт 11). Прогресс считает клиент, но сам факт перевязки — хост.
func _update_bandage(delta: float, inp: Dictionary) -> void:
	if not body.bleeding or not control_enabled:
		_bandage_progress = 0.0
		return
	var holding: bool = inp.get("bandage", false)
	var still: bool = Vector2(velocity.x, velocity.z).length() < 0.3
	if not holding or not still:
		_bandage_progress = 0.0
		return
	_bandage_progress += delta
	if _bandage_progress < body.BANDAGE_TIME:
		return
	_bandage_progress = 0.0
	if Net.hosting():
		request_bandage()
	else:
		request_bandage.rpc_id(1)


func bandage_progress() -> float:
	return clampf(_bandage_progress / body.BANDAGE_TIME, 0.0, 1.0)


# --- бой: сторона хоста ---------------------------------------------------

@rpc("any_peer", "reliable")
func request_bandage() -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner():
		return
	body.apply_bandage()


## Заявка на удар. Исполняется ТОЛЬКО на хосте.
@rpc("any_peer", "reliable")
func request_attack(kind: int, origin: Vector3, dir: Vector3) -> void:
	if not Net.hosting():
		return

	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender != peer_id:
		push_warning("Пир %d пытался ударить персонажем %d" % [sender, peer_id])
		return

	if not health.alive or _server_cooldown > 0.0:
		return
	if not WEAPONS.COOLDOWN.has(kind):
		return
	if not _weapon_allowed(kind):
		return
	# Позицию берём СВОЮ, а не присланную: клиент сообщает только намерение.
	var host_origin := aim_origin()
	if origin.distance_to(host_origin) > MAX_ORIGIN_DRIFT:
		push_warning("Заявка на удар от %d отклонена: точка удара разошлась на %.1f м"
			% [peer_id, origin.distance_to(host_origin)])
		return

	_server_cooldown = (WEAPONS.COOLDOWN[kind] * body.attack_speed_scale()
		* buff_attack_scale() * WEAPONS.gear_cooldown(gear_tier))
	var aim := dir.normalized()
	if aim.length() < 0.5:
		return

	if kind == WEAPONS.Kind.SWORD:
		# Тем же ударом рубим дерево и бьём камень: отдельной кнопки добычи нет.
		if not _server_try_harvest(aim):
			_server_swing_sword(aim)
	else:
		# Снаряд создаёт и ведёт мир — он владеет спавнером снарядов.
		projectile_requested.emit(kind, host_origin, aim, peer_id, gear_tier)


## Хост разрешает удар мечом: ищет зоны попадания в секторе перед персонажем.
func _server_swing_sword(aim: Vector3) -> void:
	var origin := aim_origin()
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = WEAPONS.SWORD_RANGE
	query.shape = sphere
	query.transform = Transform3D(Basis(), origin)
	query.collision_mask = HITBOX_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false

	# По каждой цели бьём один раз — той зоной, что даёт больший множитель.
	var best := {}
	for hit in space.intersect_shape(query, 24):
		var zone: Area3D = hit.get("collider") as Area3D
		if zone == null or not zone.has_method("owner_character"):
			continue
		var target: Node3D = zone.owner_character()
		if target == null or target == self:
			continue
		var to_target := target.global_position + Vector3.UP * 1.0 - origin
		if to_target.length() > 0.01 and aim.angle_to(to_target.normalized()) > WEAPONS.SWORD_HALF_ANGLE:
			continue
		var prev: Area3D = best.get(target)
		if prev == null or zone.damage_multiplier > prev.damage_multiplier:
			best[target] = zone

	for target in best.keys():
		var zone: Area3D = best[target]
		var damage: float = (WEAPONS.DAMAGE[WEAPONS.Kind.SWORD] * zone.damage_multiplier
			* WEAPONS.gear_damage(gear_tier))
		target.take_damage(damage, peer_id, zone.zone, zone.global_position, aim)


## Принять урон. Вызывается ТОЛЬКО на хосте (из оружия или снаряда).
func take_damage(amount: float, attacker_id: int, zone: String, point: Vector3, dir: Vector3, _aoe := false) -> void:
	if not Net.hosting():
		return
	var dealt: float = health.apply_damage(amount, attacker_id)
	if dealt <= 0.0:
		return
	# Судьбу конечности считает тело — отдельно от общего здоровья.
	body.register_hit(zone, dealt)
	show_hit.rpc(point, dir, dealt, zone)


## Прислать может только хост — проверяем отправителя, а не полагаемся на
## режим "authority": авторитет этой ноды принадлежит владельцу персонажа,
## а вызывает хост.
@rpc("any_peer", "call_local", "unreliable")
func show_hit(point: Vector3, dir: Vector3, amount: float, zone: String) -> void:
	if not _sender_is_host():
		return
	EFFECTS.blood(_effects_root(), point, dir, amount)


## Вызов пришёл от хоста? Локальный вызов даёт 0, удалённый от хоста — 1.
## Куда класть партиклы. НЕ в Players и НЕ в Spawned: за первой ходят юниты в
## поиске целей, за второй следит MultiplayerSpawner. Обе ноды должны содержать
## только то, что в них по смыслу лежит.
func _effects_root() -> Node:
	return get_parent().get_parent()


func _sender_is_host() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	return sender == 0 or sender == 1


func _on_died_on_server(killer_id: int) -> void:
	death_reported.emit(self, killer_id)


# --- ранения: визуал ------------------------------------------------------

## Реагируем на РЕПЛИЦИРОВАННОЕ состояние, поэтому отрыв виден одинаково на
## хосте и на клиентах, и отдельной сетевой команды для этого не нужно.
func _on_limb_severed(limb: int) -> void:
	var key: String = body.LIMB_KEYS[limb]
	var mesh: MeshInstance3D = _parts.get(key)
	if mesh == null:
		return

	var at := mesh.global_transform
	mesh.visible = false
	var zone: Area3D = _zones.get(key)
	if zone != null:
		zone.collision_layer = 0

	# Кровь и сама оторванная часть, которая падает и остаётся лежать.
	EFFECTS.blood(_effects_root(), at.origin, Vector3.UP, 80.0)
	var piece: Node3D = SEVERED_LIMB.instantiate()
	# Кладём прямо в мир, а не в Spawned: за той нодой следит MultiplayerSpawner,
	# а оторванная часть — локальный визуал, её каждый пир создаёт себе сам по
	# реплицированному состоянию тела.
	get_parent().get_parent().add_child(piece)
	piece.setup(mesh.mesh, at, MODEL_SCALE)
	_refresh_posture()


## Вернуть все части на место. Зовётся при респавне.
func restore_body() -> void:
	for key in _parts.keys():
		var mesh: MeshInstance3D = _parts[key]
		mesh.visible = true
		var zone: Area3D = _zones.get(key)
		if zone != null:
			zone.collision_layer = HITBOX_LAYER
	_refresh_posture()


# --- служебное ------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func set_dead(dead: bool) -> void:
	if not _sender_is_host():
		return
	control_enabled = not dead
	for key in _zones.keys():
		(_zones[key] as Area3D).collision_layer = 0 if dead else HITBOX_LAYER
	set_collision_layer_value(2, not dead)
	if dead:
		_play("die", true)
	else:
		velocity = Vector3.ZERO
		restore_body()
		_play("idle", true)


func respawn_at_slot() -> void:
	teleport.rpc(faction_spawn())


@rpc("any_peer", "call_local", "reliable")
func teleport(point: Vector3) -> void:
	if not _sender_is_host():
		return
	global_position = point
	sync_position = point
	velocity = Vector3.ZERO


func set_view_active(on: bool) -> void:
	if is_multiplayer_authority():
		_camera.current = on


## Оружие висит на правой руке: едет с ней по анимации и исчезает вместе с
## оторванной рукой. Точку хвата считает weapon_visual по габаритам руки.
func _refresh_weapon_visual() -> void:
	if _weapon_shown == sync_weapon:
		return
	_weapon_shown = sync_weapon
	_weapon_visual = WEAPON_VISUAL.attach(_parts.get("arm_r"), sync_weapon, _weapon_visual)


static func _is_bot() -> bool:
	if _bot_mode == -1:
		var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
		_bot_mode = 1 if args.has("--bot") else 0
	return _bot_mode == 1


## Физические RID капсулы и всех своих зон попадания. Нужны снаряду, чтобы
## только что выпущенная стрела не воткнулась в самого стрелка.
func own_collision_rids() -> Array[RID]:
	var rids: Array[RID] = [get_rid()]
	for key in _zones.keys():
		var zone: Area3D = _zones[key]
		if zone != null:
			rids.append(zone.get_rid())
	return rids


# --- верстак: протезы и коляска -------------------------------------------

## Стоит ли персонаж у верстака. Клиент по этому решает, показывать ли панель,
## хост — можно ли выдать протез.
func at_workbench() -> bool:
	var world := get_parent().get_parent()
	if world == null or not world.has_method("is_at_workbench"):
		return false
	return world.is_at_workbench(global_position)


func ask_prosthetic(new_tier: int) -> void:
	if Net.hosting():
		request_prosthetic(new_tier)
	else:
		request_prosthetic.rpc_id(1, new_tier)


func ask_wheelchair(on: bool) -> void:
	if Net.hosting():
		request_wheelchair(on)
	else:
		request_wheelchair.rpc_id(1, on)


## Поставить протезы на все оторванные конечности. Только на хосте.
##
## Оплата ресурсами (Этап 4): деревянный крафтится из древесины, кованый и
## мастерский стоят золота и железа. Цена — за комплект, а не за конечность.
@rpc("any_peer", "reliable")
func request_prosthetic(new_tier: int) -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner():
		return
	if not health.alive:
		return
	if not RES.PROSTHETIC_COST.has(new_tier):
		return
	# Деревянный протез крафтится ГДЕ УГОДНО: он и по GDD «крафтится сам» из
	# древесины. Верстак нужен только для кованого и мастерского.
	#
	# Без этого послабления ранения, пережившие респавн (шаг 1), означали бы
	# ползти 6-8 минут через полкарты к единственному верстаку — самый вероятный
	# способ превратить смерть в «умер и вышел из игры».
	if new_tier > 1 and not at_workbench():
		return

	# Считаем, есть ли что менять, до списания: платить за пустой заказ нельзя.
	var targets := []
	for limb in body.LIMB_KEYS.size():
		if body.is_severed(limb) and body.tier(limb) != new_tier:
			targets.append(limb)
	if targets.is_empty():
		return

	var cost: Array = RES.PROSTHETIC_COST[new_tier]
	if not stock.spend(cost):
		push_warning("Игроку %d не хватает ресурсов на протез уровня %d" % [peer_id, new_tier])
		return
	for limb in targets:
		body.grant_prosthetic(limb, new_tier)


@rpc("any_peer", "reliable")
func request_wheelchair(on: bool) -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner():
		return
	if not health.alive or not at_workbench():
		return
	body.set_wheelchair(on)


## Заявку прислал владелец этого персонажа, а не посторонний пир?
func _sender_is_owner() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	return sender == peer_id


# --- торговля (Этап 8) -----------------------------------------------------

## Игрок стоит у лавки? Клиент считает это же значение, чтобы показать подсказку,
## но решает всё равно хост — иначе покупали бы с другого конца карты.
func at_trader() -> bool:
	var world := get_parent().get_parent()
	if world == null or not world.has_method("is_at_trader"):
		return false
	return world.is_at_trader(global_position)


## Кому принадлежит лавка. Она стоит в поселении эльфов, значит хозяева — они
## (GDD раздел 9.2: цена зависит от отношения покупателя к владельцу лавки).
func trader_faction() -> int:
	return FACTIONS.Kind.ELVES


func _diplomacy() -> Node:
	var world := get_parent().get_parent()
	return world.get_node_or_null("Diplomacy") if world != null else null


## Обслужит ли лавка этого покупателя. Ниже порога вражды — нет.
func trade_allowed() -> bool:
	var dip := _diplomacy()
	return dip == null or dip.trade_allowed(faction, trader_faction())


## Цена с учётом отношения к хозяевам лавки.
func trade_cost(base: Array) -> Array:
	var dip := _diplomacy()
	return base if dip == null else dip.adjust_cost(base, faction, trader_faction())


## Цена следующего уровня снаряжения. Пустой массив — покупать больше нечего.
func next_gear_cost() -> Array:
	var next := gear_tier + 1
	if not RES.GEAR_COST.has(next):
		return []
	return trade_cost(RES.GEAR_COST[next])


func bandage_cost() -> Array:
	return trade_cost(RES.BANDAGE_COST)


func ask_trade(what: int) -> void:
	if Net.hosting():
		request_trade(what)
	else:
		request_trade.rpc_id(1, what)


## Покупка у торговца. Считает и списывает ХОСТ.
@rpc("any_peer", "reliable")
func request_trade(what: int) -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner():
		push_warning("Пир пытался торговать чужим персонажем %d" % peer_id)
		return
	if not health.alive or not at_trader():
		return

	match what:
		RES.Trade.BANDAGES:
			_server_buy_bandages()
		RES.Trade.GEAR:
			_server_buy_gear()


func _server_buy_bandages() -> void:
	if body.bandages >= RES.BANDAGE_LIMIT:
		return
	if not trade_allowed():
		push_warning("Лавка не обслуживает игрока %d: война" % peer_id)
		return
	if not stock.spend(bandage_cost()):
		return
	body.bandages = mini(RES.BANDAGE_LIMIT, body.bandages + RES.BANDAGE_PACK)
	print("[торг] игрок %d купил бинты, стало %d" % [peer_id, body.bandages])


func _server_buy_gear() -> void:
	var next := gear_tier + 1
	if not RES.GEAR_COST.has(next):
		return
	if not trade_allowed():
		push_warning("Лавка не обслуживает игрока %d: война" % peer_id)
		return
	if not stock.spend(next_gear_cost()):
		return
	gear_tier = next
	print("[торг] игрок %d купил снаряжение: %s" % [peer_id, WEAPONS.gear_name(gear_tier)])


# --- добыча ресурсов ------------------------------------------------------

## Удар пришёлся по источнику ресурсов? Тогда это добыча, а не бой.
## Считает ТОЛЬКО хост: он же решает, сколько начислить и исчерпался ли источник.
##
## Добыча руками — решение из DESIGN_ANSWERS.md, пункт 14. Наёмные рабочие
## появятся позже, когда будет на что их нанимать.
func _server_try_harvest(aim: Vector3) -> bool:
	var origin := aim_origin()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * RES.HARVEST_RANGE)
	query.collision_mask = WORLD_LAYER
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var target := hit.get("collider") as Node
	if target == null or not target.is_in_group("harvestable"):
		return false

	var kind: int = int(target.get_meta("resource", RES.Kind.WOOD))
	var taken: int = stock.add(kind, RES.YIELD_PER_HIT)
	harvested.rpc(hit.get("position", origin), kind, taken)

	# Дерево из forest.gd адресуется индексом, а не путём ноды: объёмное дерево
	# существует только пока рядом кто-то есть, и путь неустойчив.
	var tree: int = int(target.get_meta("tree", -1))
	if tree >= 0:
		var forest: Node = get_parent().get_parent().forest
		if forest.hit_tree(tree) <= 0:
			forest.fell_tree.rpc(tree)
		return true

	var left: int = int(target.get_meta("hits_left", 1)) - 1
	target.set_meta("hits_left", left)
	if left <= 0:
		# Источник исчерпан. Убираем его у всех: остальная геометрия мира
		# строится одинаково на каждом пире, поэтому путь ноды совпадает.
		deplete_source.rpc(target.get_path())
	return true


## Отрисовка добычи и подсказка в лог. На игру не влияет.
@rpc("any_peer", "call_local", "unreliable")
func harvested(point: Vector3, kind: int, taken: int) -> void:
	if not _sender_is_host():
		return
	if taken <= 0:
		return
	EFFECTS.chips(_effects_root(), point, kind)


@rpc("any_peer", "call_local", "reliable")
func deplete_source(path: NodePath) -> void:
	if not _sender_is_host():
		return
	var node := get_node_or_null(path)
	if node != null:
		node.queue_free()


# --- стройка --------------------------------------------------------------

const BUILD_CONTROLLER := preload("res://scripts/economy/build_controller.gd")


func ask_build(building_kind: int, point: Vector3) -> void:
	if Net.hosting():
		request_build(building_kind, point)
	else:
		request_build.rpc_id(1, building_kind, point)


## Заявка на постройку. Хост проверяет ВСЁ заново по своей копии мира: призрак
## у клиента — только подсказка, доверять ему нельзя.
@rpc("any_peer", "reliable")
func request_build(building_kind: int, point: Vector3) -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner() or not health.alive:
		return
	if not RES.BUILDING_COST.has(building_kind):
		return

	var cost: Array = RES.BUILDING_COST[building_kind]
	if not stock.can_afford(cost):
		push_warning("Игроку %d не хватает ресурсов на %s" % [peer_id, RES.BUILDING_NAMES[building_kind]])
		return
	if not BUILD_CONTROLLER.is_spot_buildable(self, point, building_kind):
		push_warning("Игрок %d выбрал негодное место под %s" % [peer_id, RES.BUILDING_NAMES[building_kind]])
		return

	if not stock.spend(cost):
		return
	var world := get_parent().get_parent()
	world.spawn_building(building_kind, point, peer_id)


# --- караван и подбор груза -----------------------------------------------

## Сколько караванов игрок может держать в пути одновременно.
const MAX_CARAVANS := 2
## Дальше этого точку маршрута не принимаем — защита от мусора в заявке.
const ROUTE_BOUND := 640.0


func ask_send_caravan(points: PackedVector3Array) -> void:
	if Net.hosting():
		request_send_caravan(points)
	else:
		request_send_caravan.rpc_id(1, points)


## Заявка на отправку каравана. Хост дорисовывает начало и конец сам: караван
## всегда выходит от склада и всегда едет к шахте. Игрок решает только путь
## между ними (GDD раздел 8.2).
@rpc("any_peer", "reliable")
func request_send_caravan(points: PackedVector3Array) -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner() or not health.alive:
		return

	var world := get_parent().get_parent()
	var storage: Node3D = world.storage_of(peer_id)
	if storage == null:
		push_warning("Игроку %d некуда возвращать караван: нет достроенного склада" % peer_id)
		return
	if world.caravans_of(peer_id).size() >= MAX_CARAVANS:
		push_warning("У игрока %d уже максимум караванов в пути" % peer_id)
		return

	var route := PackedVector3Array()
	route.append(storage.global_position)
	for point in points:
		if absf(point.x) > ROUTE_BOUND or absf(point.z) > ROUTE_BOUND:
			push_warning("Точка маршрута игрока %d вне карты, заявка отклонена" % peer_id)
			return
		route.append(point)
	route.append(world.mine.global_position)

	world.spawn_caravan(route, peer_id)


func ask_collect_loot() -> void:
	if Net.hosting():
		request_collect_loot()
	else:
		request_collect_loot.rpc_id(1)


## Подобрать ближайшую кучу. Расстояние проверяет хост, а не клиент.
@rpc("any_peer", "reliable")
func request_collect_loot() -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner() or not health.alive:
		return
	for node in get_tree().get_nodes_in_group("loot"):
		var pile := node as Node3D
		if pile == null:
			continue
		if pile.collect(self) > 0:
			return


## Есть ли рядом куча, которую можно подобрать. Для подсказки в HUD.
func loot_nearby() -> Node3D:
	for node in get_tree().get_nodes_in_group("loot"):
		var pile := node as Node3D
		if pile != null and pile.global_position.distance_to(global_position) <= pile.PICKUP_RANGE:
			return pile
	return null


# --- отряд и построения ---------------------------------------------------

const FORMATIONS := preload("res://scripts/units/formations.gd")


## Куда равняется отряд. В режиме следования — на командира, после приказа —
## на назначенную точку.
func squad_anchor() -> Vector3:
	return squad_rally if squad_hold else global_position


func squad_facing() -> float:
	return squad_rally_yaw if squad_hold else rotation.y


func ask_formation(kind: int) -> void:
	if Net.hosting():
		request_formation(kind)
	else:
		request_formation.rpc_id(1, kind)


func ask_squad_move(point: Vector3) -> void:
	if Net.hosting():
		request_squad_move(point)
	else:
		request_squad_move.rpc_id(1, point)


func ask_squad_follow() -> void:
	if Net.hosting():
		request_squad_follow()
	else:
		request_squad_follow.rpc_id(1)


func ask_train_unit() -> void:
	if Net.hosting():
		request_train_unit()
	else:
		request_train_unit.rpc_id(1)


@rpc("any_peer", "reliable")
func request_formation(kind: int) -> void:
	if not Net.hosting() or not _sender_is_owner():
		return
	squad_formation = clampi(kind, 0, FORMATIONS.NAMES.size() - 1)


## Приказ «идти туда». Разворот берём по направлению марша, чтобы отряд
## пришёл лицом вперёд, а не спиной.
@rpc("any_peer", "reliable")
func request_squad_move(point: Vector3) -> void:
	if not Net.hosting() or not _sender_is_owner():
		return
	if absf(point.x) > ROUTE_BOUND or absf(point.z) > ROUTE_BOUND:
		return
	var march := point - squad_anchor()
	march.y = 0.0
	squad_rally = point
	if march.length() > 0.5:
		var dir := march.normalized()
		squad_rally_yaw = atan2(-dir.x, -dir.z)
	squad_hold = true


@rpc("any_peer", "reliable")
func request_squad_follow() -> void:
	if not Net.hosting() or not _sender_is_owner():
		return
	squad_hold = false


## Нанять мечника. Нужна достроенная казарма и ресурсы (Этап 4).
@rpc("any_peer", "reliable")
func request_train_unit() -> void:
	if not Net.hosting() or not _sender_is_owner():
		return
	if not health.alive:
		return
	var world := get_parent().get_parent()
	var barracks: Node3D = world.barracks_of(peer_id)
	if barracks == null:
		push_warning("Игроку %d негде нанимать: нет достроенной казармы" % peer_id)
		return
	var squad: Array = world.units_of(peer_id)
	if squad.size() >= RES.SQUAD_LIMIT:
		push_warning("У игрока %d отряд уже полон" % peer_id)
		return
	if not stock.spend(RES.UNIT_COST):
		push_warning("Игроку %d не хватает ресурсов на мечника" % peer_id)
		return
	# Разводим по спирали: если спавнить всех в одну точку, капсулы влезают друг
	# в друга и CharacterBody3D потом не может их расцепить.
	var index: int = squad.size()
	var angle: float = float(index) * 0.9
	var radius: float = 3.0 + float(index) * 0.45
	var offset := Vector3(cos(angle) * radius, 1.0, 9.0 + sin(angle) * radius)
	world.spawn_unit(peer_id, index, barracks.global_position + offset)


# --- фракция --------------------------------------------------------------

## Где сторона появляется. Слот разводит нескольких игроков одной стороны,
## хотя в срезе стороны в сессии уникальны.
func faction_spawn() -> Vector3:
	var base: Vector3 = FACTIONS.SPAWN[clampi(faction, 0, FACTIONS.COUNT - 1)]
	return base + Vector3(float(spawn_slot) * 3.0, 0.0, 0.0)


func _select_weapon(kind: int) -> void:
	if FACTIONS.allows_weapon(faction, kind):
		sync_weapon = kind


## Есть ли у стороны стратегический режим. Только у злодея
## (DESIGN_ANSWERS.md, пункт 19).
## Стратегический режим есть у злодея по рождению и у стража, которого повысили
## до командира (GDD раздел 2.2). Вместе с ним приходят стройка и наём.
func has_strategy() -> bool:
	return FACTIONS.has_strategy(faction) or is_leader


func can_build() -> bool:
	return FACTIONS.can_build(faction) or is_leader


# --- консоль для playtest -------------------------------------------------

const CHEATS := preload("res://scripts/cheats.gd")

## Ответ хоста на консольную команду.
signal cheat_reply(text: String)


func ask_cheat(line: String) -> void:
	if not OS.is_debug_build():
		cheat_reply.emit("консоль доступна только в отладочной сборке")
		return
	if Net.hosting():
		request_cheat(line)
	else:
		request_cheat.rpc_id(1, line)


## Команду исполняет ТОЛЬКО хост: выданные локально ресурсы затёрла бы
## репликация, а спавн юнита на клиенте другие пиры бы не увидели.
@rpc("any_peer", "reliable")
func request_cheat(line: String) -> void:
	if not Net.hosting() or not OS.is_debug_build():
		return
	if not _sender_is_owner():
		return
	var reply: String = CHEATS.execute(get_parent().get_parent(), self, line)
	print("[консоль] %d: %s -> %s" % [peer_id, line, reply])
	if multiplayer.get_remote_sender_id() == 0:
		cheat_reply.emit(reply)
	else:
		cheat_answer.rpc_id(peer_id, reply)


@rpc("any_peer", "reliable")
func cheat_answer(text: String) -> void:
	if not _sender_is_host():
		return
	cheat_reply.emit(text)


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


# --- приказы командира (Этап 9) -------------------------------------------

## Игрок стоит у командира? Клиент считает то же самое для подсказки.
func at_commander() -> bool:
	var world := get_parent().get_parent()
	if world == null:
		return false
	var commander: Node3D = world.get_node_or_null("Commander")
	if commander == null:
		return false
	return commander.in_range(global_position)


func ask_report() -> void:
	if Net.hosting():
		request_report()
	else:
		request_report.rpc_id(1)


## Доклад командиру. Решает ХОСТ: он же проверяет расстояние и платит награду.
@rpc("any_peer", "reliable")
func request_report() -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner():
		push_warning("Пир пытался докладывать чужим персонажем %d" % peer_id)
		return
	if not health.alive:
		return
	if faction != FACTIONS.Kind.GUARD:
		return
	var commander: Node3D = get_parent().get_parent().get_node_or_null("Commander")
	if commander == null:
		return
	commander.report(self)


func ask_promotion() -> void:
	if Net.hosting():
		request_promotion()
	else:
		request_promotion.rpc_id(1)


## Заявка на командование. Решает ХОСТ: он же проверяет сторону, расстояние и
## то, что живого командира сейчас нет.
@rpc("any_peer", "reliable")
func request_promotion() -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner():
		push_warning("Пир пытался принять командование чужим персонажем %d" % peer_id)
		return
	var commander: Node3D = get_parent().get_parent().get_node_or_null("Commander")
	if commander == null:
		return
	commander.promote(self)


## Перевести владельца этого персонажа в наблюдатели. Присылает ХОСТ тому пиру,
## чей вожак пал окончательно.
##
## Управления больше нет, но камера остаётся: партия после победы продолжается
## как песочница (GDD раздел 7), и досмотреть её игрок должен сверху, а не с
## собственного трупа.
@rpc("any_peer", "call_local", "reliable")
func become_spectator() -> void:
	if not _sender_is_host():
		return
	if not is_multiplayer_authority():
		return
	control_enabled = false
	var world := get_parent().get_parent()
	if world != null and world.has_method("set_strategy_mode"):
		world.set_strategy_mode(true)


# --- перемирие (Этап 10, шаг 4, GDD раздел 9.4) ---------------------------

## Ближайший живой игрок другой стороны в радиусе жеста. null — предлагать некому.
func truce_target() -> Node3D:
	var dip := _diplomacy()
	if dip == null:
		return null
	var best: Node3D = null
	var best_d: float = dip.TRUCE_RANGE
	for other in get_parent().get_children():
		if other == self or not ("faction" in other) or not ("health" in other):
			continue
		if int(other.faction) == faction or not other.health.alive:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best


func ask_truce() -> void:
	if Net.hosting():
		request_truce()
	else:
		request_truce.rpc_id(1)


## Предложить перемирие ближайшему игроку другой стороны.
##
## Отдельного «принять» нет намеренно: встречное предложение той же пары и есть
## согласие. Так жест остаётся жестом, а не превращается в переговоры с UI.
@rpc("any_peer", "reliable")
func request_truce() -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner() or not health.alive:
		return
	var target := truce_target()
	if target == null:
		return
	var dip := _diplomacy()
	if dip == null:
		return
	var text: String = dip.offer_truce(faction, int(target.faction))
	if text.is_empty():
		return
	print("[дипломатия] %s" % text)
	var objective: Node3D = get_parent().get_parent().get_node_or_null("Objective")
	if objective != null:
		objective.announce.rpc(text)
