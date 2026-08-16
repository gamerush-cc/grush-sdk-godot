class_name GRushMockPlayerStates
extends RefCounted

## エディタ用の「他プレイヤーの公開状態」。実サーバへ繋がずに、他人の進捗を
## 読む側のコードを試せるようにする。
##
## hidden の扱いも再現する。運営が伏せた状態が get から返らないことは、
## ゲーム側が「必ず全員分返る」前提で書いていないかを確かめる唯一の場所。

static var _states: Dictionary = {}


static func define(pseudo_id: String, payload: Dictionary, hidden: bool = false) -> void:
	_states[pseudo_id] = {"payload": payload, "hidden": hidden, "revision": 1}


static func reset() -> void:
	_states.clear()


static func get_many(pseudo_ids: Variant) -> Array:
	var ids: Array = pseudo_ids if pseudo_ids is Array else []
	var out: Array = []
	for id in ids:
		var key := str(id)
		if not _states.has(key):
			continue
		var entry: Dictionary = _states[key]
		# hidden は返さない（実サーバと同じ）。
		if bool(entry["hidden"]):
			continue
		out.append(
			{
				"pseudoId": key,
				"payload": entry["payload"],
				"revision": int(entry["revision"]),
				"updatedAt": "",
			}
		)
	return out
