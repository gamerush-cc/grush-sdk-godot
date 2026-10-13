class_name GRushMockInbox
extends RefCounted

## エディタ用の受信箱。GameRush と同じ規則（payload の形・1KB・kind の形・自分宛ての禁止）で弾く。
## モックの相手（[constant GRushMock.RIVALS]）と [method GRushMockPlayerStates.define] で置いた相手は、
## 届いたメッセージを同じ kind と payload で送り返すので、送ってから一覧で受け取れる。
## 通報を承諾すると送り手をブロックし、その相手のメッセージと出品は見えなくなる。

const Payload := preload("res://addons/grush_sdk/grush_mock_payload.gd")
const Result := preload("res://addons/grush_sdk/grush_result.gd")

const MAX_PAYLOAD_BYTES := 1024
const MAX_IDS := 50
const DEFAULT_LIMIT := 20
const MAX_LIMIT := 50

static var _messages: Array = []
# 受信箱と交換所で共有するゲーム内のブロック。
static var _blocked: Dictionary = {}
static var _seeded := false
static var _uuid_pattern := RegEx.create_from_string(
	"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)


## [param from] から自分の受信箱へメッセージを届ける。形が受信箱の縛りに合わないか、
## 送り手をブロックしていれば false。
static func receive(from: String, kind: String, payload: Dictionary) -> bool:
	_ensure()
	if from == "" or from == GRushMock.local_pseudo_id() or not Payload.is_token(kind):
		return false
	if is_blocked(from) or Payload.error_of(payload, MAX_PAYLOAD_BYTES, "Inbox payload") != "":
		return false
	_deliver(from, kind, payload)
	return true


## はじめの1通だけに戻し、通報によるブロックも消す。
static func reset() -> void:
	_seeded = false
	_ensure()


static func is_blocked(pseudo_id: Variant) -> bool:
	_ensure()
	return pseudo_id != null and _blocked.has(str(pseudo_id))


static func block(pseudo_id: Variant) -> void:
	_ensure()
	if pseudo_id != null:
		_blocked[str(pseudo_id)] = true


static func new_id() -> String:
	var hex := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-4%s-a%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(13, 3), hex.substr(17, 3), hex.substr(20, 12)
	]


static func timestamp(unix: float) -> String:
	return Time.get_datetime_string_from_unix_time(int(unix), false) + "Z"


## ids が 1〜50 件の UUID なら小文字にそろえた辞書（集合）、そうでなければ null。
static func ids_of(value: Variant) -> Variant:
	if not (value is Array) or value.is_empty() or value.size() > MAX_IDS:
		return null
	var ids := {}
	for entry in value:
		if not (entry is String) or _uuid_pattern.search(entry) == null:
			return null
		ids[entry.to_lower()] = true
	return ids


## limit が省略なら既定値、1〜50 の整数ならその値、ほかは -1。
static func limit_of(value: Variant) -> int:
	if value == null:
		return DEFAULT_LIMIT
	if not (value is int or (value is float and value == floor(value))):
		return -1
	var limit := int(value)
	return limit if limit >= 1 and limit <= MAX_LIMIT else -1


## cursor の次の位置。cursor が無ければ 0、見つからなければ -1。
static func start_of(cursor: Variant, ids: Array) -> int:
	if cursor == null:
		return 0
	var at: int = ids.find(str(cursor)) if cursor is String else -1
	return -1 if at == -1 else at + 1


static func _ensure() -> void:
	if _seeded:
		return
	_seeded = true
	_messages.clear()
	_blocked.clear()
	_deliver(GRushMock.RIVALS[0], "challenge", {"stage": 3, "score": 1200})


static func _deliver(from: String, kind: String, payload: Dictionary) -> void:
	if _blocked.has(from):
		return
	_messages.append(
		{
			"id": new_id(),
			"from": from,
			"kind": kind,
			"payload": payload.duplicate(true),
			"createdAt": timestamp(Time.get_unix_time_from_system()),
			"readAt": null,
			"removed": false,
		}
	)


# 新しい順。消したものと、ブロックした送り手のものを除く。
static func _visible() -> Array:
	var visible: Array = []
	for index in range(_messages.size() - 1, -1, -1):
		var message: Dictionary = _messages[index]
		if not bool(message["removed"]) and not _blocked.has(message["from"]):
			visible.append(message)
	return visible


static func _wire(message: Dictionary) -> Dictionary:
	return {
		"id": message["id"],
		"from": message["from"],
		"kind": message["kind"],
		"payload": message["payload"].duplicate(true),
		"createdAt": message["createdAt"],
		"readAt": message["readAt"],
	}


static func _invalid(message: String) -> Dictionary:
	return Result.failure(Result.CODE_INVALID_PARAMS, message)


static func handle_send(params: Dictionary, self_id: String) -> Dictionary:
	_ensure()
	var to: Variant = params.get("to")
	if not (to is String) or to == "":
		return _invalid("Invalid recipient.")
	if to == self_id:
		return _invalid("Cannot send a message to yourself.")
	if not GRushMockPlayerStates.exists(to):
		return _invalid("No player with that id.")
	var kind: Variant = params.get("kind")
	if not Payload.is_token(kind):
		return _invalid("Invalid kind.")
	var error := Payload.error_of(params.get("payload"), MAX_PAYLOAD_BYTES, "Inbox payload")
	if error != "":
		return _invalid(error)
	# モックの相手は、届いたメッセージを同じ kind と payload で送り返す。
	_deliver(to, kind, params["payload"])
	return Result.ok({"sent": true})


static func handle_list(params: Dictionary) -> Dictionary:
	_ensure()
	var limit := limit_of(params.get("limit"))
	if limit == -1:
		return _invalid("Invalid limit.")
	var unread_only: bool = params.get("unreadOnly") == true
	var visible := _visible()
	var unread_count := 0
	var filtered: Array = []
	var ids: Array = []
	for message in visible:
		if message["readAt"] == null:
			unread_count += 1
		if not unread_only or message["readAt"] == null:
			filtered.append(message)
			ids.append(message["id"])
	var start := start_of(params.get("cursor"), ids)
	if start == -1:
		return _invalid("Invalid cursor.")
	var page := filtered.slice(start, start + limit)
	var next_cursor: Variant = null
	if start + limit < filtered.size() and not page.is_empty():
		next_cursor = page[page.size() - 1]["id"]
	var messages: Array = []
	for message in page:
		messages.append(_wire(message))
	return Result.ok({"messages": messages, "unreadCount": unread_count, "nextCursor": next_cursor})


static func handle_mark_read(params: Dictionary) -> Dictionary:
	return _update(params, false)


static func handle_remove(params: Dictionary) -> Dictionary:
	return _update(params, true)


static func _update(params: Dictionary, remove: bool) -> Dictionary:
	_ensure()
	var ids: Variant = ids_of(params.get("ids"))
	if ids == null:
		return _invalid("ids must be 1 to 50 message ids.")
	var updated := 0
	for message in _visible():
		if not ids.has(str(message["id"]).to_lower()):
			continue
		if remove:
			message["removed"] = true
			updated += 1
		elif message["readAt"] == null:
			message["readAt"] = timestamp(Time.get_unix_time_from_system())
			updated += 1
	return Result.ok({"updated": updated})


static func handle_report(params: Dictionary) -> Dictionary:
	_ensure()
	if not GRushMock.signed_in:
		return Result.failure(Result.CODE_SIGN_IN_REQUIRED, "Reporting requires sign-in.")
	var message_id: Variant = params.get("messageId")
	for message in _visible():
		if message["id"] == message_id:
			if not GRushMock.confirm_inbox_report:
				return Result.ok({"reported": false})
			_blocked[message["from"]] = true
			return Result.ok({"reported": true})
	return _invalid("No message for that id.")
