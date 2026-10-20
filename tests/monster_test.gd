extends "res://tests/combat_test.gd"
## Headless checks of the Bestiary monsters (Imp, Puglin) as enemies: model,
## colours, proportions, animation, their weapons hitting the player, the
## player hitting them, drops, and the roster placing them in levels
## (reuses the combat test's arena and helpers).
##   godot --headless --path . -s res://tests/monster_test.gd
## Exit code 0 = every check passed.

const IMP := preload("res://scenes/enemies/enemy_imp.tscn")
const PUGLIN := preload("res://scenes/enemies/enemy_puglin.tscn")
## creature: [scene, health, swing damage, reach, standing head height range]
const MONSTERS := {"Imp": [IMP, 45, 13, 1.6, Vector2(1.3, 1.45)], "Puglin": [PUGLIN, 26, 7, 1.25, Vector2(0.58, 0.72)]}


func _initialize() -> void:
	await process_frame
	PlayerProfile.current().save_path = ""
	await test_models()
	await test_they_fight()
	await test_player_hits_puglin()
	await test_drops()
	test_roster()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_models() -> void:
	print("1. Each monster wears its model, a random colour, its proportions and its own weapon")
	await make_arena()
	for creature: String in MONSTERS:
		var spec: Array = MONSTERS[creature]
		var colours := {}
		var first: EnemyController
		for i in 6:
			var monster := _spawn(spec[0], Vector3(i * 2.0 - 5.0, 0, 6), true)
			if first == null:
				first = monster
			await ticks(1)
			colours[(monster.get_node("Appearance") as AppearanceComponent)._creature_variant] = true
		await ticks(20)
		var component := first.get_node("Appearance") as AppearanceComponent
		var names := component.get_parts().map(func(m: MeshInstance3D) -> String: return String(m.name))
		check(names.has(creature + "_Body") and not names.has("SuperHero_Male"), "%s: its model (%s)" % [creature, ", ".join(names)])
		check(colours.size() >= 2 and colours.keys().all(func(v: int) -> bool: return v >= 0 and v < 3),
			"%s: colours vary per monster (%s)" % [creature, colours.keys()])
		check(first.health.max_health == spec[1] and first.attack_range == spec[3],
			"%s: %d health, %.2f m reach" % [creature, first.health.max_health, first.attack_range])
		var hand := first.get_node("Visual/Model/Armature/Skeleton3D/RightHand")
		check(hand.get_node_or_null("WeaponModel") == null, "%s: no extra weapon model (its own is in the mesh)" % creature)
		var skeleton := component.skeleton
		var head_y := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head"))).origin.y
		var foot_y := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot_l"))).origin.y
		var head_rest := (skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone("Head"))).origin.y
		check(head_rest > spec[4].x and head_rest < spec[4].y, "%s: its own height (head %.2f m standing)" % [creature, head_rest])
		check(head_y > head_rest * 0.85 and head_y < head_rest * 1.05,
			"%s: idles at its own scale (head %.2f m, %.0f%% of standing)" % [creature, head_y, head_y / head_rest * 100.0])
		check(foot_y > -0.05 and foot_y < 0.2, "%s: feet on the floor (%.2f m)" % [creature, foot_y])
	await clear_arena()


func test_they_fight() -> void:
	print("2. They chase, swing (library animation) and hit the player")
	for creature: String in MONSTERS:
		var spec: Array = MONSTERS[creature]
		await make_arena()
		var player := spawn_player(Vector3.ZERO)
		player.health.max_health = 1000
		var monster := _spawn(spec[0], Vector3(0, 0, -5), false)
		await ticks(3)
		var hp := player.health.current_health
		await wait_until(func() -> bool: return monster.state == EnemyController.State.ATTACK, 240)
		check(monster.state == EnemyController.State.ATTACK, "%s: chased the player and attacks" % creature)
		var animator := monster.get_node("Animator") as CharacterAnimator
		check(animator.current_action() == &"Sword_Attack", "%s: swings with the library's Sword_Attack" % creature)
		await wait_until(func() -> bool: return player.health.current_health < hp, 120)
		check(hp - player.health.current_health == spec[2], "%s: its weapon hits for %d (%d)"
			% [creature, spec[2], hp - player.health.current_health])
		await clear_arena()


func test_player_hits_puglin() -> void:
	print("3. The player's light combo reaches the short Puglin")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var puglin := _spawn(PUGLIN, Vector3(0, 0, -1.3), true)
	puglin.health.max_health = 1000
	await ticks(3)
	var log := {"hits": 0}  # (A lambda can't change a captured int.)
	puglin.health.damaged.connect(func(_a: int, _s: Node) -> void: log.hits += 1)
	for swing in 3:
		player.request_attack(false)
		await ticks(40)
	await wait_until(func() -> bool: return not player.melee.is_busy(), 120)
	check(log.hits >= 2, "%d of 3 swings connected" % log.hits)
	await clear_arena()


func test_drops() -> void:
	print("4. A slain imp drops its gold")
	await make_arena()
	var imp := _spawn(IMP, Vector3(0, 0, -4), true)
	await ticks(3)
	imp.health.take_damage(imp.health.current_health)
	await ticks(2)
	var total := 0
	for coin: Pickup in get_nodes_in_group(Pickup.GROUP):
		total += coin.amount
	check(total >= 4 and total <= 7, "%d gold (4-7)" % total)
	await clear_arena()


func test_roster() -> void:
	print("5. The dungeon roster places imps and puglins in levels")
	var seen := {}
	for s in range(1, 30):
		var layout := LevelGenerator.new().generate(s * 977, 2)
		for spawn in layout.spawns:
			seen[(spawn["entry"] as EnemyEntry).display_name] = seen.get((spawn["entry"] as EnemyEntry).display_name, 0) + 1
	print("     enemies over 29 level-2 layouts: %s" % seen)
	check(seen.get("Imp", 0) > 0 and seen.get("Puglin", 0) > 0, "imps and puglins appear")
	check(seen.get("Club Knight", 0) > 0, "knights still appear")


## A monster facing the origin; `passive` = never notices anyone.
func _spawn(scene: PackedScene, at: Vector3, passive: bool) -> EnemyController:
	var monster: EnemyController = scene.instantiate()
	if passive:
		var stats: EnemyStats = monster.stats.duplicate()
		stats.detection_radius = 0.0
		stats.lose_interest_radius = 0.01
		monster.stats = stats
	monster.position = at
	monster.rotation.y = atan2(at.x, at.z)
	world.add_child(monster)
	return monster
