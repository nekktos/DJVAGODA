extends "res://tools/test_base.gd"
##
## Поднимается ли ИИ-злодей с нуля САМ.
##
## Запуск: godot --headless --path godot_project -- --host --faction=1 --bootstraptest
##
## ЗАЧЕМ, И ПОЧЕМУ ЭТО ГЛАВНАЯ ПРОВЕРКА ДОРАБОТКИ СТАРТА. Злодей теперь начинает
## с нулём (GDD 9a): ни ресурсов, ни батраков, ни лошадей. Живой игрок идёт к
## микро-шахте и бьёт её сам. А пока человек играет за ЭЛЬФОВ или СТРАЖУ,
## злодеем правит ИИ — и если он не умеет подняться с нуля, он простоит всю
## партию у разрушенного форта. Мир снова мёртв, как уже было с эльфийским ИИ,
## сорвавшим 440 набегов из 442.
##
## Поэтому набор идёт ЗА ЭЛЬФОВ: злодей в нём гарантированно под ИИ. И ничего
## ему не даёт — ни ресурсов, ни батраков. Всё, что у злодея появится, он
## добудет сам, и именно это проверяется.
##
## ПРОВЕРЯЕМ ЦЕПОЧКУ ПО ЗВЕНЬЯМ, а не только конец: если ИИ встал, видно, на
## каком шаге — не дошёл до шахты, дошёл и не бьёт, набил и не нанимает.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")

## Сколько ждём. Дойти до микро-шахты, выбить её, нанять, поставить склад —
## минута-полторы; берём с запасом на медленную машину.
const WAIT_SECONDS := 160.0

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "подъём с нуля"
	expected_host = 5
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(2.0).timeout
	var me: Node3D = _world.local_player()
	if me == null or int(me.faction) == FACTIONS.Kind.VILLAIN:
		fail("набор должен идти НЕ за злодея: злодей обязан быть под ИИ")
		finish()
		return

	var side := FACTIONS.Kind.VILLAIN
	var hits_before := _micro_hits_left()
	check(_world.ai_hero_of(side) != null, "злодеем правит ИИ",
		"героя под ИИ нет")

	var got_resources := false
	var hired := false
	var stored := false
	var waited := 0.0
	while waited < WAIT_SECONDS:
		await get_tree().create_timer(5.0).timeout
		waited += 5.0
		var wallet: Node = _world.treasury.of(side)
		var total := 0
		for kind in RES.COUNT:
			total += int(wallet.get_amount(kind))
		if total > 0:
			got_resources = true
		if not _world.labourers_of(side).is_empty():
			hired = true
		if _world.storage_of(side) != null:
			stored = true
		if got_resources and hired and stored:
			break
	note("прошло %d с" % int(waited))

	check(_micro_hits_left() < hits_before, "ИИ-злодей бьёт микро-шахту сам",
		"ударов в залежах было %d, стало %d" % [hits_before, _micro_hits_left()])
	check(got_resources, "добытое попадает в казну злодея", "казна пуста")
	check(hired, "на добытое ИИ нанимает батраков", "батраков нет")
	check(stored, "и ставит склад — хозяйство пошло", "склада нет")
	finish()


## Сколько ударов осталось во всех залежах микро-шахты.
func _micro_hits_left() -> int:
	var mine := Vector2(WORLD_BUILDER.MICRO_MINE_POS.x, WORLD_BUILDER.MICRO_MINE_POS.z)
	var left := 0
	for node in get_tree().get_nodes_in_group("harvestable"):
		var vein := node as Node3D
		if vein == null:
			continue
		if Vector2(vein.global_position.x, vein.global_position.z).distance_to(mine) > 20.0:
			continue
		left += int(vein.get_meta("hits_left", 0))
	return left
