extends "res://tools/test_base.gd"
##
## Автопроверка системы ранений и протезов (Этап 3). Работает headless.
##
## Запуск (два процесса — второй нужен для проверки репликации):
##   godot --headless --path godot_project -- --host --woundtest
##   godot --headless --path godot_project -- --join=127.0.0.1 --woundtest
##
## Проверяем таблицу GDD раздела 4 и уточнения из DESIGN_ANSWERS.md:
## отрыв, кровотечение и смерть от него, перевязка бинтом, ползание без ноги
## и медленнее без двух, слепота, качество протезов, коляска.
##

const BODY := preload("res://scripts/combat/body.gd")
const UNIT_MAX_HEALTH := 90.0

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "раны"
	expected_host = 37
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

	if not Net.hosting():
		# Следим за персонажем ХОСТА: калечит он себя, значит и проверять
		# репликацию надо на нём, а не на своём целом теле.
		var host_player: Node3D = _world.get_node("Players").get_node_or_null("1")
		await _run_client(host_player)
		finish()
		return

	var body: Node = me.body
	var health: Node = me.health

	await _test_arm(me, body, health)
	await _test_bleeding_death(me, body, health)
	await _test_legs(me, body, health)
	await _test_eyes(me, body, health)
	await _test_prosthetics(me, body, health)
	await _test_wheelchair(me, body, health)
	await _test_trophies(me, body, health)
	await _test_necrotic(me, body, health)

	await _showcase(me, body, health)
	finish()


## Финальное состояние держим долго и не трогаем: короткие всплески между
## сценариями репликация законно может проглотить, и проверка на другом пире
## получилась бы гонкой, а не проверкой.
func _showcase(me: Node3D, body: Node, health: Node) -> void:
	await _reset(me, body, health)
	await _sever(body, health, "arm_r")
	await _sever(body, health, "leg_l")
	await _sever(body, health, "leg_r")
	body.register_hit("head", BODY.EYE_THRESHOLD)
	body.grant_prosthetic(BODY.Limb.ARM_R, 1)
	body.set_wheelchair(true)
	body.bleeding = false
	health.revive()
	print("[раны] хост встал в показательное состояние: %s" % body.summary())
	await get_tree().create_timer(18.0).timeout


## Наносим урон в зону, пока конечность не оторвёт.
func _sever(body: Node, health: Node, zone: String) -> void:
	for i in 20:
		if body.is_severed(BODY.LIMB_KEYS.find(zone)):
			return
		health.revive()
		body.register_hit(zone, 12.0)
		await get_tree().process_frame


func _reset(me: Node3D, body: Node, health: Node) -> void:
	body.reset()
	health.revive()
	await get_tree().process_frame
	# Ждём ДВА физических кадра. Облик сверяется с маской в `_physics_process`,
	# а `physics_frame` будит нас в начале шага — до того, как ноды его отработают.
	# С одним кадром проверка «конечности вернулись на модель» читала состояние
	# на кадр раньше, чем оно менялось, и падала, показывая маску 0 при
	# схлопнутой кости: правило уже сработало, картинка ещё нет.
	await get_tree().physics_frame
	await get_tree().physics_frame


func _test_arm(me: Node3D, body: Node, health: Node) -> void:
	await _reset(me, body, health)

	await _sever(body, health, "arm_r")
	check(body.is_severed(BODY.Limb.ARM_R), "отрыв правой руки", "severed_mask=%d" % body.severed_mask)
	# Отдельно спрашиваем МОДЕЛЬ, а не маску. Расчленение на скиннутом персонаже
	# делается схлопыванием кости, и если в новой модели кость зовут иначе, маска
	# встанет, все проверки правил останутся зелёными, а рука будет на месте.
	check(me.limb_hidden(BODY.Limb.ARM_R), "оторванной руки не видно на модели",
		"кость схлопнута")
	check(not me.limb_hidden(BODY.Limb.ARM_L), "целая рука на месте",
		"левая кость не тронута")
	check(body.bleeding, "кровотечение началось", "bleeding=%s" % body.bleeding)
	check(body.can_attack_ranged(), "вторая рука ещё работает", "лук доступен")

	await _sever(body, health, "arm_l")
	check(not body.can_attack_melee(), "без обеих рук бить нечем", "меч недоступен")

	# Перевязка расходует бинт и останавливает кровь (DESIGN_ANSWERS, пункт 11).
	var before: int = body.bandages
	var used: bool = body.apply_bandage()
	check(used and not body.bleeding and body.bandages == before - 1,
		"перевязка бинтом", "бинтов было %d, стало %d, кровотечение=%s" % [before, body.bandages, body.bleeding])


func _test_bleeding_death(me: Node3D, body: Node, health: Node) -> void:
	await _reset(me, body, health)
	await _sever(body, health, "arm_r")
	health.revive()
	body.bleeding = true
	await get_tree().create_timer(3.0).timeout
	var after: float = health.current
	check(after < 99.0, "кровопотеря снимает здоровье", "через 3 с здоровье %.0f" % after)

	# Без перевязки должно добить насмерть.
	while health.alive and health.current > 0.0:
		health.apply_damage(20.0, 0)
		await get_tree().process_frame
	check(not health.alive, "смерть от кровопотери без перевязки", "здоровье %.0f" % health.current)

	# Смерть запускает респавн, а тот через RESPAWN_DELAY делает body.reset().
	# Если не дождаться, он обнулит состояние посреди следующего сценария.
	await get_tree().create_timer(7.0).timeout


func _test_legs(me: Node3D, body: Node, health: Node) -> void:
	await _reset(me, body, health)
	await _sever(body, health, "leg_r")
	var one: float = body.move_speed(6.0)
	check(body.is_crawling() and is_equal_approx(one, BODY.CRAWL_SPEED_ONE),
		"без одной ноги — ползание", "скорость %.2f м/с" % one)

	await _sever(body, health, "leg_l")
	var both: float = body.move_speed(6.0)
	check(both < one and is_equal_approx(both, BODY.CRAWL_SPEED_BOTH),
		"без двух ног — ползание медленнее", "скорость %.2f м/с" % both)
	check(is_equal_approx(body.jump_velocity(5.5), 0.0), "ползком не прыгают", "прыжок %.1f" % body.jump_velocity(5.5))


func _test_eyes(me: Node3D, body: Node, health: Node) -> void:
	await _reset(me, body, health)
	health.revive()
	body.register_hit("head", BODY.EYE_THRESHOLD)
	check(body.eyes_lost == 1 and is_equal_approx(body.blindness(), 0.5),
		"потеря глаза — слепота на половину экрана", "глаз потеряно %d" % body.eyes_lost)

	health.revive()
	body.register_hit("head", BODY.EYE_THRESHOLD)
	check(body.eyes_lost == 2 and is_equal_approx(body.blindness(), 1.0),
		"второй глаз — полная слепота", "глаз потеряно %d" % body.eyes_lost)
	check(health.alive, "потеря глаз не убивает", "здоровье %.0f" % health.current)


func _test_prosthetics(me: Node3D, body: Node, health: Node) -> void:
	await _reset(me, body, health)
	await _sever(body, health, "leg_r")
	await _sever(body, health, "leg_l")
	var crawl: float = body.move_speed(6.0)

	# Деревянный: чуть быстрее ползания и травмирует (DESIGN_ANSWERS, пункт 13).
	body.grant_prosthetic(BODY.Limb.LEG_L, 1)
	body.grant_prosthetic(BODY.Limb.LEG_R, 1)
	var wooden: float = body.move_speed(6.0)
	check(wooden > crawl and wooden < 6.0,
		"деревянный протез быстрее ползания, но медленнее живых ног",
		"ползание %.2f, дерево %.2f, живые 6.00" % [crawl, wooden])

	# Кровотечение гасим, иначе оно само снимет здоровье и проверка натирания
	# пройдёт по неверной причине.
	body.bleeding = false
	health.revive()
	var before_chafe: float = health.current
	await get_tree().create_timer(BODY.CHAFE_INTERVAL + 1.0).timeout
	check(health.current < before_chafe,
		"плохо подогнанный протез травмирует",
		"здоровье %.1f -> %.1f" % [before_chafe, health.current])

	# Мастерский: ЛУЧШЕ живых конечностей.
	body.grant_prosthetic(BODY.Limb.LEG_L, 3)
	body.grant_prosthetic(BODY.Limb.LEG_R, 3)
	var master: float = body.move_speed(6.0)
	var master_jump: float = body.jump_velocity(5.5)
	check(master > 6.0 and master_jump > 5.5,
		"мастерский протез лучше живых ног",
		"бег %.2f (живые 6.00), прыжок %.2f (живой 5.50)" % [master, master_jump])

	body.bleeding = false
	health.revive()
	var steady: float = health.current
	await get_tree().create_timer(BODY.CHAFE_INTERVAL + 1.0).timeout
	check(is_equal_approx(health.current, steady),
		"хороший протез не травмирует", "здоровье держится %.1f" % health.current)

	# Рука: деревянная годится только для ближнего боя.
	await _reset(me, body, health)
	await _sever(body, health, "arm_l")
	await _sever(body, health, "arm_r")
	body.grant_prosthetic(BODY.Limb.ARM_L, 1)
	body.grant_prosthetic(BODY.Limb.ARM_R, 1)
	check(body.can_attack_melee() and not body.can_attack_ranged(),
		"деревянная рука — только ближний бой",
		"меч=%s, лук=%s" % [body.can_attack_melee(), body.can_attack_ranged()])

	body.grant_prosthetic(BODY.Limb.ARM_R, 3)
	check(body.can_attack_ranged() and body.attack_speed_scale() < 1.0,
		"мастерская рука возвращает лук и бьёт быстрее",
		"кулдаун x%.2f" % body.attack_speed_scale())


func _test_wheelchair(me: Node3D, body: Node, health: Node) -> void:
	await _reset(me, body, health)
	await _sever(body, health, "leg_l")
	await _sever(body, health, "leg_r")

	var seated: bool = body.set_wheelchair(true)
	check(seated and body.in_wheelchair, "пересадка в коляску", "in_wheelchair=%s" % body.in_wheelchair)
	check(is_equal_approx(body.move_speed(6.0), BODY.WHEELCHAIR_SPEED),
		"в коляске быстрее, чем ползком", "скорость %.2f м/с" % body.move_speed(6.0))
	check(is_equal_approx(body.jump_velocity(5.5), 0.0), "из коляски не прыгают", "прыжок 0")

	await _reset(me, body, health)
	check(not body.set_wheelchair(true), "со здоровыми ногами коляска не нужна", "отказано")
	# Респавн возвращает конечности на место — и на модели тоже, а не только в
	# маске: воскресший безрукий выглядел бы ошибкой.
	check(not me.limb_hidden(BODY.Limb.LEG_L) and not me.limb_hidden(BODY.Limb.LEG_R),
		"после сброса конечности вернулись на модель",
		"маска %d, левая схлопнута=%s, правая схлопнута=%s" % [
			body.severed_mask, me.limb_hidden(BODY.Limb.LEG_L), me.limb_hidden(BODY.Limb.LEG_R)
		])


## Трофеи: отрубленное у ЧУЖИХ идёт на счёт того, кто рубил.
##
## Проверяем на пешке, а не на втором игроке, потому что именно пешки — основной
## источник конечностей: чтобы набрать десяток, нужна война, а не дуэль.
func _test_trophies(me: Node3D, body: Node, health: Node) -> void:
	await _reset(me, body, health)
	me.trophies = PackedInt32Array([0, 0, 0])

	var victim: Node3D = _world.spawn_unit(0, 0, me.global_position + Vector3(6.0, 0.0, 0.0))
	if victim == null:
		fail("пешку для проверки трофеев не заспавнить")
		return
	await get_tree().process_frame

	# Рубим руку: урона отмеряем с запасом, порог тот же, что у человека.
	var hits := 0
	while victim.severed == 0 and hits < 30:
		victim.health = UNIT_MAX_HEALTH
		victim.take_damage(10.0, int(me.peer_id), "arm_r", victim.global_position, Vector3.FORWARD)
		hits += 1
		await get_tree().process_frame
	check(victim.severed != 0, "пешке отрывает руку тем же порогом, что и человеку",
		"ударов %d, маска %d" % [hits, victim.severed])
	check(me.trophies[me.Trophy.ARMS] == 1,
		"отрубленная рука пешки записана нападавшему в трофеи",
		"рук в трофеях: %d" % me.trophies[me.Trophy.ARMS])

	# Голова: тот же порог, что у человека, и глаз тоже идёт в трофеи.
	var eyes := 0
	while victim.eyes_lost == 0 and eyes < 30:
		victim.health = UNIT_MAX_HEALTH
		victim.take_damage(10.0, int(me.peer_id), "head", victim.global_position, Vector3.FORWARD)
		eyes += 1
		await get_tree().process_frame
	check(victim.eyes_lost == 1, "пешке выбивают глаз", "глаз потеряно %d" % victim.eyes_lost)
	check(me.trophies[me.Trophy.EYES] == 1, "выбитый глаз пешки записан в трофеи",
		"глаз в трофеях: %d" % me.trophies[me.Trophy.EYES])

	# Труп остаётся лежать: по полю после схватки должно быть видно, что тут было.
	var corpses_before: int = _corpse_count()
	victim.health = 1.0
	victim.take_damage(999.0, int(me.peer_id), "torso", victim.global_position, Vector3.FORWARD)
	await get_tree().process_frame
	await get_tree().process_frame
	check(_corpse_count() > corpses_before, "труп пешки остаётся на земле",
		"трупов было %d, стало %d" % [corpses_before, _corpse_count()])


func _corpse_count() -> int:
	var n := 0
	for child in _world.get_node("Spawned").get_children():
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("corpse.gd"):
			n += 1
	return n


## Некротический протез: платят за него чужими конечностями, а не золотом.
func _test_necrotic(me: Node3D, body: Node, health: Node) -> void:
	await _reset(me, body, health)
	# Ставится он у верстака, как кованый и мастерский: крафтить чужую ногу в
	# поле нечем. Значит и проверять надо стоя у верстака.
	var home: Vector3 = me.global_position
	me.global_position = _world.workbench_position() + Vector3(0.0, 1.0, 0.0)
	await get_tree().process_frame
	check(me.at_workbench(), "проверка идёт у верстака", "иначе отказ будет по адресу")
	await _sever(body, health, "leg_l")
	await _sever(body, health, "leg_r")
	body.bleeding = false
	health.revive()

	# Пустой карман: отказ, а не бесплатный протез.
	me.trophies = PackedInt32Array([0, 0, 0])
	me.request_prosthetic(BODY.NECROTIC_TIER)
	check(body.tier(BODY.Limb.LEG_L) == 0,
		"без трофеев некротический протез не ставится",
		"уровень протеза %d" % body.tier(BODY.Limb.LEG_L))

	# Десять ног на ногу. Ног оторвано две — значит и платить надо дважды.
	me.trophies = PackedInt32Array([0, BODY.NECROTIC_PRICE * 2, 0])
	me.request_prosthetic(BODY.NECROTIC_TIER)
	check(body.tier(BODY.Limb.LEG_L) == BODY.NECROTIC_TIER
			and body.tier(BODY.Limb.LEG_R) == BODY.NECROTIC_TIER,
		"десять чужих ног — некротическая нога",
		"уровни %d и %d" % [body.tier(BODY.Limb.LEG_L), body.tier(BODY.Limb.LEG_R)])
	check(me.trophies[me.Trophy.LEGS] == 0, "трофеи списаны по цене за конечность",
		"осталось ног: %d" % me.trophies[me.Trophy.LEGS])

	var necro: float = body.move_speed(6.0)
	body.grant_prosthetic(BODY.Limb.LEG_L, 3)
	body.grant_prosthetic(BODY.Limb.LEG_R, 3)
	var master: float = body.move_speed(6.0)
	check(necro > master, "некротическая нога быстрее мастерской",
		"некроз %.2f, мастерская %.2f" % [necro, master])

	# Мертвечина не приживается: лучший протез травит хозяина.
	body.grant_prosthetic(BODY.Limb.LEG_L, BODY.NECROTIC_TIER)
	body.grant_prosthetic(BODY.Limb.LEG_R, BODY.NECROTIC_TIER)
	body.bleeding = false
	health.revive()
	var before: float = health.current
	await get_tree().create_timer(BODY.CHAFE_INTERVAL + 1.0).timeout
	check(health.current < before, "некротический протез медленно травит хозяина",
		"здоровье %.1f -> %.1f" % [before, health.current])

	# Глаз: возвращает зрение и стоит тех же десяти.
	await _reset(me, body, health)
	health.revive()
	body.register_hit("head", BODY.EYE_THRESHOLD)
	me.trophies = PackedInt32Array([0, 0, BODY.NECROTIC_PRICE])
	me.request_eye()
	check(body.eye_implants == 1 and is_equal_approx(body.blindness(), 0.0),
		"некротический глаз возвращает зрение",
		"вставлено %d, слепота %.2f" % [body.eye_implants, body.blindness()])
	check(me.trophies[me.Trophy.EYES] == 0, "за глаз списано десять чужих глаз",
		"осталось глаз: %d" % me.trophies[me.Trophy.EYES])
	me.request_eye()
	check(body.eye_implants == 1, "лишний глаз не вставить: вставлять некуда",
		"вставлено %d" % body.eye_implants)

	me.global_position = home
	await _reset(me, body, health)


# --- клиент: проверяет, что состояние тела доехало по сети -----------------

func _run_client(watched: Node3D) -> void:
	if watched == null:
		print("[раны] ПРОВАЛ: клиент не нашёл персонажа хоста")
		return
	var seen_severed := false
	var seen_eyes := false
	var seen_wheelchair := false
	var seen_prosthetic := false
	# Ждём достаточно долго, чтобы застать показательное состояние хоста.
	for i in 90:
		await get_tree().create_timer(0.5).timeout
		if seen_severed and seen_eyes and seen_prosthetic and seen_wheelchair:
			break
		if not is_instance_valid(watched):
			break
		if watched.body.severed_mask != 0:
			seen_severed = true
		if watched.body.eyes_lost != 0:
			seen_eyes = true
		if watched.body.in_wheelchair:
			seen_wheelchair = true
		for t in watched.body.prosthetics:
			if t > 0:
				seen_prosthetic = true

	check(seen_severed, "клиент увидел отрыв конечности у хоста", "severed доехал")
	check(seen_eyes, "клиент увидел потерю глаза у хоста", "eyes_lost доехал")
	check(seen_prosthetic, "клиент увидел протез у хоста", "prosthetics доехали")
	check(seen_wheelchair, "клиент увидел коляску у хоста", "in_wheelchair доехал")
	if failures() == 0:
		note("клиент: состояние тела реплицируется полностью")
