extends "res://tests/combat_test.gd"
## Headless equipment checks on the real player (reuses the combat test's
## helpers): the starting loadout, slots and rings, stats from items, outfit
## pieces on the body (male and female, the body cut under them, hood and
## hair, skin-coloured hands), the main hand deciding the weapon, picking up
## gear with the interact key (empty slot, else the bag), saving and loading
## through the profile, gear in loot rolls, and the debug Equipment panel in
## the real Main scene.
##   godot --headless --path . -s res://tests/equipment_test.gd
## Exit code 0 = every check passed.

const G := "res://resources/items/gear/"
const CATALOG := preload("res://resources/items/catalog.tres")
const SWORD := preload("res://resources/weapons/sword.tres")
const RANGER := ["hood_ranger", "pauldron_ranger", "jerkin_ranger", "bracers_ranger", "gloves_ranger",
	"leggings_ranger", "boots_ranger"]


func _initialize() -> void:
	await process_frame
	PlayerProfile.current().save_path = ""
	await test_starting_loadout()
	await test_slots_and_stats()
	await test_pieces()
	await test_main_hand()
	await test_pickup()
	await test_persistence()
	test_loot()
	await test_menu()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_starting_loadout() -> void:
	print("1. A fresh player: sword and the Peasant tunic, trousers and shoes")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var equipment := player.equipment
	check(equipment.get_item(&"main_hand") == SWORD and player.weapon.current == SWORD, "the sword in the main hand")
	check(_id(equipment, &"chest") == &"tunic_peasant" and _id(equipment, &"legs") == &"trousers_peasant"
		and _id(equipment, &"feet") == &"shoes_peasant", "tunic, trousers, shoes")
	var names := _names(player)
	check(names.has("Male_Peasant_Body") and names.has("Male_Peasant_Legs") and names.has("Male_Peasant_Feet"),
		"their meshes are on the rig")
	check(player.character_stats.get_value(CharacterStats.Stat.ARMOR) == 10.0,
		"armor 10 from them (%.0f)" % player.character_stats.get_value(CharacterStats.Stat.ARMOR))
	await clear_arena()


func test_slots_and_stats() -> void:
	print("2. Slots, rings and the stats items give")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var equipment := player.equipment
	var might := _item("ring_might")
	var endurance := _item("ring_endurance")
	check(equipment.equip(might) == null and equipment.get_item(&"ring_1") == might, "a ring goes in ring 1")
	check(equipment.equip(endurance) == null and equipment.get_item(&"ring_2") == endurance, "the next in ring 2")
	var again := equipment.equip(endurance, &"ring_1")
	check(again == might and equipment.get_item(&"ring_1") == endurance, "a ring put in a taken slot returns the old one")
	check(equipment.equip(_item("amulet_vigor"), &"head") == null and equipment.get_item(&"head") == null,
		"an item never goes in a slot it doesn't fit")
	equipment.equip(might, &"ring_2")
	equipment.equip(_item("amulet_vigor"))
	equipment.equip(_item("charm_swiftness"))
	var stats := player.character_stats
	check(player.health.max_health == 120, "amulet: +20 health (%d)" % player.health.max_health)
	check(is_equal_approx(player.melee.damage_scale, 1.1), "ring of might: +10%% damage (x%.2f)" % player.melee.damage_scale)
	check(is_equal_approx(player.stamina.max_stamina, 120.0), "ring of endurance: +20 stamina")
	check(is_equal_approx(stats.get_value(CharacterStats.Stat.MOVE_SPEED), 1.08), "charm: +8% move speed")
	check(equipment.unequip(&"neck") != null and player.health.max_health == 100, "taking it off removes its bonus")
	var changed := []
	equipment.changed.connect(func(slot: StringName, item: GearDefinition, previous: GearDefinition) -> void:
		changed.append([slot, item, previous]))
	equipment.equip(_item("helmet_fantasy"))
	check(changed.size() == 1 and changed[0][0] == &"head", "changed(slot, item, previous) is emitted")
	await clear_arena()


func test_pieces() -> void:
	print("3. Outfit pieces: the full Ranger set, the body cut, hood and hair, female meshes")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var equipment := player.equipment
	var component := player.get_node("Appearance") as AppearanceComponent
	for slot in [&"chest", &"legs", &"feet"]:
		equipment.unequip(slot)
	var full := _triangles(_part(component, "SuperHero_Male"))
	check(_names(player).any(func(n: String) -> bool: return n.begins_with("Hair_")), "bare: the hair shows")
	for item in RANGER:
		equipment.equip(_item(item))
	var names := _names(player)
	for mesh in ["Male_Ranger_Head_Hood", "Male_Ranger_Acc_Pauldron", "Male_Ranger_Body", "Male_Ranger_Body_Belt_1",
			"Male_Ranger_Arms_Bracer", "Male_Ranger_Arms", "Male_Ranger_Legs", "Male_Ranger_Feet_Boots"]:
		check(names.has(mesh), "%s on the rig" % mesh)
	check(not names.any(func(n: String) -> bool: return n.begins_with("Hair_") and n != "Hair_Beard"),
		"the hood hides the hair")
	var dressed := _triangles(_part(component, "SuperHero_Male"))
	check(dressed < full * 0.4 and dressed > 200, "the body is cut away under the gear (%d of %d triangles)"
		% [dressed, full])
	var skin := _surface_material(player, "MI_Regular")
	check(skin != null and skin.albedo_texture == load(AppearanceComponent.BODIES[CharacterAppearance.Body.MALE]["light"]),
		"the gloves' hands use the body's skin")
	check(player.character_stats.get_value(CharacterStats.Stat.ARMOR) == 36.0,
		"Ranger set armor 36 (%.0f)" % player.character_stats.get_value(CharacterStats.Stat.ARMOR))
	var look := component.appearance
	look.body = CharacterAppearance.Body.FEMALE
	component.apply(look)
	names = _names(player)
	check(names.has("Female_Ranger_Acc_Pauldrons") and names.has("Female_Ranger_Feet") and names.has("Female_Ranger_Body"),
		"a female body gets the female meshes")
	equipment.equip(_item("tunic_peasant"))
	names = _names(player)
	check(names.has("Female_Peasant_Body") and not names.has("Female_Ranger_Body") and names.has("Female_Ranger_Legs"),
		"pieces mix: a Peasant tunic with Ranger leggings")
	await clear_arena()


func test_main_hand() -> void:
	print("4. The main hand decides the weapon")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var greatsword := preload("res://resources/weapons/greatsword.tres")
	var own_speed := player.move_speed
	player.equipment.equip(greatsword)
	check(player.weapon.current == greatsword and player.move_speed == greatsword.character_overrides["move_speed"],
		"greatsword: its moveset and speed")
	player.equipment.unequip(&"main_hand")
	check(player.weapon.current == SWORD and player.move_speed == own_speed, "empty main hand: the default sword")
	check(not greatsword.is_worn_visual() and not _names(player).any(func(n: String) -> bool: return "Claymore" in n),
		"weapons never go on the body")
	await clear_arena()


func test_pickup() -> void:
	print("5. F on gear on the floor: an empty slot equips it, else the bag; a full bag leaves it")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var hud: HUD = preload("res://scenes/ui/hud.tscn").instantiate()
	world.add_child(hud)
	var helmet := _item("helmet_fantasy")
	var pickup := _floor_item(helmet, Vector3(0, 0.5, -1.0))
	check(not pickup.can_interact(), "not while it is still falling")
	await ticks(60)
	check(pickup.is_in_group(Interactor.GROUP) and pickup.can_interact(), "an interactable once it has landed")
	check(pickup.interact_prompt() == "Take Fantasy Helmet (+10 Armor)", "prompt: %s" % pickup.interact_prompt())
	check(player.interactor.focus == pickup, "the player's interactor focuses it")
	player.request_interact()
	await ticks(3)
	check(player.equipment.get_item(&"head") == helmet and not is_instance_valid(pickup), "the head was empty: equipped")
	await ticks(70)  # The pick-up animation.
	var boots := _item("boots_ranger")
	pickup = _floor_item(boots, Vector3(0, 0.5, -1.0))
	await ticks(60)
	check(pickup.collect(player), "taken")
	check(player.equipment.get_item(&"feet") == _item("shoes_peasant") and player.inventory.item_at(0) == boots,
		"the feet were taken: the boots go into the bag")
	for i in player.inventory.capacity - 1:
		player.inventory.add(_item("ring_might"))
	check(player.inventory.is_full(), "bag filled")
	pickup = _floor_item(_item("jerkin_ranger"), Vector3(0, 0.5, -1.0))
	await ticks(60)
	check(not pickup.collect(player) and is_instance_valid(pickup) and pickup.can_interact(), "full bag: it stays")
	check(hud.get_notice() == "Bag full", "the HUD says \"%s\"" % hud.get_notice())
	var ring := _floor_item(_item("ring_endurance"), Vector3(0, 0.5, -1.0))
	await ticks(60)
	check(ring.collect(player) and player.equipment.get_item(&"ring_1") == _item("ring_endurance"),
		"a ring still fits an empty ring slot with the bag full")
	await clear_arena()


func test_persistence() -> void:
	print("6. Equipment is saved in the profile and restored")
	var profile := PlayerProfile.current()
	var path := "user://equipment_test_profile.json"
	profile.save_path = path
	profile.equipment = {}
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	check(profile.equipment.get("chest", "").ends_with("tunic_peasant.tres"), "a fresh profile saves the starting gear")
	player.equipment.equip(_item("ring_might"))
	player.equipment.equip(preload("res://resources/weapons/club.tres"))
	player.equipment.unequip(&"feet")
	await clear_arena()
	profile.equipment = {}
	profile.load_profile()
	check(profile.equipment.get("ring_1", "").ends_with("ring_might.tres") and not profile.equipment.has("feet"),
		"written to disk (%s)" % path)
	await make_arena()
	var again := spawn_player(Vector3.ZERO)
	await ticks(2)
	check(_id(again.equipment, &"ring_1") == &"ring_might" and again.weapon.current.display_name == "Club"
		and again.equipment.get_item(&"feet") == null, "a new player wears what was saved, not the starting gear")
	await clear_arena()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	profile.save_path = ""
	profile.equipment = {}


func test_loot() -> void:
	print("7. Loot tables drop gear from the catalog")
	var table := LootTable.gold_only(1, 1)
	table.gear = CATALOG
	table.gear_chance = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var drop := table.roll(rng)
	check(drop.size() == 2 and drop[1][0] in CATALOG.items, "gold and one catalog item (%s)" % drop[1][0].display_name)
	var chest := preload("res://resources/loot/chest.tres")
	var enemy := preload("res://resources/loot/club_knight.tres")
	check(chest.gear == CATALOG and chest.gear_chance > enemy.gear_chance and enemy.gear_chance > 0.0,
		"chests drop gear more often (%.0f%%) than enemies (%.0f%%)" % [chest.gear_chance * 100, enemy.gear_chance * 100])
	var hits := 0
	for i in 2000:
		for line: Array in enemy.roll(rng):
			if line[0] is GearDefinition:
				hits += 1
	check(absf(hits / 2000.0 - enemy.gear_chance) < 0.02, "an enemy drops gear ~%.0f%% of the time (%.1f%%)"
		% [enemy.gear_chance * 100, hits / 20.0])
	var every_slot := true
	for slot: StringName in Equipment.SLOTS:
		if slot != &"back" and not CATALOG.items.any(func(item: GearDefinition) -> bool:
				return slot in Equipment.slots_for(item)):
			every_slot = false
	check(every_slot, "the catalog has an item for every slot but the cloak")


func test_menu() -> void:
	print("8. The debug Equipment panel")
	var main: Node3D = preload("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await ticks(10)
	var menu := main.get_node("DebugMenu") as DebugMenu
	var panel := menu.get_node("EquipmentMenu") as EquipmentMenu
	var player := main.get_node("Player") as PlayerController
	(menu.get_node("%EquipmentButton") as Button).pressed.emit()
	check(panel.visible, "the Equipment... button opens it")
	var head := panel.get_option(&"head")
	var labels := []
	for i in head.item_count:
		labels.append(head.get_item_text(i))
	check(labels == ["None", "Fantasy Helmet", "Ranger Hood"], "the head picker: %s" % [labels])
	check(panel.get_option(&"chest").get_item_text(panel.get_option(&"chest").selected) == "Peasant Tunic",
		"it shows what is worn")
	panel.choose(&"head", _item("hood_ranger"))
	check(_id(player.equipment, &"head") == &"hood_ranger", "choosing equips it")
	panel.choose(&"main_hand", preload("res://resources/weapons/club.tres"))
	check(player.weapon.current.display_name == "Club", "the main-hand picker swaps the weapon")
	panel.choose(&"head", null)
	check(player.equipment.get_item(&"head") == null, "None takes it off")
	player.equipment.equip(_item("ring_might"))
	var ring := panel.get_option(&"ring_1")
	check(ring.get_item_text(ring.selected) == "Ring of Might", "the pickers follow changes made elsewhere")
	main.queue_free()
	await ticks(2)


func _floor_item(item: GearDefinition, at: Vector3) -> Pickup:
	var pickup := Pickup.new()
	pickup.item = item
	world.add_child(pickup)
	pickup.launch(at, Vector3.ZERO, 0.0)
	return pickup


func _item(id: String) -> GearDefinition:
	return load(G + id + ".tres")


func _id(equipment: Equipment, slot: StringName) -> StringName:
	var item := equipment.get_item(slot)
	return item.id if item else &""


func _names(player: Node) -> Array:
	var component := player.get_node("Appearance") as AppearanceComponent
	return component.get_parts().filter(func(m: MeshInstance3D) -> bool: return is_instance_valid(m)) \
		.map(func(m: MeshInstance3D) -> String: return String(m.name))


func _part(component: AppearanceComponent, part_name: String) -> MeshInstance3D:
	for part in component.get_parts():
		if is_instance_valid(part) and part.name == part_name:
			return part
	return null


func _triangles(mesh: MeshInstance3D) -> int:
	return (mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3


## The first surface material whose name starts with `prefix`, on any part.
func _surface_material(player: Node, prefix: String) -> StandardMaterial3D:
	var component := player.get_node("Appearance") as AppearanceComponent
	for part in component.get_parts():
		if not is_instance_valid(part):
			continue
		for s in part.mesh.get_surface_count():
			var material := part.get_active_material(s) as StandardMaterial3D
			if material and material.resource_name.begins_with(prefix):
				return material
	return null
