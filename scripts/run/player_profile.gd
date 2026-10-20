class_name PlayerProfile
extends Node
## What the player keeps across runs and play sessions (autoload "Profile"):
## gold now, the inventory later. Saved to `save_path` as JSON on every
## change and loaded on start. Unlike RunState, nothing here resets on
## death or a new run.
##
## Reach it with PlayerProfile.current() (see GameRun.current() for why).

signal gold_changed(total: int, delta: int)

const VERSION := 1

## Where the profile is saved; "" = don't save or load (set automatically
## under test suites and tools).
var save_path: String = "user://profile.json"
var gold: int = 0


## The autoload instance (null outside a running tree).
static func current() -> PlayerProfile:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"Profile") as PlayerProfile if tree else null


func _ready() -> void:
	# Test suites and tools run a script as the main loop (-s): the autoload
	# then never touches the real save.
	if self == PlayerProfile.current() and Engine.get_main_loop().get_script() != null:
		save_path = ""
	load_profile()


## Adds (or with a negative `amount`, spends) gold; never below 0.
func add_gold(amount: int) -> void:
	var before := gold
	gold = maxi(gold + amount, 0)
	if gold != before:
		gold_changed.emit(gold, gold - before)
		save_profile()


func save_profile() -> void:
	if save_path == "":
		return
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("PlayerProfile: cannot write %s (%s)" % [save_path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify({"version": VERSION, "gold": gold}))


## Reads `save_path`; a missing file is a fresh profile.
func load_profile() -> void:
	if save_path == "" or not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary:
		push_error("PlayerProfile: %s is not a profile; starting fresh" % save_path)
		return
	gold = maxi(int(data.get("gold", 0)), 0)
	gold_changed.emit(gold, 0)
