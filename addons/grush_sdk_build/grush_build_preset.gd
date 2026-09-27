@tool
extends RefCounted

const Settings := preload("res://addons/grush_sdk_build/grush_build_settings.gd")

const CODE_BAD_ARGS := 2
const CODE_WRITE_FAILED := 1


static func ensure(output_dir: String, for_mobile: bool = true) -> Dictionary:
	var problem := Settings.environment_problem()
	if not problem.is_empty():
		return _failure(CODE_BAD_ARGS, problem)
	var absolute := Settings.absolute_dir(output_dir)
	var unsafe := Settings.unsafe_reason(absolute)
	if not unsafe.is_empty():
		return _failure(CODE_BAD_ARGS, unsafe)
	var config := ConfigFile.new()
	if FileAccess.file_exists(Settings.PRESETS_PATH):
		var loaded := config.load(Settings.PRESETS_PATH)
		if loaded != OK:
			return _failure(CODE_WRITE_FAILED, "export_presets.cfg を読めませんでした（error %d）" % loaded)
	var index := Settings.find_preset_index(config)
	if index < 0:
		index = Settings.next_free_index(config)
	var section := "preset.%d" % index
	var changes: Array[String] = []
	var existing_exclude := str(Settings.read_value(config, section, "exclude_filter", ""))
	var preset := Settings.preset_values(Settings.export_path_for(absolute), Settings.merge_exclude_filter(existing_exclude))
	_apply(config, section, preset, changes)
	_apply(config, section + ".options", Settings.option_values(for_mobile), changes)
	if not changes.is_empty():
		var saved := config.save(Settings.PRESETS_PATH)
		if saved != OK:
			return _failure(CODE_WRITE_FAILED, "export_presets.cfg に書き込めませんでした（error %d）" % saved)
	var reimport := false
	if for_mobile:
		var enabled := _enable_mobile_import(changes)
		if not enabled["ok"]:
			return _failure(CODE_WRITE_FAILED, enabled["error"])
		reimport = enabled["changed"]
	return {"ok": true, "code": 0, "preset_index": index, "changes": changes, "reimport": reimport, "error": ""}


static func _apply(config: ConfigFile, section: String, values: Dictionary, changes: Array[String]) -> void:
	for key: String in values:
		var old_value: Variant = Settings.read_value(config, section, key)
		var new_value: Variant = values[key]
		if Settings.same_value(old_value, new_value):
			continue
		config.set_value(section, key, new_value)
		changes.append("%s: %s -> %s" % [key, Settings.display(old_value), Settings.display(new_value)])


static func _enable_mobile_import(changes: Array[String]) -> Dictionary:
	if not OS.has_feature("editor"):
		return {"ok": true, "changed": false, "error": ""}
	var current: Variant = ProjectSettings.get_setting(Settings.MOBILE_IMPORT_SETTING, false)
	if Settings.same_value(current, true):
		return {"ok": true, "changed": false, "error": ""}
	ProjectSettings.set_setting(Settings.MOBILE_IMPORT_SETTING, true)
	var saved := ProjectSettings.save()
	if saved != OK:
		return {"ok": false, "changed": false, "error": "project.godot に書き込めませんでした（error %d）" % saved}
	changes.append("%s: %s -> %s" % [Settings.MOBILE_IMPORT_SETTING, Settings.display(current), Settings.display(true)])
	return {"ok": true, "changed": true, "error": ""}


static func _failure(code: int, message: String) -> Dictionary:
	var changes: Array[String] = []
	return {"ok": false, "code": code, "preset_index": -1, "changes": changes, "error": message}
