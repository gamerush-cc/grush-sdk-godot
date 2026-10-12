extends RefCounted

## 受信箱。同じゲームの疑似 ID 宛てに、小さい構造化メッセージ（非同期対戦の結果の通知など）を
## 送り、受け取る。送信も受信もゲストができる。
##
## **payload で文章や画像は送れない。** payload は辞書で、文字列の値とキーは識別子
## （`^[A-Za-z0-9_.:-]{1,32}$`）だけ、ほかは数値・真偽値・null。入れ子は最上位を 1 段目として
## 4 段まで、値は合計 64 個まで、JSON にして 1KB まで。合わなければ invalidParams。
## 利用者どうしの文章や画像のやりとりには使わないこと。
##
## ランタイムの版数が [constant INBOX_PROTOCOL_VERSION] 未満なら、どの呼び出しも unsupported。

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

## 受信箱が使えるランタイムの版数。
const INBOX_PROTOCOL_VERSION := 7

var _grush: Node
var _backend: RefCounted


func _init(grush: Node, backend: RefCounted) -> void:
	_grush = grush
	_backend = backend


## [param to]（同じゲームの疑似 ID）へ送る。[param kind] は `^[A-Za-z0-9._:-]{1,32}$`。
## 送れたら value が true。
func send(to: String, kind: String, payload: Dictionary) -> Dictionary:
	var response := await _call("inbox.send", {"to": to, "kind": kind, "payload": payload})
	if not response["ok"]:
		return response
	return Result.ok(_flag(response["value"], "sent"))


## 受け取ったメッセージを新しい順に返す。[param options] は `unread_only`（bool）・
## `limit`（1〜50、既定 20）・`cursor`（前の結果の `next_cursor`）。value は
## `{"messages": Array, "unread_count": int, "next_cursor": String か null}`。
## メッセージは `{"id", "from", "kind", "payload", "created_at", "read_at"}`（未読の `read_at` は null）。
func list(options: Dictionary = {}) -> Dictionary:
	var params := {}
	if options.has("unread_only"):
		params["unreadOnly"] = bool(options["unread_only"])
	if options.has("limit"):
		params["limit"] = int(options["limit"])
	if options.get("cursor") != null:
		params["cursor"] = str(options["cursor"])
	var response := await _call("inbox.list", params)
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	if not (raw is Dictionary) or not (raw.get("messages") is Array):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable inbox.")
	var messages: Array = []
	for entry in raw["messages"]:
		if entry is Dictionary and str(entry.get("id", "")) != "":
			messages.append(message_of(entry))
	var next_cursor: Variant = raw.get("nextCursor")
	return Result.ok(
		{
			"messages": messages,
			"unread_count": int(raw.get("unreadCount", 0)),
			"next_cursor": null if next_cursor == null or str(next_cursor) == "" else str(next_cursor),
		}
	)


## 既読にし、value に更新した件数を返す（1 回 50 件まで）。
func mark_read(ids: Array) -> Dictionary:
	return _counted(await _call("inbox.markRead", {"ids": ids}), "updated")


## 消し、value に消した件数を返す（1 回 50 件まで）。
func remove(ids: Array) -> Dictionary:
	return _counted(await _call("inbox.remove", {"ids": ids}), "updated")


## メッセージを通報する。**ゲームは通報 UI を描けない。** 確認は GameRush が出し、
## プレイヤーが承諾したら value が true。通報すると送り手をブロックし、その相手のメッセージと
## 出品は見えなくなる。ゲストは signInRequired。
func report(message_id: String) -> Dictionary:
	var response := await _call("inbox.report", {"messageId": message_id})
	if not response["ok"]:
		return response
	return Result.ok(_flag(response["value"], "reported"))


func _call(method: String, params: Dictionary) -> Dictionary:
	# 基本機能ごと止めない。受信箱が使えない古いランタイムでは、この機能だけ unsupported にする。
	if not _grush.is_available() or _grush.protocol_version() < INBOX_PROTOCOL_VERSION:
		return Result.unsupported()
	var pending := Call.new()
	_backend.call_api(method, params, func(result: Dictionary) -> void: pending.resolve(result))
	return await pending.completed


static func message_of(raw: Dictionary) -> Dictionary:
	var payload: Variant = raw.get("payload")
	var read_at: Variant = raw.get("readAt")
	return {
		"id": str(raw.get("id", "")),
		"from": str(raw.get("from", "")),
		"kind": str(raw.get("kind", "")),
		"payload": payload if payload is Dictionary else {},
		"created_at": str(raw.get("createdAt", "")),
		"read_at": null if read_at == null or str(read_at) == "" else str(read_at),
	}


# ランタイムは包んだ RPC の結果（{"sent": true}）も、中身だけ（true）も返しうる。
static func _flag(raw: Variant, key: String) -> bool:
	var value: Variant = raw.get(key) if raw is Dictionary else raw
	return value is bool and value


static func _counted(response: Dictionary, key: String) -> Dictionary:
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var count: Variant = raw.get(key) if raw is Dictionary else raw
	if not (count is int or count is float):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable count.")
	return Result.ok(int(count))
