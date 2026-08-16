extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")
const Room := preload("res://addons/grush_sdk/grush_room.gd")

var room: GRushRoom = null

var _grush: Node
var _backend: RefCounted
var _bound := false


func _init(grush: Node, backend: RefCounted) -> void:
	_grush = grush
	_backend = backend


func join(mode := "default", room_code := "") -> Dictionary:
	if not _grush.is_available():
		return Result.unsupported()
	_bind()
	var previous := room
	room = null
	if previous != null:
		previous.close_locally("replaced")
	var params := {"mode": mode}
	if room_code != "":
		params["roomCode"] = room_code
	var pending := Call.new()
	_backend.call_api("net.join", params, func(result: Dictionary) -> void: pending.resolve(result))
	var response: Dictionary = await pending.completed
	if not response["ok"]:
		return response
	var info: Variant = response["value"]
	if not (info is Dictionary) or str(info.get("roomId", "")) == "":
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable room.")
	room = Room.new(_grush, _backend, self, info)
	return Result.ok(room)


func forget(closed_room: GRushRoom) -> void:
	if room == closed_room:
		room = null


func dispose() -> void:
	if _backend != null and _bound:
		_backend.set_net_event_handler(Callable())
	room = null
	_backend = null
	_grush = null
	_bound = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	_backend.set_net_event_handler(func(event: Dictionary) -> void: _on_event(event))


func _on_event(event: Dictionary) -> void:
	if room != null:
		room.apply(event)
