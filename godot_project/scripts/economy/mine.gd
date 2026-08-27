extends Node3D
##
## Шахта злодея (Этап 5, GDD раздел 2.3): «одна шахта, расположена далеко от
## форта, ресурсы возит караван».
##
## Копит железо и золото сама — считается, что там работают. Забрать накопленное
## можно только караваном: пешком до форта это 240 метров с полными руками.
##
## Добычу считает ТОЛЬКО хост. Шахта стоит в мире статично и одинаково на всех
## пирах, поэтому её запас едет обычным синхронизатором с авторитетом хоста.
##

const RES := preload("res://scripts/economy/resources.gd")

## Сколько единиц в секунду даёт шахта по каждому ресурсу.
##
## Состав намеренно неровный: камень — основная добыча (больше половины), железа
## заметно больше золота, золота мало. Из этого следует, зачем вообще ходить в
## шахту: камень и железо в мире больше взять негде в таком количестве, а золото
## остаётся редким и потому дорогим.
const RATE := {
	RES.Kind.STONE: 3.0,
	RES.Kind.IRON: 1.6,
	RES.Kind.GOLD: 0.4,
}
## Больше этого шахта не накапливает — забирайте караваном или батраками.
const STOCKPILE_CAP := 300

## Что тут добывают. Порядок для показа, доли — в RATE.
const PRODUCES := [RES.Kind.STONE, RES.Kind.IRON, RES.Kind.GOLD]

## Реплицируемое состояние: накопленное по каждому ресурсу.
@export var stored: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])

## Накопленные доли по каждому ресурсу: скорости дробные, а запас целый.
var _fractions := {}


func _process(delta: float) -> void:
	if not Net.hosting():
		return
	var copy := stored.duplicate()
	var changed := false
	for kind in PRODUCES:
		var carry: float = float(_fractions.get(kind, 0.0)) + float(RATE[kind]) * delta
		var whole := int(carry)
		if whole <= 0:
			_fractions[kind] = carry
			continue
		_fractions[kind] = carry - float(whole)
		copy[kind] = mini(STOCKPILE_CAP, copy[kind] + whole)
		changed = true
	if changed:
		stored = copy


## Забрать до limit единиц каждого ресурса. Только на хосте.
## Возвращает то, что реально удалось забрать.
func take(limit: int) -> PackedInt32Array:
	var taken := PackedInt32Array([0, 0, 0, 0])
	if not Net.hosting():
		return taken
	var copy := stored.duplicate()
	for kind in PRODUCES:
		var amount: int = mini(limit, copy[kind])
		copy[kind] -= amount
		taken[kind] = amount
	stored = copy
	return taken


func summary() -> String:
	var parts := PackedStringArray()
	for kind in PRODUCES:
		parts.append("%s %d" % [RES.SHORT[kind], stored[kind]])
	return " ".join(parts)
