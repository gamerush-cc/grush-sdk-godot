extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")

var _pending: Dictionary = {}
var _next_token := 1


func call_api(method: String, params: Dictionary, on_done: Callable) -> void:
	var api := JavaScriptBridge.get_interface("GRushShare")
	var promise: Variant = null
	if api != null and method == "share.open":
		promise = api.share(_options_of(params))
	elif api != null and method == "share.getAvailability":
		promise = api.isAvailable()
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


func _settle(token: int, method: String, on_done: Callable, ok: bool, args: Array) -> void:
	_forget_pending.call_deferred(token)
	var value: Variant = args[0] if args.size() > 0 else null
	if not ok:
		on_done.call(Result.failure(_code_of(value), _message_of(value)))
		return
	if method == "share.getAvailability":
		on_done.call(Result.ok(value == true))
		return
	var status: Variant = value["status"] if value != null else null
	on_done.call(Result.ok("" if status == null else str(status)))


func _forget_pending(token: int) -> void:
	_pending.erase(token)


static func _options_of(params: Dictionary) -> JavaScriptObject:
	var options := JavaScriptBridge.create_object("Object")
	options.text = params.get("text", "")
	var image: Variant = params.get("image")
	if image is Dictionary:
		var encoded := JavaScriptBridge.create_object("Object")
		encoded.base64 = image["base64"]
		encoded.mimeType = image["mimeType"]
		options.image = encoded
	elif image != null:
		options.image = str(image)
	return options


static func _code_of(error: Variant) -> String:
	if error == null or error["code"] == null:
		return Result.CODE_INTERNAL
	return Result.map_code(str(error["code"]))


static func _message_of(error: Variant) -> String:
	if error == null or error["message"] == null:
		return "GameRush API call failed."
	return str(error["message"])
