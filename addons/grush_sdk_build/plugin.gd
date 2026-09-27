@tool
extends EditorPlugin

const BuildDialog := preload("res://addons/grush_sdk_build/grush_build_dialog.gd")

const CHECK_MENU := "GameRush: 書き出し設定を確認"
const EXPORT_MENU := "GameRush: 推奨設定で書き出す"

var build_dialog: BuildDialog


func _enter_tree() -> void:
	build_dialog = BuildDialog.new()
	EditorInterface.get_base_control().add_child(build_dialog)
	add_tool_menu_item(CHECK_MENU, build_dialog.show_check)
	add_tool_menu_item(EXPORT_MENU, build_dialog.show_export)


func _exit_tree() -> void:
	remove_tool_menu_item(CHECK_MENU)
	remove_tool_menu_item(EXPORT_MENU)
	if build_dialog != null:
		build_dialog.queue_free()
		build_dialog = null
