class_name InventoryScreen
extends CanvasLayer
## The inventory screen ("inventory", I; Escape also closes it). The game
## keeps running behind it. Left: the 14 equipment slots; right: the bag
## grid (Inventory, 6 columns); below: the player's stats and gold.
##
## Double-click or right-click: a bag item is equipped (what it replaces
## takes its cell), an equipped item goes to the bag ("Bag full" when there
## is no room). Drag and drop: bag cells swap, a bag item dropped on a slot
## it fits is equipped there (and the reverse), the two ring slots swap,
## and anything dropped outside the window falls on the floor at the
## player's feet. Hovering an item shows its stats; for a bag item, also
## the difference from what is worn in its slot.
##
## While open the mouse belongs to the screen: a full-screen backdrop
## catches clicks (no attacks), and `player.mouse_blocked` stops right
## mouse from aiming / raising the shield.

signal opened
signal closed

const BAG_COLUMNS := 6
## Equipment slots in the left column, in two columns.
const EQUIP_LAYOUT: Array[StringName] = [&"head", &"neck", &"shoulders", &"back", &"chest", &"wrists",
	&"hands", &"legs", &"feet", &"trinket", &"ring_1", &"ring_2", &"main_hand", &"off_hand"]

@export var player: PlayerController
@export var inventory: Inventory
@export var equipment: Equipment
@export var stats: CharacterStats

var _equip_cells: Dictionary = {}
var _bag_cells: Array[ItemSlot] = []
var _backdrop: DropZone
var _bag_title: Label
var _stats_label: Label
var _gold_label: Label
var _window: Control
## The hover tooltip and the cell it is for.
var _tip: PanelContainer
var _tip_text: RichTextLabel
var _hovered: ItemSlot


## Anything dropped on it (outside the window) falls on the floor.
class DropZone extends ColorRect:
	var screen: InventoryScreen

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("from") is ItemSlot

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		screen.drop_to_floor(data["from"])


func _ready() -> void:
	layer = 5
	_build()
	visible = false
	if inventory:
		inventory.changed.connect(refresh)
	if equipment:
		equipment.changed.connect(func(_s: StringName, _i: GearDefinition, _p: GearDefinition) -> void: refresh())
	var profile := PlayerProfile.current()
	if profile:
		profile.gold_changed.connect(func(_total: int, _delta: int) -> void: refresh())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") or (visible and event.is_action_pressed("ui_cancel")):
		toggle()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	if player:
		player.mouse_blocked = true
	if _window.scale != Vector2.ONE:
		_window.pivot_offset = _window.size * 0.5
	refresh()
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_hovered = null
	_tip.hide()
	if player:
		player.mouse_blocked = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Scales the inventory window around its centre (debug menu slider).
func set_ui_scale(value: float) -> void:
	_window.pivot_offset = _window.size * 0.5
	_window.scale = Vector2.ONE * value


## The cell of an equipment slot / a bag index (tests).
func get_equip_cell(slot: StringName) -> ItemSlot:
	return _equip_cells.get(slot)


func get_bag_cell(index: int) -> ItemSlot:
	return _bag_cells[index] if index >= 0 and index < _bag_cells.size() else null


## Shows the current equipment, bag, stats and gold.
func refresh() -> void:
	if equipment:
		for slot: StringName in _equip_cells:
			(_equip_cells[slot] as ItemSlot).set_item(equipment.get_item(slot))
	if inventory:
		for i in _bag_cells.size():
			_bag_cells[i].set_item(inventory.item_at(i))
		_bag_title.text = "Bag  %d / %d" % [inventory.count(), inventory.capacity]
	_stats_label.text = DebugMenu.stats_text(stats)
	var profile := PlayerProfile.current()
	_gold_label.text = "Gold %d" % (profile.gold if profile else 0)
	_update_tip()


## Double-click / right-click on a cell: equip a bag item, or take an
## equipped one off into the bag.
func activate(cell: ItemSlot) -> void:
	if cell.item == null or inventory == null:
		return
	if cell.bag_index >= 0:
		inventory.equip_from(cell.bag_index)
	elif not inventory.unequip_to(cell.equip_slot):
		_notify("Bag full")


func can_drop(from: ItemSlot, to: ItemSlot) -> bool:
	if from == to or from.item == null:
		return false
	if to.bag_index >= 0:
		# Into the bag: an equipped item swaps only with one that fits its slot.
		return from.bag_index >= 0 or to.item == null or from.equip_slot in Equipment.slots_for(to.item)
	# Onto a slot: the dragged item has to fit it (rings swap between their slots).
	if not to.equip_slot in Equipment.slots_for(from.item):
		return false
	return from.bag_index >= 0 or to.item == null or from.equip_slot in Equipment.slots_for(to.item)


func drop(from: ItemSlot, to: ItemSlot) -> void:
	if not can_drop(from, to):
		return
	if from.bag_index >= 0 and to.bag_index >= 0:
		inventory.move(from.bag_index, to.bag_index)
	elif from.bag_index >= 0:
		inventory.equip_from(from.bag_index, to.equip_slot)
	elif to.bag_index >= 0:
		inventory.unequip_to(from.equip_slot, to.bag_index)
	else:
		# Slot to slot (the rings): swap.
		var moved := from.item
		var there := equipment.equip(moved, to.equip_slot)
		if there:
			equipment.equip(there, from.equip_slot)
		else:
			equipment.unequip(from.equip_slot)


## Drops the cell's item on the floor at the player's feet.
func drop_to_floor(cell: ItemSlot) -> void:
	if cell.item == null:
		return
	if cell.bag_index >= 0:
		inventory.drop(cell.bag_index)
	else:
		inventory.drop_equipped(cell.equip_slot)


## Tooltip text (BBCode) for a cell's item: name, slot, stats, and for a
## bag item the change from what is worn where it would go.
func tooltip_text_for(cell: ItemSlot) -> String:
	var item := cell.item
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % item.display_name)
	lines.append("[color=#b8ad8a]%s[/color]" % GearDefinition.SLOT_NAMES.get(item.slot, ""))
	for modifier in item.modifiers:
		lines.append(modifier.describe())
	if cell.bag_index >= 0 and equipment:
		var worn := equipment.get_item(equipment.slot_for(item))
		lines.append("")
		if worn:
			lines.append("[color=#b8ad8a]Instead of %s:[/color]" % worn.display_name)
		else:
			lines.append("[color=#b8ad8a]Slot is empty[/color]")
		var diff := compare(item, worn)
		if diff.is_empty():
			lines.append("No stat change")
		for line: Array in diff:
			lines.append("[color=%s]%s[/color]" % ["#7ee07e" if line[1] > 0.0 else "#ff7a6a", line[0]])
	lines.append("")
	lines.append("[color=#8a8a8a]%s[/color]" % ("Double-click: equip" if cell.bag_index >= 0 else "Double-click: to bag"))
	return "\n".join(lines)


## Shows the tooltip for `cell` (its item's stats) next to the mouse.
func hover(cell: ItemSlot) -> void:
	_hovered = cell
	_update_tip()


func unhover(cell: ItemSlot) -> void:
	if _hovered == cell:
		_hovered = null
		_tip.hide()


## The tooltip shown now ("" when none; tests).
func get_tooltip_text() -> String:
	return _tip_text.text if _tip.visible else ""


func _update_tip() -> void:
	if _hovered == null or _hovered.item == null or not visible:
		_tip.hide()
		return
	_tip_text.text = tooltip_text_for(_hovered)
	_tip.show()
	_tip.reset_size()
	_place_tip()


func _process(_delta: float) -> void:
	if _tip and _tip.visible:
		_place_tip()


## Next to the mouse, kept inside the screen.
func _place_tip() -> void:
	var view := get_viewport().get_visible_rect().size
	var at := get_viewport().get_mouse_position() + Vector2(18, 18)
	at.x = minf(at.x, view.x - _tip.size.x - 8.0)
	at.y = minf(at.y, view.y - _tip.size.y - 8.0)
	_tip.position = at


## Stat changes from wearing `item` instead of `worn` (null = nothing):
## [[text, signed amount], ...] per stat and kind that differs.
static func compare(item: GearDefinition, worn: GearDefinition) -> Array:
	var totals := {}
	for entry: Array in [[item, 1.0], [worn, -1.0]]:
		var gear: GearDefinition = entry[0]
		if gear == null:
			continue
		for modifier in gear.modifiers:
			var key := Vector2i(modifier.stat, modifier.kind)
			totals[key] = totals.get(key, 0.0) + modifier.value * entry[1]
	var result := []
	for key: Vector2i in totals:
		var amount: float = totals[key]
		if absf(amount) < 0.0001:
			continue
		var modifier := StatModifier.make(key.x as CharacterStats.Stat, key.y as StatModifier.Kind, amount)
		result.append([modifier.describe(), amount])
	return result


func _notify(text: String) -> void:
	get_tree().call_group(HUD.GROUP, &"notify", text)


func _build() -> void:
	_backdrop = DropZone.new()
	_backdrop.screen = self
	_backdrop.color = Color(0, 0, 0, 0.35)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	var window := PanelContainer.new()
	window.name = "Window"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.09, 0.95)
	style.set_border_width_all(1)
	style.border_color = Color(0.9, 0.75, 0.3, 0.6)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	window.add_theme_stylebox_override(&"panel", style)
	window.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	window.grow_horizontal = Control.GROW_DIRECTION_BOTH
	window.grow_vertical = Control.GROW_DIRECTION_BOTH
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.add_child(window)
	_window = window

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 10)
	window.add_child(rows)
	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override(&"font_size", 22)
	title.add_theme_color_override(&"font_color", Color(0.95, 0.8, 0.35))
	rows.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 24)
	rows.add_child(columns)

	var left := VBoxContainer.new()
	columns.add_child(left)
	left.add_child(_heading("Equipment"))
	var equip_grid := GridContainer.new()
	equip_grid.columns = 2
	equip_grid.add_theme_constant_override(&"h_separation", 6)
	equip_grid.add_theme_constant_override(&"v_separation", 6)
	left.add_child(equip_grid)
	for slot in EQUIP_LAYOUT:
		var cell := _cell()
		cell.equip_slot = slot
		cell.name = "Slot_%s" % slot
		cell.custom_minimum_size = Vector2(132, 52)
		equip_grid.add_child(cell)
		_equip_cells[slot] = cell

	var right := VBoxContainer.new()
	columns.add_child(right)
	_bag_title = _heading("Bag")
	right.add_child(_bag_title)
	var bag_grid := GridContainer.new()
	bag_grid.columns = BAG_COLUMNS
	bag_grid.add_theme_constant_override(&"h_separation", 6)
	bag_grid.add_theme_constant_override(&"v_separation", 6)
	right.add_child(bag_grid)
	for i in (inventory.capacity if inventory else 24):
		var cell := _cell()
		cell.bag_index = i
		cell.name = "Bag_%d" % i
		cell.custom_minimum_size = Vector2(80, 80)
		bag_grid.add_child(cell)
		_bag_cells.append(cell)
	_stats_label = Label.new()
	_stats_label.add_theme_color_override(&"font_color", Color(0.75, 0.85, 1.0))
	right.add_child(_stats_label)
	_gold_label = Label.new()
	_gold_label.add_theme_color_override(&"font_color", Color(1.0, 0.8, 0.3))
	right.add_child(_gold_label)

	_tip = PanelContainer.new()
	_tip.name = "Tooltip"
	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color = Color(0.04, 0.04, 0.05, 0.96)
	tip_style.set_border_width_all(1)
	tip_style.border_color = Color(0.9, 0.75, 0.3, 0.7)
	tip_style.set_corner_radius_all(4)
	tip_style.set_content_margin_all(8)
	_tip.add_theme_stylebox_override(&"panel", tip_style)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_text = RichTextLabel.new()
	_tip_text.bbcode_enabled = true
	_tip_text.fit_content = true
	_tip_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tip_text.custom_minimum_size = Vector2(220, 0)
	_tip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(_tip_text)
	_tip.hide()
	var hint := Label.new()
	hint.text = "Double-click or right-click: equip / to bag     Drag: move, equip     Drag outside: drop     I: close"
	hint.add_theme_font_size_override(&"font_size", 12)
	hint.add_theme_color_override(&"font_color", Color(0.6, 0.6, 0.6))
	rows.add_child(hint)
	add_child(_tip)  # Last: drawn over the window.


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.85, 0.78, 0.6))
	return label


func _cell() -> ItemSlot:
	var cell := ItemSlot.new()
	cell.screen = self
	cell.set_item(null)
	return cell
