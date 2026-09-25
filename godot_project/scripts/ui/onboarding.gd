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
## ЦЕПОЧКА КОНЧАЕТСЯ ЦЕЛЬЮ ПАРТИИ, а не молчанием: последний шаг у каждой
## стороны — её условие победы, и он не выполняется никогда. Так подсказка
## становится постоянным указателем на дворец, а не исчезает, оставив игрока с
## пустым экраном.
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")
const OBJECTIVE := preload("res://scripts/objective.gd")
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")
const COMMANDER := preload("res://scripts/commander.gd")

## Насколько далеко от спавна надо отойти, чтобы шаг «осмотрись» засчитался.
const LOOKED_AROUND := 40.0
## Насколько близко надо подойти к месту, чтобы шаг «дойди» засчитался.
const ARRIVED := 25.0

var _passed := 0
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
	_seen_strategy = false
	_have_spawn = false


## Текущий шаг. Пустой словарь — показывать нечего (нет персонажа).
##
## Возвращает `number`, `total`, `text`, `keys`, `place` и `at` — точку в мире
## или `null`, если идти никуда не надо.
func current(world: Node3D, me: Node3D) -> Dictionary:
	if me == null:
		return {}
	if not _have_spawn:
		_spawn = me.global_position
		_have_spawn = true
	var chain := chain_of(int(me.faction))
	while _passed < chain.size() - 1 and _done(chain[_passed], world, me):
		_passed += 1
	var step: Dictionary = chain[_passed]
	return {
		"number": _passed + 1,
		"total": chain.size(),
		"text": step["text"],
		"keys": step.get("keys", ""),
		"place": step.get("place", ""),
		"at": step.get("at", null),
	}


func _done(step: Dictionary, world: Node3D, me: Node3D) -> bool:
	var rule: String = step.get("done", "")
	match rule:
		"strategy":
			return _seen_strategy
		"storage":
			return world.storage_of(int(me.faction)) != null
		"crew":
			return not world.labourers_of(int(me.faction)).is_empty()
		"iron":
			return me.stock.get_amount(RES.Kind.IRON) > 0
		"trader":
			return world.is_at_trader(me.global_position)
		"moved":
			return me.global_position.distance_to(_spawn) > LOOKED_AROUND
		"commander":
			return world.commander != null and world.commander.in_range(me.global_position)
		"arrived":
			var at = step.get("at", null)
			if at == null:
				return true
			return _flat_gap(me.global_position, at) < ARRIVED
	return false


## Расстояние ПО ГОРИЗОНТАЛИ. Дворец стоит на шестиметровом плато, лавка в
## низине: считать по трём осям значит не засчитать приход из-за высоты.
func _flat_gap(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z))


## Куда ведёт шахта: НЕ центр глыбы, а вход перед ней. Середина
## пятидесятиметровой скалы недостижима по определению, и маяк, поставленный
## туда, звал бы игрока внутрь камня.
func _mine_entrance() -> Vector3:
	var mine: Vector3 = WORLD_BUILDER.MINE_POS
	return mine + Vector3(0.0, 0.0, WORLD_BUILDER.MINE_ENTRANCE_AHEAD)


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
			"keys": "WASD — идти, Shift — бежать, V — от первого лица",
			"done": "moved",
		},
		{
			"text": "Строят и командуют СВЕРХУ. Открой вид сверху",
			"keys": "Tab",
			"done": "strategy",
		},
		{
			"text": "Поставь склад у базы: без него добычу некуда возить",
			"keys": "сверху: 1, затем ЛКМ по земле рядом с фортом",
			"done": "storage",
			"place": "своя база",
			"at": FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN],
		},
		{
			"text": "Найми батраков: они рубят, копают и строят сами",
			"keys": "сверху: B — нанять, 5 / 6 / 7 / 8 — кем именно",
			"done": "crew",
		},
		{
			"text": "Железа в зоне нет, оно только в шахте. Нарисуй туда маршрут обоза",
			"keys": "сверху: C — рисовать, ЛКМ — точки, Enter — отправить",
			"done": "iron",
			"place": "шахта",
			"at": _mine_entrance(),
		},
		{
			"text": "Снаряжение покупают в лавке. Подойди и торгуй",
			"keys": "E у прилавка",
			"done": "trader",
			"place": "лавка",
			"at": WORLD_BUILDER.TRADER_POS,
		},
		{
			"text": "Дворец императора — твоя победа. Возьми его и удержи",
			"keys": "войти в ворота с юга и стоять внутри",
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
			"keys": "WASD — идти, Shift — бежать, V — от первого лица",
			"done": "moved",
		},
		{
			"text": "Лавка стоит у тебя в лесу. Купи оружие, прежде чем лезть в драку",
			"keys": "E у прилавка",
			"done": "trader",
			"place": "лавка",
			"at": WORLD_BUILDER.TRADER_POS,
		},
		{
			"text": "Живёшь ты грабежом. Чужие обозы идут через перекрёсток в центре",
			"keys": "E у повозки — выпрячь лошадей",
			"done": "arrived",
			"place": "перекрёсток",
			"at": WORLD_BUILDER.WORKBENCH_POS,
		},
		{
			"text": "Дворец императора — твоя победа. Он на северо-востоке, на плато",
			"keys": "наверх ведёт пандус с юга",
			"place": "дворец",
			"at": OBJECTIVE.PALACE,
		},
	]


## Стража. Цель у неё не «дойти», а «служить», и цепочка ведёт к командиру.
func _guard_chain() -> Array:
	return [
		{
			"text": "Ты охрана дворца. Дворец рядом с тобой, и он твой",
			"keys": "WASD — идти, Shift — бежать, V — от первого лица",
			"done": "moved",
		},
		{
			"text": "Приказы даёт командир. Подойди к нему и возьми первый",
			"keys": "E у командира",
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
			"text": "Злодей идёт за дворцом. Не отдай его и убей злодея",
			"keys": "перемирие с эльфами — Y",
			"place": "дворец",
			"at": OBJECTIVE.PALACE,
		},
	]
