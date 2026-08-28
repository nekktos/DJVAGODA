extends "res://tools/test_base.gd"
##
## Автопроверка героя свободной стороны (Этап 10, шаг 8; решение GDD 10.1).
## Работает headless.
##
## Запуск:
##   godot --headless --path godot_project -- --host --faction=2 --herotest
##
## Хост берёт СТРАЖУ, а не злодея: герой заводится только там, где за сторону
## никто не сел, и сесть за злодея значило бы отменить предмет проверки.
##
## Проверяем с разных сторон, потому что герой без пира ломается тихо и
## по-разному:
##
##   — он вообще есть, он вожак, и авторитет над ним у хоста;
##   — сторона при этом ОСТАЛАСЬ свободной: гарнизон цел, хозяйство идёт.
##     Считай его игроком — сторона выключила бы сама себя, и молча;
##   — он двигается и дерётся тем оружием, которое достаёт;
##   — пороговые правила каста срабатывают на своих порогах и не срабатывают
##     вне их;
##   — смерть у него окончательная, как у любого вожака;
##   — за сторону сел человек — герой уходит.
##

const FACTIONS := preload("res://scripts/factions.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")
const ABILITIES := preload("res://scripts/combat/abilities.gd")
const HEALTH := preload("res://scripts/combat/health.gd")

## Сторона, у которой герой должен появиться: вожак со стратегическим слоем.
const SIDE := FACTIONS.Kind.VILLAIN

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "герой"
	expected_host = 25
	expected_client = 4
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	# Герою нужно время появиться: его заводит `hero.gd` на своём такте.
	await get_tree().create_timer(4.0).timeout

	if not Net.hosting():
		await _run_client()
		finish()
		return

	var hero: Node3D = _world.ai_hero_of(SIDE)
	if hero == null:
		fail("герой свободной стороны не заведён")
		finish()
		return

	_test_exists_and_is_leader(hero)
	_test_side_stays_free(hero)
	await _test_moves(hero)
	await _test_fights(hero)
	_test_walks_by_map(hero)
	_test_spell_thresholds(hero)
	await _test_death_is_final(hero)
	_test_leaves_when_player_sits()
	finish()


## Он есть, он вожак, и считает его хост.
func _test_exists_and_is_leader(hero: Node3D) -> void:
	check(hero.ai_led, "герой заведён и помечен как ведомый ИИ", "ai_led=true")
	check(hero.is_leader, "герой — вожак, как и живой злодей", "is_leader=true")
	# Авторитет обязан быть у хоста. У героя нет пира, и имя ноды даёт
	# отрицательный peer id: не переопредели мы авторитет, его не было бы ни у
	# кого и персонаж просто стоял бы на месте.
	check(hero.get_multiplayer_authority() == 1, "движение героя считает хост",
		"authority=%d" % hero.get_multiplayer_authority())
	check(int(hero.faction) == SIDE, "герой на стороне злодея",
		FACTIONS.name_of(int(hero.faction)))


## Сторона осталась СВОБОДНОЙ. Это главное place, где всё могло сломаться молча.
func _test_side_stays_free(hero: Node3D) -> void:
	check(_world.players_of(SIDE).is_empty(),
		"герой не считается игроком — сторона свободна",
		"players_of пуст")
	check(_world.characters_of(SIDE).has(hero),
		"но персонажем стороны он считается",
		"characters_of его видит")
	# Следствия, ради которых разделение и заводилось: не распустился ли
	# гарнизон и не остановилось ли хозяйство.
	check(_world.garrison.size_of(SIDE) > 0,
		"гарнизон свободной стороны не распущен",
		"бойцов %d" % _world.garrison.size_of(SIDE))
	check(_world.get_node("Steward")._runs_for(SIDE),
		"хозяйство стороны продолжает вестись",
		"наём и стройка идут, как будто персонажа нет")


## Он ходит — но не просто так, а К ЦЕЛИ, и не дальше поводка.
##
## Четыре попытки до этого падали, и НИ ОДНА не нашла поломки в игре — все
## четыре ловили живой мир вокруг:
##
##   1. ждали, сдвинется ли он вообще. У базы, когда воевать не с кем, герой
##      стоит, и это правильно;
##   2. ставили врага в двадцати метрах. Не пошёл: дальше восемнадцати от якоря
##      своего отряда он не отходит — он вожак и гибнет насовсем;
##   3. приманкой был боец ЭЛЬФОВ, а эльфы тоже под ИИ: их отряд увёл приманку
##      на сорок метров, герой стоял, а расстояние росло само;
##   4. мерили расстояние В КОНЦЕ окна. Герой дошёл до трёх метров, а потом мимо
##      прошёл боец эльфов ближе хоста, и герой честно переключился на него.
##
## Поэтому: цель — сам хост (он враг злодею и в headless никуда не идёт), а
## мерим САМОЕ БЛИЗКОЕ СБЛИЖЕНИЕ за окно, а не остаток на последнем кадре. Мир
## живой, и «где он оказался в конце» о его намерениях не говорит ничего.
func _test_moves(hero: Node3D) -> void:
	var brain: Node = _world.get_node("Hero")
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж хоста не заспавнен")
		return

	me.teleport.rpc(hero.global_position + Vector3(10.0, 2.0, 0.0))
	await get_tree().physics_frame
	var before: float = hero.global_position.distance_to(me.global_position)
	var closest: float = before
	for i in 12:
		await get_tree().create_timer(0.5).timeout
		closest = minf(closest, hero.global_position.distance_to(me.global_position))
	check(closest < before - 2.0, "герой идёт к врагу, а не топчется",
		"с %.0f м сблизился до %.0f" % [before, closest])

	# За дальним не бежит: остаётся при своём отряде.
	me.teleport.rpc(hero.global_position + Vector3(70.0, 2.0, 0.0))
	await get_tree().create_timer(6.0).timeout
	var anchor: Vector3 = _world.warband.anchor_of(SIDE)
	var leash: float = INF
	if anchor.is_finite():
		leash = Vector2(anchor.x, anchor.z).distance_to(
			Vector2(hero.global_position.x, hero.global_position.z))
	check(leash <= brain.LEASH + 8.0, "за дальним врагом герой не убегает от отряда",
		"%.0f м от якоря при поводке %.0f" % [leash, brain.LEASH])


## Он дерётся: враг вплотную должен получить урон.
##
## Жертва — снова САМ ХОСТ, и по той же причине, по которой он же служит целью
## для проверки хода: любой боец, которого мы создадим, принадлежит стороне под
## ИИ, и её отряд уводит его прочь раньше, чем герой успевает замахнуться. Хост
## же в headless стоит там, где его поставили.
func _test_fights(hero: Node3D) -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж хоста не заспавнен")
		return
	me.teleport.rpc(hero.global_position + Vector3(2.5, 0.5, 0.0))
	await get_tree().physics_frame
	var before: float = me.health.current
	# Дольше отката молота (1.25 с) с запасом на такт мышления героя.
	await get_tree().create_timer(5.0).timeout
	var after: float = me.health.current if me.health.alive else 0.0
	check(after < before, "герой бьёт врага вплотную",
		"здоровье цели %.0f -> %.0f" % [before, after])

	# Оружие спрашиваем у САМОГО ПРАВИЛА, а не смотрим на героя спустя пять
	# секунд: за это время обстановка меняется, герой честно переключается, и
	# проверка падает на верном поведении. Правило же однозначно.
	var brain: Node = _world.get_node("Hero")
	brain._choose_weapon(hero, 2.0)
	check(WEAPONS.is_melee(hero.sync_weapon),
		"вплотную герой берёт оружие ближнего боя",
		WEAPONS.NAMES[hero.sync_weapon])
	brain._choose_weapon(hero, 20.0)
	check(hero.sync_weapon == WEAPONS.Kind.SPELL,
		"издали — огненный шар",
		WEAPONS.NAMES[hero.sync_weapon])


## Дальнюю цель герой берёт ПО КАРТЕ, а не по прямой.
##
## Живой прогон показал, чего стоит обратное: герой упёрся в восточную стену
## собственного форта и простоял там полторы минуты, пока его отряд уходил на
## двести метров. По коду это не видно вовсе — видно только по логу, где его
## координаты не меняются, а координаты отряда меняются.
##
## Проверяем обе половины: вблизи путь не спрашивается (иначе в ближнем бою
## герой ходил бы кругами вокруг собственного плеча), издали — спрашивается.
func _test_walks_by_map(hero: Node3D) -> void:
	var brain: Node = _world.get_node("Hero")
	var close_goal: Vector3 = hero.global_position + Vector3(5.0, 0.0, 0.0)
	check(brain._next_step(hero, close_goal) == close_goal,
		"вблизи герой идёт напрямую, не спрашивая карту",
		"шаг совпал с целью")

	# Цель за стеной форта и далеко: сюда по прямой не дойти.
	var far_goal: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.GUARD]
	var step: Vector3 = brain._next_step(hero, far_goal)
	check(step != far_goal and _world.navigation.is_ready(),
		"издали герой идёт по карте, а не сквозь стену",
		"шаг %s вместо цели %s" % [str(step.round()), str(far_goal.round())])


## Пороговые правила каста. Спрашиваем прямо решающую функцию: она и есть
## правило, а ловить сам каст в живом бою — значит проверять ещё и откаты,
## дистанции и удачу.
func _test_spell_thresholds(hero: Node3D) -> void:
	var brain: Node = _world.get_node("Hero")
	var near: Node3D = _world.spawn_garrison_unit(_enemy_of(SIDE), 10,
		hero.global_position + Vector3(3.0, 0.5, 0.0), hero.global_position, 60.0)
	if near == null:
		fail("цель для проверки порогов создать не удалось")
		return

	var full: float = hero.health.current
	# Здоров — паралич не нужен, одиночка скоплением не считается.
	hero.health.current = HEALTH.MAX_HEALTH
	check(brain._choose_spell(SIDE, hero, [near], near) == -1,
		"здоровому и против одиночки заклинание не нужно", "-1")

	# Дожимают — паралич по ближайшему.
	hero.health.current = HEALTH.MAX_HEALTH * 0.3
	check(brain._choose_spell(SIDE, hero, [near], near) == ABILITIES.Kind.PARALYSIS,
		"на низком здоровье бросает паралич",
		ABILITIES.NAMES[ABILITIES.Kind.PARALYSIS])

	# Скопление — проклятие, даже когда сам цел.
	hero.health.current = HEALTH.MAX_HEALTH
	var crowd := [near, near, near]
	check(brain._choose_spell(SIDE, hero, crowd, near) == ABILITIES.Kind.WITHER,
		"по скоплению бросает проклятие",
		ABILITIES.NAMES[ABILITIES.Kind.WITHER])
	check(brain._cluster_size(crowd, near.global_position) >= brain.CLUSTER_SIZE,
		"скопление считается по расстоянию между врагами",
		"в куче %d при пороге %d" % [
			brain._cluster_size(crowd, near.global_position), brain.CLUSTER_SIZE])

	hero.health.current = full
	near.queue_free()


## Смерть вожака окончательна и для героя ИИ: убил — и злодей выбыл до конца
## партии. Ровно то, что решено про окончательную смерть.
func _test_death_is_final(hero: Node3D) -> void:
	# Пока вожак жив, сторона НЕ сломлена, хотя за неё никто не сидит. До
	# появления героя пустующая сторона считалась сломленной сразу, и это было
	# записано как временное правило «пока ИИ фракций нет».
	check(not _world.objective.faction_is_broken(SIDE),
		"пока ИИ-вожак жив, сторона не сломлена",
		"за сторону никто не сидит, но вожак воюет")

	hero.take_damage(999.0, 1, "torso", hero.global_position, Vector3.FORWARD)
	await get_tree().create_timer(1.0).timeout
	check(not hero.health.alive, "герой убит", "мёртв")
	check(_world.objective.leader_is_down(SIDE),
		"гибель вожака засчитана стороне", "leader_down=true")
	# Дольше обычного респавна: рядовой к этому времени уже вернулся бы.
	await get_tree().create_timer(8.0).timeout
	check(not hero.health.alive, "и в мир не вернулся",
		"мёртв дольше срока респавна")
	# А вот теперь сломлена: мёртвый вожак стороне не помощник, и возродиться
	# он не может. Обе половины правила на одном герое — иначе «не сломлена
	# никогда» зеленело бы точно так же.
	check(_world.objective.faction_is_broken(SIDE),
		"с гибелью вожака сторона сломлена", "вожак мёртв и не вернётся")


## За сторону сел человек — герой уходит. Проверяем сам механизм: сажать в
## headless-прогоне второго игрока незачем, а вот убрать героя по команде надо
## уметь, иначе сторона окажется с двумя вожаками разом.
func _test_leaves_when_player_sits() -> void:
	_world.despawn_ai_hero(SIDE)
	check(_world.ai_hero_of(SIDE) == null or not is_instance_valid(_world.ai_hero_of(SIDE))
			or _world.ai_hero_of(SIDE).is_queued_for_deletion(),
		"по команде герой уходит со стороны", "убран")


func _enemy_of(faction: int) -> int:
	for other in FACTIONS.COUNT:
		if other != faction:
			return other
	return 0


## Половина КЛИЕНТА: видит ли он героя вообще.
##
## Вопрос не праздный. Герой создаётся спавнером на всех пирах, но имя ноды у
## него ОТРИЦАТЕЛЬНОЕ, а по имени персонаж на каждом пире определяет своего
## авторитета. Ошибись мы тут — и злодей под ИИ оказался бы невидим для игроков,
## причём молча: у хоста-то всё работает, а увидеть это можно только со второго
## пира.
func _run_client() -> void:
	var hero: Node3D = _world.ai_hero_of(SIDE)
	check(hero != null, "клиент видит героя свободной стороны",
		"есть" if hero != null else "нет")
	if hero == null:
		# Остальные проверки обязаны выполниться, иначе счётчик решит, что
		# клиент просто не отработал.
		check(false, "клиент знает, что им правит ИИ", "героя нет")
		check(false, "у клиента авторитет над героем — хост", "героя нет")
		check(false, "клиент видит в нём вожака", "героя нет")
		return
	check(hero.ai_led, "клиент знает, что им правит ИИ", "ai_led=true")
	check(hero.get_multiplayer_authority() == 1,
		"у клиента авторитет над героем — хост",
		"authority=%d" % hero.get_multiplayer_authority())
	check(hero.is_leader, "клиент видит в нём вожака", "is_leader=true")

	# Гибель героя тут НЕ проверяем, хотя проверять хочется. Хост доходит до неё
	# позже, чем клиент закрывается, и проверка молча не выполнялась бы — её
	# поймал бы только счётчик. Смерть вожака и её доезд до второго пира уже
	# проверены в наборе победы, на живом злодее.
