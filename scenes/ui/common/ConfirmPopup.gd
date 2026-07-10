class_name ConfirmPopup extends BasePopup

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var message_label: Label = $Panel/VBox/MessageLabel
@onready var confirm_btn: Button = $Panel/VBox/BtnBox/ConfirmButton
@onready var cancel_btn: Button = $Panel/VBox/BtnBox/CancelButton

var _on_confirmed: Callable = Callable()


func setup(title: String, message: String, on_confirmed: Callable) -> void:
	title_label.text = title
	message_label.text = message
	_on_confirmed = on_confirmed
	if not confirm_btn.pressed.is_connected(_on_confirm):
		confirm_btn.pressed.connect(_on_confirm)
	if not cancel_btn.pressed.is_connected(_on_cancel):
		cancel_btn.pressed.connect(_on_cancel)


func _on_confirm() -> void:
	if _on_confirmed.is_valid():
		_on_confirmed.call()
	UIManager.hide_popup(self)


func _on_cancel() -> void:
	UIManager.hide_popup(self)
