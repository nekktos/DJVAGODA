extends Node
##
## Здоровье персонажа. Менять его имеет право ТОЛЬКО хост.
##
## Значение реплицируется отдельным MultiplayerSynchronizer, чей авторитет
## принудительно возвращён хосту (см. player.gd::_enter_tree). Синхронизатор
## движения при этом принадлежит владельцу персонажа — это разные каналы
## специально: движение клиент считает сам, урон — никогда.
##

const MAX_HEALTH := 100.0

## Здоровье изменилось (на любом пире, после репликации).
signal changed(current: float, maximum: float)
## Персонаж умер. Эмитится и на хосте, и на клиентах.
signal died(killer_id: int)

## Реплицируемое состояние.
@export var current: float = MAX_HEALTH
## Прибавка к потолку от прокачки. Ведёт ХОЗЯИН узла (игрок), реплицируется
## вместе со здоровьем: клиент рисует полосу и обязан знать, из чего она.
##
## БАЗА ОСТАЁТСЯ КОНСТАНТОЙ. К MAX_HEALTH привязаны и урон, и проверки, и
## решения по балансу; прокачка прибавляет сверху, а не переписывает базу.
@export var bonus: float = 0.0

var alive := true

var _last_seen := MAX_HEALTH


func _ready() -> void:
	current = maximum()
	_last_seen = current


func _process(_delta: float) -> void:
	# Клиенты узнают об изменениях только через репликацию, поэтому следим за
	# значением, а не за вызовом apply_damage.
	if is_equal_approx(current, _last_seen):
		return
	_last_seen = current
	changed.emit(current, maximum())
	if current <= 0.0 and alive:
		alive = false
		died.emit(0)


## Нанести урон. Вызывается ТОЛЬКО на хосте.
## Возвращает фактически снятое здоровье.
## Потолок здоровья с учётом прокачки.
func maximum() -> float:
	return MAX_HEALTH + bonus


func apply_damage(amount: float, killer_id: int) -> float:
	if not Net.hosting():
		push_error("apply_damage вызван не на хосте — урон считает только хост")
		return 0.0
	if not alive or amount <= 0.0:
		return 0.0
	var before := current
	current = maxf(0.0, current - amount)
	var dealt := before - current
	_last_seen = current
	changed.emit(current, maximum())
	if current <= 0.0:
		alive = false
		died.emit(killer_id)
	return dealt


## Полное восстановление при респавне. Только на хосте.
func revive() -> void:
	if not Net.hosting():
		return
	current = maximum()
	_last_seen = current
	alive = true
	changed.emit(current, maximum())
