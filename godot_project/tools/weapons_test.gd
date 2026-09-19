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
const WEAPON_VISUAL := preload("res://scripts/combat/weapon_visual.gd")
const MODEL_ANIM := preload("res://scripts/model_anim.gd")

## Модели сторон — те же три, что в `player.gd::MODELS`, в том же порядке.
const SIDE_MODELS := [
	"res://assets/people/Villain.glb",
	"res://assets/people/Elf.glb",
	"res://assets/people/Guard.glb",
]

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "оружие"
	expected_host = 34
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
	_test_archer_stands_behind()
	await _test_harvest_tools(me)
	_test_weapon_sits_in_hand()
	_test_swing_is_animated()
	_test_arrow_cripples_not_severs(me)
	finish()


## Стрела не отрубает конечность, а выводит её из строя (GDD раздел 4).
##
## Проверяем ИСХОД, а не то, что «вид оружия передали»: передать можно и не
## туда. Поэтому каждая проверка смотрит на состояние тела после серии ударов,
## а последняя гонит урон через `take_damage` целиком — ровно тем путём, каким
## он идёт в бою, потому что именно проводка тут и могла отвалиться.
func _test_arrow_cripples_not_severs(me: Node3D) -> void:
	var body: Node = me.body
	var arm_r := 1
	var leg_l := 2
	var leg_r := 3

	body.reset()
	for i in 8:
		body.register_hit("arm_r", 12.0, WEAPONS.Kind.BOW)
	check(body.is_crippled(arm_r) and not body.is_severed(arm_r),
		"стрела калечит руку, но не отрывает", body.summary())

	body.reset()
	for i in 8:
		body.register_hit("arm_r", 12.0, WEAPONS.Kind.SWORD)
	check(body.is_severed(arm_r), "меч руку отрывает", body.summary())

	# Перебитая рука не работает, и протез ей не поможет: она на месте.
	body.reset()
	for i in 8:
		body.register_hit("arm_r", 12.0, WEAPONS.Kind.CROSSBOW)
		body.register_hit("arm_l", 12.0, WEAPONS.Kind.SPELL)
	check(not body.can_attack_melee() and not body.can_attack_ranged(),
		"перебитыми руками не бьют и не стреляют", body.summary())

	check(body.heal_limb(arm_r) and not body.is_crippled(arm_r)
			and body.can_attack_melee(),
		"перебитая рука лечится и снова работает", body.summary())

	# Покалеченная — в одном рубящем ударе от того, чтобы её лишиться.
	body.reset()
	for i in 8:
		body.register_hit("leg_l", 12.0, WEAPONS.Kind.HAMMER)
	var was_crippled: bool = body.is_crippled(leg_l)
	body.register_hit("leg_l", 12.0, WEAPONS.Kind.AXE)
	check(was_crippled and body.is_severed(leg_l),
		"перебитую ногу топор сносит с одного удара", body.summary())
	check(not body.heal_limb(leg_l), "оторванное не лечится ничем", body.summary())

	# Та же дорога, что в бою: от удара до тела вид оружия обязан доехать.
	body.reset()
	for i in 8:
		me.health.revive()
		me.take_damage(12.0, int(me.peer_id), "leg_r", me.global_position,
			Vector3.FORWARD, false, WEAPONS.Kind.BOW)
	me.health.revive()
	check(body.is_crippled(leg_r) and not body.is_severed(leg_r),
		"вид оружия доходит от удара до тела", body.summary())

	body.reset()
	me.health.revive()


## Оружие держат ЗА РУКОЯТЬ, а не за середину клинка.
##
## Живой отчёт: «эльф держит меч за остриё». Проверяем результат, а не сдвиг:
## берём самый дальний назад кусок модели — это и есть рукоять, `_build` кладёт
## её позади всего остального, — и смотрим, что после подвеса он пришёлся НА
## кость, а не в полуметре от неё. Числа `GRIP_Z` при этом не поминаем: проверка
## обязана падать и тогда, когда число поправили, а рукоять всё равно мимо.
func _test_weapon_sits_in_hand() -> void:
	var mount := Node3D.new()
	add_child(mount)
	var worst_kind := -1
	var worst_share := 0.0
	for kind in WEAPONS.NAMES.size():
		var holder: Node3D = WEAPON_VISUAL.attach_at(mount, kind, null, 0)
		if holder == null:
			continue
		# Протяжённость оружия вдоль его оси, вместе с наклонёнными кусками.
		var bounds := AABB()
		var first := true
		for child in holder.get_children():
			var mesh := child as MeshInstance3D
			if mesh == null:
				continue
			var box: AABB = mesh.transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		if first:
			continue
		var span: Vector3 = bounds.size
		var back: float = bounds.position.z
		var front: float = bounds.end.z
		var length: float = front - back
		if length <= 0.0:
			continue
		# Лук — исключение, и законное: он лежит вдоль СВОЕЙ длинной оси Y, а
		# держат его ровно посередине. Правило «за задний конец» — про древко и
		# клинок, то есть про оружие, вытянутое вдоль Z. Меряем его только там,
		# где Z и есть длинная ось; иначе проверка требовала бы держать лук за
		# нижнее плечо.
		if length < maxf(span.x, span.y):
			continue
		# Где на оружии оказалась кисть: 0 — у самого торца, 1 — у острия.
		# Отдельной рукояти у древкового оружия нет, руку кладут на само
		# древко, — поэтому меряем ДОЛЮ, а не расстояние до куска.
		var share: float = (-holder.position.z - back) / length
		if share > worst_share:
			worst_share = share
			worst_kind = kind
		holder.queue_free()
	mount.queue_free()
	check(worst_share < 0.40, "оружие держат за задний конец, а не за середину",
		"худший — %s, кисть на %.0f%% длины от торца" % [
			WEAPONS.NAMES[worst_kind] if worst_kind >= 0 else "нет", worst_share * 100.0
		])


## Удар ВИДЕН: у каждой стороны имя удара разрешается в реальную анимацию.
##
## Точка вызова говорит кенниевскими словами, а модели приехали от Quaternius —
## после переезда `resolve` возвращал пустую строку, и удар не рисовался вовсе.
## Проверяем именно перевод: он и есть то место, где паки расходятся.
func _test_swing_is_animated() -> void:
	var melee_missing: Array[String] = []
	var ranged_missing: Array[String] = []
	for path in SIDE_MODELS:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var root: Node = packed.instantiate()
		var anim := _find_anim(root)
		if anim == null:
			melee_missing.append(path.get_file())
			ranged_missing.append(path.get_file())
			root.queue_free()
			continue
		if MODEL_ANIM.resolve(anim, "attack-melee-right") == "":
			melee_missing.append(path.get_file())
		if MODEL_ANIM.resolve(anim, "holding-right-shoot") == "":
			ranged_missing.append(path.get_file())
		root.queue_free()
	check(melee_missing.is_empty(), "удар в ближнем бою есть у каждой стороны",
		"без удара: %s" % ", ".join(melee_missing) if not melee_missing.is_empty() else "все три")
	check(ranged_missing.is_empty(), "выстрел и каст есть у каждой стороны",
		"без выстрела: %s" % ", ".join(ranged_missing) if not ranged_missing.is_empty() else "все три")

	# Удар — разовый, стойка — цикл. Зациклённый `Sword_Attack` махал бы мечом
	# не переставая, и слово «attack» в его имени стоит НЕ в начале.
	check(MODEL_ANIM.is_one_shot("Sword_Attack")
			and MODEL_ANIM.is_one_shot("Staff_Attack")
			and MODEL_ANIM.is_one_shot("Bow_Shoot")
			and not MODEL_ANIM.is_one_shot("Idle_Attacking")
			and not MODEL_ANIM.is_one_shot("Idle_Weapon"),
		"удар разовый, а боевая стойка зациклена", "и то и другое верно")


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null


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


## Лучник стоит ПОЗАДИ своего места в строю.
##
## Без этого он вставал в первую шеренгу наравне с мечником и умирал первым —
## при том что вся его ценность в стрельбе с двадцати четырёх метров. Проверяем
## смещение, а не позицию в мире: позиция зависит ещё и от того, дошёл ли он.
func _test_archer_stands_behind() -> void:
	var UNIT := preload("res://scripts/units/unit.gd")
	var sword: Node3D = _world.spawn_garrison_unit(FACTIONS.Kind.GUARD, 0,
		Vector3(0.0, 0.5, 0.0), Vector3.ZERO, 40.0, false, false)
	var bow: Node3D = _world.spawn_garrison_unit(FACTIONS.Kind.GUARD, 0,
		Vector3(0.0, 0.5, 0.0), Vector3.ZERO, 40.0, false, true)
	if sword == null or bow == null:
		fail("бойцов для проверки строя создать не удалось")
		return
	check(bow.is_archer and not sword.is_archer, "один лучник, другой мечник",
		"да")
	# +z в осях строя — «назад».
	check(bow._formation_offset().z > sword._formation_offset().z,
		"лучник на том же месте в строю стоит дальше назад",
		"%.1f против %.1f" % [bow._formation_offset().z, sword._formation_offset().z])
	check(is_equal_approx(bow._formation_offset().z - sword._formation_offset().z,
			UNIT.ARCHER_REAR),
		"ровно на заданную величину", "%.0f м" % UNIT.ARCHER_REAR)
	sword.queue_free()
	bow.queue_free()


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
