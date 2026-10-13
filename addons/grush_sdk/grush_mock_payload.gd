extends RefCounted

## モックの受信箱と交換所が payload を確かめる。GameRush と同じく、辞書であること、文字列の値と
## キーが識別子（`^[A-Za-z0-9_.:-]{1,32}$`）であること、数値が有限であること、入れ子が最上位を
## 1 段目として 4 段まで、値が合計 64 個まで、JSON にして上限のバイト数までであることを求める。
## バイト数は Godot の JSON.stringify で数えるので、小数点の付く数値（`3.0` など）を GameRush より
## 多く数えることがある。

const MAX_DEPTH := 4
const MAX_SCALARS := 64

static var _token := RegEx.create_from_string("^[A-Za-z0-9_.:-]{1,32}$")


static func is_token(value: Variant) -> bool:
	return value is String and _token.search(value) != null


## 通るなら空文字、弾くならエラーの文言を返す。
static func error_of(value: Variant, max_bytes: int, label: String) -> String:
	if not (value is Dictionary):
		return "%s must be a JSON object." % label
	var state := {"scalars": 0}
	var error := _walk(value, 1, state, label)
	if error != "":
		return error
	if JSON.stringify(value).to_utf8_buffer().size() > max_bytes:
		return "%s must be %d bytes or smaller." % [label, max_bytes]
	return ""


# depth は value を入れている入れ物の段。上限より深い入れ物は降りずに弾く。
static func _walk(value: Variant, depth: int, state: Dictionary, label: String) -> String:
	if value is Dictionary or value is Array:
		if depth > MAX_DEPTH:
			return "%s must not nest deeper than %d levels." % [label, MAX_DEPTH]
		if value is Dictionary:
			for key in value:
				if not is_token(key):
					return "%s keys must be 1-32 letters, digits, or _ . : -" % label
				var error := _walk(value[key], depth + 1, state, label)
				if error != "":
					return error
		else:
			for item in value:
				var error := _walk(item, depth + 1, state, label)
				if error != "":
					return error
		return ""
	state["scalars"] = int(state["scalars"]) + 1
	if int(state["scalars"]) > MAX_SCALARS:
		return "%s must hold at most %d values." % [label, MAX_SCALARS]
	if value is String:
		if is_token(value):
			return ""
		return "%s strings must be 1-32 letters, digits, or _ . : - (no free text)." % label
	if value is float:
		if is_finite(value):
			return ""
		return "%s numbers must be finite." % label
	if value is int or value is bool or value == null:
		return ""
	return "%s must be JSON." % label
