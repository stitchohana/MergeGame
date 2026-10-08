class_name HomeActivityCard extends Button

@onready var activity_icon: TextureRect = $Content/IconFrame/ActivityIcon
@onready var activity_mark: Label = $Content/IconFrame/ActivityMark
@onready var name_label: Label = $Content/NameLabel

var _activity: Dictionary = {}


func _ready() -> void:
	pressed.connect(_on_pressed)
	GameState.card_collection_changed.connect(_refresh_collection_badge)


func setup(activity: Dictionary) -> void:
	_activity = activity.duplicate(true)
	var activity_name: String = str(activity.get("name", "活动"))
	var widget: String = str(activity.get("widget", ""))
	name_label.text = activity_name
	tooltip_text = activity_name
	if widget == "WeeklyActivityEntry":
		activity_icon.texture = load("res://assets/ui/weekly/weekly_entry.png") as Texture2D
		activity_icon.show()
		activity_mark.hide()
	else:
		activity_mark.text = "日" if int(activity.get("cycle", -1)) == 1 else "活"
		activity_icon.hide()
		activity_mark.show()
	_refresh_collection_badge()


func _refresh_collection_badge() -> void:
	if str(_activity.get("widget", "")) != "CardCollection":
		return
	var total: int = 0
	var claimable: bool = false
	for collection: Dictionary in ConfigDatabase.card_collection.get("collections", []):
		if int(collection.get("activity_id", 0)) != int(_activity.get("id", 0)):
			continue
		var progress: Dictionary = GameState.get_card_collection_progress(int(collection.collection_id))
		for count: Variant in progress.get("packs", {}).values():
			total += int(count)
		for card_set: Dictionary in ConfigDatabase.card_collection.get("card_sets", []):
			if int(card_set.collection_id) != int(collection.collection_id) or card_set.set_id in progress.get("claimed_sets", []):
				continue
			var complete: bool = true
			var owned: Dictionary = progress.get("cards", {})
			for card: Dictionary in ConfigDatabase.card_collection.get("cards", []):
				if int(card.set_id) == int(card_set.set_id) and int(owned.get(str(card.card_id), owned.get(int(card.card_id), 0))) <= 0:
					complete = false
			claimable = claimable or complete
	activity_mark.text = "领" if claimable else (str(total) if total > 0 else "册")
	tooltip_text = "卡组奖励可领取" if claimable else "待开卡包 ×%d" % total


func _on_pressed() -> void:
	var activity_id: int = int(_activity.get("id", 0))
	var widget: String = str(_activity.get("widget", ""))
	if widget == "CardCollection":
		var collection_panel := preload("res://scenes/ui/activity/CardCollectionPanel.tscn").instantiate()
		UIManager.show_popup(collection_panel)
		collection_panel.setup(activity_id)
		CloudService.fetch_state()
		return
	if widget == "BattlePass":
		var battle_pass := preload("res://scenes/ui/activity/BattlePassPanel.tscn").instantiate() as BattlePassPanel
		UIManager.show_popup(battle_pass)
		battle_pass.setup(activity_id)
		return
	if widget == "WeeklyActivityEntry" or not ConfigDatabase.get_weekly_tasks(activity_id).is_empty():
		var panel := preload("res://scenes/ui/activity/WeeklyActivityPanel.tscn").instantiate() as WeeklyActivityPanel
		UIManager.show_popup(panel)
		panel.setup(activity_id)
		CloudService.fetch_state()
		return
	var info_popup := preload("res://scenes/ui/activity/ActivityInfoPopup.tscn").instantiate() as ActivityInfoPopup
	UIManager.show_popup(info_popup)
	info_popup.setup(_activity)
