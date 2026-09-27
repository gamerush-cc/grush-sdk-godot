@tool
extends Node

const Settings := preload("res://addons/grush_sdk_build/grush_build_settings.gd")
const Preset := preload("res://addons/grush_sdk_build/grush_build_preset.gd")
const Export := preload("res://addons/grush_sdk_build/grush_build_export.gd")

const METADATA_SECTION := "grush_sdk_build"
const METADATA_KEY := "output_dir"
const APPLY_ACTION := "grush_apply_recommended"
const DIALOG_SIZE := Vector2i(760, 560)
const LOG_TAIL_LINES := 15
const OK_COLOR := Color(0.45, 0.85, 0.45)
const NG_COLOR := Color(0.95, 0.4, 0.4)
const MOBILE_TEXT := "スマホ向けのテクスチャ圧縮（ETC2/ASTC）も含める"
const NOTE_TEXT := "プリセット「GameRush Web」を export_presets.cfg に作成・更新します。書き出しダイアログ（Project > Export）を開いている場合は、閉じて開き直すと新しいプリセットが表示されます（エディタはプリセットをメモリに保持しているため）。"
const FREEZE_TEXT := "書き出し中はエディタが固まったように見えますが、終わるまでそのままお待ちください。"

enum Mode { CHECK, EXPORT, DONE }

var mode := Mode.CHECK
var dialog: AcceptDialog
var file_dialog: EditorFileDialog
var note_label: Label
var mobile_check: CheckBox
var dir_edit: LineEdit
var rows_scroll: ScrollContainer
var rows_grid: GridContainer
var result_label: Label
var apply_button: Button


func _ready() -> void:
	dialog = AcceptDialog.new()
	dialog.min_size = DIALOG_SIZE
	dialog.confirmed.connect(_on_confirmed)
	dialog.custom_action.connect(_on_custom_action)
	add_child(dialog)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)
	note_label = _wrapped_label()
	box.add_child(note_label)
	mobile_check = CheckBox.new()
	mobile_check.text = MOBILE_TEXT
	mobile_check.button_pressed = true
	mobile_check.toggled.connect(_on_mobile_toggled)
	box.add_child(mobile_check)
	box.add_child(_build_dir_row())
	rows_scroll = ScrollContainer.new()
	rows_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows_scroll.custom_minimum_size = Vector2(0, 260)
	box.add_child(rows_scroll)
	rows_grid = GridContainer.new()
	rows_grid.columns = 4
	rows_grid.add_theme_constant_override("h_separation", 16)
	rows_scroll.add_child(rows_grid)
	result_label = _wrapped_label()
	box.add_child(result_label)
	apply_button = dialog.add_button("推奨を適用", false, APPLY_ACTION)
	file_dialog = EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	file_dialog.title = "書き出し先フォルダを選ぶ"
	file_dialog.dir_selected.connect(_on_dir_selected)
	add_child(file_dialog)


func show_check() -> void:
	_set_mode(Mode.CHECK)
	result_label.text = ""
	_refresh_rows()
	dialog.popup_centered(DIALOG_SIZE)


func show_export() -> void:
	_set_mode(Mode.EXPORT)
	result_label.text = ""
	dialog.popup_centered(DIALOG_SIZE)


func _build_dir_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = "書き出し先"
	row.add_child(caption)
	dir_edit = LineEdit.new()
	dir_edit.text = _remembered_dir()
	dir_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dir_edit)
	var browse := Button.new()
	browse.text = "参照…"
	browse.pressed.connect(_on_browse_pressed)
	row.add_child(browse)
	return row


func _wrapped_label() -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(DIALOG_SIZE.x - 40, 0)
	return label


func _set_mode(next: Mode) -> void:
	mode = next
	var exporting := mode == Mode.EXPORT
	dialog.title = "GameRush: 書き出し設定を確認" if mode == Mode.CHECK else "GameRush: 推奨設定で書き出す"
	dialog.ok_button_text = "書き出す" if exporting else "閉じる"
	dialog.dialog_hide_on_ok = not exporting
	dialog.get_ok_button().disabled = false
	note_label.text = NOTE_TEXT + ("\n" + FREEZE_TEXT if exporting else "")
	apply_button.visible = mode == Mode.CHECK
	rows_scroll.visible = mode == Mode.CHECK
	mobile_check.disabled = mode == Mode.DONE


func _refresh_rows() -> void:
	for child: Node in rows_grid.get_children():
		rows_grid.remove_child(child)
		child.queue_free()
	for heading: String in ["", "項目", "現在", "推奨"]:
		_add_cell(heading, Color.WHITE)
	var config := ConfigFile.new()
	if FileAccess.file_exists(Settings.PRESETS_PATH):
		config.load(Settings.PRESETS_PATH)
	for row: Dictionary in Settings.compare(config, mobile_check.button_pressed):
		var ok := bool(row["ok"])
		_add_cell("✓" if ok else "✗", OK_COLOR if ok else NG_COLOR)
		_add_cell(str(row["label"]), Color.WHITE)
		_add_cell(str(row["current"]), Color.WHITE)
		_add_cell(str(row["recommended"]), Color.WHITE)


func _add_cell(text: String, color: Color) -> void:
	var cell := Label.new()
	cell.text = text
	cell.modulate = color
	rows_grid.add_child(cell)


func _on_mobile_toggled(_pressed: bool) -> void:
	if mode == Mode.CHECK:
		_refresh_rows()


func _on_browse_pressed() -> void:
	var absolute := Settings.absolute_dir(dir_edit.text)
	if not absolute.is_empty() and DirAccess.dir_exists_absolute(absolute):
		file_dialog.current_dir = absolute
	else:
		file_dialog.current_dir = Settings.project_root()
	file_dialog.popup_centered_ratio(0.6)


func _on_dir_selected(dir: String) -> void:
	var absolute := Settings.absolute_dir(dir)
	dir_edit.text = Settings.project_relative(absolute) if Settings.is_inside_project(absolute) else absolute
	_remember_dir(dir_edit.text)


func _on_custom_action(action: StringName) -> void:
	if action != APPLY_ACTION:
		return
	_remember_dir(dir_edit.text)
	var preset := Preset.ensure(dir_edit.text, mobile_check.button_pressed)
	result_label.text = _describe_preset(preset)
	_refresh_rows()


func _on_confirmed() -> void:
	if mode == Mode.EXPORT:
		_export()


func _export() -> void:
	dialog.get_ok_button().disabled = true
	result_label.text = "書き出し中…"
	await get_tree().process_frame
	await get_tree().process_frame
	var output_dir := dir_edit.text
	_remember_dir(output_dir)
	var preset := Preset.ensure(output_dir, mobile_check.button_pressed)
	var lines := PackedStringArray([_describe_preset(preset)])
	if preset["ok"]:
		lines.append(_describe_export(Export.run(output_dir)))
	_set_mode(Mode.DONE)
	result_label.text = "\n".join(lines)


func _describe_preset(preset: Dictionary) -> String:
	if not preset["ok"]:
		return "プリセットを書けませんでした: " + str(preset["error"])
	var changes: Array = preset["changes"]
	var lines := PackedStringArray()
	if changes.is_empty():
		lines.append("プリセット「%s」は推奨設定のままです。" % Settings.PRESET_NAME)
	else:
		lines.append("プリセット「%s」の %d 項目を推奨設定にしました。" % [Settings.PRESET_NAME, changes.size()])
	if preset.get("reimport", false):
		lines.append("ETC2/ASTC を有効にしたため、テクスチャが再インポートされます。")
	return "\n".join(lines)


func _describe_export(result: Dictionary) -> String:
	var lines := PackedStringArray([str(result["message"])])
	for warning: String in result["warnings"]:
		lines.append("警告: " + warning)
	if int(result["code"]) == Export.CODE_EXPORT_FAILED:
		var log_lines := str(result["log"]).strip_edges().split("\n", false)
		var start := maxi(0, log_lines.size() - LOG_TAIL_LINES)
		lines.append("\n".join(log_lines.slice(start)))
	return "\n".join(lines)


func _remembered_dir() -> String:
	var settings := EditorInterface.get_editor_settings()
	return str(settings.get_project_metadata(METADATA_SECTION, METADATA_KEY, Settings.DEFAULT_OUTPUT_DIR))


func _remember_dir(dir: String) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(METADATA_SECTION, METADATA_KEY, dir.strip_edges())
