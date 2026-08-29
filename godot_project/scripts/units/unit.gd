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
const BODY := preload("res://scripts/combat/body.gd")
const RIG := preload("res://scripts/combat/rig.gd")
## Виды трофеев — те же цифры, что в `player.gd::Trophy`. Держим их числами, а
## не ссылкой на скрипт игрока: боец о игроке знать не должен.
const TROPHY_ARMS := 0
const TROPHY_LEGS := 1
const TROPHY_EYES := 2
const SEVERED_LIMB := preload("res://scenes/SeveredLimb.tscn")
const WEAPON_VISUAL := preload("res://scripts/combat/weapon_visual.gd")
const MODEL_ANIM := preload("res://scripts/model_anim.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")
const RES := preload("res://scripts/economy/resources.gd")
const ABILITIES := preload("res://scripts/combat/abilities.gd")
const EFFECTS := preload("res://scripts/combat/effects.gd")

## Модель выбирается по РОЛИ, а не по номеру в отряде.
##
## Раньше она бралась по слоту: в толпе своих нельзя было отличить лесоруба от
## ополченца, а лучника от мечника — отдать приказ «поставь двоих на стройку»
## значило гадать. Роль читается с первого взгляда, номер в отряде — нет, и
## смотреть надо именно на неё.
const MODEL_SWORD := "res://assets/people/Warrior.gltf"
const MODEL_ARCHER := "res://assets/people/Ranger.gltf"
const MODEL_CHAMPION := "res://assets/people/Cleric.gltf"
## Волк — настоящая модель со скелетом и анимациями (Quaternius, CC0). До этого
## он собирался из коробок: узнаваемо, но неподвижно, и в бою это было видно.
const MODEL_BEAST := "res://assets/animals/Wolf.gltf"
## Модель волка сделана в натуральную величину «в единицах Blender»: длина 5.5,
## высота 2.7. Приводим к полутора метрам в холке — крупнее настоящего волка,
## но призванный зверь и должен читаться как угроза, а не как собака.
const BEAST_MODEL_SCALE := 0.35
const MODEL_SCALE := 0.63

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

## Оторванные конечности бойца. Биты те же, что у персонажа (`body.gd::Limb`):
## одна система увечий на всех, и цифры в ней значат одно и то же.
##
## Раньше увечья были только у персонажей: бойцу можно было отрубить руку, и
## ничего не происходило — он дрался дальше целым. Разница между «людьми» и
## «пешками» тут не задумана: рубят всех одинаково, и выглядеть это должно
## одинаково.
@export var severed := 0

## Урон, накопленный по зонам. Не реплицируется: считает его хост, а видно
## только результат — оторванную конечность.
var _zone_damage := {}

## Сколько глаз выбито. Реплицируется: поздний клиент обязан увидеть кривого
## кривым, как и безрукого безруким.
@export var eyes_lost := 0

## Урон по голове, накопленный до следующего выбитого глаза. Только у хоста.
var _head_damage := 0.0
var _shown_eyes := 0
## Что уже спрятано на этом пире. Нужно клиенту: маска приходит числом, а меши
## прячутся руками.
var _shown_severed := 0
## Какой моделью пешка показана сейчас. Сравниваем с нужной, чтобы не
## пересобирать её каждый кадр.
var _shown_look := ""

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
## Скелет модели: на нём зоны попадания и расчленение.
var _skeleton: Skeleton3D
## Ключ зоны -> список зон (рука это плечо И предплечье).
var _zones := {}
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


## Зона попадания зверя. Модель волка — один скиннутый меш на скелете: отдельных
## «рук» и «ног» в ней нет и делить её на зоны нечем, поэтому одна зона на всё
## тело. Пока волк собирался коробками, у него не было ни зоны, ни коллизии
## вовсе: призванный зверь был неуязвим и проходил сквозь стены.
func _build_beast_zone() -> void:
	var zone := Area3D.new()
	zone.set_script(HIT_ZONE)
	zone.zone = "torso"
	zone.damage_multiplier = 1.0
	zone.collision_layer = HITBOX_LAYER
	zone.collision_mask = 0
	zone.monitoring = false
	zone.position = Vector3(0.0, 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.9, 1.9)
	shape.shape = box
	zone.add_child(shape)
	add_child(zone)


func _build_model() -> void:
	_shown_look = _look_model()
	var packed: PackedScene = load(_shown_look)
	_model = packed.instantiate()
	_model.name = "Model"
	var model_scale := MODEL_SCALE
	if is_beast:
		model_scale = BEAST_MODEL_SCALE
	elif is_champion:
		model_scale *= CHAMPION_SCALE
	_model.scale = Vector3.ONE * model_scale
	# Модель смотрит в +Z, игра считает передом -Z — см. player.gd::_build_model.
	_model.rotation.y = PI
	add_child(_model)
	if is_champion:
		# Крупнее и в красном: в толпе стражи он должен читаться с первого
		# взгляда, иначе нападать на него будут по незнанию.
		RIG.tint(_model, CHAMPION_COLOR)

	# Тело зверя ниже и длиннее человеческого. Пока волк собирался коробками,
	# этого куска у него не было вовсе: он проходил сквозь всё и по нему нельзя
	# было попасть — призванный зверь был неуязвим и бесплотен.
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	var body_scale := 1.0
	if is_champion:
		body_scale = CHAMPION_SCALE
	capsule.radius = (0.45 if is_beast else 0.35) * body_scale
	capsule.height = (1.0 if is_beast else 1.8) * body_scale
	shape.shape = capsule
	shape.position = Vector3(0.0, capsule.height * 0.5, 0.0)
	add_child(shape)

	_anim = _find_anim(_model)
	# Ходьба должна зацикливаться — см. model_anim.gd.
	MODEL_ANIM.make_looping(_anim)
	if is_beast:
		# Модель волка — один скиннутый меш на скелете: отдельных «рук» и «ног»
		# в ней нет и делить её на зоны нечем. Одна зона на всё тело.
		_build_beast_zone()
		_play("idle")
		return
	# Тело — один скиннутый меш: зоны попадания и расчленение живут на костях.
	_skeleton = RIG.find_skeleton(_model)
	RIG.hide_built_in_weapon(_model)
	_zones = RIG.build_zones(_skeleton, ZONE_MULTIPLIERS, HITBOX_LAYER)
	# Меч в руке — свой, а не тот, что положил художник: он меняется по роли.
	WEAPON_VISUAL.attach_at(RIG.weapon_mount(_skeleton), _hand_weapon(), null, 0)
	_play("idle")


## Какой моделью выглядит эта пешка. Батрак переопределяет — у него роль.
func _look_model() -> String:
	if is_beast:
		return MODEL_BEAST
	if is_champion:
		return MODEL_CHAMPION
	return MODEL_ARCHER if is_archer else MODEL_SWORD


## Что у неё в руке. Тоже про роль: лесоруб с мечом выглядит как ополченец,
## а разницу между ними видеть нужно.
func _hand_weapon() -> int:
	return WEAPONS.Kind.BOW if is_archer else WEAPONS.Kind.SWORD


## Пересобрать облик, если роль сменилась. Роль меняется на ходу — батрак не
## специалист, а пара рук, — и модель обязана меняться вместе с ней, иначе
## переведённый на стройку так и останется на вид лесорубом.
##
## Зовём и у клиента: роль реплицируется, а модель у каждого своя.
func _refresh_look() -> void:
	if is_beast or _model == null or _look_model() == _shown_look:
		return
	_model.queue_free()
	_zones.clear()
	_shown_eyes = 0
	_build_model()
	# Увечья пережили смену роли: новая модель обязана быть такой же калекой.
	_apply_severed()
	_apply_eyes()


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null




## Игра говорит своими словами («walk»), пак называет то же самое по-своему —
## перевод живёт в `model_anim.gd::resolve`.
func _play(anim_name: String) -> void:
	if _anim == null or anim_name == _current_anim:
		return
	var real := MODEL_ANIM.resolve(_anim, anim_name)
	if real == "":
		return
	_current_anim = anim_name
	_anim.play(real)


func _physics_process(delta: float) -> void:
	# Роль меняется на ходу и реплицируется — значит и облик надо сверять у всех
	# и каждый кадр. Проверка дешёвая: сравнение двух строк.
	_refresh_look()
	if not Net.hosting():
		var t := clampf(delta * 14.0, 0.0, 1.0)
		global_position = global_position.lerp(sync_position, t)
		rotation.y = lerp_angle(rotation.y, sync_yaw, t)
		_play("walk" if sync_moving else "idle")
		# Маска увечий приходит репликацией, а прячет конечности локальный код.
		# Поздний клиент обязан увидеть безрукого безруким, и одного вызова при
		# отрыве для этого мало: его в тот момент могло не быть в сессии.
		if severed != _shown_severed:
			_shown_severed = severed
			_apply_severed()
		if eyes_lost != _shown_eyes:
			_apply_eyes()
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
	# Раны замедляют и бойца. Без этого отрубленная нога — украшение: боец без
	# ноги бежал наравне с целым, и рубить конечности не имело смысла ни для
	# кого, кроме зрелища.
	if is_beast:
		return BEAST_SPEED * wound_speed_scale()
	if is_champion:
		return CHAMPION_SPEED * wound_speed_scale()
	return BASE_SPEED * FORMATIONS.speed_scale(_formation()) * wound_speed_scale()


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
	for key in _zones.keys():
		for zone in _zones[key]:
			if zone != null:
				rids.append((zone as Area3D).get_rid())
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
	_note_zone_damage(_zone, scaled, point, dir, attacker_id)
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
	# Труп остаётся лежать — тот же, что у персонажа, и тем же кодом. Боец,
	# который просто исчезает, стирает след боя: по полю после схватки не видно
	# ничего, и понять, что здесь было, нельзя.
	if world != null and world.has_method("place_corpse"):
		world.place_corpse(global_position, rotation.y, slot, severed)
	queue_free()


## Копим урон по зонам и отрываем конечность, когда её запас исчерпан.
##
## Числа берём у персонажа (`body.gd`): один и тот же удар должен отрывать руку
## одинаково и человеку, и бойцу. Своя таблица здесь означала бы, что игрок
## расчленяет пешек легче или тяжелее, чем игроков, и никто не смог бы сказать,
## почему.
func _note_zone_damage(zone: String, amount: float, point: Vector3, dir: Vector3, attacker_id := 0) -> void:
	if not Net.hosting() or zone == "" or zone == "torso":
		return
	if zone == "head":
		# Глаз выбивают тем же порогом, что и человеку. Пешка, которой можно
		# отрубить руку, но нельзя выбить глаз, была бы наполовину живой.
		_head_damage += amount
		while _head_damage >= BODY.EYE_THRESHOLD and eyes_lost < 2:
			_head_damage -= BODY.EYE_THRESHOLD
			eyes_lost += 1
			lose_eye.rpc(point, dir)
			_award_trophy(attacker_id, TROPHY_EYES)
		return
	var limb := BODY.LIMB_KEYS.find(zone)
	if limb < 0:
		return
	if severed & (1 << limb) != 0:
		return
	_zone_damage[zone] = float(_zone_damage.get(zone, 0.0)) + amount
	if float(_zone_damage[zone]) < BODY.LIMB_DURABILITY:
		return
	severed |= (1 << limb)
	tear_off.rpc(limb, point, dir)
	var arm := limb == BODY.Limb.ARM_L or limb == BODY.Limb.ARM_R
	_award_trophy(attacker_id, TROPHY_ARMS if arm else TROPHY_LEGS)


## Записать отрубленное на счёт нападавшего: из этого крафтится некротический
## протез. Рубить пешек должно засчитываться наравне с людьми — иначе выгодно
## охотиться только на игроков, а войско обходить стороной.
func _award_trophy(attacker_id: int, kind: int) -> void:
	if attacker_id <= 0:
		return
	var world := get_parent().get_parent()
	if world != null and world.has_method("award_trophy"):
		world.award_trophy(attacker_id, kind)


## Выбить глаз у ВСЕХ пиров: тёмная повязка на лице и брызги.
@rpc("authority", "call_local", "reliable")
func lose_eye(point: Vector3, dir: Vector3) -> void:
	EFFECTS.blood(get_parent().get_parent(), point, dir, 30.0)
	_apply_eyes()


## Показать выбитые глаза — кровью на лице (см. `rig.gd::mark_eye_loss`).
func _apply_eyes() -> void:
	if _shown_eyes == eyes_lost:
		return
	_shown_eyes = eyes_lost
	RIG.mark_eye_loss(_model, eyes_lost)


## Оторвать конечность у ВСЕХ пиров: схлопываем кость и роняем кусок.
##
## Своей репликации у этого нет и быть не может: кость схлопывается локально, а
## `severed` реплицируется отдельно — но клиент, подключившийся позже, увидит
## только маску, и по ней сделает то же самое (см. `_apply_severed`).
@rpc("authority", "call_local", "reliable")
func tear_off(limb: int, point: Vector3, dir: Vector3) -> void:
	_apply_severed()
	var root: Node = get_parent().get_parent()
	EFFECTS.blood(root, point, dir, 60.0)
	var piece: Node3D = SEVERED_LIMB.instantiate()
	root.add_child(piece)
	piece.setup(RIG.limb_mesh(limb), Transform3D(Basis(), RIG.limb_point(_skeleton, limb)),
		MODEL_SCALE)


## Показать то, что оторвано. Зовём и при получении маски по сети: поздний
## клиент обязан увидеть безрукого безруким.
func _apply_severed() -> void:
	_apply_eyes()
	RIG.apply_severed(_skeleton, severed)
	for limb in BODY.LIMB_KEYS.size():
		var gone: bool = severed & (1 << limb) != 0
		for zone in _zones.get(BODY.LIMB_KEYS[limb], []):
			# Зона оторванной руки уходит с радара оружия: бить по пустому
			# месту нельзя.
			zone.collision_layer = 0 if gone else HITBOX_LAYER


## Насколько боец медленнее из-за ран. Без ноги — ползёт, как и персонаж.
func wound_speed_scale() -> float:
	var legs := 0
	if severed & (1 << BODY.Limb.LEG_L) != 0:
		legs += 1
	if severed & (1 << BODY.Limb.LEG_R) != 0:
		legs += 1
	if legs >= 2:
		return BODY.CRAWL_SPEED_BOTH / BASE_SPEED
	if legs == 1:
		return BODY.CRAWL_SPEED_ONE / BASE_SPEED
	return 1.0


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
	# Под `name` — слово ИГРЫ, а не название клипа в паке: проверка спрашивает
	# «идёт ли он», и ответ не должен меняться от смены модели.
	var clip: String = _anim.current_animation
	var anim: Animation = _anim.get_animation(clip) if clip != "" else null
	return {
		"name": _current_anim,
		"clip": clip,
		"playing": _anim.is_playing(),
		"looping": anim != null and anim.loop_mode != Animation.LOOP_NONE,
	}


## Перекрасить модель целиком: зверя в тёмное, распорядителя в красное.
## Идём по дереву — у ассетов Kenney меши лежат на разной глубине.
