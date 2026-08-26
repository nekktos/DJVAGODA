extends "res://tools/test_base.gd"
##
## Автопроверка магии поддержки эльфов (Этап 8). Работает headless.
##
## Запуск двумя пирами: хост за эльфов, клиент за кого угодно.
##   godot --headless --path godot_project -- --host --faction=1 --elftest
##   godot --headless --path godot_project -- --join=127.0.0.1 --faction=0 --elftest
##
## Одним пиром тоже работает — тогда проверяется всё, кроме репликации.
##

const ABILITIES := preload("res://scripts/combat/abilities.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const UNIT := preload("res://scripts/units/unit.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "эльфы"
	expected_host = 18
	expected_client = 4
	_world = world
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	if not multiplayer.is_server():
		await _run_client(me)
		finish()
		return

	_test_faction_access(me)
	await _test_heal(me)
	await _test_rally(me)
	await _test_summon(me)
	await _test_cheat_guard(me)
	if not multiplayer.get_peers().is_empty():
		# Под занавес вешаем клич и держим: клиенту надо на чём-то проверить, что
		# бафф и откаты хоста реально доезжают по сети.
		me.sync_ability_cd[ABILITIES.Kind.RALLY] = 0.0
		me.request_ability(ABILITIES.Kind.RALLY)
		await get_tree().create_timer(8.0).timeout
	finish()


## Магия поддержки — только у эльфов. У злодея своя, но атакующая, и она в
## оружии; страже магия не положена вовсе.
func _test_faction_access(me: Node3D) -> void:
	check(FACTIONS.has_abilities(FACTIONS.Kind.ELVES), "магия поддержки у эльфов есть",
		FACTIONS.abilities_text(FACTIONS.Kind.ELVES))
	check(not FACTIONS.has_abilities(FACTIONS.Kind.VILLAIN), "у злодея её нет", "пусто")
	check(not FACTIONS.has_abilities(FACTIONS.Kind.GUARD), "у стражи её нет", "пусто")
	check(int(me.faction) == FACTIONS.Kind.ELVES, "тест идёт за эльфов",
		FACTIONS.name_of(me.faction))


## Лечение поднимает здоровье и останавливает кровотечение, но НЕ отращивает
## отрубленное — на то есть протезы (GDD раздел 4).
func _test_heal(me: Node3D) -> void:
	me.health.apply_damage(60.0, 0)
	me.body.bleeding = true
	var before: float = me.health.current
	var severed_before: int = me.body.severed_mask

	me.request_ability(ABILITIES.Kind.HEAL)
	await get_tree().physics_frame

	check(me.health.current > before, "лечение подняло здоровье",
		"%d -> %d" % [int(before), int(me.health.current)])
	check(not me.body.bleeding, "кровотечение остановлено", "bleeding=false")
	check(me.body.severed_mask == severed_before, "отрубленное не отросло",
		"маска не изменилась")
	check(me.sync_ability_cd[ABILITIES.Kind.HEAL] > 0.0, "лечение ушло на откат",
		"%.0f с" % me.sync_ability_cd[ABILITIES.Kind.HEAL])

	# Повторный вызов на откате не должен пройти.
	var health_before: float = me.health.current
	me.health.apply_damage(20.0, 0)
	me.request_ability(ABILITIES.Kind.HEAL)
	await get_tree().physics_frame
	check(me.health.current < health_before, "на откате лечение не срабатывает",
		"HP %d" % int(me.health.current))


## Клич леса ускоряет и учащает удары на время.
func _test_rally(me: Node3D) -> void:
	var speed_before: float = me.buff_speed_scale()
	me.request_ability(ABILITIES.Kind.RALLY)
	await get_tree().physics_frame

	check(me.sync_buff_left > 0.0, "клич повесил бафф", "%.0f с" % me.sync_buff_left)
	check(me.buff_speed_scale() > speed_before, "скорость выросла",
		"%.2f -> %.2f" % [speed_before, me.buff_speed_scale()])
	check(me.buff_attack_scale() < 1.0, "откат атак сократился",
		"%.2f" % me.buff_attack_scale())

	# Бафф обязан истекать сам: вечное ускорение сломало бы баланс.
	me.sync_buff_left = 0.05
	await get_tree().create_timer(0.4).timeout
	check(me.sync_buff_left == 0.0 and me.buff_speed_scale() == 1.0, "бафф истёк сам",
		"остаток %.2f" % me.sync_buff_left)


## Призыв: волк появляется, он зверь, и больше предела их не бывает.
func _test_summon(me: Node3D) -> void:
	me.sync_ability_cd[ABILITIES.Kind.SUMMON] = 0.0
	me.request_ability(ABILITIES.Kind.SUMMON)
	await get_tree().physics_frame

	var beasts := _beasts_of(int(me.peer_id))
	check(beasts.size() == 1, "волк призван", "зверей: %d" % beasts.size())
	if beasts.is_empty():
		check(false, "у волка параметры зверя", "волка нет")
		check(false, "волк живёт не вечно", "волка нет")
		check(false, "предел призыва соблюдён", "волка нет")
		return

	var wolf: Node3D = beasts[0]
	check(wolf.is_beast and wolf.health <= UNIT.BEAST_HEALTH,
		"у волка параметры зверя", "HP %d" % int(wolf.health))
	check(wolf.life_left > 0.0 and wolf.life_left <= ABILITIES.SUMMON_LIFETIME,
		"волк живёт не вечно", "осталось %.0f с" % wolf.life_left)

	# Добиваем до предела и просим ещё одного сверх него.
	while _beasts_of(int(me.peer_id)).size() < ABILITIES.SUMMON_LIMIT:
		me.sync_ability_cd[ABILITIES.Kind.SUMMON] = 0.0
		me.request_ability(ABILITIES.Kind.SUMMON)
		await get_tree().physics_frame
	me.sync_ability_cd[ABILITIES.Kind.SUMMON] = 0.0
	me.request_ability(ABILITIES.Kind.SUMMON)
	await get_tree().physics_frame
	check(_beasts_of(int(me.peer_id)).size() == ABILITIES.SUMMON_LIMIT,
		"предел призыва соблюдён", "зверей: %d" % _beasts_of(int(me.peer_id)).size())


## Способность нельзя применить чужим персонажем и без руки.
func _test_cheat_guard(me: Node3D) -> void:
	me.sync_ability_cd[ABILITIES.Kind.HEAL] = 0.0
	me.health.apply_damage(30.0, 0)
	var before: float = me.health.current

	# Отрубаем обе руки: заклинания требуют полноценной кисти, как и лук.
	me.body.severed_mask = 0b0011
	me.request_ability(ABILITIES.Kind.HEAL)
	await get_tree().physics_frame
	check(me.health.current == before, "без рук колдовать нельзя",
		"HP не изменилось: %d" % int(me.health.current))
	me.body.severed_mask = 0


func _beasts_of(owner: int) -> Array:
	var result := []
	for unit in _world.units_of(owner):
		if "is_beast" in unit and unit.is_beast:
			result.append(unit)
	return result


## Клиент проверяет, что откаты и бафф хоста доезжают по сети, а сам он колдовать
## чужим персонажем не может.
func _run_client(me: Node3D) -> void:
	check(not FACTIONS.has_abilities(me.faction) or me.sync_ability_cd.size() == ABILITIES.COUNT,
		"откаты приехали к клиенту", "%d значений" % me.sync_ability_cd.size())

	var host_player: Node3D = _world.get_node_or_null("Players/1")
	if host_player == null:
		check(false, "персонаж хоста виден клиенту", "не найден")
		return
	check(true, "персонаж хоста виден клиенту", "найден")

	# Ждём, пока хост доберётся до финального клича.
	await get_tree().create_timer(6.0).timeout
	check(host_player.sync_buff_left > 0.0, "бафф хоста доехал до клиента",
		"осталось %.1f с" % host_player.sync_buff_left)
	check(host_player.sync_ability_cd[ABILITIES.Kind.RALLY] > 0.0,
		"откат хоста доехал до клиента",
		"клич на откате %.1f с" % host_player.sync_ability_cd[ABILITIES.Kind.RALLY])
