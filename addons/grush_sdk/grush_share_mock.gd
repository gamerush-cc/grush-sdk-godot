extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")


func call_api(method: String, params: Dictionary, on_done: Callable) -> void:
	on_done.call_deferred(_handle(method, params))


func _handle(method: String, params: Dictionary) -> Dictionary:
	if method == "share.getAvailability":
		return Result.ok(GRushMock.share_available)
	if not GRushMock.share_available:
		return Result.failure(Result.CODE_UNAVAILABLE, "Sharing is unavailable here.")
	print("[GRushMock] share text=%s image=%s" % [params.get("text", ""), _describe(params.get("image"))])
	return Result.ok(GRushMock.share_status)


static func _describe(image: Variant) -> String:
	if image is Dictionary:
		return "%s (%d base64 chars)" % [image.get("mimeType", ""), str(image.get("base64", "")).length()]
	return "none" if image == null else str(image)
