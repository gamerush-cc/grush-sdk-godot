class_name GRushMockLeaderboards
extends RefCounted

## エディタ用のランキング。作者が実サーバへ繋がずに投稿と表示を試せないと
## ランキングを組み込んだゲームを一切テストできないため、モックは付属品では
## なく本体の一部として扱う。
##
## 実サーバ側の縛り（値域・集約・自己申告であること）は同じ形で再現する。
## session 束縛と有効プレイ 10 秒はエディタでは意味を持たないので省く。

static var _boards: Dictionary = {}


## エディタで使うランキング枠を宣言する。実環境では Studio が持つ役割。
static func define(
	key: String,
	title: String = "",
	sort: String = "desc",
	value_type: String = "int",
	aggregation: String = "best",
	min_value: float = 0.0,
	max_value: float = 1000000.0
) -> void:
	_boards[key] = {
		"key": key,
		"title": title if title != "" else key,
		"sort": sort,
		"value_type": value_type,
		"aggregation": aggregation,
		"period": "all_time",
		"min_value": min_value,
		"max_value": max_value,
		"entries": [],
	}


## 他プレイヤーの行を積む。順位表示や同意の出し分けの確認に使う。
static func add_rival(
	key: String,
	display_name: String,
	value: float,
	avatar_url: Variant = null,
	is_guest: bool = false
) -> void:
	var board := _ensure(key)
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


static func reset() -> void:
	_boards.clear()


static func _ensure(key: String) -> Dictionary:
	if not _boards.has(key):
		define(key)
	return _boards[key]


static func list_wire() -> Dictionary:
	var boards: Array = []
	for key in _boards:
		var board: Dictionary = _boards[key]
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
	if not _boards.has(key):
		return {"error": "unknown", "message": "No mock leaderboard named %s." % key}
	var board: Dictionary = _boards[key]
	if value < float(board["min_value"]) or value > float(board["max_value"]):
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
	if not _boards.has(key):
		return {"error": "unknown", "message": "No mock leaderboard named %s." % key}
	var board: Dictionary = _boards[key]
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
			"periodKey": "",
			"verified": false,
			"entries": wire,
			"total": total,
		}
	}
