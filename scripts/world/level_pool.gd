class_name LevelPool
extends RefCounted
## Decides what each run level is built from (step 5 of procedural levels):
## a generated layout, or one of the hand-made Dungeon Scrawl maps in
## MAPS_DIR. A map is chosen for `scrawl_chance` of levels, decided by the
## level seed, so a run replays the same. Maps get their rooms found
## (RoomAnalysis) and the same props and enemy rules as generated levels.
##
## Adding a map: draw it in Dungeon Scrawl on its grid, put a text label
## "start" where the player begins (optionally "exit" for the gate; without
## one the gate goes in the room furthest from the start), export the .ds
## into MAPS_DIR. Interior walls drawn as the template's polylines block
## walking; door assets become door frames.
##
## Boss floors (GameRun.floor_kind(): every 5th level, and each chapter's
## last) are never maps: they are LevelGenerator.generate_boss() floors with
## `boss` or `chapter_boss`, or the encounter `level_bosses` names for that
## level (level 5: the mutant).

const MAPS_DIR := "res://assets/maps/"
const BOSS := "res://resources/encounters/warden_boss.tres"
const CHAPTER_BOSS := "res://resources/encounters/chapter_boss.tres"
const MUTANT_BOSS := "res://resources/encounters/mutant_boss.tres"

## Share of levels built from a hand-made map (when there is one).
var scrawl_chance: float = 0.3
## The maps to choose from (default: every .ds in MAPS_DIR).
var maps: PackedStringArray = map_paths()
## Enemies to choose from (null = LevelGenerator.DEFAULT_ROSTER).
var roster: EnemyRoster
## The fights of boss floors and of chapter ends.
var boss: BossEncounter = load(BOSS)
var chapter_boss: BossEncounter = load(CHAPTER_BOSS)
## Run level -> the boss fight of that level, instead of `boss`.
var level_bosses: Dictionary = {5: load(MUTANT_BOSS)}


## Every .ds map in `dir`, sorted.
static func map_paths(dir: String = MAPS_DIR) -> PackedStringArray:
	var result := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.get_extension().to_lower() == "ds":
			result.append(dir.path_join(file))
	result.sort()
	return result


## The layout for run level `level` with seed `level_seed`.
func layout_for(level_seed: int, level: int) -> DungeonLayout:
	match GameRun.floor_kind(level):
		GameRun.FLOOR_BOSS:
			return _generator().generate_boss(level_seed, level, level_bosses.get(level, boss))
		GameRun.FLOOR_CHAPTER_BOSS:
			return _generator().generate_boss(level_seed, level, chapter_boss)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([level_seed, "pool"])
	if not maps.is_empty() and rng.randf() < scrawl_chance:
		var path := maps[rng.randi_range(0, maps.size() - 1)]
		var layout := map_layout(path, level_seed, level, roster)
		if layout:
			return layout
		push_warning("LevelPool: %s can't be used as a level; generating one instead" % path)
	return _generator().generate(level_seed, level)


func _generator() -> LevelGenerator:
	var generator := LevelGenerator.new()
	generator.roster = roster
	return generator


## A hand-made map as a level: rooms found, start / exit set, props and
## enemies placed with `level_seed` for `level`. Null if the map is unusable.
static func map_layout(path: String, level_seed: int, level: int,
		map_roster: EnemyRoster = null) -> DungeonLayout:
	var layout := DungeonLayout.from_dungeon_scrawl(path)
	if layout == null or not RoomAnalysis.new().analyze(layout):
		return null
	layout.source = path
	layout.seed = level_seed
	layout.level = level
	PropScatter.new().populate(layout)
	EncounterPlanner.new().populate(layout,
		map_roster if map_roster else load(LevelGenerator.DEFAULT_ROSTER))
	return layout
