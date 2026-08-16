extends Node

const REQUIRED_PROTOCOL_VERSION := 1
const MAX_MESSAGE_BYTES := 8192
const EVERYONE := -1

const CHANNEL_RELIABLE := "reliable"
const CHANNEL_UNRELIABLE := "unreliable"

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const WebBackend := preload("res://addons/grush_sdk/grush_backend_web.gd")
const MockBackend := preload("res://addons/grush_sdk/grush_backend_mock.gd")
const PlayerApi := preload("res://addons/grush_sdk/grush_player_api.gd")
const NetApi := preload("res://addons/grush_sdk/grush_net_api.gd")

var backend: RefCounted
var player: RefCounted
var net: RefCounted


func _ready() -> void:
	use_backend(null)


func _exit_tree() -> void:
	_dispose()


func use_backend(replacement: RefCounted) -> void:
	_dispose()
	backend = replacement if replacement != null else _create_backend()
	player = PlayerApi.new(self, backend)
	net = NetApi.new(self, backend)


func _dispose() -> void:
	if net != null:
		net.dispose()
	backend = null
	player = null
	net = null


func is_available() -> bool:
	if backend == null:
		return false
	return backend.is_available() and backend.protocol_version() >= REQUIRED_PROTOCOL_VERSION


func protocol_version() -> int:
	return 0 if backend == null else backend.protocol_version()


func mock_add_peer(display_name: String) -> RefCounted:
	if backend == null or not backend.has_method("add_peer"):
		return null
	return backend.add_peer(display_name)


func mock_remove_peer(peer: RefCounted) -> void:
	if backend != null and backend.has_method("remove_peer"):
		backend.remove_peer(peer)


func _create_backend() -> RefCounted:
	if WebBackend.is_present():
		return WebBackend.new()
	return MockBackend.new()
