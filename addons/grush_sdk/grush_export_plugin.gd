@tool
extends EditorExportPlugin

## Web 書き出しのたびに、プロジェクトの直下の grush.json を index.html の隣へ写す。
## GameRush はビルドの最上位の grush.json だけをランキングの定義として読むが、
## Godot は res:// のファイルを .pck の中へ入れ、書き出し先には出さない。

const MANIFEST_PATH := "res://grush.json"
const FILE_NAME := "grush.json"

var _target_dir := ""


func _get_name() -> String:
	return "GRushLeaderboardManifest"


func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	_target_dir = ""
	if not features.has("web"):
		return
	var absolute := path
	if absolute.begins_with("res://") or absolute.is_relative_path():
		absolute = ProjectSettings.globalize_path("res://").path_join(path.trim_prefix("res://"))
	_target_dir = absolute.get_base_dir()


func _export_end() -> void:
	if _target_dir == "" or not FileAccess.file_exists(MANIFEST_PATH):
		return
	var bytes := FileAccess.get_file_as_bytes(MANIFEST_PATH)
	var target := _target_dir.path_join(FILE_NAME)
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		push_error("[GRush] %s を書き出し先へ写せません: %s" % [FILE_NAME, target])
		return
	file.store_buffer(bytes)
	file.close()
	print("[GRush] %s をビルドの最上位へ写しました: %s" % [FILE_NAME, target])
