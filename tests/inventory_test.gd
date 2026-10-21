extends "res://tests/combat_test.gd"
## Headless inventory checks: the bag (cells, full, moving), equipping from
## it and taking off into it, dropping to the floor, saving and loading
## through the profile, and the inventory screen in the real Main scene
## (I toggles it, it owns the mouse, cells show the items, double-click /
## right-click, the drag-and-drop rules, the tooltip's comparison, "Bag
## full"), plus the fullscreen setting.
##   godot --headless --path . -s res://tests/inventory_test.gd
## Exit code 0 = every check passed.

const G := "res://resources/items/gear/"


func _initialize() -> void:
	await process_frame
	PlayerProfile.current().save_path = ""
	await test_bag()
	await test_equip_and_unequip()
	await test_drop()
	await test_persistence()
	await test_screen()
	test_fullscreen()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_bag() -> void:
	print("1. The bag: 24 cells, first free, full, moving")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var bag := player.inventory
	check(bag.capacity == 24 and bag.count() == 0 and bag.first_free() == 0, "24 empty cells")
	check(bag.add(_item("ring_might")) and bag.add(_item("helmet_fantasy")) and bag.count() == 2, "items go in")
	bag.move(0, 5)
	check(bag.item_at(0) == null and bag.item_at(5) == _item("ring_might"), "moved to an empty cell")
	bag.move(5, 1)
	check(bag.item_at(1) == _item("ring_might") and bag.item_at(5) == _item("helmet_fantasy"), "moved onto an item: swapped")
	for i in 22:
		bag.add(_item("amulet_vigor"))
	check(bag.is_full() and not bag.add(_item("charm_swiftness")), "full: nothing more goes in")
	check(bag.remove_at(1) == _item("ring_might") and bag.first_free() == 1, "removing frees its cell")
	await clear_arena()


func test_equip_and_unequip() -> void:
	print("2. Equipping from the bag and taking off into it")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var bag := player.inventory
	var equipment := player.equipment
	bag.add(_item("jerkin_ranger"))
	check(bag.equip_from(0) and equipment.get_item(&"chest") == _item("jerkin_ranger")
		and bag.item_at(0) == _item("tunic_peasant"), "the jerkin is worn, the tunic takes its cell")
	bag.add(_item("ring_might"))
	check(bag.equip_from(1) and equipment.get_item(&"ring_1") == _item("ring_might") and bag.item_at(1) == null,
		"into an empty slot: the cell empties")
	check(not bag.equip_from(0, &"head"), "not into a slot it doesn't fit")
	check(bag.unequip_to(&"feet") and equipment.get_item(&"feet") == null and bag.item_at(1) == _item("shoes_peasant"),
		"taken off into the first free cell")
	check(bag.unequip_to(&"chest", 0) and equipment.get_item(&"chest") == _item("tunic_peasant")
		and bag.item_at(0) == _item("jerkin_ranger"), "onto a cell holding a chest piece: swapped")
	check(not bag.unequip_to(&"legs", 1), "onto a cell whose item doesn't fit the slot: refused")
	for i in bag.capacity:
		bag.add(_item("amulet_vigor"))
	check(not bag.unequip_to(&"legs") and equipment.get_item(&"legs") != null, "full bag: stays on")
	await clear_arena()


func test_drop() -> void:
	print("3. Dropping to the floor")
	await make_arena()
	var player := spawn_player(Vector3(2, 0, 1))
	await ticks(2)
	player.inventory.add(_item("ring_might"))
	var pickup := player.inventory.drop(0)
	check(pickup != null and pickup.item == _item("ring_might") and player.inventory.item_at(0) == null,
		"a bag item becomes a pickup")
	var worn := player.inventory.drop_equipped(&"chest")
	check(worn != null and worn.item == _item("tunic_peasant") and player.equipment.get_item(&"chest") == null,
		"an equipped item too")
	await ticks(60)
	check(pickup.global_position.distance_to(player.global_position) < 3.0 and pickup.can_interact(),
		"at the player's feet, ready to pick up again")
	await clear_arena()


func test_persistence() -> void:
	print("4. The bag is saved in the profile and restored, cells in place")
	var profile := PlayerProfile.current()
	var path := "user://inventory_test_profile.json"
	profile.save_path = path
	profile.equipment = {}
	profile.inventory = []
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	player.inventory.add(_item("ring_might"))
	player.inventory.add(_item("boots_ranger"))
	player.inventory.move(1, 7)
	await clear_arena()
	profile.inventory = []
	profile.load_profile()
	check(profile.inventory.size() == 24 and String(profile.inventory[7]).ends_with("boots_ranger.tres"),
		"written to disk")
	await make_arena()
	var again := spawn_player(Vector3.ZERO)
	await ticks(2)
	check(again.inventory.item_at(0) == _item("ring_might") and again.inventory.item_at(7) == _item("boots_ranger")
		and again.inventory.count() == 2, "a new player has the same bag")
	await clear_arena()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	profile.save_path = ""
	profile.equipment = {}
	profile.inventory = []


func test_screen() -> void:
	print("5. The inventory screen")
	var main: Node3D = preload("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await ticks(10)
	var screen := main.get_node("InventoryScreen") as InventoryScreen
	var player := main.get_node("Player") as PlayerController
	var hud := main.get_node("HUD") as HUD
	check(not screen.is_open(), "closed at the start")
	_press("inventory")
	await ticks(2)
	check(screen.is_open() and player.mouse_blocked, "I opens it; it owns the mouse")
	check(screen.get_equip_cell(&"chest").get_item_label() == "Peasant Tunic"
		and screen.get_equip_cell(&"main_hand").get_item_label() == "Sword", "the slots show what is worn")
	player.inventory.add(_item("jerkin_ranger"))
	player.inventory.add(_item("ring_might"))
	await ticks(1)
	check(screen.get_bag_cell(0).get_item_label() == "Ranger Jerkin", "the bag cells show the bag")
	var tip := screen.tooltip_text_for(screen.get_bag_cell(0))
	check("Instead of Peasant Tunic" in tip and "+6 Armor" in tip, "the tooltip compares with what is worn")
	check(InventoryScreen.compare(_item("ring_might"), null)[0][0] == "+10% Damage"
		and InventoryScreen.compare(_item("tunic_peasant"), _item("tunic_peasant")).is_empty(), "compare()")
	# Clicks belong to the screen: no attack, no aim.
	Input.action_press("aim")
	await ticks(2)
	check(not player.is_aiming, "right mouse doesn't aim while it is open")
	Input.action_release("aim")
	_double_click(screen.get_bag_cell(0))
	await ticks(1)
	check(player.equipment.get_item(&"chest") == _item("jerkin_ranger")
		and screen.get_bag_cell(0).get_item_label() == "Peasant Tunic", "double-click equips; the tunic takes the cell")
	_right_click(screen.get_equip_cell(&"chest"))
	await ticks(1)
	check(player.equipment.get_item(&"chest") == null and player.inventory.count() == 3, "right-click on a slot: to the bag")
	# Drag and drop rules.
	var tunic_cell := screen.get_bag_cell(0)
	var ring_cell := screen.get_bag_cell(1)
	check(screen.can_drop(tunic_cell, screen.get_equip_cell(&"chest"))
		and not screen.can_drop(tunic_cell, screen.get_equip_cell(&"head")), "a bag item drops only on slots it fits")
	screen.drop(ring_cell, screen.get_equip_cell(&"ring_2"))
	check(player.equipment.get_item(&"ring_2") == _item("ring_might"), "dropped on ring 2: equipped there")
	screen.drop(screen.get_equip_cell(&"ring_2"), screen.get_equip_cell(&"ring_1"))
	check(player.equipment.get_item(&"ring_1") == _item("ring_might") and player.equipment.get_item(&"ring_2") == null,
		"ring 2 dragged to ring 1: moved")
	screen.drop(screen.get_bag_cell(0), screen.get_bag_cell(10))
	check(player.inventory.item_at(10) == _item("tunic_peasant"), "bag to bag: moved")
	screen.drop(screen.get_equip_cell(&"feet"), screen.get_bag_cell(12))
	check(player.inventory.item_at(12) == _item("shoes_peasant") and player.equipment.get_item(&"feet") == null,
		"slot to bag: taken off")
	screen.drop_to_floor(screen.get_bag_cell(12))
	await ticks(2)
	check(player.inventory.item_at(12) == null and main.get_tree().get_nodes_in_group(Pickup.GROUP).any(
		func(p: Pickup) -> bool: return p.item == _item("shoes_peasant")), "dragged outside: dropped on the floor")
	for i in player.inventory.capacity:
		player.inventory.add(_item("amulet_vigor"))
	_right_click(screen.get_equip_cell(&"legs"))
	await ticks(1)
	check(player.equipment.get_item(&"legs") != null and hud.get_notice() == "Bag full", "full bag: \"Bag full\"")
	_press("inventory")
	await ticks(2)
	check(not screen.is_open() and not player.mouse_blocked, "I closes it")
	_press("inventory")
	await ticks(1)
	_press("ui_cancel")
	await ticks(1)
	check(not screen.is_open(), "Escape closes it too")
	main.queue_free()
	await ticks(2)


func test_fullscreen() -> void:
	print("6. Fullscreen")
	check(ProjectSettings.get_setting("display/window/size/mode") == DisplayServer.WINDOW_MODE_MAXIMIZED,
		"the game starts in a maximized window")
	check(not InputMap.action_get_events("toggle_fullscreen").is_empty(), "F11 toggles it")


func _item(id: String) -> GearDefinition:
	return load(G + id + ".tres")


func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _double_click(cell: ItemSlot) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = true
	cell._gui_input(event)


func _right_click(cell: ItemSlot) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	cell._gui_input(event)
