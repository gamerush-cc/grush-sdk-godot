extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const MockPeer := preload("res://addons/grush_sdk/grush_mock_peer.gd")

const STATE_PATH := "user://grush_sdk_mock.cfg"
const STATE_SECTION := "mock"

var _members: Array = []
var _outgoing_seq: Dictionary = {}
var _local_index := -1
var _consented := false
var _room_code := ""
var _net_handler := Callable()
var _random := RandomNumberGenerator.new()


func _init() -> void:
	_random.seed = 20260816
	_consented = bool(_state().get_value(STATE_SECTION, "consent", false))


func is_available() -> bool:
	return true


func protocol_version() -> int:
	return 1


func set_net_event_handler(handler: Callable) -> void:
	_net_handler = handler


func call_api(method: String, params: Dictionary, on_done: Callable) -> void:
	on_done.call_deferred(_handle(method, params))


func send(payload: PackedByteArray, channel: String, to: int) -> void:
	if _local_index < 0:
		return
	route(_local_index, payload, channel, to)


func add_peer(display_name: String) -> RefCounted:
	var peer := MockPeer.new(self)
	peer.index = _next_free_index()
	peer.pseudo_id = "mock-peer-%d" % peer.index
	peer.display_name = display_name
	_members.append({"index": peer.index, "peer": peer})
	_members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["index"] < b["index"])
	_announce("peerjoin", peer.index, _peer_wire(peer.index))
	return peer


func remove_peer(peer: RefCounted) -> void:
	if peer == null:
		return
	_members = _members.filter(func(entry: Dictionary) -> bool: return entry.get("peer") != peer)
	_outgoing_seq.erase(peer.index)
	_announce("peerleave", peer.index, {})


func route(from: int, payload: PackedByteArray, channel: String, to: int) -> void:
	if channel == "unreliable" and _random.randf() < GRushMock.unreliable_drop_rate:
		return
	var seq := int(_outgoing_seq.get(from, 0)) + 1
	_outgoing_seq[from] = seq
	for entry in _members.duplicate():
		var index := int(entry["index"])
		if index == from or (to != -1 and index != to):
			continue
		var message := {
			"kind": "message",
			"from": from,
			"channel": channel,
			"seq": seq,
			"payload": payload.duplicate(),
		}
		var peer: Variant = entry.get("peer")
		if peer != null:
			peer.deliver.call_deferred(message)
		else:
			_deliver_local.call_deferred(message)


func _handle(method: String, params: Dictionary) -> Dictionary:
	match method:
		"player.getSelf":
			return Result.ok(_player_wire(_consented))
		"player.requestProfile":
			return _request_profile()
		"player.revokeProfile":
			_set_consent(false)
			return Result.ok(_player_wire(false))
		"net.join":
			return Result.ok(_join(params))
		"net.leave":
			_leave()
			return Result.ok(null)
	return Result.failure(
		Result.CODE_UNSUPPORTED, "The mock backend does not implement %s." % method
	)


func _request_profile() -> Dictionary:
	if not GRushMock.signed_in:
		return Result.failure(
			Result.CODE_SIGN_IN_REQUIRED, "The player is a guest and has no profile."
		)
	if not GRushMock.grant_profile_consent:
		return Result.failure(
			Result.CODE_CONSENT_DECLINED, "The player declined to share their profile."
		)
	_set_consent(true)
	return Result.ok(_player_wire(true))


func _set_consent(value: bool) -> void:
	_consented = value
	var config := _state()
	config.set_value(STATE_SECTION, "consent", value)
	config.save(STATE_PATH)


func _join(params: Dictionary) -> Dictionary:
	if _room_code == "":
		_room_code = str(params.get("roomCode", "MOCKROOM"))
	var existing: Array = []
	for entry in _members:
		existing.append(_peer_wire(int(entry["index"])))
	_local_index = _next_free_index()
	_members.append({"index": _local_index, "peer": null})
	_members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["index"] < b["index"])
	_announce("peerjoin", _local_index, _peer_wire(_local_index))
	return {
		"roomId": "mock:%s:%s" % [str(params.get("mode", "default")), _room_code],
		"roomCode": _room_code,
		"localPeerIndex": _local_index,
		"peers": existing,
		"hostIndex": _host_index(),
		"epoch": 1,
		"transport": "ws",
		"serverTimeMs": Time.get_unix_time_from_system() * 1000.0,
	}


func _leave() -> void:
	if _local_index < 0:
		return
	var leaving := _local_index
	_members = _members.filter(func(entry: Dictionary) -> bool: return entry["index"] != leaving)
	_outgoing_seq.erase(leaving)
	_local_index = -1
	_announce("peerleave", leaving, {})


func _announce(kind: String, subject: int, peer: Dictionary) -> void:
	for entry in _members.duplicate():
		if entry.get("peer") != null or int(entry["index"]) == subject:
			continue
		var event := {"kind": kind}
		if kind == "peerjoin":
			event["peer"] = peer
		else:
			event["index"] = subject
		_deliver_local.call_deferred(event)


func _deliver_local(event: Dictionary) -> void:
	if _net_handler.is_valid():
		_net_handler.call(event)


func _next_free_index() -> int:
	for index in range(GRushMock.max_peers):
		var taken := _members.filter(
			func(entry: Dictionary) -> bool: return int(entry["index"]) == index
		)
		if taken.is_empty():
			return index
	return GRushMock.max_peers - 1


func _host_index() -> int:
	var host := GRushMock.max_peers
	for entry in _members:
		host = min(host, int(entry["index"]))
	return 0 if host == GRushMock.max_peers else host


func _peer_wire(index: int) -> Dictionary:
	for entry in _members:
		if int(entry["index"]) != index:
			continue
		var peer: Variant = entry.get("peer")
		if peer != null:
			return {"index": index, "pseudoId": peer.pseudo_id, "displayName": peer.display_name}
		return {
			"index": index,
			"pseudoId": _local_pseudo_id(),
			"displayName": GRushMock.display_name if _consented else null,
		}
	return {"index": index, "pseudoId": "", "displayName": null}


func _player_wire(consented: bool) -> Dictionary:
	return {
		"pseudoId": _local_pseudo_id(),
		"isGuest": not GRushMock.signed_in,
		"profileConsent": consented and GRushMock.signed_in,
		"profile": {"displayName": GRushMock.display_name, "avatarUrl": GRushMock.avatar_url},
	}


static func _state() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(STATE_PATH)
	return config


static func _local_pseudo_id() -> String:
	var config := _state()
	var stored := str(config.get_value(STATE_SECTION, "pseudo_id", ""))
	if stored != "":
		return stored
	var created := "mock-local-" + str(randi()) + str(randi())
	config.set_value(STATE_SECTION, "pseudo_id", created)
	config.save(STATE_PATH)
	return created
