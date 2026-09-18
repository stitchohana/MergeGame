extends RefCounted
class_name TimeUtils

## Format a countdown using at most the two largest non-zero time units.
## Values are rounded up so a positive fractional second never displays 0秒.
static func format_countdown(seconds: float) -> String:
	var total_seconds: int = maxi(0, int(ceil(seconds)))
	var units: Array[Dictionary] = [
		{"value": int(total_seconds / 86400), "suffix": "日"},
		{"value": int((total_seconds % 86400) / 3600), "suffix": "时"},
		{"value": int((total_seconds % 3600) / 60), "suffix": "分"},
		{"value": total_seconds % 60, "suffix": "秒"},
	]
	var parts: Array[String] = []
	for unit: Dictionary in units:
		var value: int = int(unit.get("value", 0))
		if value <= 0:
			continue
		parts.append("%d%s" % [value, str(unit.get("suffix", ""))])
		if parts.size() >= 2:
			break
	if parts.is_empty():
		return "0秒"
	return "".join(parts)
