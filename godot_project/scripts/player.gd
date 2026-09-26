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
const LABOURER := preload("res://scripts/units/labourer.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const RIG := preload("res://scripts/combat/rig.gd")

## Своя модель на сторону. Порядок — как в `factions.gd::Kind`: злодей,
## эльфы, стража.
##
## СВОИ, А НЕ ПОКУПНЫЕ (решение владельца от 19.09.2026). Кованы
## `tools/asset_forge/character.py`: модель, скелет и анимации целиком из кода,
## по одному пресету на сторону. Отличаются не файлом, а числами — ростом,
## шириной плеч, цветом, плащом, наплечниками, длиной ушей.
##
## Ради чего меняли: у покупного Ranger нет ни одной анимации замаха оружием и
## нет позы сидя — эльф махал невидимо, а безногий «полз» по стойке смирно.
## Своя модель правится там, где не устраивает, а не ищется в чужом паке.
const MODELS := [
	"res://assets/people/Villain.glb",
	"res://assets/people/Elf.glb",
	"res://assets/people/Guard.glb",
]
## Модель ростом 2.9 «единиц Blender» — приводим к человеческим 1.84 м.
## Кузница держит тот же рост НАМЕРЕННО: иначе пришлось бы заводить свой
## масштаб на каждую модель, а вместе с ним и своё расхождение.
const MODEL_SCALE := 0.63

const ZONE_MULTIPLIERS := {
	"head": 2.0,
	"torso": 1.0,
	"arm_l": 0.7,
	"arm_r": 0.7,
	"leg_l": 0.7,
	"leg_r": 0.7,
}

## Полный запас маны и сколько её возвращается в секунду.
##
## Восполнение МЕДЛЕННОЕ и намеренно: полный запас набирается сорок секунд, а
## самое дорогое заклинание стоит половину. Быстрее — и мана перестанет быть
## ограничением, превратившись во второй откат.
const MANA_MAX := 100.0
const MANA_REGEN := 2.5

const SPEED := 6.0
## Во сколько раз быстрее бег. Шаг пешком — шесть метров в секунду, бегом —
## десять с половиной: карта полтора километра в поперечнике, и дорога от форта
## злодея до дворца пешком занимает две минуты в одну сторону.
const RUN_SCALE := 1.75

## Выносливость: сколько её всего, сколько ест бег и прыжок, сколько
## возвращается.
##
## ЗАЧЕМ. Решение живого игрока — «добавить стамину». До неё бег был бесплатным
## и бесконечным: ходить шагом не было ни одной причины, и лошадь, дающая те же
## полтора раза, оказывалась подарком без цены. Выносливость возвращает цену и
## бегу, и конюшне.
##
## ЧИСЛА. Сто единиц, расход десять в секунду — десять секунд непрерывного бега,
## это около ста метров. Возврат двенадцать в секунду: чуть быстрее расхода, так
## что бегом проходится примерно половина пути, а не весь.
##
## ВТОРОЕ ДЫХАНИЕ (STAMINA_FLOOR). Выдохшись, снова бежать можно не с первой
## капли, а набрав пятнадцать. Без порога на нуле выходит дёрганый бег: чуть
## набралось — сразу потратилось, и персонаж мигает шагом-бегом каждые полкадра.
## Порог превращает это в понятное «отдышись».
##
## ЗАДЕРЖКА ПЕРЕД ВОЗВРАТОМ нужна по той же причине: без неё отпускание бега на
## доли секунды успевало подкачать выносливость, и бег становился бесконечным
## для того, кто часто моргает клавишей.
const STAMINA_MAX := 100.0
const STAMINA_RUN_DRAIN := 10.0
const STAMINA_JUMP := 12.0
const STAMINA_REGEN := 12.0
const STAMINA_FLOOR := 15.0
const STAMINA_REST := 0.6
## Насколько далеко бьёт луч прицеливания. Дальше стрелять всё равно не в кого:
## снаряды живут меньше.
const AIM_RANGE := 300.0
const JUMP_VELOCITY := 5.5
const MOUSE_SENS := 0.0025
const PITCH_MIN := -1.2
const PITCH_MAX := 0.6
const REMOTE_LERP := 15.0

## Слои физики. Капсулы персонажей намеренно вынесены со слоя статичного мира:
## иначе луч стрелы утыкается в капсулу, у которой нет зоны попадания, и урон
## теряется. Снаряды ищут слой мира и слой зон, а капсулы не видят вовсе.
const WORLD_LAYER := 1
const BODY := preload("res://scripts/combat/body.gd")
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

## Колчан. Ведёт ХОСТ, клиент только показывает.
##
## ЗАЧЕМ КОНЕЧНЫЕ СТРЕЛЫ. Решение живого игрока: «стрелы должны быть
## конечными». Бесконечный лук делает ближний бой необязательным — стрелять
## безопаснее всегда, и выбор оружия перестаёт быть выбором. Кончились стрелы —
## берёшься за меч; это и есть решение, которого раньше не было.
@export var arrows: int = RES.QUIVER_START

## Мана. Ведёт ХОСТ.
##
## ЗАЧЕМ ОНА ПРИ СУЩЕСТВУЮЩИХ ОТКАТАХ. Живой игрок: «магия имба какая та, и
## чтобы был выбор — пойти в магию, либо ручками сражаться». Откат ограничивает
## ОДНО заклинание, а не колдуна: имея шесть штук с разными откатами, злодей
## колдовал непрерывно, чередуя их. Мана — общий кошелёк на все шесть.
@export var mana: float = MANA_MAX
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
## Откаты по ВСЕМ способностям, а не только по эльфийским трём: у злодея свои
## три, и номера у них общие. Длина обязана совпадать с ABILITIES.COUNT —
## короткий массив падал на первом же заклинании злодея, молча и в каждом кадре.
@export var sync_ability_cd: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
## Нужен, чтобы чужие персонажи анимировались: движение у них не считается.
@export var sync_moving: bool = false
## Бежит ли. Едет по сети отдельно от `sync_moving`: чужой персонаж иначе
## переставлял бы ноги шагом, покрывая землю бегом.
@export var sync_running: bool = false
## Выносливость. Считает ВЛАДЕЛЕЦ, как и всё движение (Этап 0): она ограничивает
## его собственный бег, и держать её на хосте значило бы спрашивать разрешения
## на каждый шаг. Реплицируется, чтобы её видели и остальные.
@export var sync_stamina: float = STAMINA_MAX
## Выдохся: бежать нельзя, пока не наберётся STAMINA_FLOOR.
var _winded := false
## Сколько ещё не восстанавливаться.
var _rest_left := 0.0

## Состояние отряда. Считает и меняет только хост, клиенты читают.
@export var squad_formation: int = 0
@export var squad_hold: bool = false
@export var squad_rally: Vector3 = Vector3.ZERO
@export var squad_rally_yaw: float = 0.0

var peer_id := 1

## Персонажем правит ИИ, а не человек: за сторону никто не сел (GDD 10.1).
##
## Это ТОТ ЖЕ персонаж, которым играл бы живой злодей, — не второй, урезанный
## юнит-заклинатель. Меняется ровно один слой: снимок ввода даёт `ai/hero.gd`
## вместо клавиатуры. Всё остальное — движение, оружие, магия, ранения, гибель
## вожака — работает прежним кодом и потому проверено прежними наборами.
##
## Ставится в `world._make_player()` до входа в дерево: `_enter_tree()` уже
## обязан знать, кому отдавать авторитет.
var ai_led := false
var spawn_slot := 0
## Сторона игрока. Приезжает данными спавна, поэтому одинакова на всех пирах.
var faction := 0
var control_enabled := true

## Сколько секунд персонаж сбит с ног и не может бить. Ставит молот (GDD 3.1).
## Реплицируется: сбитый должен видеть, что он сбит, а не гадать, почему не бьёт.
@export var sync_stagger: float = 0.0

## Магия злодея (GDD 3.2). Все три состояния РЕПЛИЦИРУЮТСЯ: цель обязана видеть,
## что с ней происходит, иначе паралич выглядит как зависшая игра, а увядание —
## как непонятно откуда взявшаяся слабость.
@export var sync_paralysis: float = 0.0
@export var sync_wither: float = 0.0
@export var sync_blind: float = 0.0

## Окно неуязвимости к повторному параличу. Считает и хранит ТОЛЬКО хост: цели
## знать о нём незачем, а вот удерживать её в вечном контроле цепочкой кастов
## нельзя.
var _paralysis_immunity := 0.0
var _was_paralysed := false
## Идущий каст: что колдуем и сколько осталось. Тоже только на хосте — он же и
## срывает каст, когда по кастующему попали.
var _cast_kind := -1
var _cast_left := 0.0
var scripted_input := {}

static var _bot_mode := -1

var _pitch := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _cooldown_left := 0.0
var _server_cooldown := 0.0
var _swing_left := 0.0
## Сколько ещё вздрагивать от попадания. Живёт отдельно от замаха: свой удар
## важнее чужого, и сбивать собственную атаку чужой стрелой нельзя — иначе
## двое стрелков держат мечника в вечном вздрагивании.
var _flinch_left := 0.0
var _bandage_progress := 0.0

## ВИД ОТ ПЕРВОГО И ОТ ТРЕТЬЕГО ЛИЦА — решение владельца от 19.09.2026.
##
## Это НЕ замена третьего лица первым и НЕ про стратегический режим: экшен
## получил два подрежима, а `Tab` в вид сверху остался тем же, чем был. GDD
## раздел 1 этим уточняется, а не отменяется.
##
## Числа. Третье лицо — из сцены: пивот вынесен вправо (вид из-за плеча) и
## поднят выше головы. Первое — на уровне глаз: голова у скелета стоит на 2.10
## в единицах модели, а модель ужата до MODEL_SCALE, то есть глаза примерно на
## 1.36 мира. Брать сюда 1.6 от третьего лица нельзя — смотрел бы поверх
## собственной макушки.
const VIEW_THIRD_PIVOT := Vector3(0.65, 1.6, 0.0)
const VIEW_THIRD_ARM := 4.5
## Чуть вперёд по -Z: перед у персонажа там же, куда он идёт и целится.
## Высота здесь — ЗАПАСНАЯ: обычно её считает `_eye_pivot` по кости головы.
const VIEW_FIRST_PIVOT := Vector3(0.0, 1.36, -0.12)
const VIEW_FIRST_ARM := 0.0
## Насколько глаза выше центра кости головы.
const EYE_ABOVE_HEAD_BONE := 0.05

## Сколько длится вздрагивание от попадания. Короткое намеренно: длинное
## означало бы, что под обстрелом персонаж не управляется вовсе.
const FLINCH_TIME := 0.32

## Смотрим из глаз. ЛОКАЛЬНОЕ и нереплицируемое: чужим всё равно, каким видом
## играет сосед, а тело прячется только от своей камеры.
var _first_person := false

@onready var _pivot: Node3D = $CamPivot
@onready var _arm: SpringArm3D = $CamPivot/SpringArm3D
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
## Скелет модели: на нём и зоны попадания, и расчленение.
var _skeleton: Skeleton3D
## Ключ зоны -> СПИСОК зон. Их несколько на ключ: рука это плечо и предплечье,
## корпус — грудь и таз. Один шар на конечность либо не достаёт до кисти, либо
## залезает в туловище.
var _zones := {}
## Узел на кости кисти, к которому крепится оружие.
var _weapon_mount: Node3D
## Какая маска увечий уже показана на модели.
var _shown_severed := -1
## Сколько выбитых глаз уже отмечено на лице.
var _shown_eyes := -1
var _weapon_visual: Node3D
## Какое оружие сейчас показано. Нужно, чтобы перерисовывать при смене — в том
## числе у чужих персонажей, у которых sync_weapon приезжает по сети.
var _weapon_shown := -1
var _tier_shown := -1
var _current_anim := ""


func _enter_tree() -> void:
	peer_id = str(name).to_int()
	# Рекурсивно — чтобы синхронизатор движения получил того же авторитета.
	#
	# У героя под ИИ пира нет вовсе, и `peer_id` у него отрицательный. Авторитет
	# отдаём хосту: он считает и его движение тоже. Оставить как есть нельзя —
	# авторитета не оказалось бы ни у кого, и персонаж просто стоял бы.
	set_multiplayer_authority(1 if ai_led else peer_id)
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
	_name_tag.text = ("%s (ИИ)" % FACTIONS.name_of(faction) if ai_led
		else "%s (%d)" % [FACTIONS.name_of(faction), peer_id])

	# КАМЕРА И ВВОД — только у ЖИВОГО игрока, а не у всякого, кем правит этот пир.
	#
	# У героя свободной стороны авторитет — хост (см. `set_multiplayer_authority`
	# выше): его симулирует хозяин сессии, и это верно. Но `is_multiplayer_
	# authority()` у него на хосте тоже истинно, и он включал СВОЮ камеру,
	# перехватывая вид у человека. Последний заспавненный герой побеждал.
	#
	# Снаружи это выглядело так: человек начинает партию за стражу, а видит
	# чужую базу и «не работает управление» — потому что свой персонаж honestно
	# шёл по приказам, только за кадром. Три отчёта подряд об одном и том же:
	# «появляешься в форте злодея», и на всех снимках одно и то же место при
	# разных сторонах в углу экрана. Разные стороны, один вид — это и был ответ.
	var mine := is_multiplayer_authority() and not ai_led
	_camera.current = mine
	_name_tag.visible = not mine
	set_process_unhandled_input(mine)

	body.limb_severed.connect(_on_limb_severed)
	body.state_changed.connect(_refresh_posture)

	# Звук смерти — у каждого пира: `died` эмитится локально, когда до пира
	# доезжает нулевое здоровье. Ставить его в хостовый обработчик значило бы
	# слышать чужую смерть только хозяину сессии.
	health.died.connect(func(_killer: int) -> void:
		Sfx.at(Sfx.Kind.DEATH, global_position, 2.0))
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

	# Тело — один скиннутый меш, прятать по частям нечего: и зоны попадания, и
	# расчленение живут на костях (см. `rig.gd`).
	_skeleton = RIG.find_skeleton(_model)
	RIG.hide_built_in_weapon(_model)
	_zones = RIG.build_zones(_skeleton, ZONE_MULTIPLIERS, HITBOX_LAYER)
	_weapon_mount = RIG.weapon_mount(_skeleton)
	# Перевязь стороны — и на вожаке тоже. У него модель своя на каждую сторону,
	# но издали и в свалке отличать его от чужого приходится по тому же
	# признаку, что и пешек: по цвету, а не по длине ушей.
	RIG.faction_band(_skeleton, FACTIONS.color_of(faction))

	_refresh_weapon_visual()
	# Состояние тела могло приехать РАНЬШЕ модели: поздний клиент получает
	# готового калеку одним пакетом, и сигнала об отрыве при нём уже не будет.
	# Поэтому применяем маску сразу, а не ждём события.
	_apply_severed()
	# Вид ставим ПОСЛЕ модели: до неё скелета нет, и прятать тело не от чего.
	# Пересборка модели (респавн, смена облика) обязана вернуть камеру в тот же
	# вид, в каком человек играл, — иначе первое лицо слетало бы на каждой
	# смерти.
	_apply_view()
	_play("idle")


func _find_node(node: Node, type) -> Node:
	if is_instance_of(node, type):
		return node
	for child in node.get_children():
		var found := _find_node(child, type)
		if found != null:
			return found
	return null


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not control_enabled:
		return
	# Хост — авторитет и над героем ИИ тоже, а мышь у него одна: без этой строки
	# он крутил бы камеру сразу двоим.
	if ai_led:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
		_pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if Net.hosting():
		_server_cooldown = maxf(0.0, _server_cooldown - delta)
		sync_stagger = maxf(0.0, sync_stagger - delta)
		_tick_curses(delta)
		_tick_abilities(delta)

	_swing_left = maxf(0.0, _swing_left - delta)
	_flinch_left = maxf(0.0, _flinch_left - delta)
	_refresh_weapon_visual()
	# Следим за МАСКОЙ, а не только за сигналом об отрыве. Сигнал приходит один
	# раз и только когда бит ЗАЖИГАЕТСЯ: он не расскажет ни про снятие увечий
	# (сброс тела при респавне), ни про позднего клиента, которому готовое
	# состояние приехало одним пакетом. Сверка дешёвая — сравнение двух чисел.
	if body != null and body.severed_mask != _shown_severed:
		_shown_severed = body.severed_mask
		_apply_severed()
	# Выбитый глаз должны видеть ОСТАЛЬНЫЕ. Себе слепота видна закрытой половиной
	# экрана, а снаружи одноглазый ничем не отличался от целого — при том что у
	# пешек кровь на лице появилась. Одна система увечий на всех значит и один
	# вид: разница «люди целые, пешки в крови» была бы просто недоделкой.
	if body != null and body.eyes_lost != _shown_eyes:
		_shown_eyes = body.eyes_lost
		RIG.mark_eye_loss(_model, body.eyes_missing())

	if is_multiplayer_authority():
		var inp := _gather_input()
		apply_input(inp, delta)
		_update_attack(delta)
		_update_abilities()
		_update_bandage(delta, inp)
		sync_position = global_position
		sync_yaw = rotation.y
		sync_moving = Vector2(velocity.x, velocity.z).length() > 0.4
		_tick_steps(delta)
	else:
		var t := clampf(delta * REMOTE_LERP, 0.0, 1.0)
		global_position = global_position.lerp(sync_position, t)
		rotation.y = lerp_angle(rotation.y, sync_yaw, t)

	_update_animation()


## Шаги.
##
## Их не было вовсе, и тестеры это отмечали: игра беззвучна ровно там, где звук
## нужен больше всего — под ногами. Шаг важнее половины боевых звуков: по нему
## слышно, что ты движешься, и слышно, что кто-то движется рядом.
##
## Шагаем ПО ВРЕМЕНИ, а не по анимации: анимации у нас чужие, их частота нам не
## принадлежит, и привязка к ней ломается при первой замене модели. Верхом шаг
## чаще — лошадь идёт быстрее.
const STEP_INTERVAL := 0.42

var _step_left := 0.0


func _tick_steps(delta: float) -> void:
	if not sync_moving or not is_on_floor():
		_step_left = 0.0
		return
	_step_left -= delta
	if _step_left > 0.0:
		return
	_step_left = STEP_INTERVAL / maxf(0.5, mount_speed_scale())
	step_heard.rpc(global_position)


## Шаг слышен ВСЕМ, а не только тому, кто идёт: подкрадывающегося противника
## слышно — это и есть смысл звука шагов.
@rpc("authority", "call_local", "unreliable")
func step_heard(point: Vector3) -> void:
	# Верхом слышно КОПЫТО, а не сапог. Звучит один и тот же тик шага, но
	# всадник, который шуршит травой, слышится пешеходом — и по слуху нельзя
	# понять, кто приближается.
	if riding():
		Sfx.hoof(point)
	else:
		Sfx.step(point)


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
		"run": Input.is_action_pressed("sprint"),
		"bandage": Input.is_action_pressed("bandage"),
	}


## Чистая симуляция персонажа от снимка ввода. Не читает Input напрямую.
## Скорость и прыжок берутся у тела: без ноги персонаж ползёт, с мастерским
## протезом прыгает выше живого (GDD раздел 4).
func apply_input(inp: Dictionary, delta: float) -> void:
	var move: Vector2 = inp.get("move", Vector2.ZERO)
	var jump: bool = inp.get("jump", false)
	if sync_paralysis > 0.0:
		# Парализованный не двигается. КАМЕРУ у него не отбираем: смотреть по
		# сторонам он должен — иначе несколько секунд выглядят как зависшая игра,
		# а не как заклинание.
		move = Vector2.ZERO
		jump = false

	# Бег. НЕ верхом и НЕ на карачках: у лошади своя скорость, и умножать её
	# ещё и бегом значит менять цену конюшни, а безногий и так ползёт — «бежать
	# ползком» было бы издевательством, а не механикой.
	var running: bool = bool(inp.get("run", false)) \
		and move.length() > 0.1 \
		and riding() == null \
		and not body.is_crawling() \
		and not body.in_wheelchair \
		and sync_paralysis <= 0.0
	# ВЫНОСЛИВОСТЬ. Верхом не тратится: устаёт лошадь, а не всадник, и брать
	# плату за поездку значило бы отменить конюшню сразу после того, как
	# подсказка велела её построить.
	var mounted: bool = riding() != null
	if running and not mounted:
		if _winded or sync_stamina <= 0.0:
			_winded = true
			running = false
		else:
			sync_stamina = maxf(0.0, sync_stamina - STAMINA_RUN_DRAIN * delta)
			_rest_left = STAMINA_REST
			if sync_stamina <= 0.0:
				_winded = true
	sync_running = running

	var speed: float = body.move_speed(SPEED) * buff_speed_scale() * mount_speed_scale()
	if running:
		speed *= RUN_SCALE
	var jump_power: float = body.jump_velocity(JUMP_VELOCITY)

	if is_on_floor():
		# Прыжок тоже стоит сил. Прыжковая лестница через полкарты была
		# способом обойти разом и рельеф, и усталость.
		if jump and jump_power > 0.0 and (mounted or sync_stamina >= STAMINA_JUMP):
			velocity.y = jump_power
			if not mounted:
				sync_stamina = maxf(0.0, sync_stamina - STAMINA_JUMP)
				_rest_left = STAMINA_REST
	else:
		velocity.y -= _gravity * delta

	# Возврат: не бежим и отдышались — набираем.
	if not running:
		_rest_left = maxf(0.0, _rest_left - delta)
		if _rest_left <= 0.0 and sync_stamina < STAMINA_MAX:
			sync_stamina = minf(STAMINA_MAX, sync_stamina + STAMINA_REGEN * delta)
	if _winded and sync_stamina >= STAMINA_FLOOR:
		_winded = false

	var dir := (transform.basis * Vector3(move.x, 0.0, move.y))
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	move_and_slide()


# --- анимация и поза -------------------------------------------------------

## Игра говорит своими словами («walk», «die»), пак называет то же самое
## по-своему — перевод живёт в `model_anim.gd::resolve`. Пустой ответ значит
## «такого движения в этой модели нет»: тогда оставляем то, что играется, а не
## замираем в первом кадре.
func _play(anim_name: String, force := false) -> void:
	if _anim == null or (anim_name == _current_anim and not force):
		return
	var real := MODEL_ANIM.resolve(_anim, anim_name)
	if real == "":
		return
	_current_anim = anim_name
	_anim.play(real)


func _update_animation() -> void:
	if _anim == null:
		return
	if not health.alive:
		_play("die")
		return
	if _swing_left > 0.0:
		return
	if _flinch_left > 0.0:
		return
	var moving := sync_moving if not is_multiplayer_authority() else (
		Vector2(velocity.x, velocity.z).length() > 0.4
	)
	if body.in_wheelchair:
		_play("wheelchair-move-forward" if moving else "wheelchair-sit")
	elif body.is_crawling():
		_play("sit")
	elif moving:
		# Своему персонажу верим напрямую, чужому — по сети: у чужого
		# `sync_running` и есть весь ответ.
		var running: bool = sync_running
		_play("run" if running else "walk")
	else:
		_play("idle")


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
	# Поза сменилась — глаза переехали. В третьем лице это ничего не меняет, в
	# первом решает всё: иначе ползающий смотрит с высоты стоящего.
	_apply_view()


# --- бой: сторона клиента -------------------------------------------------

func _update_attack(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if not control_enabled or not health.alive or sync_stagger > 0.0 or sync_paralysis > 0.0:
		return

	# Оружие переключаем только среди разрешённого стороне: у эльфов и стражи
	# нет атакующей магии (DESIGN_ANSWERS.md, пункт 18).
	# У героя под ИИ клавиатуры нет: оружие ему выбирает `ai/hero.gd`. Читать
	# здесь Input значило бы переключать снаряжение ИИ клавишами хоста.
	if not ai_led:
		for slot in 4:
			if Input.is_action_just_pressed("weapon_%d" % (slot + 1)):
				_select_weapon(FACTIONS.weapon_on_slot(faction, slot))
				break

	var wants: bool = scripted_input.get("attack", false)
	if not wants and not ai_led and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		wants = Input.is_action_pressed("attack")
	if not wants or _cooldown_left > 0.0:
		return
	if not _weapon_allowed(sync_weapon):
		return

	_cooldown_left = (WEAPONS.COOLDOWN[sync_weapon] * body.attack_speed_scale()
		* buff_attack_scale() * WEAPONS.gear_cooldown(gear_tier))
	_swing_left = 0.45
	_play("attack-melee-right" if WEAPONS.is_melee(sync_weapon) else "holding-right-shoot", true)

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
	if WEAPONS.is_melee(kind):
		return body.can_attack_melee()
	return body.can_attack_ranged()


func aim_origin() -> Vector3:
	return global_position + Vector3.UP * EYE_HEIGHT


## Куда летит снаряд: В ТОЧКУ ПОД ПРИЦЕЛОМ, а не «куда повёрнут корпус».
##
## Камера стоит из-за плеча, то есть в стороне от персонажа. Направление,
## взятое от корпуса, и точка под прицелом при этом РАЗНЫЕ, и чем ближе цель,
## тем сильнее они расходятся: целишься в стоящего в трёх шагах, а шар уходит
## вбок на полметра. Именно поэтому «стрелять неудобно» — прицел не врал,
## врало направление.
##
## Поэтому: пускаем луч из камеры вперёд, находим, во что упёрся взгляд, и
## стреляем ИЗ РУКИ В ЭТУ ТОЧКУ. Не упёрся ни во что — берём точку на пределе
## дальности, тогда направление совпадает со взглядом.
func aim_direction() -> Vector3:
	var straight: Vector3 = -(Basis(Vector3.UP, rotation.y) * Basis(Vector3.RIGHT, _pitch)).z
	if _camera == null or not is_inside_tree():
		return straight
	var space := get_world_3d().direct_space_state
	if space == null:
		return straight
	var from: Vector3 = _camera.global_position
	var to: Vector3 = from - _camera.global_transform.basis.z * AIM_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Себя из луча исключаем: иначе с некоторых ракурсов взгляд «упирается» в
	# собственное плечо и выстрел уходит под ноги.
	query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	var target: Vector3 = hit.get("position", to)
	var dir: Vector3 = target - aim_origin()
	if dir.length() < 0.5:
		return straight
	return dir.normalized()


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


## Состояния от магии злодея и идущий каст. Только на хосте.
func _tick_curses(delta: float) -> void:
	sync_paralysis = maxf(0.0, sync_paralysis - delta)
	sync_wither = maxf(0.0, sync_wither - delta)
	sync_blind = maxf(0.0, sync_blind - delta)
	_paralysis_immunity = maxf(0.0, _paralysis_immunity - delta)
	if sync_paralysis > 0.0:
		_was_paralysed = true
	elif _was_paralysed:
		# Эффект только что кончился — открываем окно неуязвимости.
		_was_paralysed = false
		_paralysis_immunity = ABILITIES.PARALYSIS_IMMUNITY

	# Мана возвращается всегда, даже в бою: она и так медленная, а «вне боя» на
	# этой карте означает «убеги на двести метров», и получилось бы наказание
	# за то, что дерёшься.
	if mana < MANA_MAX:
		mana = minf(MANA_MAX, mana + MANA_REGEN * delta)

	if _cast_left > 0.0:
		_cast_left -= delta
		if _cast_left <= 0.0:
			var kind := _cast_kind
			_cast_kind = -1
			_finish_cast(kind)


## Сорвать идущий каст. Зовётся при попадании по кастующему — это и есть
## обязательный контрплей против паралича (GDD 3.2), и ради него же существует
## оглушение молотом.
func interrupt_cast() -> void:
	if _cast_left <= 0.0:
		return
	_cast_left = 0.0
	_cast_kind = -1
	print("[магия] каст игрока %d сорван" % peer_id)


## Идёт ли каст прямо сейчас. Для автопроверок и подсказки.
func casting() -> bool:
	return _cast_left > 0.0


## Наложить паралич. Возвращает false, если цель под окном неуязвимости.
func apply_paralysis(seconds: float) -> bool:
	if not Net.hosting() or not health.alive:
		return false
	if _paralysis_immunity > 0.0:
		return false
	sync_paralysis = maxf(sync_paralysis, seconds)
	_was_paralysed = true
	return true


func apply_wither(seconds: float) -> void:
	if not Net.hosting() or not health.alive:
		return
	sync_wither = maxf(sync_wither, seconds)
	body.start_bleeding()


func apply_blind(seconds: float) -> void:
	if not Net.hosting() or not health.alive:
		return
	sync_blind = maxf(sync_blind, seconds)


## Множитель наносимого урона. Увядание ослабляет, но не обнуляет: проклятый
## должен драться хуже, а не перестать драться.
func curse_damage_scale() -> float:
	return ABILITIES.WITHER_DAMAGE_SCALE if sync_wither > 0.0 else 1.0


## Ввод. Клиент только просит — применяет способность хост.
func _update_abilities() -> void:
	if not control_enabled or not health.alive or sync_paralysis > 0.0:
		return

	var wanted := -1
	# То же, что с оружием: клавиши 4/5/6 хоста не должны колдовать за ИИ.
	if not ai_led:
		for slot in 3:
			if Input.is_action_just_pressed("ability_%d" % (slot + 1)):
				wanted = FACTIONS.ability_on_slot(faction, slot)
				break
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
	# МАНУ ПРОВЕРЯЕМ ЗДЕСЬ, а списываем после того, как заклинание сработало
	# (см. `_pay_mana`). Порядок тот же, что у отката, и по той же причине:
	# сорванный каст не должен стоить маны, иначе прерывание наказывает дважды.
	if mana < ABILITIES.mana_cost(kind):
		_refuse("не хватает маны: нужно %d, есть %d"
			% [int(ABILITIES.mana_cost(kind)), int(mana)])
		return
	# Способности требуют полноценной руки — как лук (GDD раздел 4).
	if not body.can_attack_ranged():
		return

	if sync_paralysis > 0.0 or sync_stagger > 0.0:
		# Парализованный и сбитый не колдуют. Проверяем на хосте: клиент мог не
		# успеть узнать о своём состоянии.
		return

	# Долгий каст. Заклинание не срабатывает сразу — его видно и его можно
	# сорвать ударом (GDD 3.2, обязательный контрплей).
	var cast: float = ABILITIES.cast_time(kind)
	if cast > 0.0:
		if _cast_left > 0.0:
			return
		_cast_kind = kind
		_cast_left = cast
		ability_cast.rpc(kind, global_position)
		return

	if not _run_ability(kind):
		return
	_pay_mana(kind)
	sync_ability_cd[kind] = ABILITIES.cooldown_of(kind)
	ability_cast.rpc(kind, global_position)


## Каст доведён до конца. Откат ставим ЗДЕСЬ, а не в начале: сорванный каст не
## должен стоить заклинания, иначе прерывание превращается в двойное наказание.
func _finish_cast(kind: int) -> void:
	if kind < 0 or not health.alive:
		return
	# Мана могла кончиться, пока шёл каст: проверяем ЕЩЁ РАЗ. Без этого долгие
	# заклинания обходили бы ограничение, начавшись впритык.
	if mana < ABILITIES.mana_cost(kind):
		_refuse("мана кончилась, пока шёл каст")
		return
	if not _run_ability(kind):
		return
	_pay_mana(kind)
	sync_ability_cd[kind] = ABILITIES.cooldown_of(kind)
	ability_cast.rpc(kind, global_position)


## Списать ману за сработавшее заклинание.
func _pay_mana(kind: int) -> void:
	mana = maxf(0.0, mana - ABILITIES.mana_cost(kind))


func _run_ability(kind: int) -> bool:
	match kind:
		ABILITIES.Kind.HEAL:
			return _server_cast_heal()
		ABILITIES.Kind.RALLY:
			return _server_cast_rally()
		ABILITIES.Kind.SUMMON:
			return _server_cast_summon()
		ABILITIES.Kind.PARALYSIS:
			return _server_cast_paralysis()
		ABILITIES.Kind.WITHER:
			return _server_cast_curse(ABILITIES.Kind.WITHER)
		ABILITIES.Kind.BLIND:
			return _server_cast_curse(ABILITIES.Kind.BLIND)
	return false


# --- магия злодея (GDD 3.2) ------------------------------------------------

## Паралич воли. По ИГРОКУ — жёсткий контроль и ничего больше. По НАЁМНОМУ
## существу — переход под контроль кастующего: это юнит, а не человек.
##
## Разница не косметическая, она и есть решение: отобрать управление у живого
## человека нельзя, а перевербовать чужого волка — законный контрприём против
## друидических призывов.
func _server_cast_paralysis() -> bool:
	var target: Node3D = _nearest_enemy(ABILITIES.range_of(ABILITIES.Kind.PARALYSIS))
	if target == null:
		_refuse("паралич некому наложить: врага рядом нет")
		return false

	if target.has_method("apply_paralysis"):
		if not target.apply_paralysis(ABILITIES.PARALYSIS_HOLD):
			_refuse("цель ещё не отошла от прошлого паралича")
			return false
		print("[магия] игрок %d парализован на %.0f с" % [int(target.peer_id), ABILITIES.PARALYSIS_HOLD])
		return true

	if target.has_method("charm"):
		target.charm(int(faction), ABILITIES.PARALYSIS_CHARM)
		print("[магия] боец перевербован на %.0f с" % ABILITIES.PARALYSIS_CHARM)
		return true
	return false


## Увядание и слепота: обе бьют по одной цели и обе просто ставят срок.
func _server_cast_curse(kind: int) -> bool:
	var target: Node3D = _nearest_enemy(ABILITIES.range_of(kind))
	if target == null:
		_refuse("%s некому наложить: врага рядом нет" % ABILITIES.name_of(kind))
		return false
	if kind == ABILITIES.Kind.WITHER:
		if target.has_method("apply_wither"):
			target.apply_wither(ABILITIES.WITHER_DURATION)
		elif target.has_method("take_damage"):
			# У бойца системы ранений нет: увядание для него — чистый урон
			# вместо кровотечения, чтобы заклинание не было по нему пустым.
			target.take_damage(ABILITIES.WITHER_DURATION * 3.0, peer_id, "torso",
				target.global_position, Vector3.UP, false, WEAPONS.Kind.SPELL)
		return true
	if target.has_method("apply_blind"):
		target.apply_blind(ABILITIES.BLIND_DURATION)
		return true
	# Слепота по бойцу бессмысленна: у него нет экрана. Пусть лучше откажет
	# честно, чем сработает вхолостую и спишет откат.
	_refuse("слепота действует только на игрока")
	return false


## Ближайший враг в радиусе: персонаж другой стороны или чужой боец.
func _nearest_enemy(radius: float) -> Node3D:
	var world := get_parent().get_parent()
	var best: Node3D = null
	var best_distance := radius
	for other in get_parent().get_children():
		if other == self or not ("faction" in other) or int(other.faction) == int(faction):
			continue
		if not other.health.alive:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d < best_distance:
			best_distance = d
			best = other
	for unit in get_tree().get_nodes_in_group("unit"):
		if not is_instance_valid(unit) or not ("faction" in unit):
			continue
		if int(unit.faction) == int(faction):
			continue
		var d: float = global_position.distance_to(unit.global_position)
		if d < best_distance:
			best_distance = d
			best = unit
	return best


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
		# ЛЕЧЕНИЕ ВПРАВЛЯЕТ ОДНУ ПЕРЕБИТУЮ КОСТЬ. Заклинание называется
		# лечением, а до сих пор не лечило ровно того, что лечится: кость,
		# перебитую стрелой. Одну за каст — чтобы это было помощью в бою, а не
		# заменой медпункта: у медпункта своя цена и своё место на карте.
		for limb in target.body.LIMB_KEYS.size():
			if target.body.heal_limb(limb):
				restored = true
				break
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

	if sync_stagger > 0.0:
		# Сбитый не бьёт. Проверяем и здесь: клиент шлёт заявку раньше, чем до него
		# доедет то, что его сбили, и без этой проверки удар всё равно прошёл бы.
		return
	if WEAPONS.is_melee(kind):
		# Тем же ударом рубим дерево и бьём камень: отдельной кнопки добычи нет.
		if not _server_try_harvest(aim, kind):
			_server_swing_melee(aim, kind)
	else:
		# СТРЕЛУ СНИМАЕМ ЗДЕСЬ, у хоста, и только когда выстрел состоялся.
		# Снимать у клиента нельзя по той же причине, по которой он не считает
		# урон: колчан стал бы честным лишь у честных.
		if WEAPONS.uses_arrows(kind):
			if arrows <= 0:
				_refuse("стрелы кончились — возьмись за меч или докупи в лавке")
				return
			arrows -= 1
		# Снаряд создаёт и ведёт мир — он владеет спавнером снарядов.
		projectile_requested.emit(kind, host_origin, aim, peer_id, gear_tier)


## Хост разрешает удар в ближнем бою: ищет зоны попадания в секторе перед
## персонажем. Оружие задаёт дальность, урон и то, что случится сверх урона.
func _server_swing_melee(aim: Vector3, kind: int) -> void:
	var origin := aim_origin()
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = WEAPONS.melee_range(kind)
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
		var damage: float = (WEAPONS.DAMAGE[kind] * zone.damage_multiplier
			* WEAPONS.gear_damage(gear_tier) * curse_damage_scale())
		target.take_damage(damage, peer_id, zone.zone, zone.global_position, aim, false, kind)
		_apply_melee_effect(kind, target)


## Что оружие делает сверх урона.
##
## Это и есть разница между тремя видами ближнего боя: по числам они близки
## (51, 50 и 42 урона в секунду), а играются по-разному именно из-за этого.
func _apply_melee_effect(kind: int, target: Node3D) -> void:
	if kind == WEAPONS.Kind.AXE:
		# Топор оставляет кровоточащую рану. Не каждым ударом: постоянное
		# кровотечение превратило бы его в «меч, который всегда лучше».
		if randf() < WEAPONS.AXE_BLEED_CHANCE and "body" in target and target.body != null:
			target.body.start_bleeding()
	elif kind == WEAPONS.Kind.HAMMER:
		# Молот сбивает: цель не бьёт и не колдует, пока не оправится.
		if target.has_method("stagger"):
			target.stagger(WEAPONS.HAMMER_STAGGER)


## Принять урон. Вызывается ТОЛЬКО на хосте (из оружия или снаряда).
## `weapon` — чем ударили (`WEAPONS.Kind`). Нужен ТЕЛУ, а не здоровью: от вида
## оружия зависит, оторвёт конечность или перебьёт (GDD раздел 4). `-1` —
## неизвестно чем, и тогда не отрывает.
func take_damage(amount: float, attacker_id: int, zone: String, point: Vector3, dir: Vector3, _aoe := false, weapon := -1) -> void:
	if not Net.hosting():
		return
	var dealt: float = health.apply_damage(amount, attacker_id)
	if dealt <= 0.0:
		return
	# Два обязательных контрплея против магии злодея (GDD 3.2) — оба здесь,
	# потому что оба про «по цели попали».
	interrupt_cast()
	if sync_paralysis > 0.0:
		# Любой урон снимает паралич досрочно: у союзников есть чем выручить
		# парализованного, пусть и грубо.
		sync_paralysis = 0.0
	# Судьбу конечности считает тело — отдельно от общего здоровья.
	#
	# Трофей записываем ЗДЕСЬ, а не в теле: тело не знает, кто ударил, и знать не
	# должно — оно про состояние своего хозяина. Сравниваем состояние до и после
	# удара: выросла маска — значит этим ударом что-то и оторвало.
	var mask_before: int = body.severed_mask
	var eyes_before: int = body.eyes_lost
	body.register_hit(zone, dealt, weapon)
	_award_trophies(attacker_id, mask_before, eyes_before)
	show_hit.rpc(point, dir, dealt, zone)


## Записать нападавшему то, что он отрубил этим ударом.
func _award_trophies(attacker_id: int, mask_before: int, eyes_before: int) -> void:
	var world := get_parent().get_parent()
	if world == null or not world.has_method("award_trophy"):
		return
	# КОНЕЧНОСТИ БОЛЬШЕ НЕ НАЧИСЛЯЮТСЯ САМИ. Отрубленное падает на землю
	# предметом (см. `_on_limb_severed`), и трофей достаётся тому, кто дошёл и
	# поднял, — может и не тому, кто рубил. Начислять здесь значило бы считать
	# дважды.
	#
	# Глаз пока остаётся мгновенным: он не конечность, ронять его нечем —
	# отдельной модели нет. Вопрос открыт для дизайна.
	for i in (body.eyes_lost - eyes_before):
		world.award_trophy(attacker_id, Trophy.EYES)


## Прислать может только хост — проверяем отправителя, а не полагаемся на
## режим "authority": авторитет этой ноды принадлежит владельцу персонажа,
## а вызывает хост.
@rpc("any_peer", "call_local", "unreliable")
func show_hit(point: Vector3, dir: Vector3, amount: float, zone: String) -> void:
	if not _sender_is_host():
		return
	EFFECTS.blood(_effects_root(), point, dir, amount)
	# Вздрогнуть. Раньше попадание было видно только по крови и цифре здоровья:
	# в бою на пятерых понять, что бьют ИМЕННО ТЕБЯ, можно было лишь по полоске.
	# Свой замах при этом не перебиваем — он важнее.
	if health.alive and _swing_left <= 0.0:
		_flinch_left = FLINCH_TIME
		_play("hit", true)


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
	_apply_severed()
	var at := RIG.limb_point(_skeleton, limb)

	# Кровь — у каждого своя, это чистый визуал.
	EFFECTS.blood(_effects_root(), at, Vector3.UP, 80.0)
	# А сама оторванная часть теперь ПРЕДМЕТ, один на всех: её роняет хозяин
	# через общий спавнер, и подобрать её может кто угодно. Раньше её создавал
	# себе каждый пир сам, и лежала она у всех в разных местах.
	if Net.hosting():
		var world := get_parent().get_parent()
		if world != null and world.has_method("spawn_severed_limb"):
			world.spawn_severed_limb(at, limb, _trophy_kind(limb), MODEL_SCALE)
	_refresh_posture()


## Схлопнуть оторванное и погасить его зоны попадания.
##
## Считаем по МАСКЕ, а не по одному пришедшему сигналу: поздний клиент увидел
## сразу готовое состояние, сигнала об отрыве при нём не было, и безрукий
## обязан быть безруким и для него тоже.
func _apply_severed() -> void:
	RIG.apply_severed(_skeleton, body.severed_mask)
	for limb in body.LIMB_KEYS.size():
		var gone: bool = body.is_severed(limb)
		for zone in _zones.get(body.LIMB_KEYS[limb], []):
			# Бить по пустому месту нельзя: зона оторванной руки должна уйти с
			# радара оружия, иначе безрукого продолжают рубить за руку.
			zone.collision_layer = 0 if gone else HITBOX_LAYER


## Вернуть все части на место. Зовётся при респавне.
func restore_body() -> void:
	_apply_severed()
	_refresh_posture()


# --- служебное ------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func set_dead(dead: bool) -> void:
	if not _sender_is_host():
		return
	control_enabled = not dead
	for key in _zones.keys():
		for zone in _zones[key]:
			(zone as Area3D).collision_layer = 0 if dead else HITBOX_LAYER
	if not dead:
		# Оторванное остаётся оторванным: воскрешение зон не должно вернуть на
		# радар оружия те, которых нет.
		_apply_severed()
	set_collision_layer_value(2, not dead)
	if dead:
		_play("die", true)
	else:
		velocity = Vector3.ZERO
		restore_body()
		_play("idle", true)


func respawn_at_slot() -> void:
	# Колчан и мана возвращаются вместе с жизнью. Вещи при смерти падают кучей
	# (GDD 6), но выйти в мир без единой стрелы и без капли маны — это не
	# наказание за смерть, а невозможность играть.
	arrows = RES.QUIVER_START
	mana = MANA_MAX
	sync_stamina = STAMINA_MAX
	_winded = false
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


## Переключить первое лицо и третье. Только у своего персонажа.
func toggle_view() -> bool:
	_first_person = not _first_person
	_apply_view()
	return _first_person


func in_first_person() -> bool:
	return _first_person


## Поставить камеру и решить, показывать ли своё тело.
##
## СВОЁ ТЕЛО ГАСИМ ТЕНЬЮ, А НЕ `visible`. Спрятанный меш перестал бы отбрасывать
## тень, и в первом лице под ногами не было бы ничего — самый заметный признак,
## что персонажа в мире нет. `SHADOWS_ONLY` убирает тело из кадра, оставляя
## тень на земле; чужие видят тебя целиком в любом случае, это чисто своя
## камера.
##
## Гасим ТОЛЬКО меши самого скелета: оружие висит на `BoneAttachment3D`, и меч
## в руке в первом лице обязан остаться на виду (см. `rig.gd::body_meshes`).
## Где сейчас глаза — по КОСТИ ГОЛОВЫ, а не по числу.
##
## Первый заход ставил первое лицо на постоянные 1.36, и это верно ровно пока
## персонаж стоит. Ползание опускает модель на `CRAWL_MODEL_DROP`, коляска
## усаживает его анимацией, — а `CamPivot` висит на ПЕРСОНАЖЕ и не едет ни за
## тем, ни за другим: безногий смотрел бы с высоты стоящего, почти на полметра
## выше собственной головы.
##
## Догонять каждую позу своей константой значит заводить новую на каждую
## следующую. Кость головы уже едет за анимацией и закрывает их все разом — тем
## же приёмом, которым зоны попадания живут на костях, а не на числах.
##
## Константа остаётся запасным путём и нужна: камеру ставят и до того, как
## модель построена, и скелета в этот момент ещё нет.
func _eye_pivot() -> Vector3:
	var eye := VIEW_FIRST_PIVOT
	if _skeleton == null or not is_inside_tree():
		return eye
	var head := RIG.bone(_skeleton, "Head")
	if head < 0:
		return eye
	var at: Vector3 = (_skeleton.global_transform * _skeleton.get_bone_global_pose(head)).origin
	var above: float = at.y - global_position.y + EYE_ABOVE_HEAD_BONE
	# Модель может быть ещё не в позе, и тогда число выходит мусорным. Под
	# землю и на второй этаж камеру за собой не тащим.
	if above < 0.2 or above > 2.5:
		return eye
	eye.y = above
	return eye


## Своя ли это камера: живой игрок, а не герой под ИИ и не чужой персонаж.
func mine_view() -> bool:
	return is_multiplayer_authority() and not ai_led


func _apply_view() -> void:
	if _pivot == null or _arm == null:
		return
	# Фон поёт вокруг СЛУШАТЕЛЯ, и слушатель — свой персонаж. Ставим здесь же,
	# где решается, чья камера: это ровно то же «мой это персонаж или чужой».
	if mine_view():
		Ambience.listener = self
	_pivot.position = _eye_pivot() if _first_person else VIEW_THIRD_PIVOT
	_arm.spring_length = VIEW_FIRST_ARM if _first_person else VIEW_THIRD_ARM
	var hide_body: bool = _first_person and mine_view()
	for mesh in RIG.body_meshes(_skeleton):
		mesh.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			if hide_body else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


## Оружие висит на правой руке: едет с ней по анимации и исчезает вместе с
## оторванной рукой. Точку хвата считает weapon_visual по габаритам руки.
## Пересобираем не только при смене оружия, но и при смене УРОВНЯ снаряжения:
## купленный апгрейд виден по металлу, и увидеть его должны все, а не только
## владелец — уровень едет по сети как часть состояния персонажа.
func _refresh_weapon_visual() -> void:
	if _weapon_shown == sync_weapon and _tier_shown == gear_tier:
		return
	_weapon_shown = sync_weapon
	_tier_shown = gear_tier
	_weapon_visual = WEAPON_VISUAL.attach_at(_weapon_mount, sync_weapon, _weapon_visual, gear_tier)


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
		for zone in _zones[key]:
			if zone != null:
				rids.append((zone as Area3D).get_rid())
	return rids


## Своя достроенная постройка, у которой стоит персонаж. null — рядом ничего.
##
## `kind` -1 — любая; иначе только заданного вида. Второе нужно там, где место
## решает: лучников нанимают у казармы ЛУЧНИКОВ, и стоять для этого у конюшни
## нельзя, даже если конюшня своя и рядом.
##
## Читают это и клиент, и хост: клиент — чтобы показать панель, хост — чтобы
## решить, законна ли заявка. Одна функция на оба ответа не случайно: две
## разошлись бы, и на экране была бы кнопка, которую хост молча отвергает.
func building_at_hand(kind: int = -1) -> Node3D:
	var best: Node3D = null
	var best_gap := INF
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null or not is_instance_valid(building):
			continue
		if int(building.faction) != int(faction):
			continue
		if float(building.progress) < 1.0:
			continue
		if kind >= 0 and int(building.kind) != kind:
			continue
		var size: Vector3 = RES.BUILDING_SIZE[int(building.kind)]
		var dx: float = maxf(absf(global_position.x - building.global_position.x) - size.x * 0.5, 0.0)
		var dz: float = maxf(absf(global_position.z - building.global_position.z) - size.z * 0.5, 0.0)
		var gap: float = Vector2(dx, dz).length()
		if gap > BUILDING_REACH:
			continue
		if gap < best_gap:
			best_gap = gap
			best = building
	return best


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


## Вправить одну перебитую конечность. Лечит только МЕДПУНКТ: лубок в поле не
## накладывают, для этого и нужен лекарь.
func ask_splint() -> void:
	if Net.hosting():
		request_splint()
	else:
		request_splint.rpc_id(1)


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
func request_splint() -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner():
		return
	if not health.alive:
		return
	if not at_workbench():
		_refuse("вправить кость можно только в медпункте на перекрёстке")
		return
	# Ищем, что лечить, ДО списания: платить за пустой заказ нельзя. Та же
	# осторожность, что и у протеза.
	var hurt := -1
	for limb in body.LIMB_KEYS.size():
		if body.is_crippled(limb) and not body.is_severed(limb):
			hurt = limb
			break
	if hurt < 0:
		_refuse("нечего вправлять: перебитых костей нет")
		return
	if not stock.spend(RES.SPLINT_COST):
		_refuse("не хватает на лубок — нужно %s%s"
			% [RES.format_cost(RES.SPLINT_COST),
				RES.shortfall_hint(RES.SPLINT_COST, stock)])
		return
	if not body.heal_limb(hurt):
		# Не сложилось — деньги назад. Списание раньше действия тем и опасно.
		stock.grant(RES.SPLINT_COST)
		return
	print("[медпункт] игрок %d вправил %s" % [peer_id, body.LIMB_KEYS[hurt]])


@rpc("any_peer", "reliable")
func request_prosthetic(new_tier: int) -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner():
		return
	if not health.alive:
		return
	# Некротического в прайсе нет и быть не может: его не покупают.
	if new_tier != BODY.NECROTIC_TIER and not RES.PROSTHETIC_COST.has(new_tier):
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

	# Некротический покупается НЕ ресурсами, а чужими конечностями. Это и есть
	# его смысл: за золото такого не купить ни у кого, только нарубить самому.
	if new_tier == BODY.NECROTIC_TIER:
		for limb in targets:
			var kind := _trophy_kind(limb)
			if trophies[kind] < BODY.NECROTIC_PRICE:
				_refuse("на некротический протез нужно %d чужих %s, есть %d"
					% [BODY.NECROTIC_PRICE, _trophy_name(kind), trophies[kind]])
				return
		for limb in targets:
			var kind := _trophy_kind(limb)
			trophies[kind] -= BODY.NECROTIC_PRICE
			body.grant_prosthetic(limb, new_tier)
		return

	var cost: Array = RES.PROSTHETIC_COST[new_tier]
	if not stock.spend(cost):
		_refuse("не хватает ресурсов на протез")
		return
	for limb in targets:
		body.grant_prosthetic(limb, new_tier)


func ask_eye() -> void:
	if Net.hosting():
		request_eye()
	else:
		request_eye.rpc_id(1)


## Вставить себе чужой глаз. Цена та же, что у конечности, и платится трофеями.
##
## Отдельно от `request_prosthetic` потому, что глаз — не конечность: у него нет
## уровней, ставится он по одному, и «поставить на всё сразу» для него не значит
## ничего.
@rpc("any_peer", "reliable")
func request_eye() -> void:
	if not Net.hosting() or not _sender_is_owner() or not health.alive:
		return
	if not at_workbench():
		_refuse("глаз вставляют только у верстака")
		return
	if body.eyes_missing() <= 0:
		return
	if trophies[Trophy.EYES] < BODY.NECROTIC_PRICE:
		_refuse("на некротический глаз нужно %d чужих глаз, есть %d"
			% [BODY.NECROTIC_PRICE, trophies[Trophy.EYES]])
		return
	if body.grant_eye():
		trophies[Trophy.EYES] -= BODY.NECROTIC_PRICE


## Трофеи: чужие конечности, отрубленные ЛИЧНО. Руки, ноги, глаза — по счётчику.
##
## Считаем не «сколько валяется на земле», а «сколько отрубил ты». Подбирать их
## по одной с поля боя выглядит красиво ровно до первой схватки на два десятка
## человек, после которой поле усеяно кусками и игрок полчаса ходит и кликает.
## А как цена за лучший протез счёт работает точно так же: десять ног — нога.
@export var trophies: PackedInt32Array = PackedInt32Array([0, 0, 0])

## Виды трофеев: руки, ноги, глаза.
enum Trophy { ARMS, LEGS, EYES }


func _trophy_kind(limb: int) -> int:
	return Trophy.ARMS if limb == BODY.Limb.ARM_L or limb == BODY.Limb.ARM_R else Trophy.LEGS


func _trophy_name(kind: int) -> String:
	match kind:
		Trophy.ARMS: return "рук"
		Trophy.LEGS: return "ног"
		_: return "глаз"


## Записать трофей: этот игрок кому-то что-то отрубил.
##
## Зовётся и с персонажа, и с бойца — рубят всех одинаково, и считаться должно
## одинаково. Иначе выгоднее было бы охотиться на людей, а пешек обходить.
func note_trophy(kind: int) -> void:
	if not Net.hosting() or kind < 0 or kind >= trophies.size():
		return
	trophies[kind] += 1


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
		# Вызов не по сети. У героя под ИИ владельца-пира нет вовсе, и сравнивать
		# не с чем: единственный, кто вправе им распоряжаться, — хост, он же его и
		# считает. Заявка ПО СЕТИ сюда не попадает: там sender не ноль, и
		# сравнение с отрицательным peer_id её отобьёт.
		if ai_led:
			return Net.hosting()
		sender = multiplayer.get_unique_id()
	return sender == peer_id


# --- торговля (Этап 8) -----------------------------------------------------

## Игрок стоит у лавки? Клиент считает это же значение, чтобы показать подсказку,
## но решает всё равно хост — иначе покупали бы с другого конца карты.
func at_trader() -> bool:
	var world := get_parent().get_parent()
	if world == null or not world.has_method("is_at_trader"):
		return false
	return world.is_at_trader(global_position, int(faction))


## Кому принадлежит лавка, у которой стоишь. Своя и только своя: у каждой
## стороны теперь собственная лавка в её зоне.
##
## РАНЬШЕ ЛАВКА БЫЛА ОДНА НА ВСЮ КАРТУ, эльфийская, и обслуживала всех по
## отношениям. Живой игрок за злодея дошёл до неё и написал: «зачем мне туда, не
## понятно», а потом «меня там сразу убили». Он был прав: путь за снаряжением
## лежал через пятьсот семьдесят метров чужого леса.
func trader_faction() -> int:
	return int(faction)


## Цена у своей лавки. Наценок и скидок больше нет: система отношений вырезана
## по решению автора игры, а вместе с ней и торговля с чужими.
func trade_cost(base: Array) -> Array:
	return base


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
		RES.Trade.ARROWS:
			_server_buy_arrows()


func _server_buy_bandages() -> void:
	if body.bandages >= RES.BANDAGE_LIMIT:
		return
	if not stock.spend(bandage_cost()):
		return
	body.bandages = mini(RES.BANDAGE_LIMIT, body.bandages + RES.BANDAGE_PACK)
	print("[торг] игрок %d купил бинты, стало %d" % [peer_id, body.bandages])


## Цена пачки стрел с учётом отношения к хозяевам лавки — как у бинтов.
func arrow_cost() -> Array:
	return trade_cost(RES.ARROW_COST)


func _server_buy_arrows() -> void:
	if arrows >= RES.QUIVER_LIMIT:
		return
	if not stock.spend(arrow_cost()):
		return
	arrows = mini(RES.QUIVER_LIMIT, arrows + RES.ARROW_PACK)
	print("[торг] игрок %d купил стрелы, в колчане %d" % [peer_id, arrows])


func _server_buy_gear() -> void:
	var next := gear_tier + 1
	if not RES.GEAR_COST.has(next):
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
func _server_try_harvest(aim: Vector3, kind: int = WEAPONS.Kind.SWORD) -> bool:
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

	var resource: int = int(target.get_meta("resource", RES.Kind.WOOD))
	# Топором рубят дерево, молотом бьют камень — тем же ударом, которым дерутся.
	# Отдельного режима добычи нет и не нужно: инструмент и оружие это одно и то
	# же, и выбор оружия становится ещё и выбором, чем ты сегодня работаешь.
	var yield_now: int = int(round(RES.YIELD_PER_HIT * WEAPONS.harvest_bonus(kind, resource)))
	var taken: int = stock.add(resource, yield_now)
	harvested.rpc(hit.get("position", origin), resource, taken)

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
		_refuse("не хватает ресурсов на %s — нужно %s%s"
			% [RES.BUILDING_NAMES[building_kind],
				RES.format_cost(RES.BUILDING_COST[building_kind]),
				RES.shortfall_hint(RES.BUILDING_COST[building_kind], stock)])
		return
	if not BUILD_CONTROLLER.is_spot_buildable(self, point, building_kind):
		_refuse("здесь строить нельзя: %s не встанет на этом месте" % RES.BUILDING_NAMES[building_kind])
		return

	if not stock.spend(cost):
		return
	var world := get_parent().get_parent()
	world.spawn_building(building_kind, point, peer_id)


# --- караван и подбор груза -----------------------------------------------

## Сколько караванов игрок может держать в пути одновременно.
const MAX_CARAVANS := 2

const CARAVAN := preload("res://scripts/economy/caravan.gd")

## Сколько лошадей запрягать в следующий обоз. Две по умолчанию: одна тащит
## слишком медленно, а шестёрка — это половина конюшни в одном рейсе.
var harness_size := 2
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
	var storage: Node3D = world.storage_of(int(faction))
	if storage == null:
		_refuse("каравану некуда возвращаться: сначала дострой склад")
		return
	if world.caravans_of(peer_id).size() >= MAX_CARAVANS:
		_refuse("больше караванов в пути держать нельзя, дождись возврата")
		return

	var route := PackedVector3Array()
	route.append(storage.global_position)
	for point in points:
		if absf(point.x) > ROUTE_BOUND or absf(point.z) > ROUTE_BOUND:
			_refuse("точка маршрута вне карты, караван не отправлен")
			return
		route.append(point)
	route.append(world.mine.global_position)

	# Запрягаем столько, сколько ЕСТЬ и сколько просили. Свободных меньше —
	# едем меньшей упряжкой и говорим об этом, а не отказываем: обоз с одной
	# лошадью всё равно доедет, просто медленно.
	var wallet: Node = world.treasury.of(int(faction))
	var free: int = wallet.horses_free() if wallet != null else 0
	if free <= 0:
		_refuse("некого запрягать: свободных лошадей нет, купи в конюшне")
		return
	var team: int = mini(harness_size, free)
	if wallet != null:
		wallet.horses_out += team
	if team < harness_size:
		_show_note("свободных лошадей %d — запрягли столько" % team)
	world.spawn_caravan(route, peer_id, -1, team)


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


# --- верхом ----------------------------------------------------------------

const HORSE := preload("res://scripts/units/horse.gd")

## На какой лошади едем. Пусто — идём пешком.
@export var mount_path := NodePath()


## Чужой обоз рядом, который СТОИТ и у которого есть кого выпрягать.
##
## Захват возможен только у стоящего: на ходу лошадей не выпрягают. Остановить
## обоз можно двумя способами — подойти к нему (возница встаёт, когда рядом
## враг) или выбить лошадей до нуля, но тогда выпрягать уже некого.
func caravan_to_rob() -> Node3D:
	var world := get_parent().get_parent()
	var spawned: Node = world.get_node_or_null("Spawned")
	if spawned == null:
		return null
	for child in spawned.get_children():
		if not child.has_method("capture_horses") or not ("faction" in child):
			continue
		if int(child.faction) == int(faction):
			continue
		if not child.halted or int(child.horses) <= 0:
			continue
		if child.global_position.distance_to(global_position) <= ROB_RANGE:
			return child
	return null


## Дальше этого лошадей не выпрягают.
const ROB_RANGE := 6.0
## На сколько метров от СТЕНЫ постройки с ней можно иметь дело.
##
## От стены, а не от центра: постройки по десять-четырнадцать метров в
## поперечнике, и «в шести метрах от центра» значило бы «внутри дома».
const BUILDING_REACH := 8.0


## Увести лошадей у стоящего чужого обоза.
func ask_rob_caravan() -> void:
	if Net.hosting():
		request_rob_caravan()
	else:
		request_rob_caravan.rpc_id(1)


@rpc("any_peer", "reliable")
func request_rob_caravan() -> void:
	if not Net.hosting() or not _sender_is_owner() or not health.alive:
		return
	var cart := caravan_to_rob()
	if cart == null:
		_refuse("выпрягать нечего: обоз должен стоять и быть чужим")
		return
	var taken: int = cart.capture_horses()
	if taken <= 0:
		return
	var world := get_parent().get_parent()
	# Лошади встают рядом с обозом ЖИВЫМИ телами, а не числом в казне: увести
	# их до дома — отдельная работа, и по дороге их могут отбить.
	for i in taken:
		world.spawn_horse(cart.global_position + Vector3(2.0 + float(i) * 2.0, 0.0, 2.0))
	print("[караван] игрок %d увёл лошадей: %d" % [peer_id, taken])


## Свободная лошадь рядом, на которую можно сесть.
func horse_nearby() -> Node3D:
	for node in get_tree().get_nodes_in_group("horse"):
		var horse := node as Node3D
		if horse == null or not horse.can_mount():
			continue
		if horse.global_position.distance_to(global_position) <= HORSE.MOUNT_RANGE:
			return horse
	return null


func riding() -> Node3D:
	if mount_path.is_empty():
		return null
	return get_node_or_null(mount_path) as Node3D


## Сесть или спешиться — одной и той же клавишей.
##
## Отдельной кнопки «слезть» не заводим: игрок и так помнит, что он верхом, а
## лишняя клавиша в списке из тридцати — это ещё одна строка, которую не
## прочитают.
func ask_mount() -> void:
	if Net.hosting():
		request_mount()
	else:
		request_mount.rpc_id(1)


@rpc("any_peer", "reliable")
func request_mount() -> void:
	if not Net.hosting() or not _sender_is_owner() or not health.alive:
		return
	var riding_now := riding()
	if riding_now != null:
		# Спешиваемся рядом с собой, а не там, где сели: иначе лошадь остаётся
		# на другом конце карты и до неё надо возвращаться пешком.
		riding_now.dismount(global_position + Vector3(1.5, 0.0, 0.0))
		mount_path = NodePath()
		print("[лошадь] игрок %d спешился" % peer_id)
		return
	var horse := horse_nearby()
	if horse == null:
		_refuse("рядом нет свободной лошади")
		return
	if not horse.mount(peer_id):
		_refuse("эта лошадь уже под седлом")
		return
	mount_path = horse.get_path()
	print("[лошадь] игрок %d сел верхом" % peer_id)


## Во сколько раз быстрее верхом. Пешком — единица.
func mount_speed_scale() -> float:
	return HORSE.RIDE_SPEED_SCALE if riding() != null else 1.0


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


## Нанять бойца. archer — лучник вместо мечника; у них разные казармы и разная
## цена, но одна очередь и один потолок отряда.
func ask_train_unit(archer: bool = false) -> void:
	if Net.hosting():
		request_train_unit(archer)
	else:
		request_train_unit.rpc_id(1, archer)


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
## --- видимые отказы --------------------------------------------------------
##
## Живой тестер за пятнадцать минут четыре раза нажал «нанять» и три раза
## «построить казарму». Каждый раз хост отказывал по делу — не хватало
## ресурсов, не было казармы, — и каждый раз писал причину ТОЛЬКО в лог.
## На экране не менялось ничего, и человек решил, что игра сломана. Отказ,
## который видит один лог, для игрока неотличим от бага.
##
## Причину отказа считает хост (он один знает состояние мира) и отправляет её
## тому пиру, чью заявку отклонил.

## Хост отклонил заявку: показать причину владельцу персонажа.
signal refused(reason: String)


## Отказать по заявке. Вызывает ТОЛЬКО хост, вместо голого push_warning.
func _refuse(reason: String) -> void:
	push_warning("Игрок %d: %s" % [peer_id, reason])
	# Герою под ИИ отказ показывать некому, а `rpc_id(-1)` — ошибка в каждом кадре.
	if ai_led:
		return
	if peer_id == Net.local_id():
		refused.emit(reason)
	else:
		_show_refusal.rpc_id(peer_id, reason)


@rpc("authority", "reliable")
func _show_refusal(reason: String) -> void:
	refused.emit(reason)


## Сказать игроку то, что не является отказом.
##
## «Запрягли меньше, чем просили» — не отказ: обоз уехал, просто медленнее. Но
## сказать об этом надо, иначе человек считает, что его выбор упряжки не
## работает, и повторяет его в пустоту. Идёт тем же каналом, что и отказы: в
## интерфейсе для этого уже есть строка.
func _show_note(text: String) -> void:
	if ai_led:
		return
	if peer_id == Net.local_id():
		refused.emit(text)
	else:
		_show_refusal.rpc_id(peer_id, text)


# --- батраки ---------------------------------------------------------------
#
# Батраки принадлежат СТОРОНЕ, а не персонажу, поэтому заявка идёт от игрока, а
# считает и спавнит хост — как со стройкой и наймом мечников.

func ask_hire_labourer() -> void:
	if Net.hosting():
		request_hire_labourer()
	else:
		request_hire_labourer.rpc_id(1)


## Отправить свой отряд сопровождать свою же повозку.
func ask_escort_caravan() -> void:
	if Net.hosting():
		request_escort_caravan()
	else:
		request_escort_caravan.rpc_id(1)


## Приставить отряд к своему каравану (GDD, решение по ходу шага 8).
##
## Берём тех бойцов, что уже наняты, а не создаём новых: охрана — это ВЫБОР
## между «войско бьёт» и «войско бережёт груз», и бесплатной она быть не должна.
## Кого приставить, игрок выбирает составом отряда: мечники держат удар, лучники
## бьют издали, ополченцы дёшевы.
##
## Повозку берём ближайшую свою: караванов у игрока может быть несколько, и
## спрашивать «какую именно» посреди боя незачем — он и так смотрит на ту, о
## которой думает.
@rpc("any_peer", "reliable")
func request_escort_caravan() -> void:
	if not Net.hosting():
		return
	if not _sender_is_owner() or not health.alive:
		return
	var world := get_parent().get_parent()
	var carts: Array = world.caravans_of(peer_id)
	if carts.is_empty():
		_refuse("сопровождать нечего: своих караванов в пути нет")
		return
	var squad: Array = world.units_of(peer_id)
	if squad.is_empty():
		_refuse("сопровождать некому: отряд пуст")
		return

	var cart: Node = carts[0]
	var closest := INF
	for other in carts:
		var d: float = global_position.distance_to(other.global_position)
		if d < closest:
			closest = d
			cart = other

	var taken := 0
	for unit in squad:
		if cart.add_guard(unit):
			taken += 1
	if taken == 0:
		_refuse("отряд уже сопровождает эту повозку")
		return
	print("[караван] игрок %d приставил охрану: бойцов %d" % [peer_id, taken])


@rpc("any_peer", "reliable")
func request_hire_labourer() -> void:
	if not Net.hosting() or not _sender_is_owner():
		return
	if not health.alive:
		return
	if not FACTIONS.can_build(faction):
		_refuse("батраки есть только у злодея")
		return
	var world := get_parent().get_parent()
	var have: int = world.labourers_of(int(faction)).size()
	if have >= RES.LABOURER_LIMIT:
		_refuse("больше батраков не прокормить: потолок %d" % RES.LABOURER_LIMIT)
		return
	if not stock.spend(RES.LABOURER_COST):
		_refuse("не хватает на батрака — нужно %s%s"
			% [RES.format_cost(RES.LABOURER_COST),
				RES.shortfall_hint(RES.LABOURER_COST, stock)])
		return
	var base: Vector3 = FACTIONS.SPAWN[clampi(int(faction), 0, FACTIONS.COUNT - 1)]
	var angle := float(have) * 0.9
	var spot := base + Vector3(cos(angle) * (5.0 + float(have)), 0.5, sin(angle) * (5.0 + float(have)))
	world.spawn_labourer(int(faction), spot, base, LABOURER.Role.LUMBERJACK)


## Купить лошадь. Нужна конюшня — как мечнику нужна казарма.
func ask_hire_horse() -> void:
	if Net.hosting():
		request_hire_horse()
	else:
		request_hire_horse.rpc_id(1)


@rpc("any_peer", "reliable")
func request_hire_horse() -> void:
	if not Net.hosting() or not _sender_is_owner() or not health.alive:
		return
	var world := get_parent().get_parent()
	# Лошадей берут В КОНЮШНЕ — по той же причине, по которой бойцов нанимают у
	# казармы: место должно быть на карте, а не в списке горячих клавиш.
	if building_at_hand(RES.Building.STABLE) == null:
		if world.stable_of(int(faction)) == null:
			_refuse("лошадей брать негде: сначала построй конюшню (клавиша %d)"
				% (RES.Building.STABLE + 1))
		else:
			_refuse("подойди к конюшне — лошадей берут там")
		return
	var wallet: Node = world.treasury.of(int(faction))
	if wallet == null:
		return
	if wallet.horses >= RES.HORSE_LIMIT:
		_refuse("конюшня полна: больше %d лошадей не держат" % RES.HORSE_LIMIT)
		return
	if not stock.spend(RES.HORSE_COST):
		_refuse("не хватает на лошадь — нужно %s%s"
			% [RES.format_cost(RES.HORSE_COST),
				RES.shortfall_hint(RES.HORSE_COST, stock)])
		return
	wallet.horses += 1
	print("[конюшня] %s: куплена лошадь, всего %d"
		% [FACTIONS.name_of(int(faction)), wallet.horses])


## Сколько лошадей запрягать в следующий обоз. Меняется на ходу, от одной до
## шести: это и есть выбор между «быстро» и «дёшево, зато много обозов».
func ask_set_harness(size: int) -> void:
	harness_size = clampi(size, CARAVAN.HORSES_MIN, CARAVAN.HORSES_MAX)


func ask_set_labourer_role(role: int) -> void:
	if Net.hosting():
		request_set_labourer_role(role)
	else:
		request_set_labourer_role.rpc_id(1, role)


## Перевести одного батрака на другое дело.
##
## Берём того, кто сейчас занят самым многолюдным делом: без выбора мышью это
## единственный порядок, который не требует от игрока помнить, кого он уже
## переводил, и не оставляет роль пустой при первом же нажатии.
@rpc("any_peer", "reliable")
func request_set_labourer_role(role: int) -> void:
	if not Net.hosting() or not _sender_is_owner():
		return
	if not health.alive:
		return
	var world := get_parent().get_parent()
	var crew: Array = world.labourers_of(int(faction))
	if crew.is_empty():
		_refuse("батраков нет — сначала найми")
		return
	var wanted: int = clampi(role, 0, LABOURER.ROLE_COUNT - 1)

	var counts := {}
	for worker in crew:
		counts[int(worker.sync_role)] = int(counts.get(int(worker.sync_role), 0)) + 1
	var busiest := -1
	var most := 0
	for kind in counts.keys():
		if int(kind) != wanted and int(counts[kind]) > most:
			most = int(counts[kind])
			busiest = int(kind)
	if busiest < 0:
		_refuse("все батраки уже %s" % LABOURER.ROLE_NAMES[wanted])
		return
	for worker in crew:
		if int(worker.sync_role) == busiest:
			worker.set_role(wanted)
			print("[батраки] %s -> %s" % [LABOURER.ROLE_NAMES[busiest], LABOURER.ROLE_NAMES[wanted]])
			return


@rpc("any_peer", "reliable")
func request_train_unit(archer: bool = false) -> void:
	if not Net.hosting() or not _sender_is_owner():
		return
	if not health.alive:
		return
	var world := get_parent().get_parent()
	var kind: int = RES.Building.ARCHER_BARRACKS if archer else RES.Building.SWORD_BARRACKS
	# Нанимают У КАЗАРМЫ, а не откуда угодно на карте. Наём — это дело, которое
	# делают в конкретном месте, и место должно быть видно на карте: иначе
	# казарма превращается в галочку «построено», а не в здание, к которому
	# ходят. Проверяет ХОСТ, потому что клиент может соврать.
	var barracks: Node3D = building_at_hand(kind)
	if barracks == null:
		if world.barracks_of(int(faction), kind) == null:
			_refuse("нанимать негде: сначала построй %s (клавиша %d)"
				% [RES.BUILDING_NAMES[kind], kind + 1])
		else:
			_refuse("подойди к постройке «%s» — нанимают там" % RES.BUILDING_NAMES[kind])
		return
	var squad: Array = world.units_of(peer_id)
	# ВМЕСТИМОСТЬ — ОТ ПОСТРОЕК, а не от константы. Дом дружины на то и дом:
	# без него сторона держит только охрану.
	var room: int = world.squad_capacity(int(faction))
	if squad.size() >= room:
		_refuse("отряд полон: %d из %d — построй дом дружины (клавиша 5), он даёт ещё %d"
			% [squad.size(), room, RES.HOUSE_SLOTS])
		return
	var cost: Array = RES.ARCHER_COST if archer else RES.UNIT_COST
	if not stock.spend(cost):
		_refuse("не хватает ресурсов на %s — нужно %s%s"
			% ["лучника" if archer else "мечника", RES.format_cost(cost),
				RES.shortfall_hint(cost, stock)])
		return
	# Разводим по спирали: если спавнить всех в одну точку, капсулы влезают друг
	# в друга и CharacterBody3D потом не может их расцепить.
	var index: int = squad.size()
	var angle: float = float(index) * 0.9
	var radius: float = 3.0 + float(index) * 0.45
	var offset := Vector3(cos(angle) * radius, 1.0, 9.0 + sin(angle) * radius)
	world.spawn_unit(peer_id, index, barracks.global_position + offset, false, archer)


# --- фракция --------------------------------------------------------------

## Где сторона появляется. Слот разводит нескольких игроков одной стороны,
## хотя в срезе стороны в сессии уникальны.
func faction_spawn() -> Vector3:
	var base: Vector3 = FACTIONS.SPAWN[clampi(faction, 0, FACTIONS.COUNT - 1)]
	return base + Vector3(float(spawn_slot) * 3.0, 0.0, 0.0)


## Сбить с ног на столько секунд. Только на хосте. Повторный удар не суммируется,
## а продлевает: иначе двое с молотами держали бы цель сбитой бесконечно.
func stagger(seconds: float) -> void:
	if not Net.hosting():
		return
	sync_stagger = maxf(sync_stagger, seconds)


func _select_weapon(kind: int) -> void:
	if kind >= 0 and FACTIONS.allows_weapon(faction, kind):
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


## Для автопроверок: ВИДНО ли, что конечности нет.
##
## Спрашиваем модель, а не маску: маска и вид расходятся молча, и разошлись бы
## при первой же смене персонажа.
func limb_hidden(limb: int) -> bool:
	return RIG.is_collapsed(_skeleton, limb)


## Для автопроверок: что сейчас играет и зациклено ли оно.
##
## Под `name` отдаём слово ИГРЫ («walk»), а не название клипа в паке («Walk»,
## а в следующем паке будет третье). Проверка спрашивает «идёт ли он», и ответ
## на этот вопрос не должен меняться от смены модели. Название клипа кладём
## рядом, для разбора провалов.
func animation_state() -> Dictionary:
	if _anim == null:
		return {}
	var clip: String = _anim.current_animation
	var anim: Animation = _anim.get_animation(clip) if clip != "" else null
	return {
		"name": _current_anim,
		"clip": clip,
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
