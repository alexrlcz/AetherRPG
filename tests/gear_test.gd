extends "res://tests/combat_test.gd"
## Headless gear checks (helmet, cloak, boots) on the real player: the items,
## how they are built and skinned, the cloak's spring simulation in motion,
## and the Outfits & gear panel (reuses the combat test's arena and helpers).
##   godot --headless --path . -s res://tests/gear_test.gd
## Exit code 0 = every check passed.

const HELMET := preload("res://resources/items/gear/helmet_fantasy.tres")
const CLOAK := preload("res://resources/items/gear/cloak_poor.tres")
const BOOTS := preload("res://resources/items/gear/boots_leather.tres")

var _lift := 0.0


func _initialize() -> void:
	await process_frame
	PlayerProfile.current().save_path = ""
	test_items()
	await test_wearing()
	await test_cloak_motion()
	await test_female_and_off()
	await test_menu()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_items() -> void:
	print("1. Three gear items, one per slot")
	var slots := {}
	for item: GearDefinition in [HELMET, CLOAK, BOOTS]:
		slots[item.slot] = item.display_name
		check(item.kind == ItemDefinition.Kind.GEAR and not item.auto_collect,
			"%s is gear, picked up with the interact key" % item.display_name)
	check(slots.size() == 3, "head, back and feet: %s" % [slots.values()])


func test_wearing() -> void:
	print("2. Wearing all three: meshes, skinning, hidden hair and feet")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var component := _component(player)
	var full_body := _lowest_triangle(_part(component, "SuperHero_Male"))
	_wear(component, [HELMET, CLOAK, BOOTS])
	var names := _names(component)
	for part in ["Gear_HelmetFantasy", "Gear_CloakPoor", "Gear_BootsLeather", "Gear_BootsLeather_L"]:
		check(names.has(part), "%s on the rig" % part)
	check(not names.any(func(n: String) -> bool: return n.begins_with("Hair_") and n != "Hair_Beard"),
		"the helmet hides the hair")
	var body_low := _lowest_triangle(_part(component, "SuperHero_Male"))
	check(full_body < 0.02 and body_low > 0.06, "the feet are cut out under the boots (lowest skin %.2f m, was %.2f)"
		% [body_low, full_body])
	check(_binds(component, "Gear_HelmetFantasy") == ["Head"], "the helmet rides the head bone")
	check(_binds(component, "Gear_BootsLeather") == ["calf_r", "foot_r", "ball_r"]
		and _binds(component, "Gear_BootsLeather_L") == ["calf_l", "foot_l", "ball_l"],
		"each boot bends with its calf, foot and toes")
	var cloak_binds := _binds(component, "Gear_CloakPoor")
	check(cloak_binds.has("spine_03") and cloak_binds.filter(func(b: String) -> bool: return b.begins_with("cloak_")).size()
		== GearBuilder.CLOAK_COLUMNS * GearBuilder.CLOAK_JOINTS, "the cloak hangs on %d chain bones and the upper back"
		% (GearBuilder.CLOAK_COLUMNS * GearBuilder.CLOAK_JOINTS))
	var spring := component.skeleton.get_node_or_null(GearBuilder.CLOAK_SPRING) as SpringBoneSimulator3D
	check(spring != null and spring.active and spring.setting_count == GearBuilder.CLOAK_COLUMNS,
		"the cloak's spring simulation runs (%d chains)" % (spring.setting_count if spring else 0))
	var boot := _part(component, "Gear_BootsLeather")
	var sole := INF
	for v: Vector3 in boot.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		sole = minf(sole, v.y)
	check(absf(sole) < 0.02, "boots stand on the floor (sole %.3f m)" % sole)
	await clear_arena()


func test_cloak_motion() -> void:
	print("3. The cloak swings: trails when running, settles at rest, survives rolls and death")
	await make_arena()
	var player := spawn_player(Vector3(0, 0, 8))
	await ticks(2)
	var component := _component(player)
	_wear(component, [CLOAK])
	var skeleton := component.skeleton
	skeleton.skeleton_updated.connect(_measure.bind(skeleton))
	await ticks(60)
	var idle := _lift
	Input.action_press("move_forward")
	player.sprint_toggled = true
	await ticks(60)
	var sprinting := _lift
	check(sprinting > idle + 25.0, "sprinting lifts it behind (%.0f deg, at rest %.0f deg)" % [sprinting, idle])
	Input.action_release("move_forward")
	await ticks(150)
	check(absf(_lift - idle) < 8.0, "it settles back after stopping (%.0f deg)" % _lift)
	player.request_dodge()
	var worst := 0.0
	var finite := true
	for i in 50:
		await physics_frame
		worst = maxf(worst, _cloak_spread(skeleton))
		finite = finite and is_finite(_lift)
	check(finite and worst < 1.7, "rolling: it follows without stretching (bones within %.2f m of the back)" % worst)
	player.health.take_damage(player.health.current_health)
	await ticks(60)
	check(is_finite(_lift) and _cloak_spread(skeleton) < 1.7, "it stays sane on the ragdoll after death")
	await clear_arena()


func test_female_and_off() -> void:
	print("4. Gear fits other bodies; taking the cloak off stops its simulation")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var component := _component(player)
	var look := _wear(component, [HELMET, CLOAK, BOOTS])
	look.body = CharacterAppearance.Body.FEMALE
	component.apply(look)
	var boot := _part(component, "Gear_BootsLeather")
	var foot := component.skeleton.get_bone_global_rest(component.skeleton.find_bone("foot_r")).origin
	var centre := Vector3.ZERO
	var vertices: PackedVector3Array = boot.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in vertices:
		centre += v
	centre /= vertices.size()
	check(absf(centre.x - foot.x) < 0.04, "the boot follows the female foot (centre x %.3f, foot x %.3f)" % [centre.x, foot.x])
	look.set_gear(GearDefinition.Slot.BACK, null)
	component.apply(look)
	var spring := component.skeleton.get_node(GearBuilder.CLOAK_SPRING) as SpringBoneSimulator3D
	check(not _names(component).has("Gear_CloakPoor") and not spring.active, "cloak off: no mesh, simulation off")
	await clear_arena()


func test_menu() -> void:
	print("5. The Outfits & gear panel puts gear on and off")
	var main: Node3D = preload("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await ticks(10)
	var menu := main.get_node("DebugMenu") as DebugMenu
	var panel := menu.get_node("OutfitMenu") as OutfitMenu
	var component := main.get_node("Player/Appearance") as AppearanceComponent
	(menu.get_node("%OutfitsButton") as Button).pressed.emit()
	var head := panel.get_node("%HeadOption") as OptionButton
	var back := panel.get_node("%BackOption") as OptionButton
	var feet := panel.get_node("%FeetOption") as OptionButton
	check(head.get_item_text(1) == HELMET.display_name and back.get_item_text(1) == CLOAK.display_name
		and feet.get_item_text(1) == BOOTS.display_name, "each slot offers its gear (%s, %s, %s)"
		% [head.get_item_text(1), back.get_item_text(1), feet.get_item_text(1)])
	panel.choose_gear(GearDefinition.Slot.BACK, CLOAK)
	panel.choose_gear(GearDefinition.Slot.FEET, BOOTS)
	check(component.appearance.gear_in(GearDefinition.Slot.BACK) == CLOAK and _names(component).has("Gear_CloakPoor")
		and _names(component).has("Gear_BootsLeather"), "choosing them dresses the player")
	panel.choose_gear(GearDefinition.Slot.BACK, null)
	check(component.appearance.gear_in(GearDefinition.Slot.BACK) == null and not _names(component).has("Gear_CloakPoor"),
		"None takes the cloak off")
	main.queue_free()
	await ticks(2)


func _measure(skeleton: Skeleton3D) -> void:
	# The simulated pose only exists during the skeleton's update.
	var top := skeleton.get_bone_global_pose(skeleton.find_bone("cloak_2_1")).origin
	var tip := skeleton.get_bone_global_pose(skeleton.find_bone("cloak_2_3")).origin
	_lift = rad_to_deg((skeleton.global_basis * (tip - top)).normalized().angle_to(Vector3.DOWN))


## Farthest cloak bone from the upper back (m): a blown-up simulation would
## fling them far away.
func _cloak_spread(skeleton: Skeleton3D) -> float:
	var back := skeleton.get_bone_global_pose(skeleton.find_bone("spine_03")).origin
	var far := 0.0
	for c in GearBuilder.CLOAK_COLUMNS:
		for j in GearBuilder.CLOAK_JOINTS:
			var p := skeleton.get_bone_global_pose(skeleton.find_bone("cloak_%d_%d" % [c, j])).origin
			far = maxf(far, p.distance_to(back))
	return far


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


## Lowest point (m, bind pose) any triangle of the mesh reaches.
func _lowest_triangle(mesh: MeshInstance3D) -> float:
	var arrays := mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lowest := INF
	for i: int in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
		lowest = minf(lowest, vertices[i].y)
	return lowest
