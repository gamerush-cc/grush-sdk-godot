extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

const SHARE_PROTOCOL_VERSION := 3
## 共有に起動パラメータ（[method share] と [method share_screen] の launch_params）を添えられるランタイムの版数。
const SHARE_LAUNCH_PROTOCOL_VERSION := 9
const STATUS_OPENED := "opened"
const STATUS_CANCELLED := "cancelled"

var _grush: Node
var _transport: RefCounted


func _init(grush: Node, transport: RefCounted) -> void:
	_grush = grush
	_transport = transport


## 共有する。image は PNG にして送る。
##
## launch_params は共有リンクに添える起動パラメータ。受け取った人がリンクを開くと、ゲームの
## [code]GRush.launch[/code] に渡る（[code]{"stage": "3"}[/code] ならリンクに [code]?gp.stage=3[/code] が付く）。
## キーと値は String で、キーは英数字と [code]_-[/code] で 32 文字まで（[code]__proto__[/code] は使えない）、
## 値は英数字と [code]._~:,-[/code] で 128 文字まで（空も可）、8 個まで。1つでも合わなければ共有を開かずに
## invalidParams。空の Dictionary は渡さないときと同じ。
## ランタイムの版数が [constant SHARE_LAUNCH_PROTOCOL_VERSION] 未満なら、空でなければ共有を開かずに
## unsupported を返す。launch_params を外して呼び直せば共有できる。
##
## リンクは誰にでも見え、そのまま転送されるので、プレイヤーを識別できる値（招待コードなど）を入れない。
## 受け取る側のゲームは値を信用せず、確かめてから使う。
func share(text: String = "", image: Image = null, launch_params: Dictionary = {}) -> Dictionary:
	var params := {"text": text}
	if image != null:
		params["image"] = {
			"base64": Marshalls.raw_to_base64(image.save_png_to_buffer()),
			"mimeType": "image/png",
		}
	return await _open(params, launch_params)


## ゲームの canvas のスクショを添えて共有する。launch_params の規則と古いランタイムでの扱いは [method share] と同じ。
## リンクは誰にでも見え、そのまま転送されるので、プレイヤーを識別できる値（招待コードなど）を入れない。
func share_screen(text: String = "", launch_params: Dictionary = {}) -> Dictionary:
	return await _open({"text": text, "image": "screen"}, launch_params)


func is_available() -> bool:
	if not _supported():
		return false
	var response := await _call("share.getAvailability", {})
	return response["ok"] and response["value"] == true


func _open(params: Dictionary, launch_params: Dictionary) -> Dictionary:
	if not _supported():
		return Result.unsupported()
	if not launch_params.is_empty():
		# 古いランタイムは launchParams を読まずに共有を開くので、添えるときはそれを読む版数を求める。
		if _grush.protocol_version() < SHARE_LAUNCH_PROTOCOL_VERSION:
			return Result.unsupported()
		var strings: Variant = _string_params(launch_params)
		if strings == null:
			return Result.failure(Result.CODE_INVALID_PARAMS, "Launch params must map String to String.")
		params["launchParams"] = strings
	var response := await _call("share.open", params)
	if not response["ok"]:
		return response
	var opened := str(response["value"]) == STATUS_OPENED
	return Result.ok({"status": STATUS_OPENED if opened else STATUS_CANCELLED})


# キーと値の形は GameRush が確かめる。ここでは JavaScript へ写せる String どうしかだけを見る。
# 数値のキーを文字列に直して通すと、モックと GameRush で結果が分かれるため。
static func _string_params(launch_params: Dictionary) -> Variant:
	var strings := {}
	for key in launch_params:
		var value: Variant = launch_params[key]
		if not (key is String or key is StringName) or not (value is String or value is StringName):
			return null
		strings[str(key)] = str(value)
	return strings


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
