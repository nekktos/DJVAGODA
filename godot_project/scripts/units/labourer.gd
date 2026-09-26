extends "res://scripts/units/unit.gd"
##
## Батрак злодея (Этап 10). Рабочие руки: рубит лес, бьёт камень, работает в
## шахте, строит — или берёт оружие и идёт в ополчение.
##
## ЗАЧЕМ ОТДЕЛЬНЫЙ ВИД, А НЕ РОЛЬ У МЕЧНИКА. Мечник умеет ровно одно: держать
## строй и бить. Батрак умеет четыре разных дела, и все они про работу с местом
## на карте, а не про бой. Смешав их в одном скрипте, я получил бы `_physics_
## process` с четырьмя ветками, из которых боевая нужна одной роли из четырёх.
##
## ЧТО ОН НАСЛЕДУЕТ. Всё, что умеет боец: движение с навигацией, здоровье, зоны
## попадания, кровь, смерть, расталкивание. Своё у него только одно — куда идти,
## когда драться не с кем (`_idle_destination`). Это ровно та развилка, ради
## которой она в `unit.gd` и выделена.
##
## РОЛЬ МЕНЯЕТСЯ НА ХОДУ. По замыслу батрак — не специалист, а пара рук: сегодня
## он на лесе, завтра в ополчении. Поэтому роль это поле, а не отдельный вид
## юнита, и смена роли ничего не пересоздаёт.
##
## Считает ТОЛЬКО хост. Клиент получает позицию, здоровье и роль.
##

const RES2 := preload("res://scripts/economy/resources.gd")

enum Role { LUMBERJACK, MINER, MILITIA, BUILDER, FARMER }

const ROLE_COUNT := 5
const ROLE_NAMES := ["лесоруб", "шахтёр", "ополченец", "строитель", "фермер"]

## Своя модель и свой инструмент на каждое дело. Батраков на карте бывает
## десяток, и все они делают разное: не различив их глазом, хозяин отдаёт
## приказы вслепую — а «поставь двоих на стройку» это ровно про глаз.
## МОДЕЛИ И РОЛИ РАЗЪЕХАЛИСЬ, и это чинится здесь же. Лесоруб был одет
## крестьянином, а ополченец — лесорубом: таблица писалась, когда порядок ролей
## был другим, и после перестановки её не поправили. Рядом стоит строка «цвет
## рубахи говорит о роли столько же, сколько инструмент» — а рубаха врала.
const ROLE_MODELS := [
	"res://assets/people/Woodcutter.glb",
	"res://assets/people/Miner.glb",
	"res://assets/people/Swordsman.glb",
	"res://assets/people/Mason.glb",
	"res://assets/people/Peasant.glb",
]
## Топор лесорубу, молот шахтёру и строителю, меч ополченцу. Инструмент в руке
## говорит о роли столько же, сколько цвет рубахи, и виден с большего расстояния.
const ROLE_WEAPONS := [
	WEAPONS.Kind.AXE,
	WEAPONS.Kind.HAMMER,
	WEAPONS.Kind.SWORD,
	WEAPONS.Kind.HAMMER,
	WEAPONS.Kind.AXE,
]

## Что ищет каждая роль. Шахтёр берёт и шахту, и камень на поверхности: это одно
## занятие с двумя видами месторождения, а не две роли.
const ROLE_RESOURCES := {
	Role.LUMBERJACK: [RES2.Kind.WOOD],
	Role.MINER: [RES2.Kind.STONE, RES2.Kind.IRON],
}

## Сколько единиц батрак уносит за раз. Больше носильщика-игрока не делаем:
## батрак должен быть выгоднее числом, а не грузоподъёмностью.
const LOAD_LIMIT := 30

## Пауза между ударами по источнику.
const WORK_INTERVAL := 1.2

## Ближе этого можно работать. Чуть больше игроцкой HARVEST_RANGE: батрак
## подходит сам и не должен тыкаться носом в текстуру.
const WORK_RANGE := 4.5

## Как часто перевыбирать, где работать. Каждый кадр искать ближайшее дерево
## среди сотен источников — впустую жечь время хоста.
const RETARGET_INTERVAL := 2.0

## Ближе этого батрак бросает работу и уходит.
##
## Небоевой батрак, который стоит и рубит, пока его убивают, — это не стойкость,
## а потерянные руки: он ничего не может сделать в ответ. Бежит он к дому, а не
## куда попало: дома гарнизон, и там его хотя бы прикроют.
##
## Радиус меньше дальности, с которой его заметит боец (ENGAGE_RANGE 14): уходить
## надо ДО того, как по тебе ударили, а не после.
const FLEE_RADIUS := 18.0

## Насколько быстрее идёт стройка с каждым строителем — см. `building.gd`.
## Здесь только для документации: само число применяет постройка.

## Реплицируемая роль: клиент подписывает батрака в HUD.
@export var sync_role: int = Role.LUMBERJACK

## Что несёт с собой. Отдаётся стороне, когда батрак доносит груз до склада.
var load := RES2.empty()

var _work_t := 0.0
## Сколько кормёжек подряд пропущено. Ведёт ХОСТ, реплицируется ради подписи в
## HUD: клиент должен видеть, что его артель голодает, а не гадать.
@export var sync_hunger: int = 0
var _retarget_t := 0.0
## Текущее место работы: источник, стройка или шахта.
var _site: Node3D = null
## Куда нести груз. Пересчитывается, когда груз набран.
var _drop := Vector3.INF
## Склад, к которому несём: до постройки надо мерить от КРАЯ, а не от середины.
var _drop_site: Node3D = null


func setup(data: Dictionary) -> void:
	super(data)
	sync_role = int(data.get("role", Role.LUMBERJACK))


## Ополченец дерётся, остальные — нет. Батрак с топором в руках, бросающийся на
## мечника, — это не храбрость, а потерянные руки.
func _wants_fight() -> bool:
	return sync_role == Role.MILITIA


func _look_model() -> String:
	return ROLE_MODELS[clampi(sync_role, 0, ROLE_COUNT - 1)]


func _hand_weapon() -> int:
	return ROLE_WEAPONS[clampi(sync_role, 0, ROLE_COUNT - 1)]


func role_name() -> String:
	return ROLE_NAMES[clampi(sync_role, 0, ROLE_COUNT - 1)]


func carrying() -> int:
	var total := 0
	for value in load:
		total += value
	return total


## Сменить занятие. Прежнее место работы забываем: с новой ролью оно негодно.
func set_role(role: int) -> void:
	if not Net.hosting():
		return
	sync_role = clampi(role, 0, ROLE_COUNT - 1)
	_site = null
	_retarget_t = RETARGET_INTERVAL


func _idle_destination(delta: float) -> Vector3:
	if sync_role == Role.MILITIA:
		# Ополченец ведёт себя как обычный боец: строй, поводок, пост.
		return super(delta)

	# Враг рядом — бросаем всё и уходим. Проверяем это ПЕРВЫМ: и работа, и
	# доставка груза подождут, а батрак — нет.
	var danger := _threat_nearby()
	if danger != null:
		_site = null
		var away := global_position - danger.global_position
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3.FORWARD
		# Уходим в сторону дома, а не просто от врага: иначе первый же боец
		# загонит батрака в угол карты.
		var homeward: Vector3 = home if home != Vector3.ZERO else global_position
		return global_position + (away.normalized() * 0.5
			+ (homeward - global_position).normalized() * 0.5).normalized() * FLEE_RADIUS

	# Набрал груз — несём на склад. Работа подождёт: батрак, продолжающий рубить
	# с полными руками, просто теряет время.
	#
	# И НЕСЁМ НЕПОЛНОЕ, КОГДА БРАТЬ БОЛЬШЕ НЕЧЕГО. Без этого фермер у пустого
	# поля стоял с горстью еды и ждал полных рук по две минуты: поле растит
	# медленно, и «полные руки» наступали позже, чем сторона успевала
	# проголодаться. То же и с вычерпанной шахтой.
	if carrying() >= LOAD_LIMIT or (carrying() > 0 and _took_nothing):
		return _deliver(delta)

	_retarget_t -= delta
	if _site == null or not is_instance_valid(_site) or _retarget_t <= 0.0:
		_retarget_t = RETARGET_INTERVAL
		_site = _find_site()
	if _site == null:
		# Работы нет — стоим у дома, а не бродим по карте.
		return home if home != Vector3.ZERO else global_position

	var spot: Vector3 = _site.global_position
	if _flat_to(spot) > _work_reach(_site):
		return spot

	_work_t -= delta
	if _work_t <= 0.0:
		# Голодный работает вдвое медленнее. Беда обязана быть видна делом, а не
		# только надписью: цифра в углу экрана читается не всеми, а вставшая
		# добыча — всеми.
		_work_t = WORK_INTERVAL * (RES2.HUNGER_SLOWDOWN if sync_hunger > 0 else 1.0)
		_work_on(_site)
	# Стоим вплотную и работаем.
	return global_position


## Донести груз до места сдачи и высыпать.
func _deliver(delta: float) -> Vector3:
	if not _drop.is_finite():
		_drop = _drop_point()
	# Дальность сдачи — от КРАЯ склада, а не от его середины. Склад 12 на 10
	# метров: батрак упирается в стену за пять метров от центра и не может
	# подойти ближе физически. Он так и стоял с полными руками у собственного
	# склада, пока сторона голодала без дерева.
	#
	# Это ПЯТЫЙ случай одной и той же ошибки: до этого так же не доставали до
	# дерева (начало координат на середине ствола), до стройки строитель, и
	# бойцы не могли разрушить здание. Расстояние до середины большого объекта
	# не значит ничего.
	# Склад могли снести, пока батрак к нему шёл. Проверяем ЗДЕСЬ, а не внутри
	# `_work_reach`: движок сверяет тип аргумента ДО входа в функцию, и
	# освобождённый объект не проходит проверку на `Node3D` — тело функции при
	# этом не выполняется вовсе, и никакая защита внутри не спасает.
	if _flat_to(_drop) > _work_reach(_drop_site if is_instance_valid(_drop_site) else null):
		return _drop

	var world := get_parent().get_parent()
	if world != null and "treasury" in world:
		var wallet: Node = world.treasury.of(faction)
		if wallet != null:
			for kind in RES2.COUNT:
				# Читаем груз ТЕРПИМО. Короткий массив в руках — это чужая
				# ошибка, но платить за неё обрывом сдачи нельзя: однажды так
				# и вышло — дерево зачислилось, а руки не очистились, потому
				# что цикл упал за границу на пятом ресурсе.
				var have: int = RES2.at(load, kind)
				if have <= 0:
					continue
				# Сначала в склад: сложенное там не теряется со смертью. Пока
				# склада нет, у стороны нет и вместимости склада вовсе — тогда
				# кладём при себе, ровно туда же, куда кладёт добычу игрок без
				# склада. Иначе первые батраки сдавали бы груз в никуда: молча,
				# без отказа и без прибытка.
				var left: int = have - wallet.add_stored(kind, have)
				if left > 0:
					wallet.add(kind, left)
	load = RES2.empty()
	_drop = Vector3.INF
	_drop_site = null
	_work_t = 0.0
	return global_position


## Умереть от голода. Отдельно от боевой смерти: тут нет ни убийцы, ни трупа с
## оружием, но груз из рук падает так же — он никуда не делся оттого, что
## хозяин умер не от меча.
func die_of_hunger() -> void:
	if not Net.hosting():
		return
	print("[голод] батрак стороны «%s» умер" % FACTIONS.name_of(faction))
	take_damage(9999.0, 0, "torso", global_position, Vector3.FORWARD)


## Гружёный батрак роняет груз. Руки чистим здесь же: боец сейчас исчезнет, но
## оставлять в нём груз значило бы уронить его дважды, если смерть обработается
## повторно.
func _cargo_on_death() -> PackedInt32Array:
	var dropped := load.duplicate()
	load = RES2.empty()
	return dropped


## С какого расстояния можно работать на этом месте.
##
## У дерева и камня — длина руки. У ПОСТРОЙКИ — плюс её половина: расстояние
## меряется до середины, а склад имеет 12 на 10 метров, и строитель упирается в
## стену за шесть метров от неё. Дойти до середины он не может физически, и без
## этой поправки стройка не ускорялась бы никогда — ни одним строителем.
## Досягаемость до места работы. Освобождённый объект сюда доходить не должен:
## отсекается у вызывающего, см. `_deliver`.
func _work_reach(site: Node3D) -> float:
	if is_instance_valid(site) and site.is_in_group("building") and "kind" in site:
		var size: Vector3 = RES2.BUILDING_SIZE.get(int(site.kind), Vector3.ZERO)
		return WORK_RANGE + maxf(size.x, size.z) * 0.5
	return WORK_RANGE


## Ближайший враг, от которого стоит уйти. Ополченца это не касается — он для
## того и ополченец.
func _threat_nearby() -> Node3D:
	var world := get_parent().get_parent()
	if world == null:
		return null
	for other in world.get_node("Players").get_children():
		if not ("faction" in other) or int(other.faction) == faction:
			continue
		if not other.health.alive:
			continue
		if _flat_to(other.global_position) <= FLEE_RADIUS:
			return other
	for unit in get_tree().get_nodes_in_group("unit"):
		if not is_instance_valid(unit) or not ("faction" in unit):
			continue
		if int(unit.faction) == faction:
			continue
		if _flat_to(unit.global_position) <= FLEE_RADIUS:
			return unit
	return null


## Расстояние до места работы ПО ГОРИЗОНТАЛИ.
##
## Мерить в трёх измерениях здесь нельзя, и это не мелочь. Начало координат у
## ствола — на середине его высоты: батрак стоит в полутора метрах от дерева, а
## «по прямой» до точки отсчёта у него пять, и он вечно идёт к дереву, у которого
## уже стоит. Ровно так роща и не рубилась, пока причину не нашли.
func _flat_to(point: Vector3) -> float:
	return Vector2(global_position.x, global_position.z).distance_to(Vector2(point.x, point.z))


## Куда нести добытое: ближайший достроенный склад своей стороны, иначе домой.
##
## Дом — это точка базы. Без склада батрак всё равно должен куда-то носить,
## иначе первые руки бесполезны до первой постройки, а строить не на что.
func _drop_point() -> Vector3:
	_drop_site = null
	var best: Vector3 = home if home != Vector3.ZERO else global_position
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null or not ("faction" in building):
			continue
		if int(building.faction) != faction or float(building.progress) < 1.0:
			continue
		if int(building.kind) != RES2.Building.STORAGE:
			continue
		var d: float = global_position.distance_to(building.global_position)
		if d < best_distance:
			best_distance = d
			best = building.global_position
			_drop_site = building
	return best


## Сделать один заход работы на месте.
func _work_on(site: Node3D) -> void:
	if sync_role == Role.BUILDER:
		# Стройку двигает сама постройка, считая приставленных строителей
		# (`building.gd`). Батраку остаётся стоять рядом — и он уже стоит.
		return
	if site.has_method("take"):
		# Шахта: берём накопленное, сколько влезет в руки.
		var taken: PackedInt32Array = site.take(LOAD_LIMIT - carrying())
		var got := 0
		for value in taken:
			got += int(value)
		_took_nothing = got <= 0
		var copy := RES2.empty()
		for kind in RES2.COUNT:
			copy[kind] = RES2.at(load, kind) + RES2.at(taken, kind)
		load = copy
		return

	# Дерево и камень всегда отдают удар: у них запас в самом источнике, и пока
	# источник существует, он не пуст.
	_took_nothing = false
	var kind: int = int(site.get_meta("resource", RES2.Kind.WOOD))
	var copy := RES2.empty()
	for i in RES2.COUNT:
		copy[i] = RES2.at(load, i)
	copy[kind] += RES2.YIELD_PER_HIT
	load = copy

	var tree: int = int(site.get_meta("tree", -1))
	var world := get_parent().get_parent()
	if tree >= 0 and world != null:
		if world.forest.hit_tree(tree) <= 0:
			world.forest.fell_tree.rpc(tree)
			_site = null
		return

	var left: int = int(site.get_meta("hits_left", 1)) - 1
	site.set_meta("hits_left", left)
	if left <= 0:
		site.queue_free()
		_site = null


## Где работать. Ближайшее подходящее место для своей роли.
func _find_site() -> Node3D:
	if sync_role == Role.BUILDER:
		return _nearest_site_building()
	if sync_role == Role.FARMER:
		return _nearest_farm()
	var wanted: Array = ROLE_RESOURCES.get(sync_role, [])
	var best: Node3D = null
	var best_distance := INF

	# Шахта для шахтёра — тоже месторождение, и обычно самое богатое.
	if sync_role == Role.MINER:
		var world := get_parent().get_parent()
		if world != null and "mine" in world and world.mine != null:
			best = world.mine
			best_distance = global_position.distance_to(world.mine.global_position)

	for node in get_tree().get_nodes_in_group("harvestable"):
		var source := node as Node3D
		if source == null:
			continue
		if not wanted.has(int(source.get_meta("resource", -1))):
			continue
		var d: float = global_position.distance_to(source.global_position)
		if d < best_distance:
			best_distance = d
			best = source
	return best


## Дал ли источник хоть что-то в последний заход. Ведёт `_work_on`.
##
## СМОТРИМ НА ЗАХОД, А НЕ НА ЗАПАС В КАДРЕ. Первая версия спрашивала у поля,
## пусто ли оно прямо сейчас, — и «пусто» не наступало никогда: поле отрастает
## непрерывно, и между двумя ударами на нём успевала появиться единица. Фермер
## с горстью еды так и стоял у грядки, пока сторона голодала.
var _took_nothing := false


## Ближайшее ДОСТРОЕННОЕ поле своей стороны. Недостроенное не годится: на нём
## ещё ничего не растёт, и фермер стоял бы над котлованом.
func _nearest_farm() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("building"):
		var field := node as Node3D
		if field == null or not ("faction" in field) or not ("kind" in field):
			continue
		if int(field.kind) != RES2.Building.FARM or int(field.faction) != faction:
			continue
		if float(field.progress) < 1.0:
			continue
		var d: float = global_position.distance_to(field.global_position)
		if d < best_distance:
			best_distance = d
			best = field
	return best


## Ближайшая недостроенная постройка своей стороны.
func _nearest_site_building() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null or not ("faction" in building):
			continue
		if int(building.faction) != faction or float(building.progress) >= 1.0:
			continue
		var d: float = global_position.distance_to(building.global_position)
		if d < best_distance:
			best_distance = d
			best = building
	return best


## Стоит ли этот батрак у стройки и помогает ли ей. Спрашивает сама постройка.
func builds(building: Node3D) -> bool:
	if sync_role != Role.BUILDER or _site != building:
		return false
	return _flat_to(building.global_position) <= _work_reach(building)
