extends RefCounted
##
## Ресурсы и цены (Этап 4, GDD раздел 2.3).
##
## Четыре ресурса из GDD: дерево, камень, золото, железо. Балансные числа
## держим здесь одним местом, чтобы правка не расползалась по коду.
##

enum Kind { WOOD, STONE, GOLD, IRON }

const COUNT := 4

const NAMES := ["дерево", "камень", "золото", "железо"]
const SHORT := ["дер", "кам", "зол", "жел"]

## Базовый запас склада на каждый ресурс. Склад поднимает потолок.
const BASE_CAPACITY := 120
const STORAGE_BONUS := 400

## Сколько ресурса даёт один удар по источнику.
const YIELD_PER_HIT := 5
## Сколько ударов выдерживает источник, прежде чем исчерпается.
const SOURCE_HITS := 6
## На каком расстоянии можно добывать.
const HARVEST_RANGE := 3.2

enum Building { STORAGE, BARRACKS }

const BUILDING_NAMES := ["склад", "казарма"]

## Стоимость постройки: [дерево, камень, золото, железо].
const BUILDING_COST := {
	Building.STORAGE: [40, 20, 0, 0],
	Building.BARRACKS: [60, 40, 0, 10],
}

## Сколько секунд строится.
const BUILD_TIME := {
	Building.STORAGE: 6.0,
	Building.BARRACKS: 8.0,
}

## Размер основания, метры. Нужен и для призрака, и для проверки места.
const BUILDING_SIZE := {
	Building.STORAGE: Vector3(12.0, 7.0, 10.0),
	Building.BARRACKS: Vector3(14.0, 6.0, 9.0),
}

## Цена одного мечника из казармы и потолок отряда.
const UNIT_COST := [0, 0, 25, 10]
const SQUAD_LIMIT := 12

## Цена протезов по уровню качества. Закрывает заглушку Этапа 3: раньше их
## выдавали бесплатно, потому что экономики ещё не было.
const PROSTHETIC_COST := {
	1: [20, 0, 0, 0],
	2: [10, 0, 30, 40],
	3: [10, 0, 150, 80],
}


static func format_cost(cost: Array) -> String:
	var parts := PackedStringArray()
	for i in COUNT:
		if int(cost[i]) > 0:
			parts.append("%s %d" % [SHORT[i], int(cost[i])])
	return ", ".join(parts) if parts.size() > 0 else "бесплатно"
