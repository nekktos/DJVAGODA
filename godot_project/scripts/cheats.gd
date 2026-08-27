extends RefCounted
##
## Консольные команды для playtest.
##
## Выполняются ТОЛЬКО на хосте — по той же причине, по которой хост считает всё
## остальное: выданные локально ресурсы просто затрёт репликация, а спавн юнита
## на клиенте другие пиры не увидят. Клиент отправляет строку, хост разбирает и
## применяет, ответ уходит обратно тому, кто спросил.
##
## Консоль доступна только в отладочной сборке (OS.is_debug_build). В
## экспортированном релизе её не будет.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const FORMATIONS := preload("res://scripts/units/formations.gd")

const HELP := """Команды (выполняет хост):
  res <дер> <кам> <зол> <жел>   выдать ресурсы
  res all <n>                   выдать n каждого
  army <n>                      поставить n бойцов в отряд
  heal                          вылечить и убрать все раны
  hurt <зона> <урон>            урон в зону: head torso arm_l arm_r leg_l leg_r
  limb <зона>                   оторвать конечность сразу
  prosthetic <1-3>              выдать протезы указанного качества
  wheelchair                    сесть или встать из коляски
  bandages <n>                  выдать бинтов
  caravan                       отправить караван по прямой до шахты
  capture                       мгновенно захватить дворец своей стороной
  tp <x> <z>                    телепорт
  goto villain|elves|guard|mine|palace|trader|commander  телепорт к точке
  order done                    засчитать текущий приказ стражи целиком
  save                          сохранить мир прямо сейчас
  load                          перечитать мир из сохранения
  kill                          убить себя
  who                           кто в сессии и за кого играет
  help                          этот список"""


## Разобрать и выполнить. Только на хосте. Возвращает текст ответа.
static func execute(world: Node3D, player: Node3D, line: String) -> String:
	if world == null or player == null:
		return "нет мира или персонажа"
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var command := String(parts[0]).to_lower()
	var args := parts.slice(1)

	match command:
		"help":
			return HELP
		"who":
			return _who(world)
		"res":
			return _res(player, args)
		"bandages":
			return _bandages(player, args)
		"army":
			return _army(world, player, args)
		"heal":
			player.health.revive()
			player.body.reset()
			player.restore_body()
			return "вылечен, раны сняты"
		"hurt":
			return _hurt(player, args)
		"limb":
			return _limb(player, args)
		"prosthetic":
			return _prosthetic(player, args)
		"wheelchair":
			var on: bool = not bool(player.body.in_wheelchair)
			var ok: bool = player.body.set_wheelchair(on)
			return "коляска: %s" % ("сел" if on and ok else ("встал" if ok else "нельзя — ноги целы"))
		"save":
			return _save(world)
		"load":
			return _load(world)
		"order":
			return _order(player, args)
		"caravan":
			return _caravan(world, player)
		"capture":
			world.objective.palace_owner = int(player.faction)
			world.objective.capture_progress = 0.0
			world.objective.announce.rpc("Дворец захвачен: %s" % FACTIONS.name_of(int(player.faction)))
			return "дворец отдан стороне «%s»" % FACTIONS.name_of(int(player.faction))
		"tp":
			return _teleport(player, args)
		"goto":
			return _goto(world, player, args)
		"kill":
			player.health.apply_damage(9999.0, 0)
			return "убит"
	return "неизвестная команда «%s», см. help" % command


static func _who(world: Node3D) -> String:
	var lines := PackedStringArray()
	for child in world.get_node("Players").get_children():
		if not ("faction" in child):
			continue
		lines.append("  id %s — %s, HP %d, бойцов %d" % [
			child.name, FACTIONS.name_of(int(child.faction)),
			int(child.health.current), world.units_of(int(child.peer_id)).size(),
		])
	return "в сессии:\n" + "\n".join(lines)


static func _res(player: Node3D, args: Array) -> String:
	if args.size() == 2 and String(args[0]).to_lower() == "all":
		var value := int(args[1])
		for kind in RES.COUNT:
			player.stock.add(kind, value)
		return "выдано по %d каждого: %s" % [value, player.stock.summary()]
	if args.size() < RES.COUNT:
		return "нужно: res <дер> <кам> <зол> <жел>  или  res all <n>"
	for kind in RES.COUNT:
		player.stock.add(kind, int(args[kind]))
	return "выдано: %s" % player.stock.summary()


static func _bandages(player: Node3D, args: Array) -> String:
	var value: int = int(args[0]) if args.size() > 0 else 5
	player.body.bandages += maxi(0, value)
	return "бинтов теперь %d" % int(player.body.bandages)


## Ставим бойцов в обход казармы и оплаты: консоль для того и нужна.
static func _army(world: Node3D, player: Node3D, args: Array) -> String:
	var count: int = int(args[0]) if args.size() > 0 else 4
	count = clampi(count, 1, RES.SQUAD_LIMIT)
	var have: int = world.units_of(int(player.peer_id)).size()
	var added := 0
	for i in count:
		if have + added >= RES.SQUAD_LIMIT:
			break
		var index: int = have + added
		var angle: float = float(index) * 0.9
		var radius: float = 4.0 + float(index) * 0.5
		var point: Vector3 = player.global_position + Vector3(
			cos(angle) * radius, 1.0, 6.0 + sin(angle) * radius
		)
		world.spawn_unit(int(player.peer_id), index, point)
		added += 1
	return "добавлено бойцов: %d, в отряде %d из %d" % [
		added, world.units_of(int(player.peer_id)).size(), RES.SQUAD_LIMIT
	]


static func _hurt(player: Node3D, args: Array) -> String:
	if args.size() < 1:
		return "нужно: hurt <зона> [урон]"
	var zone := String(args[0]).to_lower()
	var amount: float = float(args[1]) if args.size() > 1 else 20.0
	player.take_damage(amount, int(player.peer_id), zone, player.global_position + Vector3.UP, Vector3.FORWARD)
	return "нанесено %.0f по зоне %s, HP %d" % [amount, zone, int(player.health.current)]


static func _limb(player: Node3D, args: Array) -> String:
	if args.size() < 1:
		return "нужно: limb <arm_l|arm_r|leg_l|leg_r>"
	var zone := String(args[0]).to_lower()
	for i in 12:
		player.health.revive()
		player.body.register_hit(zone, 12.0)
	player.health.revive()
	return "состояние тела: %s" % player.body.summary()


static func _prosthetic(player: Node3D, args: Array) -> String:
	var tier: int = int(args[0]) if args.size() > 0 else 2
	tier = clampi(tier, 1, 3)
	var granted := 0
	for limb in player.body.LIMB_KEYS.size():
		if player.body.is_severed(limb) and player.body.grant_prosthetic(limb, tier):
			granted += 1
	if granted == 0:
		return "нечего протезировать — все конечности на месте"
	return "поставлено протезов: %d, тело: %s" % [granted, player.body.summary()]


## Караван по прямой: консоли не нужен нарисованный маршрут.
static func _caravan(world: Node3D, player: Node3D) -> String:
	var storage: Node3D = world.storage_of(int(player.faction))
	if storage == null:
		return "нет достроенного склада — каравану некуда возвращаться"
	world.spawn_caravan(PackedVector3Array([
		storage.global_position, world.mine.global_position
	]), int(player.peer_id))
	return "караван отправлен по прямой"


static func _teleport(player: Node3D, args: Array) -> String:
	if args.size() < 2:
		return "нужно: tp <x> <z>"
	var point := Vector3(float(args[0]), 4.0, float(args[1]))
	player.teleport.rpc(point)
	return "телепорт в %s" % point


static func _goto(world: Node3D, player: Node3D, args: Array) -> String:
	if args.size() < 1:
		return "нужно: goto villain|elves|guard|mine|palace|trader|commander"
	var where := String(args[0]).to_lower()
	var point := Vector3.ZERO
	match where:
		"villain": point = FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN]
		"elves": point = FACTIONS.SPAWN[FACTIONS.Kind.ELVES]
		"guard": point = FACTIONS.SPAWN[FACTIONS.Kind.GUARD]
		"mine": point = world.mine.global_position + Vector3(0.0, 4.0, 34.0)
		"trader": point = world.trader_position() + Vector3(0.0, 2.0, 4.0)
		"commander": point = world.commander.POSITION + Vector3(0.0, 2.0, 4.0)
		"palace": point = world.objective.PALACE + Vector3(0.0, 4.0, 0.0)
		_: return "не знаю точку «%s»" % where
	player.teleport.rpc(point + Vector3.UP * 2.0)
	return "телепорт к «%s»" % where


## Досрочно закрыть текущий приказ стражи. Нужен для playtest: ждать 25 секунд
## удержания или бежать через полкарты в набег ради проверки цикла — трата
## времени тестировщика, а не проверка механики.
static func _order(player: Node3D, args: Array) -> String:
	const ORDERS := preload("res://scripts/orders.gd")
	if not ("order_kind" in player):
		return "у этого персонажа нет приказов"
	if player.order_kind < 0:
		return "приказа нет — доложись командиру"
	if args.size() < 1 or String(args[0]).to_lower() != "done":
		return "нужно: order done"
	player.order_progress = ORDERS.target_of(player.order_kind)
	return "приказ «%s» отмечен выполненным, доложи командиру" % ORDERS.name_of(player.order_kind)


## Ручное сохранение и загрузка. По GDD раздел 6 нужны слоты; пока это одна
## ячейка на мир, а команды дают проверить её, не дожидаясь автосейва.
static func _save(world: Node3D) -> String:
	var path: String = world.savegame.save_world()
	return "мир сохранён: %s" % path if not path.is_empty() else "сохранить не удалось"


static func _load(world: Node3D) -> String:
	if not world.savegame.has_save():
		return "сохранения нет"
	return "мир загружен" if world.savegame.load_world() else "загрузить не удалось"
