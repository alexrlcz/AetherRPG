extends Node3D
## Top-level game flow: runs the current run (RunState) one generated level at
## a time. On start it builds the run's level; the level's exit gate fades to
## the next one; after the player dies, "restart" begins a new run.
## The debug menu can also generate any seed / level in place.

## A level replaced the previous one: the player stands at its start, its
## enemies and its exit gate are in place.
signal level_generated(layout: DungeonLayout)
## A boss floor's boss was spawned (its exit gate stays sealed until the boss
## dies).
signal boss_spawned(boss: EnemyController, title: String)

@export var player: PlayerController
## The current level node (replaced by generate_level()).
@export var dungeon: Node3D
## Holds the level's enemies (replaced with each level).
@export var enemies: Node3D
## Hides level swaps.
@export var fade: LevelFade
## Shows the boss health bar (optional).
@export var hud: HUD
## Build the run's current level on start (off for scenes that bring their
## own level).
@export var start_run_on_ready: bool = true
## Seconds after death before "restart" is accepted (avoids accidental skips).
@export var restart_delay: float = 1.0

## The level being played (null until the first one is built).
var layout: DungeonLayout
var gate: ExitGate
## The current boss floor's boss (null on other levels).
var boss: EnemyController
## True while a level is being built.
var loading: bool = false

var _restart_allowed_at: float = INF
## Each generate_level() call takes a number; an older call that finds a newer
## one has started gives up (only the newest level is kept).
var _generation: int = 0


func _ready() -> void:
	player.health.died.connect(_on_player_died)
	if hud:
		boss_spawned.connect(hud.show_boss)
	if start_run_on_ready:
		if not GameRun.current().active:
			GameRun.current().start_new_run()
		_start_run_level.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and can_restart():
		restart()


func can_restart() -> bool:
	return player.is_dead and _now() >= _restart_allowed_at


## Starts a new run from level 1 (the scene reloads with a fresh player).
func restart() -> void:
	GameRun.current().start_new_run()
	get_tree().reload_current_scene()


## Builds the run's current level (RunState level and seed): generated, or
## one of the hand-made maps (LevelPool).
func load_run_level() -> DungeonLayout:
	var run := GameRun.current()
	return await play_layout(LevelPool.new().layout_for(run.level_seed(), run.level))


## Plays a hand-made map (a .ds path) as a level, populated with `level_seed`
## for `level_number` (debug menu).
func play_map(path: String, level_seed: int, level_number: int = 1) -> DungeonLayout:
	return await play_layout(LevelPool.map_layout(path, level_seed, level_number))


## Replaces the dungeon with a level generated from `level_seed` for
## `level_number` (enemy budget; a boss floor on boss levels, never a map).
## See play_layout().
func generate_level(level_seed: int, level_number: int = 1) -> DungeonLayout:
	var pool := LevelPool.new()
	pool.scrawl_chance = 0.0
	return await play_layout(pool.layout_for(level_seed, level_number))


## Replaces the dungeon with `new_layout`, moves the player to its start, and
## once the navmesh is in use spawns the level's enemies (in place of the old
## ones) and connects its exit gate. Returns the layout, or null if it is null
## or a newer call replaced this level meanwhile.
func play_layout(new_layout: DungeonLayout) -> DungeonLayout:
	_generation += 1
	var ticket := _generation
	if new_layout == null:
		return null
	loading = true
	var index := dungeon.get_index() if dungeon else 0
	if dungeon:
		remove_child(dungeon)
		dungeon.queue_free()
	gate = null
	boss = null
	if enemies:
		for enemy in enemies.get_children():
			enemy.queue_free()
	var level := DungeonLevel.new()
	level.name = "Dungeon"
	level.add_to_group(DropComponent.CONTAINER_GROUP)  # Loot is freed with its level.
	add_child(level)
	move_child(level, index)
	dungeon = level
	layout = new_layout
	level.build(new_layout, "Level%d" % new_layout.seed)
	# The floor's colliders exist now; only the navmesh is still baking.
	_place_player(level.get_marker("Start").global_position)
	await level.navigation_ready
	if ticket != _generation:
		return null  # A newer level took over while this one baked.
	_spawn_enemies(new_layout)
	_connect_gate(level)
	if boss:
		if gate:
			gate.sealed = true
			boss.health.died.connect(gate.unseal)
		boss_spawned.emit(boss, new_layout.boss.title if new_layout.boss else boss.stats.display_name)
	loading = false
	level_generated.emit(new_layout)
	return new_layout


func _start_run_level() -> void:
	if fade:
		fade.cover_now(GameRun.level_title(GameRun.current().level))
	await load_run_level()
	if fade:
		await fade.reveal()


func _on_gate_entered() -> void:
	if loading or player.is_dead:
		return
	GameRun.current().advance(player.health.current_health)
	if fade:
		await fade.cover(GameRun.level_title(GameRun.current().level))
	await load_run_level()
	if fade:
		await fade.reveal()


## The builder put the gate on the Exit label; listen to it.
func _connect_gate(level: DungeonLevel) -> void:
	gate = level.level.get_node_or_null("NavigationRegion3D/ExitGate") as ExitGate
	if gate:
		gate.player_entered.connect(_on_gate_entered)


func _spawn_enemies(for_layout: DungeonLayout) -> void:
	if enemies == null:
		return
	for i in for_layout.spawns.size():
		var spawn := for_layout.spawns[i]
		var entry: EnemyEntry = spawn["entry"]
		var enemy := entry.scene.instantiate() as Node3D
		var drops := enemy.get_node_or_null("Drops") as DropComponent
		if drops:
			if entry.loot:
				drops.loot = entry.loot
			drops.level = for_layout.level
			drops.rng_seed = hash([for_layout.seed, for_layout.level, i, "drops"])
		var weapon := enemy.get_node_or_null("Weapon") as WeaponComponent
		if weapon and entry.weapon:
			weapon.random_weapons = []
			weapon.weapon = entry.weapon
		var controller := enemy as EnemyController
		if controller:
			controller.size_scale = entry.size_scale
			controller.health_scale = entry.health_scale
			controller.damage_scale = entry.damage_scale
			controller.poise_scale = entry.poise_scale
			if spawn.get("boss", false):
				boss = controller
		# Before add_child: enemies take their home and facing in _ready().
		enemy.position = enemies.to_local(for_layout.to_world(spawn["cell"], DungeonBuilder.CELL))
		enemy.rotation.y = deg_to_rad(spawn["yaw"])
		enemies.add_child(enemy)


func _place_player(at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	if player.lock_on:
		player.lock_on.release()
	var rig := get_tree().get_first_node_in_group(IsoCameraRig.GROUP) as IsoCameraRig
	if rig:
		rig.set_target(player)  # Snap the camera instead of gliding across.


func _on_player_died() -> void:
	_restart_allowed_at = _now() + restart_delay


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
