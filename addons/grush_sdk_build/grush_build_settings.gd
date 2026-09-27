@tool
extends RefCounted

const PRESET_NAME := "GameRush Web"
const PRESETS_PATH := "res://export_presets.cfg"
const OWN_ADDON_FILTER := "addons/grush_sdk_build/*"
const MOBILE_IMPORT_SETTING := "rendering/textures/vram_compression/import_etc2_astc"
const DEFAULT_OUTPUT_DIR := "build/gamerush"
const EXPORT_FILE_NAME := "index.html"
const UNSET_TEXT := "（未設定）"

const PRESET_LABELS := {
	"platform": "プラットフォーム",
	"export_filter": "書き出すリソース",
}

const OPTION_LABELS := {
	"variant/thread_support": "スレッド（GameRush の配信は COOP/COEP を送らないため無効）",
	"variant/extensions_support": "GDExtension サポート",
	"vram_texture_compression/for_desktop": "PC 向けテクスチャ圧縮（S3TC/BPTC）",
	"vram_texture_compression/for_mobile": "スマホ向けテクスチャ圧縮（ETC2/ASTC）",
	"html/canvas_resize_policy": "キャンバスのリサイズ（適応）",
	"html/focus_canvas_on_start": "起動時にキャンバスへフォーカス",
	"html/custom_html_shell": "カスタム HTML シェル",
	"html/experimental_virtual_keyboard": "仮想キーボード（実験的）",
	"progressive_web_app/enabled": "PWA",
	"progressive_web_app/ensure_cross_origin_isolation_headers": "COOP/COEP ヘッダの付与（PWA）",
}


static func preset_values(export_path: String, exclude_filter: String) -> Dictionary:
	return {
		"name": PRESET_NAME,
		"platform": "Web",
		"runnable": false,
		"advanced_options": false,
		"dedicated_server": false,
		"custom_features": "",
		"export_filter": "all_resources",
		"include_filter": "",
		"exclude_filter": exclude_filter,
		"export_path": export_path,
		"patches": PackedStringArray(),
		"encryption_include_filters": "",
		"encryption_exclude_filters": "",
		"seed": 0,
		"encrypt_pck": false,
		"encrypt_directory": false,
		"script_export_mode": 2,
	}


static func option_values(for_mobile: bool) -> Dictionary:
	return {
		"custom_template/debug": "",
		"custom_template/release": "",
		"variant/extensions_support": false,
		"variant/thread_support": false,
		"vram_texture_compression/for_desktop": true,
		"vram_texture_compression/for_mobile": for_mobile,
		"html/export_icon": true,
		"html/custom_html_shell": "",
		"html/head_include": "",
		"html/canvas_resize_policy": 2,
		"html/focus_canvas_on_start": true,
		"html/experimental_virtual_keyboard": false,
		"progressive_web_app/enabled": false,
		"progressive_web_app/ensure_cross_origin_isolation_headers": false,
		"progressive_web_app/offline_page": "",
		"progressive_web_app/display": 1,
		"progressive_web_app/orientation": 0,
		"progressive_web_app/icon_144x144": "",
		"progressive_web_app/icon_180x180": "",
		"progressive_web_app/icon_512x512": "",
		"progressive_web_app/background_color": Color(0, 0, 0, 1),
	}


static func compare(config: ConfigFile, for_mobile: bool) -> Array[Dictionary]:
	var index := find_preset_index(config)
	var section := "preset.%d" % index
	var rows: Array[Dictionary] = []
	var found_text := "あり" if index >= 0 else "なし"
	rows.append(_row("name", "プリセット「%s」" % PRESET_NAME, found_text, "あり", index >= 0))
	var preset := preset_values("", "")
	for key: String in PRESET_LABELS:
		rows.append(_value_row(config, section, key, PRESET_LABELS[key], preset[key], index >= 0))
	var exclude := str(read_value(config, section, "exclude_filter", ""))
	var excluded := index >= 0 and filter_parts(exclude).has(OWN_ADDON_FILTER)
	rows.append(_row("exclude_filter", "ビルド用アドオンを書き出しから除外", _text_or_unset(exclude), "…," + OWN_ADDON_FILTER, excluded))
	var options := option_values(for_mobile)
	for key: String in OPTION_LABELS:
		rows.append(_value_row(config, section + ".options", key, OPTION_LABELS[key], options[key], index >= 0))
	if for_mobile:
		var imported: Variant = ProjectSettings.get_setting(MOBILE_IMPORT_SETTING, false)
		rows.append(_row(MOBILE_IMPORT_SETTING, "プロジェクト設定: ETC2/ASTC を読み込む", display(imported), display(true), same_value(imported, true)))
	return rows


static func read_value(config: ConfigFile, section: String, key: String, fallback: Variant = null) -> Variant:
	if config.has_section_key(section, key):
		return config.get_value(section, key)
	return fallback


static func find_preset_index(config: ConfigFile) -> int:
	var index := 0
	while config.has_section("preset.%d" % index):
		if str(read_value(config, "preset.%d" % index, "name", "")) == PRESET_NAME:
			return index
		index += 1
	return -1


static func next_free_index(config: ConfigFile) -> int:
	var index := 0
	while config.has_section("preset.%d" % index):
		index += 1
	return index


static func filter_parts(filter: String) -> PackedStringArray:
	var parts := PackedStringArray()
	for part: String in filter.split(",", false):
		var trimmed := part.strip_edges()
		if not trimmed.is_empty() and not parts.has(trimmed):
			parts.append(trimmed)
	return parts


static func merge_exclude_filter(existing: String) -> String:
	var parts := filter_parts(existing)
	if not parts.has(OWN_ADDON_FILTER):
		parts.append(OWN_ADDON_FILTER)
	return ",".join(parts)


static func same_value(left: Variant, right: Variant) -> bool:
	return typeof(left) == typeof(right) and left == right


static func display(value: Variant) -> String:
	if value == null:
		return UNSET_TEXT
	return var_to_str(value)


static func project_root() -> String:
	return ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/")


static func absolute_dir(output_dir: String) -> String:
	var dir := output_dir.strip_edges().replace("\\", "/")
	if dir.is_empty():
		return ""
	if dir.begins_with("res://") or dir.begins_with("user://"):
		return ProjectSettings.globalize_path(dir).replace("\\", "/").simplify_path().trim_suffix("/")
	if dir.is_absolute_path():
		return dir.simplify_path().trim_suffix("/")
	return project_root().path_join(dir).simplify_path().trim_suffix("/")


static func is_inside_project(absolute: String) -> bool:
	var root := project_root()
	return absolute == root or absolute.begins_with(root + "/")


static func project_relative(absolute: String) -> String:
	var root := project_root()
	if absolute == root:
		return ""
	return absolute.substr(root.length() + 1)


static func unsafe_reason(absolute: String) -> String:
	if absolute.is_empty():
		return "出力先が指定されていません"
	if not is_inside_project(absolute):
		return ""
	var relative := project_relative(absolute)
	if relative.is_empty():
		return "プロジェクトのルートそのものには書き出せません。build/gamerush のようなサブフォルダを指定してください"
	if not relative.contains("/"):
		return "プロジェクト直下のフォルダには書き出せません。build/gamerush のように1段下のフォルダを指定してください"
	for reserved: String in ["addons", ".godot"]:
		if relative == reserved or relative.begins_with(reserved + "/"):
			return "%s の中には書き出せません: %s" % [reserved, absolute]
	return ""


static func export_path_for(absolute: String) -> String:
	if is_inside_project(absolute):
		return project_relative(absolute).path_join(EXPORT_FILE_NAME)
	return absolute.path_join(EXPORT_FILE_NAME)


static func _value_row(config: ConfigFile, section: String, key: String, label: String, recommended: Variant, found: bool) -> Dictionary:
	var current: Variant = read_value(config, section, key) if found else null
	return _row(key, label, display(current), display(recommended), same_value(current, recommended))


static func _text_or_unset(text: String) -> String:
	return UNSET_TEXT if text.is_empty() else text


static func _row(key: String, label: String, current: String, recommended: String, ok: bool) -> Dictionary:
	return {"key": key, "label": label, "current": current, "recommended": recommended, "ok": ok}


static func environment_problem() -> String:
	var info := Engine.get_version_info()
	var major := int(info.get("major", 0))
	var minor := int(info.get("minor", 0))
	if major < 4 or (major == 4 and minor < 3):
		return "Godot 4.3 以降が必要です（現在 %s）" % str(info.get("string", "不明"))
	if not OS.has_feature("editor"):
		return "書き出しはエディタ版の Godot から実行してください"
	return ""
