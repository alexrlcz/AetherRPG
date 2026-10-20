extends "res://tests/combat_test.gd"
## Headless gold checks: the profile that keeps it, enemies dropping it as
## coins, coins flying to the player, the HUD, and Main giving each enemy its
## roster entry's gold (reuses the combat test's arena and helpers).
##   godot --headless --path . -s res://tests/gold_test.gd
## Exit code 0 = every check passed. Never writes the real profile.

const TEST_PROFILE := "user://test_profile.json"


func _initialize() -> void:
	await process_frame
	PlayerProfile.current().save_path = ""  # Keep the real save untouched.
	await test_profile()
	await test_drop()
	await test_collect()
	await test_wall_clamp()
	await test_main()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_profile() -> void:
	print("1. The profile keeps gold across sessions")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	var a := PlayerProfile.new()
	a.save_path = TEST_PROFILE
	root.add_child(a)
	check(a.gold == 0, "a fresh profile has no gold")
	a.add_gold(42)
	check(FileAccess.file_exists(TEST_PROFILE), "saved on change")
	var b := PlayerProfile.new()
	b.save_path = TEST_PROFILE
	root.add_child(b)
	check(b.gold == 42, "a new session loads it (%d)" % b.gold)
	b.add_gold(-100)
	check(b.gold == 0, "spending never goes below 0")
	a.queue_free()
	b.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	await ticks(1)


func test_drop() -> void:
	print("2. A dying enemy pops its gold out as coins")
	await make_arena()
	var enemy := spawn_enemy(Vector3(0, 0, -6), true)
	var drops := enemy.get_node("Drops") as DropComponent
	drops.loot = LootTable.gold_only(17, 17)
	drops.rng_seed = 5
	await ticks(3)
	enemy.health.take_damage(enemy.health.current_health)
	await ticks(1)
	var coins := _pickups()
	var total := 0
	for coin in coins:
		total += coin.amount
	check(coins.size() == 4, "17 gold in 4 coins (%d)" % coins.size())
	check(total == 17, "worth 17 together (%d)" % total)
	var high := 0.0
	for i in 15:
		await physics_frame
		for coin in coins:
			high = maxf(high, coin.global_position.y)
	check(high > 1.5, "they pop up (%.1f m)" % high)
	await ticks(60)
	var landed := true
	var spread := 0.0
	for coin in coins:
		landed = landed and coin.global_position.y < 0.05 and not coin._airborne
		spread = maxf(spread, flat(coin.global_position - enemy.global_position).length())
	check(landed, "and land on the floor")
	check(spread > 0.5 and spread < 3.0, "around the body (up to %.1f m away)" % spread)
	# Same seed, same drop.
	var first := []
	for coin in coins:
		first.append([coin.amount, coin.global_position.snapped(Vector3.ONE * 0.01)])
	for coin in coins:
		coin.queue_free()
	await ticks(1)
	var again := drops.drop()
	await ticks(75)
	var second := []
	for coin in again:
		second.append([coin.amount, coin.global_position.snapped(Vector3.ONE * 0.01)])
	check(str(first) == str(second), "the same seed drops the same coins in the same places")
	await clear_arena()


func test_collect() -> void:
	print("3. Coins fly to a nearby player and add to the profile")
	await make_arena()
	var player := spawn_player(Vector3(0, 0, 9))
	var enemy := spawn_enemy(Vector3(0, 0, -3), true)
	var drops := enemy.get_node("Drops") as DropComponent
	drops.loot = LootTable.gold_only(23, 23)
	await ticks(3)
	var before := PlayerProfile.current().gold
	enemy.health.take_damage(enemy.health.current_health)
	await ticks(90)
	check(_pickups().size() == 5, "out of reach (12 m): the coins wait (%d)" % _pickups().size())
	check(PlayerProfile.current().gold == before, "no gold yet")
	player.global_position = Vector3(0.6, 0, -3)  # Where the body fell: every coin within reach.
	await wait_until(func() -> bool: return _pickups().is_empty(), 180)
	check(_pickups().is_empty(), "within reach they fly in and are collected")
	check(PlayerProfile.current().gold == before + 23, "+23 gold (%d -> %d)" % [before, PlayerProfile.current().gold])
	await clear_arena()


func test_wall_clamp() -> void:
	print("4. Coins don't land behind a wall")
	# A wall 1 m to the enemy's east (its west face at x = 0.75).
	await make_arena([[Vector3(1.0, 1.5, 0), Vector3(0.5, 3.0, 12)]])
	var enemy := spawn_enemy(Vector3(0, 0, 0), true)
	var drops := enemy.get_node("Drops") as DropComponent
	drops.loot = LootTable.gold_only(40, 40)
	drops.rng_seed = 99
	await ticks(3)
	enemy.health.take_damage(enemy.health.current_health)
	await ticks(90)
	var behind := 0
	for coin in _pickups():
		if coin.global_position.x > 0.75:
			behind += 1
	check(_pickups().size() == 8 and behind == 0, "all %d coins on the near side (%d behind)" % [_pickups().size(), behind])
	await clear_arena()


func test_main() -> void:
	print("5. Main: each enemy drops its roster entry's loot; the HUD counts gold")
	var main: Node3D = preload("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await wait_until(func() -> bool: return main.get_node("Enemies").get_child_count() > 0, 600)
	var layout: DungeonLayout = main.layout
	var enemies := main.get_node("Enemies").get_children()
	var matching := 0
	for i in mini(enemies.size(), layout.spawns.size()):
		var drops := enemies[i].get_node_or_null("Drops") as DropComponent
		var entry := layout.spawns[i]["entry"] as EnemyEntry
		if drops and entry.loot != null and drops.loot == entry.loot and drops.level == layout.level 				and drops.rng_seed != 0:
			matching += 1
	check(matching == layout.spawns.size() and matching > 0,
		"%d of %d enemies carry their entry's loot table, the level and a seed" % [matching, layout.spawns.size()])
	check(main.dungeon.is_in_group(DropComponent.CONTAINER_GROUP), "loot goes into the level (freed with it)")
	var label := main.get_node("HUD").get_node("%GoldLabel") as Label
	var gold := PlayerProfile.current().gold
	check(label.text == "Gold %d" % gold, "HUD: %s" % label.text)
	PlayerProfile.current().add_gold(7)
	check(label.text == "Gold %d" % (gold + 7), "follows the profile (%s)" % label.text)
	main.queue_free()
	await ticks(2)


func _pickups() -> Array[Pickup]:
	var result: Array[Pickup] = []
	for node in get_nodes_in_group(Pickup.GROUP):
		if not node.is_queued_for_deletion():
			result.append(node as Pickup)
	return result
