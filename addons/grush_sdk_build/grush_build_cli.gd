extends SceneTree

const Preset := preload("res://addons/grush_sdk_build/grush_build_preset.gd")
const Export := preload("res://addons/grush_sdk_build/grush_build_export.gd")
const Settings := preload("res://addons/grush_sdk_build/grush_build_settings.gd")

const PREFIX := "[grush-build] "
const USAGE := "godot --headless --path . --script res://addons/grush_sdk_build/grush_build_cli.gd -- --output build/gamerush [--no-mobile-textures] [--preset-only]"


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var parsed := _parse(args)
	if parsed.has("error"):
		_say(str(parsed["error"]))
		_say("usage: " + USAGE)
		return Export.CODE_BAD_ARGS
	var problem := Export.environment_problem()
	if problem.is_empty():
		problem = Settings.unsafe_reason(Settings.absolute_dir(str(parsed["output"])))
	if not problem.is_empty():
		_say(problem)
		return Export.CODE_BAD_ARGS
	var preset := Preset.ensure(str(parsed["output"]), bool(parsed["mobile"]))
	if not preset["ok"]:
		_say(str(preset["error"]))
		return int(preset["code"])
	_say("プリセット「%s」: preset.%d" % [Settings.PRESET_NAME, int(preset["preset_index"])])
	for change: String in preset["changes"]:
		_say("set " + change)
	if preset["changes"].is_empty():
		_say("プリセットは推奨設定のままです（変更なし）")
	if preset.get("reimport", false):
		_say("ETC2/ASTC を有効にしたため、テクスチャが再インポートされます")
	if parsed["preset_only"]:
		_say("--preset-only のため書き出しは省略しました")
		return Export.CODE_OK
	_say("書き出し中: " + Settings.absolute_dir(str(parsed["output"])))
	var result := Export.run(str(parsed["output"]))
	if int(result["code"]) == Export.CODE_EXPORT_FAILED:
		for line: String in str(result["log"]).split("\n", false):
			_say("godot: " + line)
	for line: String in str(result["message"]).split("\n", false):
		_say(line)
	for warning: String in result["warnings"]:
		_say("警告: " + warning)
	return int(result["code"])


func _parse(args: PackedStringArray) -> Dictionary:
	var parsed := {"output": "", "mobile": true, "preset_only": false}
	var index := 0
	while index < args.size():
		var arg := args[index]
		match arg:
			"--output":
				if index + 1 >= args.size():
					return {"error": "--output の後に出力先フォルダを指定してください"}
				index += 1
				parsed["output"] = args[index]
			"--no-mobile-textures":
				parsed["mobile"] = false
			"--preset-only":
				parsed["preset_only"] = true
			_:
				return {"error": "不明な引数です: " + arg}
		index += 1
	if str(parsed["output"]).strip_edges().is_empty():
		return {"error": "--output は必須です"}
	return parsed


func _say(line: String) -> void:
	print(PREFIX + line)
