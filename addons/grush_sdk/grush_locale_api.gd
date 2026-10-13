extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

const LOCALE_PROTOCOL_VERSION := 4

signal changed(info: Dictionary)

var _grush: Node
var _transport: RefCounted
var _disposed := false
# use_transport のたびに増やす。差し替える前の受け取り口から call_deferred で積まれた通知を捨てるため。
var _generation := 0


func _init(grush: Node, transport: RefCounted) -> void:
	_grush = grush
	use_transport(transport)


## 言語の値の受け取り口を差し替える。changed への接続はそのまま、新しい受け取り口の通知が届く。
## GRush.use_backend が呼ぶ。
func use_transport(transport: RefCounted) -> void:
	if _transport != null:
		_transport.dispose()
	_transport = transport
	_generation += 1
	var generation := _generation
	if _supported():
		_transport.watch(func(info: Dictionary) -> void: _on_changed(generation, info))


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


func _on_changed(generation: int, info: Dictionary) -> void:
	_emit_changed.call_deferred(generation, info)


func _emit_changed(generation: int, info: Dictionary) -> void:
	if not _disposed and generation == _generation:
		changed.emit(info)


func _supported() -> bool:
	return (
		not _disposed
		and _transport != null
		and _grush.is_available()
		and _grush.protocol_version() >= LOCALE_PROTOCOL_VERSION
	)
