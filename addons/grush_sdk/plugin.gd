@tool
extends EditorPlugin

const AUTOLOAD_NAME := "GRush"
const AUTOLOAD_PATH := "res://addons/grush_sdk/grush.gd"
const ExportPlugin := preload("res://addons/grush_sdk/grush_export_plugin.gd")

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	_export_plugin = ExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null
	remove_autoload_singleton(AUTOLOAD_NAME)
