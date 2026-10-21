class_name EquipmentMenu
extends PanelContainer
## Debug panel for the player's equipment (opened from DebugMenu's
## "Equipment..." button): one picker per Equipment slot, offering "None"
## and every `catalog` item that fits it. Choosing equips it at once
## (Equipment saves it like any other change); the pickers follow changes
## made elsewhere (pickups).

signal closed

## The player's equipment (DebugMenu sets it).
@export var equipment: Equipment:
	set(value):
		if equipment and equipment.changed.is_connected(_on_changed):
			equipment.changed.disconnect(_on_changed)
		equipment = value
		if equipment and is_node_ready():
			equipment.changed.connect(_on_changed)
			sync()
## Items offered in the pickers.
@export var catalog: ItemCatalog

## Equipment slot -> its OptionButton ("None" + the items for that slot).
var _options: Dictionary = {}

@onready var _grid: GridContainer = %Grid


func _ready() -> void:
	hide()
	for slot: StringName in Equipment.SLOTS:
		var label := Label.new()
		label.text = Equipment.SLOT_NAMES.get(slot, String(slot))
		_grid.add_child(label)
		var option := OptionButton.new()
		option.name = "%sOption" % String(slot).to_pascal_case()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.add_item("None")
		option.set_item_metadata(0, null)
		if catalog:
			for item in catalog.items:
				if item and slot in Equipment.slots_for(item):
					option.add_item(item.display_name)
					option.set_item_metadata(option.item_count - 1, item)
		option.item_selected.connect(func(i: int) -> void: choose(slot, option.get_item_metadata(i)))
		_grid.add_child(option)
		_options[slot] = option
	%CloseButton.pressed.connect(close)
	# Mouse-only: a focused button would swallow Space (jump) as ui_accept.
	for button in find_children("*", "BaseButton", true, false):
		(button as BaseButton).focus_mode = Control.FOCUS_NONE
	if equipment:
		equipment.changed.connect(_on_changed)


func open() -> void:
	show()
	sync()


func close() -> void:
	hide()
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Equips `item` in `slot` (null empties it), as if chosen in the picker.
func choose(slot: StringName, item: GearDefinition) -> void:
	if equipment == null:
		return
	if item:
		equipment.equip(item, slot)
	else:
		equipment.unequip(slot)
	sync()


## The picker of `slot` (tests).
func get_option(slot: StringName) -> OptionButton:
	return _options.get(slot)


## Shows what is equipped now.
func sync() -> void:
	if equipment == null:
		return
	for slot: StringName in _options:
		var option: OptionButton = _options[slot]
		var worn := equipment.get_item(slot)
		option.select(0)
		for i in option.item_count:
			if option.get_item_metadata(i) == worn:
				option.select(i)


func _on_changed(_slot: StringName, _item: GearDefinition, _previous: GearDefinition) -> void:
	if visible:
		sync()
