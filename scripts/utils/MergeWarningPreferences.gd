extends RefCounted

# Local UI preference; use Beijing calendar days regardless of device timezone.
static var storage_path: String = "user://merge_warning_preferences.cfg"


static func day_key(unix_time: float = Time.get_unix_time_from_system()) -> String:
	return Time.get_date_string_from_unix_time(int(unix_time) + 8 * 3600)


static func is_suppressed_today(unix_time: float = Time.get_unix_time_from_system()) -> bool:
	var preferences: ConfigFile = ConfigFile.new()
	if preferences.load(storage_path) != OK:
		return false
	return str(preferences.get_value("merge", "skip_warning_date", "")) == day_key(unix_time)


static func suppress_today(unix_time: float = Time.get_unix_time_from_system()) -> void:
	var preferences: ConfigFile = ConfigFile.new()
	preferences.load(storage_path)
	preferences.set_value("merge", "skip_warning_date", day_key(unix_time))
	if preferences.save(storage_path) != OK:
		push_warning("无法保存今日越境合成提示设置")
