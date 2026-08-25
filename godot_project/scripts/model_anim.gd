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
const ONE_SHOT_PREFIXES := ["die", "attack", "emote", "interact", "pick-up"]


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
