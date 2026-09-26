extends "res://tools/test_base.gd"
##
## Конечные расходники боя: стрелы в колчане и мана.
##
## Запуск: godot --headless --path godot_project -- --host --faction=1 --ammotest
##
## ЗАЧЕМ. Решение живого игрока, и оно про выбор: «стрелы должны быть
## конечными» и «магия имба какая та, чтобы был выбор — пойти в магию, либо
## ручками сражаться, либо ресурсы качать». Пока лук стрелял вечно, ближний бой
## был необязателен: стрелять безопаснее всегда. Пока магию ограничивали только
## откаты, шесть заклинаний с разными откатами складывались в непрерывное
## колдовство.
##
## ЗА СТОРОНУ ЭЛЬФОВ. У них есть и лук, и лечение — единственное заклинание,
## которое срабатывает без чужой цели, а значит его результат виден прямо:
## здоровье выросло или нет. Проклятия злодея без цели не срабатывают вовсе, и
## проверять ими трату маны значило бы проверять отсутствие цели.
##
## ПРОВЕРЯЕМ РЕЗУЛЬТАТ. Не «запрос на выстрел отклонён», а «снаряд не родился»;
## не «заклинание не прошло», а «здоровье не изменилось».
##

const WEAPONS := preload("res://scripts/combat/weapons.gd")
const ABILITIES := preload("res://scripts/combat/abilities.gd")
const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")

var _world: Node3D
var _shots := 0


func start(world: Node3D) -> void:
	tag = "расходники"
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
	me.projectile_requested.connect(func(_k, _o, _d, _s, _g): _shots += 1)

	_test_shot_spends_an_arrow(me)
	_test_empty_quiver_does_not_shoot(me)
	_test_melee_costs_no_arrows(me)
	_test_spell_spends_mana(me)
	_test_no_mana_no_spell(me)
	await _test_mana_returns(me)
	_test_arrows_can_be_bought(me)
	_test_respawn_refills(me)
	finish()


## Один выстрел — одна стрела, и снаряд при этом рождается.
func _test_shot_spends_an_arrow(me: Node3D) -> void:
	me.arrows = 10
	var before := _shots
	_shoot(me, WEAPONS.Kind.BOW)
	check(me.arrows == 9 and _shots == before + 1,
		"выстрел тратит ровно одну стрелу",
		"в колчане %d, снарядов за выстрел %d" % [me.arrows, _shots - before])


## Пустой колчан НЕ стреляет. Проверяем по снаряду, а не по отказу: отказ —
## это намерение движка, а вопрос в том, полетело ли что-нибудь.
func _test_empty_quiver_does_not_shoot(me: Node3D) -> void:
	me.arrows = 0
	var before := _shots
	_shoot(me, WEAPONS.Kind.BOW)
	check(_shots == before and me.arrows == 0,
		"с пустым колчаном выстрела нет",
		"снарядов родилось %d, в колчане %d" % [_shots - before, me.arrows])


## Меч стрел не ест. Сторож за перечислением QUIVERED: заведи его «всё, что не
## ближний бой» — и огненный шар начнёт просить стрелу.
func _test_melee_costs_no_arrows(me: Node3D) -> void:
	me.arrows = 7
	_shoot(me, WEAPONS.Kind.SWORD)
	check(me.arrows == 7, "удар мечом стрелу не тратит",
		"в колчане осталось %d из 7" % me.arrows)


func _test_spell_spends_mana(me: Node3D) -> void:
	me.mana = me.MANA_MAX
	me.health.current = 40.0
	me.sync_ability_cd[ABILITIES.Kind.HEAL] = 0.0
	me.request_ability(ABILITIES.Kind.HEAL)
	var cost: float = ABILITIES.mana_cost(ABILITIES.Kind.HEAL)
	check(me.health.current > 40.0 and me.mana <= me.MANA_MAX - cost + 0.01,
		"заклинание тратит ману",
		"здоровье %d, маны %d из %d, цена %d"
			% [int(me.health.current), int(me.mana), int(me.MANA_MAX), int(cost)])


## Без маны заклинания НЕТ. Смотрим на здоровье: если оно выросло, значит
## лечение прошло бесплатно.
func _test_no_mana_no_spell(me: Node3D) -> void:
	me.mana = 0.0
	me.health.current = 30.0
	me.sync_ability_cd[ABILITIES.Kind.HEAL] = 0.0
	me.request_ability(ABILITIES.Kind.HEAL)
	check(is_equal_approx(me.health.current, 30.0),
		"без маны заклинание не срабатывает",
		"здоровье стало %d вместо 30" % int(me.health.current))


func _test_mana_returns(me: Node3D) -> void:
	me.mana = 0.0
	var waited := 2.0
	await get_tree().create_timer(waited).timeout
	# Ждём с запасом на кадры: точного равенства тут не бывает.
	var expected: float = me.MANA_REGEN * waited * 0.6
	check(me.mana >= expected, "мана возвращается со временем",
		"за %.0f с набралось %d, ждали хотя бы %d"
			% [waited, int(me.mana), int(expected)])


## Стрелы покупаются в лавке: колчан растёт, деньги уходят.
func _test_arrows_can_be_bought(me: Node3D) -> void:
	var home: Vector3 = me.global_position
	me.global_position = WORLD_BUILDER.TRADER_POS
	me.arrows = 0
	me.stock.add(RES.Kind.GOLD, 200)
	me.stock.add(RES.Kind.IRON, 200)
	var gold_before: int = me.stock.get_amount(RES.Kind.GOLD)
	me.request_trade(RES.Trade.ARROWS)
	var bought: int = me.arrows
	var gold_after: int = me.stock.get_amount(RES.Kind.GOLD)
	me.global_position = home
	check(bought == RES.ARROW_PACK and gold_after < gold_before,
		"в лавке стрелы покупаются",
		"в колчане %d (ждали %d), золото %d -> %d"
			% [bought, RES.ARROW_PACK, gold_before, gold_after])


## Возрождение возвращает и колчан, и ману. Выйти в мир без единой стрелы и без
## капли маны — это не наказание за смерть, а невозможность играть.
func _test_respawn_refills(me: Node3D) -> void:
	me.arrows = 0
	me.mana = 0.0
	me.respawn_at_slot()
	check(me.arrows == RES.QUIVER_START and is_equal_approx(me.mana, me.MANA_MAX),
		"возрождение возвращает колчан и ману",
		"стрел %d из %d, маны %d из %d" % [me.arrows, RES.QUIVER_START,
			int(me.mana), int(me.MANA_MAX)])


## Выстрелить прямо сейчас: откат сбрасываем, иначе второй запрос подряд не
## пройдёт и проверка соврёт про колчан.
func _shoot(me: Node3D, kind: int) -> void:
	me._server_cooldown = 0.0
	me.sync_stagger = 0.0
	me.request_attack(kind, me.aim_origin(), -me.global_transform.basis.z)
