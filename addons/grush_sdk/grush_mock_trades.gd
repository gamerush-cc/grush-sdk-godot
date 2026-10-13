class_name GRushMockTrades
extends RefCounted

## エディタ用の交換所。GameRush と同じ規則（offer・want・give の形と大きさ・key・期限・
## operationId での冪等・受付中の出品は 10 件まで）で弾き、受諾の結果・pending・ack を同じ形で返す。
## はじめと [method reset] の後は、モックの相手（[constant GRushMock.RIVALS]）の受付中の出品を2件持つ。
## 相手が自分の出品を受ける・相手が出品する・期限を切らすことは、[method accept]・[method offer]・
## [method expire] で起こす。

const Payload := preload("res://addons/grush_sdk/grush_mock_payload.gd")
const Result := preload("res://addons/grush_sdk/grush_result.gd")
const TradeApi := preload("res://addons/grush_sdk/grush_trade_api.gd")

const MAX_OFFER_BYTES := 2048
const MAX_WANT_BYTES := 1024
const MAX_GIVE_BYTES := 2048
const MAX_OPEN_TRADES := 10
const PENDING_LIMIT := 100
const DEFAULT_EXPIRES_IN_SEC := 3 * 24 * 60 * 60
const MIN_EXPIRES_IN_SEC := 10 * 60
const MAX_EXPIRES_IN_SEC := 7 * 24 * 60 * 60

static var _trades: Array = []
static var _seeded := false
static var _operation_id := RegEx.create_from_string("^[A-Za-z0-9._:-]{1,64}$")


## [param from] の出品を作り、出品（[code]GRush.trade[/code] が返すのと同じ形）を返す。
## [param options] は [code]offer_key[/code]・[code]want_key[/code]・[code]expires_in_sec[/code]・
## [code]to_self[/code]（true で自分宛ての指名の出品）。形が縛りに合わなければ null。
static func offer(from: String, offer_items: Dictionary, want: Dictionary, options: Dictionary = {}) -> Variant:
	_ensure()
	var self_id := GRushMock.local_pseudo_id()
	if from == "" or from == self_id:
		return null
	var opts := {
		"offerKey": options.get("offer_key"),
		"wantKey": options.get("want_key"),
		"expiresInSec": options.get("expires_in_sec"),
	}
	if _options_error(offer_items, want, opts) != "":
		return null
	var to: Variant = self_id if options.get("to_self", false) == true else null
	var trade := _open(from, offer_items, want, opts, to, null)
	return TradeApi.trade_of(_wire(trade, self_id))


## 自分の出品を [param by]（省略すると最初の相手）が受ける。結果は受諾の outcome と同じ文字列。
static func accept(trade_id: String, give: Dictionary, by: String = "") -> String:
	_ensure()
	var self_id := GRushMock.local_pseudo_id()
	var taker := by if by != "" else str(GRushMock.RIVALS[0])
	if taker == self_id or Payload.error_of(give, MAX_GIVE_BYTES, "Trade give") != "":
		return "notFound"
	var trade: Variant = _find(trade_id)
	if trade == null or trade["from"] != self_id:
		return "notFound"
	return _settle(trade_id, give, taker)["outcome"]


## 受付中の出品をいま期限切れにする。
static func expire(trade_id: String) -> bool:
	_ensure()
	var trade: Variant = _find(trade_id)
	if trade == null or trade["status"] != "open":
		return false
	trade["expiresAt"] = Time.get_unix_time_from_system()
	_expire_due()
	return true


## はじめの2件の出品だけに戻す。
static func reset() -> void:
	_seeded = false
	_ensure()


static func _ensure() -> void:
	if _seeded:
		return
	_seeded = true
	_trades.clear()
	_open(
		str(GRushMock.RIVALS[0]),
		{"item": "sword", "count": 1},
		{"item": "gem", "count": 3},
		{"offerKey": "sword", "wantKey": "gem"},
		null,
		null
	)
	_open(
		str(GRushMock.RIVALS[1]),
		{"item": "shield", "count": 1},
		{"item": "coin", "count": 100},
		{"offerKey": "shield", "wantKey": "coin"},
		null,
		null
	)


static func _open(
	from: String, offer_items: Dictionary, want: Dictionary, opts: Dictionary, to: Variant, operation_id: Variant
) -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var seconds: Variant = opts.get("expiresInSec")
	var trade := {
		"id": GRushMockInbox.new_id(),
		"from": from,
		"to": to,
		"taker": null,
		"offer": offer_items.duplicate(true),
		"want": want.duplicate(true),
		"offerKey": opts.get("offerKey"),
		"wantKey": opts.get("wantKey"),
		"give": null,
		"status": "open",
		"createdAt": now,
		"expiresAt": now + (DEFAULT_EXPIRES_IN_SEC if seconds == null else int(seconds)),
		"settledAt": null,
		"ackedBy": {},
		"operationId": operation_id,
	}
	_trades.append(trade)
	return trade


static func _options_error(offer_items: Variant, want: Variant, opts: Dictionary) -> String:
	var error := Payload.error_of(offer_items, MAX_OFFER_BYTES, "Trade offer")
	if error != "":
		return error
	error = Payload.error_of(want, MAX_WANT_BYTES, "Trade want")
	if error != "":
		return error
	for name in ["offerKey", "wantKey"]:
		var value: Variant = opts.get(name)
		if value != null and not Payload.is_token(value):
			return "Invalid %s." % name
	var seconds: Variant = opts.get("expiresInSec")
	if seconds != null:
		var whole: bool = seconds is int or (seconds is float and seconds == floor(seconds))
		if not whole or int(seconds) < MIN_EXPIRES_IN_SEC or int(seconds) > MAX_EXPIRES_IN_SEC:
			return "Invalid expiresInSec."
	return ""


static func _find(trade_id: Variant) -> Variant:
	for trade in _trades:
		if trade["id"] == trade_id:
			return trade
	return null


static func _expire_due() -> void:
	var now := Time.get_unix_time_from_system()
	for trade in _trades:
		if trade["status"] == "open" and float(trade["expiresAt"]) <= now:
			trade["status"] = "expired"
			trade["settledAt"] = trade["expiresAt"]


static func _wire(trade: Dictionary, self_id: String) -> Dictionary:
	var party: bool = trade["from"] == self_id or trade["taker"] == self_id
	var give: Variant = trade["give"]
	return {
		"id": trade["id"],
		"from": trade["from"],
		"to": trade["to"],
		"taker": trade["taker"],
		"offer": trade["offer"].duplicate(true),
		"want": trade["want"].duplicate(true),
		"offerKey": trade["offerKey"],
		"wantKey": trade["wantKey"],
		"give": give.duplicate(true) if party and give != null else null,
		"status": trade["status"],
		"createdAt": GRushMockInbox.timestamp(float(trade["createdAt"])),
		"expiresAt": GRushMockInbox.timestamp(float(trade["expiresAt"])),
		"settledAt": null if trade["settledAt"] == null else GRushMockInbox.timestamp(float(trade["settledAt"])),
	}


static func _invalid(message: String) -> Dictionary:
	return Result.failure(Result.CODE_INVALID_PARAMS, message)


static func handle_create(params: Dictionary, self_id: String) -> Dictionary:
	_ensure()
	var error := _options_error(params.get("offer"), params.get("want"), params)
	if error != "":
		return _invalid(error)
	var operation_id: Variant = params.get("operationId")
	if not (operation_id is String) or _operation_id.search(operation_id) == null:
		return _invalid("Invalid operationId.")
	var to: Variant = params.get("to")
	if to != null:
		if not (to is String) or to == "":
			return _invalid("Invalid recipient.")
		if to == self_id:
			return _invalid("Cannot offer a trade to yourself.")
		if not GRushMockPlayerStates.exists(to):
			return _invalid("No player with that id.")
	# 同じ operationId の再送には、中身によらず先に作った出品を返す。
	for trade in _trades:
		if trade["from"] == self_id and trade["operationId"] == operation_id:
			return Result.ok({"trade": _wire(trade, self_id)})
	_expire_due()
	var open := 0
	for trade in _trades:
		if trade["from"] == self_id and trade["status"] == "open":
			open += 1
	if open >= MAX_OPEN_TRADES:
		# GameRush と同じく、待っても直らない上限なので rateLimited にしない。
		return Result.failure(Result.CODE_INVALID_PARAMS, "Too many open trades. Cancel an open trade first.")
	var created := _open(self_id, params["offer"], params["want"], params, to, operation_id)
	return Result.ok({"trade": _wire(created, self_id)})


static func handle_list(params: Dictionary, self_id: String) -> Dictionary:
	_ensure()
	var limit := GRushMockInbox.limit_of(params.get("limit"))
	if limit == -1:
		return _invalid("Invalid limit.")
	var offer_key: Variant = params.get("offerKey")
	var want_key: Variant = params.get("wantKey")
	_expire_due()
	var visible: Array = []
	var ids: Array = []
	for index in range(_trades.size() - 1, -1, -1):
		var trade: Dictionary = _trades[index]
		if trade["status"] != "open" or trade["from"] == self_id:
			continue
		if trade["to"] != null and trade["to"] != self_id:
			continue
		if GRushMockInbox.is_blocked(trade["from"]):
			continue
		if offer_key != null and trade["offerKey"] != offer_key:
			continue
		if want_key != null and trade["wantKey"] != want_key:
			continue
		visible.append(trade)
		ids.append(trade["id"])
	var start := GRushMockInbox.start_of(params.get("cursor"), ids)
	if start == -1:
		return _invalid("Invalid cursor.")
	var page := visible.slice(start, start + limit)
	var next_cursor: Variant = null
	if start + limit < visible.size() and not page.is_empty():
		next_cursor = page[page.size() - 1]["id"]
	var trades: Array = []
	for trade in page:
		trades.append(_wire(trade, self_id))
	return Result.ok({"trades": trades, "nextCursor": next_cursor})


static func _pending_wire(trade: Dictionary, self_id: String) -> Variant:
	if trade["status"] == "open" or trade["ackedBy"].has(self_id):
		return null
	if trade["from"] == self_id:
		var wire := _wire(trade, self_id)
		wire["role"] = "offerer"
		wire["action"] = "receiveGive" if trade["status"] == "matched" else "returnOffer"
		return wire
	if trade["taker"] == self_id:
		var wire := _wire(trade, self_id)
		wire["role"] = "taker"
		wire["action"] = "receiveOffer"
		return wire
	return null


static func handle_mine(self_id: String) -> Dictionary:
	_ensure()
	_expire_due()
	var open: Array = []
	for index in range(_trades.size() - 1, -1, -1):
		var trade: Dictionary = _trades[index]
		if trade["from"] == self_id and trade["status"] == "open":
			open.append(_wire(trade, self_id))
	var finished: Array = []
	for trade in _trades:
		if _pending_wire(trade, self_id) != null:
			finished.append(trade)
	finished.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a["settledAt"]) < float(b["settledAt"])
	)
	var pending: Array = []
	for trade in finished.slice(0, PENDING_LIMIT):
		pending.append(_pending_wire(trade, self_id))
	return Result.ok({"open": open, "pending": pending})


# 受諾の判定。見えない出品は notFound、終わった出品はその状態、受付中なら成立させる。
static func _settle(trade_id: Variant, give: Dictionary, taker: String) -> Dictionary:
	_expire_due()
	var trade: Variant = _find(trade_id)
	if (
		trade == null
		or trade["from"] == taker
		or (trade["to"] != null and trade["to"] != taker)
		or GRushMockInbox.is_blocked(trade["from"])
	):
		return {"outcome": "notFound", "trade": null}
	if trade["status"] == "matched":
		if trade["taker"] != taker:
			return {"outcome": "taken", "trade": null}
		return {"outcome": "matched", "trade": trade}
	if trade["status"] != "open":
		return {"outcome": trade["status"], "trade": null}
	trade["taker"] = taker
	trade["give"] = give.duplicate(true)
	trade["status"] = "matched"
	trade["settledAt"] = Time.get_unix_time_from_system()
	return {"outcome": "matched", "trade": trade}


static func handle_accept(params: Dictionary, self_id: String) -> Dictionary:
	_ensure()
	var trade_id: Variant = params.get("tradeId")
	if not (trade_id is String) or trade_id == "":
		return _invalid("Invalid tradeId.")
	var give: Variant = params.get("give")
	var error := Payload.error_of(give, MAX_GIVE_BYTES, "Trade give")
	if error != "":
		return _invalid(error)
	var settled := _settle(trade_id, give, self_id)
	var result := {"outcome": settled["outcome"]}
	if settled["trade"] != null:
		result["trade"] = _wire(settled["trade"], self_id)
	return Result.ok(result)


static func handle_cancel(params: Dictionary, self_id: String) -> Dictionary:
	_ensure()
	_expire_due()
	var trade: Variant = _find(params.get("tradeId"))
	if trade == null or trade["from"] != self_id:
		return _invalid("No trade of yours for that id.")
	if trade["status"] == "open":
		trade["status"] = "cancelled"
		trade["settledAt"] = Time.get_unix_time_from_system()
	return Result.ok({"trade": _wire(trade, self_id)})


static func handle_ack(params: Dictionary, self_id: String) -> Dictionary:
	_ensure()
	var ids: Variant = GRushMockInbox.ids_of(params.get("ids"))
	if ids == null:
		return _invalid("ids must be 1 to 50 trade ids.")
	_expire_due()
	var acked := 0
	for trade in _trades:
		if ids.has(str(trade["id"]).to_lower()) and _pending_wire(trade, self_id) != null:
			trade["ackedBy"][self_id] = true
			acked += 1
	return Result.ok({"acked": acked})


static func handle_report(params: Dictionary, self_id: String) -> Dictionary:
	_ensure()
	if not GRushMock.signed_in:
		return Result.failure(Result.CODE_SIGN_IN_REQUIRED, "Reporting requires sign-in.")
	_expire_due()
	var trade: Variant = _find(params.get("tradeId"))
	if trade == null:
		return _invalid("No trade for that id.")
	var listed: bool = (
		trade["status"] == "open"
		and trade["from"] != self_id
		and (trade["to"] == null or trade["to"] == self_id)
	)
	if not listed and trade["taker"] != self_id:
		return _invalid("No trade for that id.")
	if not GRushMock.confirm_trade_report:
		return Result.ok({"reported": false})
	GRushMockInbox.block(trade["from"])
	return Result.ok({"reported": true})
