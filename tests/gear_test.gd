extends "res://tests/combat_test.gd"
## Headless gear checks (the helmet) on the real player: the item, how it is
## built and skinned, other bodies, and the Outfits & gear panel (reuses the
## combat test's arena and helpers).
##   godot --headless --path . -s res://tests/gear_test.gd
## Exit code 0 = every check passed.

const HELMET := preload("res://resources/items/gear/helmet_fantasy.tres")


func _initialize() -> void:
	await process_frame
	PlayerProfile.current().save_path = ""
	test_items()
	await test_wearing()
	await test_female_and_off()
	await test_menu()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_items() -> void:
	print("1. The helmet item")
	check(HELMET.kind == ItemDefinition.Kind.GEAR and not HELMET.auto_collect,
		"%s is gear, picked up with the interact key" % HELMET.display_name)
	check(HELMET.slot == GearDefinition.Slot.HEAD, "it goes on the head")


func test_wearing() -> void:
	print("2. Wearing the helmet: mesh, skinning, hidden hair")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var component := _component(player)
	_wear(component, [HELMET])
	var names := _names(component)
	check(names.has("Gear_HelmetFantasy"), "Gear_HelmetFantasy on the rig")
	check(not names.any(func(n: String) -> bool: return n.begins_with("Hair_") and n != "Hair_Beard"),
		"the helmet hides the hair")
	check(_binds(component, "Gear_HelmetFantasy") == ["Head"], "the helmet rides the head bone")
	await clear_arena()


func test_female_and_off() -> void:
	print("3. The helmet fits other bodies; taking it off restores the hair")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var component := _component(player)
	var look := _wear(component, [HELMET])
	look.body = CharacterAppearance.Body.FEMALE
	component.apply(look)
	check(_names(component).has("Gear_HelmetFantasy"), "the helmet is built on the female body")
	look.set_gear(GearDefinition.Slot.HEAD, null)
	component.apply(look)
	var names := _names(component)
	check(not names.has("Gear_HelmetFantasy") and names.any(func(n: String) -> bool: return n.begins_with("Hair_")),
		"helmet off: no mesh, hair back")
	await clear_arena()


func test_menu() -> void:
	print("4. The Equipment panel puts the helmet on and off")
	var main: Node3D = preload("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await ticks(10)
	var menu := main.get_node("DebugMenu") as DebugMenu
	var panel := menu.get_node("EquipmentMenu") as EquipmentMenu
	var component := main.get_node("Player/Appearance") as AppearanceComponent
	(menu.get_node("%EquipmentButton") as Button).pressed.emit()
	var head := panel.get_option(&"head")
	check(head.get_item_text(1) == HELMET.display_name, "the head slot offers %s" % head.get_item_text(1))
	check(panel.get_option(&"back").item_count == 1, "the cloak slot offers only None")
	panel.choose(&"head", HELMET)
	check(component.appearance.gear_in(GearDefinition.Slot.HEAD) == HELMET and _names(component).has("Gear_HelmetFantasy"),
		"choosing it dresses the player")
	panel.choose(&"head", null)
	check(component.appearance.gear_in(GearDefinition.Slot.HEAD) == null and not _names(component).has("Gear_HelmetFantasy"),
		"None takes the helmet off")
	main.queue_free()
	await ticks(2)


func _wear(component: AppearanceComponent, items: Array) -> CharacterAppearance:
	var look := component.appearance.duplicate() as CharacterAppearance
	for item: GearDefinition in items:
		look.set_gear(item.slot, item)
	component.apply(look)
	return look


func _component(player: Node) -> AppearanceComponent:
	return player.get_node("Appearance") as AppearanceComponent


func _names(component: AppearanceComponent) -> Array:
	return component.get_parts().filter(func(m: MeshInstance3D) -> bool: return is_instance_valid(m)) \
		.map(func(m: MeshInstance3D) -> String: return String(m.name))


func _part(component: AppearanceComponent, part_name: String) -> MeshInstance3D:
	for part in component.get_parts():
		if is_instance_valid(part) and part.name == part_name:
			return part
	return null


func _binds(component: AppearanceComponent, part_name: String) -> Array:
	var skin := _part(component, part_name).skin
	var names := []
	for i in skin.get_bind_count():
		names.append(String(skin.get_bind_name(i)))
	return names
