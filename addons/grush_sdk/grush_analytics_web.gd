extends RefCounted

# ランタイムの GRushAnalytics へ同期で渡す。params は JavaScript のオブジェクトに写して log(kind, params) に渡す。
# 確かめるのはランタイムで、ここでは値を見ない。


static func _api() -> JavaScriptObject:
	var api := JavaScriptBridge.get_interface("GRushAnalytics")
	if api == null:
		api = JavaScriptBridge.get_interface("GameRushAnalytics")
	return api


func is_available() -> bool:
	var api := _api()
	return api != null and api.isAvailable() == true


func log_event(kind: String, params: Dictionary) -> bool:
	var api := _api()
	if api == null:
		return false
	return api.log(kind, _object_of(params)) == true


# 入れ子は fields の1段だけ。キーは文字列にする（JavaScript のプロパティ名は文字列）。
static func _object_of(source: Dictionary) -> JavaScriptObject:
	var target := JavaScriptBridge.create_object("Object")
	for key in source:
		var value: Variant = source[key]
		target.set(str(key), _object_of(value) if value is Dictionary else value)
	return target
