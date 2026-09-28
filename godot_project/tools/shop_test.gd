extends "res://tools/test_base.gd"
##
## Лавки сторон и кузня (GDD 9a, ответы автора от 28.09.2026).
##
## Запуск: godot --headless --path godot_project -- --host --faction=0 --shoptest
##
## Решение автора: «уголь — расходный ресурс для кузни, без угля нет огня и
## металлообработка невозможна»; «разный товар и своя лавка: у эльфов травы,
## зелья, луки, лёгкая броня и оружие, у злодея и людей магазины одинаковые,
## но стилистически разные (у злодея латы чёрные, у людей серебряные)».
##
## Набор идёт за злодея: кузня и латы — его.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "лавка и кузня"
	expected_host = 8
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(2.0).timeout
	var me: Node3D = _world.local_player()
	if me == null or int(me.faction) != FACTIONS.Kind.VILLAIN:
		fail("набор должен идти за злодея")
		finish()
		return

	_test_goods_by_side()
	await _test_shop_refuses_foreign_goods(me)
	await _test_armor(me)
	await _test_forge(me)
	_test_who_builds_forge()
	_test_potion(me)
	finish()


func _test_goods_by_side() -> void:
	var villain: Array = RES.SHOP[FACTIONS.Kind.VILLAIN]
	var guard: Array = RES.SHOP[FACTIONS.Kind.GUARD]
	var elves: Array = RES.SHOP[FACTIONS.Kind.ELVES]
	var elf_gear_plain := true
	for tier in RES.ELF_GEAR_COST:
		var cost: Array = RES.ELF_GEAR_COST[tier]
		if RES.at(cost, RES.Kind.IRON) > 0 or RES.at(cost, RES.Kind.COAL) > 0:
			elf_gear_plain = false
	check(villain == guard and not villain.has(RES.Trade.GEAR)
			and not villain.has(RES.Trade.POTION_HEAL)
			and elves.has(RES.Trade.POTION_HEAL) and elves.has(RES.Trade.POTION_MANA)
			and elves.has(RES.Trade.GEAR) and elves.has(RES.Trade.ARMOR) and elf_gear_plain
			and RES.armor_name(FACTIONS.Kind.VILLAIN, 1) != RES.armor_name(FACTIONS.Kind.GUARD, 1),
		"у злодея и стражи товар одинаковый, вид разный; у эльфов — зелья и своё оружие",
		"злодей %s, стража %s, эльфы %s" % [villain, guard, elves])


func _at_trader(me: Node3D) -> void:
	me.teleport.rpc(WORLD_BUILDER.TRADER_POS[FACTIONS.Kind.VILLAIN] + Vector3(0.0, 1.0, 3.0))
	await get_tree().create_timer(0.3).timeout


## Чужого товара своя лавка не продаёт: ни оружия (его куют), ни зелий.
func _test_shop_refuses_foreign_goods(me: Node3D) -> void:
	me.stock.grant(RES.fit([0, 0, 500, 200, 0, 0]))
	await _at_trader(me)
	me.request_trade(RES.Trade.GEAR)
	me.request_trade(RES.Trade.POTION_HEAL)
	await get_tree().physics_frame
	check(me.at_trader() and int(me.gear_tier) == 0 and int(me.potions_heal) == 0,
		"лавка злодея не продаёт оружия и зелий",
		"у лавки %s, оружие %d, зелий %d" % [me.at_trader(), int(me.gear_tier), int(me.potions_heal)])


## Латы режут урон ровно на свою долю и видны на теле.
func _test_armor(me: Node3D) -> void:
	me.request_trade(RES.Trade.ARMOR)
	await get_tree().physics_frame
	var bought: bool = int(me.armor_tier) == 1
	me.health.current = 100.0
	me.take_damage(50.0, 0, "torso", me.global_position, Vector3.FORWARD)
	var lost: float = 100.0 - me.health.current
	var expected: float = 50.0 * RES.armor_taken(FACTIONS.Kind.VILLAIN, 1)
	check(bought and absf(lost - expected) < 0.5,
		"латы куплены и режут урон на свою долю",
		"ступень %d, потеряно %.1f при ожидаемых %.1f" % [int(me.armor_tier), lost, expected])
	me.request_trade(RES.Trade.ARMOR)
	await get_tree().create_timer(0.3).timeout
	var pads := 0
	for node in me.find_children("ArmorPad*", "BoneAttachment3D", true, false):
		pads += 1
	var chest: bool = me.find_child("Armor*", true, false) != null
	check(int(me.armor_tier) == 2 and chest and pads == 2,
		"на второй ступени на теле кираса и два наплечника",
		"ступень %d, кираса %s, наплечников %d" % [int(me.armor_tier), chest, pads])
	me.health.current = 100.0


## Закалка — только у своей кузни и только с углём. Уголь сгорает.
func _test_forge(me: Node3D) -> void:
	me.stock.grant(RES.fit([0, 0, 500, 200, 0, 0]))
	me.request_forge_gear()
	await get_tree().physics_frame
	var no_forge: bool = int(me.gear_tier) == 0
	var spot: Vector3 = me.global_position + Vector3(10.0, 0.0, 0.0)
	_world.spawn_building(RES.Building.FORGE, spot, 0, FACTIONS.Kind.VILLAIN, true)
	await get_tree().create_timer(0.3).timeout
	me.teleport.rpc(spot + Vector3(0.0, 1.0, RES.BUILDING_SIZE[RES.Building.FORGE].z * 0.5 + 2.0))
	await get_tree().create_timer(0.3).timeout
	me.request_forge_gear()
	await get_tree().physics_frame
	var no_coal: bool = int(me.gear_tier) == 0
	me.stock.grant(RES.fit([0, 0, 500, 200, 0, 50]))
	await get_tree().physics_frame
	var coal_before: int = int(me.stock.get_amount(RES.Kind.COAL))
	me.request_forge_gear()
	await get_tree().physics_frame
	var coal_after: int = int(me.stock.get_amount(RES.Kind.COAL))
	check(no_forge and no_coal, "без кузни и без угля оружие не закалить",
		"без кузни %s, без угля %s" % [no_forge, no_coal])
	check(int(me.gear_tier) == 1 and coal_before - coal_after == RES.at(RES.FORGE_GEAR_COST[1], RES.Kind.COAL),
		"в кузне с углём оружие закаляется, и уголь сгорает",
		"ступень %d, угля %d -> %d" % [int(me.gear_tier), coal_before, coal_after])


func _test_who_builds_forge() -> void:
	check(FACTIONS.may_build(FACTIONS.Kind.VILLAIN, RES.Building.FORGE, true)
			and not FACTIONS.may_build(FACTIONS.Kind.ELVES, RES.Building.FORGE, false)
			and not FACTIONS.may_build(FACTIONS.Kind.GUARD, RES.Building.FORGE, false)
			and FACTIONS.may_build(FACTIONS.Kind.GUARD, RES.Building.FORGE, true),
		"кузню строят злодей и командир стражи, эльфы и рядовой страж — нет", "")


func _test_potion(me: Node3D) -> void:
	me.potions_heal = 1
	me.health.current = 20.0
	me.request_use_potion(0)
	check(int(me.potions_heal) == 0 and me.health.current >= 20.0 + RES.POTION_HEAL - 0.5,
		"зелье лечения выпито и лечит", "зелий %d, здоровье %.0f" % [int(me.potions_heal), me.health.current])
