extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")


func current() -> Variant:
	var tag := GRushMock.locale
	var source := "user"
	if tag == "":
		tag = OS.get_locale().replace("_", "-")
		source = "device"
	return {"locale": tag, "source": source, "languages": PackedStringArray([tag])}


func fetch(on_done: Callable) -> void:
	on_done.call_deferred(Result.ok(current()))


func watch(_handler: Callable) -> void:
	pass


func dispose() -> void:
	pass
