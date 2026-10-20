extends "res://tests/combat_test.gd"
## Headless outfit checks on the real player (reuses the combat test's
## helpers), then the Outfits panel in the real Main scene.
##   godot --headless --path . -s res://tests/outfit_test.gd
## Exit code 0 = every check passed.


func _initialize() -> void:
	await process_frame
	PlayerProfile.current().save_path = ""
	await test_ranger()
	await test_pieces_and_colours()
	await test_female_and_none()
	await test_menu()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_ranger() -> void:
	print("1. A ranger outfit: head-only body, outfit meshes, hood hides the hair, skin matches")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var component := _component(player)
	var full_triangles := _triangles(_part(component, "SuperHero_Male"))
	var look := _look(component)
	look.outfit = "Ranger"
	look.skin_texture = CharacterAppearance.SkinTexture.LIGHT
	look.skin_tint = Color(0.9, 0.8, 0.7)
	look.beard = true
	component.apply(look)
	var names := _names(component)
	check(names.has("Male_Ranger_Body") and names.has("Male_Ranger_Legs") and names.has("Male_Ranger_Feet_Boots"),
		"the ranger's meshes are on the rig")
	var body := _part(component, "SuperHero_Male")
	var head_triangles := _triangles(body)
	check(head_triangles > 200 and head_triangles < full_triangles * 0.4,
		"under clothes only the head is left (%d of %d triangles)" % [head_triangles, full_triangles])
	check(_lowest_vertex(body) > 1.3, "nothing below the neck (lowest point %.2f m)" % _lowest_vertex(body))
	check(names.has("Male_Ranger_Head_Hood"), "hood on")
	check(not names.any(func(n: String) -> bool: return n.begins_with("Hair_") and n != "Hair_Beard"),
		"the hood hides the hair (%s)" % ", ".join(names))
	check(names.any(func(n: String) -> bool: return "Beard" in n), "the beard stays")
	var skin := _surface_material(component, "MI_Regular")
	check(skin != null and skin.albedo_texture == load(AppearanceComponent.BODIES[CharacterAppearance.Body.MALE]["light"])
		and skin.albedo_color.is_equal_approx(look.skin_tint), "the outfit's hands use the body's skin texture and tint")
	await clear_arena()


func test_pieces_and_colours() -> void:
	print("2. Hood and pauldrons come off; colour variants swap the cloth")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var component := _component(player)
	var look := _look(component)
	look.outfit = "Ranger"
	look.hood = false
	look.pauldrons = false
	look.hair_style = "Long"
	component.apply(look)
	var names := _names(component)
	check(not names.has("Male_Ranger_Head_Hood") and not names.has("Male_Ranger_Acc_Pauldron"),
		"no hood, no pauldron")
	check(names.has("Hair_Long"), "hood down: the hair shows")
	var cloth_default := _cloth_texture(component, "Male_Ranger_Body")
	look.outfit_variant = 1
	component.apply(look)
	var cloth_variant := _cloth_texture(component, "Male_Ranger_Body")
	check(cloth_variant != null and cloth_variant.resource_path.ends_with("T_Ranger_3_BaseColor.png"),
		"variant 1 (%s) uses T_Ranger_3" % look.variant_names()[1])
	check(cloth_default == null or cloth_default != cloth_variant, "different from the default cloth")
	await clear_arena()


func test_female_and_none() -> void:
	print("3. Female bodies get the female cut; None restores the full body")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var other := spawn_player(Vector3(3, 0, 0))
	await ticks(2)
	var component := _component(player)
	var look := _look(component)
	look.body = CharacterAppearance.Body.FEMALE
	look.outfit = "Peasant"
	component.apply(look)
	var names := _names(component)
	check(names.has("Female_Peasant_Body") and not names.has("Male_Peasant_Body"), "female peasant meshes")
	check(_triangles(_part(component, "Superhero_Female")) < 4000, "female head-only body")
	var other_look := _look(_component(other))
	other_look.body = CharacterAppearance.Body.FEMALE
	other_look.outfit = "Ranger"
	_component(other).apply(other_look)
	check(_part(component, "Superhero_Female").mesh == _part(_component(other), "Superhero_Female").mesh,
		"the head cut is made once per body and shared")
	look.outfit = "None"
	look.body = CharacterAppearance.Body.MALE
	component.apply(look)
	names = _names(component)
	check(not names.any(func(n: String) -> bool: return n.begins_with("Male_") or n.begins_with("Female_")),
		"no outfit meshes left")
	check(_triangles(_part(component, "SuperHero_Male")) > 8000, "the full body is back (%d triangles)"
		% _triangles(_part(component, "SuperHero_Male")))
	await clear_arena()


func test_menu() -> void:
	print("4. The debug menu's Outfits... button opens the Outfits panel, which dresses the player")
	var main: Node3D = preload("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await ticks(10)
	var menu := main.get_node("DebugMenu") as DebugMenu
	var outfits := menu.get_node("OutfitMenu") as OutfitMenu
	var component := main.get_node("Player/Appearance") as AppearanceComponent
	check(not outfits.visible, "closed at first")
	# The default window (1152x648): the button must be on screen, and the
	# whole panel must fit (it scrolls instead of running off the bottom).
	root.size = Vector2i(1152, 648)
	menu.get_node("Panel").show()
	await process_frame
	await process_frame
	var screen := root.get_visible_rect()
	var outfits_button := menu.get_node("%OutfitsButton") as Control
	check(screen.encloses(outfits_button.get_global_rect()), "Outfits... is on screen in a 1152x648 window (%s)"
		% outfits_button.get_global_rect())
	check((menu.get_node("Panel") as Control).get_global_rect().end.y <= screen.end.y,
		"the debug panel fits the window (bottom %.0f of %.0f)" % [(menu.get_node("Panel") as Control).get_global_rect().end.y, screen.end.y])
	(menu.get_node("%OutfitsButton") as Button).pressed.emit()
	check(outfits.visible, "Outfits... opens it")
	var debug_panel := menu.get_node("Panel") as Control
	check(outfits.get_global_rect().end.x <= debug_panel.get_global_rect().position.x,
		"beside the debug panel, not over it")
	outfits.choose_outfit("Ranger")
	check(component.appearance.outfit == "Ranger" and _names(component).has("Male_Ranger_Body"),
		"choosing Ranger dresses the player")
	var variant := outfits.get_node("%VariantOption") as OptionButton
	check(variant.item_count == 2 and variant.get_item_text(1) == "Sand", "colours: %s, %s"
		% [variant.get_item_text(0), variant.get_item_text(1)])
	check(not (outfits.get_node("%HoodCheck") as CheckBox).disabled, "the ranger has a hood to toggle")
	(outfits.get_node("%HoodCheck") as CheckBox).button_pressed = false
	check(not component.appearance.hood and not _names(component).has("Male_Ranger_Head_Hood"), "unticking Hood lowers it")
	outfits.choose_outfit("Peasant")
	check((outfits.get_node("%HoodCheck") as CheckBox).disabled, "the peasant has no hood (toggle disabled)")
	var f1 := InputEventAction.new()
	f1.action = &"debug_menu"
	f1.pressed = true
	menu.get_node("Panel").show()
	menu._unhandled_input(f1)
	check(not outfits.visible, "closing the debug menu closes it too")
	main.queue_free()
	await ticks(2)


func _component(player: Node) -> AppearanceComponent:
	return player.get_node("Appearance") as AppearanceComponent


## The component's appearance, as an editable copy.
func _look(component: AppearanceComponent) -> CharacterAppearance:
	component.appearance = component.appearance.duplicate()
	return component.appearance


func _names(component: AppearanceComponent) -> Array:
	return component.get_parts().filter(func(m: MeshInstance3D) -> bool: return is_instance_valid(m)) \
		.map(func(m: MeshInstance3D) -> String: return String(m.name))


func _part(component: AppearanceComponent, part_name: String) -> MeshInstance3D:
	for part in component.get_parts():
		if is_instance_valid(part) and part.name == part_name:
			return part
	return null


func _triangles(mesh: MeshInstance3D) -> int:
	if mesh == null:
		return 0
	return (mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3


## Lowest point (m, bind pose) any triangle of the mesh reaches.
func _lowest_vertex(mesh: MeshInstance3D) -> float:
	var arrays := mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lowest := INF
	for i: int in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
		lowest = minf(lowest, vertices[i].y)
	return lowest


func _surface_material(component: AppearanceComponent, prefix: String) -> StandardMaterial3D:
	for part in component.get_parts():
		if not is_instance_valid(part):
			continue
		for s in part.mesh.get_surface_count():
			var material := part.get_active_material(s) as StandardMaterial3D
			if material and material.resource_name.begins_with(prefix):
				return material
	return null


func _cloth_texture(component: AppearanceComponent, part_name: String) -> Texture2D:
	var part := _part(component, part_name)
	var material := part.get_active_material(0) as StandardMaterial3D if part else null
	return material.albedo_texture if material else null
