extends RefCounted
##
## Данные об оружии Этапа 2. Ровно три вида из GDD, раздел 3: меч, лук, одно
## заклинание. Топоры, молоты, арбалеты и остальная магия — по мере готовности
## ядра, не сейчас.
##
## Балансные числа держим здесь одним местом, чтобы правка не расползалась по
## коду персонажа и снарядов.
##

enum Kind { SWORD, BOW, SPELL }

const NAMES := {
	Kind.SWORD: "меч",
	Kind.BOW: "лук",
	Kind.SPELL: "огненный шар",
}

## Задержка между ударами, секунды. Проверяется ХОСТОМ — клиентский кулдаун
## нужен только чтобы не слать заведомо лишние заявки.
const COOLDOWN := {
	Kind.SWORD: 0.7,
	Kind.BOW: 1.0,
	Kind.SPELL: 1.5,
}

const DAMAGE := {
	Kind.SWORD: 35.0,
	Kind.BOW: 30.0,
	Kind.SPELL: 45.0,
}

## Дальность удара мечом, метры.
const SWORD_RANGE := 2.6
## Полуугол сектора поражения мечом, радианы (примерно 50 градусов в каждую сторону).
const SWORD_HALF_ANGLE := 0.9

const PROJECTILE_SPEED := {
	Kind.BOW: 55.0,
	Kind.SPELL: 32.0,
}

## Радиус взрыва огненного шара, метры. У стрелы площади нет.
const SPELL_BLAST_RADIUS := 6.0
## Сколько секунд снаряд живёт, если ни во что не попал.
const PROJECTILE_LIFETIME := 6.0


static func is_projectile(kind: int) -> bool:
	return kind == Kind.BOW or kind == Kind.SPELL
