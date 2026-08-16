extends RefCounted

signal completed(result: Dictionary)


func resolve(result: Dictionary) -> void:
	completed.emit(result)
