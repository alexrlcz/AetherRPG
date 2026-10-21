class_name ItemSlot
extends PanelContainer
## One cell of the inventory screen: a bag cell (`bag_index` >= 0) or an
## equipment slot (`equip_slot`). Shows its item's name (no icons yet) on a
## colour for the kind of item; an empty equipment slot shows its slot
## name. Double-click or right-click asks the screen to equip / take off;
## drag and drop goes through the screen's can_drop() / drop(); hovering
## shows the screen's tooltip (stats, compared with what is worn).

## Background colours per item slot (dimmed when empty).
const KIND_COLORS := {
	GearDefinition.Slot.MAIN_HAND: Color(0.45, 0.22, 0.2), GearDefinition.Slot.OFF_HAND: Color(0.4, 0.3, 0.18),
	GearDefinition.Slot.RING: Color(0.42, 0.34, 0.12), GearDefinition.Slot.NECK: Color(0.42, 0.34, 0.12),
	GearDefinition.Slot.TRINKET: Color(0.36, 0.22, 0.42),
}
const ARMOR_COLOR := Color(0.2, 0.3, 0.38)
const EMPTY_COLOR := Color(0.1, 0.1, 0.12, 0.9)

var screen: InventoryScreen
var bag_index: int = -1
var equip_slot: StringName = &""
var item: GearDefinition

var _style := StyleBoxFlat.new()
var _label := Label.new()
var _caption := Label.new()


func _init() -> void:
	custom_minimum_size = Vector2(80, 64)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style.set_corner_radius_all(4)
	_style.set_border_width_all(1)
	_style.border_color = Color(0.9, 0.75, 0.3, 0.35)
	_style.set_content_margin_all(4)
	add_theme_stylebox_override(&"panel", _style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 0)
	add_child(box)
	for label in [_caption, _label]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD  # Never inside a word ("Greatswor-d").
		box.add_child(label)
	_caption.add_theme_font_size_override(&"font_size", 11)
	_caption.add_theme_color_override(&"font_color", Color(0.75, 0.7, 0.55))
	_label.add_theme_font_size_override(&"font_size", 12)
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func set_item(new_item: GearDefinition) -> void:
	item = new_item
	_caption.text = Equipment.SLOT_NAMES.get(equip_slot, "") if equip_slot != &"" else ""
	_caption.visible = equip_slot != &""
	_label.text = item.display_name if item else ""
	_style.bg_color = EMPTY_COLOR if item == null else KIND_COLORS.get(item.slot, ARMOR_COLOR)
	# Any text turns Godot's tooltip on; the content is _make_custom_tooltip().
	tooltip_text = item.display_name if item else ""


func get_item_label() -> String:
	return _label.text


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or item == null:
		return
	if (click.button_index == MOUSE_BUTTON_LEFT and click.double_click) or click.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		screen.activate(self)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	var preview := Label.new()
	preview.text = item.display_name
	preview.add_theme_font_size_override(&"font_size", 14)
	set_drag_preview(preview)
	return {"from": self}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from") is ItemSlot and screen.can_drop(data["from"], self)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	screen.drop(data["from"], self)


func _make_custom_tooltip(_for_text: String) -> Object:
	return screen.make_tooltip(self) if item else null
