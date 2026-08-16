extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")

var _room: JavaScriptObject = null
var _room_callbacks: Array = []
var _retired_callbacks: Array = []
var _pending: Dictionary = {}
var _next_token := 1
var _net_handler := Callable()


static func is_present() -> bool:
	if not OS.has_feature("web"):
		return false
	return (
		JavaScriptBridge.get_interface("GRushInfo") != null
		and JavaScriptBridge.get_interface("GRushNet") != null
		and JavaScriptBridge.get_interface("GRushPlayer") != null
	)


func is_available() -> bool:
	return is_present()


func protocol_version() -> int:
	var info := JavaScriptBridge.get_interface("GRushInfo")
	if info == null:
		return 0
	var version: Variant = info.protocolVersion
	return int(version) if version != null else 0


func set_net_event_handler(handler: Callable) -> void:
	_net_handler = handler


func call_api(method: String, params: Dictionary, on_done: Callable) -> void:
	if method == "net.leave" and _room == null:
		on_done.call_deferred(Result.ok(null))
		return
	var promise: Variant = _invoke(method, params)
	if promise == null:
		on_done.call_deferred(
			Result.failure(Result.CODE_UNSUPPORTED, "GameRush does not expose %s here." % method)
		)
		return
	var token := _next_token
	_next_token += 1
	var on_ok := JavaScriptBridge.create_callback(
		func(args: Array) -> void: _settle(token, method, on_done, true, args)
	)
	var on_error := JavaScriptBridge.create_callback(
		func(args: Array) -> void: _settle(token, method, on_done, false, args)
	)
	_pending[token] = [on_ok, on_error]
	promise.then(on_ok, on_error)


func send(payload: PackedByteArray, channel: String, to: int) -> void:
	if _room == null:
		return
	var options := JavaScriptBridge.create_object("Object")
	options.channel = channel
	options.to = to
	_room.sendBase64(Marshalls.raw_to_base64(payload), options)


func _invoke(method: String, params: Dictionary) -> Variant:
	var player := JavaScriptBridge.get_interface("GRushPlayer")
	var net := JavaScriptBridge.get_interface("GRushNet")
	match method:
		"player.getSelf":
			return player.getSelf() if player != null else null
		"player.requestProfile":
			return player.requestProfile() if player != null else null
		"player.revokeProfile":
			return player.revokeProfile() if player != null else null
		"net.join":
			if net == null:
				return null
			return net.join(_to_js(params))
		"net.leave":
			var leaving := _room
			_release_room()
			return leaving.leave() if leaving != null else null
	return null


func _settle(token: int, method: String, on_done: Callable, ok: bool, args: Array) -> void:
	_forget_pending.call_deferred(token)
	var value: Variant = args[0] if args.size() > 0 else null
	if not ok:
		on_done.call(Result.failure(_code_of(value), _message_of(value)))
		return
	on_done.call(Result.ok(_value_of(method, value)))


func _value_of(method: String, value: Variant) -> Variant:
	if method == "net.join":
		return _bind_room(value)
	if method.begins_with("player."):
		return _player_of(value)
	return null


func _bind_room(room: Variant) -> Variant:
	_release_room()
	if room == null:
		return null
	_room = room
	_listen("message", func(args: Array) -> void: _emit(_message_of_js(args)))
	_listen(
		"peerjoin",
		func(args: Array) -> void: _emit({"kind": "peerjoin", "peer": _peer_of(args[0])})
	)
	_listen(
		"peerleave",
		func(args: Array) -> void: _emit({"kind": "peerleave", "index": int(args[0]["index"])})
	)
	_listen("host", func(args: Array) -> void: _emit({"kind": "host", "index": int(args[0]["index"])}))
	_listen(
		"transportchange",
		func(args: Array) -> void: _emit(
			{"kind": "transportchange", "transport": str(args[0]["transport"])}
		)
	)
	_listen("close", func(args: Array) -> void: _on_close(args))
	return JSON.parse_string(str(_room.describeJson()))


func _listen(event_name: String, handler: Callable) -> void:
	var callback := JavaScriptBridge.create_callback(handler)
	_room_callbacks.append(callback)
	_room.on(event_name, callback)


func _on_close(args: Array) -> void:
	var reason := ""
	if args.size() > 0 and args[0] != null and args[0]["reason"] != null:
		reason = str(args[0]["reason"])
	_emit({"kind": "close", "reason": reason})
	_release_room()


func _forget_pending(token: int) -> void:
	_pending.erase(token)


func _release_room() -> void:
	_room = null
	_retired_callbacks = _room_callbacks
	_room_callbacks = []


func _emit(event: Dictionary) -> void:
	if _net_handler.is_valid():
		_net_handler.call(event)


func _message_of_js(args: Array) -> Dictionary:
	var message: Variant = args[0]
	var payload := PackedByteArray()
	var raw: Variant = message["payload"]
	if raw != null and JavaScriptBridge.is_js_buffer(raw):
		payload = JavaScriptBridge.js_buffer_to_packed_byte_array(raw)
	return {
		"kind": "message",
		"from": int(message["from"]),
		"channel": str(message["channel"]),
		"seq": int(message["seq"]),
		"payload": payload,
	}


static func _peer_of(peer: Variant) -> Dictionary:
	if peer == null:
		return {}
	var display_name: Variant = peer["displayName"]
	var avatar_url: Variant = peer["avatarUrl"]
	return {
		"index": int(peer["index"]),
		"pseudoId": str(peer["pseudoId"]),
		"displayName": null if display_name == null else str(display_name),
		"avatarUrl": null if avatar_url == null else str(avatar_url),
	}


static func _player_of(player: Variant) -> Dictionary:
	if player == null:
		return {}
	var profile: Variant = player["profile"]
	var normalized := {
		"pseudoId": str(player["pseudoId"]),
		"isGuest": bool(player["isGuest"]),
		"profileConsent": bool(player["profileConsent"]),
	}
	if profile != null:
		normalized["profile"] = {
			"displayName": profile["displayName"],
			"avatarUrl": profile["avatarUrl"],
		}
	return normalized


static func _code_of(error: Variant) -> String:
	if error == null or error["code"] == null:
		return Result.CODE_INTERNAL
	return Result.map_code(str(error["code"]))


static func _message_of(error: Variant) -> String:
	if error == null or error["message"] == null:
		return "GameRush API call failed."
	return str(error["message"])


static func _to_js(params: Dictionary) -> JavaScriptObject:
	var object := JavaScriptBridge.create_object("Object")
	object.mode = params.get("mode", "default")
	if params.has("roomCode"):
		object.roomCode = params["roomCode"]
	return object
