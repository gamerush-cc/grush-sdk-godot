extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")

var _pending: Dictionary = {}
var _next_token := 1
var _watch_callback: JavaScriptObject = null
var _watch_id := 0

const SHIM_JS := """
(function () {
  if (window.__grushLocaleShim) return;
  var subscriptions = {};
  var nextId = 1;
  function api() {
    return window.GRushLocale || window.GameRushLocale;
  }
  window.__grushLocaleShim = {
    fetch: function () {
      var locale = api();
      return locale ? locale.get() : null;
    },
    watch: function (handler) {
      var locale = api();
      if (!locale) return 0;
      var id = nextId++;
      subscriptions[id] = locale.onChange(handler);
      return id;
    },
    unwatch: function (id) {
      var off = subscriptions[id];
      delete subscriptions[id];
      if (typeof off === "function") off();
    }
  };
})();
"""

static var _shim_installed := false


static func _api() -> JavaScriptObject:
	var api := JavaScriptBridge.get_interface("GRushLocale")
	if api == null:
		api = JavaScriptBridge.get_interface("GameRushLocale")
	return api


static func snapshot_of(value: Variant) -> Variant:
	var json := JavaScriptBridge.get_interface("JSON")
	if value == null or json == null:
		return null
	var parsed: Variant = JSON.parse_string(str(json.stringify(value)))
	if not (parsed is Dictionary) or str(parsed.get("locale", "")) == "":
		return null
	var languages := PackedStringArray()
	var raw: Variant = parsed.get("languages")
	if raw is Array:
		for tag in raw:
			languages.append(str(tag))
	return {"locale": str(parsed["locale"]), "source": str(parsed.get("source", "")), "languages": languages}


static func _shim() -> JavaScriptObject:
	if not _shim_installed:
		JavaScriptBridge.eval(SHIM_JS, true)
		_shim_installed = true
	return JavaScriptBridge.get_interface("__grushLocaleShim")


func current() -> Variant:
	var api := _api()
	if api == null:
		return null
	return snapshot_of(api.current())


func fetch(on_done: Callable) -> void:
	var api := _api()
	var promise: Variant = _shim().fetch() if api != null else null
	if promise == null:
		on_done.call_deferred(Result.unsupported())
		return
	var token := _next_token
	_next_token += 1
	var on_ok := JavaScriptBridge.create_callback(
		func(args: Array) -> void: _settle(token, on_done, true, args)
	)
	var on_error := JavaScriptBridge.create_callback(
		func(args: Array) -> void: _settle(token, on_done, false, args)
	)
	_pending[token] = [on_ok, on_error]
	promise.then(on_ok, on_error)


func watch(handler: Callable) -> void:
	var api := _api()
	if api == null or _watch_callback != null:
		return
	_watch_callback = JavaScriptBridge.create_callback(
		func(args: Array) -> void: _on_watch(handler, args)
	)
	_watch_id = int(_shim().watch(_watch_callback))


func dispose() -> void:
	if _watch_id != 0:
		_shim().unwatch(_watch_id)
		_watch_id = 0
	_watch_callback = null


func _on_watch(handler: Callable, args: Array) -> void:
	var info: Variant = snapshot_of(args[0]) if args.size() > 0 else null
	if info != null:
		handler.call(info)


func _settle(token: int, on_done: Callable, ok: bool, args: Array) -> void:
	_forget_pending.call_deferred(token)
	var value: Variant = args[0] if args.size() > 0 else null
	if not ok:
		on_done.call(Result.failure(_code_of(value), _message_of(value)))
		return
	var info: Variant = snapshot_of(value)
	if info == null:
		on_done.call(Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable locale."))
		return
	on_done.call(Result.ok(info))


func _forget_pending(token: int) -> void:
	_pending.erase(token)


static func _code_of(error: Variant) -> String:
	if error == null or error["code"] == null:
		return Result.CODE_INTERNAL
	return Result.map_code(str(error["code"]))


static func _message_of(error: Variant) -> String:
	if error == null or error["message"] == null:
		return "GameRush API call failed."
	return str(error["message"])
