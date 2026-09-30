extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")


func current() -> Variant:
	var device := OS.get_locale().replace("_", "-")
	var tag := GRushMock.locale
	if tag == "":
		return {"locale": device, "source": "device", "languages": PackedStringArray([device])}
	var languages := PackedStringArray([tag])
	if device != tag:
		languages.append(device)
	return {"locale": tag, "source": "user", "languages": languages}


func fetch(on_done: Callable) -> void:
	on_done.call_deferred(Result.ok(current()))


func watch(_handler: Callable) -> void:
	pass


func dispose() -> void:
	pass
