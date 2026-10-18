extends SceneTree
## Headless checks of boss floors (step 6 of procedural levels): which levels
## are boss floors, the approach + arena layout, the boss and escorts in it,
## elite scaling of the knight, the sealed gate, and the HUD's boss bar.
##   godot --headless --path . -s res://tests/boss_test.gd
## Exit code 0 = every check passed.

const MAIN := preload("res://scenes/main/main.tscn")
const KNIGHT := preload("res://scenes/enemies/enemy_knight.tscn")

var failures: int = 0


func check(condition: bool, message: String) -> void:
	print(("  PASS " if condition else "  FAIL ") + message)
	if not condition:
		failures += 1


func _initialize() -> void:
	await process_frame
	test_floor_kinds()
	test_layouts()
	await test_elite()
	await test_real_build()
	await test_main_boss_floor()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_floor_kinds() -> void:
	print("1. Boss every 5th level, chapter boss on each chapter's last")
	var kinds := {}
	for n in range(1, 31):
		kinds[n] = GameRun.floor_kind(n)
	var bosses := kinds.keys().filter(func(n: int) -> bool: return kinds[n] == GameRun.FLOOR_BOSS)
	var chapters := kinds.keys().filter(func(n: int) -> bool: return kinds[n] == GameRun.FLOOR_CHAPTER_BOSS)
	check(bosses == [5, 10, 20, 25], "boss floors 1-30: %s" % [bosses])
	check(chapters == [15, 30], "chapter bosses 1-30: %s" % [chapters])
	check(GameRun.level_title(5) == "Level 5 · Boss" and GameRun.level_title(15) == "Level 15 · Chapter boss"
		and GameRun.level_title(3) == "Level 3", "level titles")


func test_layouts() -> void:
	print("2. Boss floor layouts (40 seeds each)")
	var pool := LevelPool.new()
	pool.scrawl_chance = 1.0  # Boss floors never come from maps.
	for level in [5, 15]:
		var encounter: BossEncounter = pool.boss if level == 5 else pool.chapter_boss
		var bad := {}
		for s in range(1, 41):
			var problem := _check_boss_floor(pool.layout_for(s, level), encounter)
			if problem != "":
				bad[s] = problem
		check(bad.is_empty(), "level %d: all valid (%d bad: %s)" % [level, bad.size(), str(bad).left(300)])
	var a := pool.layout_for(77, 5)
	var b := pool.layout_for(77, 5)
	check(var_to_str(a.props) == var_to_str(b.props) and var_to_str(a.labels) == var_to_str(b.labels)
		and a.spawns.size() == b.spawns.size(), "same seed, same boss floor")
	check(pool.layout_for(77, 4).boss == null and pool.layout_for(77, 6).boss == null, "levels 4 and 6 have no boss")


## "" when `layout` is a sound boss floor for `encounter`, else what's wrong.
func _check_boss_floor(layout: DungeonLayout, encounter: BossEncounter) -> String:
	if layout == null:
		return "no layout"
	if layout.boss != encounter or layout.source != "":
		return "not a generated boss floor"
	var roles := layout.rooms.map(func(r: Dictionary) -> String: return r["role"])
	if roles.count("boss") != 1 or roles.count("exit") != 0 or roles.count("side") != 0:
		return "roles %s" % [roles]
	if layout.rooms.size() < 3 or layout.rooms.size() > 4:
		return "%d rooms (start, 1-2 approach, arena)" % layout.rooms.size()
	var arena := roles.find("boss")
	var rect: Rect2i = layout.rooms[arena]["rect"]
	if rect.size != Vector2i(encounter.arena_size, encounter.arena_size):
		return "arena %s" % rect.size
	var exit: Vector2 = layout.labels.filter(func(l: Array) -> bool: return l[0] == "Exit")[0][1]
	var exit_cell := Vector2i(floori(exit.x), floori(exit.y))
	if not rect.has_point(exit_cell):
		return "gate outside the arena"
	if layout.blocked_cells.has(exit_cell):
		return "a prop on the gate"
	for p: Array in layout.props:
		if Vector2(p[1], p[2]).distance_to(exit) < 1.3:
			return "%s under the gate" % p[0]
	var bosses := layout.spawns.filter(func(s: Dictionary) -> bool: return s.get("boss", false))
	if bosses.size() != 1 or bosses[0]["room"] != arena or bosses[0]["entry"] != encounter.boss:
		return "%d bosses" % bosses.size()
	var boss_at: Vector2 = bosses[0]["cell"]
	if boss_at.distance_to(exit) < 3.0:
		return "the boss stands on the gate"
	var in_arena := layout.spawns.filter(func(s: Dictionary) -> bool: return s["room"] == arena)
	if in_arena.size() != 1 + encounter.escort_count:
		return "%d in the arena (1 boss + %d escorts expected)" % [in_arena.size(), encounter.escort_count]
	for s in in_arena:
		if not s.get("boss", false) and (s["cell"] as Vector2).distance_to(boss_at) < 2.5:
			return "an escort on top of the boss"
	return ""


func test_elite() -> void:
	print("3. Elite scaling of the knight")
	var entry: EnemyEntry = (load(LevelPool.BOSS) as BossEncounter).boss
	var boss := KNIGHT.instantiate() as EnemyController
	boss.size_scale = entry.size_scale
	boss.health_scale = entry.health_scale
	boss.damage_scale = entry.damage_scale
	boss.poise_scale = entry.poise_scale
	var regular := KNIGHT.instantiate() as EnemyController
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	ground_shape.shape = BoxShape3D.new()
	(ground_shape.shape as BoxShape3D).size = Vector3(40, 1, 40)
	ground_shape.position = Vector3(0, -0.5, 0)
	ground.add_child(ground_shape)
	root.add_child(ground)
	root.add_child(boss)
	root.add_child(regular)
	regular.position = Vector3(6, 0, 0)
	await physics_frame
	var base: EnemyStats = regular.stats
	check(boss.health.max_health == roundi(base.max_health * entry.health_scale)
		and boss.health.current_health == boss.health.max_health,
		"health ×%.0f: %d" % [entry.health_scale, boss.health.max_health])
	check(regular.health.max_health == base.max_health and base.max_health == 60, "the shared stats are untouched")
	check(is_equal_approx(boss.get_node("Visual").scale.x, entry.size_scale), "model scaled ×%.2f" % entry.size_scale)
	var big := (boss.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	var small := (regular.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	check(is_equal_approx(big.radius, small.radius * entry.size_scale) and big != small,
		"body capsule scaled on its own copy (%.2f vs %.2f)" % [big.radius, small.radius])
	check(boss.melee.damage_scale == entry.damage_scale and regular.melee.damage_scale == 1.0, "damage ×%.1f" % entry.damage_scale)
	check(is_equal_approx(boss.attack_range, boss.weapon.current.enemy_attack_range * entry.size_scale),
		"reach grows with size")
	check(boss.reaction.poise == base.poise * entry.poise_scale, "poise ×%.0f" % entry.poise_scale)
	# A scaled ragdoll must not explode.
	for i in 10:
		await physics_frame
	var died_at := boss.global_position
	boss.health.take_damage(99999)
	for i in 90:
		await physics_frame
	var ragdoll := boss.get_node("Ragdoll") as RagdollComponent
	var bones := ragdoll.get_physical_bones()
	var sane := not bones.is_empty()
	for bone in bones:
		if not bone.global_position.is_finite() or bone.global_position.distance_to(died_at) > 5.0 				or bone.global_position.y < -0.3:
			sane = false
	check(sane, "the boss's ragdoll stays together (%d bones)" % bones.size())
	if not sane:
		for bone in bones:
			print("     %s %s %.2f" % [bone.name, bone.global_position, bone.global_position.distance_to(died_at)])
	boss.queue_free()
	regular.queue_free()
	ground.queue_free()
	await process_frame


func test_real_build() -> void:
	print("4. A real chapter-boss floor: paths to the boss and the gate")
	var pool := LevelPool.new()
	var layout := pool.layout_for(4242, 15)
	var level := DungeonLevel.new()
	root.add_child(level)
	level.build(layout, "Boss")
	await level.navigation_ready
	check(level.level.get_node_or_null("NavigationRegion3D/ExitGate") != null, "the gate is built")
	var map := level.get_world_3d().navigation_map
	var start := level.get_marker("Start").global_position + Vector3.UP * 0.5
	var unreachable := 0
	var targets: Array[Vector3] = [level.get_marker("Exit").global_position + Vector3.UP * 0.5]
	for spawn in layout.spawns:
		targets.append(layout.to_world(spawn["cell"], DungeonBuilder.CELL) + Vector3.UP * 0.5)
	for at in targets:
		var path := NavigationServer3D.map_get_path(map, start, at, true)
		if path.is_empty() or path[-1].distance_to(at) > 1.0:
			unreachable += 1
	check(unreachable == 0, "gate and all %d enemies reachable from the start" % layout.spawns.size())
	level.queue_free()
	await process_frame


func test_main_boss_floor() -> void:
	print("5. Main: sealed gate, boss bar, the gate opens when the boss dies")
	GameRun.current().start_new_run(55)
	GameRun.current().jump_to(5)
	var main = MAIN.instantiate()
	main.start_run_on_ready = false
	root.add_child(main)
	await process_frame
	var spawned := [null]
	main.boss_spawned.connect(func(b: EnemyController, _title: String) -> void: spawned[0] = b)
	var layout: DungeonLayout = await main.generate_level(GameRun.current().level_seed(), 5)
	check(layout != null and layout.boss != null, "level 5 is a boss floor")
	var boss: EnemyController = main.boss
	check(boss != null and spawned[0] == boss and boss.is_elite(), "the boss is spawned and announced")
	var gate: ExitGate = main.gate
	check(gate != null and gate.sealed, "the gate is sealed")
	var hud: HUD = main.hud
	check(not hud.is_boss_bar_shown(), "no boss bar before the fight")
	var player: PlayerController = main.player
	gate._on_body_entered(player)
	check(not gate.is_used(), "a sealed gate lets nobody through")
	# Walk up to the boss: it notices and the bar fades in.
	var to_player := boss.global_position.direction_to(gate.global_position)
	player.global_position = boss.global_position + Vector3(to_player.x, 0, to_player.z) * 4.0
	for i in 20:
		await physics_frame
	check(boss.state != EnemyController.State.IDLE, "the boss engages")
	check(hud.is_boss_bar_shown(), "the boss bar is shown")
	boss.health.take_damage(99999)
	await process_frame
	check(not gate.sealed, "the boss died: the gate opens")
	player.global_position = gate.global_position
	for i in 40:
		await physics_frame
		if gate.is_used():
			break
	check(gate.is_used() and GameRun.current().level == 6, "through the gate to level 6")
	main.queue_free()
	await process_frame
