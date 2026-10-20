extends "res://tests/combat_test.gd"
## Headless loot checks: LootTable rolls, the shipped tables, chests built by
## DungeonBuilder opened through the player's Interactor (F), and the HUD
## prompt (reuses the combat test's arena and helpers).
##   godot --headless --path . -s res://tests/loot_test.gd
## Exit code 0 = every check passed.

const GOLD := preload("res://resources/items/gold.tres")
const CHEST_LOOT := preload("res://resources/loot/chest.tres")


func _initialize() -> void:
	await process_frame
	PlayerProfile.current().save_path = ""
	test_tables()
	await test_chest()
	await test_reach_and_busy()
	await test_hud_prompt()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_tables() -> void:
	print("1. Loot tables: chances, weights, per-level amounts, seeds")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	# Guaranteed entry with a chance.
	var table := LootTable.gold_only(10, 10)
	table.guaranteed[0].chance = 0.25
	var hits := 0
	for i in 4000:
		if not table.roll(rng).is_empty():
			hits += 1
	check(absf(hits / 4000.0 - 0.25) < 0.03, "a 25%% entry drops %.1f%% of the time" % (hits / 40.0))
	# Weighted picks with a "nothing" share: the chest's bonus pile is 1 in 3.
	var bonus := 0
	for i in 3000:
		var line: Array = CHEST_LOOT.roll(rng)[0]
		if line[1] > roundi(30):  # More than the guaranteed part can give at level 1.
			bonus += 1
	check(bonus > 600 and bonus < 1400, "the chest's bonus pile comes up about 1 in 3 (%d of 3000; some hide under 30)" % bonus)
	# Amounts grow per level.
	var low := 0
	var high := 0
	for i in 500:
		low += CHEST_LOOT.roll(rng, 1)[0][1]
		high += CHEST_LOOT.roll(rng, 6)[0][1]
	check(high > low * 1.8, "level 6 chests give about twice level 1 (%.1f vs %.1f gold)" % [high / 500.0, low / 500.0])
	# Same seed, same roll; lines of one item are merged.
	var a := RandomNumberGenerator.new()
	a.seed = 77
	var b := RandomNumberGenerator.new()
	b.seed = 77
	var roll_a := CHEST_LOOT.roll(a, 3)
	check(str(roll_a) == str(CHEST_LOOT.roll(b, 3)), "the same seed rolls the same (%s gold)" % roll_a[0][1])
	check(roll_a.size() == 1 and roll_a[0][0] == GOLD, "gold lines merged into one")
	# The shipped enemy tables.
	for entry: EnemyEntry in [load("res://resources/encounters/club_knight.tres"),
			load("res://resources/encounters/greatsword_knight.tres")]:
		var lowest := 999
		var highest := 0
		for i in 300:
			var g: int = entry.loot.roll(rng, 1)[0][1]
			lowest = mini(lowest, g)
			highest = maxi(highest, g)
		print("     %s: %d-%d gold at level 1" % [entry.display_name, lowest, highest])
		var expected: Vector2i = entry.loot.guaranteed[0].amount
		check(lowest == expected.x and highest == expected.y,
			"%s drops %d-%d gold (its own table, not the scene default)" % [entry.display_name, expected.x, expected.y])


func test_chest() -> void:
	print("2. A built chest opens with F: the player turns to it, the lid swings, gold flies out the front")
	await make_arena()
	var level := DungeonBuilder.new().build(_chest_room(), "ChestRoom")
	world.add_child(level)
	level.add_to_group(DropComponent.CONTAINER_GROUP)
	await ticks(2)
	var chest := level.get_node("NavigationRegion3D/Props/Chest1") as Chest
	check(chest != null and chest.lid_pivot != null, "the builder makes a Chest with a lid")
	check(chest.level == 4 and chest.rng_seed != 0, "rolled for the layout's level, seeded (level %d)" % chest.level)
	var front := flat(chest.global_basis.z).normalized()
	var player := spawn_player(chest.global_position + front * 1.3)
	player.rotation.y = 0.0  # Facing away from the chest at first (it faces it after F).
	await ticks(3)
	check(player.interactor.focus == chest, "the chest is in focus within reach")
	var before := PlayerProfile.current().gold
	player.request_interact()
	await ticks(2)
	check(chest.is_open and player.interactor.is_busy(), "F opens it; the player is busy")
	check(_animator(player).current_action() == &"UAL2/Chest_Open", "plays UAL2/Chest_Open")
	var to_chest := flat(chest.global_position - player.global_position).normalized()
	check(flat(-player.global_basis.z).normalized().dot(to_chest) > 0.95, "the player turned to the chest")
	Input.action_press("move_forward")
	await ticks(20)
	check(flat(player.velocity).length() < 0.05, "standing still while opening")
	Input.action_release("move_forward")
	await wait_until(func() -> bool: return absf(chest.lid_pivot.rotation.x) > deg_to_rad(90.0), 90)
	check(absf(chest.lid_pivot.rotation.x) > deg_to_rad(90.0), "the lid swings open (%.0f°)" % rad_to_deg(-chest.lid_pivot.rotation.x))
	await wait_until(func() -> bool: return not get_nodes_in_group(Pickup.GROUP).is_empty(), 90)
	var coins := get_nodes_in_group(Pickup.GROUP)
	var total := 0
	for coin: Pickup in coins:
		total += coin.amount
	check(not coins.is_empty() and total >= roundi(15 * 1.6), "%d coins, %d gold (level 4 table)" % [coins.size(), total])
	await ticks(50)
	var in_front := 0
	for coin in coins:
		if is_instance_valid(coin) and flat((coin as Pickup).global_position - chest.global_position).dot(front) > 0.0:
			in_front += 1
	check(in_front == coins.size() or PlayerProfile.current().gold > before,
		"they land in front of the chest (%d of %d), or are already collected" % [in_front, coins.size()])
	await wait_until(func() -> bool: return get_nodes_in_group(Pickup.GROUP).is_empty(), 240)
	check(PlayerProfile.current().gold == before + total, "the player gets them: +%d gold" % total)
	check(not chest.can_interact() and player.interactor.focus == null, "an open chest can't be used again")
	player.request_interact()
	await ticks(5)
	check(not player.interactor.is_busy(), "F does nothing now")
	await clear_arena()


func test_reach_and_busy() -> void:
	print("3. Out of reach, mid-attack or dead: no interaction")
	await make_arena()
	var level := DungeonBuilder.new().build(_chest_room(), "ChestRoom")
	world.add_child(level)
	await ticks(2)
	var chest := level.get_node("NavigationRegion3D/Props/Chest1") as Chest
	var front := flat(chest.global_basis.z).normalized()
	var player := spawn_player(chest.global_position + front * 3.0)
	await ticks(3)
	check(player.interactor.focus == null, "3 m away: nothing in focus")
	player.request_interact()
	await ticks(5)
	check(not chest.is_open, "F does nothing out of reach")
	await ticks(20)  # Let that press's buffer run out.
	player.global_position = chest.global_position + front * 1.3
	await ticks(3)
	player.request_attack(false)
	await wait_until(func() -> bool: return player.melee.is_busy(), 30)
	player.request_interact()
	await ticks(3)
	check(not chest.is_open, "not while attacking")
	await wait_until(func() -> bool: return not player.melee.is_busy(), 120)
	await ticks(20)
	check(not chest.is_open, "the press expired with the swing (0.3 s buffer, like attacks)")
	player.request_interact()
	await ticks(3)
	check(chest.is_open, "pressed again after the swing: it opens")
	await clear_arena()
	await make_arena()
	level = DungeonBuilder.new().build(_chest_room(), "ChestRoom")
	world.add_child(level)
	await ticks(2)
	chest = level.get_node("NavigationRegion3D/Props/Chest1") as Chest
	player = spawn_player(chest.global_position + front * 1.3)
	await ticks(3)
	player.health.take_damage(player.health.current_health)
	await ticks(3)
	player.interactor.try_interact()
	check(not chest.is_open and player.interactor.focus == null, "not when dead")
	await clear_arena()


func test_hud_prompt() -> void:
	print("4. The HUD prompts \"[F] Open chest\" in reach; F is bound")
	await make_arena()
	var level := DungeonBuilder.new().build(_chest_room(), "ChestRoom")
	world.add_child(level)
	await ticks(2)
	var chest := level.get_node("NavigationRegion3D/Props/Chest1") as Chest
	var front := flat(chest.global_basis.z).normalized()
	var player := spawn_player(chest.global_position + front * 4.0)
	var hud := preload("res://scenes/ui/hud.tscn").instantiate() as HUD
	world.add_child(hud)
	hud.bind_player_interactor(player.interactor)
	var prompt := hud.get_node("%InteractPrompt") as Label
	await ticks(3)
	check(not prompt.visible, "hidden out of reach")
	player.global_position = chest.global_position + front * 1.3
	await ticks(3)
	check(prompt.visible and prompt.text == "[F]  Open chest", "shown in reach: %s" % prompt.text)
	player.request_interact()
	await ticks(3)
	check(not prompt.visible, "hidden once opened")
	var keys := InputMap.action_get_events(&"interact").filter(func(e: InputEvent) -> bool:
		return e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_F)
	check(not keys.is_empty(), "interact is bound to F")
	await clear_arena()


## A 6x6 room at level 4 with one chest against its north wall, facing south.
func _chest_room() -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.floor_rings.append(PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(6, 6), Vector2(0, 6)]))
	layout.props = [["chest", 3.0, 0.6, 0]]
	layout.seed = 2024
	layout.level = 4
	layout.curvature = 0.0
	layout.centre_origin()
	return layout


func _animator(player: PlayerController) -> CharacterAnimator:
	return player.get_node("Animator") as CharacterAnimator
