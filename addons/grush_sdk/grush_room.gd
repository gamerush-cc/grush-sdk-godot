class_name GRushRoom
extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

signal message_received(message: Dictionary)
signal peer_joined(peer: Dictionary)
signal peer_left(index: int)
signal host_changed(index: int)
signal transport_changed(transport: String)
signal closed(reason: String)

var room_id := ""
var room_code := ""
var room_epoch := 0
var local_peer_id := 0
var host_peer_id := 0
var is_closed := false

var _peers: Array = []
var _transport := "ws"
var _server_offset_ms := 0.0
var _last_seq: Dictionary = {}
var _grush: Node
var _backend: RefCounted
var _net: RefCounted


func _init(grush: Node, backend: RefCounted, net: RefCounted, info: Dictionary) -> void:
	_grush = grush
	_backend = backend
	_net = net
	room_id = str(info.get("roomId", ""))
	room_code = str(info.get("roomCode", ""))
	room_epoch = int(info.get("epoch", 0))
	local_peer_id = int(info.get("localPeerIndex", 0))
	host_peer_id = int(info.get("hostIndex", 0))
	_transport = str(info.get("transport", "ws"))
	_server_offset_ms = float(info.get("serverTimeMs", 0.0)) - _local_now_ms()
	for entry in info.get("peers", []):
		if entry is Dictionary:
			_peers.append(_peer_of(entry))


func peers() -> Array:
	return _peers.duplicate()


func transport() -> String:
	return _transport


func is_host() -> bool:
	return host_peer_id == local_peer_id


func server_time_ms() -> int:
	return int(_local_now_ms() + _server_offset_ms)


func last_seq_from(peer_id: int) -> int:
	return int(_last_seq.get(peer_id, 0))


func send(
	payload: PackedByteArray, channel := "reliable", to := -1
) -> Dictionary:
	if is_closed:
		return Result.failure(Result.CODE_UNAVAILABLE, "The room is already closed.")
	if payload.size() > _grush.MAX_MESSAGE_BYTES:
		return Result.failure(Result.CODE_INVALID_PARAMS, "Payload exceeds the 8KB message limit.")
	_backend.send(payload, channel, to)
	return Result.ok(true)


func leave() -> Dictionary:
	if is_closed:
		return Result.ok(true)
	var pending := Call.new()
	_backend.call_api("net.leave", {}, func(result: Dictionary) -> void: pending.resolve(result))
	var response: Dictionary = await pending.completed
	_mark_closed("left")
	return response


func close_locally(reason: String) -> void:
	_mark_closed(reason)


func apply(event: Dictionary) -> void:
	match str(event.get("kind", "")):
		"message":
			_apply_message(event)
		"peerjoin":
			_apply_peer_join(event)
		"peerleave":
			var index := int(event.get("index", -1))
			_peers = _peers.filter(func(peer: Dictionary) -> bool: return peer["index"] != index)
			peer_left.emit(index)
		"host":
			host_peer_id = int(event.get("index", host_peer_id))
			host_changed.emit(host_peer_id)
		"transportchange":
			_transport = str(event.get("transport", _transport))
			transport_changed.emit(_transport)
		"close":
			_mark_closed(str(event.get("reason", "")))


func _apply_message(event: Dictionary) -> void:
	var from := int(event.get("from", -1))
	var seq := int(event.get("seq", 0))
	var previous := last_seq_from(from)
	_last_seq[from] = seq
	message_received.emit(
		{
			"from": from,
			"channel": str(event.get("channel", "reliable")),
			"seq": seq,
			"payload": event.get("payload", PackedByteArray()),
			"is_stale": seq != 0 and seq <= previous,
		}
	)


func _apply_peer_join(event: Dictionary) -> void:
	var raw: Variant = event.get("peer", null)
	if not (raw is Dictionary):
		return
	var peer := _peer_of(raw)
	_peers = _peers.filter(func(entry: Dictionary) -> bool: return entry["index"] != peer["index"])
	_peers.append(peer)
	peer_joined.emit(peer)


func _mark_closed(reason: String) -> void:
	if is_closed:
		return
	is_closed = true
	_peers.clear()
	if _net != null:
		_net.forget(self)
	closed.emit(reason)
	_net = null
	_backend = null
	_grush = null


static func _peer_of(raw: Dictionary) -> Dictionary:
	return {
		"index": int(raw.get("index", -1)),
		"pseudo_id": str(raw.get("pseudoId", raw.get("pseudo_id", ""))),
		"display_name": raw.get("displayName", raw.get("display_name", null)),
	}


static func _local_now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0
