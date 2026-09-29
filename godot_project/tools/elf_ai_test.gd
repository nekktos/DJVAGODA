extends "res://tools/test_base.gd"
##
## ИИ-эльфы строят дома так же, как игрок (ответ автора от 29.09.2026).
##
## Запуск: godot --headless --path godot_project -- --host --faction=0 --elfaitest
##
## Набор идёт за злодея: эльфы — под ИИ. Проверяем путь целиком: вожак эльфов
## рубит лес у поселения, копит дерево и ставит дом тем же запросом стройки,
## что игрок, — с его ценой и у поселения.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")

const WAIT_SECONDS := 150.0

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "ИИ-эльфы"
	expected_host = 3
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(3.0).timeout
	var elf: Node3D = _world.ai_hero_of(FACTIONS.Kind.ELVES)
	check(elf != null and bool(elf.ai_led), "за пустую сторону эльфов есть ИИ-вожак",
		"вожака нет" if elf == null else "есть")
	if elf == null:
		finish()
		return

	var wallet: Node = _world.treasury.of(FACTIONS.Kind.ELVES)
	var houses_before: int = _world.elf_houses().size()
	var most_wood := 0
	var built: Node3D = null
	var waited := 0.0
	while waited < WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		most_wood = maxi(most_wood, int(wallet.get_amount(RES.Kind.WOOD)))
		if _world.elf_houses().size() > houses_before:
			built = _world.elf_houses()[_world.elf_houses().size() - 1]
			break
	note("прошло %d с" % int(waited))
	# Дерево ПРИШЛО (нарублено) и УШЛО на дом: дом не даром, а за цену игрока.
	var price: int = RES.at(RES.BUILDING_COST[RES.Building.ELF_HOUSE], RES.Kind.WOOD)
	check(most_wood >= price and int(wallet.get_amount(RES.Kind.WOOD)) <= most_wood - price,
		"ИИ-эльф нарубил дерева на дом и заплатил им за стройку",
		"наибольший запас %d при цене %d, сейчас %d" % [most_wood, price,
			int(wallet.get_amount(RES.Kind.WOOD))])
	var near := INF
	if built != null:
		near = Vector2(built.global_position.x, built.global_position.z).distance_to(
			Vector2(FACTIONS.SPAWN[FACTIONS.Kind.ELVES].x, FACTIONS.SPAWN[FACTIONS.Kind.ELVES].z))
	check(built != null and near < 80.0, "и ставит новый дом у поселения",
		"домов %d -> %d, до середины поселения %.0f м" % [houses_before,
			_world.elf_houses().size(), near])
	finish()
