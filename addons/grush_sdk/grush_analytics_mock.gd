extends RefCounted

# GameRush と同じ検査をして、通ったイベントを1件ずつ出力し、直近の分を GRushMock.analytics_events に持つ。
# どこへも送らない。

const Rules := preload("res://addons/grush_sdk/grush_analytics_rules.gd")

const MAX_EVENTS := 200

# GameRush と同じく、拒んだ理由ごとに1回だけ警告する。
var _warned := {}


func is_available() -> bool:
	return true


func log_event(kind: String, params: Dictionary) -> bool:
	var result := Rules.sanitize(kind, params)
	if not result["ok"]:
		var reason: String = result["reason"]
		if not _warned.has(reason):
			_warned[reason] = true
			push_warning("[GRushMock] analytics event rejected (%s)." % reason)
		return false
	var event: Dictionary = result["event"]
	GRushMock.analytics_events.append(event)
	while GRushMock.analytics_events.size() > MAX_EVENTS:
		GRushMock.analytics_events.pop_front()
	print("[GRushMock] analytics %s" % JSON.stringify(event))
	return true
