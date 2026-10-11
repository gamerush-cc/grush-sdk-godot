class_name GRushMockLeaderboards
extends RefCounted

## エディタ用のランキング。作者が実サーバへ繋がずに投稿と表示を試せないと
## ランキングを組み込んだゲームを一切テストできないため、モックは付属品では
## なく本体の一部として扱う。
##
## 実サーバ側の縛り（値域・集約・自己申告であること）は同じ形で再現する。
## session 束縛と有効プレイ 10 秒はエディタでは意味を持たないので省く。
##
## プロジェクトの直下に [constant MANIFEST_PATH]（res://grush.json）があれば、最初の
## ランキングの呼び出しの前に読んで枠を宣言する。Web 書き出しでは同じファイルが
## index.html の隣へ写るので、アップロードと手元の確認で同じ定義を使える。

const Manifest := preload("res://addons/grush_sdk/grush_mock_manifest.gd")
const Result := preload("res://addons/grush_sdk/grush_result.gd")

## モックが読む、ランキングの定義のファイル。
const MANIFEST_PATH := "res://grush.json"

static var _boards: Dictionary = {}
static var _manifest_read := false


## エディタで使うランキング枠を宣言する。実環境では Studio か grush.json が持つ役割。
## [constant MANIFEST_PATH] を自動で読むときは、同じ key をこちらで宣言してあれば
## こちらを使う。[method load_manifest] に渡した定義は、こちらの宣言を置き換える。
## [param period] は [code]all_time[/code] / [code]daily[/code] / [code]weekly[/code] /
## [code]monthly[/code]。
## [param enabled] が false の枠は、宣言していない key と同じく投稿と取得が
## [code]invalidParams[/code] になる。
static func define(
	key: String,
	title: String = "",
	sort: String = "desc",
	value_type: String = "int",
	aggregation: String = "best",
	min_value: float = 0.0,
	max_value: float = 1000000.0,
	period: String = "all_time",
	enabled: bool = true
) -> void:
	_put(
		{
			"key": key,
			"title": title if title != "" else key,
			"sort": sort,
			"value_type": value_type,
			"aggregation": aggregation,
			"period": period if period != "" else "all_time",
			"min_value": min_value,
			"max_value": max_value,
			"enabled": enabled,
			"require_range": false,
		}
	)


## grush.json の中身（JSON の文字列）で枠を宣言し、宣言した key の配列を結果の
## [code]value[/code] に入れて返す。アップロードと同じ規則で読み、誤りは
## [code]invalidParams[/code] とアップロードと同じ文言で返す。同じ key を
## [method define] で宣言してあっても、こちらの定義で置き換える。これを呼ぶと、
## [constant MANIFEST_PATH] は自動では読まない。
static func load_manifest(json_text: String) -> Dictionary:
	_manifest_read = true
	var parsed := Manifest.parse(json_text)
	if parsed.has("error"):
		return Result.failure(Result.CODE_INVALID_PARAMS, str(parsed["error"]))
	return Result.ok(_apply(parsed["leaderboards"], false))


static func _apply(entries: Array, keep_defined: bool) -> Array:
	var defined: Array = []
	for entry in entries:
		if keep_defined and _boards.has(entry["key"]):
			continue
		var board: Dictionary = entry.duplicate()
		# GameRush は値域の無い枠への投稿を受けないので、grush.json の枠はそれに合わせる。
		board["require_range"] = true
		_put(board)
		defined.append(entry["key"])
	return defined


static func _put(board: Dictionary) -> void:
	board["period_key"] = period_key(str(board["period"]), int(Time.get_unix_time_from_system()))
	board["entries"] = []
	_boards[board["key"]] = board


# MANIFEST_PATH を一度だけ読む。無ければ何もしない。
static func _ensure_manifest() -> void:
	if _manifest_read:
		return
	_manifest_read = true
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	# 文字列で読むと、UTF-8 でないバイト列も通り、上限も文字数で測ることになる。GameRush と同じく
	# バイト列のまま確かめる。
	var parsed := Manifest.parse_bytes(FileAccess.get_file_as_bytes(MANIFEST_PATH))
	if parsed.has("error"):
		push_warning("[GRushMock] %s" % parsed["error"])
		return
	_apply(parsed["leaderboards"], true)


## GameRush と同じ期間キー（UTC）。daily は YYYY-MM-DD、weekly は ISO 週の YYYY-Www、
## monthly は YYYY-MM、all_time は空。
static func period_key(period: String, unix_time: int) -> String:
	var date := Time.get_datetime_dict_from_unix_time(unix_time)
	match period:
		"daily":
			return "%04d-%02d-%02d" % [date["year"], date["month"], date["day"]]
		"monthly":
			return "%04d-%02d" % [date["year"], date["month"]]
		"weekly":
			var day_number := floori(unix_time / 86400.0)
			var weekday: int = date["weekday"]
			var iso_weekday := 7 if weekday == 0 else weekday
			var thursday := day_number + 4 - iso_weekday
			var year: int = Time.get_datetime_dict_from_unix_time(thursday * 86400)["year"]
			var year_start := floori(
				Time.get_unix_time_from_datetime_dict({"year": year, "month": 1, "day": 1}) / 86400.0
			)
			return "%04d-W%02d" % [year, (thursday - year_start) / 7 + 1]
	return ""


static func _current(board: Dictionary) -> Dictionary:
	var key := period_key(str(board["period"]), int(Time.get_unix_time_from_system()))
	if key != board["period_key"]:
		board["period_key"] = key
		board["entries"] = []
	return board


# GameRush は宣言していない key と止めた枠を同じく 404 で返す。
static func _playable(key: String) -> Dictionary:
	_ensure_manifest()
	if not _boards.has(key):
		return {
			"error": "unknown",
			"message":
			"No mock leaderboard named %s. Declare it in grush.json or with GRushMockLeaderboards.define." % key,
		}
	var board: Dictionary = _boards[key]
	if not bool(board.get("enabled", true)):
		return {"error": "disabled", "message": "The mock leaderboard %s is disabled." % key}
	return {"board": _current(board)}


## 他プレイヤーの行を積む。順位表示や同意の出し分けの確認に使う。
static func add_rival(
	key: String,
	display_name: String,
	value: float,
	avatar_url: Variant = null,
	is_guest: bool = false
) -> void:
	var board := _current(_ensure(key))
	board["entries"].append(
		{
			"pseudoId": "mock-rival-%d" % randi(),
			"displayName": null if is_guest else display_name,
			"avatarUrl": null if is_guest else avatar_url,
			"isGuest": is_guest,
			"value": value,
			"isSelf": false,
		}
	)


## 宣言した枠をすべて消す。次のランキングの呼び出しで、grush.json を読み直す。
static func reset() -> void:
	_boards.clear()
	_manifest_read = false


static func _ensure(key: String) -> Dictionary:
	_ensure_manifest()
	if not _boards.has(key):
		define(key)
	return _boards[key]


static func list_wire() -> Dictionary:
	_ensure_manifest()
	var boards: Array = []
	for key in _boards:
		var board: Dictionary = _boards[key]
		if not bool(board.get("enabled", true)):
			continue
		boards.append(
			{
				"key": board["key"],
				"title": board["title"],
				"sort": board["sort"],
				"valueType": board["value_type"],
				"aggregation": board["aggregation"],
				"period": board["period"],
				"minValue": board["min_value"],
				"maxValue": board["max_value"],
			}
		)
	return {"leaderboards": boards}


static func submit(key: String, value: float, metadata: Variant, pseudo_id: String) -> Dictionary:
	var found := _playable(key)
	if found.has("error"):
		return found
	var board: Dictionary = found["board"]
	if board["require_range"] and board["min_value"] == null:
		return {
			"error": "range",
			"message": "This leaderboard declares no minValue / maxValue, so it accepts no score.",
		}
	var below: bool = board["min_value"] != null and value < float(board["min_value"])
	var above: bool = board["max_value"] != null and value > float(board["max_value"])
	if below or above:
		return {"error": "range", "message": "Score is outside the declared range."}

	var entries: Array = board["entries"]
	var self_entry: Variant = null
	for entry in entries:
		if bool(entry["isSelf"]):
			self_entry = entry
			break

	var updated := true
	if self_entry == null:
		self_entry = {
			"pseudoId": pseudo_id,
			"displayName": GRushMock.display_name,
			"avatarUrl": GRushMock.avatar_url,
			"isGuest": not GRushMock.signed_in,
			"value": value,
			"isSelf": true,
		}
		entries.append(self_entry)
	elif board["aggregation"] == "sum":
		self_entry["value"] = float(self_entry["value"]) + value
	elif board["aggregation"] == "best":
		var better := (
			value > float(self_entry["value"])
			if board["sort"] == "desc"
			else value < float(self_entry["value"])
		)
		if better:
			self_entry["value"] = value
		else:
			updated = false
	else:
		self_entry["value"] = value

	if metadata != null:
		self_entry["metadata"] = metadata

	var ranked := _ranked(board)
	var rank := 0
	for index in ranked.size():
		if bool(ranked[index]["isSelf"]):
			rank = index + 1
			break

	return {
		"result":
		{
			"accepted": true,
			"updated": updated,
			"value": float(self_entry["value"]),
			"rank": rank,
			"verified": false,
		}
	}


static func page(key: String, window: int, offset: int, around_me: bool) -> Dictionary:
	var found := _playable(key)
	if found.has("error"):
		return found
	var board: Dictionary = found["board"]
	var ranked := _ranked(board)

	var start := offset
	var count := window if window > 0 else 20

	if around_me:
		var self_index := -1
		for index in ranked.size():
			if bool(ranked[index]["isSelf"]):
				self_index = index
				break
		if self_index < 0:
			# 自分がまだ載っていないときは空。先頭を返すと「1位」と読める。
			return _page_wire(board, [], 0, ranked.size())
		var window_size := window if window > 0 else 5
		start = max(0, self_index - window_size)
		count = window_size * 2 + 1

	var slice: Array = []
	var cursor := start
	while cursor < ranked.size() and slice.size() < count:
		slice.append(ranked[cursor])
		cursor += 1
	return _page_wire(board, slice, start, ranked.size())


static func _ranked(board: Dictionary) -> Array:
	var ranked: Array = board["entries"].duplicate()
	var descending: bool = board["sort"] != "asc"
	ranked.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				float(a["value"]) > float(b["value"])
				if descending
				else float(a["value"]) < float(b["value"])
			)
	)
	return ranked


static func _page_wire(board: Dictionary, entries: Array, start: int, total: int) -> Dictionary:
	var wire: Array = []
	for index in entries.size():
		var entry: Dictionary = entries[index]
		wire.append(
			{
				"rank": start + index + 1,
				"pseudoId": entry["pseudoId"],
				"displayName": entry["displayName"],
				"avatarUrl": entry["avatarUrl"],
				"isGuest": entry["isGuest"],
				"value": float(entry["value"]),
				"metadata": entry.get("metadata", null),
				"submittedAt": "",
				"isSelf": entry["isSelf"],
			}
		)
	return {
		"leaderboard":
		{
			"key": board["key"],
			"title": board["title"],
			"sort": board["sort"],
			"valueType": board["value_type"],
			"period": board["period"],
			"periodKey": board["period_key"],
			"verified": false,
			"entries": wire,
			"total": total,
		}
	}
