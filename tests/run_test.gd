extends SceneTree
## Headless checks of the run flow (step 4 of procedural levels): RunState,
## the game starting on generated level 1, the exit gate taking the player to
## the next level with health carried, and overlapping level requests.
##   godot --headless --path . -s res://tests/run_test.gd
## Exit code 0 = every check passed.

const MAIN := preload("res://scenes/main/main.tscn")

var failures: int = 0
var run_state: GameRun


func check(condition: bool, message: String) -> void:
	print(("  PASS " if condition else "  FAIL ") + message)
	if not condition:
		failures += 1


func _initialize() -> void:
	await process_frame
	run_state = GameRun.current()
	test_run_state()
	await test_start_and_gate()
	await test_overlapping_requests()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_run_state() -> void:
	print("1. RunState: levels, seeds, chapters, boss floors")
	run_state.start_new_run(777)
	check(run_state.active and run_state.level == 1 and run_state.player_health == -1, "a new run starts at level 1, full health")
	var s1: int = run_state.level_seed(1)
	var s2: int = run_state.level_seed(2)
	check(s1 != s2 and s1 > 0, "levels get different seeds (%d, %d)" % [s1, s2])
	run_state.start_new_run(777)
	check(run_state.level_seed(2) == s2, "the same run seed gives the same level seeds")
	run_state.advance(63)
	check(run_state.level == 2 and run_state.player_health == 63, "advance: level 2, health 63 carried")
	run_state.jump_to(5)
	check(run_state.is_boss_level() and run_state.chapter() == 1, "level 5 is a boss floor in chapter 1")
	run_state.jump_to(16)
	check(run_state.chapter() == 2 and run_state.level_in_chapter() == 1, "level 16 = chapter 2, level 1")


func test_start_and_gate() -> void:
	print("2. The game starts on level 1; the gate leads to level 2")
	run_state.start_new_run(4242)
	var main = MAIN.instantiate()
	root.add_child(main)
	var ready := await _wait_for_level(main)
	check(ready, "level 1 built")
	var layout: DungeonLayout = main.layout
	check(layout != null and layout.seed == run_state.level_seed(1) and layout.level == 1,
		"it is the run's level 1 (seed %d)" % (layout.seed if layout else -1))
	var gate: ExitGate = main.gate
	var exit := (main.dungeon as DungeonLevel).get_marker("Exit")
	check(gate != null and gate.global_position.distance_to(exit.global_position) < 0.01, "the exit gate stands on the Exit marker")
	var nearest_enemy := INF
	for e in _alive(main.get_node("Enemies")):
		nearest_enemy = minf(nearest_enemy, EnemyController._flat((e as Node3D).global_position - gate.global_position).length())
	check(nearest_enemy > 4.0, "no enemy at the gate (nearest %.1f m)" % nearest_enemy)
	var map: RID = (main.dungeon as Node3D).get_world_3d().navigation_map
	var pillar := gate.global_position + gate.global_basis.x * 1.45 + Vector3.UP * 0.5
	var on_mesh := NavigationServer3D.map_get_closest_point(map, pillar)
	check(EnemyController._flat(on_mesh - pillar).length() > 0.5, "the gate's pillars are holes in the navmesh")
	var alive := _alive(main.get_node("Enemies"))
	check(alive.size() == layout.spawns.size(), "%d enemies spawned (%d planned)" % [alive.size(), layout.spawns.size()])
	var hud_label := main.get_node("HUD").get_node("%LevelLabel") as Label
	check(hud_label.text == "Level 1", "HUD shows %s" % hud_label.text)
	# Enemies never trigger the gate.
	var knight := alive[0] as Node3D
	var knight_home := knight.global_position
	knight.global_position = gate.global_position
	for i in 45:
		await physics_frame
	check(run_state.level == 1 and not gate.is_used(), "a knight in the gate does nothing")
	knight.global_position = knight_home
	# The player steps in, hurt: level 2 loads, health carried.
	var player := main.get_node("Player") as PlayerController
	player.health.take_damage(37)
	var hp := player.health.current_health
	player.global_position = gate.global_position + Vector3.UP * 0.1
	ready = await _wait_for(func() -> bool: return run_state.level == 2 and main.layout != layout and not main.loading, 600)
	check(ready, "entering the gate loads level 2")
	var layout2: DungeonLayout = main.layout
	check(layout2.seed == run_state.level_seed(2) and layout2.level == 2, "it is the run's level 2")
	var start := (main.dungeon as DungeonLevel).get_marker("Start").global_position
	check(EnemyController._flat(player.global_position - start).length() < 0.6, "the player stands at level 2's start")
	check(player.health.current_health == hp and run_state.player_health == hp, "health carried (%d)" % player.health.current_health)
	check(main.gate != null and main.gate != gate and not main.gate.is_used(), "a fresh gate on level 2")
	check(_alive(main.get_node("Enemies")).size() == layout2.spawns.size(), "level 2's enemies replaced level 1's")
	check(hud_label.text == "Level 2", "HUD shows %s" % hud_label.text)
	await _wait_for(func() -> bool: return not (main.fade as LevelFade).is_covered(), 120)
	check(not (main.fade as LevelFade).is_covered(), "the fade lifts")
	main.queue_free()
	await process_frame


func test_overlapping_requests() -> void:
	print("3. Overlapping level requests: only the newest is kept")
	run_state.start_new_run(99)
	var main = MAIN.instantiate()
	main.start_run_on_ready = false
	root.add_child(main)
	await process_frame
	# Lambdas capture locals by value: results go in an array.
	var results := [null, null]
	var done := [0]
	(func() -> void:
		results[0] = await main.generate_level(111, 1)
		done[0] += 1).call()
	(func() -> void:
		results[1] = await main.generate_level(222, 1)
		done[0] += 1).call()
	await _wait_for(func() -> bool: return done[0] >= 1 and not main.loading, 300)
	for i in 10:
		await physics_frame
	check(results[1] != null and (results[1] as DungeonLayout).seed == 222, "the newer request finished")
	check(results[0] == null, "the older one gave up")
	check(main.layout.seed == 222 and main.get_node("Dungeon") == main.dungeon, "one level in the scene, seed 222")
	var levels := main.get_children().filter(func(n: Node) -> bool: return n is DungeonLevel and not n.is_queued_for_deletion())
	check(levels.size() == 1, "%d level node(s)" % levels.size())
	main.queue_free()
	await process_frame


func _wait_for_level(main) -> bool:
	return await _wait_for(func() -> bool: return main.layout != null and not main.loading and main.gate != null, 600)


func _wait_for(condition: Callable, frames: int) -> bool:
	for i in frames:
		if condition.call():
			return true
		await physics_frame
	return condition.call()


func _alive(container: Node) -> Array:
	return container.get_children().filter(func(e: Node) -> bool: return not e.is_queued_for_deletion())
