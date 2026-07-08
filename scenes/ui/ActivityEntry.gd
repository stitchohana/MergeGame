class_name ActivityEntry extends Control

signal pressed()

@onready var btn: Button = $Button


func _ready() -> void:
	btn.pressed.connect(func(): pressed.emit())
