extends "res://tools/test_base.gd"
##
## Автопроверка экономики (Этап 4): добыча ресурсов и стройка. Работает headless.
##
## Запуск: godot --headless --path godot_project -- --host --econtest
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "эконом"
	expected_host = 21
	expected_client = 2
	_world = world
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	if not Net.hosting():
		await _run_client(me)
		finish()
		return

	_test_treasury(me)
	await _test_harvest(me, RES.Kind.WOOD, "рубка дерева")
	await _test_harvest(me, RES.Kind.STONE, "добыча камня")
	await _test_capacity(me)
	await _test_build(me)
	await _test_prosthetic_cost(me)
	_test_shortfall_hint(me)

	finish()


## Найти ближайший к точке источник нужного ресурса.
## Источники нужного вида, от ближнего к дальнему.
##
## Ближайший не всегда годится: между ним и персонажем может стоять что-то ещё.
## Так и вышло, когда у злодея появилась своя роща — она встала между фортом и
## горами, персонаж бил по стволу и «добыча камня» проваливалась на ровном месте.
func _sources_by_distance(kind: int, from: Vector3) -> Array:
	var found := []
	for node in get_tree().get_nodes_in_group("harvestable"):
		var body := node as Node3D
		if body == null or int(body.get_meta("resource", -1)) != kind:
			continue
		found.append(body)
	found.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	return found


## Смотрит ли персонаж прямо на источник. Тот же луч, которым добычу считает
## сама игра (player.gd::_server_try_harvest).
func _aims_at(me: Node3D, source: Node3D) -> bool:
	var origin: Vector3 = me.aim_origin()
	var forward := -me.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * RES.HARVEST_RANGE)
	query.collision_mask = 1
	var hit: Dictionary = me.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") == source


func _test_harvest(me: Node3D, kind: int, label: String) -> void:
	var candidates := _sources_by_distance(kind, me.global_position)
	if candidates.is_empty():
		check(false, label, "источник не найден на карте")
		return

	# Встаём у КРАЯ источника, а не в двух метрах от его центра: горы у злодея
	# бывают шириной в десятки метров, и такая точка оказывается внутри скалы.
	#
	# И проверяем, что удар ПРИДЁТСЯ ПО НЕМУ: если между нами и источником что-то
	# выросло, берём следующий. Иначе проверка добычи молча превращается в
	# проверку того, что рядом стоит дерево.
	var source: Node3D = null
	for candidate in candidates:
		# Подход меряем по ФОРМЕ СТОЛКНОВЕНИЯ, а не по мешам.
		#
		# По мешам считалось раньше, и это сломалось в тот день, когда крона
		# дерева стала ребёнком ствола: ширина кроны — десять метров, проверка
		# отходила на шесть с половиной и била в воздух, потому что рука столько
		# не достаёт. Бить можно по тому, во что упираешься, — то есть по
		# коллизии; крона же украшение и через неё проходят насквозь.
		var reach := 2.0
		for child in candidate.get_children():
			var shape := child as CollisionShape3D
			if shape == null or shape.shape == null:
				continue
			if shape.shape is CylinderShape3D:
				reach = maxf(reach, (shape.shape as CylinderShape3D).radius + 1.6)
			elif shape.shape is BoxShape3D:
				var size: Vector3 = (shape.shape as BoxShape3D).size
				reach = maxf(reach, maxf(size.x, size.z) * 0.5 + 1.6)
		var to_source: Vector3 = candidate.global_position - me.global_position
		to_source.y = 0.0
		var dir := to_source.normalized()
		me.global_position = candidate.global_position - dir * reach
		me.global_position.y = 2.0
		me.sync_position = me.global_position
		me.rotation.y = atan2(-dir.x, -dir.z)
		me.velocity = Vector3.ZERO
		await get_tree().create_timer(0.3).timeout
		if _aims_at(me, candidate):
			source = candidate
			break
	if source == null:
		check(false, label, "не нашлось источника, по которому получается ударить")
		return

	var before: int = me.stock.get_amount(kind)
	me.sync_weapon = 0                      # меч
	me.scripted_input = {"move": Vector2.ZERO, "jump": false, "attack": true}
	await get_tree().create_timer(3.0).timeout
	me.scripted_input = {}
	var after: int = me.stock.get_amount(kind)

	check(after > before, label, "%s: %d -> %d" % [RES.NAMES[kind], before, after])


func _test_capacity(me: Node3D) -> void:
	var before: int = me.stock.capacity
	me.stock.raise_capacity(RES.STORAGE_BONUS)
	check(me.stock.capacity == before + RES.STORAGE_BONUS,
		"склад поднимает потолок хранения", "%d -> %d" % [before, me.stock.capacity])

	# Сверх потолка не влезает.
	me.stock.grant([10, 0, 0, 0])
	me.stock.set_carried_capacity(10)
	var taken: int = me.stock.add(RES.Kind.WOOD, 50)
	check(taken == 0 and me.stock.get_amount(RES.Kind.WOOD) == 10,
		"сверх потолка не принимается", "влезло %d" % taken)


func _give(me: Node3D, wood: int, stone: int, gold: int, iron: int) -> void:
	me.stock.grant([wood, stone, gold, iron])
	await get_tree().process_frame


## Ближайшая постройка к точке. Нужна, чтобы посмотреть, что под ней выросло.
func _nearest_building(at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_gap := INF
	for node in _buildings():
		var gap: float = node.global_position.distance_to(at)
		if gap < best_gap:
			best_gap = gap
			best = node
	return best if best_gap < 40.0 else null


func _buildings() -> Array:
	return get_tree().get_nodes_in_group("building")


func _test_build(me: Node3D) -> void:
	# Ровная площадка в стороне от перекрёстка и стартовых ресурсов.
	var spot := Vector3(60.0, 0.0, 60.0)

	# Без ресурсов строить нельзя.
	await _give(me, 0, 0, 0, 0)
	var before: int = _buildings().size()
	me.request_build(RES.Building.STORAGE, spot)
	await get_tree().create_timer(0.4).timeout
	check(_buildings().size() == before, "без ресурсов склад не ставится", "построек %d" % _buildings().size())

	# С ресурсами — ставится, и стоимость списывается.
	await _give(me, 200, 200, 200, 200)
	var wood_before: int = me.stock.get_amount(RES.Kind.WOOD)
	me.request_build(RES.Building.STORAGE, spot)
	await get_tree().create_timer(0.4).timeout
	var placed: bool = _buildings().size() == before + 1
	check(placed, "склад поставлен", "построек %d" % _buildings().size())
	check(me.stock.get_amount(RES.Kind.WOOD) < wood_before,
		"стоимость списана", "дерево %d -> %d" % [wood_before, me.stock.get_amount(RES.Kind.WOOD)])

	# Второй склад вплотную к первому не влезает.
	var packed: int = _buildings().size()
	me.request_build(RES.Building.STORAGE, spot + Vector3(2.0, 0.0, 2.0))
	await get_tree().create_timer(0.4).timeout
	check(_buildings().size() == packed, "вплотную к соседнему зданию не ставится",
		"построек %d" % _buildings().size())

	# НА ПЕРЕПАДЕ ВЫСОТ СТРОИТЬ МОЖНО — и это новое правило, отменившее
	# прежнее. Здесь стояла обратная проверка: «на неровном месте не ставится».
	# Она была верна, пока карта была плоской и ровного места хватало; с
	# рельефом она запретила стройку почти везде.
	#
	# Теперь дом садится на самую высокую точку под собой, под низкими углами
	# встают сваи, ко входу приставляется пандус. Проверяем ровно это: что дом
	# ПОСТРОИЛСЯ и что опора под ним появилась.
	var slope := Vector3(480.0, 0.0, -300.0)
	var on_slope: int = _buildings().size()
	me.request_build(RES.Building.SWORD_BARRACKS, slope)
	await get_tree().create_timer(0.6).timeout
	check(_buildings().size() == on_slope + 1, "на перепаде высот дом СТАВИТСЯ",
		"построек %d было, %d стало" % [on_slope, _buildings().size()])

	var on_hill: Node3D = _nearest_building(slope)
	if on_hill != null:
		var footing: Node = on_hill.get_node_or_null("Footing")
		var posts := 0
		var ramps := 0
		if footing != null:
			for child in footing.get_children():
				if child is StaticBody3D:
					ramps += 1
				else:
					posts += 1
		check(posts > 0, "под ним выросли сваи", "столбов %d" % posts)
		# Пандус — с коллизией: без неё дом на сваях недоступен, и заметит это
		# только тот, кто попробует войти.
		check(ramps > 0, "и подмостки, по которым можно войти",
			"тел с коллизией %d" % ramps)

	# Достроенный склад поднимает потолок.
	var cap_before: int = me.stock.capacity
	await get_tree().create_timer(RES.BUILD_TIME[RES.Building.STORAGE] + 1.5).timeout
	check(me.stock.capacity > cap_before, "достроенный склад поднял потолок",
		"%d -> %d" % [cap_before, me.stock.capacity])


func _test_prosthetic_cost(me: Node3D) -> void:
	# Отрываем руку и встаём к верстаку.
	me.body.reset()
	me.health.revive()
	for i in 6:
		me.body.register_hit("arm_r", 12.0)
		me.health.revive()
	me.body.bleeding = false
	me.global_position = _world.workbench_position() + Vector3(0.0, 2.0, 2.0)
	me.sync_position = me.global_position
	await get_tree().create_timer(0.4).timeout

	await _give(me, 0, 0, 0, 0)
	me.request_prosthetic(1)
	await get_tree().process_frame
	check(me.body.tier(0 if me.body.is_severed(0) else 1) == 0,
		"без ресурсов протез не выдают", "уровень протеза 0")

	await _give(me, 200, 200, 200, 200)
	var wood_before: int = me.stock.get_amount(RES.Kind.WOOD)
	me.request_prosthetic(1)
	await get_tree().process_frame
	var limb := 0 if me.body.is_severed(0) else 1
	check(me.body.tier(limb) == 1 and me.stock.get_amount(RES.Kind.WOOD) < wood_before,
		"деревянный протез крафтится за древесину",
		"уровень %d, дерево %d -> %d" % [me.body.tier(limb), wood_before, me.stock.get_amount(RES.Kind.WOOD)])


# --- клиент: пробует строить за чужой счёт --------------------------------

func _run_client(me: Node3D) -> void:
	await get_tree().create_timer(2.0).timeout
	var host_player: Node3D = _world.get_node("Players").get_node_or_null("1")
	if host_player == null:
		print("[эконом] клиент: персонаж хоста не найден")
		return

	# Атака 1: приказать ЧУЖОМУ персонажу построить здание. Хост обязан
	# отклонить — заявку прислал не владелец.
	var before: int = _buildings().size()
	host_player.request_build.rpc_id(1, RES.Building.STORAGE, Vector3(90.0, 0.0, 90.0))
	await get_tree().create_timer(1.5).timeout
	check(_buildings().size() == before,
		"клиент не может строить чужим персонажем", "построек %d" % _buildings().size())

	# Атака 2: выписать себе ресурсы локально. Репликация обязана затереть.
	me.stock.grant([9999, 9999, 9999, 9999])
	await get_tree().create_timer(1.5).timeout
	var wood: int = me.stock.get_amount(RES.Kind.WOOD)
	check(wood < 9999, "подделка ресурсов затёрта хостом", "дерева стало %d" % wood)


## Запас принадлежит ФРАКЦИИ, а не персонажу (Этап 10, шаг 0).
##
## Проверяем не «работает как раньше» — это и так показали остальные проверки, —
## а что владелец сменился на самом деле: у персонажа больше нет собственного
## кошелька, а тот, что он отдаёт, лежит в казне его стороны.
func _test_treasury(me: Node3D) -> void:
	check(me.get_node_or_null("Stock") == null, "у персонажа нет своего запаса",
		"ноды Stock нет")

	var mine: Node = _world.treasury.of(me.faction)
	check(mine != null and me.stock == mine, "персонаж отдаёт казну своей стороны",
		FACTIONS.name_of(me.faction))

	# У разных сторон казна разная: общий кошелёк на всех был бы хуже, чем
	# кошелёк на персонаже.
	var others := 0
	for faction in FACTIONS.COUNT:
		if faction != int(me.faction) and _world.treasury.of(faction) != mine:
			others += 1
	check(others == FACTIONS.COUNT - 1, "у каждой стороны своя казна",
		"чужих казн: %d" % others)

	# Трата персонажа уходит из казны фракции, а не из воздуха.
	var before: int = mine.get_amount(RES.Kind.WOOD)
	me.stock.spend([5, 0, 0, 0])
	check(mine.get_amount(RES.Kind.WOOD) == before - 5, "трата уходит из казны стороны",
		"%d -> %d" % [before, mine.get_amount(RES.Kind.WOOD)])
	mine.add(RES.Kind.WOOD, 5)


## Отказ говорит не только СКОЛЬКО не хватает, но и ГДЕ это взять.
##
## Тестер первого playtest прекратил игру на пятнадцатой минуте, и одной из
## трёх причин было «не понял, где источник железа, никаких подсказок в игре не
## увидел». Отказ честно называл цену и молчал о том, что железо не рубится и
## не бьётся.
##
## Проверяем ровно границу: подсказка появляется на железе и золоте и НЕ
## появляется на дереве и камне. Подсказка на каждый отказ перестаёт читаться
## через пять минут игры, и «подсказка есть всегда» было бы не лучше, чем
## «подсказки нет никогда».
func _test_shortfall_hint(me: Node3D) -> void:
	var empty: Object = me.stock
	var iron_only: Array = [0, 0, 0, 999]
	var wood_only: Array = [999, 999, 0, 0]
	var both: Array = [0, 0, 999, 999]

	var hint: String = RES.shortfall_hint(iron_only, empty)
	check(hint.contains("железо") and hint.contains("шахте"),
		"на нехватку железа подсказывают шахту", hint.strip_edges())
	check(RES.shortfall_hint(wood_only, empty).is_empty(),
		"на дерево и камень подсказки нет", "пусто, как и задумано")
	var pair: String = RES.shortfall_hint(both, empty)
	check(pair.contains("золото") and pair.contains("железо"),
		"когда не хватает обоих — названы оба", pair.strip_edges())
