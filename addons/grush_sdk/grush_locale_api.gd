extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

const LOCALE_PROTOCOL_VERSION := 4

signal changed(info: Dictionary)

var _grush: Node
var _transport: RefCounted
var _disposed := false


func _init(grush: Node, transport: RefCounted) -> void:
	_grush = grush
	_transport = transport
	if _supported():
		_transport.watch(func(info: Dictionary) -> void: _on_changed(info))


func fetch() -> Dictionary:
	if not _supported():
		return Result.unsupported()
	var pending := Call.new()
	_transport.fetch(func(result: Dictionary) -> void: pending.resolve(result))
	return await pending.completed


func current() -> Variant:
	if not _supported():
		return null
	return _transport.current()


func dispose() -> void:
	_disposed = true
	if _transport != null:
		_transport.dispose()
	_transport = null
	_grush = null


func _on_changed(info: Dictionary) -> void:
	_emit_changed.call_deferred(info)


func _emit_changed(info: Dictionary) -> void:
	if not _disposed:
		changed.emit(info)


func _supported() -> bool:
	return (
		not _disposed
		and _transport != null
		and _grush.is_available()
		and _grush.protocol_version() >= LOCALE_PROTOCOL_VERSION
	)
