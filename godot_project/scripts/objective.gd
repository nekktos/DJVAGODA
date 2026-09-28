extends Node3D
##
## Цель вертикального среза (Этап 7): дворец императора.
##
## GDD описывает срез как «форт → отряд → построение → марш → бой → ранения →
## результат», но не говорит, что такое результат. Решение из DESIGN_ANSWERS.md,
## пункт 17: злодей захватывает дворец, стража убивает злодея, эльфам дворец
## тоже интересен. Захват НЕ обрывает партию — он меняет её состояние, и злодей
## может продолжать борьбу.
##
## Всё считает ТОЛЬКО хост. Клиенты получают владельца и прогресс захвата и
## просто рисуют.
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")

## Где стоит дворец и какого радиуса точка захвата.
const PALACE := Vector3(300.0, 6.0, -300.0)
const RADIUS := 34.0
## Сколько секунд надо удерживать точку без помех.
const CAPTURE_SECONDS := 20.0
## Насколько быстро прогресс откатывается, когда точку бросили.
const DECAY_PER_SECOND := 0.06

## ПАРТИЯ ИДЁТ ДО ПОСЛЕДНЕЙ СТОРОНЫ (GDD 9a, ответ автора от 28.09 —
## заменяет раздел 7). Цели сторон:
## - злодей: сперва взять дворец — стража и земли людей переходят к нему, —
##   потом вырезать эльфов;
## - стража: уничтожить и злодея, и эльфов;
## - эльфы: вернуть древние земли — уничтожить и стражу, и злодея.
##
## «ПОБЕДА» объявляется одна и только когда на карте осталась одна сторона.
## Выбывшую сторону объявляем отдельно, в миг выбывания.
## Порядок — как в FACTIONS.Kind.
const VICTORY_TEXT := [
	"дворец взят, эльфы вырезаны",
	"древние земли вернулись к эльфам",
	"злодей и эльфы уничтожены",
]
## Как сторона выбыла — для объявления.
const OUT_TEXT := [
	"вожак злодея пал",
	"эльфов больше нет",
	"стража сломлена",
]
## Как часто пересматривать, кто выбыл. Смерть ИИ-вожака, опустевшая сторона
## и прочее не присылают события — их надо заметить.
const CHECK_INTERVAL := 2.0

signal announced(text: String)
## Событие мира — в ЛОГ, а не на экран.
##
## Отдельный канал нужен, потому что смешались две разные вещи. Объявление
## («Дворец захвачен», «ПОБЕДА») адресовано игроку и обязано быть видно.
## А «Набег: Охрана дворца → зона Охрана дворца» — это отладочная строка: она
## выдаёт игроку всезнание о чужих ходах через всю карту, которого у него быть
## не должно, и вдобавок читается бессмыслицей, когда сторона идёт «в набег» на
## собственную зону (`_place_name` берёт ближайшую базу к цели).
##
## Событие всё так же доезжает до всех пиров — это проверяется набором, — но
## на экран не попадает.
signal logged(text: String)

## Реплицируемое состояние.
@export var palace_owner: int = FACTIONS.Kind.GUARD
@export var capture_progress: float = 0.0
@export var contested: bool = false
## Кто сейчас захватывает. -1 — никто.
@export var claimant: int = -1
## Кто из сторон уже объявлен победившим. Байт на сторону, чтобы не объявлять
## одно и то же дважды.
@export var victors: PackedByteArray = PackedByteArray([0, 0, 0])
## Пал ли вожак стороны. Вожак — злодей по рождению и повышенный командир
## стражи; их смерть окончательна.
@export var leader_down: PackedByteArray = PackedByteArray([0, 0, 0])
## Кто выбыл из партии. Байт на сторону. Выбывание окончательно.
@export var out: PackedByteArray = PackedByteArray([0, 0, 0])
## Стража перешла к злодею: дворец взят (GDD 9a). Едет по сети, и по нему
## каждый пир выставляет союз в `FACTIONS.overlord`.
@export var guard_absorbed := false

var _seen_owner := FACTIONS.Kind.GUARD
var _check_t := 0.0


func _ready() -> void:
	position = PALACE
	_seen_owner = palace_owner


## Вернуть исход партии к нерешённому. Зовётся при начале новой партии: без
## этого объявленная победа и павшие вожаки переезжали бы в новый мир, и он
## начинался бы уже проигранным для кого-то.
func reset() -> void:
	palace_owner = FACTIONS.Kind.GUARD
	capture_progress = 0.0
	contested = false
	claimant = -1
	victors = PackedByteArray([0, 0, 0])
	leader_down = PackedByteArray([0, 0, 0])
	out = PackedByteArray([0, 0, 0])
	guard_absorbed = false
	_seen_owner = palace_owner
	_apply_alliances()


func _process(delta: float) -> void:
	# Объявление идёт ТОЛЬКО по RPC. Раньше здесь дублировалась ещё и реакция на
	# смену реплицированного владельца, и клиенты получали баннер дважды.
	_seen_owner = palace_owner
	_apply_alliances()
	if not Net.hosting():
		return
	_server_tick(delta)
	_check_t += delta
	if _check_t >= CHECK_INTERVAL:
		_check_t = 0.0
		check_victories()


## Союз стражи со злодеем — на КАЖДОМ пире, по реплицированному признаку.
func _apply_alliances() -> void:
	FACTIONS.overlord[FACTIONS.Kind.GUARD] = FACTIONS.Kind.VILLAIN if guard_absorbed else -1


func _server_tick(delta: float) -> void:
	var present := _factions_inside()
	contested = present.size() > 1

	if present.is_empty() or contested:
		# Бросили или оспаривают — прогресс откатывается, но не мгновенно.
		claimant = -1
		capture_progress = maxf(0.0, capture_progress - DECAY_PER_SECOND * delta)
		return

	var who: int = present[0]
	if who == palace_owner:
		# Хозяин стоит у себя — просто откатываем чужой прогресс.
		claimant = -1
		capture_progress = maxf(0.0, capture_progress - DECAY_PER_SECOND * delta * 4.0)
		return

	if claimant != who:
		claimant = who
		capture_progress = 0.0
	capture_progress = minf(1.0, capture_progress + delta / CAPTURE_SECONDS)
	if capture_progress >= 1.0:
		_capture(who)


func _capture(faction: int) -> void:
	palace_owner = faction
	capture_progress = 0.0
	claimant = -1
	_seen_owner = faction
	var text := "Дворец захвачен: %s" % FACTIONS.name_of(faction)
	print("[цель] %s" % text)
	announce.rpc(text)
	# Злодей взял дворец — стража и земли людей переходят к нему. Однажды:
	# поглощённой стражи больше нет, и отбить дворец обратно ей некем.
	if faction == FACTIONS.Kind.VILLAIN and not guard_absorbed:
		guard_absorbed = true
		_apply_alliances()
		var world := get_parent()
		if world != null and world.has_method("absorb_guard"):
			world.absorb_guard()
		announce.rpc("Земли людей и стража теперь под рукой злодея")
	check_victories()



# --- условия победы (Этап 10, шаг 2, GDD раздел 7) -------------------------


## Вожак пал. Зовёт мир, когда окончательно умирает злодей или командир стражи.
func report_leader_down(faction: int, killer_faction: int) -> void:
	if not Net.hosting():
		return
	if faction < 0 or faction >= FACTIONS.COUNT or leader_down[faction] == 1:
		return
	leader_down[faction] = 1
	var text := "%s: вожак пал" % FACTIONS.name_of(faction)
	if killer_faction >= 0:
		text += " (%s)" % FACTIONS.name_of(killer_faction)
	print("[цель] %s" % text)
	announce.rpc(text)
	check_victories()


func leader_is_down(faction: int) -> bool:
	return faction >= 0 and faction < FACTIONS.COUNT and leader_down[faction] == 1


## Сторона сломлена. Для стражи этого мало — нужны ОБА условия: пал командир И
## снесена казарма (решение по итогам шага 2). Убить одного человека проще, чем
## выбить гарнизон, и одного убийства не должно хватать.
##
## Пустующая сторона считается сломленной автоматически — но ТОЛЬКО пока за неё
## некому воевать.
##
## Правило стояло здесь с оговоркой «пока ИИ фракций нет»: без него победа
## эльфов вдвоём была бы недостижима, потому что сломить сторону было бы некому
## и нечем. ИИ теперь есть, и у свободной стороны есть вожак — объявлять её
## сломленной, пока он жив и воюет, значит отдавать партию даром (решение по
## ходу шага 8).
##
## Мёртвый вожак стороне не помощник, и его сторона снова сломлена сразу: он не
## возрождается, окончательная смерть у вожаков и есть окончательная.
func faction_is_broken(faction: int) -> bool:
	var world := get_parent()
	var players: Array = world.players_of(faction)
	if players.is_empty():
		# Сторона, у которой ИИ-вожака ЕЩЁ НЕТ, не выбыла: он появляется не в
		# первый кадр партии. С проверкой раз в две секунды (GDD 9a: партия до
		# последней стороны) прежнее «нет вожака — сломлена» выкидывало бы все
		# пустые стороны на старте и объявляло победу первому вошедшему.
		var hero: Node3D = world.ai_hero_of(faction)
		if hero != null and not hero.health.alive:
			return true
	if not leader_is_down(faction):
		return false
	if faction == FACTIONS.Kind.GUARD:
		return not _has_barracks(FACTIONS.Kind.GUARD)
	return true


## Есть ли у стороны живая казарма. Недостроенная тоже считается: сорвать
## стройку — законный способ, но пока она стоит, гарнизон не выбит.
func _has_barracks(faction: int) -> bool:
	for node in get_tree().get_nodes_in_group("building"):
		if not ("faction" in node) or not ("kind" in node):
			continue
		if int(node.faction) != faction:
			continue
		# ТОЛЬКО НАСТОЯЩИЕ КАЗАРМЫ. Раньше здесь стояло «всё, кроме склада» —
		# и пока у стражи была одна казарма, это было одно и то же. С новым
		# стартом (GDD 9a) у стражи поля, дом, конюшня, и набор «победа» поймал
		# последствие: снёс казарму, а стража не сломлена — ферму условие
		# поражения считало казармой. Перечисляем казармы, а не исключаем склад.
		if int(node.kind) in [RES.Building.SWORD_BARRACKS, RES.Building.ARCHER_BARRACKS]:
			return true
	return false


## Выбыла ли сторона — окончательно.
##
## - злодей: пал его вожак (или за пустую сторону пал ИИ-вожак);
## - стража: перешла к злодею с дворцом — или сломлена: пал командир И
##   снесены казармы;
## - эльфы: снесены ВСЕ их дома, даже строящиеся, И в живых нет ни одного
##   эльфа (ответ автора: «при разрушении последней постройки эльфы
##   проигрывают, только если в живых нет никого: им негде возрождаться»).
func side_out(faction: int) -> bool:
	if faction == FACTIONS.Kind.GUARD and guard_absorbed:
		return true
	if faction == FACTIONS.Kind.ELVES:
		var world := get_parent()
		if world != null and world.has_method("elf_houses"):
			return world.elf_houses().is_empty() and world.living_elves() == 0
	return faction_is_broken(faction)


## Пересмотреть, кто выбыл, и объявить победу, если осталась одна сторона.
## Только на хосте.
##
## Выбывание окончательно: вернувшийся на пустую сторону игрок её не
## воскрешает — партия ушла дальше.
func check_victories() -> void:
	if not Net.hosting():
		return
	for faction in FACTIONS.COUNT:
		if out[faction] == 1 or not side_out(faction):
			continue
		out[faction] = 1
		var gone := "%s выбывает из партии: %s" % [FACTIONS.name_of(faction), OUT_TEXT[faction]]
		if faction == FACTIONS.Kind.GUARD and guard_absorbed:
			gone = "%s больше не сторона: она служит злодею" % FACTIONS.name_of(faction)
		print("[цель] %s" % gone)
		announce.rpc(gone)
	var left := []
	for faction in FACTIONS.COUNT:
		if out[faction] == 0:
			left.append(faction)
	if left.size() == 1:
		_declare(int(left[0]))


## Сколько сторон ещё в партии.
func sides_left() -> int:
	var count := 0
	for faction in FACTIONS.COUNT:
		if out[faction] == 0:
			count += 1
	return count


func _declare(faction: int) -> void:
	if victors[faction] == 1:
		return
	victors[faction] = 1
	var text := "ПОБЕДА: %s — %s" % [FACTIONS.name_of(faction), VICTORY_TEXT[faction]]
	print("[цель] %s" % text)
	announce.rpc(text)


## Какие стороны сейчас стоят в точке. Считает хост.
func _factions_inside() -> Array:
	var found := []
	var players := get_parent().get_node_or_null("Players")
	if players == null:
		return found
	for child in players.get_children():
		if not ("faction" in child) or not child.has_method("take_damage"):
			continue
		if not child.health.alive:
			continue
		var flat := Vector3(child.global_position.x, PALACE.y, child.global_position.z)
		if flat.distance_to(PALACE) > RADIUS:
			continue
		# Союзник стоит за сюзерена: страж, служащий злодею, захвату злодея
		# не мешает и своего не начинает.
		var faction: int = FACTIONS._root(int(child.faction))
		if not found.has(faction):
			found.append(faction)
	return found


## Объявить результат всем. Прислать может только хост.
@rpc("any_peer", "call_local", "reliable")
func announce(text: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	announced.emit(text)


## Записать событие мира всем. На экран НЕ выводится — см. `logged`.
@rpc("any_peer", "call_local", "reliable")
func log_event(text: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	print("[мир] %s" % text)
	logged.emit(text)


func status_text() -> String:
	var line := "дворец: %s" % FACTIONS.name_of(palace_owner)
	var gone := PackedStringArray()
	for faction in FACTIONS.COUNT:
		if out[faction] == 1:
			gone.append(FACTIONS.name_of(faction))
	if not gone.is_empty():
		line += "   выбыли: %s" % ", ".join(gone)
	if contested:
		return line + "   ТОЧКА ОСПАРИВАЕТСЯ"
	if claimant >= 0 and capture_progress > 0.0:
		return line + "   захват (%s): %d%%" % [FACTIONS.name_of(claimant), int(capture_progress * 100.0)]
	return line
