extends RefCounted
##
## Первые минуты: что делать прямо сейчас и куда для этого идти.
##
## ЗАЧЕМ. Живой отчёт по playtest-6 поставил «понятно, что делать дальше»
## ЕДИНИЦУ — при четвёрках за бой, управление, читаемость экрана и звук. Игра
## работает; человек не знает, что в ней делать. Его слова: «не понятно что
## делать, написано мало», «не понятно где шахта», «не понятно моя зона в
## начале». Второй игрок до него спрашивал ровно то же и теми же словами: где
## шахта, где построить склад, маршрут для кого и куда.
##
## ЧЕГО НЕ ХВАТАЛО. HUD показывал ЦЕЛЬ ПАРТИИ — «захватить дворец императора».
## Это верно и совершенно бесполезно на первой минуте: между «захватить дворец»
## и «нажми Tab» лежит десяток шагов, и ни одного из них на экране не было.
## Полный список клавиш под F1 дыру не закрывает: он отвечает «чем», когда
## человек спрашивает «что» и «куда».
##
## КАК УСТРОЕНО. Цепочка шагов на сторону. Показывается РОВНО ОДИН — ближайший
## невыполненный, с клавишами и с местом, куда идти. Место рисуется маяком в
## мире (`waypoint.gd`), потому что «где шахта» словами не лечится: шахта в
## шестистах метрах за холмом, и назвать её «на севере» — ответить наполовину.
##
## ШАГ НАЗАД НЕ ОТКАТЫВАЕТСЯ. Пройденное запоминается номером и только растёт.
## Иначе разрушенный склад вернул бы игрока к шагу «построй склад» на двадцатой
## минуте — ровно тогда, когда он воюет и давно всё понял.
##
## ШАГ МОЖЕТ БЫТЬ НЕОБЯЗАТЕЛЬНЫМ, И ЭТО НЕ ПРИДИРКА. Живой игрок дошёл до шага
## «зайди в лавку» и написал: «зачем мне туда, не понятно, нет определённой
## цели, я ничего не собираюсь покупать; и меня там сразу убили, я даже не
## успел прочитать, что там дают». Он прав дважды.
##
## Во-первых, шаг говорил КУДА и ЧЕМ, но не ГОВОРИЛ ЗАЧЕМ. Во-вторых — и это
## хуже — лавка ЭЛЬФИЙСКАЯ и стоит на поляне их поселения (GDD 2.1). Злодея я
## отправлял за пятьсот семьдесят метров в чужой лес, не сказав ни слова о том,
## что лес чужой. Безопасной её не сделать, она такой задумана; а вот
## предупредить, назвать цену и выгоду и разрешить пройти мимо — можно.
##
## Отсюда два правила. Шаг называет ВЫГОДУ, а не только действие. И шаг,
## который человек вправе не делать, помечен необязательным: он пропускается
## сам, когда сделать его нельзя (нечем платить, лавка не обслужит) — иначе
## цепочка встаёт намертво на том, чего игрок делать не собирался, и до цели
## партии он не доходит вовсе.
##
## ЦЕПОЧКА КОНЧАЕТСЯ ЦЕЛЬЮ ПАРТИИ, а не молчанием: последний шаг у каждой
## стороны — её условие победы, и он не выполняется никогда. Так подсказка
## становится постоянным указателем на дворец, а не исчезает, оставив игрока с
## пустым экраном.
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")
const KEYMAP := preload("res://scripts/ui/keymap.gd")
const ELDER := preload("res://scripts/elder.gd")
const OBJECTIVE := preload("res://scripts/objective.gd")
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")
const COMMANDER := preload("res://scripts/commander.gd")

## Насколько далеко от спавна надо отойти, чтобы шаг «осмотрись» засчитался.
const LOOKED_AROUND := 40.0
## Насколько близко надо подойти к месту, чтобы шаг «дойди» засчитался.
const ARRIVED := 25.0

var _passed := 0
## Чья это цепочка. Без привязки прогресс переезжает между сторонами, а
## цепочки у них РАЗНОЙ ДЛИНЫ: у злодея одиннадцать шагов, у стражи четыре.
## Дошёл до шестого за злодея, сменился персонаж — и обращение к шагу номер
## пять валится за границу массива. Поймано правилом «ругань движка в логе —
## тоже провал»: проверки при этом были зелёными, а лог набора «стража» вырос
## на 3220 ошибок.
var _faction := -1
var _seen_strategy := false
var _spawn := Vector3.ZERO
var _have_spawn := false


## Запомнить, что игрок открывал вид сверху.
##
## Зовёт `main` при переключении режима, а не опрос каждый кадр: игрок успевает
## открыть и закрыть вид между двумя опросами, и шаг не засчитался бы.
func note_strategy() -> void:
	_seen_strategy = true


## Начать заново. Зовётся на новой партии: иначе второй заход продолжился бы с
## конца цепочки, и человек, впервые севший за вторую партию, остался бы без
## подсказки вовсе.
func reset() -> void:
	_passed = 0
	_faction = -1
	_seen_strategy = false
	_have_spawn = false


## Текущий шаг. Пустой словарь — показывать нечего (нет персонажа).
##
## Возвращает `number`, `total`, `text`, `keys`, `place` и `at` — точку в мире
## или `null`, если идти никуда не надо.
func current(world: Node3D, me: Node3D) -> Dictionary:
	if me == null:
		return {}
	# Сменился персонаж или сторона — начинаем цепочку заново. Это не только
	# про границы массива: шаги у сторон разные по смыслу, и продолжать чужую
	# цепочку с середины значит показывать человеку задачи не его стороны.
	if int(me.faction) != _faction:
		_faction = int(me.faction)
		_passed = 0
		_have_spawn = false
	if not _have_spawn:
		_spawn = me.global_position
		_have_spawn = true
	var chain := chain_of(_faction)
	# Пояс поверх подтяжек: даже если прогресс окажется больше цепочки,
	# показать надо последний шаг, а не уронить кадр.
	_passed = clampi(_passed, 0, chain.size() - 1)
	while _passed < chain.size() - 1 and (_done(chain[_passed], world, me)
			or _skipped(chain[_passed], me)):
		_passed += 1
	var step: Dictionary = chain[_passed]
	return {
		"number": _passed + 1,
		"total": chain.size(),
		"text": _live_text(step, world, me),
		"keys": step.get("keys", ""),
		"place": step.get("place", ""),
		"at": step.get("at", null),
	}


## Текст шага с учётом того, что прямо сейчас происходит в точке захвата.
##
## ЗАЧЕМ. Живой игрок встал во дворце и простоял ПЯТЬ МИНУТ: «другого вожака
## нет, просто не хочет дальше работать». Проверка показала, что захват
## исправен — злодей берёт дворец за двадцать секунд. Сломано было другое, и
## сломал это я: последний шаг не меняется НИКОГДА. Человек смотрел ровно туда,
## где была написана задача, а панель повторяла «возьми и удержи» и тогда,
## когда дворец уже был взят.
##
## Отсюда правило: шаг, который нельзя выполнить, обязан хотя бы ОТЧИТЫВАТЬСЯ.
## Здесь он показывает то, что игра и так считает, но прячет мелким шрифтом
## среди пяти строк справа внизу: идёт ли захват, оспаривается ли точка и чей
## дворец сейчас.
func _live_text(step: Dictionary, world: Node3D, me: Node3D) -> String:
	var plain: String = String(step["text"])
	if String(step.get("live", "")) != "palace":
		return plain
	var goal: Node = world.objective
	if goal == null:
		return plain
	if int(goal.palace_owner) == int(me.faction):
		# НЕ «держи его»: живой игрок сразу спросил «а зачем мне держать дворец
		# дальше?» — и незачем. С 28.09 (GDD 9a) взятый дворец отдаёт злодею
		# стражу и земли людей НАВСЕГДА, а партия идёт до последней стороны:
		# следующая цель — эльфы.
		if int(me.faction) == FACTIONS.Kind.VILLAIN:
			return "ДВОРЕЦ ВЗЯТ: земли людей и стража теперь твои, навсегда. Дальше — вырежи эльфов"
		return "Дворец твой, но твоя цель не в нём"
	if bool(goal.contested):
		return ("ТОЧКА ОСПАРИВАЕТСЯ: рядом чужой ВОЖАК. Убей его или выгони "
			+ "за %d м — солдаты захвату не мешают") % int(OBJECTIVE.RADIUS)
	if float(goal.capture_progress) > 0.01:
		return "Захват идёт: %d%%. Не выходи из круга" % int(goal.capture_progress * 100.0)
	return plain


func _done(step: Dictionary, world: Node3D, me: Node3D) -> bool:
	var rule: String = step.get("done", "")
	match rule:
		"strategy":
			return _seen_strategy
		"storage":
			return world.storage_of(int(me.faction)) != null
		"crew":
			return not world.labourers_of(int(me.faction)).is_empty()
		"barracks":
			return _has_barracks(world, int(me.faction))
		"farm":
			return _has_building(world, int(me.faction), RES.Building.FARM)
		"afford_storage":
			return (me.stock.can_afford(RES.BUILDING_COST[RES.Building.STORAGE])
				or _has_building(world, int(me.faction), RES.Building.STORAGE))
		"horse":
			return int(me.stock.horses) > 0
		"house":
			return world.squad_capacity(int(me.faction)) > RES.SQUAD_BASE
		"forge":
			return _has_building(world, int(me.faction), RES.Building.FORGE)
		"squad":
			return not world.units_of(int(me.peer_id)).is_empty()
		"stable":
			return world.stable_of(int(me.faction)) != null
		"iron":
			return me.stock.get_amount(RES.Kind.IRON) > 0
		"trader":
			return world.is_at_trader(me.global_position, int(me.faction))
		"moved":
			return me.global_position.distance_to(_spawn) > LOOKED_AROUND
		"commander":
			return world.commander != null and world.commander.in_range(me.global_position)
		"elder":
			return int(me.order_kind) >= 0
		"arrived":
			var at = step.get("at", null)
			if at == null:
				return true
			# Порог свой у каждого шага. «Дойди и встань» — это двадцать пять
			# метров, а «сходи посмотри, что тебя ждёт» засчитывается издали:
			# требовать от разведки войти внутрь дворца значит требовать штурма.
			return _flat_gap(me.global_position, at) < float(step.get("near", ARRIVED))
	return false


## Можно ли пройти шаг мимо.
##
## Не «игрок поленился», а «сделать его нельзя»: платить нечем или лавка не
## обслужит. Такой шаг молча пропускаем — иначе цепочка встанет на нём, и до
## цели партии человек не доберётся.
func _skipped(step: Dictionary, me: Node3D) -> bool:
	var rule := String(step.get("skip", ""))
	if rule == "forge":
		return not me.stock.can_afford(RES.BUILDING_COST[RES.Building.FORGE])
	if rule == "armor":
		var price: Array = me.next_armor_cost()
		return price.is_empty() or not me.stock.can_afford(price)
	if rule != "gear":
		return false
	var cost: Array = me.next_gear_cost()
	return cost.is_empty() or not me.stock.can_afford(cost) or not me.trade_allowed()


## Как на самом деле берут дворец — словами и числами У ИГРЫ.
##
## ЗАЧЕМ ОТДЕЛЬНО. Живой игрок дошёл до последнего шага, встал внутри дворца и
## написал: «я стою и ничего дальше не происходит». Шаг говорил «войти в ворота
## с юга и стоять внутри» — и это было ПРАВДОЙ, но не всей, а неполная правда в
## подсказке работает как ложь.
##
## Настоящее правило (`objective.gd`): точка засчитывается за двадцать секунд, и
## только пока внутри круга нет ЧУЖОГО ВОЖАКА. Солдаты гарнизона захвату не
## мешают — считаются лишь игроки и герои под ИИ. Стоишь вдвоём с чужим вожаком
## — точка оспаривается, и прогресс откатывается, сколько ни стой.
func _capture_rule() -> String:
	return ("держаться %d секунд · внутри не должно быть чужого вожака · "
		+ "ход захвата виден справа внизу") % int(OBJECTIVE.CAPTURE_SECONDS)


## Цена следующего снаряжения словами. Берём У ИГРЫ, а не вписываем числом:
## цены ещё будут меняться, и подсказка, врущая про цену, хуже молчания.
## Есть ли у стороны казарма — любая. Склад не в счёт: он про добычу, а шаг
## про то, чтобы было кем воевать.
## Есть ли у стороны достроенная постройка такого вида.
func _has_building(world: Node3D, faction: int, kind: int) -> bool:
	for node in world.get_tree().get_nodes_in_group("building"):
		if not ("faction" in node) or not ("kind" in node):
			continue
		if int(node.faction) != faction or int(node.kind) != kind:
			continue
		if float(node.progress) < 1.0:
			continue
		return true
	return false


func _has_barracks(world: Node3D, faction: int) -> bool:
	for node in world.get_tree().get_nodes_in_group("building"):
		if not ("faction" in node) or not ("kind" in node):
			continue
		if int(node.faction) != faction:
			continue
		if int(node.kind) != RES.Building.STORAGE:
			return true
	return false


## Цена постройки словами. Берём У ИГРЫ по той же причине, что и цену
## снаряжения: числа ещё будут меняться, а подсказка, врущая про цену, хуже
## молчания.
func _build_price(kind: int) -> String:
	var cost: Array = RES.BUILDING_COST.get(kind, [])
	if cost.is_empty():
		return ""
	var parts := PackedStringArray()
	# Родительный падеж — по ресурсу на каждый вид из RES.Kind. Уголь шестой:
	# без него цена в угле уронила бы подсказку на обращении за край списка.
	var names := ["дерева", "камня", "золота", "железа", "еды", "угля"]
	for i in RES.COUNT:
		if RES.at(cost, i) > 0:
			parts.append("%d %s" % [RES.at(cost, i), names[i]])
	return ", ".join(parts)


## Расстояние ПО ГОРИЗОНТАЛИ. Дворец стоит на шестиметровом плато, лавка в
## низине: считать по трём осям значит не засчитать приход из-за высоты.
func _flat_gap(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z))


## Куда ведёт шаг «железо»: ко ВХОДУ железной шахты, а не в центр скалы.
## Середина скалы недостижима по определению, и маяк, поставленный туда, звал
## бы игрока внутрь камня. Шахт три (GDD 9a), но казарме нужно именно железо.
func _mine_entrance() -> Vector3:
	var info: Dictionary = WORLD_BUILDER.mine_info(RES.Kind.IRON)
	return WORLD_BUILDER.mine_entrance(info["at"])


## Клавиша действия по раскладке. Подсказки берут клавиши ОТСЮДА, а не пишут
## буквами: после переназначения подсказка «нажми 1» врала бы.
static func _k(action: StringName) -> String:
	return KEYMAP.key_text(action)


static func _walk_keys() -> String:
	return "%s%s%s%s — идти, %s — бежать, %s — от первого лица" % [
		_k(&"move_forward"), _k(&"move_left"), _k(&"move_back"), _k(&"move_right"),
		_k(&"sprint"), _k(&"toggle_view")]


static func _roles_keys() -> String:
	return " / ".join(PackedStringArray([_k(&"role_lumberjack"), _k(&"role_miner"),
		_k(&"role_militia"), _k(&"role_builder"), _k(&"role_farmer")]))


## Цепочка стороны целиком. Открыта наружу ради проверок: набор «онбординг»
## обходит все точки всех цепочек и спрашивает у навигации, дойдёт ли до них
## человек. Маяк, показывающий туда, куда не дойти, — худшая из подсказок.
func chain_of(faction: int) -> Array:
	match faction:
		FACTIONS.Kind.VILLAIN:
			return _villain_chain()
		FACTIONS.Kind.ELVES:
			return _elf_chain()
		_:
			return _guard_chain()


## Злодей. Единственная сторона со стройкой и видом сверху — и единственная, у
## кого цепочка длинная. Порядок повторяет тот, в котором живой игрок задавал
## вопросы вслух: где я, как строить, кем, откуда железо, где купить.
func _villain_chain() -> Array:
	return [
		{
			"text": "Ты злодей. Всё вокруг — твоя зона. Осмотрись: пробегись и оглядись",
			"keys": _walk_keys(),
			"done": "moved",
		},
		{
			# ЗЛОДЕЙ НАЧИНАЕТ С НУЛЯ (GDD 9a), и строить ему пока не на что.
			# Первое дело — набрать самому: камень и золото в микро-шахте у
			# форта, дерево в роще. Без этого шага цепочка начиналась бы с
			# «поставь склад», который поставить невозможно.
			"text": "Строить пока не на что. Набери сам: камень и золото — в микро-шахте у форта, дерево — в роще",
			"keys": "%s — молот, им камень бьётся вдвое · %s по залежи или дереву" % [_k(&"weapon_4"), _k(&"attack")],
			"done": "afford_storage",
			"place": "микро-шахта",
			"at": WORLD_BUILDER.MICRO_MINE_POS,
		},
		{
			"text": "Строят и командуют СВЕРХУ. Открой вид сверху",
			"keys": _k(&"toggle_camera"),
			"done": "strategy",
		},
		{
			"text": "Поставь склад у базы: без него добычу некуда возить",
			"keys": "сверху: %s, затем ЛКМ по земле рядом с фортом" % _k(&"build_storage"),
			"done": "storage",
			"place": "своя база",
			"at": FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN],
		},
		{
			"text": "Найми батраков: они рубят, копают и строят сами",
			"keys": "сверху: %s — нанять, %s — кем именно" % [_k(&"hire_labourer"), _roles_keys()],
			"done": "crew",
		},
		{
			"text": "Поставь поле: еда растёт на нём сама, а фермер уносит её на склад",
			"keys": "сверху: %s — поле, нужно %s · %s — поставить батрака фермером" % [
				_k(&"build_farm"), _build_price(RES.Building.FARM), _k(&"role_farmer")],
			"done": "farm",
			"place": "своя база",
			"at": FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN],
		},
		{
			# КОНЮШНЯ ДО ОБОЗА, а не в конце. Лошадей на старте у злодея нет
			# (GDD 9a), а без лошади обоз не выедет: шаг «нарисуй маршрут»
			# раньше этого был бы невыполним.
			"text": "Обозу нужна лошадь, а лошадь продают в конюшне. Поставь её и купи первую",
			"keys": "сверху: %s — конюшня, нужно %s · у конюшни %s — купить лошадь" % [
				_k(&"build_stable"), _build_price(RES.Building.STABLE), _k(&"interact")],
			"done": "horse",
			"place": "своя база",
			"at": FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN],
		},
		{
			"text": "Железа у форта нет. Оно в железной шахте в лесу эльфов — нарисуй туда маршрут обоза",
			"keys": "сверху: %s — рисовать, ЛКМ — точки, последняя у шахты, Enter — отправить" % _k(&"route"),
			"done": "iron",
			"place": "шахта",
			"at": _mine_entrance(),
		},
		{
			"text": "Воевать пока некем. Поставь казарму: бойцы берутся только из неё",
			"keys": "сверху: %s — казарма мечников, %s — лучников, ЛКМ по земле · нужно %s" % [
				_k(&"build_sword"), _k(&"build_archer"), _build_price(RES.Building.SWORD_BARRACKS)],
			"done": "barracks",
			"place": "своя база",
			"at": FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN],
		},
		{
			"text": "Поставь дом дружины: без него сторона держит только охрану, а не войско",
			"keys": "сверху: %s — дом дружины, нужно %s · каждый дом даёт ещё %d бойцов" % [
				_k(&"build_house"), _build_price(RES.Building.HOUSE), RES.HOUSE_SLOTS],
			"done": "house",
			"place": "своя база",
			"at": FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN],
		},
		{
			"text": "Найми бойцов. Они пойдут за тобой — один ты дворец не возьмёшь",
			"keys": "подойди к казарме и нажми %s — там наём · отряд виден справа внизу" % _k(&"interact"),
			"done": "squad",
			"place": "своя база",
			"at": FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN],
		},
		{
			# КУЗНЯ И УГОЛЬ (GDD 9a): без этого шага закалка оружия пряталась бы
			# за клавишей, о которой никто не сказал. Необязательный: уголь
			# возят обозом из леса эльфов, и первым делом он не нужен.
			"text": "Кузня закаляет оружие за железо и уголь. Уголь — в угольной шахте в лесу эльфов, везёт обоз",
			"keys": "сверху: %s — кузня, нужно %s · у кузни %s — закалить · шаг необязательный" % [
				_k(&"build_forge"), _build_price(RES.Building.FORGE), _k(&"interact")],
			"done": "forge",
			"skip": "forge",
			"place": "своя база",
			"at": FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN],
		},
		{
			"text": "Вот ради чего всё: дворец императора на северо-востоке. Сходи посмотри, что тебя ждёт",
			"keys": "наверх ведёт пандус с юга",
			"done": "arrived",
			"near": 150.0,
			"place": "дворец",
			"at": OBJECTIVE.PALACE,
		},
		{
			# НЕОБЯЗАТЕЛЬНЫЙ, но БОЛЬШЕ НЕ ОПАСНЫЙ. Первая версия отправляла
			# злодея за снаряжением в эльфийский лес за пятьсот семьдесят
			# метров, и живой игрок написал сперва «зачем мне туда, не
			# понятно», а потом «меня там сразу убили». Лавок теперь три, по
			# одной на сторону, и своя стоит у форта. Необязательным шаг
			# остался: покупать никто не обязан.
			# С 28.09 (GDD 9a) оружие злодея закаляют в КУЗНЕ за железо и
			# уголь, а лавка продаёт бинты, стрелы и латы.
			"text": "В своей лавке у форта — чёрная кираса: режет урон почти на пятую часть",
			"keys": "%s у прилавка · цена %s · шаг необязательный" % [
				_k(&"interact"), RES.format_cost(RES.armor_cost(FACTIONS.Kind.VILLAIN, 1))],
			"done": "trader",
			"skip": "armor",
			"place": "своя лавка",
			"at": WORLD_BUILDER.TRADER_POS[FACTIONS.Kind.VILLAIN],
		},
		{
			"text": "Дворец берут не мечом, а временем: войди в ворота с юга и продержись внутри",
			"keys": _capture_rule(),
			"live": "palace",
			"place": "дворец",
			"at": OBJECTIVE.PALACE,
		},
	]


## Эльфы. Стройки у них нет вовсе, и цепочка короткая: вооружиться, понять, чем
## живёшь, дойти до дворца.
func _elf_chain() -> Array:
	return [
		{
			"text": "Ты лесной эльф. Твой лес — юго-западный угол карты. Осмотрись",
			"keys": _walk_keys(),
			"done": "moved",
		},
		{
			# НЕ «купи»: эльфы стартуют с нулём золота (FACTIONS.STARTING_RESOURCES),
			# и первая версия этого шага велела им покупать на пустой карман.
			# Лавка у них своя и в тридцати метрах — значит шаг про МЕСТО, а не
			# про покупку.
			"text": "Лавка — твоя и рядом. Запомни место: сюда носить награбленное и здесь же покупать",
			"keys": "%s у прилавка · денег пока нет, они с грабежа · чужие лавки тебя не обслужат" % _k(&"interact"),
			"done": "trader",
			"place": "лавка",
			"at": WORLD_BUILDER.TRADER_POS[FACTIONS.Kind.ELVES],
		},
		{
			# СТАРЕЙШИНА (GDD 9a): у эльфов теперь есть задания, как у стражи
			# приказы. Без этого шага эльф узнавал о них разве что случайно.
			"text": "Старейшина в поселении даёт задания: засады на обозы, шахты, древние земли",
			"keys": "%s у старейшины" % _k(&"interact"),
			"done": "elder",
			"place": "старейшина",
			"at": ELDER.POSITION,
		},
		{
			"text": "Живёшь ты грабежом. Чужие обозы идут через перекрёсток в центре",
			"keys": "%s у повозки — выпрячь лошадей" % _k(&"interact"),
			"done": "arrived",
			"place": "перекрёсток",
			"at": WORLD_BUILDER.WORKBENCH_POS,
		},
		{
			# С 28.09 (GDD 9a) дворец эльфам не победа: их цель — древние земли,
			# то есть злодей и стража. Дворец — дом стражи, туда и ведёт шаг.
			"text": "Верни древние земли: уничтожь злодея и стражу. Стража — во дворце на северо-востоке",
			"keys": "наверх ведёт пандус с юга · " + _capture_rule(),
			"live": "palace",
			"place": "дворец",
			"at": OBJECTIVE.PALACE,
		},
	]


## Стража. Цель у неё не «дойти», а «служить», и цепочка ведёт к командиру.
func _guard_chain() -> Array:
	return [
		{
			"text": "Ты охрана дворца. Дворец рядом с тобой, и он твой",
			"keys": _walk_keys(),
			"done": "moved",
		},
		{
			"text": "Приказы даёт командир. Подойди к нему и возьми первый",
			"keys": "%s у командира" % _k(&"interact"),
			"done": "commander",
			"place": "командир",
			"at": COMMANDER.POSITION,
		},
		{
			"text": "Выполняй приказы: пять выполненных — повышение",
			"keys": "текущий приказ виден справа внизу",
			"done": "arrived",
			"place": "дворец",
			"at": OBJECTIVE.PALACE,
		},
		{
			"text": "Не отдай дворец: взятый, он отдаст злодею всю стражу. Твоя цель — злодей и эльфы",
			# Правило захвата страже нужнее всех, и с изнанки: её СОЛДАТЫ
			# захвату не мешают вовсе. Чтобы сорвать захват, в круг обязан
			# встать сам вожак — иначе злодей возьмёт дворец посреди гарнизона.
			# Про перемирие здесь больше ни слова: его вырезали вместе с
			# репутацией (GDD раздел 9), а подсказка продолжала звать жать Y.
			"keys": "чужой захват срывается только тем, что ты сам стоишь в круге: %s" % _capture_rule(),
			"live": "palace",
			"place": "дворец",
			"at": OBJECTIVE.PALACE,
		},
	]
