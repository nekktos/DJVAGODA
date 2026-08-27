extends "res://tools/test_base.gd"
##
## Долгий прогон мира без людей (Этап 10, шаг 8). Работает headless.
##
## Запуск: godot --headless --path godot_project -- --host --soaktest
##
## ЗАЧЕМ ЭТО ОТДЕЛЬНО ОТ ОСТАЛЬНЫХ НАБОРОВ. Все прочие проверки короткие: они
## смотрят, делает ли система то, что должна, в течение нескольких секунд. Но
## ИИ — это то, что работает часами без присмотра, и ломается он не сразу.
## Отряд, который каждые две секунды ставит новую цель и не доходит ни до одной;
## гарнизон, который пополняет штат быстрее, чем тот гибнет; бойцы, которые
## накапливаются в мире, потому что кто-то забыл их убрать, — ничего из этого
## короткая проверка не увидит.
##
## Поэтому здесь мы не проверяем поведение. Мы оставляем мир вариться сам с
## собой на несколько минут и смотрим на три вещи, каждая из которых означает
## поломку: сколько бойцов в мире, сколько ошибок в логе и не встал ли кто-то
## намертво.
##

const FACTIONS := preload("res://scripts/factions.gd")
const GARRISON := preload("res://scripts/ai/garrison.gd")
const WARBAND := preload("res://scripts/ai/warband.gd")
const RES := preload("res://scripts/economy/resources.gd")
const UNIT := preload("res://scripts/units/unit.gd")

## Сколько варить мир. Три минуты — это больше десятка циклов «выйти в набег,
## подраться, отойти, пополниться», и уже видно, копится ли что-нибудь.
const SOAK_SECONDS := 180.0

## Как часто снимать показания.
const SAMPLE_INTERVAL := 5.0

var _world: Node3D
## Сколько бойцов было в мире в каждый замер.
var _counts := PackedInt32Array()
## Какие состояния отряда встретились. Пустое множество состояний, кроме одного,
## означало бы застывший ИИ.
var _states := {}
## Позиции якорей в каждый замер — чтобы отличить поход от топтания.
var _travelled := 0.0
## Объявления за прогон. Их число — мера того, не заело ли ИИ: набег должен
## кончаться результатом, а не повторяться каждые несколько секунд.
var _heard := 0
## Постройка-приманка: её судьба и есть итог набега.
var _bait: Node3D = null


func start(world: Node3D) -> void:
	tag = "выдержка"
	expected_host = 9
	expected_client = 1
	_world = world
	_world.objective.announced.connect(func(_text: String) -> void: _heard += 1)
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(3.0).timeout

	# Даём ИИ повод воевать. Без имущества в чужой половине карты набегов не
	# будет вовсе — так и задумано (см. RAID_RANGE), но тогда и выдерживать
	# нечего: мир просто стоит. Ставим склад злодея на полпути к базе стражи,
	# то есть делаем ровно то, за что по замыслу и приходят.
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		return
	var mine_base: Vector3 = FACTIONS.SPAWN[int(me.faction)]
	var guard_base: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.GUARD]
	var spot := mine_base.lerp(guard_base, 0.5)
	spot.y = 0.0
	_bait = _world.spawn_building(RES.Building.STORAGE, spot,
		int(me.peer_id), int(me.faction), true)
	check(_bait != null, "приманка для ИИ поставлена", "склад на полпути к страже")

	# Игрок при этом уходит к себе: проверяем поведение ИИ, а не драку с ним.
	me.teleport.rpc(mine_base + Vector3(0.0, 2.0, 6.0))
	await get_tree().physics_frame

	var last := {}
	var elapsed := 0.0
	while elapsed < SOAK_SECONDS:
		await get_tree().create_timer(SAMPLE_INTERVAL).timeout
		elapsed += SAMPLE_INTERVAL
		_counts.append(_units())
		if is_instance_valid(_bait) and int(elapsed) % 20 == 0:
			var near := INF
			var picked := "нет"
			for unit in get_tree().get_nodes_in_group("unit"):
				if not is_instance_valid(unit) or int(unit.faction) != FACTIONS.Kind.GUARD:
					continue
				var d: float = unit.global_position.distance_to(_bait.global_position)
				if d < near:
					near = d
					var t: Node3D = unit._find_target()
					picked = "нет" if t == null else str(t.name)
			var wb: Node = _world.warband
			var anchor: Vector3 = wb.anchor_of(FACTIONS.Kind.GUARD)
			var centre: Vector3 = wb._centre_of(FACTIONS.Kind.GUARD)
			var route: Array = wb._route.get(FACTIONS.Kind.GUARD, [])
			note("%ds: склад %d hp, страж в %.0f м (цель %s) | якорь %s, отряд в %.0f м от якоря, точек %d, %s"
				% [int(elapsed), int(_bait.health), near, picked, str(anchor.round()),
					(centre.distance_to(anchor) if centre.is_finite() else -1.0), route.size(),
					WARBAND.STATE_NAMES[wb.state_of(FACTIONS.Kind.GUARD)]])
		for faction in FACTIONS.COUNT:
			_states[_world.warband.state_of(faction)] = true
			var anchor: Vector3 = _world.warband.anchor_of(faction)
			if not anchor.is_finite():
				continue
			if last.has(faction):
				_travelled += anchor.distance_to(last[faction])
			last[faction] = anchor

	_report()
	finish()


func _units() -> int:
	var count := 0
	for unit in get_tree().get_nodes_in_group("unit"):
		if is_instance_valid(unit):
			count += 1
	return count


func _report() -> void:
	if _counts.is_empty():
		fail("замеров не сделано")
		return

	var first: int = _counts[0]
	var peak: int = _counts[0]
	var low: int = _counts[0]
	for value in _counts:
		peak = maxi(peak, value)
		low = mini(low, value)
	note("бойцов в мире: начало %d, минимум %d, максимум %d, замеров %d"
		% [first, low, peak, _counts.size()])

	# Потолок населения. Каждая свободная сторона держит GARRISON.SIZE бойцов,
	# плюс распорядитель стражи. Запас вдвое — на бойцов, которые уже мертвы, но
	# ещё не убраны из дерева в этом кадре.
	var ceiling: int = FACTIONS.COUNT * GARRISON.SIZE * 2 + 2
	check(peak <= ceiling, "население мира не растёт бесконтрольно",
		"максимум %d при потолке %d" % [peak, ceiling])

	# И не вымирает: гарнизон обязан восполнять потери, иначе через час мир снова
	# станет пустым — тем самым, ради ухода от которого ступень «а» и делалась.
	check(low >= GARRISON.SIZE, "мир не вымирает",
		"минимум %d бойцов" % low)

	# ИИ живой: за три минуты он обязан побывать не в одном состоянии.
	check(_states.size() >= 2, "ИИ меняет состояния, а не застыл",
		"состояний встречено: %d" % _states.size())

	# И обязан реально ходить, а не топтаться. Три минуты стояния на месте дали
	# бы ноль, а бесконечная смена цели — неправдоподобно много.
	check(_travelled > 100.0, "отряды действительно ходят по карте",
		"суммарно %.0f м" % _travelled)
	# Верхняя граница — по скорости самого бойца: якорь теперь стоит на точках
	# маршрута и не может уехать быстрее тех, кто до них доходит.
	check(_travelled < UNIT.BASE_SPEED * 1.5 * SOAK_SECONDS * FACTIONS.COUNT,
		"и не мечутся быстрее, чем физически могут идти",
		"%.0f м за %.0f с" % [_travelled, SOAK_SECONDS])

	check(_counts[_counts.size() - 1] > 0, "мир жив к концу прогона",
		"%d бойцов" % _counts[_counts.size() - 1])

	# Набег обязан КОНЧАТЬСЯ. Пока постройку нельзя было сломать, отряд доходил
	# до неё и ставил ту же цель заново — снаружи это выглядело как война, а на
	# деле мир стоял. Проверяем результат, а не намерение.
	check(_bait == null or not is_instance_valid(_bait), "набег дошёл до конца: приманка разрушена",
		"склад %s" % ("снесён" if _bait == null or not is_instance_valid(_bait) else "цел"))

	# И объявлений должно быть немного: одно на набег, а не одно на каждый
	# пересчёт цели. Три минуты — это единицы набегов.
	check(_heard <= 12, "об одном набеге объявляют один раз",
		"объявлений за прогон: %d" % _heard)
