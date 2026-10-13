extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")


func current() -> Variant:
	var params := {}
	for key in GRushMock.launch_params:
		var value: Variant = GRushMock.launch_params[key]
		if value is String:
			params[str(key)] = value
	return {"params": params}


func fetch(on_done: Callable) -> void:
	on_done.call_deferred(Result.ok(current()))
