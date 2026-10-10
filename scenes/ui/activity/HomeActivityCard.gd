class_name HomeActivityCard extends Button

@onready var activity_icon: TextureRect = $Content/IconFrame/ActivityIcon
@onready var activity_mark: Label = $Content/IconFrame/ActivityMark
@onready var name_label: Label = $Content/NameLabel
@onready var status_label: Label = $Content/StatusLabel

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
	if widget == "StairClimb":
		activity_mark.text = "梯"
		status_label.text = "● 比拼中" if bool(activity.get("active", false)) else "查看结算"
		tooltip_text = "完成订单累积积分，查看本组排名与奖励"
	_refresh_collection_badge()


func _refresh_collection_badge() -> void:
	if str(_activity.get("widget", "")) != "CardCollection":
		return
	activity_mark.text = "册"
	tooltip_text = "查看卡片收集与卡组奖励"


func _on_pressed() -> void:
	if RequirementList.is_scroll_click_cancelled(self):
		return
	var activity_id: int = int(_activity.get("id", 0))
	var widget: String = str(_activity.get("widget", ""))
	if widget == "StairClimb":
		var stair_panel := preload("res://scenes/ui/activity/StairClimbPanel.tscn").instantiate()
		UIManager.show_popup(stair_panel)
		stair_panel.setup(activity_id)
		return
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
