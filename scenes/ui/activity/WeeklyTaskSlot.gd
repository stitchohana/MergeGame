class_name WeeklyTaskSlot extends HBoxContainer

@onready var name_label: Label = $NameLabel
@onready var progress_label: Label = $ProgressLabel
@onready var rewards_container: HBoxContainer = $RewardsContainer
@onready var claim_btn: Button = $ClaimButton
@onready var done_label: Label = $DoneLabel

var _quest_id: int = 0


func setup(quest: Dictionary, progress: Dictionary) -> void:
	_quest_id = quest.get("id", 0)
	name_label.text = quest.get("name", "#" + str(_quest_id))

	for child in rewards_container.get_children():
		child.queue_free()
	_display_rewards(quest)

	var current: int = progress.get("current_count", 0)
	var target: int = quest.get("target_count", 1)
	var completed: bool = progress.get("completed", false) or current >= target
	var claimed: bool = progress.get("claimed", false)

	progress_label.text = "%d/%d" % [current, target]
	claim_btn.visible = false
	done_label.visible = false
	claim_btn.disabled = false

	if claimed:
		progress_label.self_modulate = Color(0.3, 1, 0.3, 1)
		done_label.visible = true
	elif completed:
		progress_label.self_modulate = Color(1, 0.85, 0.2, 1)
		claim_btn.visible = true
		if not claim_btn.pressed.is_connected(_on_claim):
			claim_btn.pressed.connect(_on_claim)
	else:
		progress_label.self_modulate = Color(1, 1, 1, 0.6)


func _display_rewards(quest: Dictionary) -> void:
	var rewards: Dictionary = quest.get("rewards", {})
	if rewards.is_empty():
		return
	for t in rewards.get("tokens", []):
		var token_id: int = int(t.get("token", 0))
		var amount: int = int(t.get("amount", 0))
		if token_id <= 0 or amount <= 0:
			continue
		var slot := preload("res://scenes/ui/meridian/RewardSlot.tscn").instantiate() as RewardSlot
		rewards_container.add_child(slot)
		slot.setup(token_id, amount)
	for it in rewards.get("items", []):
		var item_id: int = int(it.get("id", 0))
		var count: int = int(it.get("count", 0))
		if item_id <= 0 or count <= 0:
			continue
		var slot := preload("res://scenes/ui/meridian/RewardSlot.tscn").instantiate() as RewardSlot
		rewards_container.add_child(slot)
		slot.setup(item_id, count)

func _on_claim() -> void:
	claim_btn.disabled = true
	claim_btn.text = "..."
	QuestService.claim_quest(_quest_id)
