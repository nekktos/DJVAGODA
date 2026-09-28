extends RefCounted
##
## Задания старейшины эльфов (GDD 9a, 28.09.2026).
##
## Автор поручил придумать страже и эльфам интересные задачи («злодей у нас
## пока самый логичный и играбельный»). Страже их даёт командир (`orders.gd`),
## эльфам — старейшина в поселении, и задачи у них про то, чем эльфы живут:
## грабёж обозов, свои земли и шахты в своём лесу.
##
## Состояние задания лежит на игроке в тех же полях, что приказ стражи
## (`order_kind`, `order_progress`, `orders_done`): у одного персонажа не
## бывает и приказа, и задания разом — он или страж, или эльф.
##

enum Kind { AMBUSH, MINE, LABOURERS, RECLAIM, HORSE, HEAD }

## Круг заданий. «Охота за головой» в круг не входит: её дают, когда сдано
## HEAD_AFTER заданий, — как последний бой у стражи.
const ROTATION := [Kind.AMBUSH, Kind.MINE, Kind.LABOURERS, Kind.RECLAIM, Kind.HORSE]
const KINDS := 6
const HEAD_AFTER := 5

const NAMES := [
	"засада на обоз",
	"изгнать чужаков с шахты",
	"подрубить чужое хозяйство",
	"вернуть землю",
	"пригнать коня",
	"охота за головой",
]

const BRIEFS := [
	"Останови чужой обоз и возьми своё: уведи лошадей, разграбь или разбей повозку.",
	"Встань у любой шахты в нашем лесу и продержись %d секунд, пока рядом нет чужих.",
	"Убей %d батраков злодея или стражи: без рук их хозяйство встанет.",
	"Удержи любой хутор %d секунд, пока рядом нет чужих: это древние земли.",
	"Приведи коня в поселение — верхом.",
	"Убей вожака злодея или командира стражи. Своими руками.",
]

const TARGETS := [1, 20, 3, 20, 1, 1]

## Награда — золото: это валюта эльфийской лавки, и платить им эльфам больше
## нечем (ни шахт, ни складов).
const REWARDS := [
	[0, 0, 50, 0],
	[0, 0, 60, 0],
	[0, 0, 70, 0],
	[0, 0, 60, 0],
	[0, 0, 50, 0],
	[0, 0, 250, 0],
]

## Насколько близко говорить со старейшиной.
const TALK_RANGE := 8.0
## Шахта и хутор: радиус, где стоять и где не должно быть чужих.
const HOLD_RADIUS := 35.0
## «В поселении» — ближе этого к его середине.
const VILLAGE_RADIUS := 60.0


static func name_of(kind: int) -> String:
	return NAMES[clampi(kind, 0, KINDS - 1)]


static func target_of(kind: int) -> int:
	return TARGETS[clampi(kind, 0, KINDS - 1)]


static func reward_of(kind: int) -> Array:
	return REWARDS[clampi(kind, 0, KINDS - 1)]


static func brief_of(kind: int) -> String:
	var index := clampi(kind, 0, KINDS - 1)
	if BRIEFS[index].contains("%d"):
		return BRIEFS[index] % TARGETS[index]
	return BRIEFS[index]


static func progress_text(kind: int, progress: int) -> String:
	var index := clampi(kind, 0, KINDS - 1)
	if TARGETS[index] == 1:
		return "выполнено" if progress >= 1 else "ещё нет"
	return "%d из %d" % [mini(progress, TARGETS[index]), TARGETS[index]]
