extends "res://tools/test_base.gd"
##
## Опыт и прокачка вожака.
##
## Запуск: godot --headless --path godot_project -- --host --faction=0 --progresstest
##
## ЗАЧЕМ. Решение автора игры: «опыт злодея должен получаться за добычу
## ресурсов, за убийства, за выращивание на ферме (добыча ресурсов), за
## успешную доставку караванов». Выращенное на ферме отдельной проверки не
## требует: еда — ресурс, и доносится она тем же путём.
##
## Проверяем РЕЗУЛЬТАТ: не «функция вызвана», а «опыта стало больше», и не
## «уровень записан», а «шкала выросла».
##

const PROGRESS := preload("res://scripts/progression.gd")
const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "прокачка"
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
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	_test_resources_give_xp(me)
	_test_caravan_gives_xp(me)
	_test_kill_gives_xp(me)
	_test_no_xp_for_own(me)
	_test_upgrade_costs_xp(me)
	_test_upgrade_raises_the_scale(me)
	_test_upgrade_refused_without_xp(me)
	_test_ceiling(me)
	finish()


## Опыт за донесённую добычу, и НЕ за каждую единицу: очко стоит нескольких.
func _test_resources_give_xp(me: Node3D) -> void:
	me.experience = 0
	me._res_tail = 0
	me.award_xp_for_resources(PROGRESS.RESOURCE_PER_POINT - 1)
	var after_scrap: int = int(me.experience)
	me.award_xp_for_resources(PROGRESS.RESOURCE_PER_POINT * 3 + 1)
	# Ожидаемое СЧИТАЕМ, а не вписываем: первая версия ждала три очка с
	# шестнадцати единиц, забыв про горсть, которая легла в хвост. Проверка
	# упала на исправном коде.
	var units: int = (PROGRESS.RESOURCE_PER_POINT - 1) + PROGRESS.RESOURCE_PER_POINT * 3 + 1
	var want: int = units / PROGRESS.RESOURCE_PER_POINT
	check(after_scrap == 0 and int(me.experience) == want,
		"опыт идёт за донесённую добычу, по очку за несколько единиц",
		"с горсти %d, с %d единиц всего %d, ждали %d"
			% [after_scrap, units, int(me.experience), want])


func _test_caravan_gives_xp(me: Node3D) -> void:
	me.experience = 0
	_world.award_faction_xp(int(me.faction), PROGRESS.XP_CARAVAN, "обоз")
	check(int(me.experience) == PROGRESS.XP_CARAVAN,
		"опыт за доехавший обоз идёт вожаку стороны",
		"получено %d, ждали %d" % [int(me.experience), PROGRESS.XP_CARAVAN])


func _test_kill_gives_xp(me: Node3D) -> void:
	me.experience = 0
	var enemy: int = (int(me.faction) + 1) % FACTIONS.COUNT
	_world._award_kill_xp(int(me.peer_id), enemy, false)
	var plain: int = int(me.experience)
	_world._award_kill_xp(int(me.peer_id), enemy, true)
	check(plain == PROGRESS.XP_UNIT_KILL
			and int(me.experience) == PROGRESS.XP_UNIT_KILL + PROGRESS.XP_LEADER_KILL,
		"за убийство даётся опыт, за вожака — больше",
		"боец %d, всего с вожаком %d" % [plain, int(me.experience)])


## ЗА СВОИХ НЕ ДАЁМ. Иначе выгоднее всего было бы резать собственный гарнизон:
## он рядом, он не сопротивляется и возобновляется бесконечно.
func _test_no_xp_for_own(me: Node3D) -> void:
	me.experience = 0
	_world._award_kill_xp(int(me.peer_id), int(me.faction), false)
	check(int(me.experience) == 0, "за убийство своих опыта нет",
		"получено %d" % int(me.experience))


func _test_upgrade_costs_xp(me: Node3D) -> void:
	_reset(me)
	me.experience = PROGRESS.cost_of(0) + 7
	me.request_upgrade(PROGRESS.Stat.STAMINA)
	check(me.level_of(PROGRESS.Stat.STAMINA) == 1 and int(me.experience) == 7,
		"уровень покупается и списывает опыт",
		"уровень %d, осталось опыта %d"
			% [me.level_of(PROGRESS.Stat.STAMINA), int(me.experience)])


## Шкала ДЕЙСТВИТЕЛЬНО выросла, а не только число уровня.
func _test_upgrade_raises_the_scale(me: Node3D) -> void:
	_reset(me)
	var stamina_before: float = me.stamina_max()
	var mana_before: float = me.mana_max()
	var run_before: float = me.run_scale()
	var health_before: float = me.health.maximum()
	me.experience = PROGRESS.cost_of(0) * 4
	for stat in PROGRESS.COUNT:
		me.request_upgrade(stat)
	check(me.stamina_max() > stamina_before and me.mana_max() > mana_before
			and me.run_scale() > run_before and me.health.maximum() > health_before,
		"купленный уровень поднимает саму шкалу",
		"выносливость %.0f -> %.0f, мана %.0f -> %.0f, бег %.2f -> %.2f, жизнь %.0f -> %.0f"
			% [stamina_before, me.stamina_max(), mana_before, me.mana_max(),
				run_before, me.run_scale(), health_before, me.health.maximum()])


func _test_upgrade_refused_without_xp(me: Node3D) -> void:
	_reset(me)
	me.experience = PROGRESS.cost_of(0) - 1
	me.request_upgrade(PROGRESS.Stat.MANA)
	check(me.level_of(PROGRESS.Stat.MANA) == 0 and int(me.experience) == PROGRESS.cost_of(0) - 1,
		"без опыта уровень не покупается и опыт не пропадает",
		"уровень %d, опыта %d" % [me.level_of(PROGRESS.Stat.MANA), int(me.experience)])


## Выше потолка не поднять, и опыт за отказ не списывается.
func _test_ceiling(me: Node3D) -> void:
	_reset(me)
	me.experience = 100000
	for i in PROGRESS.MAX_LEVEL + 3:
		me.request_upgrade(PROGRESS.Stat.SPEED)
	var left: int = int(me.experience)
	me.request_upgrade(PROGRESS.Stat.SPEED)
	check(me.level_of(PROGRESS.Stat.SPEED) == PROGRESS.MAX_LEVEL
			and int(me.experience) == left,
		"выше потолка не поднять, и опыт за отказ не пропадает",
		"уровень %d при потолке %d" % [me.level_of(PROGRESS.Stat.SPEED),
			PROGRESS.MAX_LEVEL])
	_reset(me)


func _reset(me: Node3D) -> void:
	me.upgrades = PackedInt32Array([0, 0, 0, 0])
	me.experience = 0
	me.health.bonus = 0.0
