extends RefCounted
##
## Настройка анимаций импортированной модели.
##
## glTF из пака Kenney приезжает в Godot с режимом LOOP_NONE: анимация ходьбы
## проигрывается один раз и замирает, а персонаж дальше едет в позе последнего
## кадра. Циклические анимации надо помечать вручную.
##
## Разовыми оставляем те, что по смыслу играются один раз: смерть, удары,
## взаимодействия и эмоции. Всё остальное — цикл.
##

## Начала имён анимаций, которые НЕ зацикливаем.
## У Kenney смерть называется «die», у Quaternius «Death», прыжок в приземление
## «Jump_ToIdle» — сравниваем в нижнем регистре и держим оба словаря названий в
## одном списке. Зациклённая смерть выглядит как труп, который встаёт и умирает
## снова, и заметить это в бою некому: смотрят на живых.
const ONE_SHOT_PREFIXES := [
	"die", "death", "attack", "emote", "interact", "pick-up", "jump_toidle",
]


static func make_looping(player: AnimationPlayer) -> void:
	if player == null:
		return
	for anim_name in player.get_animation_list():
		var anim: Animation = player.get_animation(anim_name)
		if anim == null:
			continue
		anim.loop_mode = Animation.LOOP_NONE if is_one_shot(anim_name) else Animation.LOOP_LINEAR


static func is_one_shot(anim_name: String) -> bool:
	var lowered := anim_name.to_lower()
	for prefix in ONE_SHOT_PREFIXES:
		if lowered.begins_with(prefix):
			return true
	return false
