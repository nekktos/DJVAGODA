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

enum Kind { VILLAIN, ELVES, GUARD }

const COUNT := 3

const NAMES := ["Злодей", "Лесные эльфы", "Охрана дворца"]

## Где сторона появляется в мире.
const SPAWN := {
	Kind.VILLAIN: Vector3(-300.0, 2.0, 296.0),
	Kind.ELVES: Vector3(-300.0, 2.0, -300.0),
	Kind.GUARD: Vector3(300.0, 8.0, -240.0),
}

## Стратегический режим — только у злодея.
const HAS_STRATEGY := [true, false, false]
## Стройка и наём отряда — тоже пока только у него.
const CAN_BUILD := [true, false, false]

## Чем сторона умеет драться. У злодея атакующая магия (GDD 8.4), эльфы в
## срезе начинают с лука и меча (DESIGN_ANSWERS.md, пункт 18).
const WEAPON_SETS := {
	Kind.VILLAIN: [WEAPONS.Kind.SWORD, WEAPONS.Kind.BOW, WEAPONS.Kind.SPELL],
	Kind.ELVES: [WEAPONS.Kind.SWORD, WEAPONS.Kind.BOW],
	Kind.GUARD: [WEAPONS.Kind.SWORD, WEAPONS.Kind.BOW],
}

## Сколько бойцов сторона получает на старте.
const STARTING_SQUAD := [0, 0, 0]

## Стартовые ресурсы: у злодея есть форт и шахта, эльфы живут грабежом.
const STARTING_RESOURCES := {
	Kind.VILLAIN: [80, 60, 60, 30],
	Kind.ELVES: [0, 0, 0, 0],
	Kind.GUARD: [120, 120, 200, 120],
}

const GOALS := [
	"захватить дворец императора",
	"жить грабежом караванов и добраться до дворца",
	"убить злодея и не отдать дворец",
]


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


static func name_of(faction: int) -> String:
	return NAMES[clampi(faction, 0, COUNT - 1)]


static func goal_of(faction: int) -> String:
	return GOALS[clampi(faction, 0, COUNT - 1)]


static func weapons_text(faction: int) -> String:
	var parts := PackedStringArray()
	for weapon in WEAPON_SETS.get(clampi(faction, 0, COUNT - 1), []):
		parts.append(WEAPONS.NAMES[weapon])
	return ", ".join(parts)
