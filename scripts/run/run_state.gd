class_name GameRun
extends Node
## The current run (autoload "RunState"): which level the player is on, the
## run's seed, and what carries from one level to the next. Lives across
## level swaps and scene reloads; Main reads it to build each level.
##
## Reach it with GameRun.current(): the autoload's global name is not
## available to scripts compiled when a script is the main loop (`-s`, the
## test suites), the node itself is.
##
## A level's seed is derived from the run seed and the level number, so a
## run can be replayed level by level from its seed.

## The level number changed (a new run, or the gate to the next level).
signal level_changed(level: int)

## Levels per chapter; boss floors every `boss_every` levels (step 6).
const LEVELS_PER_CHAPTER := 15
const BOSS_EVERY := 5

var run_seed: int = 0
## 1-based, counted across chapters.
var level: int = 1
## True once a run has started (Main starts one if not).
var active: bool = false
## Player health carried into the next level; -1 = full.
var player_health: int = -1


## The autoload instance (null outside a running tree).
static func current() -> GameRun:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"RunState") as GameRun if tree else null


## Starts a run at level 1 (`new_seed` 0 = random).
func start_new_run(new_seed: int = 0) -> void:
	run_seed = new_seed if new_seed != 0 else randi_range(1, 2_000_000_000)
	level = 1
	player_health = -1
	active = true
	level_changed.emit(level)


## Moves on to the next level, carrying the player's current health.
func advance(health_now: int) -> void:
	player_health = health_now
	level += 1
	level_changed.emit(level)


## Debug: makes `to_level` the current level of the run (starting one if
## needed), without the gate.
func jump_to(to_level: int) -> void:
	if not active:
		start_new_run()
	level = maxi(1, to_level)
	level_changed.emit(level)


## The seed of `for_level` (default: the current level) in this run.
func level_seed(for_level: int = -1) -> int:
	var n := level if for_level < 0 else for_level
	return absi(hash([run_seed, n])) % 1_000_000_000 + 1


func chapter() -> int:
	return (level - 1) / LEVELS_PER_CHAPTER + 1


## Level within the chapter, 1..LEVELS_PER_CHAPTER.
func level_in_chapter() -> int:
	return (level - 1) % LEVELS_PER_CHAPTER + 1


func is_boss_level() -> bool:
	return level_in_chapter() % BOSS_EVERY == 0
