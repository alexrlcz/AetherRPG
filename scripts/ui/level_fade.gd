class_name LevelFade
extends CanvasLayer
## Full-screen fade with a title ("Level 3") that hides a level swap.
##   await fade.cover("Level 3")   # to black
##   ... swap the level ...
##   await fade.reveal()           # back to the game

@export var duration: float = 0.35

var _rect: ColorRect
var _label: Label
var _tween: Tween


func _ready() -> void:
	layer = 50
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 40)
	_label.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.6))
	_label.modulate.a = 0.0
	_rect.add_child(_label)


## Fades to black showing `title`.
func cover(title: String = "") -> void:
	_label.text = title
	await _fade(1.0)


## Black at once (the first level, before anything has been shown).
func cover_now(title: String = "") -> void:
	if _tween:
		_tween.kill()
	_label.text = title
	_rect.color.a = 1.0
	_label.modulate.a = 1.0


## Fades back to the game.
func reveal() -> void:
	await _fade(0.0)


func is_covered() -> bool:
	return _rect.color.a > 0.99


func _fade(to: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel()
	_tween.tween_property(_rect, "color:a", to, duration)
	_tween.tween_property(_label, "modulate:a", to, duration)
	await _tween.finished
