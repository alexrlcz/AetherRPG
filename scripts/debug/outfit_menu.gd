class_name OutfitMenu
extends PanelContainer
## Debug panel for dressing the player (opened from DebugMenu's "Outfits..."
## button): outfit, colour variant, hood and pauldrons, and the gear worn in
## each slot (helmet, cloak, boots, shield from `gear_items`), previewed live. Edits
## the appearance the AppearanceComponent holds (DebugMenu's copy; nothing
## is saved).

signal closed

## The player's appearance to dress (DebugMenu sets it).
@export var appearance_component: AppearanceComponent
## Gear offered in the slot pickers.
@export var gear_items: Array[GearDefinition] = []

@onready var _outfit: OptionButton = %OutfitOption
@onready var _variant: OptionButton = %VariantOption
@onready var _hood: CheckBox = %HoodCheck
@onready var _pauldrons: CheckBox = %PauldronsCheck
## Slot -> its OptionButton ("None" + the gear for that slot).
@onready var _slot_options := {
	GearDefinition.Slot.HEAD: %HeadOption as OptionButton,
	GearDefinition.Slot.BACK: %BackOption as OptionButton,
	GearDefinition.Slot.FEET: %FeetOption as OptionButton,
	GearDefinition.Slot.OFF_HAND: %OffHandOption as OptionButton,
}


func _ready() -> void:
	hide()
	_outfit.clear()
	for id in CharacterAppearance.OUTFITS:
		_outfit.add_item(id)
	_outfit.item_selected.connect(func(i: int) -> void:
		_edit(func(a: CharacterAppearance) -> void:
			a.outfit = CharacterAppearance.OUTFITS[i]
			a.outfit_variant = 0))
	_variant.item_selected.connect(func(i: int) -> void:
		_edit(func(a: CharacterAppearance) -> void: a.outfit_variant = i))
	_hood.toggled.connect(func(on: bool) -> void:
		_edit(func(a: CharacterAppearance) -> void: a.hood = on))
	_pauldrons.toggled.connect(func(on: bool) -> void:
		_edit(func(a: CharacterAppearance) -> void: a.pauldrons = on))
	for slot: GearDefinition.Slot in _slot_options:
		var option: OptionButton = _slot_options[slot]
		option.clear()
		option.add_item("None")
		option.set_item_metadata(0, null)
		for item in gear_items:
			if item.slot == slot:
				option.add_item(item.display_name)
				option.set_item_metadata(option.item_count - 1, item)
		option.item_selected.connect(func(i: int) -> void:
			var item: GearDefinition = option.get_item_metadata(i)
			_edit(func(a: CharacterAppearance) -> void: a.set_gear(slot, item)))
	%CloseButton.pressed.connect(close)
	# Mouse-only: a focused button would swallow Space (jump) as ui_accept.
	for button in find_children("*", "BaseButton", true, false):
		(button as BaseButton).focus_mode = Control.FOCUS_NONE


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


## Wears `item` in its slot (or clears `slot` with null), as if chosen in
## the menu (debug / tests).
func choose_gear(slot: GearDefinition.Slot, item: GearDefinition) -> void:
	var option: OptionButton = _slot_options[slot]
	for i in option.item_count:
		if option.get_item_metadata(i) == item:
			option.select(i)
			option.item_selected.emit(i)
			return


## Picks the outfit by id (debug / tests), as if chosen in the menu.
func choose_outfit(id: String) -> void:
	var index := CharacterAppearance.OUTFITS.find(id)
	if index >= 0:
		_outfit.select(index)
		_outfit.item_selected.emit(index)


## Shows the appearance's current values (also after other edits).
func sync() -> void:
	var a := _appearance()
	if a == null:
		return
	_outfit.select(maxi(CharacterAppearance.OUTFITS.find(a.outfit), 0))
	_variant.clear()
	for variant_name in a.variant_names():
		_variant.add_item(variant_name)
	_variant.disabled = _variant.item_count < 2
	if _variant.item_count > 0:
		_variant.select(clampi(a.outfit_variant, 0, _variant.item_count - 1))
	var pieces: Array = CharacterAppearance.OUTFIT_PIECES.get(a.outfit, [])
	_hood.disabled = not pieces.has("hood")
	_pauldrons.disabled = not pieces.has("pauldrons")
	_hood.set_pressed_no_signal(a.hood)
	_pauldrons.set_pressed_no_signal(a.pauldrons)
	for slot: GearDefinition.Slot in _slot_options:
		var option: OptionButton = _slot_options[slot]
		var worn := a.gear_in(slot)
		for i in option.item_count:
			if option.get_item_metadata(i) == worn:
				option.select(i)


func _appearance() -> CharacterAppearance:
	return appearance_component.appearance if appearance_component else null


func _edit(change: Callable) -> void:
	var a := _appearance()
	if a == null:
		return
	change.call(a)
	appearance_component.apply(a)
	sync()
