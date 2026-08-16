extends Control

const STATE_PATH := "user://grush_sample_score_attack.cfg"

var _player: Dictionary = {}
var _status := "Connecting to GameRush..."
var _score := 0
var _best := 0
var _remaining := 0.0
var _running := false

var _label: Label
var _share_button: Button
var _start_button: Button
var _tap_button: Button


func _ready() -> void:
	_best = _load_best()
	_build_ui()
	await _refresh_player()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 16)
	box.custom_minimum_size = Vector2(420, 0)
	add_child(box)

	_label = Label.new()
	box.add_child(_label)

	_share_button = Button.new()
	_share_button.text = "Share my profile"
	_share_button.pressed.connect(_on_share_pressed)
	box.add_child(_share_button)

	_start_button = Button.new()
	_start_button.text = "Start 10 second run"
	_start_button.pressed.connect(_on_start_pressed)
	box.add_child(_start_button)

	_tap_button = Button.new()
	_tap_button.text = "Tap for a point"
	_tap_button.pressed.connect(_on_tap_pressed)
	box.add_child(_tap_button)


func _refresh_player() -> void:
	var result: Dictionary = await GRush.player.get_self()
	if not result["ok"]:
		_status = result["message"] if GRush.is_available() else "Running outside GameRush."
		return
	_player = result["value"]
	_status = "Playing as a guest." if _player["is_guest"] else "Signed in."


func _on_share_pressed() -> void:
	_status = "Waiting for the GameRush consent dialog..."
	var result: Dictionary = await GRush.player.request_profile()
	if not result["ok"]:
		_status = (
			"Profile sharing was declined."
			if result["code"] == "consentDeclined"
			else result["message"]
		)
		return
	_player = result["value"]
	_status = "Profile shared."


func _on_start_pressed() -> void:
	_score = 0
	_remaining = 10.0
	_running = true


func _on_tap_pressed() -> void:
	if _running:
		_score += 1


func _process(delta: float) -> void:
	if _running:
		_remaining -= delta
		if _remaining <= 0.0:
			_running = false
			_remaining = 0.0
			if _score > _best:
				_best = _score
				_save_best(_best)
	_redraw()


func _redraw() -> void:
	var shared_name := "(not shared)"
	if _player.get("profile_consent", false) and _player.get("display_name") != null:
		shared_name = str(_player["display_name"])
	_label.text = "\n".join(
		[
			"GameRush Score Attack",
			_status,
			"Pseudo ID: %s" % str(_player.get("pseudo_id", "-")),
			"Display name: %s" % shared_name,
			"Score: %d    Best: %d" % [_score, _best],
			"Time left: %d" % ceili(_remaining),
		]
	)
	var guest: bool = _player.get("is_guest", true)
	_share_button.visible = not _player.get("profile_consent", false) and not guest
	_start_button.disabled = _running
	_tap_button.disabled = not _running


static func _load_best() -> int:
	var config := ConfigFile.new()
	config.load(STATE_PATH)
	return int(config.get_value("score_attack", "best", 0))


static func _save_best(value: int) -> void:
	var config := ConfigFile.new()
	config.load(STATE_PATH)
	config.set_value("score_attack", "best", value)
	config.save(STATE_PATH)
