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

## Сколько единиц в секунду добавляется в каждый добываемый ресурс.
const RATE_PER_SECOND := 2.0
## Больше этого шахта не накапливает — забирайте караваном.
const STOCKPILE_CAP := 300

## Что тут добывают.
const PRODUCES := [RES.Kind.IRON, RES.Kind.GOLD]

## Реплицируемое состояние: накопленное по каждому ресурсу.
@export var stored: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])

var _fraction := 0.0


func _process(delta: float) -> void:
	if not Net.hosting():
		return
	_fraction += RATE_PER_SECOND * delta
	if _fraction < 1.0:
		return
	var whole := int(_fraction)
	_fraction -= float(whole)

	var copy := stored.duplicate()
	for kind in PRODUCES:
		copy[kind] = mini(STOCKPILE_CAP, copy[kind] + whole)
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
