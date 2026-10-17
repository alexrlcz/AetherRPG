class_name Dungeon01Layout
extends RefCounted
## The first dungeon: the Dungeon Scrawl map assets/maps/dungeon_01.ds
## (floor, walls, doors, "Start" / "BossRoom" labels) plus its hand-placed
## props. tools/build_dungeon.gd saves it as scenes/world/dungeon_01.tscn;
## DungeonBuilder can also build it at runtime.

const SOURCE := "res://assets/maps/dungeon_01.ds"

## kind, cell x, cell y, yaw degrees (DungeonLayout.props; kinds: DungeonBuilder).
const PROPS := [
	# North room and corridor
	["chest", 4.5, 0.55, 0],
	["barrel", 6.4, 1.5, 0],
	["barrel", 6.35, 2.25, 0],
	["rubble", 2.7, 4.2, 20],
	["spike_trap", 4.5, 8.0, 0],
	# West hall
	["pillar", 2.0, 14.0, 0],
	["pillar", 7.0, 14.0, 0],
	["crate", 0.6, 11.6, 10],
	["crate", 1.55, 11.55, -5],
	["crate", 0.6, 12.5, 30],
	["barrel", 8.4, 16.4, 0],
	["barrel", 7.7, 16.5, 0],
	["barrel", 8.4, 15.7, 0],
	# Start room
	["campfire", 3.2, 25.0, 0],
	["bedroll", 6.0, 25.3, 90],
	["crate", 1.5, 21.6, 15],
	["barrel", 6.87, 21.61, 0],
	# Central hall
	["statue", 15.0, 10.9, 0],
	["pillar", 12.8, 13.2, 0],
	["pillar", 17.2, 13.2, 0],
	["pillar", 12.8, 15.8, 0],
	["pillar", 17.2, 15.8, 0],
	# East room
	["crate", 28.3, 12.4, 5],
	["crate", 28.3, 13.35, -10],
	["crate", 27.35, 12.4, 20],
	["barrel", 23.0, 16.0, 0],
	["barrel", 23.8, 16.3, 0],
	["table", 25.5, 14.5, 0],
	["rubble", 27.8, 16.0, 75],
	# South corridor and hall
	["rubble", 16.3, 20.2, 40],
	["pillar", 13.0, 24.0, 0],
	["pillar", 18.0, 24.0, 0],
	["pillar", 13.0, 26.5, 0],
	["pillar", 18.0, 26.5, 0],
	["barrel", 11.5, 27.4, 0],
	# South-east room
	["table", 25.0, 24.0, 90],
	["crate", 27.3, 21.7, 0],
	["crate", 27.3, 22.65, 12],
	["barrel", 22.7, 28.3, 0],
	["barrel", 23.5, 28.4, 0],
	["rubble", 26.8, 27.6, -30],
	# Boss room
	["carpet", 15.5, 34.2, 0],
	["pillar", 13.2, 32.0, 0],
	["pillar", 17.8, 32.0, 0],
	["pillar", 13.2, 35.0, 0],
	["pillar", 17.8, 35.0, 0],
	["brazier", 14.0, 37.6, 0],
	["brazier", 17.0, 37.6, 0],
	["throne", 15.5, 38.4, 0],
]


## The layout, or null if the map can't be read.
static func create() -> DungeonLayout:
	var layout := DungeonLayout.from_dungeon_scrawl(SOURCE)
	if layout:
		layout.props = PROPS.duplicate(true)
	return layout
