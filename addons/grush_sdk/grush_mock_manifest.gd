extends RefCounted

## モックが grush.json を読む。アップロードと同じ規則で読み、誤りはアップロードと
## 同じ文言で返すので、手元で確かめた時点で書き損じに気づける。

const FILE_NAME := "grush.json"
const MAX_BYTES := 64 * 1024
const MAX_LEADERBOARDS := 20
const MAX_TITLE_LENGTH := 60
const MAX_KEY_LENGTH := 64
const TOP_LEVEL_FIELDS := ["$schema", "leaderboards"]
const ENTRY_FIELDS := [
	"key",
	"title",
	"sort",
	"valueType",
	"aggregation",
	"period",
	"minValue",
	"maxValue",
	"enabled",
]
const CHOICES := {
	"sort": ["desc", "asc"],
	"valueType": ["int", "float", "duration_ms"],
	"aggregation": ["best", "last", "sum"],
	"period": ["all_time", "daily", "weekly", "monthly"],
}


## 読めたら {"leaderboards": [...]}、読めなければ {"error": 文言} を返す。
static func parse(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return {"error": "%s is too large (%dKB at most)." % [FILE_NAME, MAX_BYTES / 1024]}
	if text.begins_with(char(0xFEFF)):
		text = text.substr(1)
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "%s can't be read as a JSON object." % FILE_NAME}
	var root: Dictionary = json.data
	for field in root:
		if not TOP_LEVEL_FIELDS.has(field):
			return {"error": "%s has an unknown field: %s" % [FILE_NAME, field]}

	var list: Variant = root.get("leaderboards", null)
	if list == null:
		return {"leaderboards": []}
	if typeof(list) != TYPE_ARRAY:
		return _invalid("leaderboards")
	if list.size() > MAX_LEADERBOARDS:
		return {
			"error": "%s can declare up to %d leaderboards." % [FILE_NAME, MAX_LEADERBOARDS]
		}

	var entries: Array = []
	var seen := {}
	for index in list.size():
		var read := _read_entry(list[index], "leaderboards[%d]" % index)
		if read.has("error"):
			return read
		var key: String = read["key"]
		if seen.has(key):
			return {
				"error":
				"%s declares the leaderboard key more than once: %s" % [FILE_NAME, key]
			}
		seen[key] = true
		entries.append(read)
	return {"leaderboards": entries}


static func _read_entry(item: Variant, at: String) -> Dictionary:
	if typeof(item) != TYPE_DICTIONARY:
		return _invalid(at)
	for field in item:
		if not ENTRY_FIELDS.has(field):
			return {"error": "%s has an unknown field: %s.%s" % [FILE_NAME, at, field]}

	var key: Variant = item.get("key", null)
	if typeof(key) != TYPE_STRING or not _is_key(key):
		return _invalid(at + ".key")
	var title := _collapse_title(item.get("title", null))
	if title.length() < 1 or title.length() > MAX_TITLE_LENGTH:
		return _invalid(at + ".title")
	for field in CHOICES:
		var value: Variant = item.get(field, null)
		if typeof(value) != TYPE_STRING or not CHOICES[field].has(value):
			return _invalid("%s.%s" % [at, field])
	if item.has("enabled") and typeof(item["enabled"]) != TYPE_BOOL:
		return _invalid(at + ".enabled")
	for field in ["minValue", "maxValue"]:
		var value: Variant = item.get(field, null)
		if value == null:
			continue
		var numeric := typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT
		if not numeric or not is_finite(float(value)):
			return _invalid("%s.%s" % [at, field])
	var min_value: Variant = item.get("minValue", null)
	var max_value: Variant = item.get("maxValue", null)
	if (min_value == null) != (max_value == null):
		return _invalid(at + ".minValue / maxValue")
	if min_value != null and float(min_value) >= float(max_value):
		return _invalid(at + ".minValue / maxValue")

	return {
		"key": key,
		"title": title,
		"sort": item["sort"],
		"value_type": item["valueType"],
		"aggregation": item["aggregation"],
		"period": item["period"],
		"min_value": null if min_value == null else float(min_value),
		"max_value": null if max_value == null else float(max_value),
		"enabled": item.get("enabled", true),
	}


static func _is_key(key: String) -> bool:
	if key.is_empty() or key.length() > MAX_KEY_LENGTH:
		return false
	for index in key.length():
		var c := key.unicode_at(index)
		var allowed := (
			(c >= 0x41 and c <= 0x5A)
			or (c >= 0x61 and c <= 0x7A)
			or (c >= 0x30 and c <= 0x39)
			or c in [0x2E, 0x5F, 0x3A, 0x2D]
		)
		if not allowed:
			return false
	return true


# 改行と制御文字を空白にしてから前後を詰める。GameRush が保存するタイトルと同じ形にする。
static func _collapse_title(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var text: String = value
	var collapsed := ""
	var in_run := false
	for index in text.length():
		var c := text.unicode_at(index)
		var breaking := (
			c < 0x20
			or (c >= 0x7F and c <= 0x9F)
			or c == 0x2028
			or c == 0x2029
			or (c >= 0x202A and c <= 0x202E)
			or (c >= 0x2066 and c <= 0x2069)
		)
		if breaking:
			if not in_run:
				collapsed += " "
			in_run = true
			continue
		in_run = false
		collapsed += text[index]
	return collapsed.strip_edges()


static func _invalid(field: String) -> Dictionary:
	return {"error": "%s has an invalid value: %s" % [FILE_NAME, field]}
