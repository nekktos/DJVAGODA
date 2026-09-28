extends Node3D
##
## Шахта (Этап 5, GDD 2.3; с доработки 28.09.2026 — GDD 9a).
##
## Шахт ЧЕТЫРЕ, по одной на породу: железо, камень, уголь, золото, и все на
## земле эльфов.
## Какая порода у этой — говорит `kind`, его выставляет мир (`world.gd`).
##
## Копит добытое сама — считается, что там работают. Забрать накопленное можно
## ТОЛЬКО обозом: по решению автора «ресурсы, добытые на шахте, можно
## использовать только после того, как караван дойдёт с шахты до склада».
## Батраки-шахтёры отсюда больше не берут: раньше они носили руду домой в руках,
## мимо обоза, и грабить было нечего.
##
## Запас общий, а не чей-то: кто первым подогнал обоз, тот и увёз.
##
## Добычу считает ТОЛЬКО хост. Шахта стоит в мире статично и одинаково на всех
## пирах, поэтому её запас едет обычным синхронизатором с авторитетом хоста.
##

const RES := preload("res://scripts/economy/resources.gd")

## Сколько единиц в секунду даёт шахта каждой породы.
##
## Камень и железо — прежние скорости единой шахты. Золота больше, чем давала
## попутная жила (0.4), потому что теперь за ним едут отдельным рейсом через
## весь лес, а не везут заодно с камнем; но меньше железа — оно дорогое.
const RATES := {
	RES.Kind.IRON: {RES.Kind.IRON: 1.6},
	RES.Kind.STONE: {RES.Kind.STONE: 3.0},
	RES.Kind.COAL: {RES.Kind.COAL: 1.6},
	RES.Kind.GOLD: {RES.Kind.GOLD: 0.6},
}
## Больше этого шахта не накапливает по каждой породе — забирайте обозом.
const STOCKPILE_CAP := 300

## Главная порода шахты. Выставляет мир при постройке.
var kind: int = RES.Kind.IRON

## Реплицируемое состояние: накопленное по каждому ресурсу.
@export var stored: PackedInt32Array = RES.empty()

## Накопленные доли по каждому ресурсу: скорости дробные, а запас целый.
var _fractions := {}


func _process(delta: float) -> void:
	if not Net.hosting():
		return
	var copy := RES.fit(stored)
	var changed := false
	var rate: Dictionary = RATES.get(kind, {})
	for ore in rate:
		var carry: float = float(_fractions.get(ore, 0.0)) + float(rate[ore]) * delta
		var whole := int(carry)
		if whole <= 0:
			_fractions[ore] = carry
			continue
		_fractions[ore] = carry - float(whole)
		copy[ore] = mini(STOCKPILE_CAP, copy[ore] + whole)
		changed = true
	if changed:
		stored = copy


## Забрать до limit единиц каждого ресурса. Только на хосте.
## Возвращает то, что реально удалось забрать.
func take(limit: int) -> PackedInt32Array:
	var taken := RES.empty()
	if not Net.hosting():
		return taken
	# Берём ВСЁ, что лежит, а не только то, что шахта добывает сейчас: запас
	# мог попасть сюда и иначе (проверки, сохранение), и оставлять его навсегда
	# недоступным незачем.
	var copy := RES.fit(stored)
	for ore in RES.COUNT:
		var amount: int = mini(limit, copy[ore])
		copy[ore] -= amount
		taken[ore] = amount
	stored = copy
	return taken


func summary() -> String:
	var parts := PackedStringArray()
	for ore in RES.COUNT:
		if RES.at(stored, ore) > 0 or RATES.get(kind, {}).has(ore):
			parts.append("%s %d" % [RES.SHORT[ore], RES.at(stored, ore)])
	return " ".join(parts)


## Как шахту называть игроку: «железная шахта».
func title() -> String:
	match kind:
		RES.Kind.IRON: return "железная шахта"
		RES.Kind.STONE: return "каменоломня"
		RES.Kind.COAL: return "угольная шахта"
		RES.Kind.GOLD: return "золотой прииск"
	return "шахта"
