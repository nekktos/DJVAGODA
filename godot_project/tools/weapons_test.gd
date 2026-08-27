extends "res://tools/test_base.gd"
##
## Автопроверка эксклюзивного оружия сторон (Этап 10, шаг 9, GDD раздел 3.1).
## Работает headless.
##
## Запуск: godot --headless --path godot_project -- --host --faction=1 --weapontest
##
## Хост берёт эльфов — у них топор, и на нём удобно проверять и бой, и рубку.
##
## Проверяем не «оружие добавлено», а то, ради чего оно добавлено: что стороны
## РАЗНЫЕ и что каждое оружие делает СВОЁ сверх урона. Проверка «у эльфа есть
## топор» была бы зелёной и бесполезной — топор, который ничем не отличается от
## меча, ей не отличить от топора, который отличается.
##

const FACTIONS := preload("res://scripts/factions.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")
const RES := preload("res://scripts/economy/resources.gd")
const FORMATIONS := preload("res://scripts/units/formations.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "оружие"
	expected_host = 20
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(2.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	_test_sets_differ()
	_test_numbers_are_a_tradeoff()
	await _test_axe_bleeds(me)
	await _test_hammer_staggers(me)
	_test_crossbow_pierces_formation()
	await _test_harvest_tools(me)
	finish()


## У каждой стороны свой набор, и эксклюзивы не пересекаются.
func _test_sets_differ() -> void:
	var elf: int = FACTIONS.weapon_on_slot(FACTIONS.Kind.ELVES, 2)
	var guard: int = FACTIONS.weapon_on_slot(FACTIONS.Kind.GUARD, 2)
	var villain: int = FACTIONS.weapon_on_slot(FACTIONS.Kind.VILLAIN, 3)
	check(elf == WEAPONS.Kind.AXE, "у эльфов топор", WEAPONS.NAMES[elf])
	check(guard == WEAPONS.Kind.CROSSBOW, "у стражи арбалет", WEAPONS.NAMES[guard])
	check(villain == WEAPONS.Kind.HAMMER, "у злодея молот", WEAPONS.NAMES[villain])

	check(not FACTIONS.allows_weapon(FACTIONS.Kind.ELVES, WEAPONS.Kind.HAMMER),
		"чужое оружие стороне недоступно", "эльфу молот не выдать")
	check(FACTIONS.allows_weapon(FACTIONS.Kind.GUARD, WEAPONS.Kind.SWORD)
			and FACTIONS.allows_weapon(FACTIONS.Kind.ELVES, WEAPONS.Kind.BOW),
		"меч и лук остались общей базой", "есть у всех")


## Числа должны быть РАЗМЕНОМ, а не «одно лучше другого».
##
## Это главная проверка баланса, какую вообще можно сделать без живых людей:
## урон в секунду у трёх видов ближнего боя обязан быть сопоставим, иначе выбор
## оружия — не выбор.
func _test_numbers_are_a_tradeoff() -> void:
	var sword: float = WEAPONS.DAMAGE[WEAPONS.Kind.SWORD] / WEAPONS.COOLDOWN[WEAPONS.Kind.SWORD]
	var axe: float = WEAPONS.DAMAGE[WEAPONS.Kind.AXE] / WEAPONS.COOLDOWN[WEAPONS.Kind.AXE]
	var hammer: float = WEAPONS.DAMAGE[WEAPONS.Kind.HAMMER] / WEAPONS.COOLDOWN[WEAPONS.Kind.HAMMER]
	var best: float = maxf(sword, maxf(axe, hammer))
	var worst: float = minf(sword, minf(axe, hammer))
	check(best / worst < 1.35, "урон в секунду у ближнего боя сопоставим",
		"меч %.0f, топор %.0f, молот %.0f" % [sword, axe, hammer])

	check(WEAPONS.COOLDOWN[WEAPONS.Kind.AXE] < WEAPONS.COOLDOWN[WEAPONS.Kind.SWORD],
		"топор быстрее меча", "%.2f против %.2f с"
		% [WEAPONS.COOLDOWN[WEAPONS.Kind.AXE], WEAPONS.COOLDOWN[WEAPONS.Kind.SWORD]])
	check(WEAPONS.DAMAGE[WEAPONS.Kind.HAMMER] > WEAPONS.DAMAGE[WEAPONS.Kind.SWORD]
			and WEAPONS.COOLDOWN[WEAPONS.Kind.HAMMER] > WEAPONS.COOLDOWN[WEAPONS.Kind.SWORD],
		"молот бьёт сильнее и реже", "%.0f за %.2f с"
		% [WEAPONS.DAMAGE[WEAPONS.Kind.HAMMER], WEAPONS.COOLDOWN[WEAPONS.Kind.HAMMER]])
	check(WEAPONS.DAMAGE[WEAPONS.Kind.CROSSBOW] > WEAPONS.DAMAGE[WEAPONS.Kind.BOW]
			and WEAPONS.COOLDOWN[WEAPONS.Kind.CROSSBOW] > WEAPONS.COOLDOWN[WEAPONS.Kind.BOW],
		"арбалет бьёт сильнее и реже лука", "%.0f за %.2f с"
		% [WEAPONS.DAMAGE[WEAPONS.Kind.CROSSBOW], WEAPONS.COOLDOWN[WEAPONS.Kind.CROSSBOW]])


## Топор открывает кровотечение. Не каждым ударом — значит бьём, пока не пойдёт.
func _test_axe_bleeds(me: Node3D) -> void:
	var victim: Node3D = _world.spawn_garrison_unit(_enemy_of(int(me.faction)), 5,
		me.global_position + Vector3(3.0, 0.5, 0.0), me.global_position, 50.0)
	await get_tree().physics_frame
	if victim == null:
		fail("жертву создать не удалось")
		return

	# Бьём по персонажу: кровотечение живёт в системе ранений, а она есть только
	# у персонажей. Значит и проверять надо на персонаже — на себе.
	if is_instance_valid(victim):
		victim.queue_free()
	check(not me.body.bleeding, "до удара крови нет", "не кровит")

	var opened := false
	for i in 40:
		me.body.bleeding = false
		me._apply_melee_effect(WEAPONS.Kind.AXE, me)
		if me.body.bleeding:
			opened = true
			break
	check(opened, "топор открывает кровотечение", "за 40 ударов открылось")

	me.body.bleeding = false
	var swords := 0
	for i in 40:
		me._apply_melee_effect(WEAPONS.Kind.SWORD, me)
		if me.body.bleeding:
			swords += 1
	check(swords == 0, "меч кровотечения не даёт", "ударов с кровью: %d" % swords)


## Молот сбивает: сбитый не бьёт, и это проверяет ХОСТ, а не только клиент.
func _test_hammer_staggers(me: Node3D) -> void:
	me.sync_stagger = 0.0
	# Меряем здоровье вплотную вокруг самого сбивания, без единого кадра между:
	# рядом стоит враг, и любая пауза припишет молоту его удары.
	var before: float = me.health.current
	me._apply_melee_effect(WEAPONS.Kind.HAMMER, me)
	check(me.sync_stagger > 0.0, "молот сбивает цель с ног",
		"сбит на %.1f с" % me.sync_stagger)
	check(is_equal_approx(before, me.health.current), "сбивание само по себе не ранит",
		"здоровье прежнее")

	# Заявка на удар от сбитого обязана быть отклонена хостом.
	var dummy: Node3D = _world.spawn_garrison_unit(_enemy_of(int(me.faction)), 6,
		me.global_position + Vector3(1.5, 0.5, 0.0), me.global_position, 50.0)
	await get_tree().physics_frame
	var victim_health: float = dummy.health if dummy != null else -1.0
	me.request_attack(WEAPONS.Kind.SWORD, me.aim_origin(), Vector3(1.0, 0.0, 0.0))
	await get_tree().physics_frame
	check(dummy == null or is_equal_approx(dummy.health, victim_health),
		"сбитый не может ударить", "здоровье цели не изменилось")
	if dummy != null and is_instance_valid(dummy):
		dummy.queue_free()
	me.sync_stagger = 0.0


## Арбалет пробивает строй. Защита построения существует, защиты от снаряжения в
## игре нет вовсе — болт задуман против первой.
func _test_crossbow_pierces_formation() -> void:
	var wall: float = FORMATIONS.damage_scale(FORMATIONS.Kind.SHIELD_WALL, false)
	check(wall < 1.0, "стена щитов действительно режет урон", "множитель %.2f" % wall)
	var pierced: float = lerpf(wall, 1.0, WEAPONS.CROSSBOW_PIERCE)
	check(pierced > wall and pierced < 1.0, "болт пробивает строй лишь ЧАСТИЧНО",
		"%.2f вместо %.2f, но не 1.0" % [pierced, wall])


## Топор рубит дерево лучше, молот бьёт камень лучше — тем же ударом, которым
## дерутся.
func _test_harvest_tools(me: Node3D) -> void:
	check(WEAPONS.harvest_bonus(WEAPONS.Kind.AXE, RES.Kind.WOOD) > 1.0,
		"топор эффективнее на дереве",
		"x%.1f" % WEAPONS.harvest_bonus(WEAPONS.Kind.AXE, RES.Kind.WOOD))
	check(WEAPONS.harvest_bonus(WEAPONS.Kind.HAMMER, RES.Kind.STONE) > 1.0,
		"молот эффективнее на камне",
		"x%.1f" % WEAPONS.harvest_bonus(WEAPONS.Kind.HAMMER, RES.Kind.STONE))
	check(is_equal_approx(WEAPONS.harvest_bonus(WEAPONS.Kind.AXE, RES.Kind.STONE), 1.0)
			and is_equal_approx(WEAPONS.harvest_bonus(WEAPONS.Kind.SWORD, RES.Kind.WOOD), 1.0),
		"не на своём материале прибавки нет", "меч и топор по камню обычные")
	await get_tree().process_frame


func _enemy_of(faction: int) -> int:
	for other in FACTIONS.COUNT:
		if other != faction:
			return other
	return 0
