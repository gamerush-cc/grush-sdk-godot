extends RefCounted

## 公開プレイヤー状態（他プレイヤーへ見せる進捗）。
##
## **これは他プレイヤーへ見えるユーザー生成コンテンツである。** 通報とモデレーション
## の対象になるため、payload は人間が読める構造化 JSON（辞書）に限られる。4KB を
## 超えるもの、base64 のような読めない文字列を含むものはサーバが弾く。
##
## クラウドセーブ（本人だけが読む非公開データ）とは別の入れ物であり、
## この経路からクラウドセーブは一切読めない。

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

## 公開プレイヤー状態が使えるランタイムの版数。
const PLAYER_STATE_PROTOCOL_VERSION := 2

var _grush: Node
var _backend: RefCounted


func _init(grush: Node, backend: RefCounted) -> void:
	_grush = grush
	_backend = backend


## 自分の状態を読む。運営が hidden にしていても本人には返る。
func get_mine() -> Dictionary:
	var response := await _call("playerState.getMine", {})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var state: Variant = raw.get("state") if raw is Dictionary else null
	return Result.ok(null if state == null else _state_of(state))


## 自分の状態を書く。`base_revision` を渡すと楽観ロックになり、他所で
## 更新されていた場合は invalidParams（409 相当）で戻る。
func set_mine(payload: Dictionary, base_revision: Variant = null) -> Dictionary:
	var params := {"payload": payload}
	if base_revision != null:
		params["baseRevision"] = int(base_revision)
	var response := await _call("playerState.setMine", params)
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var state: Variant = raw.get("state") if raw is Dictionary else null
	if not (state is Dictionary):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable player state.")
	return Result.ok(_state_of(state))


## 他プレイヤーの状態を疑似IDで引く（1回 50 件まで）。
## **運営が hidden にしたものは返らない。**
func get_many(pseudo_ids: Array) -> Dictionary:
	var response := await _call("playerState.get", {"pseudoIds": pseudo_ids})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var states: Array = []
	if raw is Dictionary and raw.get("states") is Array:
		for entry in raw["states"]:
			states.append(_state_of(entry))
	return Result.ok(states)


## 他プレイヤーの状態を通報する。**ゲームは通報 UI を描けない。**
## 確認ダイアログは親（信頼済み UI）が出し、承諾されたときだけ送られる。
func report(pseudo_id: String) -> Dictionary:
	var response := await _call("playerState.report", {"pseudoId": pseudo_id})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var reported: bool = bool(raw.get("reported", false)) if raw is Dictionary else false
	return Result.ok(reported)


func _call(method: String, params: Dictionary) -> Dictionary:
	# 基本機能ごと止めない。公開プレイヤー状態が使えない古いランタイムでは
	# この機能だけ unsupported にする。
	if not _grush.is_available() or _grush.protocol_version() < PLAYER_STATE_PROTOCOL_VERSION:
		return Result.unsupported()
	var pending := Call.new()
	_backend.call_api(method, params, func(result: Dictionary) -> void: pending.resolve(result))
	return await pending.completed


static func _state_of(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"pseudo_id": str(source.get("pseudoId", "")),
		"payload": source.get("payload", {}),
		"revision": int(source.get("revision", 0)),
		"updated_at": str(source.get("updatedAt", "")),
	}
