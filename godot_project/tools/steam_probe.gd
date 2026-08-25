extends SceneTree
##
## Диагностика GodotSteam без побочных эффектов: загрузился ли аддон, есть ли
## класс пира, какие у него сигнатуры, и проходит ли инициализация Steam.
##
## Полезен после обновления Godot или GodotSteam — сразу видно, сломалась ли
## совместимость, не запуская игру.
##
## Запуск:
##   godot --headless --path godot_project --script res://tools/steam_probe.gd
##

const DEV_APP_ID := 480


func _initialize() -> void:
	print("--- GodotSteam probe ---")
	var has_singleton := Engine.has_singleton("Steam")
	var has_peer := ClassDB.class_exists("SteamMultiplayerPeer")
	print("синглтон Steam:            ", has_singleton)
	print("класс SteamMultiplayerPeer: ", has_peer)

	if has_peer:
		for m in ClassDB.class_get_method_list("SteamMultiplayerPeer", true):
			if String(m.name).begins_with("create"):
				print("  %s %s(%s)" % [type_string(m["return"].type), m.name, _fmt(m.args)])

	if not has_singleton:
		print("ВЕРДИКТ: аддон не загружен, Steam-транспорт недоступен.")
		quit(1)
		return

	var steam: Object = Engine.get_singleton("Steam")
	var res: Variant = steam.call("steamInitEx", DEV_APP_ID, false)
	var status := int(res.get("status", -1)) if res is Dictionary else -1
	print("steamInitEx(%d, false):    %s" % [DEV_APP_ID, res])

	if status == 0 and has_peer:
		print("ВЕРДИКТ: всё на месте, Steam-транспорт работоспособен.")
		quit(0)
	else:
		print("ВЕРДИКТ: инициализация не прошла. Steam запущен?")
		quit(1)


func _fmt(args: Array) -> String:
	var parts := PackedStringArray()
	for a in args:
		parts.append("%s: %s" % [a.name, type_string(a.type)])
	return ", ".join(parts)
