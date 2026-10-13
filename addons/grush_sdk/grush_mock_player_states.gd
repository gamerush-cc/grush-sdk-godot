class_name GRushMockPlayerStates
extends RefCounted

## エディタ用の「他プレイヤーの公開状態」。実サーバへ繋がずに、他人の進捗を
## 読む側のコードを試せるようにする。
##
## hidden の扱いも再現する。運営が伏せた状態が get から返らないことは、
## ゲーム側が「必ず全員分返る」前提で書いていないかを確かめる唯一の場所。
##
## モックの相手（[constant GRushMock.RIVALS]）は、はじめから rating 付きの状態を持つので、
## 相手探し（[code]GRush.player_state.sample[/code]）がそのまま試せる。[method reset] の後も持ち直す。

const Result := preload("res://addons/grush_sdk/grush_result.gd")

const SAMPLE_DEFAULT_COUNT := 10
const SAMPLE_MAX_COUNT := 20
const RATING_LIMIT := 1e9
const RIVAL_RATINGS := [1000.0, 1200.0, 1500.0]

static var _states: Dictionary = {}
static var _seeded := false


## [param rating] を渡すと、相手探しの範囲の絞り込みを試せる。
static func define(
	pseudo_id: String, payload: Dictionary, hidden: bool = false, rating: Variant = null
) -> void:
	_ensure_rivals()
	_put(pseudo_id, payload, hidden, rating)


## 置いた状態を消し、モックの相手の状態を置き直す。
static func reset() -> void:
	_states.clear()
	_seeded = false
	_ensure_rivals()


static func exists(pseudo_id: String) -> bool:
	_ensure_rivals()
	return _states.has(pseudo_id)


static func is_rating(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return is_finite(number) and number > -RATING_LIMIT and number < RATING_LIMIT


static func get_many(pseudo_ids: Variant) -> Array:
	_ensure_rivals()
	var ids: Array = pseudo_ids if pseudo_ids is Array else []
	var out: Array = []
	for id in ids:
		var key := str(id)
		if not _states.has(key):
			continue
		# hidden は返さない（実サーバと同じ）。
		if bool(_states[key]["hidden"]):
			continue
		out.append(_wire(key))
	return out


## 実サーバの相手探しと同じく、自分と伏せた状態を除いてランダムに引く。範囲を渡したときは、
## rating の無い状態を返さない。
static func sample(params: Dictionary, self_id: String) -> Dictionary:
	_ensure_rivals()
	var count := SAMPLE_DEFAULT_COUNT
	var raw_count: Variant = params.get("count")
	if raw_count != null:
		if not _is_integer(raw_count) or int(raw_count) < 1 or int(raw_count) > SAMPLE_MAX_COUNT:
			return _invalid("count must be an integer from 1 to %d." % SAMPLE_MAX_COUNT)
		count = int(raw_count)
	var min_rating: Variant = params.get("minRating")
	var max_rating: Variant = params.get("maxRating")
	var ranged: bool = min_rating != null
	if ranged != (max_rating != null):
		return _invalid("minRating and maxRating must be given together.")
	if ranged:
		if not is_rating(min_rating) or not is_rating(max_rating):
			return _invalid("Invalid rating range.")
		if float(min_rating) > float(max_rating):
			return _invalid("minRating must not exceed maxRating.")
	var candidates: Array = []
	for key in _states:
		var entry: Dictionary = _states[key]
		if bool(entry["hidden"]) or key == self_id:
			continue
		if ranged:
			var rating: Variant = entry["rating"]
			if rating == null or float(rating) < float(min_rating) or float(rating) > float(max_rating):
				continue
		candidates.append(key)
	candidates.shuffle()
	var states: Array = []
	for key in candidates.slice(0, count):
		states.append(_wire(key))
	return Result.ok({"states": states})


static func _ensure_rivals() -> void:
	if _seeded:
		return
	_seeded = true
	for index in range(GRushMock.RIVALS.size()):
		_put(GRushMock.RIVALS[index], {"level": (index + 1) * 5}, false, RIVAL_RATINGS[index])


static func _put(pseudo_id: String, payload: Dictionary, hidden: bool, rating: Variant) -> void:
	_states[pseudo_id] = {
		"payload": payload,
		"hidden": hidden,
		"revision": 1,
		"rating": float(rating) if is_rating(rating) else null,
	}


static func _wire(key: String) -> Dictionary:
	var entry: Dictionary = _states[key]
	return {
		"pseudoId": key,
		"payload": entry["payload"],
		"revision": int(entry["revision"]),
		"rating": entry["rating"],
		"updatedAt": "",
	}


static func _is_integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))


static func _invalid(message: String) -> Dictionary:
	return Result.failure(Result.CODE_INVALID_PARAMS, message)
