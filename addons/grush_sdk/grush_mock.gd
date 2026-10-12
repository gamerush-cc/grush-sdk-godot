class_name GRushMock
extends RefCounted

## モックの相手の疑似 ID。それぞれ rating 付きの公開プレイヤー状態を持ち、届いたメッセージを
## 同じ kind と payload で送り返す。はじめと [method GRushMockInbox.reset] /
## [method GRushMockTrades.reset] の後は、最初の相手からのメッセージ1通と、受付中の出品を2件持つ。
const RIVALS := ["mock-rival-1", "mock-rival-2", "mock-rival-3"]

const STATE_PATH := "user://grush_sdk_mock.cfg"
const STATE_SECTION := "mock"

static var signed_in := true
static var display_name := "Editor Player"
static var avatar_url: Variant = null
static var grant_profile_consent := true
## 通報の確認ダイアログでプレイヤーが押す答え。エディタ用。
static var confirm_player_state_report := true
## 受信箱の通報の確認でプレイヤーが押す答え。
static var confirm_inbox_report := true
## 交換所の通報の確認でプレイヤーが押す答え。
static var confirm_trade_report := true
static var unreliable_drop_rate := 0.0
static var max_peers := 8
static var share_available := true
static var share_status := "opened"
static var locale := ""


## モックの自分の疑似 ID。初めて読んだときに作り、user:// に残す。
static func local_pseudo_id() -> String:
	var config := ConfigFile.new()
	config.load(STATE_PATH)
	var stored := str(config.get_value(STATE_SECTION, "pseudo_id", ""))
	if stored != "":
		return stored
	var created := "mock-local-" + str(randi()) + str(randi())
	config.set_value(STATE_SECTION, "pseudo_id", created)
	config.save(STATE_PATH)
	return created
