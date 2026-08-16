extends Control

const PADDLE_KIND := 1
const BALL_KIND := 2
const SEND_INTERVAL_SEC := 0.05
const FIELD := Rect2(160, 220, 300, 300)

var _room: GRushRoom = null
var _sparring: RefCounted = null
var _status := "Joining a duel room..."
var _local_paddle_y := 0.5
var _remote_paddle_y := 0.5
var _ball := Vector2(0.5, 0.5)
var _ball_velocity := Vector2(0.35, 0.22)
var _send_timer := 0.0
var _paddle_input := 0.0

var _label: Label


func _ready() -> void:
	_build_ui()
	if not GRush.is_available():
		_status = "Running outside GameRush."
		return
	if not OS.has_feature("web"):
		_sparring = GRush.mock_add_peer("Sparring Partner")
		if _sparring != null:
			_sparring.received.connect(_on_sparring_message)

	var joined: Dictionary = await GRush.net.join("duel")
	if not joined["ok"]:
		_status = "Could not join: %s" % joined["message"]
		return
	_room = joined["value"]
	_room.message_received.connect(_on_message)
	_room.peer_joined.connect(
		func(peer: Dictionary) -> void: _status = "Opponent joined: %s" % str(
			peer["display_name"] if peer["display_name"] != null else "guest"
		)
	)
	_room.peer_left.connect(func(index: int) -> void: _status = "Opponent left (peer %d)." % index)
	_room.transport_changed.connect(
		func(transport: String) -> void: _status = "Transport is now %s." % transport
	)
	_room.closed.connect(func(reason: String) -> void: _status = "Room closed: %s" % reason)
	_status = "You are the host." if _room.is_host() else "Waiting for the host."


func _exit_tree() -> void:
	if _sparring != null:
		GRush.mock_remove_peer(_sparring)
	if _room != null and not _room.is_closed:
		_room.leave()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 16)
	add_child(box)

	_label = Label.new()
	box.add_child(_label)

	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_hold_button("Up", -1.0))
	row.add_child(_hold_button("Down", 1.0))


func _hold_button(text: String, direction: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(80, 0)
	button.button_down.connect(func() -> void: _paddle_input = direction)
	button.button_up.connect(func() -> void: _paddle_input = 0.0)
	return button


func _process(delta: float) -> void:
	queue_redraw()
	if _room == null or _room.is_closed:
		return
	_local_paddle_y = clampf(_local_paddle_y + _paddle_input * delta, 0.0, 1.0)
	if _room.is_host():
		_simulate_ball(delta)

	_send_timer += delta
	if _send_timer < SEND_INTERVAL_SEC:
		return
	_send_timer = 0.0
	_room.send(_paddle_frame(_local_paddle_y), GRush.CHANNEL_UNRELIABLE, GRush.EVERYONE)
	if _room.is_host():
		var frame := PackedByteArray()
		frame.resize(9)
		frame.encode_u8(0, BALL_KIND)
		frame.encode_float(1, _ball.x)
		frame.encode_float(5, _ball.y)
		_room.send(frame, GRush.CHANNEL_UNRELIABLE, GRush.EVERYONE)


func _simulate_ball(delta: float) -> void:
	_ball += _ball_velocity * delta
	if _ball.y <= 0.0 or _ball.y >= 1.0:
		_ball_velocity.y = -_ball_velocity.y
		_ball.y = clampf(_ball.y, 0.0, 1.0)
	if _ball.x <= 0.0 or _ball.x >= 1.0:
		_ball_velocity.x = -_ball_velocity.x
		_ball.x = clampf(_ball.x, 0.0, 1.0)


func _on_message(message: Dictionary) -> void:
	var payload: PackedByteArray = message["payload"]
	if message["is_stale"] or payload.size() < 5:
		return
	var kind := payload.decode_u8(0)
	if kind == PADDLE_KIND:
		_remote_paddle_y = payload.decode_float(1)
		return
	if kind == BALL_KIND and payload.size() >= 9 and not _room.is_host():
		_ball = Vector2(payload.decode_float(1), payload.decode_float(5))


func _on_sparring_message(message: Dictionary) -> void:
	var payload: PackedByteArray = message["payload"]
	if payload.size() < 9 or payload.decode_u8(0) != BALL_KIND:
		return
	_sparring.send(
		_paddle_frame(payload.decode_float(5)), GRush.CHANNEL_UNRELIABLE, GRush.EVERYONE
	)


func _draw() -> void:
	draw_rect(FIELD, Color(1, 1, 1, 0.15))
	draw_rect(
		Rect2(FIELD.position.x + 6, FIELD.position.y + FIELD.size.y * _local_paddle_y - 20, 10, 40),
		Color.WHITE
	)
	draw_rect(
		Rect2(FIELD.end.x - 16, FIELD.position.y + FIELD.size.y * _remote_paddle_y - 20, 10, 40),
		Color.WHITE
	)
	draw_rect(
		Rect2(
			FIELD.position.x + FIELD.size.x * _ball.x - 5,
			FIELD.position.y + FIELD.size.y * _ball.y - 5,
			10,
			10
		),
		Color.WHITE
	)
	var lines := [_status]
	if _room != null:
		lines.append(
			"Peer %d / host %d / %s" % [_room.local_peer_id, _room.host_peer_id, _room.transport()]
		)
		lines.append("Server time: %d" % _room.server_time_ms())
		lines.append("Room code: %s" % _room.room_code)
	_label.text = "GameRush Duel\n" + "\n".join(lines)


static func _paddle_frame(value: float) -> PackedByteArray:
	var frame := PackedByteArray()
	frame.resize(5)
	frame.encode_u8(0, PADDLE_KIND)
	frame.encode_float(1, value)
	return frame
