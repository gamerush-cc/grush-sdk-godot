extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

const SHARE_PROTOCOL_VERSION := 3
const STATUS_OPENED := "opened"
const STATUS_CANCELLED := "cancelled"

var _grush: Node
var _transport: RefCounted


func _init(grush: Node, transport: RefCounted) -> void:
	_grush = grush
	_transport = transport


func share(text: String = "", image: Image = null) -> Dictionary:
	var params := {"text": text}
	if image != null:
		params["image"] = {
			"base64": Marshalls.raw_to_base64(image.save_png_to_buffer()),
			"mimeType": "image/png",
		}
	return await _open(params)


func share_screen(text: String = "") -> Dictionary:
	return await _open({"text": text, "image": "screen"})


func is_available() -> bool:
	if not _supported():
		return false
	var response := await _call("share.getAvailability", {})
	return response["ok"] and response["value"] == true


func _open(params: Dictionary) -> Dictionary:
	if not _supported():
		return Result.unsupported()
	var response := await _call("share.open", params)
	if not response["ok"]:
		return response
	var opened := str(response["value"]) == STATUS_OPENED
	return Result.ok({"status": STATUS_OPENED if opened else STATUS_CANCELLED})


func _supported() -> bool:
	return (
		_transport != null
		and _grush.is_available()
		and _grush.protocol_version() >= SHARE_PROTOCOL_VERSION
	)


func _call(method: String, params: Dictionary) -> Dictionary:
	var pending := Call.new()
	_transport.call_api(method, params, func(result: Dictionary) -> void: pending.resolve(result))
	return await pending.completed
