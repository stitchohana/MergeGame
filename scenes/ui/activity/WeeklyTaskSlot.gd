class_name WeeklyTaskSlot extends Control

@onready var name_label: Label = $Content/Column/Header/NameLabel
@onready var progress_label: Label = $Content/Column/Header/ProgressLabel
@onready var progress_bar: ProgressBar = $Content/Column/ProgressBar
@onready var rewards_container: HBoxContainer = $Content/Column/Footer/RewardsContainer
@onready var claim_btn: Button = $Content/Column/Footer/ClaimButton
@onready var done_label: Label = $Content/Column/Footer/DoneLabel
@onready var state_label: Label = $Content/Column/Footer/StateLabel

var _quest_id: int = 0


func setup(quest: Dictionary, progress: Dictionary) -> void:
	_quest_id = int(quest.get("id", 0))
	name_label.text = str(quest.get("name", "#" + str(_quest_id)))

	for child in rewards_container.get_children():
		child.queue_free()
	_display_rewards(quest)

	var current: int = int(progress.get("current_count", 0))
	var target: int = maxi(1, int(quest.get("target_count", 1)))
	var completed: bool = bool(progress.get("completed", false)) or current >= target
	var claimed: bool = bool(progress.get("claimed", false))

	progress_label.text = "%d / %d" % [mini(current, target), target]
	progress_bar.value = clampf(float(current) / float(target) * 100.0, 0.0, 100.0)
	claim_btn.visible = false
	done_label.visible = false
	state_label.visible = false
	claim_btn.disabled = false
	claim_btn.text = "领取"

	if claimed:
		done_label.visible = true
	elif completed:
		claim_btn.visible = true
		if not claim_btn.pressed.is_connected(_on_claim):
			claim_btn.pressed.connect(_on_claim)
	else:
		state_label.visible = true


func _display_rewards(quest: Dictionary) -> void:
	var rewards_variant: Variant = quest.get("rewards", {})
	if not rewards_variant is Dictionary:
		return
	var rewards: Dictionary = rewards_variant
	if rewards.is_empty():
		return
	var token_rewards: Array = rewards.get("tokens", [])
	for token_reward: Dictionary in token_rewards:
		_add_reward_icon(int(token_reward.get("token", 0)), int(token_reward.get("amount", 0)))
	var item_rewards: Array = rewards.get("items", [])
	for item_reward: Dictionary in item_rewards:
		_add_reward_icon(int(item_reward.get("id", 0)), int(item_reward.get("count", 0)))


func _add_reward_icon(item_id: int, amount: int) -> void:
	if item_id <= 0 or amount <= 0:
		return
	var icon: WeeklyRewardIcon = preload("res://scenes/ui/activity/WeeklyRewardIcon.tscn").instantiate() as WeeklyRewardIcon
	rewards_container.add_child(icon)
	icon.setup(item_id, amount)

func _on_claim() -> void:
	claim_btn.disabled = true
	claim_btn.text = "..."
	QuestService.claim_quest(_quest_id)
