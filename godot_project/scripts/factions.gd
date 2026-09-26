extends RefCounted
##
## Фракции и их асимметрия (Этап 7).
##
## Три стороны из GDD раздела 2. Игрок выбирает сторону сам, две одинаковые в
## одной сессии запрещены (DESIGN_ANSWERS.md, пункт 3).
##
## Асимметрия здесь не косметическая: стороны отличаются местом старта, целью,
## доступным оружием и — главное — тем, есть ли у них стратегический режим.
## Он есть ТОЛЬКО у злодея (DESIGN_ANSWERS.md, пункт 19), и это закрывает
## вопрос, который GDD раздел 1 оставлял открытым.
##

const WEAPONS := preload("res://scripts/combat/weapons.gd")
const ABILITIES := preload("res://scripts/combat/abilities.gd")
const RES := preload("res://scripts/economy/resources.gd")

enum Kind { VILLAIN, ELVES, GUARD }

const COUNT := 3

const NAMES := ["Злодей", "Лесные эльфы", "Охрана дворца"]

## Опознавательный цвет стороны: им красится перевязь на груди у всех, кто за
## эту сторону воюет (`rig.gd::faction_band`).
##
## ЦВЕТА ПОДОБРАНЫ ПОД КАРТУ, А НЕ ПОД НАЗВАНИЕ. Эльфам просится зелёный — и
## именно его брать нельзя: карта зелёная, и зелёная лента на зелёном поле не
## видна вовсе.
##
## ВТОРАЯ ПОПЫТКА. Сперва эльфам достался бирюзовый, и проверка «цвета сторон не
## путаются между собой» его завернула: до синего у стражи было всего 0.46 при
## пороге 0.5. Различать их пришлось бы в свалке, издали и в тени — там бирюза и
## синий сливаются. Взяли золото: до багрового 0.73, до синего 1.26.
##
## Три цвета намеренно далеки друг от друга и по тону, и по светлоте.
const COLORS := [
	Color(0.78, 0.09, 0.12),   # злодей — багровый
	Color(0.95, 0.80, 0.10),   # эльфы — золотой
	Color(0.13, 0.30, 0.92),   # стража — синий
]


static func color_of(faction: int) -> Color:
	return COLORS[clampi(faction, 0, COUNT - 1)]

## Где сторона появляется в мире.
const SPAWN := {
	Kind.VILLAIN: Vector3(-300.0, 2.0, 296.0),
	Kind.ELVES: Vector3(-300.0, 2.0, -300.0),
	Kind.GUARD: Vector3(300.0, 8.0, -240.0),
}

## Сколько игроков помещается на сторону.
##
## Злодей ОДИН по определению: он один человек с личной армией, а не отряд
## равных. У эльфов и стражи это партизанский отряд и караул — их естественно
## больше одного.
const SLOTS := [1, 5, 5]


## Стратегический режим — только у злодея.
const HAS_STRATEGY := [true, false, false]
## Стройка и наём отряда — тоже пока только у него.
const CAN_BUILD := [true, false, false]

## Чем сторона умеет драться. У злодея атакующая магия (GDD 8.4), эльфы в
## срезе начинают с лука и меча (DESIGN_ANSWERS.md, пункт 18).
## Меч и лук — общая база, плюс одно эксклюзивное тяжёлое оружие на сторону
## (GDD раздел 3.1). Порядок в списке — это порядок клавиш 1, 2, 3, ...
const WEAPON_SETS := {
	# У злодея четыре вида оружия и вдобавок три заклинания на 4/5/6, поэтому
	# огненный шар оставлен на прежней третьей клавише — за неё держится рука, —
	# а молот получил отдельную, седьмую. Иначе пришлось бы двигать шар и ломать
	# привычку ради порядка в списке.
	Kind.VILLAIN: [WEAPONS.Kind.SWORD, WEAPONS.Kind.BOW, WEAPONS.Kind.SPELL,
		WEAPONS.Kind.HAMMER],
	Kind.ELVES: [WEAPONS.Kind.SWORD, WEAPONS.Kind.BOW, WEAPONS.Kind.AXE],
	Kind.GUARD: [WEAPONS.Kind.SWORD, WEAPONS.Kind.BOW, WEAPONS.Kind.CROSSBOW],
}


## Какое оружие стоит на этой клавише у этой стороны. -1 — клавиша пустая.
##
## Раньше клавиши 1/2/3 были жёстко привязаны к мечу, луку и заклинанию, и новое
## оружие вешать было некуда. Теперь клавиша — это НОМЕР В НАБОРЕ стороны, и
## каждая сторона получает свои три-четыре подряд, без дыр.
static func weapon_on_slot(faction: int, slot: int) -> int:
	var set: Array = WEAPON_SETS.get(clampi(faction, 0, COUNT - 1), [])
	return int(set[slot]) if slot >= 0 and slot < set.size() else -1

## Способности поддержки. Друидический уклон — только у эльфов (GDD 8.4):
## лечение, бафф и призыв животных. У злодея своя магия, но атакующая, и она
## живёт в WEAPON_SETS; страже магия не положена вовсе.
const ABILITY_SETS := {
	Kind.VILLAIN: [ABILITIES.Kind.PARALYSIS, ABILITIES.Kind.WITHER, ABILITIES.Kind.BLIND],
	Kind.ELVES: [ABILITIES.Kind.HEAL, ABILITIES.Kind.RALLY, ABILITIES.Kind.SUMMON],
	Kind.GUARD: [],
}


## Какая способность на этой клавише у этой стороны. -1 — клавиша пустая.
## Клавиши 4/5/6 одни и те же, а что на них — зависит от стороны.
static func ability_on_slot(faction: int, slot: int) -> int:
	var set: Array = ABILITY_SETS.get(clampi(faction, 0, COUNT - 1), [])
	return int(set[slot]) if slot >= 0 and slot < set.size() else -1


## Сколько бойцов сторона получает на старте.
const STARTING_SQUAD := [0, 0, 0]

## Стартовые ресурсы: у злодея есть форт и шахта, эльфы живут грабежом.
const STARTING_RESOURCES := {
	Kind.VILLAIN: [80, 60, 60, 30],
	Kind.ELVES: [0, 0, 0, 0],
	Kind.GUARD: [120, 120, 200, 120],
}

## Лошади на старте.
##
## У злодея пара: форт и шахта в двухстах сорока метрах друг от друга без единой
## лошади — это хозяйство, которое не может начать работать. Первый обоз должен
## уехать до всякой конюшни, иначе выходит замкнутый круг: обозу нужны лошади,
## лошадям конюшня, конюшне железо, а железо возит обоз. Этот круг я честно
## построил и на нём же встал — сторона за пять минут успевала поставить только
## склад.
##
## Эльфы живут грабежом и лошадей заводят захватом, страже обозы не нужны.
## Четыре, а не две. Игрок держит в пути до двух обозов, упряжка по умолчанию —
## пара: на две пары нужно четыре. С двумя лошадьми первый же обоз забирал всю
## конюшню, и второй отправить было нечем — набор караванов это и поймал.
const STARTING_HORSES := {
	Kind.VILLAIN: 4,
	Kind.ELVES: 0,
	Kind.GUARD: 0,
}

## Потолок склада на старте.
##
## У злодея он базовый и растёт от построенных складов. Эльфы и стража строить
## не умеют (CAN_BUILD), поднять потолок им нечем — поэтому он задан сразу.
## Без этого стража со стартовыми 200 золота при базовом потолке 120 не смогла
## бы получить НИ ОДНОЙ монеты: свободное место считается как потолок минус
## текущее, и оно выходило нулевым или отрицательным.
const STARTING_CAPACITY := [RES.BASE_CAPACITY, 400, 600]


const GOALS := [
	"захватить дворец императора",
	"жить грабежом караванов и добраться до дворца",
	"убить злодея и не отдать дворец",
]


static func starting_capacity(faction: int) -> int:
	return STARTING_CAPACITY[clampi(faction, 0, COUNT - 1)]


static func slots(faction: int) -> int:
	return SLOTS[clampi(faction, 0, COUNT - 1)]


## Сколько игроков вмещает сессия целиком.
static func total_slots() -> int:
	var sum := 0
	for n in SLOTS:
		sum += int(n)
	return sum


static func has_strategy(faction: int) -> bool:
	return HAS_STRATEGY[clampi(faction, 0, COUNT - 1)]


static func can_build(faction: int) -> bool:
	return CAN_BUILD[clampi(faction, 0, COUNT - 1)]


static func allows_weapon(faction: int, weapon: int) -> bool:
	var set: Array = WEAPON_SETS.get(clampi(faction, 0, COUNT - 1), [])
	return set.has(weapon)


## Первое разрешённое стороне оружие — с ним и начинаем.
static func default_weapon(faction: int) -> int:
	var set: Array = WEAPON_SETS.get(clampi(faction, 0, COUNT - 1), [WEAPONS.Kind.SWORD])
	return int(set[0]) if set.size() > 0 else WEAPONS.Kind.SWORD


static func allows_ability(faction: int, ability: int) -> bool:
	var set: Array = ABILITY_SETS.get(clampi(faction, 0, COUNT - 1), [])
	return set.has(ability)


static func has_abilities(faction: int) -> bool:
	return not ABILITY_SETS.get(clampi(faction, 0, COUNT - 1), []).is_empty()


static func name_of(faction: int) -> String:
	return NAMES[clampi(faction, 0, COUNT - 1)]


static func goal_of(faction: int) -> String:
	return GOALS[clampi(faction, 0, COUNT - 1)]


static func abilities_text(faction: int) -> String:
	var parts := PackedStringArray()
	for ability in ABILITY_SETS.get(clampi(faction, 0, COUNT - 1), []):
		parts.append(ABILITIES.name_of(ability))
	return ", ".join(parts)


static func weapons_text(faction: int) -> String:
	var parts := PackedStringArray()
	for weapon in WEAPON_SETS.get(clampi(faction, 0, COUNT - 1), []):
		parts.append(WEAPONS.NAMES[weapon])
	return ", ".join(parts)
