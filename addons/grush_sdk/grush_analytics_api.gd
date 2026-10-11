extends RefCounted

## 作者のアナリティクスへ送るイベント。ほかの API と違い、どれも同期で bool を返し、await しない。
## true は GameRush へ渡したことで、保存されたことではない。形が不正なとき、protocol_version 6 未満の
## GameRush、GameRush の外では false。名前・値・fields にプレイヤーを識別できる情報を入れない。

const ANALYTICS_PROTOCOL_VERSION := 6

## エコノミーのイベントの向き。
const FLOW_SOURCE := "source"
const FLOW_SINK := "sink"

## GameRush の標準の取引の種類。ほかの値（英数字と ._:- で 32 文字まで）も渡せる。
const TRANSACTION_TIMED_REWARD := "TimedReward"
const TRANSACTION_ONBOARDING := "Onboarding"
const TRANSACTION_SHOP := "Shop"
const TRANSACTION_GAMEPLAY := "Gameplay"
const TRANSACTION_CONTEXTUAL_PURCHASE := "ContextualPurchase"

var _grush: Node
var _transport: RefCounted


func _init(grush: Node, transport: RefCounted) -> void:
	_grush = grush
	_transport = transport


## GameRush の中で動いていて、分析イベントを送れるか。
func is_available() -> bool:
	return _supported() and _transport.is_available()


## オンボーディングのステップ。step は 1〜100。step_name と fields の値は1行のテキストで 40 文字まで。
## fields は String から String への Dictionary で3つまで、キーは英数字と _ で 32 文字まで。
func log_onboarding_step(step: int, step_name: String = "", fields: Dictionary = {}) -> bool:
	return _log("onboarding", {"step": step, "stepName": step_name}, fields)


## ファネルのステップ。funnel と funnel_session_id は英数字と ._:- で 64 文字まで。funnel_session_id は
## 空文字で省略できる。同じファネルを1回のプレイで何度も通るなら、通るたびに別の funnel_session_id を渡す。
func log_funnel_step(
	funnel: String,
	funnel_session_id: String,
	step: int,
	step_name: String = "",
	fields: Dictionary = {}
) -> bool:
	var params := {
		"funnel": funnel,
		"funnelSessionId": funnel_session_id,
		"step": step,
		"stepName": step_name,
	}
	return _log("funnel", params, fields)


## カスタムイベント。event_name は英数字と ._:- で 64 文字まで。value は絶対値 1e9 まで。
func log_custom_event(event_name: String, value: float = 1.0, fields: Dictionary = {}) -> bool:
	return _log("custom", {"name": event_name, "value": value}, fields)


## 通貨の入手（FLOW_SOURCE）と消費（FLOW_SINK）。amount は正の値で 1e12 まで、ending_balance はその後の
## 残高で絶対値 1e15 まで。currency と transaction_type は英数字と ._:- で 32 文字まで。item_sku は1行の
## テキストで 40 文字まで、空文字で省略できる。
func log_economy_event(
	flow_type: String,
	currency: String,
	amount: float,
	ending_balance: float,
	transaction_type: String,
	item_sku: String = "",
	fields: Dictionary = {}
) -> bool:
	var params := {
		"flowType": flow_type,
		"currency": currency,
		"amount": amount,
		"endingBalance": ending_balance,
		"transactionType": transaction_type,
		"itemSku": item_sku,
	}
	return _log("economy", params, fields)


func _log(kind: String, params: Dictionary, fields: Dictionary) -> bool:
	if not _supported():
		return false
	if not fields.is_empty():
		params["fields"] = fields
	return _transport.log_event(kind, params)


func _supported() -> bool:
	return (
		_transport != null
		and _grush.is_available()
		and _grush.protocol_version() >= ANALYTICS_PROTOCOL_VERSION
	)
