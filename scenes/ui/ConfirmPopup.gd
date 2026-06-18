class_name ConfirmPopup extends BasePopup

signal confirmed()
signal cancelled()

@onready var message_label: Label = $Panel/MessageLabel
@onready var confirm_btn: Button = $Panel/ConfirmButton
@onready var cancel_btn: Button = $Panel/CancelButton

func _ready() -> void:
	if confirm_btn:
		confirm_btn.pressed.connect(_on_confirm)
	if cancel_btn:
		cancel_btn.pressed.connect(_on_cancel)

func setup(msg: String) -> void:
	if message_label:
		message_label.text = msg

func _on_confirm() -> void:
	confirmed.emit()
	UIManager.hide_popup(self)

func _on_cancel() -> void:
	cancelled.emit()
	UIManager.hide_popup(self)
